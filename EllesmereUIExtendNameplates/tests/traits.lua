-- Run from the repository root with Lua or fengari.
local fixture = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("traits")
local api, namespace, mocks, secret = fixture.api, fixture.namespace, fixture.mocks, fixture.secret
local cases = 0
local function Reset()
    for key in pairs(mocks) do mocks[key] = nil end
    api.GetSettings().enabled = true
    api.GetSettings().rules = {
        { name = "Trait probe", enabled = true, conditions = { target = { yes = true } }, style = {} },
    }
end
local function Traits()
    local rule, _, traits = namespace.FindRule("nameplate1")
    assert(rule, "trait probe did not match")
    return traits
end
local function Equal(actual, expected, label)
    cases = cases + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function Cast(state, interruptible, school, label)
    local traits = Traits()
    Equal(traits.castState, state, label .. " state")
    Equal(traits.interruptible, interruptible, label .. " interruptibility")
    Equal(traits.spellSchool, school, label .. " school")
end
Reset()
assert(api.RegisterSpellSchool(123, "fire"))
assert(api.RegisterSpellSchool(456, "frost"))
Cast("none", "any", "unknown", "no cast")
mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, false, 123 }
mocks.channel = { "Channel", nil, nil, nil, nil, nil, true, 456, true }
-- A channel/obsolete API must not override an ordinary cast.
UnitEmpoweredChannelInfo = function() error("obsolete empowerment API called") end
Cast("casting", "interruptible", "fire", "ordinary cast takes precedence")
mocks.casting[8] = true
Cast("casting", "uninterruptible", "fire", "uninterruptible cast")
mocks.casting = {}
Cast("empowered", "uninterruptible", "frost", "ninth return empowered")
api.GetRules()[1].conditions.castState = { channel = true }
Equal(namespace.FindRule("nameplate1"), nil, "empowered must not match ordinary channel rule")
api.GetRules()[1].conditions.castState = { empowered = true }
Equal(namespace.FindRule("nameplate1") ~= nil, true, "empowered-only rule matches")
api.GetRules()[1].conditions.castState = {}
mocks.channel[9] = false
Cast("channel", "uninterruptible", "frost", "ordinary channel")
mocks.channel[9] = nil
UnitEmpoweredChannelInfo = nil
Cast("channel", "uninterruptible", "frost", "older client without empowerment flag")
mocks.channel[7], mocks.channel[8] = nil, 999
Cast("channel", "unknown", "unknown", "unavailable interruptibility and school")
mocks.channel[7], mocks.channel[8], mocks.channel[9] = secret, secret, secret
Cast("unknown", "unknown", "unknown", "restricted channel metadata")
api.GetRules()[1].conditions.castState = { casting = true, channel = true, empowered = true }
Equal(namespace.FindRule("nameplate1") ~= nil, true, "explicit Casting includes active casts with restricted kind metadata")
api.GetRules()[1].conditions.castState = { channel = true, empowered = true }
Equal(namespace.FindRule("nameplate1"), nil, "unknown cast kind must not match specific kind rules")
api.GetRules()[1].conditions.castState = {}
mocks.channel[9] = "true"
Cast("unknown", "unknown", "unknown", "malformed empowerment flag")
mocks.channel[1], mocks.channel[9] = secret, false
Cast("channel", "unknown", "unknown", "restricted name still indicates channel presence")
mocks.casting = { secret, nil, nil, nil, nil, nil, nil, secret, secret }
Cast("casting", "unknown", "unknown", "restricted cast metadata")

local function Reaction(attackable, reaction, expected, label)
    Reset()
    mocks.attackable, mocks.reaction = attackable, reaction
    Equal(Traits().reaction, expected, label)
end
Reaction(true, 3, "enemy", "hostile")
Reaction(false, 5, "friendly", "friendly")
Reaction(true, 4, "neutral", "attackable yellow neutral")
Reaction(false, 4, "neutral", "nonattackable neutral")
Reaction(true, 5, "enemy", "friendly-faction duel opponent")
Reaction(false, 3, "friendly", "nonattackable unusual hostile faction")
Reaction(true, nil, "enemy", "unavailable reaction enemy fallback")
Reaction(false, nil, "friendly", "unavailable reaction friendly fallback")
Reaction(true, secret, "enemy", "restricted reaction enemy fallback")
Reaction(false, secret, "friendly", "restricted reaction friendly fallback")
Reaction(secret, 3, "unknown", "restricted attackability does not infer hostile")
Reaction(secret, 5, "unknown", "restricted attackability does not infer friendly")
Reaction(secret, 4, "neutral", "readable neutral with restricted attackability")
Reaction(secret, secret, "unknown", "both reaction sources restricted")
Reaction("true", "4", "unknown", "malformed reaction sources")
local unitReaction = UnitReaction
UnitReaction = nil
Reaction(true, nil, "enemy", "missing reaction API enemy fallback")
Reaction(false, nil, "friendly", "missing reaction API friendly fallback")
UnitReaction = unitReaction
Reset()
mocks.player, mocks.target, mocks.classification = secret, secret, secret
local captured
assert(api.RegisterCondition("captureTraits", function(_, traits) captured = traits; return true end))
api.GetRules()[1].conditions = { captureTraits = true }
namespace.FindRule("nameplate1")
Equal(captured.unitType, "unknown", "restricted player type")
Equal(captured.target, nil, "restricted target")
Equal(captured.classification, "unknown", "restricted classification")

local function Predicate(callback, expected, label)
    Reset()
    assert(api.RegisterCondition("traitPredicate", callback))
    api.GetRules()[1].conditions.traitPredicate = true
    local ok, rule = pcall(namespace.FindRule, "nameplate1")
    mocks.secretBoolean = nil
    Equal(ok, true, label .. " must not escape matching")
    Equal(rule ~= nil, expected, label .. " result")
end
Predicate(function() return true end, true, "explicit true")
Predicate(function() return false end, false, "false")
Predicate(function() error("predicate failure") end, false, "predicate error")
Predicate(function() return nil end, false, "nil")
Predicate(function() return 1 end, false, "truthy number")
Predicate(function() return "true" end, false, "truthy string")
Predicate(function() return {} end, false, "truthy table")
Predicate(function() return secret end, false, "successful restricted sentinel return")
Predicate(function() mocks.secretBoolean = true; return true end, false, "successful secret-flagged boolean return")
-- Plain Lua cannot forbid truth-testing a secret bool as Retail does; these mocks
-- verify rejection through issecretvalue, with live-client validation still required.
Reset()
mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, secret, secret }
api.GetRules()[1].conditions.castState = { interruptible = true }
api.GetRules()[1].style = { castEnabled = true, castColorEnabled = true }
Equal(namespace.FindRule("nameplate1"), api.GetRules()[1], "secret Interruptible implies Casting for appearance effects")
Equal(namespace.FindCastColorOverrides("nameplate1").interruptible ~= nil, true, "Interruptible supplies a secret-safe color candidate")
api.GetRules()[1].conditions.castState = "interruptible"
Equal(namespace.FindCastColorOverrides("nameplate1").interruptible ~= nil, true, "legacy scalar color selection remains supported")
for _, selection in ipairs({ "casting", "interruptible", "interruptOnCD", "uninterruptible" }) do
    api.GetRules()[1].conditions.castState = { [selection] = true }
    mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, secret, secret }
    mocks.channel = {}
    local colorKey = selection == "casting" and "interruptible" or selection
    Equal(namespace.FindCastColorOverrides("nameplate1")[colorKey] ~= nil, true, selection .. " colors ordinary cast")
    mocks.casting = {}
    mocks.channel = { "Channel", nil, nil, nil, nil, nil, secret, secret, false }
    Equal(namespace.FindCastColorOverrides("nameplate1")[colorKey] ~= nil, true, selection .. " colors channel")
    mocks.channel[9] = true
    Equal(namespace.FindCastColorOverrides("nameplate1")[colorKey] ~= nil, true, selection .. " colors empowered cast")
    mocks.channel[9] = secret
    Equal(namespace.FindCastColorOverrides("nameplate1")[colorKey] ~= nil, true, selection .. " colors active unknown kind")
    mocks.channel = {}
    Equal(namespace.FindRule("nameplate1"), nil, selection .. " still requires an active cast")
    Equal(next(namespace.FindCastColorOverrides("nameplate1")), nil, selection .. " supplies no candidate without cast")
end
api.GetRules()[1].conditions.castState = { empowered = true }
mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, secret, secret }
Equal(namespace.FindRule("nameplate1"), nil, "implicit empowered eligibility must not match ordinary casts")
mocks.casting = {}
mocks.channel = { "Channel", nil, nil, nil, nil, nil, secret, secret, false }
Equal(namespace.FindRule("nameplate1"), nil, "empowered selection must not match ordinary channels")
mocks.channel[9] = true
Equal(namespace.FindRule("nameplate1") ~= nil, true, "empowered selection matches empowerment without explicit Casting")
api.GetRules()[1].conditions.castState = { interruptible = true }
mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, secret, secret }
mocks.channel = {}
mocks.target = true

local function CastDebug()
    local messages, originalPrint = {}, print
    print = function(message) messages[#messages + 1] = message end
    local ok, err = pcall(SlashCmdList.EXTENDNAMEPLATES, "cast")
    print = originalPrint
    assert(ok, tostring(err))
    return table.concat(messages, "\n")
end
local function Contains(text, expected, label)
    Equal(text:find(expected, 1, true) ~= nil, true, label)
end
local originalTostring = tostring
tostring = function(value)
    assert(value ~= secret, "diagnostics tried to stringify a secret value")
    return originalTostring(value)
end
local ok, output = pcall(CastDebug)
tostring = originalTostring
assert(ok, output)
Contains(output, "interruptibility=unknown; knowledge=unknown (secret)", "debug unknown secret")
Contains(output, "notInterruptible secret=true", "debug secret flag")
Contains(output, "Winning nameplate rule=1 (Trait probe)", "debug implicit Casting appearance winner")
Contains(output, "Cast color interruptible=rule 1 (Trait probe)", "debug cast-color winner")
mocks.casting[8] = false
Contains(CastDebug(), "interruptibility=interruptible; knowledge=known", "debug known interruptible")
mocks.casting[8] = true
Contains(CastDebug(), "interruptibility=uninterruptible; knowledge=known", "debug known uninterruptible")
mocks.casting[8] = nil
Contains(CastDebug(), "knowledge=unknown (unavailable)", "debug unavailable metadata")
mocks.casting = {}
mocks.channel = { "Channel", nil, nil, nil, nil, nil, secret, 456, false }
Contains(CastDebug(), "source=UnitChannelInfo", "debug channel source")
mocks.channel = {}
Contains(CastDebug(), "No active cast/channel", "debug no cast")
local originalCasting = UnitCastingInfo
UnitCastingInfo = function() error("API failure") end
Contains(CastDebug(), "API read failed", "debug API error")
UnitCastingInfo = originalCasting
local originalExists = UnitExists
UnitExists = function() return false end
Contains(CastDebug(), "select a target first", "debug missing target")
UnitExists = originalExists
print("PASS: " .. cases .. " focused cast, reaction, restricted-trait and predicate checks")
