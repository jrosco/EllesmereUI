-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("traits")
local api, addon, checks = f.api, f.namespace, 0
local function Check(value, label) checks = checks + 1; assert(value, label) end
local function Near(actual, expected, label) Check(math.abs(actual - expected) < 0.00001, label) end
local combat, kind, difficulty = false, "none", 0
local combatCalls, instanceCalls = 0, 0
function UnitAffectingCombat(unit)
    Check(unit == "player", "combat condition reads the player, never the nameplate unit")
    combatCalls = combatCalls + 1; return combat
end
function GetInstanceInfo() instanceCalls = instanceCalls + 1; return "Test Zone", kind, difficulty end
EllesmereUI = EllesmereUI or {}
local function Rule(name, c, scale)
    return { name = name, enabled = true, conditions = c,
        style = { healthEnabled = false, borderSize = 0, scale = scale or 120, castEnabled = true,
            castColorEnabled = true, castColor = { r = 0.2, g = 0.7, b = 0.9 } } }
end
local probe = Rule("Context", {})
api.GetSettings().rules = { probe }
f.mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, f.secret, 123 }
local function Match(c, expected, label)
    probe.conditions = c
    Check((addon.FindRule("nameplate1") == probe) == expected, label .. " ordinary")
    Check((addon.FindCastColorOverrides("nameplate1").interruptible ~= nil) == expected, label .. " cast palette")
end
Match({}, true, "old rules remain unrestricted")
Check(combatCalls == 0 and instanceCalls == 0, "empty context filters do not query context APIs")
Match({ playerCombat = { inCombat = true } }, false, "in-combat rejects player out of combat")
Match({ playerCombat = { outOfCombat = true } }, true, "out-of-combat selection")
combat = true
Match({ playerCombat = { inCombat = true } }, true, "player in combat")
Match({ playerCombat = { outOfCombat = true } }, false, "out-of-combat rejects combat")
Match({ playerCombat = { inCombat = true, outOfCombat = true } }, true, "both combat states OR")
combat = f.secret
Match({ playerCombat = {} }, true, "empty combat remains Any with restricted player data")
Match({ playerCombat = { inCombat = true, outOfCombat = true } }, false, "unknown selected combat state fails closed")
local nativeCombat = UnitAffectingCombat
UnitAffectingCombat = function() error("unavailable") end
Match({ playerCombat = { outOfCombat = true } }, false, "API error is not assumed to mean out of combat")
UnitAffectingCombat = nativeCombat
combat = false

for _, case in ipairs({ { "none", 0, "world" }, { "party", 1, "dungeon" }, { "raid", 14, "raid" },
    { "pvp", 0, "battleground" }, { "arena", 0, "arena" }, { "scenario", 12, "scenario" },
    { "scenario", 208, "delve" }, { "delve", 208, "delve" } }) do
    kind, difficulty = case[1], case[2]
    Match({ instanceType = { [case[3]] = true } }, true, "instance classification " .. case[3])
    if case[3] ~= "world" then Match({ instanceType = { world = true } }, false, "instance is not open world") end
end
kind, difficulty = "scenario", 208
C_PartyInfo = { IsDelveInProgress = function() error("do not use in-progress flag to classify completed delves") end }
Match({ instanceType = { delve = true } }, true, "completed delve retains its separate type")
Match({ instanceType = { scenario = true } }, false, "delve never leaks into scenario selection")
Match({ instanceType = { scenario = true, delve = true } }, true, "scenario/delve OR")
kind, difficulty = "party", 1
combat = true
Match({ playerCombat = { inCombat = true }, instanceType = { dungeon = true }, target = { yes = true } }, true,
    "combat, instance and unit filters AND")
Match({ playerCombat = { outOfCombat = true }, instanceType = { dungeon = true } }, false, "combat mismatch rejects dungeon")
Match({ playerCombat = { inCombat = true }, instanceType = { raid = true } }, false, "instance mismatch rejects combat")
kind = f.secret
Match({ instanceType = {} }, true, "empty instance remains Any under restriction")
Match({ instanceType = { dungeon = true } }, false, "restricted instance type fails closed")
kind, difficulty = "scenario", f.secret
Match({ instanceType = { scenario = true } }, false, "unknown difficulty cannot distinguish scenario from delve")
kind = "unknown"
Match({ instanceType = { world = true } }, false, "unrecognized instance is not open world")

-- Events reevaluate ordinary appearance, with normal first-match priority.
local inside = Rule("Combat dungeon", { playerCombat = { inCombat = true }, instanceType = { dungeon = true } }, 150)
local outside = Rule("Out of combat", { playerCombat = { outOfCombat = true } }, 110)
api.GetSettings().rules = { inside, outside }
kind, difficulty, combat = "party", 1, false
api.Refresh(); f.Flush()
Near(f.plate:GetScale(), 1.1, "out-of-combat appearance")
combat = true
f.Fire("PLAYER_REGEN_DISABLED")
Near(f.plate:GetScale(), 1.5, "combat-start appearance transition")
kind = "none"
f.Fire("ZONE_CHANGED_NEW_AREA")
Near(f.plate:GetScale(), 1, "leaving matching instance restores EUI appearance")
kind = "party"
f.Fire("PLAYER_ENTERING_WORLD")
Near(f.plate:GetScale(), 1.5, "entering matching instance applies rule")
combat = false
f.Fire("PLAYER_REGEN_ENABLED")
Near(f.plate:GetScale(), 1.1, "combat-end appearance transition")

-- Saved/imported Retail-only selections stay intact but are blocked on Forever.
api.GetSettings().rules = { probe }
EllesmereUI.IS_FOREVER = true
for _, value in ipairs({ "arena", "scenario", "delve" }) do
    kind, difficulty = value == "delve" and "scenario" or value, value == "delve" and 208 or 12
    Match({ instanceType = { [value] = true } }, false, "Forever blocks " .. value)
    Check(not api.SupportsInstanceType(value), "Forever editor capability " .. value)
end
kind, difficulty = "pvp", 0
Match({ instanceType = { battleground = true } }, true, "Forever battleground")
kind = "party"
Match({ instanceType = { dungeon = true, delve = true } }, true, "supported choice in a mixed Forever selection")
kind = "none"
Match({ instanceType = {} }, true, "Forever Any instance")
Check(not api.SupportsInstanceType("unknown"), "unknown instance option never supported")
EllesmereUI.IS_FOREVER = false
Check(api.ValidateRuleConditions({ playerCombat = { inCombat = true, outOfCombat = true }, instanceType = { raid = true, delve = true } }),
    "new condition maps validate")
Check(not api.ValidateRuleConditions({ playerCombat = { unknown = true } })
    and not api.ValidateRuleConditions({ instanceType = { party = true } }), "unknown/category API keys rejected")
print("PASS: " .. checks .. " player combat/instance OR-AND, API gating, palette filters, restrictions, events and Forever capability checks")
