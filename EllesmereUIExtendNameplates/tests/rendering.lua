-- Run from the repository root with Lua or fengari. Uses the real cast-lift module.
unpack = unpack or table.unpack
local timers = {}
local function Noop() end
function CreateFrame(kind, _, parent)
    local frame = { scale = 1, alpha = 1, parent = parent, kind = kind, alphaWrites = 0 }
    function frame:GetScale() return self.scale end
    function frame:SetScale(value) self.scale = value end
    function frame:GetEffectiveScale()
        return self.scale * (not self.ignoreParentScale and self.parent and self.parent:GetEffectiveScale() or 1)
    end
    function frame:SetIgnoreParentScale(value) self.ignoreParentScale = value end
    function frame:GetParent() return self.parent end
    function frame:SetParent(value) self.parent = value end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(value) self.alpha = value; self.alphaWrites = self.alphaWrites + 1 end
    function frame:GetFrameStrata() return "MEDIUM" end
    function frame:GetFrameLevel() return 10 end
    function frame:GetStatusBarColor() return unpack(self.color) end
    function frame:SetStatusBarColor(...) self.color = { ... } end
    function frame:GetStatusBarTexture()
        local path = self.texture
        return { GetTexture = function() return path end }
    end
    function frame:SetStatusBarTexture(value) self.texture = value end
    for _, method in ipairs({ "RegisterEvent", "UnregisterEvent", "SetScript", "SetSize",
        "SetFrameStrata", "EnableMouse", "Hide", "Show" }) do frame[method] = Noop end
    return frame
end
function hooksecurefunc(object, method, callback)
    local original = assert(object[method], method)
    object[method] = function(...) original(...); callback(...) end
end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function Flush()
    local iterations = 0
    while #timers > 0 do
        iterations = iterations + 1
        assert(iterations < 30, "refresh loop")
        local pending = timers
        timers = {}
        for _, callback in ipairs(pending) do callback() end
    end
end
function UnitExists() return true end
function UnitIsPlayer() return false end
function UnitFullName() return "Rendering", "TestRealm" end
function UnitPlayerControlled() return false end
function UnitCanAttack() return true end
function UnitIsUnit(unit, other) return unit == "nameplate1" and other == "target" end
function UnitClassification() return "normal" end
function UnitIsTapDenied() return false end
function UnitCastingInfo() end
function UnitChannelInfo() end
function geterrorhandler() return error end
SlashCmdList = {}
UIParent = CreateFrame("Frame")
UIParent:SetScale(0.8)
local NP = { plates = {}, friendlyPlates = {}, _ntAlpha = 1,
    db = { profile = { castOverlayEnabled = true } } }
EllesmereNameplates_NS = NP
-- Same alpha calculation/cache contract as the actual engine's NT_Apply.
function NP.NT_Apply(plate)
    local unit = plate.unit
    if not unit then return end
    local a = 1
    local nt = NP._ntAlpha
    if nt < 1 and UnitExists("target") and not UnitIsUnit(unit, "target")
        and not (NP._ntKeepFocus and UnitIsUnit(unit, "focus"))
        and not UnitIsUnit(unit, "player") then a = nt end
    a = a * (plate._oorCurAlpha or 1)
    if (plate._ntCurAlpha or 1) ~= a then
        plate._ntCurAlpha = a
        plate:SetAlpha(a)
    end
end
assert(loadfile("EllesmereUINameplates/EllesmereUINameplates_CastOverlay.lua"))("Nameplates", NP)
local namespace = {}
assert(loadfile("EllesmereUIExtendNameplates/Nameplates.lua"))("EllesmereUIExtendNameplates", namespace)
local api = EllesmereUIExtendNameplates
local function Near(actual, expected, label)
    assert(math.abs(actual - expected) < 0.00001,
        label .. ": expected " .. expected .. ", got " .. tostring(actual))
end
local function Fresh(opacity, scale, initialAlpha)
    local plate = CreateFrame("Frame", nil, UIParent)
    plate.unit = "nameplate1"
    plate.health = CreateFrame("StatusBar", nil, plate)
    plate.health.color, plate.health.texture = { 0.8, 0.1, 0.1, 1 }, "engine-health"
    plate.cast = CreateFrame("StatusBar", nil, plate)
    plate:SetAlpha(initialAlpha or 1)
    function plate:ClearUnit()
        -- Actual engine ordering: alpha reset/cache clear, then unit clear, then scale reset.
        if self._ntCurAlpha and self._ntCurAlpha < 1 then self:SetAlpha(1) end
        self._ntCurAlpha, self._oorCurAlpha = nil, nil
        self.unit = nil
        self:SetScale(1)
        self._curScale = nil
        self:SetParent(UIParent)
    end
    NP.plates, NP.friendlyPlates = { nameplate1 = plate }, {}
    NP.db.profile.castOverlayEnabled = true
    NP.RefreshCastOverlay(plate)
    EllesmereUIExtendNameplatesDB = { enabled = true, rules = {
        { name = "Rendering", conditions = { target = "yes" }, style = {
            opacity = opacity, scale = scale or 100, healthEnabled = false, borderSize = 0,
        } },
    } }
    api.Refresh(); Flush()
    return plate, api.GetRules()[1].style
end
local failures, passed = 0, 0
local function Test(name, callback)
    local ok, err = pcall(callback)
    if ok then passed = passed + 1; print("PASS: " .. name)
    else failures = failures + 1; print("FAIL: " .. name .. ": " .. tostring(err)) end
end
Test("fresh engine alpha and cached updates", function()
    local plate = Fresh(50)
    plate._oorCurAlpha = 0.4
    NP.NT_Apply(plate); Flush()
    Near(plate:GetAlpha(), 0.2, "engine alpha composed once")
    local writes = plate.alphaWrites
    for _ = 1, 10 do NP.NT_Apply(plate); Flush() end
    Near(plate._ntCurAlpha, 0.4, "engine cache unmodified")
    Near(plate:GetAlpha(), 0.2, "cached engine alpha")
    assert(plate.alphaWrites == writes, "cached refresh should not rewrite alpha")
    api.GetSettings().enabled = false; api.Refresh(); Flush()
    Near(plate:GetAlpha(), 0.4, "disable restores engine alpha")
end)
Test("zero opacity and rule transitions", function()
    local plate, style = Fresh(0)
    plate._oorCurAlpha = 0.3
    NP.NT_Apply(plate); Flush()
    Near(plate:GetAlpha(), 0, "zero stays zero")
    for _ = 1, 5 do NP.NT_Apply(plate); Flush() end
    style.opacity = 50; api.Refresh(); Flush()
    Near(plate:GetAlpha(), 0.15, "leaving zero uses authoritative alpha")
    api.GetRules()[1].conditions.target = "no"; api.Refresh(); Flush()
    Near(plate:GetAlpha(), 0.3, "unmatched rule restoration")
end)
Test("independent alpha writes survive cached NT passes", function()
    local plate = Fresh(50, 100, 0.7)
    Near(plate:GetAlpha(), 0.35, "pre-hook alpha captured")
    plate._oorCurAlpha = 0.4; NP.NT_Apply(plate); Flush()
    plate:SetAlpha(0.6)
    Near(plate:GetAlpha(), 0.3, "independent write composed immediately")
    for _ = 1, 5 do NP.NT_Apply(plate); Flush() end
    Near(plate:GetAlpha(), 0.3, "cached NT does not claim independent write")
    api.GetSettings().enabled = false; api.Refresh(); Flush()
    Near(plate:GetAlpha(), 0.6, "latest independent write restored")
    plate:SetAlpha(0.8); api.Refresh(); Flush()
    Near(plate:GetAlpha(), 0.8, "disabled writes remain authoritative")
end)
Test("release and recycle with engine fade", function()
    local plate = Fresh(50, 150)
    plate._oorCurAlpha = 0.4; NP.NT_Apply(plate); Flush()
    plate:ClearUnit()
    Near(plate:GetAlpha(), 1, "release is full opacity")
    Near(plate:GetScale(), 1, "release is engine pool scale")
    assert(plate._ntCurAlpha == nil and plate._curScale == nil, "release caches remain cleared")
    Flush(); Near(plate:GetAlpha(), 1, "queued release refresh")
    plate.unit = "nameplate1"; api.Refresh(); Flush()
    NP.NT_Apply(plate); Flush()
    Near(plate:GetAlpha(), 0.5, "recycle starts from full engine alpha")
    plate._oorCurAlpha = 0.2; NP.NT_Apply(plate); Flush()
    Near(plate:GetAlpha(), 0.1, "recycled engine fade")
end)
Test("release when engine alpha reset is skipped", function()
    for _, opacity in ipairs({ 0, 50, 100 }) do
        local plate = Fresh(opacity)
        assert(plate._ntCurAlpha == nil, "engine did not need an alpha write")
        plate:ClearUnit(); Flush()
        Near(plate:GetAlpha(), 1, "pool cleanup without engine alpha setter")
        plate.unit = "nameplate1"; api.Refresh(); Flush()
        Near(plate:GetAlpha(), opacity / 100, "recycle opacity")
    end
end)
Test("lift container sync on apply, animation, transition, disable and recycle", function()
    local plate, style = Fresh(100, 150)
    assert(plate.cast:GetParent() == plate._castLift and plate._castLift:GetParent() == UIParent,
        "cast must be lifted outside plate hierarchy")
    Near(plate._castLift:GetScale(), plate:GetEffectiveScale(), "rule apply syncs lift container")
    plate._curScale, plate._destScale = 1.2, 1.4
    plate:SetScale(1.2)
    Near(plate:GetScale(), 1.8, "animation rendered multiplier")
    Near(plate._curScale, 1.2, "animation current unchanged")
    Near(plate._destScale, 1.4, "animation destination unchanged")
    Near(plate._castLift:GetScale(), 1.44, "animation syncs lift")
    style.scale = 125; api.Refresh(); Flush()
    Near(plate._castLift:GetScale(), 1.2, "rule scale transition")
    api.GetSettings().enabled = false; api.Refresh(); Flush()
    Near(plate._castLift:GetScale(), 0.96, "disable restores lifted scale")
    api.GetSettings().enabled = true; api.Refresh(); Flush()
    plate:ClearUnit(); Flush()
    Near(plate._castLift:GetScale(), 0.8, "pool scale sync")
    plate.unit = "nameplate1"; api.Refresh(); Flush()
    Near(plate._castLift:GetScale(), 1, "recycled lift sync")
    NP.db.profile.castOverlayEnabled = false; NP.RefreshCastOverlay(plate)
    style.scale = 150; api.Refresh(); Flush()
    assert(plate.cast:GetParent() == plate, "non-lifted cast remains on plate")
    Near(plate.cast:GetEffectiveScale(), plate:GetEffectiveScale(), "non-lifted inheritance")
    NP.RefreshCastOverlay = nil -- optional engine integration
    style.scale = 100; api.Refresh(); Flush()
    Near(plate:GetScale(), 1, "scale works without overlay API")
end)
assert(failures == 0, failures .. " rendering fixtures failed; " .. passed .. " passed")
print("PASS: all rendering fixtures")
