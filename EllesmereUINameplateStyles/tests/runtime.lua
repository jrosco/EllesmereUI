-- Run from the repository root with Lua or fengari.
unpack = unpack or table.unpack
local frames, timers = {}, {}
local function Noop() end
function CreateFrame()
    local frame = { events = {}, scripts = {}, scale = 1, alpha = 1 }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:GetScale() return self.scale end
    function frame:SetScale(value) self.scale = value end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:GetFrameStrata() return "MEDIUM" end
    function frame:GetFrameLevel() return 10 end
    for _, method in ipairs({ "SetAllPoints", "SetFrameStrata", "SetFrameLevel", "Hide", "Show",
        "ClearAllPoints", "SetPoint", "SetHeight", "SetWidth", "SetColorTexture" }) do
        frame[method] = Noop
    end
    function frame:CreateTexture() return CreateFrame() end
    frames[#frames + 1] = frame
    return frame
end
function hooksecurefunc(object, method, callback)
    local original = assert(object[method], method)
    object[method] = function(...)
        original(...)
        callback(...)
    end
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
local function Fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
    Flush()
end
function UnitExists() return true end
function UnitIsPlayer() return false end
function UnitPlayerControlled() return false end
function UnitCanAttack() return true end
function UnitIsUnit(unit, other) return unit == "nameplate1" and other == "target" end
function UnitClassification() return "normal" end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function geterrorhandler() return error end
SlashCmdList = {}

local plate = CreateFrame()
plate.unit = "nameplate1"
plate.health = CreateFrame()
plate.health.color = { 0.8, 0.1, 0.1, 1 }
plate.health.texture = "base"
function plate.health:GetStatusBarColor() return unpack(self.color) end
function plate.health:SetStatusBarColor(...) self.color = { ... } end
function plate.health:GetStatusBarTexture()
    local path = self.texture
    return { GetTexture = function() return path end }
end
function plate.health:SetStatusBarTexture(value) self.texture = value end
function plate:ApplyScale()
    self._curScale, self._destScale = 1, 1
    self:SetScale(1)
end
function plate:ClearUnit() self.unit = nil end
EllesmereNameplates_NS = { plates = { nameplate1 = plate }, friendlyPlates = {} }

local function Near(actual, expected, label)
    assert(math.abs(actual - expected) < 0.00001,
        label .. ": expected " .. expected .. ", got " .. tostring(actual))
end
local function Settings(name, scale, r)
    return { enabled = true, selectedRule = 1, rules = {
        { name = name, enabled = true, conditions = { target = "yes" },
          style = { scale = scale, borderSize = 0, healthColor = { r = r, g = 0.3, b = 0.4 } } },
    } }
end
local namespace = {}
assert(loadfile("EllesmereUINameplateStyles/EllesmereUINameplateStyles.lua"))("EllesmereUINameplateStyles", namespace)
assert(EllesmereUINameplateStylesDB == nil, "SavedVariables initialized before ADDON_LOADED")
local api = EllesmereUINameplateStyles

-- Model SavedVariables becoming available after addon chunks execute.
EllesmereUINameplateStylesDB = Settings("Loaded rule", 150, 0.2)
Fire("ADDON_LOADED", "EllesmereUINameplateStyles")
assert(api.GetSettings() == EllesmereUINameplateStylesDB)
assert(namespace.FindRule("nameplate1").name == "Loaded rule")
Near(plate.scale, 1.5, "saved scale")
Near(plate.health.color[1], 0.2, "saved color")

-- Replacing the table must not leave the renderer reading its previous rules.
EllesmereUINameplateStylesDB = Settings("Replacement rule", 115, 0.6)
api.Refresh(); Flush()
assert(api.GetRules() == EllesmereUINameplateStylesDB.rules)
assert(namespace.db == EllesmereUINameplateStylesDB)
Near(plate.scale, 1.15, "replacement scale")
Near(plate.health.color[1], 0.6, "replacement color")
for _ = 1, 10 do
    plate:ApplyScale()
    api.Refresh(); Flush()
    Near(plate.scale, 1.15, "repeated EUI scale update")
    Near(plate._curScale, 1, "EUI animation current remains unmodified")
    Near(plate._destScale, 1, "EUI animation destination remains unmodified")
end
plate:SetScale(1.2)
Near(plate.scale, 1.38, "animation scale multiplied once")
api.Refresh(); Flush()
Near(plate.scale, 1.38, "refresh preserves engine scale")

local rows, spec = {}, nil
local W = {}
function W:SectionHeader() return {}, 40 end
function W:Button(_, text, _, click) rows[text] = { click = click }; return {}, 50 end
function W:Toggle(_, text, _, get, set) rows[text] = { get = get, set = set }; return {}, 50 end
function W:Slider(_, text, _, _, _, _, get, set) rows[text] = { get = get, set = set }; return {}, 50 end
function W:Dropdown(_, text, _, values, get, set) rows[text] = { get = get, set = set, values = values }; return {}, 50 end
function W:DualRow(_, _, config)
    assert(config.type == "input")
    rows[config.text] = { get = config.getValue, set = config.setValue }
    return {}, 50
end
function W:ColorPicker(_, text, _, get, set)
    assert(type(get()) == "number", "color getter must return RGB components")
    rows[text] = { get = get, set = set }
    return {}, 50
end
EllesmereUI = {
    Widgets = W,
    RegisterPlugin = function(_, value) spec = value; return true end,
    IsPluginRegistered = function() return false end,
    GetPluginModuleKey = function() return "plugin:test:Styles" end,
    InvalidateModulePageCache = Noop,
    RefreshPage = function() spec.modules[1].buildPage("Rules", {}, 0) end,
}
assert(loadfile("EllesmereUINameplateStyles/EllesmereUINameplateStyles_Options.lua"))()
Fire("PLAYER_LOGIN")
spec.modules[1].buildPage("Rules", {}, 0)
rows["Nameplate size (%)"].set(120)
rows["Health-bar color"].set(0.9, 0.8, 0.7)
Flush()
Near(plate.scale, 1.44, "options slider changes live scale")
Near(plate.health.color[1], 0.9, "options picker changes live color")
rows["Add Rule"].click(); Flush()
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "new rule not selected by renderer")
Near(plate.scale, 1.2, "new rule scale")
Near(plate.health.color[1], 1, "new rule color")

local renamed = api.GetRules()[1]
local style, conditions = renamed.style, renamed.conditions
rows["Rule name"].set("  My Target Rule  ")
assert(renamed.name == "My Target Rule", "rename must trim and save")
assert(rows["Edit rule"].values["1"] == "My Target Rule", "dropdown label not updated")
assert(api.GetSettings().selectedRule == 1 and api.GetRules()[1] == renamed, "rename changed order or selection")
assert(renamed.style == style and renamed.conditions == conditions, "rename changed rule behavior")
rows["Rule name"].set(" \t\n ")
assert(renamed.name == "My Target Rule", "blank name replaced existing name")
local oldNameField = rows["Rule name"]
rows["Edit rule"].set("2")
oldNameField.set("Target Rule")
assert(renamed.name == "Target Rule" and api.GetRules()[2].name == "Replacement rule",
    "focus-loss commit renamed the wrong rule")
rows["Edit rule"].set("1")
assert(rows["Rule name"].get() == "Target Rule", "rename lost after page rebuild")

rows["Nameplate size (%)"].set(115); Flush()
plate:ClearUnit()
Near(plate.scale, 1.2, "pool release restores engine scale")
plate.unit = "nameplate1"
plate:ApplyScale(); api.Refresh(); Flush()
Near(plate.scale, 1.15, "recycled plate scale")
api.GetSettings().enabled = false
api.Refresh(); Flush()
Near(plate.scale, 1, "disable restores engine scale")

-- Existing option callbacks must also follow a replaced SavedVariables table.
EllesmereUINameplateStylesDB = Settings("Late replacement", 100, 0.1)
rows["Nameplate size (%)"].set(130)
rows["Health-bar color"].set(0.4, 0.5, 0.6)
Flush()
Near(plate.scale, 1.3, "cached options use current settings")
Near(plate.health.color[1], 0.4, "cached color picker uses current settings")
assert(namespace.db == EllesmereUINameplateStylesDB)

print("PASS: delayed SavedVariables, table replacement, live options, new rules, renaming, repeated scaling, recycling, disable")
