-- Run from the repository root with Lua or fengari. Loads the actual profile
-- module; only client/codec boundaries are mocked, never the parser itself.
EllesmereUI = { Lite = { RegisterPreLogout = function() end } }
C_AddOns = { IsAddOnLoaded = function() return false end }
LibDeflate = {
    DecodeForPrint = function(_, value) return value end,
    DecompressDeflate = function(_, value) return value end,
}
local frames = {}
function CreateFrame()
    local frame = { scripts = {} }
    function frame:RegisterEvent() end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:Hide() self.shown = false end
    function frame:Show() self.shown = true end
    frames[#frames + 1] = frame
    return frame
end
local clock = 0
function debugprofilestop() clock = clock + 10; return clock end
assert(loadfile("EllesmereUI_Profiles.lua"))()
local serializer = assert(EllesmereUI._Serializer)

-- Guard even the unfixed implementation. A pcall alone cannot stop a loop.
local function GuardedDeserialize(input)
    debug.sethook(function() error("instruction budget exceeded") end, "", 200000)
    local ok, value = pcall(serializer.Deserialize, input)
    debug.sethook()
    return ok, value
end

local cases = 0
local function Reject(input)
    local ok, value = GuardedDeserialize(input)
    assert(ok, "parser raised or exceeded instruction budget for " .. tostring(input))
    assert(value == nil, "parser accepted " .. tostring(input))
    cases = cases + 1
end
for _, input in ipairs({
    "", "s", "n", "{s}", "{n}", "{Ks}", "{Ks1:an}", "{Kn}",
    "s:abc", "s-1:x", "s+1:x", "s1.5:abc", "s1e1:abcdefghij", "s 1:x",
    "s0x1:x", "s1 :x", "s5:ab", "{s5:ab}", "s999999999999999999999999999999:x",
    "s" .. string.rep("9", 400) .. ":x", "s1:", "s2:x", "{s0}",
    "n;", "nwat;", "n1", "{n;}", "n1e999;", "n-1e999;", "nnan;", "ninf;",
    "{Kn1e999;T}", "{", "{T", "{{}", "{Ks1:aT", "{K}", "{Ks1:a}",
    "{KNT}", "{KNN}", "}", "K", "x", "{x}", "{T?}", "{}junk", "{}{}",
    "T;", "N{}", "s0:x", "n1;;", "{T}}", "{Ks1:aK}",
}) do Reject(input) end
Reject(nil)
Reject(false)
Reject(123)
Reject({})

local function Equal(a, b)
    assert(type(a) == type(b), "round-trip type mismatch")
    if type(a) ~= "table" then assert(a == b, "round-trip value mismatch"); return end
    for key, value in pairs(a) do Equal(value, b[key]) end
    for key, value in pairs(b) do Equal(value, a[key]) end
end
for _, value in ipairs({
    "", "s:{};KNTF", "\000\255\n\r:;{}", "UTF-8: café", true, false,
    0, -1, 1.25, -0.001, 1e20, 1e-100, 1e308,
    {}, { true, false, "a:b", { 0.1, 0.2, 0.3, 1 } },
    { [false] = "false key", [true] = false, [0] = "zero", [-1] = "negative", [1.5] = "fraction" },
    { version = 3, type = "full", data = { addons = { EllesmereUINameplates = { enabled = true } } } },
    { version = 1, rules = { { name = "Rule", conditions = { target = {} }, appearance = { alpha = 0.5 } } } },
}) do
    Equal(value, serializer.Deserialize(serializer.Serialize(value)))
    cases = cases + 1
end
assert(serializer.Serialize(nil) == "N" and serializer.Deserialize("N") == nil)
assert(serializer.Serialize("a:b") == "s3:a:b")
assert(serializer.Serialize({ true, false, "" }) == "{TFs0:}")
Equal({ [2] = true }, serializer.Deserialize("{NT}"))
Equal({}, serializer.Deserialize("{Ks1:xN}"))
assert(serializer.Deserialize("s0001:x") == "x")
local tableKey = {}
local keyRoundTrip = serializer.Deserialize(serializer.Serialize({ [tableKey] = "table key" }))
local decodedKey, decodedValue = next(keyRoundTrip)
assert(type(decodedKey) == "table" and decodedValue == "table key")

-- Nesting and total-work boundaries, including reset after a failed parse.
local function Nested(depth) return string.rep("{", depth) .. "T" .. string.rep("}", depth) end
local deep = serializer.Deserialize(Nested(128))
for _ = 1, 128 do deep = assert(deep[1]) end
assert(deep == true)
Reject(Nested(129))
Reject(string.rep("{K", 129) .. "TT" .. string.rep("T}", 129))
local workCalls = 0
serializer.SetYieldHook(function()
    workCalls = workCalls + 1
    assert(workCalls <= 489, "parser did not enforce work limit")
end)
-- N leaves do not allocate a million table entries in the test harness.
Equal({}, serializer.Deserialize("{" .. string.rep("N", 999999) .. "}"))
assert(workCalls == 488)
workCalls = 0
assert(serializer.Deserialize("{" .. string.rep("N", 1000000) .. "}") == nil)
assert(workCalls == 488)
serializer.SetYieldHook(nil)
Equal({}, serializer.Deserialize("{}"))
local maxBytes = 16 * 1024 * 1024
local content = string.rep("x", maxBytes - 10)
local atLimit = "s" .. #content .. ":" .. content
assert(#atLimit == maxBytes and serializer.Deserialize(atLimit) == content)
assert(serializer.Deserialize(atLimit .. "x") == nil)
content, atLimit = nil, nil

-- Hooks yield with advancing positions and cannot share another parse's counters.
local positions = {}
local input = "{" .. string.rep("T", 8192) .. "}"
serializer.SetYieldHook(function(pos)
    assert(#positions == 0 or pos > positions[#positions], "yield did not advance")
    positions[#positions + 1] = pos
    coroutine.yield(pos)
end)
local co = coroutine.create(function() return serializer.Deserialize(input) end)
local resumes = 0
while coroutine.status(co) ~= "dead" do
    resumes = resumes + 1
    assert(resumes <= 5, "parser coroutine stalled")
    local ok, value = coroutine.resume(co)
    assert(ok, value)
    if resumes == 1 then
        -- Match the async caller's guard against yielding a synchronous parse.
        serializer.SetYieldHook(function(pos)
            if coroutine.running() == co then
                positions[#positions + 1] = pos
                coroutine.yield(pos)
            end
        end)
        local nested = serializer.Deserialize("{" .. string.rep("T", 3000) .. "}")
        assert(#nested == 3000)
    end
    if coroutine.status(co) == "dead" then assert(#value == 8192) end
end
assert(#positions == 4 and positions[2] == 4096 and positions[4] == 8192)
serializer.SetYieldHook(function() error("test hook failure") end)
local ok, err = pcall(serializer.Deserialize, input)
assert(not ok and tostring(err):find("test hook failure", 1, true))
serializer.SetYieldHook(nil)
assert(#serializer.Deserialize(input) == 8192)
serializer.SetYieldHook(function() error("unexpected stale work counter") end)
for _ = 1, 3000 do assert(serializer.Deserialize("T") == true) end
serializer.SetYieldHook(nil)

-- Exercise the actual sync and async profile callers with identity codec mocks.
local function Async(code, progress)
    local calls, payload, message = 0
    local handle = EllesmereUI.DecodeImportStringAsync(code, function(value, errorMessage)
        calls, payload, message = calls + 1, value, errorMessage
    end, progress)
    local steps = 0
    while calls == 0 do
        steps = steps + 1
        assert(steps < 30, "async decode stalled")
        for _, frame in ipairs(frames) do
            if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate() end
        end
    end
    assert(calls == 1, "async callback count")
    return payload, message, handle
end
local valid = { version = 3, type = "full", data = { addons = {} }, values = {} }
for i = 1, 5000 do valid.values[i] = i end
local code = "!EUI_" .. serializer.Serialize(valid)
Equal(valid, assert(EllesmereUI.DecodeImportString(code)))
local progressCalls = 0
local asyncValue, asyncError = Async(code, function() progressCalls = progressCalls + 1 end)
Equal(valid, asyncValue)
assert(asyncError == nil and progressCalls >= 4)
for _, body in ipairs({ "{s}", "{n}", "{T", "{}junk", "T", "{Ks7:versions1:x}" }) do
    local value, message = EllesmereUI.DecodeImportString("!EUI_" .. body)
    assert(value == nil and message == "Failed to deserialize data", body)
    value, message = Async("!EUI_" .. body)
    assert(value == nil and message == "Failed to deserialize data", body)
end
local yieldedMalformed = "!EUI_{" .. string.rep("T", 4096) .. "s}"
local badValue, badMessage = Async(yieldedMalformed)
assert(badValue == nil and badMessage == "Failed to deserialize data")
for _, invalid in ipairs({ false, 123, {}, "bad" }) do
    local value, message = EllesmereUI.DecodeImportString(invalid)
    assert(value == nil and message == "Invalid string")
    value, message = Async(invalid)
    assert(value == nil and message == "Invalid string")
end
-- Async hook errors/cancellation clean up the hook and complete at most once.
local failedProgressCalls = 0
local value, message = Async(code, function(fraction)
    failedProgressCalls = failedProgressCalls + 1
    if fraction > 0.5 then error("progress callback failure") end
end)
assert(value == nil and message == "Failed to read import data")
local previousProgressCalls = failedProgressCalls
assert(#serializer.Deserialize(input) == 8192)
assert(failedProgressCalls == previousProgressCalls, "failed async run left a hook installed")
local cancelledCalls, cancelProgressCalls, parserStarted = 0, 0, false
local cancelled = EllesmereUI.DecodeImportStringAsync(code, function() cancelledCalls = cancelledCalls + 1 end,
    function(fraction)
        cancelProgressCalls = cancelProgressCalls + 1
        if fraction > 0.5 then parserStarted = true end
    end)
local cancelSteps = 0
while not parserStarted do
    cancelSteps = cancelSteps + 1
    assert(cancelSteps < 30, "cancel test did not reach parser yield")
    for _, frame in ipairs(frames) do
        if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate() end
    end
end
cancelled:Cancel()
for _, frame in ipairs(frames) do
    if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate() end
end
previousProgressCalls = cancelProgressCalls
assert(cancelledCalls == 0 and #serializer.Deserialize(input) == 8192)
assert(cancelProgressCalls == previousProgressCalls, "cancelled async run left a hook installed")
Equal(valid, (Async(code)))

-- Use the real Extras consumer too: its pcall must receive a finite failure
-- from the shared parser, and malformed input must leave settings untouched.
local settings = { rules = { "original" } }
local refreshes = 0
EllesmereUINameplateExtras = {
    GetSettings = function() return settings end,
    GetRules = function() return settings.rules end,
    Refresh = function() refreshes = refreshes + 1 end,
}
LibStub = function(name) assert(name == "LibDeflate"); return LibDeflate end
LibDeflate.CompressDeflate = function(_, wire) return wire end
LibDeflate.EncodeForPrint = function(_, wire) return wire end
assert(loadfile("EllesmereUINameplateExtras/EllesmereUINameplateExtras_RuleIO.lua"))()
for _, body in ipairs({ "{s}", "{n}", "{Ks1:an}", "{T", "{}junk", Nested(129) }) do
    local exceededBudget = false
    debug.sethook(function()
        exceededBudget = true
        error("instruction budget exceeded")
    end, "", 200000)
    local success, reason = EllesmereUINameplateExtras.ImportRuleSet("!EUI_NPEX_RULES2!" .. body)
    debug.sethook()
    assert(not exceededBudget, "Extras import stalled inside its pcall")
    assert(success == false and reason == "The rule-set code is damaged or from an unsupported version.")
    assert(settings.rules[1] == "original" and refreshes == 0)
end
local rules = { { name = "Rule", enabled = true, conditions = {}, style = { scale = 100 } } }
for version = 1, 2 do
    local rulesBody = serializer.Serialize({ format = "EllesmereUINameplateExtrasRules", version = version, rules = rules })
    assert(EllesmereUINameplateExtras.ImportRuleSet("!EUI_NPEX_RULES" .. version .. "!" .. rulesBody))
    assert(settings.rules[1].name == "Rule" and settings.rules[1].conditions.target ~= nil)
end
local exportedRules = assert(EllesmereUINameplateExtras.ExportRuleSet())
assert(EllesmereUINameplateExtras.ImportRuleSet(exportedRules))
assert(refreshes == 3)

print("Parser regression suite passed: " .. cases .. " malformed/round-trip cases plus limits, hooks, sync/async profiles, and Extras imports")
