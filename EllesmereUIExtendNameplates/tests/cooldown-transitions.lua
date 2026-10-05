-- Run from the repository root with Lua or fengari.
local fixture = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("traits")
local api, addon = fixture.api, fixture.namespace
-- Native methods exist before Extras installs its hooks, as on EUI frames.
local plate = CreateFrame()
plate.unit = "nameplate1"
plate.health = fixture.plate.health
plate.cast = CreateFrame("StatusBar", nil, plate)
local fill = plate.cast:CreateTexture()
fill:SetTexture("cast-base")
function plate.cast:GetStatusBarTexture() return fill end
plate.castBarOverlay = plate.cast:CreateTexture()
function plate:ClearUnit()
    self.unit = nil
    self:SetScale(1)
    self:SetAlpha(1)
end
EllesmereNameplates_NS.plates = { nameplate1 = plate }
EllesmereNameplates_NS._castingPlates = { [plate] = true }
local ready, hiddenReady, haveCooldown, knownKick = false, true, true, true
EllesmereUI = assert(loadfile("EllesmereUIExtendNameplates/tests/border-mocks.lua"))()
UnitGUID = function() return nil end
UnitClassBase = function() return "MAGE" end
IsSpellKnown = function() return knownKick end
assert(loadfile("EllesmereUI_Kick.lua"))()
EllesmereUI.RefreshKickAbility()
C_Spell = { GetSpellCooldownDuration = function(spell)
    assert(spell == EllesmereUI.GetActiveKickSpell(), "wrong interrupt cooldown")
    if not haveCooldown then return nil end
    return { IsZero = function() return ready end }
end }
C_CurveUtil = { EvaluateColorValueFromBoolean = function(value, yes, no)
    -- The native boundary may consume an opaque boolean; addon Lua may not.
    if value == fixture.secret then value = hiddenReady end
    return value and yes or no
end }
function plate:ApplyCastColor(protected)
    self._kickProtected = protected
    local r, g, b = EllesmereUI.ComputeCastBarTint(
        { r = 0.1, g = 0.2, b = 0.9 }, { r = 0.8, g = 0.1, b = 0.1 })
    self.cast:GetStatusBarTexture():SetVertexColor(r, g, b, 1)
end
local restartCalls = 0
function plate:UpdateCast() restartCalls = restartCalls + 1 end
fixture.mocks.casting = { "Long cast", nil, nil, nil, nil, nil, nil, false, 123 }
local function Rule(name, state, opacity, scale, border)
    return { name = name, enabled = true, conditions = { castState = { [state] = true }, appearanceState = state },
        style = { castEnabled = true, castOpacityEnabled = true, castOpacity = opacity,
            scale = scale, borderSize = 0, castBorderEnabled = border, castBorderSize = 3,
            healthColorEnabled = false } }
end
local onCD = Rule("On cooldown", "interruptOnCD", 20, 120, true)
local available = Rule("Ready", "interruptible", 80, 150, false)
local protected = Rule("Protected", "uninterruptible", 60, 110, true)
onCD.style.castColorEnabled, onCD.style.castColor = true, { r = 0.1, g = 0.2, b = 0.9 }
available.style.castColorEnabled, available.style.castColor = true, { r = 0.8, g = 0.1, b = 0.1 }
protected.style.castColorEnabled, protected.style.castColor = true, { r = 0.6, g = 0.1, b = 0.8 }
-- Built-in color selections now imply Casting for appearances. An extension may
-- still explicitly require readable state knowledge, so transition tracking stays useful.
api.RegisterCondition("appearanceState", function(_, traits, expected) return traits.castColorState == expected end)
local function ColorRule(rule)
    local color = rule.style.castColor
    rule.style.castColorEnabled = false
    return { name = rule.name .. " color", enabled = true,
        conditions = { castState = rule.conditions.castState },
        style = { castEnabled = true, castColorEnabled = true, castColor = color,
            healthColorEnabled = false, borderSize = 0 } }
end
local colorRules = { ColorRule(onCD), ColorRule(available), ColorRule(protected) }
api.GetSettings().rules = { onCD, available, protected, colorRules[1], colorRules[2], colorRules[3] }
plate:ApplyCastColor(false)
addon.RefreshAll()
local function Near(actual, expected, label)
    assert(math.abs(actual - expected) < 0.00001,
        label .. ": expected " .. expected .. ", got " .. tostring(actual))
end
Near(plate.cast.alpha, 0.2, "initial cooldown opacity")
ready = true
assert(addon.FindRule(plate.unit) == available, "ready rule not selected")
plate:ApplyCastColor(false)
fixture.Flush()
Near(plate.cast.alpha, 0.8, "completion repaint must refresh ordinary opacity")
Near(plate.scale, 1.5, "completion repaint must refresh size")
local castBorder
for _, frame in ipairs(fixture.frames) do
    if frame.parent == plate.cast and frame.kind == "Frame" then castBorder = frame end
end
assert(castBorder and not castBorder.shown, "completion must hide CD border")

-- Count real ordinary applications and scheduling, not a duplicate rule engine.
local applications, scheduled = {}, 0
local realApply, realAfter = addon.ApplyCastStyle, C_Timer.After
addon.ApplyCastStyle = function(p, ...)
    applications[p] = (applications[p] or 0) + 1
    return realApply(p, ...)
end
C_Timer.After = function(delay, callback)
    scheduled = scheduled + 1
    return realAfter(delay, callback)
end
EllesmereNameplates_NS.RefreshCastOverlay = function(p)
    if p.ApplyCastColor then p:ApplyCastColor(p._kickProtected) end
end
local function ResetCounts() applications, scheduled = {}, 0 end
local function Dispatch(event, ...)
    for _, frame in ipairs(fixture.frames) do
        if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
end
local function Effects(opacity, scale, border, label)
    Near(plate.cast.alpha, opacity, label .. " opacity")
    Near(plate.scale, scale, label .. " size")
    assert(castBorder.shown == border, label .. " border")
end
ResetCounts()
for _ = 1, 20 do plate:ApplyCastColor(false) end
fixture.Flush()
assert(scheduled == 0 and not applications[plate], "stable repaint scheduled ordinary work")
local activePlates = EllesmereNameplates_NS._castingPlates
EllesmereNameplates_NS._castingPlates = {}
fixture.Fire("SPELL_UPDATE_COOLDOWN")
assert(scheduled == 0, "cooldown event without active casts scheduled work")
EllesmereNameplates_NS._castingPlates = activePlates

ready = false
ResetCounts()
for _ = 1, 20 do plate:ApplyCastColor(false) end
assert(scheduled == 1, "repaint burst must coalesce")
fixture.Flush()
assert(applications[plate] == 1, "transition applied more than once")
Effects(0.2, 1.2, true, "cooldown start")
ResetCounts()
for _ = 1, 20 do plate:ApplyCastColor(false) end
assert(scheduled == 0, "post-transition snapshot not advanced")

-- A second active protected cast and an idle plate must not refresh for kick CD.
local quiet = CreateFrame()
quiet.unit, quiet.health = "nameplate2", fixture.plate.health
local originalCasting = UnitCastingInfo
UnitCastingInfo = function(unit)
    if unit == quiet.unit then return "Protected", nil, nil, nil, nil, nil, nil, true, 456 end
    return originalCasting(unit)
end
local idle = CreateFrame()
idle.unit, idle.health = "nameplate3", fixture.plate.health
local castingWithQuiet = UnitCastingInfo
UnitCastingInfo = function(unit)
    if unit ~= idle.unit then return castingWithQuiet(unit) end
end
EllesmereNameplates_NS.plates.nameplate2 = quiet
EllesmereNameplates_NS.plates.nameplate3 = idle
EllesmereNameplates_NS._castingPlates[quiet] = true
addon.RefreshAll()
ready = true
ResetCounts()
for _ = 1, 20 do Dispatch("SPELL_UPDATE_COOLDOWN"); Dispatch("SPELL_UPDATE_USABLE") end
assert(scheduled == 1, "event burst must coalesce")
fixture.Flush()
Effects(0.8, 1.5, false, "event-only completion")
assert(applications[plate] == 1 and not applications[quiet] and not applications[idle],
    "cooldown events refreshed unchanged or idle plates")
ResetCounts()
fixture.Fire("SPELL_UPDATE_COOLDOWN")
assert(not applications[plate] and not applications[quiet], "stable cooldown event applied rules")
ready = false
fixture.Fire("SPELL_UPDATE_COOLDOWN")
Effects(0.2, 1.2, true, "event-only cooldown start")
plate.cast:SetAlpha(0.5)
Near(plate.cast.alpha, 0.1, "cooldown composes fresh engine alpha")
ready = true
plate:ApplyCastColor(false); fixture.Flush()
Near(plate.cast.alpha, 0.4, "completion preserves engine alpha ownership")
plate.cast:SetAlpha(1)
ready = false
plate:ApplyCastColor(false); fixture.Flush()

-- Active kick changes are observed after the shared lookup event listener.
knownKick = false
fixture.Fire("SPELLS_CHANGED")
Effects(0.8, 1.5, false, "interrupt removed")
knownKick = true
fixture.Fire("UNIT_PET", "player")
Effects(0.2, 1.2, true, "interrupt restored")
ResetCounts()
fixture.Fire("UNIT_PET", "party1")
assert(scheduled == 0, "unrelated pet change scheduled work")

fixture.mocks.casting[8] = true
ResetCounts()
fixture.Fire("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "nameplate1")
Effects(0.6, 1.1, true, "protected transition")
assert(applications[plate] == 1 and not applications[quiet], "interrupt change must target its unit")
ready = true
fixture.Fire("SPELL_UPDATE_COOLDOWN")
Effects(0.6, 1.1, true, "protected precedence")
fixture.mocks.casting[8] = false
fixture.Fire("UNIT_SPELLCAST_INTERRUPTIBLE", "nameplate1")
Effects(0.8, 1.5, false, "interruptible transition")
ResetCounts()
fixture.Fire("UNIT_SPELLCAST_INTERRUPTIBLE", "party1")
assert(scheduled == 0, "unrelated interruptibility event scheduled work")

ready = fixture.secret
plate:ApplyCastColor(false)
fixture.Flush()
Effects(1, 1, false, "explicit readable-state predicate rejects opaque cooldown")
Near(fill.vertexColor[1], 0.8, "opaque ready cooldown still renders native ready color")
hiddenReady = false
ResetCounts()
plate:ApplyCastColor(false)
fixture.Flush()
Near(fill.vertexColor[3], 0.9, "opaque cooldown still renders native CD color")
assert(scheduled == 0 and not applications[plate], "opaque stable state schedules ordinary rules")
ready = true
plate:ApplyCastColor(false); fixture.Flush()
Effects(0.8, 1.5, false, "cooldown readable again")
fixture.mocks.casting[8] = fixture.secret
plate:ApplyCastColor(false); fixture.Flush()
Effects(1, 1, false, "explicit readable-state predicate rejects opaque interrupt flag")
fixture.mocks.casting[8] = nil
plate:ApplyCastColor(false); fixture.Flush()
Effects(1, 1, false, "explicit readable-state predicate rejects unavailable flag")
fixture.mocks.casting[8] = false
plate:ApplyCastColor(false); fixture.Flush()
fixture.mocks.secretBoolean = true
fixture.mocks.casting[8] = true
plate:ApplyCastColor(true); fixture.Flush()
Effects(1, 1, false, "explicit readable-state predicate rejects secret protection")
Near(fill.vertexColor[1], 0.6, "secret boolean protection retains native palette")
fixture.mocks.secretBoolean = nil
fixture.mocks.casting[8] = false
haveCooldown = false
plate:ApplyCastColor(false); fixture.Flush()
Effects(0.8, 1.5, false, "missing cooldown preserves EUI normal fallback")
haveCooldown, ready = true, false
plate:ApplyCastColor(false); fixture.Flush()
Effects(0.2, 1.2, true, "cooldown returns")

-- Snapshot must be the one used for rules even if an extension changes readiness.
local flip = true
api.RegisterCondition("flipKick", function()
    if flip then ready, flip = true, false end
    return true
end)
onCD.conditions.flipKick = true
api.Refresh(); fixture.Flush()
Effects(0.2, 1.2, true, "rule snapshot precedes extension mutation")
plate:ApplyCastColor(false); fixture.Flush()
Effects(0.8, 1.5, false, "repaint catches mutation after rule snapshot")
onCD.conditions.flipKick = nil
ResetCounts()
api.Refresh(); fixture.Flush()
ResetCounts()
plate:ApplyCastColor(false); fixture.Flush()
assert(scheduled == 0, "explicit refresh left stale transition cache")

-- A pending transition must not leak through pool release or frame reassignment.
ready = false
plate:ApplyCastColor(false)
plate:ClearUnit()
ResetCounts()
fixture.Flush()
Effects(1, 1, false, "pool release")
assert(not applications[plate], "released plate consumed pending work")
plate.unit = "nameplate1"
api.Refresh(); fixture.Flush()
Effects(0.2, 1.2, true, "same-token reuse")
ready = true
plate:ApplyCastColor(false)
plate.unit = "nameplate4"
ResetCounts()
fixture.Flush()
assert(not applications[plate], "pending transition crossed unit reassignment")
api.Refresh(); fixture.Flush()
Effects(0.8, 1.5, false, "reassigned plate refresh")
plate.unit = "nameplate1"
fixture.mocks.casting = nil
fixture.Fire("UNIT_SPELLCAST_STOP", "nameplate1")
Effects(1, 1, false, "cast end")
fixture.mocks.casting = { "Next cast", nil, nil, nil, nil, nil, nil, false, 123 }
fixture.Fire("UNIT_SPELLCAST_START", "nameplate1")
Effects(0.8, 1.5, false, "next cast")
available.enabled = false
api.Refresh(); fixture.Flush()
Effects(1, 1, false, "winning rule disabled")
onCD.enabled, protected.enabled = false, false
for _, rule in ipairs(colorRules) do rule.enabled = false end
api.Refresh(); fixture.Flush()
ResetCounts()
plate:ApplyCastColor(false)
fixture.Fire("SPELL_UPDATE_COOLDOWN")
assert(scheduled == 0, "disabled state rules still monitor transitions")
available.enabled = true
for _, rule in ipairs(colorRules) do rule.enabled = true end
api.Refresh(); fixture.Flush()
api.GetSettings().enabled = false
api.Refresh(); fixture.Flush()
Effects(1, 1, false, "addon disable")
ResetCounts()
ready = false
plate:ApplyCastColor(false)
fixture.Fire("SPELL_UPDATE_COOLDOWN")
assert(scheduled == 0, "disabled addon schedules transitions")
api.GetSettings().enabled = true
onCD.enabled = true
api.Refresh(); fixture.Flush()
Effects(0.2, 1.2, true, "addon reenabled")
assert(restartCalls == 0, "cooldown refresh restarted a cast")
print("PASS: cooldown start/completion, kick and protection changes, opacity/size/border, targeted coalescing, secret native rendering, snapshots and restoration")
