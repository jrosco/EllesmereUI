-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("ui-locks")
local api, rows, checks = f.api, f.rows, 0
local function Check(value, label) checks = checks + 1; assert(value, label) end
local function Cog() return assert(rows["Nameplate scaling"]) end
local first = api.GetRules()[1]
local all = Cog().rows[1]
Check(Cog().captureRegion == rows["Nameplate size (%)"].row._leftRegion, "cog belongs to size slider rather than opacity")
Check(#Cog().rows == 6, "scale all and five component toggles")
local labels = { ["Scale all"] = true, ["Health bar"] = true, ["Cast bar"] = true,
    ["Class resources"] = true, ["Text"] = true, ["Other elements"] = true }
for _, row in ipairs(Cog().rows) do Check(labels[row.label], "only requested category: " .. row.label) end
Check(all.get(), "old rules default to scale all")
for _, row in ipairs(Cog().rows) do Check(row.get(), "default enabled " .. row.label) end
local cast
for _, row in ipairs(Cog().rows) do if row.label == "Cast bar" then cast = row end end
cast.set(false); f.Flush()
Check(first.style.scaleElements.castBar == false and not all.get(), "individual opt-out stored")
local code = assert(api.ExportRuleSet())
all.set(true); f.Flush()
Check(first.style.scaleElements == nil and all.get(), "scale all uses backward-compatible default")
Check(api.ImportRuleSet(code), "selective scaling imports")
first = api.GetRules()[1]
EllesmereUI:RefreshPage()
Check(first.style.scaleElements.castBar == false, "sharing preserves false rather than treating it as missing")
all = Cog().rows[1]
local text, otherToggle
for _, row in ipairs(Cog().rows) do
    if row.label == "Text" then text = row end
    if row.label == "Other elements" then otherToggle = row end
end
otherToggle.set(false); f.Flush()
Check(text.get() and first.style.scaleElements.text == true, "turning Other off preserves independently enabled Text")
api.NormalizeScaleElements(first.style.scaleElements)
Check(text.get(), "explicit Text-on survives profile normalization beside Other-off")
text.set(false); f.Flush()
otherToggle.set(true); f.Flush()
Check(not text.get() and otherToggle.get(), "turning Other on preserves independently disabled Text")
otherToggle.set(false); text.set(true); f.Flush()
Check(first.style.scaleElements.text == true and first.style.scaleElements.other == false,
    "enabling Text independently persists explicit true")
local textCode = assert(api.ExportRuleSet())
Check(api.ImportRuleSet(textCode) and api.GetRules()[1].style.scaleElements.text == true
    and api.GetRules()[1].style.scaleElements.other == false, "Text-on Other-off sharing roundtrip")
first = api.GetRules()[1]
EllesmereUI:RefreshPage()
all = Cog().rows[1]
all.set(false); f.Flush()
for _, row in ipairs(Cog().rows) do Check(not row.get(), "scale none " .. row.label) end
all.set(true); f.Flush()
for _, row in ipairs(Cog().rows) do Check(row.get(), "scale all " .. row.label) end

local stale = Cog()
rows["Enable rule styling"].set(false); f.Flush()
Check(stale.disabled(), "global off locks cog")
for _, row in ipairs(stale.rows) do
    Check(row.disabled(), "global off locks popup " .. row.label)
    row.set(false)
end
Check(first.style.scaleElements == nil, "open popup cannot write with global styling off")
rows["Enable rule styling"].set(true); f.Flush()
stale = Cog()
rows["Rule enabled"].set(false); f.Flush()
Check(stale.disabled(), "individual rule off locks cog")
for _, row in ipairs(stale.rows) do row.set(false) end
Check(first.style.scaleElements == nil, "open popup cannot write to disabled rule")
rows["Rule enabled"].set(true); f.Flush()
stale = Cog()
rows["Add Rule"].click(); f.Flush()
for _, row in ipairs(stale.rows) do row.set(false) end
Check(first.style.scaleElements == nil and api.GetRules()[1].style.scaleElements == nil,
    "old popup cannot edit a different selected rule")

local current = api.GetRules()[1]
for _, invalid in ipairs({ false, "all", { unknown = true }, { castBar = 1 }, { buffs = "false" } }) do
    current.style.scaleElements = invalid
    local rejected, reason = api.ExportRuleSet()
    Check(not rejected and reason:find("scale-elements", 1, true), "sharing rejects malformed scale selections")
end
current.style.scaleElements = { healthBar = false }
code = assert(api.ExportRuleSet())
local serialize, deserialize = EllesmereUI._Serializer.Serialize, EllesmereUI._Serializer.Deserialize
local payload = deserialize(code:sub(18))
payload.rules[1].style.scaleElements = { healthBar = "false" }
local before = api.GetRules()
local imported, reason = api.ImportRuleSet("!EUI_NPEX_RULES2!" .. serialize(payload))
Check(not imported and reason:find("scale-elements", 1, true) and api.GetRules() == before,
    "bad imports rejected before replacing stored rules")
current.style.scaleElements = nil
code = assert(api.ExportRuleSet())
Check(api.ImportRuleSet(code) and api.IsScaleElementEnabled(api.GetRules()[1].style, "castBar"),
    "legacy missing selection roundtrips as scale all")
for _, other in ipairs({ true, false }) do
    payload = deserialize(code:sub(18))
    payload.rules[1].style.scaleElements = { healthBar = false, buffs = false, debuffs = true, cc = false, other = other }
    Check(api.ImportRuleSet("!EUI_NPEX_RULES2!" .. serialize(payload)), "legacy aura-toggle code remains importable")
    local selection = api.GetRules()[1].style.scaleElements
    Check(selection.healthBar == false and selection.other == other and selection.buffs == nil
        and selection.debuffs == nil and selection.cc == nil, "import keeps Other choice and removes retired aura toggles")
    Check(api.IsScaleElementEnabled(api.GetRules()[1].style, "text") == other,
        "older imported Text inherits the prior Other choice")
    local exported = deserialize(assert(api.ExportRuleSet()):sub(18)).rules[1].style.scaleElements
    Check(exported.other == other and exported.buffs == nil and exported.debuffs == nil and exported.cc == nil,
        "new export contains no retired aura toggles")
end
payload = deserialize(code:sub(18))
payload.rules[1].style.scaleElements = { buffs = false, debuffs = false, cc = false }
Check(api.ImportRuleSet("!EUI_NPEX_RULES2!" .. serialize(payload)) and api.GetRules()[1].style.scaleElements == nil,
    "legacy aura-only opt-outs now use default Other selection")
EllesmereUI:RefreshPage()
stale = Cog()
local oldRule = api.GetRules()[1]
Check(api.CreateProfile("Scaling popup"), "create second profile")
for _, row in ipairs(stale.rows) do row.set(false) end
Check(oldRule.style.scaleElements == nil and api.GetRules()[1].style.scaleElements == nil,
    "open popup cannot edit a different profile")
print("PASS: " .. checks .. " scale cog defaults, selection, sharing validation and stale-popup lock checks")
