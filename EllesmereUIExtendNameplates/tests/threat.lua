-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("traits")
local api, addon, mocks, secret = f.api, f.namespace, f.mocks, f.secret
local checks, detailCalls, roleCalls, rosterCalls = 0, {}, 0, 0
local held, roles, live, aliases, raid, members, current, fail = {}, {}, {}, {}, false, 0, false, false
UnitExists = function(unit) return live[unit] == true end
UnitIsUnit = function(unit, other)
    if other == "target" then return current and unit == "nameplate1" end
    if other == "player" then return unit == "player" or aliases[unit] == "player" end
    return unit == other
end
UnitDetailedThreatSituation = function(participant, mob)
    detailCalls[#detailCalls + 1] = { participant, mob }
    if fail then error("restricted API pairing") end
    -- A readable/pinned numeric status is not reliable proof of the holder.
    return held[participant], 3, secret, secret, secret
end
UnitThreatSituation = function() error("must not infer aggro from pinned situation status") end
EllesmereUI = { UnitEffectiveRole = function(unit)
    roleCalls = roleCalls + 1
    return roles[unit]
end }
UnitGroupRolesAssigned = function(unit) roleCalls = roleCalls + 1; return roles[unit] end
IsInRaid = function() return raid end
GetNumGroupMembers = function() rosterCalls = rosterCalls + 1; return members end
GetNumSubgroupMembers = function() rosterCalls = rosterCalls + 1; return members end
local rule = { name = "Threat probe", enabled = true, conditions = {},
    style = { castEnabled = true, castColorEnabled = true, castColor = { r = 0.9, g = 0.1, b = 0.2 } } }
api.GetSettings().rules = { rule }
local function Check(value, label)
    checks = checks + 1
    assert(value, label)
end
local function Reset()
    held, roles, live, aliases = {}, {}, { player = true, nameplate1 = true, target = true }, {}
    raid, members, current, fail = false, 0, false, false
    detailCalls, roleCalls, rosterCalls = {}, 0, 0
    for key in pairs(mocks) do mocks[key] = nil end
    rule.enabled = true
    rule.conditions = {}
    api.GetSettings().enabled = true
end
local function Match(selection, expected, label)
    rule.conditions.threat = selection
    local ok, winner = pcall(addon.FindRule, "nameplate1")
    Check(ok, label .. " must not throw")
    Check((winner == rule) == expected, label .. " ordinary matching")
    local colors = addon.FindCastColorOverrides("nameplate1")
    Check((colors.interruptible ~= nil) == expected, label .. " cast-color matching")
end
Reset()
held.player, roles.player = true, "TANK"
Match({ tank = true }, true, "player tank holds aggro")
Match({ nonTank = true }, false, "player tank is not non-tank")
Match({ me = true }, true, "tank aggro is also on me")
roles.player = "DAMAGER"
Match({ nonTank = true }, true, "player damage holds aggro")
Match({ tank = true }, false, "player damage is not tank")
roles.player = "HEALER"
Match({ nonTank = true }, true, "player healer holds aggro")
roles.player = secret
Match({ tank = true }, false, "secret holder role rejects tank")
Match({ nonTank = true }, false, "secret holder role rejects non-tank")
Match({ me = true }, true, "on me does not require readable role")
roles.player = "NONE"
Match({ nonTank = true }, false, "unassigned role is not proof of non-tank")
Match({ me = true }, true, "unassigned player can still hold aggro")
Reset()
held.player, roles.player = false, "DAMAGER"
held.party1, roles.party1, live.party1, members = true, "TANK", true, 1
Match({ tank = true }, true, "another tank holds aggro")
Match({ nonTank = true }, false, "my damage role does not classify holder")
Match({ me = true }, false, "another tank is not on me")
roles.player, roles.party1 = "TANK", "DAMAGER"
Match({ nonTank = true }, true, "non-tank holds while I am tank")
Match({ tank = true }, false, "my tank role does not classify holder")
roles.party1 = "HEALER"
Match({ nonTank = true }, true, "another healer holds aggro")
Match({ tank = true, nonTank = true }, true, "choices within threat OR")
rule.conditions.reaction = { friendly = true }
Match({ nonTank = true }, false, "threat still ANDs with reaction")
rule.conditions.reaction = nil
rule.conditions.target = { yes = true }
Match({ nonTank = true }, false, "threat still ANDs with current-target requirement")
current = true
Match({ nonTank = true }, true, "holder on selected enemy")
Check(detailCalls[#detailCalls][2] == "target", "selected enemy should use target API pairing")
Reset()
-- An enemy's temporary spell target is not necessarily its actual aggro holder.
live.nameplate1target, roles.nameplate1target, held.nameplate1target = true, "HEALER", false
held.player, held.party1, roles.party1, live.party1, members = false, true, "TANK", true, 1
Match({ tank = true }, true, "actual tank beats temporary healer spell target")
Match({ nonTank = true }, false, "temporary spell target does not imply non-tank threat")
held.nameplate1target = true
Match({ nonTank = true }, true, "target candidate accepted only after detailed confirmation")
Reset()
raid, members = true, 2
held.player, held.raid1, held.raid2 = false, false, true
live.raid1, live.raid2, roles.raid2 = true, true, "TANK"
Match({ tank = true }, true, "raid holder lookup")
roles.raid2 = "DAMAGER"
Match({ nonTank = true }, true, "raid non-tank holder")
aliases.raid2, roles.raid2, held.player = "player", "TANK", secret
Match({ tank = true, me = true }, true, "readable raid alias confirms player holder")
Reset()
held.player, live.pet, held.pet, roles.pet = false, true, true, "NONE"
Match({ nonTank = true }, false, "unknown pet role is not guessed")
Reset()
held.player, live.party1, held.party1, roles.party1, members = secret, true, secret, "TANK", 1
Match({ tank = true }, false, "secret detailed flags cannot classify holder")
Match({ nonTank = true }, false, "secret detailed flags cannot infer non-tank")
Match({ me = true }, false, "secret player flag cannot match on me")
held.player = nil
Match({ me = true }, false, "missing threat table is unknown")
held.player = 3
Match({ me = true }, false, "numeric pinned status is not a boolean holder flag")
fail = true
Match({ tank = true, nonTank = true, me = true }, false, "API errors fail closed")
Reset()
held.player = true
roles.player = "TANK"
local roleGetter = EllesmereUI.UnitEffectiveRole
EllesmereUI.UnitEffectiveRole = nil
Match("tank", true, "assigned-role fallback and scalar condition")
EllesmereUI.UnitEffectiveRole = roleGetter
local detailed = UnitDetailedThreatSituation
UnitDetailedThreatSituation = nil
Match({ me = true }, false, "missing API fails closed")
UnitDetailedThreatSituation = detailed
Reset()
held.player = true
Match({ me = true }, true, "only-me matching")
Check(roleCalls == 0 and rosterCalls == 0, "only-me must not perform role/roster scans")
Reset()
Match({}, true, "empty threat means Any")
Match("any", true, "scalar Any remains unrestricted")
Check(#detailCalls == 0 and roleCalls == 0 and rosterCalls == 0, "Any must not query threat")
rule.conditions.threat = { tank = true }
rule.enabled = false
addon.FindRule("nameplate1")
Check(#detailCalls == 0, "disabled threat rules must not trigger scans")
Reset()
held.player = false
rule.conditions = { threat = { me = true } }
rule.style.castColorEnabled = false
rule.style.scale, rule.style.healthColorEnabled, rule.style.borderSize = 130, false, 0
addon.RefreshAll()
Check(f.plate:GetScale() == 1, "no aggro leaves default appearance")
held.player = true
f.Fire("UNIT_THREAT_SITUATION_UPDATE", "player")
Check(f.plate:GetScale() == 1.3, "threat acquisition refreshes appearance")
held.player = false
f.Fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
Check(f.plate:GetScale() == 1, "threat loss restores appearance")
rule.conditions.threat = { tank = true }
held.party1, roles.party1, live.party1, members = true, "TANK", true, 1
f.Fire("GROUP_ROSTER_UPDATE")
Check(f.plate:GetScale() == 1.3, "group tank holder refresh")
roles.party1 = "HEALER"
f.Fire("PLAYER_ROLES_ASSIGNED")
Check(f.plate:GetScale() == 1, "role change invalidates tank appearance")
local required = { UNIT_THREAT_SITUATION_UPDATE = false, GROUP_ROSTER_UPDATE = false, PLAYER_ROLES_ASSIGNED = false,
    ROLE_CHANGED_INFORM = false, PLAYER_SPECIALIZATION_CHANGED = false, ACTIVE_TALENT_GROUP_CHANGED = false }
for _, frame in ipairs(f.frames) do
    for event in pairs(required) do if frame.events[event] then required[event] = true end end
end
for event, registered in pairs(required) do Check(registered, "missing threat/role event " .. event) end
Check(api.ValidateRuleConditions({ threat = { nonTank = true, tank = true, me = true } }), "threat choices must validate")
Check(not api.ValidateRuleConditions({ threat = { unknown = true } }), "unknown threat choice must be rejected")
print("PASS: " .. checks .. " aggro-holder threat, secrecy, role, OR/AND, API gating and event checks")
