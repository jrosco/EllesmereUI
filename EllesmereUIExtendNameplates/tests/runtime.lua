-- Run from the repository root with Lua or fengari.
unpack = unpack or table.unpack
local frames, timers = {}, {}
local function Noop() end
local tappedByOther = false
local questObjective = false
local playerName = "TestCharacter"
local activeCast
local traitMocks = {}
local secretValue = {}
local function TraitValue(key, default)
    if traitMocks[key] ~= nil then return traitMocks[key] end
    return default
end
-- Sentinels and flagged booleans exercise the guards, not Retail's secret VM semantics.
function issecretvalue(value)
    return value == secretValue or (traitMocks.secretBoolean == true and value == true)
end
function CreateFrame(kind, _, parentFrame, template)
    if template == "DisableUntrustedLayoutScriptsTemplate" and traitMocks.unsupportedArrowTemplate then
        error("template unavailable on this client")
    end
    assert(parentFrame == nil or rawget(parentFrame, "nativeFrame"), "native UI parent required")
    local frame = { nativeFrame = true, events = {}, scripts = {}, scale = 1, alpha = 1, kind = kind, parent = parentFrame, template = template,
        vertexColor = { 1, 1, 1, 1 } }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:GetScale() return self.scale end
    function frame:SetScale(value) self.scale = value end
    function frame:GetAlpha() return self.alpha end
    function frame:GetParent() return self.parent end
    function frame:SetParent(parent) self.parent = parent end
    function frame:SetIgnoreParentScale(value) self.ignoreParentScale = value end
    function frame:IsIgnoringParentScale() return self.ignoreParentScale == true end
    function frame:GetEffectiveScale()
        local inherited = not self.ignoreParentScale and self.parent and self.parent:GetEffectiveScale() or 1
        return self.scale * inherited
    end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:SetAlphaFromBoolean(value, yes, no)
        if value == secretValue then self.alpha = secretValue else self.alpha = value and (yes or 1) or (no or 0) end
    end
    function frame:GetFrameStrata() return self.frameStrata or "MEDIUM" end
    function frame:GetFrameLevel() return self.frameLevel or 10 end
    function frame:GetWidth() return self.width or 800 end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    for _, method in ipairs({ "SetAllPoints", "SetFrameStrata", "SetFrameLevel", "Hide", "Show",
        "ClearAllPoints", "SetPoint", "SetHeight", "SetWidth", "SetColorTexture", "SetText",
        "SetJustifyH", "SetWordWrap", "SetMaxLines", "EnableMouse", "SetMouseClickEnabled" }) do
        frame[method] = Noop
    end
    function frame:CreateTexture() return CreateFrame("Texture", nil, self) end
    function frame:SetMinMaxValues(min, max) self.min, self.max = min, max end
    function frame:SetValue(value) self.value = value end
    function frame:SetStatusBarTexture(path)
        self.fill = self.fill or self:CreateTexture()
        self.fill:SetTexture(path)
    end
    function frame:GetStatusBarTexture() return self.fill end
    function frame:SetStatusBarColor(...) self.color = { ... } end
    function frame:GetStatusBarColor() return unpack(self.color) end
    function frame:SetColorTexture(...) self.color = { ... } end
    function frame:SetFont(path, size, flags) self.fontPath, self.fontSize, self.fontFlags = path, size, flags; return true end
    function frame:SetFrameLevel(value) self.frameLevel = value end
    function frame:SetFrameStrata(value) self.frameStrata = value end
    function frame:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a or 1 } end
    function frame:GetTextColor() return unpack(self.textColor or { 1, 1, 1, 1 }) end
    function frame:SetFormattedText(format, ...) self.text = string.format(format, ...) end
    function frame:SetHeight(value) self.height = value end
    function frame:SetWidth(value) self.width = value end
    function frame:SetAllPoints(other) self.allPoints = other end
    function frame:EnableMouse(value) self.mouseEnabled = value end
    function frame:CreateFontString()
        local font = CreateFrame("FontString", nil, self)
        function font:SetText(text) self.text = text end
        function font:SetWidth(width) self.width = width end
        function font:SetWordWrap(wrap) self.wordWrap = wrap end
        function font:GetStringHeight()
            return math.max(1, math.ceil(#(self.text or "") * 7 / (self.width or 800))) * 16
        end
        return font
    end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:GetNumPoints() return self.point and 1 or 0 end
    function frame:GetPoint() return unpack(self.point) end
    function frame:SetTexture(path) self.texture = path end
    function frame:GetTexture() return self.texture end
    function frame:GetVertexColor() return unpack(self.vertexColor) end
    function frame:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a or 1 } end
    function frame:Show()
        local was = self.shown ~= false
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function frame:Hide()
        local was = self.shown ~= false
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function frame:IsShown() return self.shown == true end
    function frame:IsVisible()
        if self.shown == false then return false end
        return not self.parent or self.parent:IsVisible()
    end
    function frame:SetShown(value) if value then self:Show() else self:Hide() end end
    frames[#frames + 1] = frame
    return frame
end
function hooksecurefunc(object, method, callback)
    local original = assert(object[method], method)
    local function Pack(...) return { n = select("#", ...), ... } end
    object[method] = function(...)
        local result = Pack(original(...))
        callback(...)
        return unpack(result, 1, result.n)
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
function UnitExists(unit)
    if unit == "target" then return TraitValue("targetExists", true) end
    return true
end
function UnitIsPlayer() return TraitValue("player", false) end
function UnitFullName() return playerName, "TestRealm" end
function UnitName() return playerName end
function GetRealmName() return "TestRealm" end
function UnitPlayerControlled() return TraitValue("controlled", false) end
function UnitCanAttack() return TraitValue("attackable", true) end
function UnitReaction() return traitMocks.reaction end
function UnitIsUnit(unit, other)
    return TraitValue("target", TraitValue("targetExists", true) == true and unit == "nameplate1" and other == "target")
end
function UnitClassification() return TraitValue("classification", "normal") end
function UnitIsTapDenied() return tappedByOther end
function UnitCastingInfo()
    if traitMocks.casting then return unpack(traitMocks.casting, 1, 9) end
    if activeCast == "casting" then return "Test Spell", nil, nil, nil, nil, nil, nil, false, 123 end
end
function UnitChannelInfo()
    if traitMocks.channel then return unpack(traitMocks.channel, 1, 9) end
    if activeCast == "channel" then return "Test Channel", nil, nil, nil, nil, nil, false, 456 end
end
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
function plate:ClearUnit()
    -- EUI resets faded pooled plates before clearing the cache and unit.
    if self._ntCurAlpha and self._ntCurAlpha < 1 then self:SetAlpha(1) end
    self._ntCurAlpha, self._oorCurAlpha = nil, nil
    self.unit = nil
    self:SetScale(1)
    self._curScale = nil
end
function plate:UpdateHealthColor() end -- EUI's cached-color path performs no setter call.
plate.cast = CreateFrame("StatusBar", nil, plate)
function plate.cast:GetStatusBarTexture() return self.fill end
function plate.cast:SetStatusBarTexture(path)
    self.fill = self:CreateTexture()
    self.fill:SetTexture(path)
end
plate.cast:SetStatusBarTexture("cast-base")
plate.cast:GetStatusBarTexture():SetVertexColor(0.2, 0.3, 0.4, 1)
plate.castBarOverlay = plate.cast:CreateTexture()
plate.castBarOverlay:SetTexture("overlay-base")
plate.castBarOverlay:SetVertexColor(0.5, 0.5, 0.5, 1)
plate.castBarOverlay:SetAlpha(0.25)
plate.castSpark = plate.cast:CreateTexture()
plate.castSpark:SetPoint("CENTER", plate.cast:GetStatusBarTexture(), "RIGHT", 0, 0)
EllesmereNameplates_NS = {
    plates = { nameplate1 = plate }, friendlyPlates = {},
    IsQuestMob = function() return questObjective end,
    healthBarTextures = {
        blizzard = "EUI-Blizzard", melli = "EUI-Melli", ["sm:Test Texture"] = "SM-Test-Path",
    },
    healthBarTextureNames = {
        none = "None", blizzard = "Blizzard", melli = "Melli", ["sm:Test Texture"] = "Test Texture",
    },
    healthBarTextureOrder = { "none", "blizzard", "melli", "---", "sm:Test Texture" },
}
function EllesmereNameplates_NS.ApplyCastBarTexture(p)
    p.cast:SetStatusBarTexture("new-engine-texture")
    p.castBarOverlay:SetTexture("new-engine-overlay")
end
function EllesmereNameplates_NS.NT_Apply(p)
    if not p.unit then return end
    local alpha = p._oorCurAlpha or 1 -- this fixture's plate is the current target
    if (p._ntCurAlpha or 1) ~= alpha then
        p._ntCurAlpha = alpha
        p:SetAlpha(alpha)
    end
end

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
local borderAPI = assert(loadfile("EllesmereUIExtendNameplates/tests/border-mocks.lua"))()
EllesmereUI = EllesmereUI or {}
for key, value in pairs(borderAPI) do EllesmereUI[key] = value end
if ... == "scaling" then
    UIParent = CreateFrame()
    EllesmereNameplates_NS.db = { profile = { castOverlayEnabled = false } }
    assert(loadfile("EllesmereUINameplates/EllesmereUINameplates_CastOverlay.lua"))("EllesmereUINameplates", EllesmereNameplates_NS)
    local bundles = {}
    function EllesmereNameplates_NS.NPC_AttachPlate(p, bundle)
        bundles[p] = bundle
        bundle.holder:SetParent(p)
    end
    function EllesmereNameplates_NS.NPC_DetachPlate(p)
        local b = bundles[p]
        bundles[p] = nil
        if b then b.holder:SetParent(UIParent) end
    end
    EllesmereUI.AuraKit = { AddGroupToContainer = function(container, spec)
        container.testGroupStyle = spec.style
    end }
    EllesmereNameplates_NS._cachedTargetPlate = plate
    function EllesmereNameplates_NS.GetClassPowerScale() return 1 end
    function EllesmereNameplates_NS.RefreshClassPower() EllesmereNameplates_NS.GetClassPowerScale() end
    function EllesmereNameplates_NS._WCNP_Attach(anchor, rel, left, x, y, width, height, cell, gap, scale, color, empty, bg, power)
        return scale, "renderer", power
    end
end
assert(loadfile("EllesmereUIExtendNameplates/Nameplates.lua"))("EllesmereUIExtendNameplates", namespace)
assert(loadfile("EllesmereUIExtendNameplates/Borders.lua"))("EllesmereUIExtendNameplates", namespace)
assert(loadfile("EllesmereUIExtendNameplates/Glows.lua"))("EllesmereUIExtendNameplates", namespace)
assert(loadfile("EllesmereUIExtendNameplates/Text.lua"))("EllesmereUIExtendNameplates", namespace)
assert(loadfile("EllesmereUIExtendNameplates/Scaling.lua"))("EllesmereUIExtendNameplates", namespace)
assert(loadfile("EllesmereUIExtendNameplates/TargetArrows.lua"))("EllesmereUIExtendNameplates", namespace)
assert(loadfile("EllesmereUIExtendNameplates/CastStyles.lua"))("EllesmereUIExtendNameplates", namespace)
assert(EllesmereUIExtendNameplatesDB == nil, "new SavedVariables initialized before ADDON_LOADED")
local api = EllesmereUIExtendNameplates
assert(api, "public API missing")
if ... == "traits" or ... == "scaling" then
    return { api = api, namespace = namespace, mocks = traitMocks, secret = secretValue,
        plate = plate, frames = frames, Flush = Flush, Fire = Fire }
end

-- Model the fresh Extras SavedVariables loading after addon chunks execute.
EllesmereUIExtendNameplatesDB = Settings("Loaded rule", 150, 0.2)
Fire("ADDON_LOADED", "EllesmereUIExtendNameplates")
assert(api.GetSettings() == EllesmereUIExtendNameplatesDB.profiles.Default)
assert(type(api.GetRules()[1].conditions.target) == "table"
    and api.GetRules()[1].conditions.target.yes == true,
    "legacy scalar target condition was not migrated to a selection set")
assert(type(api.GetRules()[1].conditions.unitType) == "table"
    and next(api.GetRules()[1].conditions.unitType) == nil,
    "missing condition should normalize to an empty (Any) selection")
assert(api.GetProfileInfo().character == "TestCharacter - TestRealm")
assert(api.GetProfileInfo().active == "Default")
assert(EllesmereUIExtendNameplatesDB.characterProfiles["TestCharacter - TestRealm"] == "Default")
assert(namespace.FindRule("nameplate1").name == "Loaded rule")
Near(plate.scale, 1.5, "saved scale")
Near(plate.health.color[1], 0.2, "saved color")

-- Profile loading/switching must preserve Any, No-only, and omitted target selections.
local loadedStore = EllesmereUIExtendNameplatesDB
EllesmereUIExtendNameplatesDB = { profiles = { Default = { rules = {
    { name = "Any target", conditions = { target = {} } },
    { name = "Not target", conditions = { target = { no = true } } },
    { name = "Generic rule", conditions = {} },
} } } }
local function CheckTargetSelections()
    local rules = api.GetRules()
    assert(next(rules[1].conditions.target) == nil, "reload/switch changed Any target to Yes")
    assert(rules[2].conditions.target.no and not rules[2].conditions.target.yes,
        "reload/switch changed No-only target to both states")
    assert(next(rules[3].conditions.target) == nil, "missing generic target must stay unrestricted")
end
CheckTargetSelections()
assert(api.CreateProfile("Target regression"))
local startersByName = {}
for _, starter in ipairs(api.GetRules()) do startersByName[starter.name] = starter end
assert(next(startersByName["Elite Enemies"].conditions.target) == nil, "starter elite rule must allow non-targets")
assert(next(startersByName["Enemy Casting"].conditions.target) == nil, "starter casting rule must allow non-targets")
local originalIsUnit, originalClassification = UnitIsUnit, UnitClassification
UnitIsUnit = function() return false end
UnitClassification = function() return "elite" end
assert(namespace.FindRule("nameplate1").name == "Elite Enemies", "non-target elite starter cannot win")
UnitClassification = originalClassification
activeCast = "casting"
assert(namespace.FindRule("nameplate1").name == "Enemy Casting", "non-target casting starter cannot win")
activeCast, UnitIsUnit = nil, originalIsUnit
assert(api.SelectProfile("Default"))
CheckTargetSelections()
assert(namespace.FindRule("nameplate1").name == "Any target", "generic Any rule must match current target")
api.GetRules()[1].enabled = false
assert(namespace.FindRule("nameplate1").name == "Generic rule", "No-only rule must reject current target")
UnitIsUnit = function() return false end
assert(namespace.FindRule("nameplate1").name == "Not target", "No-only rule must match non-target")
UnitIsUnit = originalIsUnit
EllesmereUIExtendNameplatesDB = loadedStore
api.Refresh(); Flush()

-- Replacing the table must not leave the renderer reading its previous rules.
EllesmereUIExtendNameplatesDB = Settings("Replacement rule", 115, 0.6)
api.Refresh(); Flush()
assert(api.GetRules() == EllesmereUIExtendNameplatesDB.profiles.Default.rules)
assert(namespace.db.profile == EllesmereUIExtendNameplatesDB.profiles.Default)
Near(plate.scale, 1.15, "replacement scale")
Near(plate.health.color[1], 0.6, "replacement color")

-- The shared Default is the starting point, and character assignments are independent.
api.GetSettings().rules[1].name = "Shared Default"
local created, profileError = api.CreateProfile("Tank")
assert(created, tostring(profileError) .. "; character=" .. tostring(api.GetProfileInfo().character))
assert(api.GetProfileInfo().active == "Tank")
assert(api.GetSettings().rules[1].name == api.DefaultRules[1].name, "new profile should start with built-in rules")
Near(api.GetSettings().rules[1].style.healthColor.r, api.DefaultRules[1].style.healthColor.r, "new profile built-in health color")
api.GetSettings().rules[1].name = "Tank Rule"
playerName = "AltCharacter"
assert(api.GetProfileInfo().active == "Default", "new character should start on shared Default")
assert(api.GetSettings().rules[1].name == "Shared Default", "Default isn't shared across characters")
local selected, selectError = api.SelectProfile("Tank")
assert(selected, selectError)
assert(api.GetSettings().rules[1].name == "Tank Rule")
api.GetSettings().rules[1].name = "Shared Tank Rule"
playerName = "TestCharacter"
assert(api.GetProfileInfo().active == "Tank" and api.GetSettings().rules[1].name == "Shared Tank Rule",
    "named profile should be shared by characters assigned to it")
local renamedShared, renameSharedError = api.RenameProfile("Main Tank")
assert(renamedShared, renameSharedError)
assert(api.GetProfileInfo().active == "Main Tank")
local createdOther, createOtherError = api.CreateProfile("DPS")
assert(createdOther, createOtherError)
assert(api.GetSettings().rules[1].name == api.DefaultRules[1].name, "new profile should use fresh built-in rules")
local renamedProfile, renameError = api.RenameProfile("Raid")
assert(renamedProfile, renameError)
assert(api.GetProfileInfo().active == "Raid")
local deletedProfile, deleteError = api.DeleteProfile()
assert(deletedProfile, deleteError)
assert(api.GetProfileInfo().active == "Default" and api.GetSettings().rules[1].name == "Shared Default",
    "deleting an assigned profile should return this character to Default")
playerName = "AltCharacter"
assert(api.GetProfileInfo().active == "Main Tank", "renaming a shared profile should update its other character assignment")
local deletedShared, deleteSharedError = api.DeleteProfile()
assert(deletedShared, deleteSharedError)
playerName = "TestCharacter"
assert(api.GetProfileInfo().active == "Default", "deleting a shared profile should return all assigned characters to Default")
assert(not api.DeleteProfile(), "Default profile should not be deletable")
assert(not api.RenameProfile("Renamed Default"), "Default profile should not be renamable")
playerName = "AltCharacter"
assert(api.GetProfileInfo().active == "Default")
playerName = "TestCharacter"

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

local rows, spec, registeredID = {}, nil, nil
local sectionHeaders = {}
local parent = CreateFrame()
local contentHeader = CreateFrame()
local W = {}
local widgetRefreshes = {}
function W:SectionHeader(_, text)
    if text == "RULE STYLING" or text == "NAMEPLATE EXTRAS" then
        for index = #sectionHeaders, 1, -1 do sectionHeaders[index] = nil end
    end
    sectionHeaders[#sectionHeaders + 1] = text
    return {}, 40
end
function W:Button(parent, text, y, click)
    if EllesmereUI.IsSearchPrebuild() then return {}, 50 end
    local row = CreateFrame("Frame", nil, parent)
    local button = CreateFrame("Button", nil, row)
    function row:GetChildren() return button end
    rows[text] = { click = click, row = row, button = button, y = y }
    return row, 50
end
function W:WideButton(_, text, _, click)
    rows[text] = { click = click }
    return {}, 62
end
function W:WideDualButton(_, first, second, _, onFirst, onSecond, _)
    local row = EllesmereUI.IsSearchPrebuild() and {} or CreateFrame()
    rows[first] = { click = onFirst, row = row }
    rows[second] = { click = onSecond, row = row }
    return row, 57
end
function W:WideTripleButton(_, first, second, third, _, onFirst, onSecond, onThird, _)
    local row = EllesmereUI.IsSearchPrebuild() and {} or CreateFrame()
    rows[first] = { click = onFirst, row = row }
    rows[second] = { click = onSecond, row = row }
    rows[third] = { click = onThird, row = row }
    return row, 57
end
function W:Toggle(_, text, _, get, set) rows[text] = { get = get, set = set }; return {}, 50 end
function W:Spacer(parent, y, height)
    if EllesmereUI.IsSearchPrebuild() then return {}, height end
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth(), height)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    return row, height
end
function W:Slider(_, text, _, _, _, _, get, set) rows[text] = { get = get, set = set }; return {}, 50 end
function W:Dropdown(_, text, _, values, get, set) rows[text] = { get = get, set = set, values = values }; return {}, 50 end
function W:DualRow(_, _, config, right)
    -- Search DualRow returns a frameless absorber; even its regions are placeholders.
    if EllesmereUI.IsSearchPrebuild() then
        local meta
        meta = { __index = function(_, key)
            if type(key) ~= "number" then return setmetatable({}, meta) end
        end, __call = function() return setmetatable({}, meta) end,
            __add = function() return 100 end }
        return setmetatable({}, meta), 40
    end
    if config.type == "spacer" then
        local row = CreateFrame()
        row._leftRegion = CreateFrame("Frame", nil, row)
        row._rightRegion = CreateFrame("Frame", nil, row)
        if right and right.type == "toggle" then
            rows[right.text] = { get = right.getValue, set = right.setValue, row = row,
                disabled = right.disabled, disabledTooltip = right.disabledTooltip }
        end
        return row, 50
    end
    local row = CreateFrame()
    row._leftRegion = CreateFrame("Frame", nil, row)
    row._rightRegion = CreateFrame("Frame", nil, row)
    for _, cfg in ipairs({ config, right }) do
        if cfg.type == "colorpicker" then assert(type(cfg.getValue()) == "number") end
        rows[cfg.text] = { get = cfg.getValue, set = cfg.setValue, disabled = cfg.disabled,
            disabledTooltip = cfg.disabledTooltip, values = cfg.values, row = row }
    end
    return row, 50
end
function W:ColorPicker(_, text, _, get, set)
    assert(type(get()) == "number", "color getter must return RGB components")
    rows[text] = { get = get, set = set }
    return {}, 50
end
local wirePayloads, wireSerial = {}, 0
local function CloneWire(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = CloneWire(item) end
    return result
end
local deflate = {
    CompressDeflate = function(_, value) return value end,
    EncodeForPrint = function(_, value) return value end,
    DecodeForPrint = function(_, value) return value end,
    DecompressDeflate = function(_, value) return value end,
}
function LibStub(name)
    if name == "LibDeflate" then return deflate end
end
local exportedPopup, importedPopup, legacyImportPopup, deleteConfirm
EllesmereUI = {
    PP = borderAPI.PP, ApplyBorderStyle = borderAPI.ApplyBorderStyle, GetBorderTextureDropdown = borderAPI.GetBorderTextureDropdown,
    Widgets = W,
    BuildInlineCog = function(region, opts)
        assert(region and region.nativeFrame, "cog needs a native region")
        rows[opts.title] = opts
        return CreateFrame("Button", nil, region)
    end,
    MakeStyledButton = function(button, text, _, _, click)
        rows[text] = { click = click, row = button.parent, button = button }
    end,
    MakeFont = function(parent) return parent:CreateFontString() end,
    L = function(text) return text end,
    RegisterWidgetRefresh = function(callback) widgetRefreshes[#widgetRefreshes + 1] = callback end,
    ShowWidgetTooltip = Noop,
    HideWidgetTooltip = Noop,
    BuildVisOptsCBDropdown = function(parent, width, frameLevel, items, get, set, _, _, _, _, _, opts)
        local button = CreateFrame("Button", nil, parent)
        button:SetSize(width, 30)
        button:SetFrameLevel(frameLevel)
        rows[opts.label] = { get = get, set = set, items = items, emptyLabel = opts.emptyLabel, row = parent.parent, button = button }
        return button, Noop
    end,
    ResolveTexturePath = function(textureTable, key, fallback) return textureTable[key] or fallback end,
    CONTENT_PAD = 20,
    PanelPP = {
        Size = function(frame, width, height) frame:SetSize(width, height) end,
        Point = function(frame, ...) frame:SetPoint(...) end,
    },
    _contentHeader = contentHeader,
    SetContentHeader = function(self, builder)
        self:ClearContentHeader()
        contentHeader:Show()
        contentHeader:SetHeight(builder(contentHeader, contentHeader:GetWidth()))
    end,
    ClearContentHeader = function()
        local p = contentHeader._extrasRulePreview
        if p then p:Hide(); p:SetParent(nil) end
        contentHeader._extrasRulePreview = nil
        contentHeader:Hide()
    end,
    UpdateContentHeaderHeight = function(_, height) contentHeader:SetHeight(height) end,
    IsSearchPrebuild = function() return false end,
    _Serializer = {
        Serialize = function(payload)
            wireSerial = wireSerial + 1
            wirePayloads[tostring(wireSerial)] = CloneWire(payload)
            return tostring(wireSerial)
        end,
        Deserialize = function(value) return CloneWire(wirePayloads[value]) end,
    },
    ShowCopyPopup = function(_, title, subtitle, code)
        exportedPopup = { title = title, subtitle = subtitle, code = code }
    end,
    ShowImportStringPopup = function(_, title, subtitle, confirmText, callback)
        importedPopup = { title = title, subtitle = subtitle, confirmText = confirmText, onConfirm = callback }
    end,
    ShowInputPopup = function(_, options) legacyImportPopup = options end,
    ShowConfirmPopup = function(_, options) deleteConfirm = options end,
    PrintError = Noop,
    Print = Noop,
    RegisterPlugin = function(id, value) registeredID = id; spec = value; return true end,
    IsPluginRegistered = function() return false end,
    GetPluginModuleKey = function() return "plugin:test:Styles" end,
    InvalidateModulePageCache = Noop,
    RefreshPage = function()
        for i = #widgetRefreshes, 1, -1 do widgetRefreshes[i] = nil end
        spec.modules[1].buildPage("Rules", parent, 0)
    end,
}
assert(loadfile("EllesmereUIExtendNameplates/RuleIO.lua"))()
assert(loadfile("EllesmereUIExtendNameplates/Preview.lua"))()
assert(loadfile("EllesmereUIExtendNameplates/Options.lua"))()
Fire("PLAYER_LOGIN")
assert(registeredID == "EllesmereUIExtendNameplates")
assert(spec.label == "Extend Nameplates")
assert(spec.modules[1].key == "NameplateStyle" and spec.modules[1].title == "Nameplate Style")
assert(spec.modules[1].pages[2] == "Profiles" and spec.modules[1].pages[3] == "Sharing")
spec.modules[1].buildPage("Rules", parent, 0)
assert(rows["Edit rule"].row == rows["Rule name"].row, "selector and name must share a row")
assert(rows["Nameplate size (%)"].row == rows["Opacity (%)"].row, "nameplate size and opacity must share a row")
if ... == "ui-locks" then
    return { api = api, namespace = namespace, rows = rows, spec = spec, parent = parent,
        plate = plate, frames = frames, Flush = Flush, refreshes = widgetRefreshes,
        header = contentHeader, secret = secretValue, GetPreview = function() return contentHeader._extrasRulePreview end,
        GetConfirm = function() return deleteConfirm end }
end
local masterToggle = assert(rows["Enable rule styling"], "Rules page is missing the global toggle")
local storedRules, storedSelection = api.GetRules(), api.GetSettings().selectedRule
local enabledFlags = {}
for i, rule in ipairs(storedRules) do enabledFlags[i] = rule.enabled end
local styledScale = plate:GetScale()
masterToggle.set(false); Flush()
assert(not masterToggle.get() and api.GetSettings().enabled == false)
assert(api.GetRules() == storedRules and api.GetSettings().selectedRule == storedSelection,
    "global disable replaced rules or changed selection")
for i, rule in ipairs(storedRules) do assert(rule.enabled == enabledFlags[i], "global disable changed individual rule flags") end
Near(plate:GetScale(), 1.2, "global disable restores engine scale")
local storedScale = storedRules[1].style.scale
rows["Nameplate size (%)"].set(storedScale + 5); Flush()
assert(rows["Nameplate size (%)"].disabled() and storedRules[1].style.scale == storedScale,
    "global styling off must lock rule edits")
Near(plate:GetScale(), 1.2, "locked edits must not apply live styling")
rows["Nameplate size (%)"].set(storedScale); Flush()
masterToggle.set(true); Flush()
Near(plate:GetScale(), styledScale, "global reenable restores rule appearance")
assert(api.GetRules() == storedRules and api.GetSettings().selectedRule == storedSelection,
    "global reenable changed rules or selection")
for i, rule in ipairs(storedRules) do assert(rule.enabled == enabledFlags[i], "global reenable changed individual rule flags") end
rows["Enable rule styling"] = nil
local beforeAbout = #frames
local oldMetadata = C_AddOns
C_AddOns = { GetAddOnMetadata = function(name, key)
    assert(name == "EllesmereUIExtendNameplates" and key == "Version")
    return "test-version"
end }
local aboutHeight = spec.modules[1].buildPage("About", parent, 0)
C_AddOns = oldMetadata
assert(rows["Enable rule styling"] == nil, "About must not contain the global toggle")
assert(aboutHeight > 200, "About page is missing its summary")
local aboutText = {}
for i = beforeAbout + 1, #frames do
    local frame = frames[i]
    if frame.kind == "FontString" and frame.text then
        assert(frame.wordWrap == true and frame.width > 0, "About paragraphs must wrap to the page width")
        aboutText[#aboutText + 1] = frame.text
    end
end
local aboutBody = table.concat(aboutText, "\n")
for _, detail in ipairs({ "test-version", "rule-based styling", "size and opacity", "quest objectives",
    "interruptible casts", "interrupts on cooldown", "uninterruptible casts", "profiles", "export or import",
    "Enable rule styling", "without deleting" }) do
    assert(aboutBody:find(detail, 1, true), "About is missing " .. detail)
end
assert(rows["Open Nameplate Style Rules"], "About must retain its Rules navigation button")
spec.modules[1].buildPage("Rules", parent, 0)

spec.modules[1].buildPage("Profiles", parent, 0)
assert(rows["Profile for this character"].values.Default,
    "Profiles page doesn't list the shared Default profile")
rows["Create Profile"].click()
assert(legacyImportPopup and legacyImportPopup.title == "Create Nameplate Profile")
legacyImportPopup.onConfirm("UI Test Profile")
assert(api.GetProfileInfo().active == "UI Test Profile", "Profiles tab didn't create/select its profile")
assert(api.GetSettings().rules[1].name == api.DefaultRules[1].name, "Profiles tab didn't create a fresh profile")
rows["Profile for this character"].set("Default")
assert(api.GetProfileInfo().active == "Default", "Profiles tab didn't switch back to Default")
spec.modules[1].buildPage("Rules", parent, 0)
local ruleCode = assert(api.ExportRuleSet())
assert(ruleCode:sub(1, 17) == "!EUI_NPEX_RULES2!", "standalone export prefix missing")
local wirePayload = wirePayloads[ruleCode:sub(18)]
assert(type(wirePayload.rules[1].conditions.unitType) == "table",
    "export should serialize multi-select conditions")
spec.modules[1].buildPage("Sharing", parent, 0)
rows["Export Rule Set"].click()
assert(exportedPopup and exportedPopup.code:sub(1, 17) == "!EUI_NPEX_RULES2!",
    "export action didn't display the share code")
rows["Import Rule Set"].click()
assert(importedPopup and importedPopup.title == "Import Nameplate Rules"
    and importedPopup.confirmText == "Import Rules", "import should use the shared scrollable string popup")
local exportedRuleName = api.GetRules()[1].name
api.GetRules()[1].name = "Temporary edit"
local importOK, importError = api.ImportRuleSet(ruleCode)
assert(importOK, importError)
assert(api.GetRules()[1].name == exportedRuleName, "import didn't restore the exported rules")
local currentRules = api.GetRules()
local invalidOK = api.ImportRuleSet("not a rule-set code")
assert(not invalidOK and api.GetRules() == currentRules, "invalid import replaced the live rules")
local exportedUnitType = wirePayload.rules[1].conditions.unitType
wirePayload.rules[1].conditions.unitType = { invalidChoice = true }
local invalidConditionOK = api.ImportRuleSet(ruleCode)
assert(not invalidConditionOK and api.GetRules() == currentRules,
    "import accepted an unknown multi-select condition")
wirePayload.rules[1].conditions.unitType = exportedUnitType
wirePayload.rules[1].conditions.unitType = "npc"
wirePayload.version = 1
local legacyRuleCode = "!EUI_NPEX_RULES1!" .. ruleCode:sub(18)
local legacyConditionOK, legacyConditionError = api.ImportRuleSet(legacyRuleCode)
assert(legacyConditionOK, legacyConditionError)
assert(api.GetRules()[1].conditions.unitType.npc == true,
    "legacy scalar import was not normalized to a selection set")
wirePayload.version = 2
wirePayload.rules[1].conditions.unitType = exportedUnitType
assert(api.ImportRuleSet(ruleCode), "could not restore the exported multi-select rule")
importedPopup.onConfirm(ruleCode)
assert(api.GetRules()[1].name == exportedRuleName, "paste popup didn't apply the exported rules")
local scrollImportPopup = EllesmereUI.ShowImportStringPopup
EllesmereUI.ShowImportStringPopup = nil -- emulate a Retail EUI install predating this helper
rows["Import Rule Set"].click()
assert(legacyImportPopup and legacyImportPopup.maxLetters == api.RuleSetMaxCodeLength,
    "older EUI should use the compatible one-line import field")
legacyImportPopup.onConfirm(ruleCode)
assert(api.GetRules()[1].name == exportedRuleName, "legacy EUI import fallback failed")
EllesmereUI.ShowImportStringPopup = scrollImportPopup
assert(rows["Health-bar texture"].values.melli == "Melli")
assert(rows["Cast-bar texture"].values["sm:Test Texture"] == "Test Texture")
local function HasHeader(text)
    for _, header in ipairs(sectionHeaders) do
        if header == text then return true end
    end
    return false
end
assert(HasHeader("RULE ORDER"), table.concat(sectionHeaders, " | "))
assert(rows["Edit rule"].values["1"] == "[1] Shared Default")
assert(HasHeader("MATCH CONDITIONS"))
assert(HasHeader("APPEARANCE - NAMEPLATE"))
assert(HasHeader("APPEARANCE - HEALTH BAR"))
assert(HasHeader("APPEARANCE - CAST BAR"))
local actions = { "Add Rule", "Copy Rule", "Delete Rule", "Move Rule Up", "Move Rule Down" }
for index, text in ipairs(actions) do
    local action = rows[text]
    assert(action.row == rows[actions[1]].row, "all five actions must share one row")
    assert(action.button.point[2] == action.row and action.button.point[5] == 0, "button anchor must stay relative to shared row")
end
rows["Nameplate size (%)"].set(120)
rows["Health-bar color"].set(0.9, 0.8, 0.7)
Flush()
Near(plate.scale, 1.44, "options slider changes live scale")
Near(plate.health.color[1], 0.9, "options picker changes live color")
assert(rows["Quest Objective"].get() == false)
rows["Quest Objective"].set(true)
assert(api.GetRules()[1].conditions.questObjective == "yes")
api.GetRules()[1].conditions.questObjective = "yes"
questObjective = false
assert(namespace.FindRule("nameplate1") == nil, "quest condition matched a non-objective")
questObjective = true
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "quest objective condition failed to match")
rows["Quest Objective"].set(false)
assert(api.GetRules()[1].conditions.questObjective == "any", "quest toggle off must remove the condition")

-- Every category uses OR within its selection, while separate condition fields still AND.
local unitType = rows["Unit type"]
local reaction = rows["Reaction"]
local classification = rows["Classification"]
local targetState = rows["Target state"]
local threatState = rows["Threat"]
local castState = rows["Cast state"]
local spellSchool = rows["Spell school"]
assert(unitType and reaction and classification and targetState and threatState and castState and spellSchool,
    "categorical multi-select controls were not built")
assert(threatState.emptyLabel == "Any threat" and #threatState.items == 3, "Threat choices missing")
assert(threatState.row == rows["Quest Objective"].row, "Threat and Quest Objective must share a row")
threatState.set("me", true)
assert(api.GetRules()[1].conditions.threat.me, "Threat on me was not saved")
local originalDetailedThreat = UnitDetailedThreatSituation
UnitDetailedThreatSituation = function(participant) assert(participant == "player"); return true end
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "Threat on me UI selection did not match")
threatState.set("tank", true)
assert(threatState.get("me") and threatState.get("tank"), "Threat selections must preserve other choices")
threatState.set("tank", false)
threatState.set("me", false)
UnitDetailedThreatSituation = originalDetailedThreat
local hasNoTargetItem = false
for _, item in ipairs(targetState.items) do
    if item.key == "none" and item.label == "No target selected" then hasNoTargetItem = true end
end
assert(hasNoTargetItem, "Target state must expose No target selected")
targetState.set("yes", false)
targetState.set("none", true)
assert(api.GetRules()[1].conditions.target.none, "no-target choice was not saved")
traitMocks.targetExists = false
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "UI no-target choice must match without a selected target")
traitMocks.targetExists = nil
assert(namespace.FindRule("nameplate1") == nil, "UI no-target choice must reject a selected target")
targetState.set("none", false)
targetState.set("yes", true)
-- Custom-style color choices explain their lock and preserve selections across styles.
local np = EllesmereNameplates_NS
local originalStyle, originalDB, originalLatched = np.NP_Style, np.db, np._npStyle
local renderedStyle = "eui"
np.NP_Style = function() return renderedStyle end
local castItems = {}
for _, item in ipairs(castState.items) do castItems[item.key] = item end
local originalCastSelection = api.GetRules()[1].conditions.castState
for _, key in ipairs({ "interruptible", "interruptOnCD", "uninterruptible" }) do
    assert(castItems[key].lockedFn and not castItems[key].lockedFn(), "EUI cast color choice must be enabled")
    assert(castItems[key].lockedTooltip():find("Enable EUI or Classic WoW UI", 1, true), "style lock must explain supported styles")
    castState.set(key, true)
end
for _, style in ipairs({ "blizzard", "forever" }) do
    renderedStyle = style
    for _, key in ipairs({ "interruptible", "interruptOnCD", "uninterruptible" }) do
        assert(castItems[key].lockedFn(), "Blizzard/Forever cast color choice must be inactive")
        castState.set(key, false)
        assert(castState.get(key), "inactive choices must preserve saved selections")
    end
    for _, key in ipairs({ "none", "casting", "channel", "empowered" }) do
        assert(not castItems[key].lockedFn(), "ordinary cast choices must remain available")
    end
end
renderedStyle = "classic"
for _, key in ipairs({ "interruptible", "interruptOnCD", "uninterruptible" }) do
    assert(not castItems[key].lockedFn(), "Classic WoW UI cast color choice must be available")
    castState.set(key, false)
    assert(not castState.get(key), "Classic WoW UI must allow editing cast color choices")
    castState.set(key, true)
end
renderedStyle = "blizzard"
np.db = { profile = { useBlizzardStyle = true, useForeverStyle = true } }
assert(castItems.interruptible.lockedFn(), "Forever variant uses Blizzard rendering and must remain locked")
np.db = { profile = { useBlizzardStyle = false, useClassicStyle = false } }
assert(castItems.interruptible.lockedFn(), "pending EUI profile change must not bypass latched Blizzard rendering")
renderedStyle = "eui"
np.db.profile.useBlizzardStyle = true
assert(not castItems.interruptible.lockedFn(), "pending Blizzard profile change must not lock live EUI rendering")
np.NP_Style, np._npStyle = nil, nil
assert(castItems.interruptible.lockedFn(), "older API fallback must detect Blizzard style")
np.db.profile.useBlizzardStyle, np.db.profile.useClassicStyle = false, true
assert(not castItems.interruptible.lockedFn(), "older API fallback must allow Classic style")
np.db.profile.useBlizzardStyle = true
assert(not castItems.interruptible.lockedFn(), "Classic must take precedence when both flags are set")
np._npStyle = "blizzard"
assert(castItems.interruptible.lockedFn(), "cached Blizzard rendering stays locked despite pending Classic settings")
np._npStyle = "classic"
assert(not castItems.interruptible.lockedFn(), "cached Classic rendering must be allowed")
np._npStyle = "eui"
assert(not castItems.interruptible.lockedFn(), "cached rendering style takes precedence over profile flags")
np.NP_Style, np.db, np._npStyle = originalStyle, originalDB, originalLatched
api.GetRules()[1].conditions.castState = originalCastSelection
for _, key in ipairs({ "interruptible", "interruptOnCD", "uninterruptible" }) do castState.set(key, false) end
unitType.set("player", true)
unitType.set("npc", true)
assert(api.GetRules()[1].conditions.unitType.player and api.GetRules()[1].conditions.unitType.npc)
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "unit type selections should OR together")
unitType.set("npc", false)
assert(namespace.FindRule("nameplate1") == nil, "different condition groups should still AND together")
unitType.set("player", false)
reaction.set("friendly", true)
assert(namespace.FindRule("nameplate1") == nil, "a nonmatching reaction should fail")
reaction.set("enemy", true)
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "reaction selections should OR together")
reaction.set("friendly", false)
reaction.set("enemy", false)
classification.set("elite", true)
assert(namespace.FindRule("nameplate1") == nil, "classification should reject an unmatched rank")
classification.set("normal", true)
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "classification selections should OR together")
classification.set("elite", false)
classification.set("normal", false)
targetState.set("no", true)
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "target yes/no alternatives should OR together")
targetState.set("yes", false)
assert(namespace.FindRule("nameplate1") == nil, "target state should reject the current target when only No is selected")
targetState.set("no", false)
targetState.set("yes", true)
castState.set("none", true)
castState.set("casting", true)
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "cast-state selections should OR together")
castState.set("none", false)
assert(namespace.FindRule("nameplate1") == nil, "cast state should reject a unit outside the selected alternatives")
activeCast = "casting"
assert(api.RegisterSpellSchool(123, "fire"), "spell school registration failed")
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "selected casting state did not match")
castState.set("channel", true)
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "cast-state alternatives should match active casts")
castState.set("casting", false)
assert(namespace.FindRule("nameplate1") == nil, "a nonselected cast state should not match")
activeCast = "channel"
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "channel state should match its selected alternative")
castState.set("channel", false)
activeCast = "casting"
castState.set("interruptible", true)
assert(not castState.get("casting"), "Interruptible must not visibly select Casting")
castState.set("casting", true)
assert(castState.get("casting"), "Casting can be selected explicitly for all casts")
castState.set("casting", false)
assert(not castState.get("casting"), "implicit Casting must not force its checkbox on")
traitMocks.casting = { "Secret cast", nil, nil, nil, nil, nil, nil, secretValue, secretValue }
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "color-state selection must imply Casting for appearance effects")
traitMocks.casting = nil
castState.set("interruptible", false)
castState.set("casting", true)
castState.set("uninterruptible", true)
assert(not castState.get("casting"), "Uninterruptible should replace broad Casting without exposing it")
castState.set("uninterruptible", false)
castState.set("casting", true)
castState.set("empowered", true)
assert(not castState.get("casting"), "Empowered should not expose implicit Casting")
castState.set("empowered", false)
castState.set("casting", false)
spellSchool.set("fire", true)
spellSchool.set("frost", true)
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "spell-school alternatives should match active casts")
spellSchool.set("fire", false)
assert(namespace.FindRule("nameplate1") == nil, "spell school should reject a nonselected school")
spellSchool.set("frost", false)
activeCast = nil
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "empty school selection should mean Any")

rows["Add Rule"].click(); Flush()
assert(rows["Edit rule"].values["1"] == "[1] Custom Rule 2")
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "new rule not selected by renderer")
Near(plate.scale, 1.2, "new rule scale")
Near(plate.health.color[1], 1, "new rule color")

local renamed = api.GetRules()[1]
local style, conditions = renamed.style, renamed.conditions
rows["Rule name"].set("  My Target Rule  ")
assert(renamed.name == "My Target Rule", "rename must trim and save")
assert(rows["Edit rule"].values["1"] == "[1] My Target Rule", "dropdown label not updated")
assert(HasHeader("APPEARANCE - NAMEPLATE"), "stable appearance section missing after rename")
assert(api.GetSettings().selectedRule == 1 and api.GetRules()[1] == renamed, "rename changed order or selection")
assert(renamed.style == style and renamed.conditions == conditions, "rename changed rule behavior")
rows["Rule name"].set(" \t\n ")
assert(renamed.name == "My Target Rule", "blank name replaced existing name")
local oldNameField = rows["Rule name"]
rows["Copy Rule"].click(); Flush()
local copy = api.GetRules()[2]
assert(copy ~= renamed and copy.name == "My Target Rule Copy", "copy did not create a named rule")
assert(copy.conditions ~= renamed.conditions and copy.style ~= renamed.style, "copy shares mutable rule tables")
assert(copy.conditions.target.yes == renamed.conditions.target.yes
    and copy.conditions.target ~= renamed.conditions.target
    and copy.style.scale == renamed.style.scale,
    "copy did not preserve rule settings")
assert(api.GetSettings().selectedRule == 2 and rows["Rule name"].get() == copy.name,
    "copy was not selected for editing")
rows["Edit rule"].set("3")
assert(rows["Edit rule"].values["3"] == "[3] Shared Default")
oldNameField.set("Target Rule")
assert(renamed.name == "Target Rule" and api.GetRules()[3].name == "Shared Default",
    "focus-loss commit renamed the wrong rule")
rows["Edit rule"].set("1")
assert(rows["Rule name"].get() == "Target Rule", "rename lost after page rebuild")
rows["Move Rule Down"].click(); Flush()
assert(rows["Edit rule"].values["2"] == "[2] Target Rule" and api.GetRules()[2] == renamed)
rows["Move Rule Up"].click(); Flush()
assert(rows["Edit rule"].values["1"] == "[1] Target Rule" and api.GetRules()[1] == renamed)

EllesmereUI.IsSearchPrebuild = function() return true end
spec.modules[1].buildPage("Rules", {}, 0)
EllesmereUI.IsSearchPrebuild = function() return false end
spec.modules[1].buildPage("Rules", parent, 0)

rows["Nameplate size (%)"].set(115); Flush()
api.GetRules()[1].style.opacity = 50
plate._oorCurAlpha = 0.4
EllesmereNameplates_NS.NT_Apply(plate); Flush()
Near(plate.alpha, 0.2, "engine root alpha composition")
EllesmereNameplates_NS.NT_Apply(plate); Flush()
Near(plate.alpha, 0.2, "cached engine root alpha composition")
plate:ClearUnit()
Near(plate.scale, 1, "pool release preserves engine reset scale")
Near(plate.alpha, 1, "pool release preserves engine reset alpha")
plate.unit = "nameplate1"
plate:ApplyScale(); api.Refresh(); Flush()
Near(plate.scale, 1.15, "recycled plate scale")
Near(plate.alpha, 0.5, "recycled plate starts with full engine alpha")
api.GetSettings().enabled = false
api.Refresh(); Flush()
Near(plate.scale, 1, "disable restores engine scale")
Near(plate.alpha, 1, "disable restores recycled engine alpha")

-- Existing option callbacks must also follow a replaced SavedVariables table.
EllesmereUIExtendNameplatesDB = Settings("Late replacement", 100, 0.1)
rows["Nameplate size (%)"].set(130)
rows["Health-bar color"].set(0.4, 0.5, 0.6)
Flush()
Near(plate.scale, 1.3, "cached options use current settings")
Near(plate.health.color[1], 0.4, "cached color picker uses current settings")
assert(namespace.db.profile == EllesmereUIExtendNameplatesDB.profiles.Default)

rows["Add Rule"].click(); Flush()
local countBeforeDelete = #api.GetRules()
rows["Delete Rule"].click(); Flush()
assert(#api.GetRules() == countBeforeDelete, "rule was deleted before confirmation")
assert(deleteConfirm and deleteConfirm.title == "Delete Nameplate Rule?"
    and deleteConfirm.cancelText == "Keep Rule", "rule delete confirmation wasn't shown")
deleteConfirm.onConfirm()
Flush()
assert(rows["Edit rule"].values["1"] == "[1] Late replacement", "delete must update priority")

-- Cast styling is opt-in, including on existing saved rules.
assert(rows["Override cast bar"].get() == false)
assert(rows["Custom cast color"].disabled())
assert(rows["Cast fill color"].disabled())
assert(plate.cast:GetStatusBarTexture():GetTexture() == "cast-base")
Near(plate.cast:GetStatusBarTexture().vertexColor[1], 0.2, "default cast color untouched")
rows["Override cast bar"].set(true); Flush()
assert(not rows["Custom cast color"].disabled())
assert(rows["Cast fill color"].disabled())
rows["Custom cast color"].set(true)
rows["Cast fill color"].set(0.9, 0.2, 0.1)
rows["Custom cast opacity"].set(true)
rows["Cast opacity (%)"].set(60)
rows["Override cast border"].set(true)
rows["Cast border size"].set(3)
rows["Cast border color"].set(0.1, 0.9, 0.3)
Flush()
Near(plate.cast:GetStatusBarTexture().vertexColor[1], 0.9, "custom cast fill")
Near(plate.castBarOverlay.vertexColor[1], 0.9, "custom uninterruptible fill")
Near(plate.castBarOverlay.alpha, 0.25, "engine interruptibility alpha preserved")
Near(plate.cast.alpha, 0.6, "cast opacity")
local castBorder
for _, frame in ipairs(frames) do
    if frame.parent == plate.cast and frame.kind == "Frame" then castBorder = frame end
end
assert(castBorder and castBorder.shown, "cast border must belong to cast, including lifted casts")

-- Repaints remain styled immediately, but the latest engine paint is restored on disable.
plate.cast:GetStatusBarTexture():SetVertexColor(0.1, 0.4, 0.6, 1)
plate.castBarOverlay:SetVertexColor(0.3, 0.3, 0.3, 1)
plate.cast:SetAlpha(0.8)
Near(plate.cast:GetStatusBarTexture().vertexColor[1], 0.9, "color survives cooldown repaint")
Near(plate.cast.alpha, 0.48, "opacity multiplies fresh base once")
plate._interrupted = true
plate.cast:GetStatusBarTexture():SetVertexColor(1, 0, 0, 1)
Near(plate.cast:GetStatusBarTexture().vertexColor[1], 1, "interrupt flash wins")
api.Refresh(); Flush()
Near(plate.cast:GetStatusBarTexture().vertexColor[2], 0, "refresh preserves interrupt flash")
plate._interrupted = nil
plate.cast:GetStatusBarTexture():SetVertexColor(0.1, 0.4, 0.6, 1)
Near(plate.cast:GetStatusBarTexture().vertexColor[1], 0.9, "next cast gets override")
rows["Custom cast color"].set(false); Flush()
Near(plate.cast:GetStatusBarTexture().vertexColor[1], 0.1, "color toggle restores latest engine paint")
Near(plate.castBarOverlay.vertexColor[1], 0.3, "color toggle restores overlay paint")
rows["Custom cast color"].set(true); Flush()

rows["Cast-bar texture"].set("flat"); Flush()
assert(plate.cast:GetStatusBarTexture():GetTexture() == "Interface\\Buttons\\WHITE8x8")
assert(plate.castBarOverlay:GetTexture() == "Interface\\Buttons\\WHITE8x8")
assert(plate.castSpark.point[2] == plate.cast:GetStatusBarTexture(), "spark must follow replacement fill")
local unchangedFill = plate.cast:GetStatusBarTexture()
api.Refresh(); Flush()
assert(plate.cast:GetStatusBarTexture() == unchangedFill, "ordinary refresh must not replace texture")
EllesmereNameplates_NS.ApplyCastBarTexture(plate)
assert(plate.cast:GetStatusBarTexture():GetTexture() == "Interface\\Buttons\\WHITE8x8", "texture survives engine refresh")
assert(plate.castSpark.point[2] == plate.cast:GetStatusBarTexture(), "spark follows engine texture refresh")
rows["Cast-bar texture"].set("melli"); Flush()
assert(plate.cast:GetStatusBarTexture():GetTexture() == "EUI-Melli", "cast selector should resolve EUI textures")
rows["Cast-bar texture"].set("sm:Test Texture"); Flush()
assert(plate.cast:GetStatusBarTexture():GetTexture() == "SM-Test-Path", "cast selector should resolve SharedMedia textures")
rows["Cast-bar texture"].set("flat"); Flush()
rows["Override cast bar"].set(false); Flush()
assert(plate.cast:GetStatusBarTexture():GetTexture() == "new-engine-texture")
assert(plate.castSpark.point[2] == plate.cast:GetStatusBarTexture(), "spark follows restored texture")
assert(plate.castBarOverlay:GetTexture() == "new-engine-overlay")
Near(plate.cast.alpha, 0.8, "disable restores latest engine opacity")
Near(plate.castBarOverlay.vertexColor[1], 0.3, "disable restores latest overlay color")
assert(not castBorder.shown)

-- Atlas-based stock artwork is never replaced by a texture override.
plate._blizzCastArt = true
rows["Override cast bar"].set(true); Flush()
assert(plate.cast:GetStatusBarTexture():GetTexture() == "new-engine-texture")
plate._blizzCastArt = nil
api.Refresh(); Flush()
assert(plate.cast:GetStatusBarTexture():GetTexture() == "Interface\\Buttons\\WHITE8x8")
plate:ClearUnit()
assert(plate.cast:GetStatusBarTexture():GetTexture() == "new-engine-texture")
assert(not castBorder.shown, "pool release hides cast border")
plate.unit = "nameplate1"
api.Refresh(); Flush()
assert(castBorder.shown)
api.GetRules()[1].conditions.target = "no"
api.Refresh(); Flush()
assert(not castBorder.shown, "unmatching restores cast")
assert(plate.cast:GetStatusBarTexture():GetTexture() == "new-engine-texture")
api.GetRules()[1].conditions.target = "yes"
api.Refresh(); Flush()
api.GetSettings().enabled = false
api.Refresh(); Flush()
assert(not castBorder.shown and plate.cast:GetStatusBarTexture():GetTexture() == "new-engine-texture")
namespace.ApplyCastStyle({ health = plate.health }, { castEnabled = true }) -- friendly plate without cast

-- Health controls preserve saved behavior, including the old border-size=0 switch.
api.GetSettings().enabled = true
api.Refresh(); Flush()
assert(rows["Override health bar"].get())
assert(rows["Custom health color"].get())
assert(not rows["Override health border"].get())
assert(rows["Health border size"].disabled())
rows["Override health border"].set(true); Flush()
assert(api.GetRules()[1].style.borderSize == 2, "enabling legacy zero-size border needs a visible size")
rows["Health border size"].set(4)
rows["Health border color"].set(0.4, 0.7, 0.2)
rows["Health-bar texture"].set("flat")
Flush()
local healthBorder = namespace.GetRuleBorderFrames(plate)
assert(healthBorder and healthBorder.shown)
rows["Health-bar texture"].set("melli"); Flush()
assert(plate.health.texture == "EUI-Melli", "health selector should resolve EUI textures")
rows["Health-bar texture"].set("sm:Test Texture"); Flush()
assert(plate.health.texture == "SM-Test-Path", "health selector should resolve SharedMedia textures")
rows["Health-bar texture"].set("flat"); Flush()
rows["Override health border"].set(false); Flush()
assert(not healthBorder.shown and rows["Health border color"].disabled())
assert(api.GetRules()[1].style.borderSize == 4, "border toggle must preserve size")
rows["Override health border"].set(true); Flush()
assert(healthBorder.shown and api.GetRules()[1].style.borderSize == 4)

-- Observe genuine engine writes, not plugin paint left behind by cached updates.
plate.health:SetStatusBarColor(0.25, 0.35, 0.45, 0.8)
plate.health:SetStatusBarTexture("latest-health-engine")
Flush()
Near(plate.health.color[1], 0.4, "health override survives engine repaint")
assert(plate.health.texture == "Interface\\Buttons\\WHITE8x8")
plate:UpdateHealthColor(); Flush()
rows["Custom health color"].set(false); Flush()
Near(plate.health.color[1], 0.25, "color toggle restores engine color after cached repaint")
Near(plate.health.color[4], 0.8, "color toggle restores engine alpha")
assert(rows["Health-bar color"].disabled())
rows["Custom health color"].set(true); Flush()
rows["Override health bar"].set(false); Flush()
Near(plate.health.color[1], 0.25, "health master restores color")
assert(plate.health.texture == "latest-health-engine" and not healthBorder.shown)
assert(rows["Custom health color"].disabled() and rows["Health-bar texture"].disabled())
assert(rows["Override health border"].disabled() and rows["Health border size"].disabled())
assert(castBorder.shown, "health master must not disable cast overrides")
Near(plate.scale, 1.3, "health master must not change whole-nameplate scale")
rows["Override health bar"].set(true); Flush()
Near(plate.health.color[1], 0.4, "health master restores custom color")
assert(healthBorder.shown and plate.health.texture == "Interface\\Buttons\\WHITE8x8")
assert(api.GetRules()[1].style.borderSize == 4)
rows["Health-bar texture"].set("eui"); Flush()
assert(plate.health.texture == "latest-health-engine", "Use EUI texture restores latest base")

-- A tapped unit retains EUI's tap-denied health color; unrelated rule styling remains.
plate.health:SetStatusBarColor(0.5, 0.5, 0.5, 1)
Flush()
tappedByOther = true
Fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
Near(plate.health.color[1], 0.5, "tapped color not overwritten")
assert(healthBorder.shown, "tap protection only suppresses plugin health color")
tappedByOther = false
plate.health:SetStatusBarColor(0.25, 0.35, 0.45, 1)
Flush()
Near(plate.health.color[1], 0.4, "health color override resumes after tap denial")

EllesmereUI.IsSearchPrebuild = function() return true end
spec.modules[1].buildPage("Rules", {}, 0)
EllesmereUI.IsSearchPrebuild = function() return false end

print("PASS: settings, rules, copy, search, scaling, health/cast overrides, engine repaints, restoration, recycling")
