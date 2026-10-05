-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("ui-locks")
local api, rows, checks = f.api, f.rows, 0
local G = assert(loadfile("EllesmereUIExtendNameplates/tests/glow-mocks.lua"))()
EllesmereUI.Glows = G
C_Texture = { GetAtlasInfo = function() return {} end }
local function Check(value, label) checks = checks + 1; assert(value, label) end
local function Near(actual, expected, label) Check(math.abs(actual - expected) < 0.00001, label) end
local function Preview(name) local p = assert(f.GetPreview()); return name == "Health" and p.health or p.cast end
local rule = api.GetRules()[1]
rule.style.castEnabled = true
EllesmereUI:RefreshPage()
Check(rows["Health border glow"].get() == 0 and rows["Cast border glow"].get() == 0, "existing rules default to no plugin glows")
Check(rows["Health glow color"].disabled() and rows["Cast glow color"].disabled(), "None disables glow color editing")
for _, name in ipairs({ "Health border glow", "Cast border glow" }) do
    local choices = rows[name].values
    for _, index in ipairs({ 0, 1, 3 }) do Check(choices[index], name .. " offered style " .. index) end
    for _, index in ipairs({ 2, 4, 5, 6, 7, 8 }) do Check(choices[index] == nil, name .. " excludes icon style " .. index) end
end
rows["Health border glow"].set(1); f.Flush()
rows["Cast border glow"].set(3); f.Flush()
Check(rule.style.healthGlowStyle == 1 and rule.style.castGlowStyle == 3, "style selectors save independently")
rows["Health glow color"].set(0.2, 0.6, 0.8)
rows["Cast glow color"].set(0.9, 0.4, 0.2)
local health, cast = Preview("Health"), Preview("Cast")
Check(health._glow._mockGlowSpec.style == 1 and cast._glow._mockGlowSpec.style == 3, "both existing bar previews display glows")
Near(health._glow._mockGlowSpec.r, 0.2, "preview health custom color")
Near(cast._glow._mockGlowSpec.r, 0.9, "preview cast custom color")
Check(health._glow._mockGlowSpec.panel and cast._glow._mockGlowSpec.lowLevel, "Pixel preview uses panel correction; Shine uses size-capable renderer")
Check(health._glow._euiGlowPreview and cast._glow._euiGlowPreview, "UI preview is marked for shared glow renderer")
Check(health._glow:GetParent() == health._appearance, "glow preview inherits bar opacity")
rows["Opacity (%)"].set(45)
Near(health._appearance:GetAlpha(), 0.45, "glow preview keeps whole-bar opacity")

local cog = rows["Health glow settings"]
Check(not cog.disabled() and #cog.rows == 5, "Pixel parameters exposed in inline cog")
local params = {}
for _, row in ipairs(cog.rows) do params[row.label] = row end
params.Lines.set(12); params.Thickness.set(3); params.Speed.set(8)
params.Background.set(true); params["Background Color"].set(0.1, 0.2, 0.3)
Check(rule.style.healthGlowLines == 12 and rule.style.healthGlowThickness == 3 and rule.style.healthGlowSpeed == 1,
    "Pixel sliders use native lines/thickness and UI-speed conversion")
Check(rule.style.healthGlowBackground and rule.style.healthGlowBackgroundColor.b == 0.3, "Pixel background stored independently")
Check(Preview("Health")._glow._mockGlowSpec.lines == 12, "cog updates existing preview immediately")
local castShine = rows["Cast glow settings"]
Check(not castShine.disabled() and #castShine.rows == 1 and castShine.rows[1].label == "Sparkle size (%)",
    "Auto-Cast Shine cog exposes only sparkle sizing")
castShine.rows[1].set(200)
Check(rule.style.castGlowShineSize == 200 and rule.style.healthGlowShineSize == nil, "sparkle size saved independently per bar")
Near(Preview("Cast")._glow._euiAcData.sparkles[1].width, 14, "sparkle sizing updates existing cast preview immediately")
rows["Health border glow"].set(3)
local healthShine = rows["Health glow settings"]
healthShine.rows[1].set(50)
Near(Preview("Health")._glow._euiAcData.sparkles[1].width, 3.5, "health preview supports its own small sparkles")
rows["Cast border glow"].set(1)
castShine.rows[1].set(150)
Check(rule.style.castGlowShineSize == 200, "stale Shine popup cannot change settings after switching to Pixel")
rows["Cast border glow"].set(3)
params.Lines.set(7)
Check(rule.style.healthGlowLines == 12, "old Pixel popup cannot change parameters after style switches")
rows["Health border glow"].set(1)
healthShine.rows[1].set(150)
Check(rule.style.healthGlowShineSize == 50, "health Shine popup guarded after style switch")
f.Flush()
local popup = rows["Health glow settings"]
local before = rule.style.healthGlowLines
rows["Enable rule styling"].set(false)
Check(popup.disabled(), "global lock disables open glow cog")
popup.rows[1].set(16)
Check(rule.style.healthGlowLines == before, "global lock guards stale cog callback")
rows["Enable rule styling"].set(true)
popup = rows["Health glow settings"]
rows["Rule enabled"].set(false)
popup.rows[1].set(16)
Check(rule.style.healthGlowLines == before and rows["Health border glow"].disabled(), "disabled rule guards cog and style inputs")
rows["Rule enabled"].set(true)
popup = rows["Health glow settings"]
local other = {}
for key, value in pairs(rule) do other[key] = value end
other.name, other.style = "Other glow rule", {}
for key, value in pairs(rule.style) do other.style[key] = value end
api.GetSettings().rules[2] = other
EllesmereUI:RefreshPage()
rows["Edit rule"].set("2")
popup.rows[1].set(16)
Check(rule.style.healthGlowLines == before and other.style.healthGlowLines == before, "old popup cannot edit a different selected rule")

-- Hidden previews stop their animations; cached-page OnShow restarts them.
local hero = f.GetPreview()
health = hero.health
hero:Hide()
Check(not health._glow._mockGlowActive, "preview OnHide stops shared glow driver")
health._refresh()
Check(not health._glow._mockGlowActive, "hidden preview refresh does not restart glow")
hero:Show()
Check(health._glow._mockGlowActive, "preview OnShow restarts current style")
rows["Override health bar"].set(false)
Check(not Preview("Health")._glow._mockGlowActive, "health master off removes plugin glow from preview")
rows["Override health bar"].set(true)

local code = assert(api.ExportRuleSet())
Check(api.ImportRuleSet(code), "glow rules import")
local selection = api.GetRules()[2].style
Check(selection.healthGlowStyle == 1 and selection.castGlowStyle == 3 and selection.healthGlowLines == 12
    and selection.healthGlowColor.r == 0.2 and selection.healthGlowBackground
    and selection.healthGlowShineSize == 50 and selection.castGlowShineSize == 200, "independent glow settings and sparkle sizes sharing roundtrip")
local serializer = EllesmereUI._Serializer
local payload = serializer.Deserialize(code:sub(18))
local invalid = { healthGlowStyle = 2, castGlowStyle = 6, healthGlowLines = 1,
    castGlowThickness = 5, healthGlowSpeed = 0, castGlowBackground = "true", healthGlowColor = { r = 2, g = 0, b = 0 } }
invalid.healthGlowShineSize, invalid.castGlowShineSize = 49, 201
for key, value in pairs(invalid) do
    local bad = serializer.Deserialize(code:sub(18))
    bad.rules[1].style[key] = value
    local beforeRules = api.GetRules()
    local ok = api.ImportRuleSet("!EUI_NPEX_RULES2!" .. serializer.Serialize(bad))
    Check(not ok and api.GetRules() == beforeRules, "malformed glow setting rejected atomically: " .. key)
end
for _, r in ipairs(payload.rules) do
    for key in pairs(r.style) do if key:match("^healthGlow") or key:match("^castGlow") then r.style[key] = nil end end
end
Check(api.ImportRuleSet("!EUI_NPEX_RULES2!" .. serializer.Serialize(payload)), "older codes without glow settings still import")
Check(api.GetRules()[2].style.healthGlowStyle == nil and api.GetRules()[2].style.castGlowStyle == nil, "old codes stay glow-free")
print("PASS: " .. checks .. " glow controls, independent previews/colors, Pixel cog, lifecycle, stale locks and validated sharing")
