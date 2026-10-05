-- Run from the repository root with Lua or fengari. No nameplate/UI/codec dependencies.
SlashCmdList = {}
function UnitFullName() return "SchemaCharacter", "TestRealm" end
function CreateFrame()
    return { RegisterEvent = function() end, SetScript = function() end }
end
C_Timer = { After = function() end }
local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = Copy(child) end
    return copy
end
local function LoadRuntime()
    assert(loadfile("EllesmereUIExtendNameplates/Nameplates.lua"))("EllesmereUIExtendNameplates", {})
    return EllesmereUIExtendNameplates
end
EllesmereUIExtendNameplatesDB = { profiles = { Default = { rules = {
    { name = "Any", conditions = { target = {} } },
    { name = "No", conditions = { target = { no = true } } },
    { name = "Missing", conditions = {} },
} } } }
local api = LoadRuntime()
local failures = 0
local function Check(ok, label)
    if not ok then failures = failures + 1; print("FAIL: " .. label) end
end
local function CheckTargets(phase)
    local rules = api.GetRules()
    Check(next(rules[1].conditions.target) == nil, phase .. ": empty target stays Any")
    Check(rules[2].conditions.target.no and not rules[2].conditions.target.yes, phase .. ": No-only stays No-only")
    Check(next(rules[3].conditions.target) == nil, phase .. ": missing generic target stays Any")
end
CheckTargets("load")
assert(api.CreateProfile("Starters"))
local startersByName = {}
for _, rule in ipairs(api.GetRules()) do startersByName[rule.name] = rule end
Check(next(startersByName["Elite Enemies"].conditions.target) == nil, "starter elite permits non-targets")
Check(next(startersByName["Enemy Casting"].conditions.target) == nil, "starter enemy casting permits non-targets")
Check(startersByName["Current Target"].conditions.target.yes == true, "starter current target retains Yes")
Check(startersByName["Non Target"].conditions.target.no == true
    and startersByName["Non Target"].conditions.target.none == true
    and startersByName["Non Target"].conditions.target.yes == nil,
    "starter non-target selects other units and no selected target, never current target")
assert(api.SelectProfile("Default"))
CheckTargets("switch")
-- Model serialization/reload with a fresh root and fresh runtime locals.
EllesmereUIExtendNameplatesDB = Copy(EllesmereUIExtendNameplatesDB)
api = LoadRuntime()
CheckTargets("reload")
assert(failures == 0, failures .. " target normalization regressions failed")

local function Same(actual, expected, label)
    assert(type(actual) == type(expected), label .. ": type differs")
    if type(expected) ~= "table" then assert(actual == expected, label .. ": value differs"); return end
    for key, child in pairs(expected) do Same(actual[key], child, label .. "." .. tostring(key)) end
    for key in pairs(actual) do assert(expected[key] ~= nil, label .. ": unexpected key " .. tostring(key)) end
end
local choices = {
    unitType = { "player", "npc", "pet", "creature" },
    reaction = { "enemy", "friendly", "neutral" },
    classification = { "normal", "elite", "rare", "rareelite", "boss", "minus" },
    target = { "yes", "no", "none" },
    threat = { "nonTank", "tank", "me" },
    playerCombat = { "inCombat", "outOfCombat" },
    instanceType = { "world", "dungeon", "raid", "battleground", "arena", "scenario", "delve" },
    castState = { "none", "casting", "channel", "empowered", "interruptible", "interruptOnCD", "uninterruptible" },
    spellSchool = { "physical", "holy", "fire", "nature", "frost", "shadow", "arcane", "mixed" },
}
local function ExpectedConditions(key, value)
    local result = { questObjective = "any" }
    for field in pairs(choices) do result[field] = {} end
    if key then result[key] = Copy(value) end
    return result
end

-- Only the transport is stubbed: exercise RuleIO's actual validation/normalization.
local payload
EllesmereUI = { _Serializer = {
    Serialize = function(value) payload = Copy(value); return "schema" end,
    Deserialize = function() return Copy(payload) end,
} }
local codec = {
    CompressDeflate = function(_, value) return value end,
    EncodeForPrint = function(_, value) return value end,
    DecodeForPrint = function(_, value) return value end,
    DecompressDeflate = function(_, value) return value end,
}
function LibStub(name) if name == "LibDeflate" then return codec end end
local function LoadRuleIO()
    assert(loadfile("EllesmereUIExtendNameplates/RuleIO.lua"))()
end
LoadRuleIO()
local cases = 0
local function ImportConditions(conditions, version)
    payload = { format = "EllesmereUINameplateExtrasRules", version = version, rules = {
        { name = "Schema rule", enabled = true, conditions = Copy(conditions), style = {} },
    } }
    return api.ImportRuleSet("!EUI_NPEX_RULES" .. version .. "!schema")
end
local function Accept(conditions, expected, label)
    local normalized = { conditions = Copy(conditions) }
    assert(api.NormalizeRuleConditions(normalized) == normalized, "normalization must return the rule")
    Same(normalized.conditions, expected, label .. " runtime")
    api.NormalizeRuleConditions(normalized)
    Same(normalized.conditions, expected, label .. " idempotence")
    for version = 1, 2 do
        local ok, err = ImportConditions(conditions, version)
        assert(ok, label .. ": " .. tostring(err))
        Same(api.GetRules()[1].conditions, expected, label .. " import v" .. version)
        -- Imported rules pass through all-profile normalization on each switch.
        assert(api.SelectProfile("Starters"))
        assert(api.SelectProfile("Default"))
        Same(api.GetRules()[1].conditions, expected, label .. " switch v" .. version)
        cases = cases + 1
    end
end
Accept({}, ExpectedConditions(), "missing conditions")
for key, values in pairs(choices) do
    Accept({ [key] = "any" }, ExpectedConditions(), key .. " scalar Any")
    Accept({ [key] = {} }, ExpectedConditions(), key .. " empty selection")
    local all = {}
    for _, value in ipairs(values) do
        all[value] = true
        local expected = ExpectedConditions(key, { [value] = true })
        Accept({ [key] = value }, expected, key .. " legacy " .. value)
        Accept({ [key] = { [value] = true } }, expected, key .. " selection " .. value)
    end
    Accept({ [key] = all }, ExpectedConditions(key, all), key .. " all selections")
end
for _, value in ipairs({ "any", "yes", "no" }) do
    Accept({ questObjective = value }, ExpectedConditions("questObjective", value), "quest " .. value)
end

-- Reject bad imports before replacing the live rules; saved-data cleanup remains tolerant.
for key, values in pairs(choices) do
    for _, value in ipairs({ "unknown", false, 7, { unknown = true }, { [values[1]] = false }, { [values[1]] = 1 } }) do
        local valid, invalidKey = api.ValidateRuleConditions({ [key] = value })
        assert(not valid and invalidKey == key, key .. " invalid value accepted by schema")
        local before = api.GetRules()
        local ok, err = ImportConditions({ [key] = value }, 2)
        assert(not ok and err:find(key, 1, true) and api.GetRules() == before,
            key .. " invalid import mutated live rules")
    end
    local dirty = { conditions = { [key] = { [values[1]] = true, [values[2]] = false, unknown = true } } }
    api.NormalizeRuleConditions(dirty)
    Same(dirty.conditions[key], { [values[1]] = true }, key .. " saved-data cleanup")
end
for _, value in ipairs({ "unknown", true, {}, 7 }) do
    local before = api.GetRules()
    local ok, err = ImportConditions({ questObjective = value }, 2)
    assert(not ok and err:find("questObjective", 1, true) and api.GetRules() == before,
        "invalid quest import mutated live rules")
end
for _, conditions in ipairs({ false, "invalid" }) do
    local rule = { conditions = conditions }
    api.NormalizeRuleConditions(rule)
    Same(rule.conditions, ExpectedConditions(), "invalid saved conditions container")
end

-- Intentional both-state selections and extension-owned data cannot be guessed away.
local custom = { mode = "strict", choices = { "a", "b" }, enabled = false }
local expected = ExpectedConditions("target", { yes = true, no = true })
expected.extensionFlag = false
expected.extensionData = Copy(custom)
assert(api.RegisterCondition("extensionData", function() return true end))
Accept({ target = { yes = true, no = true }, extensionFlag = false, extensionData = custom },
    expected, "both targets and custom conditions")
local code = assert(api.ExportRuleSet())
assert(code == "!EUI_NPEX_RULES2!schema", "export version changed")
Same(payload.rules[1].conditions, expected, "export preserves selections/custom data")
assert(api.ImportRuleSet(code))
EllesmereUIExtendNameplatesDB = Copy(EllesmereUIExtendNameplatesDB)
api = LoadRuntime()
LoadRuleIO()
Same(api.GetRules()[1].conditions, expected, "import then reload preserves selections/custom data")
local normalized = { conditions = { extensionData = custom } }
api.NormalizeRuleConditions(normalized)
assert(normalized.conditions.extensionData == custom, "normalization replaced extension-owned data")
payload.version = 1
local before = api.GetRules()
assert(not api.ImportRuleSet(code) and api.GetRules() == before, "mismatched version accepted")
payload.version = 2
payload.rules[1].conditions.castState = { interruptible = true }
assert(api.ImportRuleSet(code), "interruptible cast import failed")
assert(api.GetRules()[1].conditions.castState.casting == nil, "import must not expose implicit Casting")
assert(api.ExportRuleSet() == code)
assert(payload.rules[1].conditions.castState.interruptible and payload.rules[1].conditions.castState.casting == nil,
    "export exposed implicit cast selection")
print("PASS: schema target reload/switch regressions, " .. cases .. " v1/v2 import cases, validation, custom conditions")
