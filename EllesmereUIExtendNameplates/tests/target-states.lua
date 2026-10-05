-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("traits")
local api, addon, mocks = f.api, f.namespace, f.mocks
local checks = 0
local function Check(value, label)
    checks = checks + 1
    assert(value, label)
end
local function Near(actual, expected, label)
    Check(math.abs(actual - expected) < 0.00001,
        label .. ": expected " .. expected .. ", got " .. tostring(actual))
end
local selectedUnit = "nameplate1"
UnitIsUnit = function(unit, other)
    if mocks.target ~= nil then return mocks.target end
    return other == "target" and UnitExists("target") == true and unit == selectedUnit
end
local plate, other = f.plate, CreateFrame()
other.unit, other.health = "nameplate2", plate.health
EllesmereNameplates_NS.plates.nameplate2 = other
local function Rule(name, target, scale, opacity)
    return { name = name, enabled = true, conditions = { target = target },
        style = { scale = scale, opacity = opacity, healthEnabled = false, borderSize = 0 } }
end
local current = Rule("Current", { yes = true }, 150, 80)
local noncurrent = Rule("Other", { no = true }, 110, 50)
local untargeted = Rule("No selected target", { none = true }, 90, 100)
api.GetSettings().rules = { current, noncurrent, untargeted }
mocks.targetExists = true
addon.RefreshAll()
Near(plate:GetScale(), 1.5, "current target size")
Near(other:GetScale(), 1.1, "non-target size with a selected target")
Near(plate:GetAlpha(), 0.8, "current target opacity")
Near(other:GetAlpha(), 0.5, "non-target opacity")
selectedUnit = "nameplate2"
f.Fire("PLAYER_TARGET_CHANGED")
Near(plate:GetScale(), 1.1, "retargeting former target to non-target")
Near(other:GetScale(), 1.5, "retargeting new current target")
mocks.targetExists = false
f.Fire("PLAYER_TARGET_CHANGED")
Near(plate:GetScale(), 0.9, "clearing target applies explicit no-target appearance")
Near(other:GetScale(), 0.9, "clearing target applies no-target appearance to every plate")
Near(plate:GetAlpha(), 1, "clearing target removes non-target opacity")
untargeted.enabled = false
api.Refresh(); f.Flush()
Near(plate:GetScale(), 1, "no target and no no-target rule restores EUI appearance")
Near(other:GetScale(), 1, "Not current target must not apply without a selected target")

-- Exercise the same filter for ordinary effects and cast-color candidates.
mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, f.secret, f.secret }
local probe = Rule("Filter probe", {}, 125, 100)
probe.style.castEnabled, probe.style.castColorEnabled = true, true
api.GetSettings().rules = { probe }
local function Match(selection, exists, relation, expected, label)
    probe.conditions = { target = selection }
    mocks.targetExists, mocks.target = exists, relation
    Check((addon.FindRule("nameplate1") == probe) == expected, label .. " ordinary")
    Check((addon.FindCastColorOverrides("nameplate1").interruptible ~= nil) == expected, label .. " cast colors")
end
for _, selection in ipairs({ "yes", { yes = true } }) do
    Match(selection, true, true, true, "current target")
    Match(selection, true, false, false, "current rejects another unit")
    Match(selection, false, false, false, "current requires a selected target")
    Match(selection, f.secret, true, false, "current rejects unknown target existence")
end
for _, selection in ipairs({ "no", { no = true } }) do
    Match(selection, true, false, true, "non-current requires another selected target")
    Match(selection, true, true, false, "non-current rejects selected unit")
    Match(selection, false, false, false, "non-current rejects no-target state")
    Match(selection, f.secret, false, false, "non-current rejects unknown target existence")
    Match(selection, true, f.secret, false, "non-current rejects unknown unit relation")
end
for _, selection in ipairs({ "none", { none = true } }) do
    Match(selection, false, false, true, "explicit no target")
    Match(selection, false, f.secret, true, "no target needs no readable relation")
    Match(selection, true, false, false, "no target rejects other units while targeting")
    Match(selection, true, true, false, "no target rejects current target")
    Match(selection, f.secret, false, false, "no target rejects unknown existence")
end
Match({ yes = true, no = true }, true, false, true, "both existing-target states")
Match({ yes = true, no = true }, false, false, false, "both existing-target states still require a target")
Match({ no = true, none = true }, false, false, true, "noncurrent OR no-target recreates older behavior")
Match({ no = true, none = true }, true, true, false, "combined alternatives still exclude current unit")
Match({ yes = true, none = true }, false, false, true, "current OR no target")
Match({ yes = true, no = true, none = true }, false, false, true, "all known states include no target")
Match({}, false, false, true, "empty target filter is Any")
Match("any", f.secret, f.secret, true, "Any imposes no target restriction")
Match({ none = true }, false, false, true, "no target before other AND filter")
probe.conditions.reaction = { friendly = true }
Check(addon.FindRule("nameplate1") == nil, "target states still AND with reaction")
Check(next(addon.FindCastColorOverrides("nameplate1")) == nil, "reaction rejects no-target color candidate")
print("PASS: " .. checks .. " target-state, OR/AND, legacy, restricted-value and target-change checks")
