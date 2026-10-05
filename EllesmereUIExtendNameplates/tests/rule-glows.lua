-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("traits")
local api, addon, plate, np = f.api, f.namespace, f.plate, EllesmereNameplates_NS
local G = assert(loadfile("EllesmereUIExtendNameplates/tests/glow-mocks.lua"))()
EllesmereUI.Glows = G
C_Texture = { GetAtlasInfo = function(name) return { name = name } end }
local checks = 0
local function Check(value, label) checks = checks + 1; assert(value, label) end
local function Near(actual, expected, label) Check(math.abs(actual - expected) < 0.00001, label) end
np.GetHealthBarWidth = function() return 210 end
np.GetHealthBarHeight = function() return 12 end
np.GetCastBarHeight = function() return 17 end
plate.health:SetParent(plate)
plate.health.GetWidth = function() error("restricted bar geometry must not be measured") end
plate.cast.GetWidth = function() return f.secret end
function plate:UpdateImportantCastGlow(value)
    if not self._importantCastOverlay then self._importantCastOverlay = CreateFrame("Frame", nil, self.cast) end
    self._importantCastOverlay:Show()
    self._importantCastOverlay:SetAlphaFromBoolean(value)
end
function plate:ClearImportantCastGlow()
    if self._importantCastOverlay then
        self._importantCastOverlay:SetAlpha(0)
        self._importantCastOverlay:Hide()
    end
end
function plate:UpdateCast() end
local style = { healthEnabled = true, healthColorEnabled = false, scale = 150, opacity = 70,
    borderSize = 2, borderEnabled = true, borderTexture = "glow", borderColor = { r = 1, g = 1, b = 1 },
    healthGlowStyle = 1, healthGlowColor = { r = 0.2, g = 0.8, b = 0.3 },
    castEnabled = true, castBorderEnabled = true, castBorderSize = 2, castBorderTexture = "blizz",
    castGlowStyle = 3, castGlowColor = { r = 0.9, g = 0.2, b = 0.1 }, castOpacityEnabled = true, castOpacity = 50 }
local rule = { name = "Target glow", enabled = true, conditions = { target = { yes = true } }, style = style }
api.GetSettings().rules = { rule }
local function Refresh() api.Refresh(); f.Flush() end
Refresh()
local health, cast = addon.GetRuleGlowFrames(plate)
Check(health:GetParent() == plate.health and cast:GetParent() == plate.cast, "independent glow hosts belong to their bars")
Check(health._mockGlowActive and cast._mockGlowActive, "matching rule starts both glows")
Check(health._mockGlowSpec.style == 1 and cast._mockGlowSpec.style == 3, "independent style selections")
Near(health._mockGlowSpec.r, 0.2, "independent health color")
Near(cast._mockGlowSpec.r, 0.9, "independent cast color")
Near(health._mockGlowSpec.width, 210, "authored health width, no restricted geometry read")
Near(health._mockGlowSpec.height, 12, "authored health height")
Near(cast._mockGlowSpec.height, 17, "authored cast height")
local borderHealth, borderCast = addon.GetRuleBorderFrames(plate)
Check(borderHealth:IsShown() and borderCast:IsShown(), "animated glow coexists with selected media borders")
Near(health:GetEffectiveScale(), 1.5, "health glow inherits rule scaling")
Near(cast:GetEffectiveScale(), 1.5, "cast glow inherits rule scaling")
Near(plate.cast:GetAlpha(), 0.5, "glow leaves cast opacity intact")
local starts = G.starts
for _ = 1, 8 do Refresh() end
Check(G.starts == starts, "stable rule refresh does not restart glow animations")
Check(cast._mockGlowSpec.lowLevel and cast._mockGlowSpec.scale == 1, "Auto-Cast Shine uses public renderer at default sparkle size")
Near(cast._euiAcData.sparkles[1].width, 7, "default sparkle size")
style.castGlowShineSize = 200
Refresh()
Near(cast._euiAcData.sparkles[1].width, 14, "sparkle size slider doubles the first layer's sparkles")
Near(cast._euiAcData.sparkles[16].width, 8, "sparkle size slider preserves staggered layer sizes")
Check(cast._euiAcData.period == 2 and cast._euiAcData.dotsPerLayer == 4, "sparkle sizing does not change orbit speed or count")
Check(cast._euiAcData.w == 210 and cast._euiAcData.h == 17 and cast._euiAcData.spacing > 0,
    "Auto-Cast orbit cache uses authored geometry, avoiding restricted GetSize on first tick")
starts = G.starts
for _ = 1, 4 do Refresh() end
Check(G.starts == starts, "custom-sized Shine remains animation-stable on repeated refresh")

plate:UpdateImportantCastGlow(true)
local native = plate._importantCastOverlay
Near(native:GetAlpha(), 0, "lazy Important Cast Glow suppressed by plugin cast glow")
native:SetAlpha(0.35)
Near(native:GetAlpha(), 0, "native alpha repaint cannot reveal competing glow")
style.castGlowStyle = 0
Refresh()
Near(native:GetAlpha(), 0.35, "None restores latest native glow alpha")
Check(not cast._mockGlowActive and health._mockGlowActive, "cast None does not stop health glow")
style.castGlowStyle = 1
Refresh()
plate:UpdateImportantCastGlow(false)
style.castGlowStyle = 0
Refresh()
Near(native:GetAlpha(), 0, "non-important cast remains non-glowing after release")
style.castGlowStyle = 1
Refresh()
plate:UpdateImportantCastGlow(f.secret)
Near(native:GetAlpha(), 0, "secret native important flag suppressed without branching")
style.castGlowStyle = 0
Refresh()
Check(native:GetAlpha() == f.secret, "secret native alpha forwarded to setter on restoration")
style.castGlowStyle = 1
Refresh()
plate:ClearImportantCastGlow()
style.castGlowStyle = 0
Refresh()
Check(native:GetAlpha() == 0 and not native:IsShown(), "ended native glow is not resurrected")

-- Native authored dimensions update without measuring the restricted tree.
style.castGlowStyle = 1
Refresh()
plate.health:SetSize(250, 14)
plate.cast:SetSize(220, 19)
Check(health._mockGlowSpec.width == 250 and health._mockGlowSpec.height == 14, "health layout writes update glow geometry")
Check(cast._mockGlowSpec.width == 220 and cast._mockGlowSpec.height == 19, "cast layout writes update glow geometry")
plate.cast:SetWidth(f.secret)
Check(cast._mockGlowSpec.width == 220, "secret layout writes do not enter glow arithmetic")
plate.cast:SetHeight(20)
Check(cast._mockGlowSpec.height == 20, "independent height setter updates geometry")

style.healthGlowLines, style.healthGlowThickness, style.healthGlowSpeed = 12, 3, 2
style.healthGlowBackground, style.healthGlowBackgroundColor = true, { r = 0.1, g = 0.2, b = 0.3 }
Refresh()
Check(health._mockGlowSpec.lines == 12 and health._mockGlowSpec.thickness == 3 and health._mockGlowSpec.speed == 2,
    "Pixel parameters use the shared engine spec")
Check(health._mockGlowSpec.bg and health._mockGlowSpec.bgB == 0.3, "Pixel background spec")
local values = api.GetRuleGlowOptions()
for _, index in ipairs({ 1, 3 }) do
    style.healthGlowStyle = index
    Refresh()
    Check(health._mockGlowSpec.style == index and values[index], "all offered effects render " .. index)
end
for _, index in ipairs({ 2, 4, 5, 6, 7, 8 }) do
    Check(values[index] == nil and not api.ValidateRuleGlowStyle(index), "icon glow not offered or accepted " .. index)
end
style.healthGlowShineSize = 50
Refresh()
Near(health._euiAcData.sparkles[1].width, 3.5, "health sparkle sizing is independent of cast")

-- Retail restricted visibility uses EUI's C-side engine-host rendering.
local visible = health.IsVisible
health.IsVisible = function() return f.secret end
style.healthGlowStyle = 1
Refresh()
Check(health._mockGlowSpec.kind == "engine" and health._mockGlowSpec.style == 1,
    "restricted Pixel Glow uses animated engine ants instead of a frozen Lua driver")
style.healthGlowStyle = 3
Refresh()
Check(health._mockGlowSpec.kind == "engine" and health._mockGlowSpec.style == 1,
    "restricted Auto-Cast Shine falls back to native Pixel ants, not button glow artwork")
Check(style.healthGlowStyle == 3, "restricted fallback preserves requested saved style")
health.IsVisible = visible

-- Neither supported effect depends on Retail-only action-button atlases.
C_Texture.GetAtlasInfo = function() error("bar glows must not request action-button atlases") end
style.healthGlowStyle = 3
Refresh()
Check(health._mockGlowSpec.style == 3, "Forever Auto-Cast Shine uses shared sparkle textures without atlas probes")

plate.cast:Hide()
Check(not cast._mockGlowActive and health._mockGlowActive, "cast hide stops animation but keeps health glow")
plate.cast:Show()
Check(cast._mockGlowActive, "cast show restarts requested glow")
style.healthEnabled = false
Refresh()
Check(not health._mockGlowActive and cast._mockGlowActive, "health master off independently stops health glow")
style.castEnabled = false
Refresh()
Check(not cast._mockGlowActive, "cast master off stops glow")
style.healthEnabled, style.castEnabled = true, true
style.healthGlowStyle = 1
style.scaleElements = { healthBar = false, castBar = false }
Refresh()
Near(health:GetEffectiveScale(), 1, "health glow follows Health bar scale toggle")
Near(cast:GetEffectiveScale(), 1, "cast glow follows Cast bar scale toggle")
rule.conditions.target = { no = true }
Refresh()
Check(not health._mockGlowActive and not cast._mockGlowActive, "leaving match tears down glows")
rule.conditions.target = { yes = true }
Refresh()
plate:ClearUnit()
Check(not health._mockGlowActive and not cast._mockGlowActive, "recycling tears down glows")
plate.unit = "nameplate1"
Refresh()
Check(health._mockGlowActive and cast._mockGlowActive, "reused plate reapplies glows")
local higher = { name = "Higher priority without glow", enabled = true, conditions = {}, style = { healthEnabled = false } }
api.GetSettings().rules = { higher, rule }
Refresh()
Check(not health._mockGlowActive and not cast._mockGlowActive, "higher matching rule without glow blocks lower rule glows")
higher.enabled = false
Refresh()
Check(health._mockGlowActive and cast._mockGlowActive, "disabling higher rule reveals lower matching glows")
plate:UpdateImportantCastGlow(true)
local start = G.StartSpecGlow
G.StartSpecGlow = function() error("simulated renderer failure") end
local ok = pcall(addon.ApplyRuleGlows, plate, style)
Check(not ok and native:GetAlpha() == 1, "renderer failure releases native Important Cast suppression")
G.StartSpecGlow = start
Refresh()
Check(cast._mockGlowActive and native:GetAlpha() == 0, "successful renderer retry restores plugin glow ownership")
api.GetSettings().enabled = false
Refresh()
Check(not health._mockGlowActive and not cast._mockGlowActive, "global disable tears down both animations")
EllesmereUI.Glows = nil
api.GetSettings().enabled = true
Refresh()
Check(not health._mockGlowActive and not cast._mockGlowActive, "missing glow engine fails closed")
print("PASS: " .. checks .. " independent rule glows, border coexistence, geometry, native Important Cast restoration, restrictions, Forever fallback and teardown")
