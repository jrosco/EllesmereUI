-- Run from the repository root with Lua or fengari.
local fixture = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("traits")
local namespace = fixture.namespace
-- Verify the real rule renderer forwards conditions even when the API flag is secret.
local probe = { name = "Scoped cast", enabled = true, conditions = { castState = { interruptible = true } },
    style = { castEnabled = true, castColorEnabled = true } }
fixture.api.GetSettings().rules = { probe }
fixture.mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, fixture.secret, fixture.secret }
local painter, forwarded = namespace.ApplyCastStyle
namespace.ApplyCastStyle = function(_, style, _, colors)
    forwarded = style == probe.style and colors and colors.interruptible and colors.interruptible.rule == probe
end
namespace.RefreshAll()
namespace.ApplyCastStyle = painter
assert(forwarded, "secret-cast color rule must forward both appearance and state-specific palette")
local plate = CreateFrame()
plate.unit = "nameplate1"
plate.cast = CreateFrame("StatusBar", nil, plate)
local fill = plate.cast:CreateTexture()
fill:SetTexture("engine")
function plate.cast:GetStatusBarTexture() return fill end
plate.castBarOverlay = plate.cast:CreateTexture()
plate.castBarOverlay:SetTexture("overlay")
plate.castBarOverlay:SetAlpha(0.4)
local engineColor = { 0.2, 0.3, 0.4, 0.8 }
local overlayColor = { 0.5, 0.6, 0.7, 0.9 }
local evaluatorCalls = 0
local secretMode = false
issecretvalue = function(value) return value == fixture.secret or (secretMode and type(value) == "boolean") end
C_CurveUtil = { EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse)
    -- This mock represents the native, secret-aware boundary, not addon branching.
    evaluatorCalls = evaluatorCalls + 1
    if value then return ifTrue end
    return ifFalse
end }
function plate:ApplyCastColor(protected)
    self._kickProtected = protected
    fill:SetVertexColor(unpack(engineColor))
    -- Like EUI, interruptibility flips do not necessarily repaint overlay RGB.
end
fill:SetVertexColor(unpack(engineColor))
plate.castBarOverlay:SetVertexColor(unpack(overlayColor))
local style = { castEnabled = true, castColorEnabled = true,
    castColor = { r = 0.9, g = 0.1, b = 0.2 } }
local conditions = { castState = { interruptible = true } }
local function Apply(currentStyle) namespace.ApplyCastStyle(plate, currentStyle, conditions) end
local function Near(actual, expected, label)
    assert(math.abs(actual - expected) < 0.00001, label)
end
local function Colors(expectedFill, expectedOverlay, label)
    for i = 1, 3 do
        Near(fill.vertexColor[i], expectedFill[i], label .. " fill channel " .. i)
        Near(plate.castBarOverlay.vertexColor[i], expectedOverlay[i], label .. " overlay channel " .. i)
    end
    Near(fill.vertexColor[4], engineColor[4], label .. " fill alpha")
    Near(plate.castBarOverlay.vertexColor[4], overlayColor[4], label .. " overlay color alpha")
    Near(plate.castBarOverlay:GetAlpha(), 0.4, label .. " native visibility unchanged")
end
local custom = { 0.9, 0.1, 0.2 }
Apply(style)
Colors(engineColor, overlayColor, "missing stamp leaves EUI paint")
plate:ApplyCastColor(false)
Colors(custom, custom, "readable interruptible cast")
plate:ApplyCastColor(true)
Colors(engineColor, overlayColor, "uninterruptible restores both layers immediately")
secretMode = true
plate:ApplyCastColor(false)
Colors(custom, custom, "secret interruptible uses native evaluator")
plate:ApplyCastColor(true)
Colors(engineColor, overlayColor, "secret uninterruptible uses native evaluator")
assert(evaluatorCalls > 0, "secret values were not passed to native evaluator")
local nativeEvaluate = C_CurveUtil.EvaluateColorValueFromBoolean
C_CurveUtil.EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse)
    -- Opaque results model secret color channels accepted by native setters.
    return { nativeValue = nativeEvaluate(value, ifTrue, ifFalse) }
end
plate:ApplyCastColor(false)
for i = 1, 3 do
    assert(type(fill.vertexColor[i]) == "table" and fill.vertexColor[i].nativeValue == custom[i],
        "opaque native color channel was not forwarded directly to the setter")
end
Apply(nil)
Colors(engineColor, overlayColor, "opaque result never replaces cached engine paint")
C_CurveUtil.EvaluateColorValueFromBoolean = nativeEvaluate
Apply(style)
plate:ApplyCastColor(false)
plate._interrupted = true
engineColor = { 1, 0, 0, 1 }
plate:ApplyCastColor(false)
Colors(engineColor, overlayColor, "interrupted flash wins")
plate._interrupted = nil
engineColor = { 0.1, 0.4, 0.6, 0.8 }
plate:ApplyCastColor(false)
Colors(custom, custom, "new engine paint stays scoped")
Apply(nil)
Colors(engineColor, overlayColor, "disable restores latest engine paints")
Apply(style)
fill = plate.cast:CreateTexture()
fill:SetTexture("replacement")
fill:SetVertexColor(unpack(engineColor))
Apply(style)
Colors(custom, custom, "replacement fill is watched")
plate:ApplyCastColor(true)
Colors(engineColor, overlayColor, "replacement fill respects uninterruptible state")
Apply(nil)
conditions.castState = { uninterruptible = true }
Apply(style)
plate:ApplyCastColor(true)
Colors(custom, custom, "secret uninterruptible-only custom color")
plate:ApplyCastColor(false)
Colors(engineColor, overlayColor, "uninterruptible-only preserves interruptible engine paint")
conditions.castState = { interruptible = true, casting = true }
Apply(style)
plate:ApplyCastColor(true)
Colors(custom, custom, "explicit Casting overrides subtype filter")
conditions.castState = { interruptible = true }
Apply(nil)
C_CurveUtil = nil
secretMode = false
Apply(style)
plate:ApplyCastColor(false)
Colors(custom, custom, "older client readable fallback")
plate:ApplyCastColor(true)
Colors(engineColor, overlayColor, "older client uninterruptible fallback")
secretMode = true
plate:ApplyCastColor(false)
Colors(engineColor, overlayColor, "secret without evaluator preserves EUI paint")
conditions.castState.uninterruptible = true
C_CurveUtil = { EvaluateColorValueFromBoolean = nativeEvaluate }
Apply(style)
Colors(custom, custom, "both interruptibility choices supply normal and protected colors")
conditions.castState = {}
Apply(style)
Colors(custom, custom, "legacy all-cast coloring remains unchanged")
Apply(nil)
Colors(engineColor, overlayColor, "all-cast disable restores base")
-- Exercise EUI's actual cooldown tint helper rather than duplicate its precedence.
EllesmereUI = {}
UnitGUID = function() return nil end
UnitClassBase = function() return "MAGE" end
IsSpellKnown = function() return true end
assert(loadfile("EllesmereUI_Kick.lua"))()
EllesmereUI.RefreshKickAbility()
local offCooldown, haveCooldown = true, true
C_CurveUtil = { EvaluateColorValueFromBoolean = nativeEvaluate }
C_Spell = { GetSpellCooldownDuration = function()
    if haveCooldown then return { IsZero = function() return offCooldown end } end
end }
local function Rule(name, selection, color, rank)
    return { name = name, enabled = true,
        conditions = { classification = { [rank or "normal"] = true }, castState = selection },
        style = { castEnabled = true, castColorEnabled = true, castColor = { r = color[1], g = color[2], b = color[3] } } }
end
local readyColor, cooldownColor, protectedColor, fallbackColor =
    { 0.8, 0.1, 0.1 }, { 0.1, 0.2, 0.9 }, { 0.6, 0.1, 0.8 }, { 0.1, 0.9, 0.2 }
local readyRule = Rule("Ready", { interruptible = true }, readyColor)
local cooldownRule = Rule("On cooldown", { interruptOnCD = true }, cooldownColor)
local protectedRule = Rule("Protected", { uninterruptible = true }, protectedColor)
local fallbackRule = Rule("Fallback", { casting = true }, fallbackColor)
fixture.api.GetSettings().rules = { readyRule, cooldownRule, protectedRule, fallbackRule }
local function Palette()
    return namespace.FindCastColorOverrides("nameplate1")
end
local palette = Palette()
assert(palette.interruptible.rule == readyRule and palette.interruptOnCD.rule == cooldownRule
    and palette.uninterruptible.rule == protectedRule, "first rule must win independently for each color state")
assert(namespace.FindRule("nameplate1") == readyRule, "implicit Casting must use first-match appearance priority")
namespace.ApplyCastStyle(plate, nil, nil, palette)
offCooldown = true
plate:ApplyCastColor(false)
Colors(readyColor, readyColor, "interrupt available override")
offCooldown = false
plate:ApplyCastColor(false)
Colors(cooldownColor, cooldownColor, "interrupt on CD override")
plate:ApplyCastColor(true)
Colors(protectedColor, protectedColor, "uninterruptible wins over cooldown")
offCooldown = true
plate:ApplyCastColor(true)
Colors(protectedColor, protectedColor, "uninterruptible wins over ready")
-- State knowledge stays available for diagnostics/extensions; appearances use implicit Casting.
secretMode = false
fixture.mocks.casting[8] = false
offCooldown = true
local selected, _, traits = namespace.FindRule("nameplate1")
assert(selected == readyRule and traits.castColorState == "interruptible", "ready knowledge with first appearance rule")
offCooldown = false
selected, _, traits = namespace.FindRule("nameplate1")
assert(selected == readyRule and traits.castColorState == "interruptOnCD", "cooldown knowledge must not change broad appearance priority")
fixture.mocks.casting[8] = true
selected, _, traits = namespace.FindRule("nameplate1")
assert(selected == readyRule and traits.castColorState == "uninterruptible", "protected knowledge with implicit Casting appearances")
fixture.mocks.casting[8] = fixture.secret
secretMode = true
fixture.api.GetSettings().rules = { readyRule, cooldownRule, protectedRule }
assert(namespace.FindRule("nameplate1") == readyRule, "hidden color state still permits implicit Casting appearances")
fixture.api.GetSettings().rules = { readyRule, cooldownRule, protectedRule, fallbackRule }
cooldownRule.enabled = false
namespace.ApplyCastStyle(plate, nil, nil, Palette())
offCooldown = false
plate:ApplyCastColor(false)
Colors(fallbackColor, fallbackColor, "lower all-casts rule fills only missing color state")
fallbackRule.enabled = false
namespace.ApplyCastStyle(plate, nil, nil, Palette())
plate:ApplyCastColor(false)
Colors(engineColor, overlayColor, "unmatched CD state retains each engine layer")
fixture.api.GetSettings().rules = { Rule("Two states", { interruptible = true, uninterruptible = true }, readyColor) }
local twoStates = Palette()
assert(twoStates.interruptible and twoStates.uninterruptible and not twoStates.interruptOnCD,
    "selecting two states must not implicitly override the third")
fixture.api.GetSettings().rules = { readyRule, cooldownRule, protectedRule, fallbackRule }
cooldownRule.enabled = true
cooldownRule.conditions.classification = { elite = true }
assert(not Palette().interruptOnCD, "nonmatching readable conditions must reject a color candidate")
cooldownRule.conditions.classification = { normal = true }
namespace.ApplyCastStyle(plate, nil, nil, Palette())
haveCooldown = false
plate:ApplyCastColor(false)
Colors(readyColor, readyColor, "unavailable cooldown uses EUI normal-state fallback")
IsSpellKnown = function() return false end
EllesmereUI.RefreshKickAbility()
plate:ApplyCastColor(false)
Colors(readyColor, readyColor, "no interrupt ability uses EUI normal-state fallback")
IsSpellKnown = function() return true end
EllesmereUI.RefreshKickAbility()
haveCooldown = true
plate._interrupted = true
plate:ApplyCastColor(false)
Colors(engineColor, overlayColor, "state palettes preserve interrupted flash")
plate._interrupted = nil
fixture.api.GetSettings().enabled = false
namespace.ApplyCastStyle(plate, nil, nil, Palette())
Colors(engineColor, overlayColor, "global disable restores latest engine paints")
fixture.api.GetSettings().enabled = true
print("PASS: per-state rule priority, actual EUI cooldown tint, secret rendering, unmatched defaults and restoration")
