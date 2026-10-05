-- Run from the repository root with Lua or fengari.
local fixture = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("traits")
local api, namespace, mocks = fixture.api, fixture.namespace, fixture.mocks
local plate = EllesmereNameplates_NS.plates.nameplate1
local cases = 0
local function Equal(actual, expected, label)
    cases = cases + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function Rule(name, selection, scale)
    return { name = name, enabled = true,
        conditions = { castState = selection, snapshotPredicate = name },
        style = { scale = scale or 150, borderSize = 0, castEnabled = true,
            castColorEnabled = true, castColor = { r = 0.9, g = 0.1, b = 0.2 } } }
end
local paints = {}
local painter = namespace.ApplyCastStyle
namespace.ApplyCastStyle = function(currentPlate, style, conditions, colors)
    paints[currentPlate.unit] = { style = style, conditions = conditions, colors = colors }
    painter(currentPlate, style, conditions, colors)
end
mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, false, 123 }
local calls = 0
assert(api.RegisterCondition("snapshotPredicate", function()
    calls = calls + 1
    return calls == 1
end))
local probe = Rule("First call only", { casting = true })
api.GetSettings().rules = { probe }
namespace.RefreshAll()
-- The original renderer applies scale but rejects the same rule's palette after
-- invoking the callback again. Check both real render effects before the count.
Equal(plate:GetScale(), 1.5, "first-call predicate applies scale")
Equal(paints.nameplate1.colors.interruptible and paints.nameplate1.colors.interruptible.rule,
    probe, "same refresh retains first-call predicate's color (callbacks=" .. calls .. ")")
Equal(calls, 1, "one callback in an actual rendering refresh")
Equal(plate.cast:GetStatusBarTexture().vertexColor[1], 0.9, "real cast fill receives shared color")
namespace.RefreshAll()
Equal(calls, 2, "second rendering refresh reevaluates predicate")
Equal(plate:GetScale(), 1, "second false result restores scale")
Equal(next(paints.nameplate1.colors), nil, "second false result rejects colors")
Equal(plate.cast:GetStatusBarTexture().vertexColor[1], 0.2, "second refresh restores engine fill")

local function Reset(rules, callback)
    for key in pairs(mocks) do mocks[key] = nil end
    mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, false, 123 }
    EllesmereNameplates_NS.plates = { nameplate1 = plate }
    EllesmereNameplates_NS.friendlyPlates = {}
    api.GetSettings().enabled = true
    api.GetSettings().rules = rules
    paints = {}
    calls = 0
    assert(api.RegisterCondition("snapshotPredicate", function(unit, traits, expected, rule)
        calls = calls + 1
        return callback(unit, traits, expected, rule)
    end))
end

-- Callback arguments and pure predicates keep their ordinary matching contract.
probe = Rule("Pure", { casting = true })
local capturedTraits
Reset({ probe }, function(unit, traits, expected, rule)
    Equal(unit, "nameplate1", "predicate unit argument")
    Equal(expected, "Pure", "predicate expected argument")
    Equal(rule, probe, "predicate rule argument")
    Equal(traits.castState, "casting", "predicate readable traits argument")
    capturedTraits = traits
    return true
end)
namespace.RefreshAll()
Equal(calls, 1, "pure predicate shared between passes")
Equal(paints.nameplate1.style, probe.style, "pure ordinary winner")
Equal(paints.nameplate1.colors.uninterruptible.rule, probe, "pure broad color winner")
Equal(capturedTraits.castColorState, "interruptible", "predicate retains ordinary state knowledge")

-- A later color rule is evaluated even after ordinary first-match resolution.
local ready = Rule("Ready", { interruptible = true }, 125)
local cooldown = Rule("Cooldown", { interruptOnCD = true }, 175)
local broad = Rule("Broad", { casting = true }, 190)
local byRule = {}
Reset({ ready, cooldown, broad }, function(_, _, _, rule)
    byRule[rule] = (byRule[rule] or 0) + 1
    return true
end)
namespace.RefreshAll()
Equal(plate:GetScale(), 1.25, "ordinary first-match priority")
Equal(paints.nameplate1.colors.interruptible.rule, ready, "first ready color remains winner")
Equal(paints.nameplate1.colors.interruptOnCD.rule, cooldown, "lower priority fills cooldown state")
Equal(paints.nameplate1.colors.uninterruptible.rule, broad, "broad fills only unfilled state")
Equal(byRule[ready], 1, "ordinary winner shared predicate count")
Equal(byRule[cooldown], 1, "color-only lower rule predicate count")
Equal(byRule[broad], 1, "broad lower rule predicate count")

-- Color-state choices imply Casting, while color masks remain independently narrow.
probe = Rule("Secret state", { interruptible = true })
Reset({ probe }, function() return true end)
mocks.casting[8] = fixture.secret
namespace.RefreshAll()
Equal(plate:GetScale(), 1.5, "secret state implies ordinary Casting scale")
Equal(paints.nameplate1.style, probe.style, "secret state retains other appearances")
Equal(paints.nameplate1.colors.interruptible.rule, probe, "secret state keeps native color candidate")
Equal(paints.nameplate1.colors.uninterruptible, nil, "secret state respects narrow mask")
Equal(calls, 1, "secret state shares one predicate between appearance and color paths")
namespace.RefreshAll()
Equal(calls, 2, "secret color path reevaluates next refresh")
mocks.casting[8] = nil
namespace.RefreshAll()
Equal(paints.nameplate1.style, probe.style, "unavailable state still permits active-cast appearances")
Equal(paints.nameplate1.colors.interruptible.rule, probe, "unavailable state retains native candidate")
Equal(calls, 3, "unavailable state fresh callback")

-- Rejected cast paths and readable condition groups must remain lazy.
for _, selection in ipairs({ { interruptible = true }, { casting = true }, { channel = true } }) do
    probe = Rule("Inactive", selection)
    Reset({ probe }, function() error("irrelevant callback must not run") end)
    mocks.casting = {}
    namespace.RefreshAll()
    Equal(calls, 0, "no-cast rejection skips custom predicate")
    Equal(next(paints.nameplate1.colors), nil, "inactive cast supplies no palette")
end
probe = Rule("Wrong cast kind", { channel = true })
Reset({ probe }, function() error("wrong-kind callback must not run") end)
namespace.RefreshAll()
Equal(calls, 0, "active wrong cast kind skips callback in both paths")
probe.conditions.castState = { interruptible = true, channel = true }
namespace.RefreshAll()
Equal(calls, 1, "OR cast selection allows eligible path and contains error once")
Equal(next(paints.nameplate1.colors), nil, "error from newly relevant predicate fails closed")

probe = Rule("Condition groups", { interruptible = true, uninterruptible = true })
probe.conditions.unitType = { player = true, npc = true }
probe.conditions.reaction = { friendly = true, enemy = true }
probe.conditions.target = { yes = true, no = true }
Reset({ probe }, function() return true end)
namespace.RefreshAll()
Equal(calls, 1, "OR within condition groups remains eligible")
Equal(paints.nameplate1.colors.interruptible.rule, probe, "multi-state mask ready candidate")
Equal(paints.nameplate1.colors.uninterruptible.rule, probe, "multi-state mask protected candidate")
Equal(paints.nameplate1.colors.interruptOnCD, nil, "multi-state mask leaves cooldown unfilled")
probe.conditions.classification = { elite = true }
namespace.RefreshAll()
Equal(calls, 1, "AND between groups rejects before custom predicate")
Equal(next(paints.nameplate1.colors), nil, "readable group rejects both paths")
probe.conditions.classification = nil
probe.conditions.spellSchool = { frost = true }
namespace.RefreshAll()
Equal(calls, 1, "spell school rejection stays lazy")

-- Restricted, nonboolean, false and throwing callbacks are cached as rejection.
local rejected = {
    { "false", function() return false end },
    { "nil", function() return nil end },
    { "number", function() return 1 end },
    { "string", function() return "true" end },
    { "table", function() return {} end },
    { "secret sentinel", function() return fixture.secret end },
    { "secret boolean", function() mocks.secretBoolean = true; return true end },
    { "exception", function() error("snapshot predicate failure") end },
}
for _, test in ipairs(rejected) do
    probe = Rule("Rejected " .. test[1], { casting = true })
    Reset({ probe }, test[2])
    local ok = pcall(namespace.RefreshAll)
    mocks.secretBoolean = nil
    Equal(ok, true, test[1] .. " does not escape refresh")
    Equal(calls, 1, test[1] .. " evaluated once despite two matching passes")
    Equal(plate:GetScale(), 1, test[1] .. " rejects ordinary effects")
    Equal(next(paints.nameplate1.colors), nil, test[1] .. " rejects color effects")
    namespace.RefreshAll()
    mocks.secretBoolean = nil
    Equal(calls, 2, test[1] .. " reevaluates in next refresh")
end

-- Multiple custom conditions remain ANDed; no iteration order is assumed.
probe = Rule("Custom AND", { casting = true })
probe.conditions.snapshotSecond = true
local secondCalls = 0
assert(api.RegisterCondition("snapshotSecond", function()
    secondCalls = secondCalls + 1
    return true
end))
Reset({ probe }, function() return true end)
namespace.RefreshAll()
Equal(calls, 1, "first custom condition shared")
Equal(secondCalls, 1, "second custom condition shared")
assert(api.RegisterCondition("snapshotSecond", function() return false end))
namespace.RefreshAll()
Equal(next(paints.nameplate1.colors), nil, "false separate custom group rejects palette")
Equal(plate:GetScale(), 1, "false separate custom group rejects ordinary effects")
probe.conditions.snapshotSecond = nil
probe.conditions.unregisteredCondition = true
namespace.RefreshAll()
Equal(next(paints.nameplate1.colors), nil, "unknown condition still fails closed")

-- Refresh-local results do not leak between hostile and friendly plates.
local otherPlate = CreateFrame()
otherPlate.unit = "nameplate2"
otherPlate.health = CreateFrame()
function otherPlate.health:GetStatusBarColor() return 0.8, 0.1, 0.1, 1 end
function otherPlate.health:SetStatusBarColor() end
function otherPlate.health:GetStatusBarTexture() return { GetTexture = function() return "base" end } end
function otherPlate.health:SetStatusBarTexture() end
probe = Rule("Unit isolation", { casting = true })
local unitCalls = {}
Reset({ probe }, function(unit)
    unitCalls[unit] = (unitCalls[unit] or 0) + 1
    return unit == "nameplate1"
end)
EllesmereNameplates_NS.friendlyPlates = { nameplate2 = otherPlate }
namespace.RefreshAll()
Equal(unitCalls.nameplate1, 1, "hostile plate predicate count")
Equal(unitCalls.nameplate2, 1, "friendly plate predicate count")
Equal(plate:GetScale(), 1.5, "hostile unit's true result applies")
Equal(otherPlate:GetScale(), 1, "friendly unit's false result stays isolated")
Equal(paints.nameplate1.colors.interruptible.rule, probe, "hostile palette isolated")
Equal(next(paints.nameplate2.colors), nil, "friendly palette isolated")
namespace.RefreshAll()
Equal(unitCalls.nameplate1, 2, "hostile plate fresh second refresh")
Equal(unitCalls.nameplate2, 2, "friendly plate fresh second refresh")

-- Rules, predicate registration and profiles are all fresh on later refreshes.
probe = Rule("Mutable", { casting = true })
Reset({ probe }, function(_, _, expected) return expected == "Mutable" end)
namespace.RefreshAll()
probe.conditions.snapshotPredicate = "Changed"
namespace.RefreshAll()
Equal(calls, 2, "same rule table is reevaluated after condition edit")
Equal(plate:GetScale(), 1, "condition edit observed")
Equal(next(paints.nameplate1.colors), nil, "condition edit rejects colors")
assert(api.RegisterCondition("snapshotPredicate", function() calls = calls + 1; return true end))
namespace.RefreshAll()
Equal(calls, 3, "predicate replacement observed")
Equal(plate:GetScale(), 1.5, "new predicate applies same rule")
assert(api.CreateProfile("Snapshot regression"))
local newRule = Rule("New profile", { casting = true }, 120)
api.GetSettings().rules = { newRule }
namespace.RefreshAll()
Equal(calls, 4, "new profile fresh callback")
Equal(plate:GetScale(), 1.2, "new profile ordinary rule observed")
Equal(paints.nameplate1.colors.interruptible.rule, newRule, "new profile palette observed")
assert(api.SelectProfile("Default"))
namespace.RefreshAll()
Equal(calls, 5, "switching back to prior profile reevaluates")
Equal(plate:GetScale(), 1.5, "prior profile observed freshly")

-- Standalone selectors and diagnostics do not borrow any rendering snapshot.
Reset({ probe }, function() return true end)
local selected, index, traits = namespace.FindRule("nameplate1")
Equal(selected, probe, "standalone ordinary rule return")
Equal(index, 1, "standalone ordinary index return")
Equal(traits.castState, "casting", "standalone ordinary traits return")
Equal(namespace.FindCastColorOverrides("nameplate1", traits).interruptible.rule, probe,
    "standalone color selector accepts existing traits")
Equal(namespace.FindCastColorOverrides("nameplate1").interruptible.rule, probe,
    "standalone color selector reads fresh traits")
Equal(calls, 3, "separate selector calls get separate evaluations")
local originalPrint, output = print, {}
print = function(text) output[#output + 1] = text end
local ok, err = pcall(SlashCmdList.EXTENDNAMEPLATES, "cast")
print = originalPrint
assert(ok, tostring(err))
Equal(calls, 5, "diagnostic selectors evaluate fresh")
Equal(table.concat(output, "\n"):find("Cast color interruptible=rule 1", 1, true) ~= nil,
    true, "diagnostic color report remains available")
api.GetSettings().enabled = false
namespace.RefreshAll()
Equal(calls, 5, "disabled addon skips predicate evaluation")
Equal(plate:GetScale(), 1, "disabled addon restores ordinary style")
Equal(next(paints.nameplate1.colors), nil, "disabled addon clears palette")
print("PASS: " .. cases .. " predicate snapshot checks")
