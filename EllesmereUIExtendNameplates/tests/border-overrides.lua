-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("traits")
local api, addon, plate, checks = f.api, f.namespace, f.plate, 0
local PP = EllesmereUI.PP
local function Check(value, label) checks = checks + 1; assert(value, label) end
local function Near(actual, expected, label) Check(math.abs(actual - expected) < 0.00001, label) end
plate.health:SetParent(plate)
local basicHealth = PP.CreateBorder(plate.health, 0.1, 0.2, 0.3, 0.8, 2)
local basicCast = PP.CreateBorder(plate.cast, 0.4, 0.5, 0.6, 0.7, 1)
plate._customBorder = CreateFrame("Frame", nil, plate.health)
EllesmereUI.ApplyBorderStyle(plate._customBorder, 3, 0.7, 0.6, 0.5, 0.9, "blizz")
plate._customBorder:SetAlpha(0.9)
plate.castWrapRegion = CreateFrame("Frame", nil, plate.cast)
plate._cbWrapLower = CreateFrame("Frame", nil, plate.cast)
function plate:ApplyBorder()
    PP.CreateBorder(self.health, 0.2, 0.3, 0.4, 1, 4)
    EllesmereUI.ApplyBorderStyle(self._customBorder, 2, 0.1, 0.3, 0.5, 1, "glow")
end
function plate:ApplyCastBorder() PP.CreateBorder(self.cast, 0.6, 0.4, 0.2, 1, 3) end
function plate:UpdateBorderWrap() self.wrapRefreshes = (self.wrapRefreshes or 0) + 1 end
local style = { scale = 150, opacity = 70, healthEnabled = true, borderEnabled = true, borderSize = 3,
    borderTexture = "glow", borderColor = { r = 1, g = 0.2, b = 0.1 },
    castEnabled = true, castBorderEnabled = true, castBorderSize = 2, castBorderTexture = "blizz",
    castBorderColor = { r = 0.1, g = 0.8, b = 0.3 }, castOpacityEnabled = true, castOpacity = 50 }
api.GetSettings().rules = { { name = "Native border override", enabled = true, conditions = {}, style = style } }
local function Refresh() api.Refresh(); f.Flush() end
Refresh()
local health, cast = addon.GetRuleBorderFrames(plate)
Check(health:GetParent() == plate.health and cast:GetParent() == plate.cast, "replacement hosts ride health and cast subtrees")
Check(health._testBorder.texture == "glow" and cast._testBorder.texture == "blizz", "shared renderer receives selected textures")
Check(health._testBorder.addonKey == "nameplates" and health._testBorder.sizeKey == 3, "same native nameplates media offsets")
Near(basicHealth:GetAlpha(), 0, "native health outline suppressed")
Near(basicCast:GetAlpha(), 0, "native cast outline suppressed")
Near(plate._customBorder:GetAlpha(), 0, "native custom health outline replaced, not doubled")
Near(plate.castWrapRegion:GetAlpha(), 0, "native wrap outline suppressed")
Near(health:GetEffectiveScale(), 1.5, "health border follows selected scaling")
Near(cast:GetEffectiveScale(), 1.5, "cast border follows selected scaling")
plate._castOverlayLifted = true
local originalStrata = plate.cast.GetFrameStrata
plate.cast.GetFrameStrata = function() return "HIGH" end
Refresh()
Check(cast._testBorder.texture == "blizz" and cast:GetParent() == plate.cast, "lifted cast retains its border host")
plate._castOverlayLifted = nil
plate.cast.GetFrameStrata = originalStrata
plate:ApplyBorder(); plate:ApplyCastBorder()
Near(plate._customBorder:GetAlpha(), 0, "native style repaint stays suppressed")
Near(health._testBorder.color[1], 1, "rule tint survives native repaint")
Check(plate._customBorder._testBorder.texture == "glow" and basicHealth.size == 4 and basicCast.size == 3,
    "latest native style/size continues updating underneath")
basicHealth:SetAlpha(0.35); basicCast:SetAlpha(0.45); plate._customBorder:SetAlpha(0.55)
Near(basicHealth:GetAlpha(), 0, "engine alpha writes cannot reveal duplicate border")
style.borderTexture, style.castBorderTexture = "solid", "sm:Test Border"
Refresh()
Check(health._testBorder.texture == "solid" and cast._testBorder.texture == "sm:Test Border", "live solid/SharedMedia switching")
style.castBorderSize = 7
Refresh()
Check(cast._testBorder.size == 4 and style.castBorderSize == 7, "textured renderer caps native size steps without discarding saved solid thickness")
style.castBorderSize = 2
Check(PP.GetBorders(health).guarded, "solid outline uses native nameplate scaleGuard")
style.borderEnabled = false
local np = EllesmereNameplates_NS
plate._cbWrapActive = true
function np.NP_UnwrapCustomBorder(p) p._cbWrapActive = nil; p.unwrapped = true end
basicHealth._hideBottom = true
Refresh()
Check(not health:IsShown() and cast:IsShown(), "health override off leaves cast override active")
Near(basicHealth:GetAlpha(), 0.35, "health restores latest native alpha")
Near(plate._customBorder:GetAlpha(), 0.55, "custom native outline restored")
Near(basicCast:GetAlpha(), 0, "cast remains suppressed independently")
Check(plate.unwrapped and basicHealth._hideBottom == nil, "cast-only override separates native wrapped health outline")
style.castBorderEnabled = false
Refresh()
Near(basicCast:GetAlpha(), 0.45, "cast restores latest native alpha")
Check(not cast:IsShown() and plate.wrapRefreshes > 0, "cast release restores native wrapping")
Check(plate._customBorder._testBorder.size == 2 and plate._customBorder._testBorder.texture == "glow",
    "native color/texture/thickness retained without stale restoration snapshots")

style.borderEnabled, style.castBorderEnabled = true, true
plate._classicHealthHost = CreateFrame("Frame", nil, plate.health)
plate._classicCastHost = CreateFrame("Frame", nil, plate.cast)
plate.healthBG, plate.castBG = plate.health:CreateTexture(), plate.cast:CreateTexture()
plate._blizzBarBg, plate._blizzCastArt = true, true
plate.healthBG:SetAlpha(0.75); plate.castBG:SetAlpha(0.65)
Refresh()
Near(plate._classicHealthHost:GetAlpha(), 0, "classic health art suppressed")
Near(plate._classicCastHost:GetAlpha(), 0, "classic cast art suppressed")
Near(plate.healthBG:GetAlpha(), 0, "stock health rim replaced")
Near(plate.castBG:GetAlpha(), 0, "stock cast rim replaced")
-- Secret values can flow through alpha setters, never branch or do arithmetic.
basicHealth:SetAlpha(f.secret)
style.healthEnabled, style.castEnabled = false, false
Refresh()
Check(basicHealth:GetAlpha() == f.secret, "secret native alpha restored only through setter")
Near(plate.healthBG:GetAlpha(), 0.75, "stock health art restored")
Near(plate.castBG:GetAlpha(), 0.65, "stock cast art restored")
Near(plate._classicHealthHost:GetAlpha(), 1, "classic health art restored")
Near(plate._classicCastHost:GetAlpha(), 1, "classic cast art restored")
basicHealth:SetAlpha(1)
style.healthEnabled, style.castEnabled = true, true
Refresh()
plate:ClearUnit()
Check(not health:IsShown() and not cast:IsShown(), "recycle releases rule borders")
Near(basicCast:GetAlpha(), 0.45, "recycle returns native cast outline")
plate.unit = "nameplate1"
Refresh()
Check(health:IsShown() and cast:IsShown(), "reused plate reapplies rule")
api.GetSettings().enabled = false
Refresh()
Check(not health:IsShown() and not cast:IsShown(), "global disable releases replacements")
Near(plate._customBorder:GetAlpha(), 0.55, "global disable restores native custom outline")
-- Missing shared renderer on an older build must leave native outlines alone.
local renderer = EllesmereUI.ApplyBorderStyle
EllesmereUI.ApplyBorderStyle = nil
api.GetSettings().enabled = true
Refresh()
Near(plate._customBorder:GetAlpha(), 0.55, "missing renderer preserves native health outline")
Near(basicCast:GetAlpha(), 0.45, "missing renderer preserves native cast outline")
EllesmereUI.ApplyBorderStyle = renderer
Refresh()
Check(health:IsShown() and cast:IsShown(), "renderer becoming available reapplies overrides")
for _, key in ipairs({ "solid", "blizz", "glow", "pixels", "sm:Missing On Recipient" }) do
    Check(api.ValidateBorderStyle(key), "valid media border key " .. key)
end
for _, key in ipairs({ "unknown", "../arbitrary", "", "solid\n", false, 1, {} }) do
    Check(not api.ValidateBorderStyle(key), "malformed/unlisted border rejected")
end
print("PASS: " .. checks .. " native border replacement, renderer arguments, engine updates, independence, stock art, restoration and secret-safe alpha checks")
