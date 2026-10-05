-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("traits")
local api, addon, plate, np, checks = f.api, f.namespace, f.plate, EllesmereNameplates_NS, 0
local function Check(value, label) checks = checks + 1; assert(value, label) end
local function Near(actual, expected, label) Check(math.abs(actual - expected) < 0.00001, label) end
plate.health:SetParent(plate)
plate.healthTextFrame = CreateFrame("Frame", nil, plate)
plate.topTextFrame = CreateFrame("Frame", nil, plate)
plate.castTextFrame = CreateFrame("Frame", nil, plate.cast)
for _, key in ipairs({ "name", "hpText", "hpNumber", "levelText", "totText" }) do plate[key] = plate.healthTextFrame:CreateFontString(); plate[key]:Show() end
for _, key in ipairs({ "castName", "castTarget", "castTimer" }) do plate[key] = plate.castTextFrame:CreateFontString(); plate[key]:Show() end
np.db = { profile = { textSlotTop = "enemyName", textSlotLeft = "level", textSlotRight = "healthNumber", showCastTimer = true } }
np.GetTextSlot = function(key) return np.db.profile[key] or "none" end
np.GetHealthBarWidth = function() return 180 end
np.GetUnitLevelText = function() return "22" end
UnitHealth = function() return 6600 end
UnitHealthMax = function() return 8800 end
CurveConstants = { ScaleTo100 = {} }
UnitHealthPercent = function(_, _, curve) Check(curve == CurveConstants.ScaleTo100, "native health percent uses ScaleTo100 curve"); return 75 end
UnitName = function(unit) return unit:match("target$") and "Target Name" or "Enemy Name" end
UnitSpellTargetName = function() return "Spell Target" end
UnitShouldDisplaySpellTargetName = function() return true end
f.mocks.casting = { "Spell Name", nil, nil, 1000, 4000, nil, nil, false, 123 }
UnitCastingDuration = function() return {
    GetRemainingDuration = function() return 2 end, GetElapsedDuration = function() return 1 end, GetTotalDuration = function() return 3 end,
} end
function plate:UpdateHealthValues() plate.hpNumber:SetText("latest native HP") end
function plate:UpdateName() plate.name:SetText("latest native name") end
function plate:UpdateCast() end
function np.RefreshCastOverlay(owner)
    -- Model the descendant strata reset performed by native cast reparenting.
    local _, fs = addon.GetRuleTextFrames(owner)
    if fs and fs.castName then fs.castName:GetParent():SetFrameStrata("LOW") end
end
local style = { scale = 150, opacity = 100, borderSize = 0, healthEnabled = false, textEnabled = true,
    textSlots = { textSlotTop = "name", textSlotLeft = "level", textSlotCenter = "healthPercent",
        textSlotRight = "healthCurrentMax", textSlotBottomLeft = "healthMax", textSlotBottomRight = "targetOfTarget",
        castName = "spellName", castTarget = "castTarget", castTimer = "castElapsedTotal" },
    textColors = { name = { r = 0.2, g = 0.7, b = 0.9 }, level = { r = 0.9, g = 0.7, b = 0.2 },
        castElapsedTotal = { r = 0.9, g = 0.2, b = 0.1 } } }
local rule = { name = "Text rule", enabled = true, conditions = { target = { yes = true } }, style = style }
api.GetSettings().rules = { rule }
local function Refresh() api.Refresh(); f.Flush() end
Refresh()
local host, fonts = addon.GetRuleTextFrames(plate)
Check(fonts.textSlotTop.text == "Enemy Name" and fonts.textSlotLeft.text == "22", "name and level slot contents")
Check(fonts.textSlotCenter.text == "75%" and fonts.textSlotRight.text == "6600 / 8800", "percent and current/max contents")
Check(fonts.textSlotBottomLeft.text == "8800" and fonts.textSlotBottomRight.text == "Target Name", "maximum and target-of-target contents")
Check(fonts.castName.text == "Spell Name" and fonts.castTarget.text == "Spell Target" and fonts.castTimer.text == "1.0 / 3.0",
    "cast name, target and duration contents")
local castHost = fonts.castName:GetParent()
Check(castHost ~= plate.cast and castHost:GetParent() == plate.cast and castHost:GetFrameLevel() == 900,
    "replacement cast labels use a raised cast-owned text host")
Check(castHost:GetFrameStrata() == "MEDIUM", "ordinary cast text escapes flattened bar layers")
plate._castOverlayLifted = true
np.RefreshCastOverlay(plate)
Check(castHost:GetFrameStrata() == "HIGH" and castHost:GetFrameLevel() == 900, "lifted cast re-seats replacement text above the fill")
plate._castOverlayLifted = nil
np.RefreshCastOverlay(plate)
Check(castHost:GetFrameStrata() == "MEDIUM", "returning cast to plate restores ordinary text tier")
Near(fonts.textSlotTop.textColor[1], 0.2, "name independent color")
Near(fonts.textSlotLeft.textColor[1], 0.9, "level independent color")
Near(fonts.castTimer.textColor[1], 0.9, "cast time independent color")
Near(plate.name:GetAlpha(), 0, "native name suppressed instead of duplicated")
Near(fonts.textSlotTop:GetEffectiveScale(), 1.5, "replacement health text participates in Text scaling")
plate.name:SetAlpha(0.6); plate.name:SetTextColor(0.4, 0.5, 0.6, 0.8)
plate:UpdateName()
Near(plate.name:GetAlpha(), 0, "native repaint cannot reveal a competing label")
style.textSlots.textSlotTop = "eui"
Refresh()
Check(not fonts.textSlotTop:IsShown(), "Use EUI setting releases owned slot")
Near(plate.name:GetAlpha(), 0.6, "Use EUI restores latest native alpha")
Near(plate.name.textColor[1], 0.2, "per-element name color can override native slot without replacing content")
plate.name:SetTextColor(0.8, 0.6, 0.4, 0.9)
Near(plate.name.textColor[1], 0.2, "text color survives native color repaint")
style.textColors.name = nil
Refresh()
Near(plate.name.textColor[1], 0.8, "color toggle off restores latest native color")
style.textSlots.textSlotTop = "none"
Refresh()
Check(not fonts.textSlotTop:IsShown() and plate.name:GetAlpha() == 0, "None hides the slot without destroying native content")
style.textSlots.castTimer = "castRemaining"; Refresh()
Check(fonts.castTimer.text == "2.0", "remaining time selection")
style.textSlots.castTimer = "castTotal"; Refresh()
Check(fonts.castTimer.text == "3.0", "total time selection")
style.textSlots.castTimer = "castElapsed"; Refresh()
Check(fonts.castTimer.text == "1.0", "elapsed time selection")

-- Model native format sinks accepting secret arguments, unlike Fengari's Lua
-- string.format implementation. Secret health/names/durations never get math.
for _, fs in pairs(fonts) do
    fs.SetFormattedText = function(self, format, ...)
        local args = { ... }; self.format, self.args = format, args
        for _, value in ipairs(args) do if issecretvalue(value) then self.text = f.secret; return end end
        self.text = string.format(format, ...)
    end
end
UnitHealth, UnitHealthMax, UnitHealthPercent, UnitName = function() return f.secret end,
    function() return f.secret end, function() return f.secret end, function() return f.secret end
UnitCastingDuration = function() return { GetRemainingDuration = function() return f.secret end,
    GetElapsedDuration = function() return f.secret end, GetTotalDuration = function() return f.secret end } end
style.textSlots.textSlotTop, style.textSlots.castTimer = "name", "castElapsedTotal"
Refresh()
Check(fonts.textSlotTop.text == f.secret and fonts.textSlotCenter.text == f.secret, "secret name/percent forwarded to native sinks")
Check(fonts.textSlotRight.args[1] == f.secret and fonts.textSlotRight.args[2] == f.secret, "secret current/max forwarded separately")
Check(fonts.castTimer.args[1] == f.secret and fonts.castTimer.args[2] == f.secret, "secret elapsed/total forwarded separately")
UnitCastingDuration, UnitHealthPercent = nil, nil
Refresh()
Check(fonts.textSlotCenter.text == "", "missing native percent path fails closed on secret operands")

-- Forever readable timestamps/health work without Retail-only APIs.
UnitHealth, UnitHealthMax = function() return 4400 end, function() return 8800 end
GetTime = function() return 2 end
UnitShouldDisplaySpellTargetName, UnitSpellTargetName = nil, nil
style.textSlots.castTimer = "castElapsedTotal"
Refresh()
Check(fonts.textSlotCenter.text == "50%" and fonts.castTimer.text == "1.0 / 3.0", "Forever percentage/timestamp fallbacks")
Check(fonts.castTarget.text == "", "unavailable cast target data is blank, not guessed from temporary unit target")
f.mocks.casting[4], f.mocks.casting[5] = f.secret, f.secret
Refresh()
Check(fonts.castTimer.text == "", "restricted fallback timestamps never enter arithmetic")
plate._interrupted = true
Refresh()
Check(not fonts.castName:IsShown() and plate.castName:GetAlpha() == 1, "native Interrupted label takes precedence")
plate._interrupted = nil
style.textEnabled = false
Refresh()
for _, fs in pairs(fonts) do Check(not fs:IsShown(), "master off hides owned text") end
Near(plate.name:GetAlpha(), 0.6, "master off restores latest native name visibility")
Near(plate.name.textColor[1], 0.8, "master off restores native name color")
style.textEnabled = true
Refresh()
plate:ClearUnit()
Check(not fonts.textSlotLeft:IsShown() and plate.name:GetAlpha() == 0.6, "recycle releases replacements and native suppression")
plate.unit = "nameplate1"
rule.conditions.target = { no = true }
Refresh()
Check(not fonts.textSlotLeft:IsShown(), "unmatching rule restores text")
Check(api.ValidateRuleText({ textSlots = { textSlotTop = "name", castTimer = "castRemaining" }, textColors = {} }), "valid text schema")
for _, bad in ipairs({ { textSlots = { unknown = "name" } }, { textSlots = { castName = "healthPercent" } },
    { textColors = { name = { r = 2, g = 0, b = 0 } } }, { textColors = { unknown = { r = 0, g = 0, b = 0 } } } }) do
    Check(not api.ValidateRuleText(bad), "invalid text schema rejected")
end
print("PASS: " .. checks .. " per-rule text slots/colors, native restoration, health/cast content, secret sinks and Forever fallbacks")
