-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("ui-locks")
local api, rows, np, checks = f.api, f.rows, EllesmereNameplates_NS, 0
local function Check(value, label) checks = checks + 1; assert(value, label) end
local function Near(actual, expected, label) Check(math.abs(actual - expected) < 0.00001, label) end
EllesmereUI.Glows = assert(loadfile("EllesmereUIExtendNameplates/tests/glow-mocks.lua"))()
np.TARGET_ARROW_DIR = "Arrows/"
np.TARGET_ARROW_STYLES = {
    simple = { l = "simple-left", r = "simple-right", w = 11, label = "Simple" },
    winged = { l = "winged-left", r = "winged-right", w = 28, label = "Winged" },
}
np.db = { profile = { targetArrowStyle = "simple", showTargetArrows = false, targetArrowScale = 1,
    healthBarTexture = "melli", castBarTexture = "blizzard" } }
np.ResolveTargetArrowStyle = function(p) return np.TARGET_ARROW_STYLES[p and p.targetArrowStyle or "simple"] end
np.GetTargetArrowColor = function() return 0.2, 0.6, 0.8 end
np.GetHealthBarWidth = function() return 180 end
np.GetHealthBarHeight = function() return 14 end
np.GetCastBarHeight = function() return 17 end
local rule = api.GetRules()[1]
local style = rule.style
rule.conditions.target = { no = true } -- intentionally cannot match fixture's current target
style.healthEnabled, style.healthColorEnabled, style.healthColor = true, true, { r = 0.9, g = 0.1, b = 0.2 }
style.castEnabled, style.castColorEnabled, style.castColor = true, true, { r = 0.3, g = 0.4, b = 0.9 }
style.healthGlowStyle, style.castGlowStyle = 1, 3
style.targetArrowsEnabled, style.targetArrowStyle = true, "winged"
style.scale, style.opacity, style.castOpacityEnabled, style.castOpacity = 150, 70, true, 50
style.scaleElements = nil
EllesmereUI:RefreshPage()
local hero = assert(f.GetPreview())
Check(hero:GetParent() == f.header and hero:GetParent() ~= f.parent, "preview uses fixed content header outside scroll wrapper")
Check(hero.health:GetParent() == hero.plate and hero.cast:GetParent() == hero.plate, "both bars in one combined nameplate")
Check(hero.arrows.left:IsShown() and hero.arrows.right:IsShown(), "combined nameplate includes target arrows")
Check(hero.arrows.left:GetTexture() == "Arrows/winged-left.png", "selected rule's arrow style")
Check(hero.title.text:find(rule.name, 1, true), "header identifies selected rule")
Check(rows["Health-bar preview"] == nil and rows["Cast-bar preview"] == nil and rows["Target-arrow preview"] == nil,
    "inline previews removed")
Near(hero.health._bar.color[1], 0.9, "preview ignores match conditions and samples selected rule")
Near(hero.cast._bar.color[3], 0.9, "selected cast settings sampled")
Near(hero.health._appearance.alpha, 0.7, "health opacity")
Near(hero.cast._appearance.alpha, 0.35, "cast and nameplate opacity combined")
Near(hero.health:GetEffectiveScale(), 1.5, "health rule scaling")
Near(hero.cast:GetEffectiveScale(), 1.5, "cast rule scaling")
Near(hero.textHost:GetEffectiveScale(), 1.5, "nameplate text scaling")
Near(hero.arrows.left:GetEffectiveScale(), 1.5, "arrow Other scaling")
Check(hero.health._glow._mockGlowActive and hero.cast._glow._mockGlowActive, "combined preview includes both animated glows")
local tick = assert(hero.scripts.OnUpdate)
tick(hero, 1.5)
Near(hero.cast._bar.value, 50, "sample cast advances without a real unit or spell")
Check(hero.timer.text == "1.5s", "sample cast timer updates")
tick(hero, 2)
Near(hero.cast._bar.value, 100 / 6, "sample cast repeats after three seconds")
local phase = hero.elapsed
rows["Health-bar texture"].set("flat")
Check(f.GetPreview() == hero and hero.elapsed == phase, "in-place appearance update does not restart cast animation")

-- Scrolling/reflowing settings cannot move a header owned by a separate parent.
f.parent:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, -800)
Check(hero:GetParent() == f.header and hero.point[2] == f.header, "header remains pinned when settings scroll")
rows["Nameplate size (%)"].set(200)
Near(hero.health:GetEffectiveScale(), 2, "live rule scale update")
Check(f.header.height == hero.height and f.header.height >= 150, "framework reserves current preview height")
style.scaleElements = { healthBar = false, text = false, other = false }
hero.Update()
Near(hero.health:GetEffectiveScale(), 1, "health can remain unscaled")
Near(hero.cast:GetEffectiveScale(), 2, "cast can scale independently")
Near(hero.textHost:GetEffectiveScale(), 1, "text can remain unscaled")
Near(hero.arrows.left:GetEffectiveScale(), 1, "arrows can remain unscaled")
style.scaleElements = nil
hero.Update()

-- Cache restore can report its old saved height after OnShow. The module's
-- cache-restore callback reapplies the current height through the public API.
hero:Hide()
Check(hero.scripts.OnUpdate == nil and not hero.health._glow._mockGlowActive and not hero.cast._glow._mockGlowActive,
    "cached/hidden hero stops cast ticker and both glow engines")
hero.Update()
Check(hero.scripts.OnUpdate == nil, "hidden widget refresh cannot restart preview")
hero:Show()
f.header:SetHeight(150)
f.spec.modules[1].onPageCacheRestore("Rules")
Check(f.header.height == hero.height and hero.scripts.OnUpdate, "cached Rules resumes ticker and repairs header height")
Check(hero.health._glow._mockGlowActive and hero.cast._glow._mockGlowActive, "cached Rules restarts glows")

rows["Override target arrows"].set(false)
hero = f.GetPreview()
Check(not hero.arrows.left:IsShown(), "arrow override off respects native arrows-off")
np.db.profile.showTargetArrows = true
hero.Update()
Check(hero.arrows.left:IsShown() and hero.arrows.left:GetTexture() == "Arrows/simple-left.png", "native arrow baseline restored in preview")
rows["Override health bar"].set(false); rows["Override cast bar"].set(false)
hero = f.GetPreview()
Check(hero.health.alpha == 1 and hero.cast.alpha == 1 and hero.scripts.OnUpdate,
    "master overrides off do not dim preview or remove its sample cast")
rows["Opacity (%)"].set(40)
Near(hero.health._appearance.alpha, 0.4, "master-off health opacity remains visible")
Near(hero.cast._appearance.alpha, 0.4, "master-off cast opacity remains visible")

-- Only Rules provides the fixed hero; other pages clear it and its animations.
for _, page in ipairs({ "Profiles", "Sharing", "About" }) do
    f.spec.modules[1].buildPage(page, f.parent, 0)
    Check(f.GetPreview() == nil and f.spec.modules[1].getHeaderBuilder(page) == nil, page .. " has no preview header")
    Check(hero.scripts.OnUpdate == nil, page .. " stops the former Rules animation")
    EllesmereUI:RefreshPage()
    hero = f.GetPreview()
    Check(hero.scripts.OnUpdate, "Rules recreates header after " .. page)
end

-- Owned UI dimensions/font metrics use public EUI profile data, not unit data.
local width = np.GetHealthBarWidth
np.GetHealthBarWidth = function() return f.secret end
hero.Update()
np.GetHealthBarWidth = width
f.header:SetWidth(250)
hero.Update()
Check(hero.plate:GetScale() > 0 and hero.height >= 150, "narrow header fits the complete sample instead of clipping it")
f.Flush()
print("PASS: " .. checks .. " pinned Rules-only hero, repeating casts, live settings, independent scaling/arrows, scrolling, cache restoration and teardown")
