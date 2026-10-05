-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("ui-locks")
local api, rows, checks = f.api, f.rows, 0
local function Check(value, label) checks = checks + 1; assert(value, label) end
Check(not rows["Override text"].get() and rows["Top text content"].disabled(), "text overrides off by default")
rows["Override text"].set(true); f.Flush()
local rule = api.GetRules()[1]
Check(not rows["Top text content"].disabled(), "text master unlocks content choices")
Check(rows["Top text content"].values.eui and rows["Top text content"].values.none and rows["Top text content"].values.healthMax,
    "health choices include native, hidden and proposed content")
Check(rows["Cast timer text content"].values.castElapsedTotal and not rows["Cast timer text content"].values.healthMax,
    "cast choices scoped to cast text")
rows["Top text content"].set("name")
rows["Left text content"].set("level")
rows["Center text content"].set("healthPercent")
rows["Right text content"].set("healthCurrentMax")
rows["Bottom-left text content"].set("healthMax")
rows["Bottom-right text content"].set("targetOfTarget")
rows["Cast name text content"].set("spellName")
rows["Cast target text content"].set("castTarget")
rows["Cast timer text content"].set("castElapsedTotal")
rows["Override Name color"].set(true)
rows["Name text color"].set(0.2, 0.6, 0.8)
rows["Override Level color"].set(true)
rows["Level text color"].set(0.8, 0.6, 0.2)
local hero = f.GetPreview()
Check(hero.textFonts.textSlotTop.text == "Enemy Name" and hero.textFonts.textSlotRight.text == "6,600 / 8,800", "hero shows selected name/health content")
Check(hero.textFonts.textSlotBottomLeft.text == "8,800" and hero.textFonts.textSlotBottomRight.text == "Target Name", "hero shows bottom-slot content")
Check(hero.textFonts.castName:GetParent() == hero.castTextHost and hero.textFonts.castTimer:GetParent() == hero.castTextHost,
    "replacement preview cast text uses the same raised host as baseline spell text")
Check(hero.castTextHost:GetFrameLevel() > hero.cast._bar:GetFrameLevel(), "replacement spell/time labels render above cast fill")
Check(hero.textFonts.textSlotTop.textColor[1] == 0.2 and hero.textFonts.textSlotLeft.textColor[1] == 0.8, "hero colors independent by element")
hero.scripts.OnUpdate(hero, 1)
Check(hero.textFonts.castTimer.text == "1.0 / 3.0", "hero custom cast timer updates with sample cast")
rows["Top text content"].set("none")
Check(not hero.textFonts.textSlotTop:IsShown(), "None hides selected preview slot")
rows["Top text content"].set("eui")
Check(rule.style.textSlots.textSlotTop == nil, "Use EUI stores no override")
local staleSlot, staleColor = rows["Top text content"].set, rows["Name text color"].set
rows["Rule enabled"].set(false)
staleSlot("healthMax"); staleColor(1, 0, 0)
Check(rule.style.textSlots.textSlotTop == nil and rule.style.textColors.name.r == 0.2, "disabled rule blocks stale text callbacks")
rows["Rule enabled"].set(true)
rows["Enable rule styling"].set(false)
rows["Override text"].set(false)
Check(rule.style.textEnabled, "global lock preserves text enable flag")
rows["Enable rule styling"].set(true)
staleSlot = rows["Top text content"].set
local other = { name = "Other text rule", enabled = true, conditions = {}, style = {} }
for key, value in pairs(rule.style) do other.style[key] = value end
other.style.textSlots, other.style.textColors, other.style.textEnabled = nil, nil, true
api.GetSettings().rules[2] = other
EllesmereUI:RefreshPage()
rows["Edit rule"].set("2")
staleSlot("level")
Check(other.style.textSlots == nil and rule.style.textSlots.textSlotTop == nil, "stale text slot callback cannot edit another selected rule")
rows["Edit rule"].set("1")
local code = assert(api.ExportRuleSet())
Check(api.ImportRuleSet(code), "text rules import")
Check(api.GetRules()[1].style.textSlots.castTimer == "castElapsedTotal" and api.GetRules()[1].style.textColors.level.r == 0.8,
    "content and independent colors sharing roundtrip")
local serializer = EllesmereUI._Serializer
for _, invalid in ipairs({ { textSlots = { unknown = "name" } }, { textSlots = { castTimer = "healthMax" } },
    { textColors = { name = { r = 2, g = 0, b = 0 } } }, { textEnabled = "true" } }) do
    local payload = serializer.Deserialize(code:sub(18))
    for key, value in pairs(invalid) do payload.rules[1].style[key] = value end
    local before = api.GetRules()
    Check(not api.ImportRuleSet("!EUI_NPEX_RULES2!" .. serializer.Serialize(payload)) and api.GetRules() == before,
        "malformed text settings rejected before replacing rules")
end
EllesmereUI:RefreshPage()
rows["Override text"].set(false)
hero = f.GetPreview()
Check(hero.name:IsShown() and (not hero.textFonts.textSlotLeft or not hero.textFonts.textSlotLeft:IsShown()), "text master off restores baseline hero labels")
Check(api.GetRules()[1].style.textColors.name.r == 0.2, "turning override off preserves per-element colors")
f.Flush()
print("PASS: " .. checks .. " text editor defaults/slots/colors, hero content/timers, stale locks and validated sharing")
