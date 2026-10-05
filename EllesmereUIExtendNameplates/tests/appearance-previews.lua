-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("ui-locks")
local api, rows, np = f.api, f.rows, EllesmereNameplates_NS
local checks = 0
local function Check(value, label) checks = checks + 1; assert(value, label) end
local function Near(actual, expected, label)
    Check(math.abs(actual - expected) < 0.00001, label .. ": expected " .. expected .. ", got " .. tostring(actual))
end
local function Preview(kind)
    local preview = assert(f.GetPreview())
    Check(preview:GetParent() == f.header and preview:GetParent() ~= f.parent, "combined preview lives in pinned header, not scroll settings")
    return kind == "Health-bar" and preview.health or preview.cast
end
local function Texture(preview) return preview._bar:GetStatusBarTexture():GetTexture() end
local function Color(preview, r, g, b, label)
    local cr, cg, cb = preview._bar:GetStatusBarColor()
    Near(cr, r, label .. " red"); Near(cg, g, label .. " green"); Near(cb, b, label .. " blue")
end
local function Borders(preview, size, r, g, b, label)
    local rendered = preview._border._testBorder
    Near(rendered.size, size, label .. " renderer size")
    Near(rendered.color[1], r, label .. " red"); Near(rendered.color[2], g, label .. " green"); Near(rendered.color[3], b, label .. " blue")
    Check(rendered.addonKey == "nameplates", label .. " same registered offsets as native nameplates")
end
np.db = { profile = { healthBarTexture = "melli", castBarTexture = "blizzard",
    enemyInCombat = { r = 0.2, g = 0.4, b = 0.6 }, castBar = { r = 0.6, g = 0.4, b = 0.2 },
    borderColor = { r = 0.1, g = 0.1, b = 0.1 }, castBorderSize = 1, castBorderColor = { r = 0.1, g = 0.1, b = 0.1 } } }
local first = api.GetRules()[1]
local style = first.style
style.healthEnabled, style.healthColorEnabled, style.texture = true, true, "flat"
style.healthColor, style.borderColor = { r = 0.9, g = 0.2, b = 0.1 }, { r = 0.3, g = 0.6, b = 0.9 }
style.borderEnabled, style.borderSize, style.opacity = true, 3, 80
style.castEnabled, style.castColorEnabled, style.castTexture = true, true, "melli"
style.castColor, style.castBorderColor = { r = 0.8, g = 0.7, b = 0.2 }, { r = 0.9, g = 0.6, b = 0.3 }
style.castBorderEnabled, style.castBorderSize = true, 2
style.castOpacityEnabled, style.castOpacity = true, 50
EllesmereUI:RefreshPage()
local health, cast = Preview("Health-bar"), Preview("Cast-bar")
Check(health._bar.kind == "StatusBar" and cast._bar.kind == "StatusBar", "native status-bar samples")
Check(health._bar.min == 0 and health._bar.max == 100 and health._bar.value == 75, "health sample has partial fill")
Check(cast._bar.value == 0 and f.GetPreview().scripts.OnUpdate, "cast sample starts an animated repeating cast")
Check(Texture(health) == "Interface\\Buttons\\WHITE8x8" and Texture(cast) == "EUI-Melli", "initial selected textures")
Color(health, 0.9, 0.2, 0.1, "health custom color")
Color(cast, 0.8, 0.7, 0.2, "cast custom color")
Near(health._appearance.alpha, 0.8, "health rule opacity")
Near(cast._appearance.alpha, 0.4, "cast opacity multiplies rule opacity")
Borders(health, 3, 0.3, 0.6, 0.9, "health replacement border")
Borders(cast, 2, 0.9, 0.6, 0.3, "cast replacement border")
for _, key in ipairs({ "solid", "blizz", "glow", "pixels", "sm:Test Border" }) do
    rows["Health border texture"].set(key)
    rows["Cast border texture"].set(key)
    health, cast = Preview("Health-bar"), Preview("Cast-bar")
    Check(health._border._testBorder.texture == key and cast._border._testBorder.texture == key, "live border media preview " .. key)
end
rows["Health border texture"].set("solid"); rows["Cast border texture"].set("solid")
health, cast = Preview("Health-bar"), Preview("Cast-bar")

-- Texture/color/size callbacks update the existing sample immediately, without
-- a full page rebuild or a visible nameplate/cast.
for key, path in pairs({ flat = "Interface\\Buttons\\WHITE8x8", blizzard = "EUI-Blizzard", melli = "EUI-Melli",
    ["sm:Test Texture"] = "SM-Test-Path", ["sm:Missing"] = "Interface\\Buttons\\WHITE8x8" }) do
    rows["Health-bar texture"].set(key)
    rows["Cast-bar texture"].set(key)
    Check(Texture(health) == path and Texture(cast) == path, "live texture selection " .. key)
    Check(Preview("Health-bar") == health and Preview("Cast-bar") == cast, "texture change retains preview frames")
end
rows["Health-bar texture"].set("eui")
rows["Cast-bar texture"].set("eui")
Check(Texture(health) == "EUI-Melli" and Texture(cast) == "EUI-Blizzard", "EUI texture uses each profile baseline")
rows["Health-bar color"].set(0.4, 0.5, 0.6)
rows["Cast fill color"].set(0.6, 0.5, 0.4)
Color(health, 0.4, 0.5, 0.6, "live health color")
Color(cast, 0.6, 0.5, 0.4, "live cast color")
rows["Health border size"].set(5)
rows["Cast border size"].set(4)
Borders(health, 5, 0.3, 0.6, 0.9, "live health thickness")
Borders(cast, 4, 0.9, 0.6, 0.3, "live cast thickness")
rows["Health border color"].set(0.2, 0.3, 0.4)
rows["Cast border color"].set(0.4, 0.3, 0.2)
Borders(health, 5, 0.2, 0.3, 0.4, "live health border color")
Borders(cast, 4, 0.4, 0.3, 0.2, "live cast border color")
rows["Cast opacity (%)"].set(0)
Near(cast._appearance.alpha, 0, "zero cast opacity")
Near(cast.alpha, 1, "preview lock layer stays independent of opacity")
rows["Opacity (%)"].set(60)
Near(health._appearance.alpha, 0.6, "live whole-nameplate opacity")
rows["Cast opacity (%)"].set(50)
Near(cast._appearance.alpha, 0.3, "live combined cast opacity")

rows["Custom health color"].set(false)
rows["Custom cast color"].set(false)
health, cast = Preview("Health-bar"), Preview("Cast-bar")
Color(health, 0.2, 0.4, 0.6, "health EUI sample color")
Color(cast, 0.6, 0.4, 0.2, "cast EUI sample color")
rows["Override health border"].set(false)
rows["Override cast border"].set(false)
health, cast = Preview("Health-bar"), Preview("Cast-bar")
Borders(health, 1, 0.1, 0.1, 0.1, "health baseline outline")
Borders(cast, 1, 0.1, 0.1, 0.1, "cast baseline outline")
np.db.profile.customBorderEnabled, np.db.profile.customBorderTexture = true, "glow"
np.db.profile.customBorderSize, np.db.profile.customBorderAlpha = 2, 0.6
health._refresh()
Check(health._border._testBorder.texture == "glow" and health._border._testBorder.size == 2,
    "border-off preview restores current native textured border")
Near(health._border._testBorder.color[4], 0.6, "native textured border alpha preview")
np.db.profile.customBorderEnabled = false
np.db.profile.showBorder = false
health._refresh()
Check(health._border._testBorder.size == 0, "native border-off is respected, not changed into an artificial outline")
np.db.profile.showBorder = true
rows["Health-bar texture"].set("flat")
rows["Cast-bar texture"].set("flat")
rows["Override health bar"].set(false)
rows["Override cast bar"].set(false)
health, cast = Preview("Health-bar"), Preview("Cast-bar")
Check(Texture(health) == "EUI-Melli" and Texture(cast) == "EUI-Blizzard", "override off restores baseline samples")
Near(health.alpha, 1, "health override off does not dim preview")
Near(cast.alpha, 1, "cast override off does not dim preview")
Near(cast._appearance.alpha, 0.6, "cast override off ignores custom cast opacity")
rows["Opacity (%)"].set(35)
Near(health._appearance.alpha, 0.35, "health override-off preview shows live nameplate opacity")
Near(cast._appearance.alpha, 0.35, "cast override-off preview shows live nameplate opacity")
Near(health.alpha, 1, "opacity updates do not dim health preview lock layer")
Near(cast.alpha, 1, "opacity updates do not dim cast preview lock layer")

rows["Override health bar"].set(true)
rows["Override cast bar"].set(true)
rows["Rule enabled"].set(false)
health, cast = Preview("Health-bar"), Preview("Cast-bar")
Near(health.alpha, 0.3, "disabled rule dims health sample")
Near(cast.alpha, 0.3, "disabled rule dims cast sample")
rows["Health-bar texture"].set("blizzard")
Check(style.texture == "flat" and Texture(health) == "Interface\\Buttons\\WHITE8x8", "disabled callbacks preserve sample and rule")
rows["Rule enabled"].set(true)
rows["Enable rule styling"].set(false)
Near(Preview("Health-bar").alpha, 0.3, "global lock dims health sample")
Near(Preview("Cast-bar").alpha, 0.3, "global lock dims cast sample")
rows["Enable rule styling"].set(true)
Near(Preview("Health-bar").alpha, 1, "reenable restores sample brightness")

-- Selected-rule changes use the selected rule's appearance.
local secondStyle = {}
for key, value in pairs(style) do secondStyle[key] = value end
secondStyle.healthColorEnabled, secondStyle.healthColor, secondStyle.texture = true, { r = 0.1, g = 0.7, b = 0.3 }, "melli"
api.GetSettings().rules[2] = { name = "Preview second rule", enabled = true, conditions = {}, style = secondStyle }
EllesmereUI:RefreshPage()
rows["Edit rule"].set("2")
health = Preview("Health-bar")
Color(health, 0.1, 0.7, 0.3, "selected second rule color")
Check(Texture(health) == "EUI-Melli", "selected second rule texture")
Check(health._bar ~= f.plate.health and cast._bar ~= f.plate.cast, "preview renders independent UI-owned bars")
f.Flush()
-- Media selections participate in validated rule sharing.
local selectedRule = api.GetRules()[2]
selectedRule.style.borderTexture, selectedRule.style.castBorderTexture = "glow", "sm:Test Border"
local code = assert(api.ExportRuleSet())
Check(api.ImportRuleSet(code) and api.GetRules()[2].style.borderTexture == "glow"
    and api.GetRules()[2].style.castBorderTexture == "sm:Test Border", "border texture sharing roundtrip")
api.GetRules()[2].style.castBorderTexture = "arbitrary/path"
local rejected, reason = api.ExportRuleSet()
Check(not rejected and reason:find("castBorderTexture", 1, true), "unknown cast border rejected during sharing")
print("PASS: " .. checks .. " header appearance preview, live textures/colors/borders/opacity, baseline fallbacks and editor locks")
