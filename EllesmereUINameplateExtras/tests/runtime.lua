-- Run from the repository root with Lua or fengari.
unpack = unpack or table.unpack
local frames, timers = {}, {}
local function Noop() end
local tappedByOther = false
local questObjective = false
local playerName = "TestCharacter"
function CreateFrame(kind, _, parentFrame)
    local frame = { events = {}, scripts = {}, scale = 1, alpha = 1, kind = kind, parent = parentFrame,
        vertexColor = { 1, 1, 1, 1 } }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:GetScale() return self.scale end
    function frame:SetScale(value) self.scale = value end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:GetFrameStrata() return "MEDIUM" end
    function frame:GetFrameLevel() return 10 end
    function frame:GetWidth() return self.width or 800 end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    for _, method in ipairs({ "SetAllPoints", "SetFrameStrata", "SetFrameLevel", "Hide", "Show",
        "ClearAllPoints", "SetPoint", "SetHeight", "SetWidth", "SetColorTexture" }) do
        frame[method] = Noop
    end
    function frame:CreateTexture() return CreateFrame("Texture", nil, self) end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:GetNumPoints() return self.point and 1 or 0 end
    function frame:GetPoint() return unpack(self.point) end
    function frame:SetTexture(path) self.texture = path end
    function frame:GetTexture() return self.texture end
    function frame:GetVertexColor() return unpack(self.vertexColor) end
    function frame:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a or 1 } end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
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
function UnitFullName() return playerName, "TestRealm" end
function UnitName() return playerName end
function GetRealmName() return "TestRealm" end
function UnitPlayerControlled() return false end
function UnitCanAttack() return true end
function UnitIsUnit(unit, other) return unit == "nameplate1" and other == "target" end
function UnitClassification() return "normal" end
function UnitIsTapDenied() return tappedByOther end
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
assert(loadfile("EllesmereUINameplateExtras/EllesmereUINameplateExtras.lua"))("EllesmereUINameplateExtras", namespace)
assert(loadfile("EllesmereUINameplateExtras/EllesmereUINameplateExtras_CastStyles.lua"))("EllesmereUINameplateExtras", namespace)
assert(EllesmereUINameplateExtrasDB == nil, "new SavedVariables initialized before ADDON_LOADED")
local api = EllesmereUINameplateExtras
assert(api, "public API missing")

-- Model the fresh Extras SavedVariables loading after addon chunks execute.
EllesmereUINameplateExtrasDB = Settings("Loaded rule", 150, 0.2)
Fire("ADDON_LOADED", "EllesmereUINameplateExtras")
assert(api.GetSettings() == EllesmereUINameplateExtrasDB.profiles.Default)
assert(api.GetProfileInfo().character == "TestCharacter - TestRealm")
assert(api.GetProfileInfo().active == "Default")
assert(EllesmereUINameplateExtrasDB.characterProfiles["TestCharacter - TestRealm"] == "Default")
assert(namespace.FindRule("nameplate1").name == "Loaded rule")
Near(plate.scale, 1.5, "saved scale")
Near(plate.health.color[1], 0.2, "saved color")

-- Replacing the table must not leave the renderer reading its previous rules.
EllesmereUINameplateExtrasDB = Settings("Replacement rule", 115, 0.6)
api.Refresh(); Flush()
assert(api.GetRules() == EllesmereUINameplateExtrasDB.profiles.Default.rules)
assert(namespace.db.profile == EllesmereUINameplateExtrasDB.profiles.Default)
Near(plate.scale, 1.15, "replacement scale")
Near(plate.health.color[1], 0.6, "replacement color")

-- The shared Default is the starting point, and character assignments are independent.
api.GetSettings().rules[1].name = "Shared Default"
local created, profileError = api.CreateProfile("Tank")
assert(created, tostring(profileError) .. "; character=" .. tostring(api.GetProfileInfo().character))
assert(api.GetProfileInfo().active == "Tank")
assert(api.GetSettings().rules[1].name == "Current Target", "new profile should start with built-in rules")
Near(api.GetSettings().rules[1].style.healthColor.r, 0.12, "new profile built-in health color")
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
assert(api.GetSettings().rules[1].name == "Current Target", "new profile should use fresh built-in rules")
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
local W = {}
function W:SectionHeader(_, text)
    if text:find("^RULE ORDER") then
        for index = #sectionHeaders, 1, -1 do sectionHeaders[index] = nil end
    end
    sectionHeaders[#sectionHeaders + 1] = text
    return {}, 40
end
function W:Button(_, text, y, click)
    local row, button = CreateFrame(), CreateFrame()
    function row:GetChildren() return button end
    rows[text] = { click = click, row = row, button = button, y = y }
    if EllesmereUI.IsSearchPrebuild() then return {}, 50 end
    return row, 50
end
function W:WideButton(_, text, _, click)
    rows[text] = { click = click }
    return {}, 62
end
function W:WideDualButton(_, first, second, _, onFirst, onSecond, _)
    rows[first] = { click = onFirst }
    rows[second] = { click = onSecond }
    return {}, 60
end
function W:Toggle(_, text, _, get, set) rows[text] = { get = get, set = set }; return {}, 50 end
function W:Slider(_, text, _, _, _, _, get, set) rows[text] = { get = get, set = set }; return {}, 50 end
function W:Dropdown(_, text, _, values, get, set) rows[text] = { get = get, set = set, values = values }; return {}, 50 end
function W:DualRow(_, _, config, right)
    for _, cfg in ipairs({ config, right }) do
        if cfg.type == "colorpicker" then assert(type(cfg.getValue()) == "number") end
        rows[cfg.text] = { get = cfg.getValue, set = cfg.setValue, disabled = cfg.disabled, values = cfg.values }
    end
    return {}, 50
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
    Widgets = W,
    ResolveTexturePath = function(textureTable, key, fallback) return textureTable[key] or fallback end,
    CONTENT_PAD = 20,
    PanelPP = {
        Size = function(frame, width, height) frame:SetSize(width, height) end,
        Point = function(frame, ...) frame:SetPoint(...) end,
    },
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
    RefreshPage = function() spec.modules[1].buildPage("Rules", parent, 0) end,
}
assert(loadfile("EllesmereUINameplateExtras/EllesmereUINameplateExtras_RuleIO.lua"))()
assert(loadfile("EllesmereUINameplateExtras/EllesmereUINameplateExtras_Options.lua"))()
Fire("PLAYER_LOGIN")
assert(registeredID == "EllesmereUINameplateExtras")
assert(spec.label == "Nameplate Extras")
assert(spec.modules[1].key == "NameplateStyle" and spec.modules[1].title == "Nameplate Style")
assert(spec.modules[1].pages[2] == "Profiles" and spec.modules[1].pages[3] == "Sharing")
spec.modules[1].buildPage("Rules", parent, 0)

spec.modules[1].buildPage("Profiles", parent, 0)
assert(rows["Profile for this character"].values.Default,
    "Profiles page doesn't list the shared Default profile")
rows["Create Profile"].click()
assert(legacyImportPopup and legacyImportPopup.title == "Create Nameplate Profile")
legacyImportPopup.onConfirm("UI Test Profile")
assert(api.GetProfileInfo().active == "UI Test Profile", "Profiles tab didn't create/select its profile")
assert(api.GetSettings().rules[1].name == "Current Target", "Profiles tab didn't create a fresh profile")
rows["Profile for this character"].set("Default")
assert(api.GetProfileInfo().active == "Default", "Profiles tab didn't switch back to Default")
spec.modules[1].buildPage("Rules", parent, 0)
local ruleCode = assert(api.ExportRuleSet())
assert(ruleCode:sub(1, 17) == "!EUI_NPEX_RULES1!", "standalone export prefix missing")
spec.modules[1].buildPage("Sharing", parent, 0)
rows["Export Rule Set"].click()
assert(exportedPopup and exportedPopup.code:sub(1, 17) == "!EUI_NPEX_RULES1!",
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
local function HasHeader(prefix, suffix)
    for _, text in ipairs(sectionHeaders) do
        if text:find(prefix, 1, true) == 1 and text:sub(-#suffix) == suffix then return true end
    end
    return false
end
assert(HasHeader("RULE ORDER - POSITION 1 OF 1", "(Shared Default)"), table.concat(sectionHeaders, " | "))
assert(HasHeader("MATCH CONDITIONS", "(Shared Default)"))
assert(HasHeader("APPEARANCE - NAMEPLATE", "(Shared Default)"))
assert(HasHeader("APPEARANCE - HEALTH BAR", "(Shared Default)"))
assert(HasHeader("APPEARANCE - CAST BAR", "(Shared Default)"))
local actions = { "Add Rule", "Copy Rule", "Delete Rule", "Move Rule Up", "Move Rule Down" }
for index, text in ipairs(actions) do
    local action = rows[text]
    assert(action.y == rows[actions[1]].y, "action buttons must share a row")
    Near(action.row.width, 152, "action column width")
    Near(action.row.point[4], 20 + (index - 1) * 152, "left-to-right button order")
    Near(action.button.width, 140, "button fits its column")
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
rows["Add Rule"].click(); Flush()
assert(HasHeader("RULE ORDER - POSITION 1 OF 2", "(Custom Rule 2)"))
assert(namespace.FindRule("nameplate1") == api.GetRules()[1], "new rule not selected by renderer")
Near(plate.scale, 1.2, "new rule scale")
Near(plate.health.color[1], 1, "new rule color")

local renamed = api.GetRules()[1]
local style, conditions = renamed.style, renamed.conditions
rows["Rule name"].set("  My Target Rule  ")
assert(renamed.name == "My Target Rule", "rename must trim and save")
assert(rows["Edit rule"].values["1"] == "My Target Rule", "dropdown label not updated")
assert(HasHeader("APPEARANCE - NAMEPLATE", "(My Target Rule)"), "heading did not update after rename")
assert(api.GetSettings().selectedRule == 1 and api.GetRules()[1] == renamed, "rename changed order or selection")
assert(renamed.style == style and renamed.conditions == conditions, "rename changed rule behavior")
rows["Rule name"].set(" \t\n ")
assert(renamed.name == "My Target Rule", "blank name replaced existing name")
local oldNameField = rows["Rule name"]
rows["Copy Rule"].click(); Flush()
local copy = api.GetRules()[2]
assert(copy ~= renamed and copy.name == "My Target Rule Copy", "copy did not create a named rule")
assert(copy.conditions ~= renamed.conditions and copy.style ~= renamed.style, "copy shares mutable rule tables")
assert(copy.conditions.target == renamed.conditions.target and copy.style.scale == renamed.style.scale,
    "copy did not preserve rule settings")
assert(api.GetSettings().selectedRule == 2 and rows["Rule name"].get() == copy.name,
    "copy was not selected for editing")
rows["Edit rule"].set("3")
assert(HasHeader("RULE ORDER - POSITION 3 OF 3", "(Shared Default)"))
oldNameField.set("Target Rule")
assert(renamed.name == "Target Rule" and api.GetRules()[3].name == "Shared Default",
    "focus-loss commit renamed the wrong rule")
rows["Edit rule"].set("1")
assert(rows["Rule name"].get() == "Target Rule", "rename lost after page rebuild")
rows["Move Rule Down"].click(); Flush()
assert(HasHeader("RULE ORDER - POSITION 2 OF 3", "(Target Rule)") and api.GetRules()[2] == renamed)
rows["Move Rule Up"].click(); Flush()
assert(HasHeader("RULE ORDER - POSITION 1 OF 3", "(Target Rule)") and api.GetRules()[1] == renamed)

EllesmereUI.IsSearchPrebuild = function() return true end
spec.modules[1].buildPage("Rules", {}, 0)
EllesmereUI.IsSearchPrebuild = function() return false end
spec.modules[1].buildPage("Rules", parent, 0)

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
EllesmereUINameplateExtrasDB = Settings("Late replacement", 100, 0.1)
rows["Nameplate size (%)"].set(130)
rows["Health-bar color"].set(0.4, 0.5, 0.6)
Flush()
Near(plate.scale, 1.3, "cached options use current settings")
Near(plate.health.color[1], 0.4, "cached color picker uses current settings")
assert(namespace.db.profile == EllesmereUINameplateExtrasDB.profiles.Default)

rows["Add Rule"].click(); Flush()
local countBeforeDelete = #api.GetRules()
rows["Delete Rule"].click(); Flush()
assert(#api.GetRules() == countBeforeDelete, "rule was deleted before confirmation")
assert(deleteConfirm and deleteConfirm.title == "Delete Nameplate Rule?"
    and deleteConfirm.cancelText == "Keep Rule", "rule delete confirmation wasn't shown")
deleteConfirm.onConfirm()
Flush()
assert(HasHeader("RULE ORDER - POSITION 1 OF 1", "(Late replacement)"), "delete must update position and total")

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
rows["Additional cast border"].set(true)
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
assert(not rows["Additional health border"].get())
assert(rows["Health border size"].disabled())
rows["Additional health border"].set(true); Flush()
assert(api.GetRules()[1].style.borderSize == 2, "enabling legacy zero-size border needs a visible size")
rows["Health border size"].set(4)
rows["Health border color"].set(0.4, 0.7, 0.2)
rows["Health-bar texture"].set("flat")
Flush()
local healthBorder
for _, frame in ipairs(frames) do
    if frame.parent == plate and frame.kind == "Frame" then healthBorder = frame end
end
assert(healthBorder and healthBorder.shown)
rows["Health-bar texture"].set("melli"); Flush()
assert(plate.health.texture == "EUI-Melli", "health selector should resolve EUI textures")
rows["Health-bar texture"].set("sm:Test Texture"); Flush()
assert(plate.health.texture == "SM-Test-Path", "health selector should resolve SharedMedia textures")
rows["Health-bar texture"].set("flat"); Flush()
rows["Additional health border"].set(false); Flush()
assert(not healthBorder.shown and rows["Health border color"].disabled())
assert(api.GetRules()[1].style.borderSize == 4, "border toggle must preserve size")
rows["Additional health border"].set(true); Flush()
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
assert(rows["Additional health border"].disabled() and rows["Health border size"].disabled())
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
