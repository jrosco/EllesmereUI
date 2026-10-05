-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("ui-locks")
local api, rows, np, checks = f.api, f.rows, EllesmereNameplates_NS, 0
local function Check(value, label) checks = checks + 1; assert(value, label) end
np.TARGET_ARROW_DIR = "Arrows/"
np.TARGET_ARROW_STYLES = {
    simple = { l = "simple-left", r = "simple-right", w = 11, label = "Simple Arrows" },
    double = { l = "double-left", r = "double-right", w = 22, label = "Double Arrows" },
    winged = { l = "winged-left", r = "winged-right", w = 28, label = "Winged" },
}
np.db = { profile = { targetArrowStyle = "double", showTargetArrows = false } }
function np.ResolveTargetArrowStyle(profile) return np.TARGET_ARROW_STYLES[profile.targetArrowStyle] end
function np.GetTargetArrowColor() return 0.2, 0.6, 0.9 end
EllesmereUI:RefreshPage()
local first = api.GetRules()[1]
Check(rows["Override target arrows"].get() == false, "existing rules leave target-arrow override off")
Check(rows["Target-arrow style"].disabled(), "style selector requires override")
rows["Override target arrows"].set(true); f.Flush()
local selector = rows["Target-arrow style"]
Check(not selector.disabled(), "enabling override unlocks style selector")
Check(selector.values.eui and selector.values.simple and selector.values.double and selector.values.winged, "style choices supplied by EUI")
Check(selector.values._menuOpts.icon("winged") == "Arrows/winged-left.png", "dropdown style thumbnail")
rows["Target-arrow style"].set("winged"); f.Flush()
Check(first.style.targetArrowStyle == "winged" and first.style.targetArrowsEnabled, "style setter stores rule appearance")
Check(rows["Target-arrow preview"] == nil, "inline arrow preview replaced by combined hero")
local sample = f.GetPreview().arrows
Check(sample.left:GetTexture() == "Arrows/winged-left.png" and sample.right:GetTexture() == "Arrows/winged-right.png", "preview updates with style")
Check(sample.left.width == 28 and sample.right.width == 28, "preview preserves native arrow aspect ratio")
rows["Target-arrow style"].set("eui")
Check(sample.left:GetTexture() == "Arrows/double-left.png", "EUI-style preview resolves profile choice")
rows["Target-arrow style"].set("winged")
local code = assert(api.ExportRuleSet())
rows["Override target arrows"].set(false)
Check(api.ImportRuleSet(code), "target-arrow rules import")
EllesmereUI:RefreshPage()
first = api.GetRules()[1]
Check(first.style.targetArrowsEnabled and first.style.targetArrowStyle == "winged", "target-arrow sharing roundtrip")
local oldStyle = rows["Target-arrow style"].set
rows["Rule enabled"].set(false)
oldStyle("simple")
Check(first.style.targetArrowStyle == "winged" and rows["Target-arrow style"].disabled(), "disabled rule blocks stale style callback")
rows["Rule enabled"].set(true)
local oldToggle = rows["Override target arrows"].set
rows["Enable rule styling"].set(false)
oldToggle(false)
Check(first.style.targetArrowsEnabled, "global lock blocks stale override callback")
rows["Enable rule styling"].set(true)

for _, invalid in ipairs({ "missing", "../arrow", 42, true, {} }) do
    first.style.targetArrowStyle = invalid
    local result, reason = api.ExportRuleSet()
    Check(not result and reason:find("target%-arrow"), "malformed/unknown arrow styles rejected")
end
first.style.targetArrowStyle = "simple"
first.style.targetArrowsEnabled = "true"
local result, reason = api.ExportRuleSet()
Check(not result and reason:find("targetArrowsEnabled", 1, true), "malformed enable flag rejected")
first.style.targetArrowsEnabled = true
code = assert(api.ExportRuleSet())
local serializer = EllesmereUI._Serializer
local payload = serializer.Deserialize(code:sub(18))
payload.rules[1].style.targetArrowStyle = "unknown"
local before = api.GetRules()
Check(not api.ImportRuleSet("!EUI_NPEX_RULES2!" .. serializer.Serialize(payload)) and api.GetRules() == before,
    "bad imported arrow style rejected atomically")
payload.rules[1].style.targetArrowStyle, payload.rules[1].style.targetArrowsEnabled = nil, nil
Check(api.ImportRuleSet("!EUI_NPEX_RULES2!" .. serializer.Serialize(payload)) and api.GetRules()[1].style.targetArrowsEnabled == nil,
    "older codes without arrows preserve EUI behavior")
print("PASS: " .. checks .. " target-arrow editor, style preview, sharing validation, backward compatibility and stale locks")
