local addonName, addon = ...

local DEFAULT_RULES = {
    {
        name = "Current Target",
        enabled = true,
        conditions = { unitType = "any", reaction = "any", classification = "any", target = "yes", castState = "any", spellSchool = "any" },
        style = { healthColorEnabled = true, healthColor = { r = 0.12, g = 0.92, b = 0.67 }, scale = 115, opacity = 100, borderSize = 2, borderColor = { r = 0.12, g = 0.92, b = 0.67 }, texture = "eui" },
    },
    {
        name = "Elite Enemies",
        enabled = true,
        conditions = { unitType = "any", reaction = "enemy", classification = "elite", target = "any", castState = "any", spellSchool = "any" },
        style = { healthColorEnabled = true, healthColor = { r = 0.72, g = 0.36, b = 1.00 }, scale = 105, opacity = 100, borderSize = 2, borderColor = { r = 0.72, g = 0.36, b = 1.00 }, texture = "eui" },
    },
    {
        name = "Enemy Casting",
        enabled = true,
        conditions = { unitType = "any", reaction = "enemy", classification = "any", target = "any", castState = "casting", spellSchool = "any" },
        style = { healthColorEnabled = true, healthColor = { r = 1.00, g = 0.28, b = 0.18 }, scale = 100, opacity = 100, borderSize = 2, borderColor = { r = 1.00, g = 0.28, b = 0.18 }, texture = "eui" },
    },
}

local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = Copy(v) end
    return copy
end

local function MergeMissing(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = Copy(v)
        elseif type(dst[k]) == "table" and type(v) == "table" then
            MergeMissing(dst[k], v)
        end
    end
end

local db
local function GetSettings()
    local saved = _G.EllesmereUINameplateExtrasDB
    if db and db == saved then return db end
    -- SavedVariables may replace the global after this file's main chunk runs.
    -- Both the renderer and options must resolve the same current table.
    if type(saved) ~= "table" then saved = {} end
    if type(saved.rules) ~= "table" or #saved.rules == 0 then saved.rules = Copy(DEFAULT_RULES) end
    for _, rule in ipairs(saved.rules) do
        if type(rule.conditions) ~= "table" then rule.conditions = {} end
        if type(rule.style) ~= "table" then rule.style = {} end
        MergeMissing(rule.conditions, DEFAULT_RULES[1].conditions)
        MergeMissing(rule.style, DEFAULT_RULES[1].style)
        if rule.enabled == nil then rule.enabled = true end
    end
    saved.selectedRule = math.max(1, math.min(tonumber(saved.selectedRule) or 1, #saved.rules))
    db = saved
    _G.EllesmereUINameplateExtrasDB = saved
    addon.db = db
    return db
end

addon.defaultRules = DEFAULT_RULES

local NP = _G.EllesmereNameplates_NS
local unitFrame = CreateFrame("Frame")
local queued = false
local states = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local spellSchools = {}
local combatLogActive = false
local MAX_RULES = 12

local function TryRegisterEvent(frame, event)
    local ok, registered = pcall(frame.RegisterEvent, frame, event)
    return ok and registered ~= false
end

local function TryUnregisterEvent(frame, event)
    pcall(frame.UnregisterEvent, frame, event)
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function SafeBool(value)
    if IsSecret(value) or type(value) ~= "boolean" then return nil end
    return value
end

local function GetState(plate)
    local state = states[plate]
    if not state then
        state = { baseScale = plate:GetScale(), baseAlpha = 1, alphaFactor = 1, scaleFactor = 1 }
        states[plate] = state
    end
    return state
end

local function ColorOf(statusBar)
    if not statusBar or not statusBar.GetStatusBarColor then return nil end
    local r, g, b, a = statusBar:GetStatusBarColor()
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    if type(a) == "nil" then a = 1 end
    return { r = r, g = g, b = b, a = a }
end

local function TextureOf(statusBar)
    if not statusBar or not statusBar.GetStatusBarTexture then return nil end
    local fill = statusBar:GetStatusBarTexture()
    if not fill or not fill.GetTexture then return nil end
    return fill:GetTexture()
end

local function EnsureBorder(plate, state)
    if state.border then return state.border end
    if not plate.health then return nil end
    local border = CreateFrame("Frame", nil, plate)
    border:SetAllPoints(plate.health)
    border:SetFrameStrata(plate.health:GetFrameStrata())
    border:SetFrameLevel(plate.health:GetFrameLevel() + 20)
    local edges = {}
    for i = 1, 4 do
        local tex = border:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(1, 1, 1, 1)
        edges[i] = tex
    end
    state.border = border
    state.borderEdges = edges
    return border
end

local function ApplyBorder(plate, state, style)
    local size = math.max(0, math.min(8, tonumber(style.borderSize) or 0))
    if style.healthEnabled == false or style.borderEnabled == false or size == 0 then
        if state.border then state.border:Hide() end
        return
    end
    local border = EnsureBorder(plate, state)
    if not border then return end
    local c = style.borderColor or { r = 1, g = 1, b = 1 }
    local px = math.max(1, math.floor(size + 0.5))
    local top, bottom, left, right = unpack(state.borderEdges)
    top:ClearAllPoints(); top:SetPoint("TOPLEFT", border, "TOPLEFT"); top:SetPoint("TOPRIGHT", border, "TOPRIGHT"); top:SetHeight(px)
    bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT"); bottom:SetHeight(px)
    left:ClearAllPoints(); left:SetPoint("TOPLEFT", top, "BOTTOMLEFT"); left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT"); left:SetWidth(px)
    right:ClearAllPoints(); right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT"); right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT"); right:SetWidth(px)
    for _, edge in ipairs(state.borderEdges) do edge:SetColorTexture(c.r or 1, c.g or 1, c.b or 1, 1) end
    border:Show()
end

local SCHOOL_MASKS = {
    physical = 1, holy = 2, fire = 4, nature = 8,
    frost = 16, shadow = 32, arcane = 64,
}

local function GetSchoolFromMask(mask)
    if IsSecret(mask) or type(mask) ~= "number" or not bit then return "unknown" end
    local found, count
    count = 0
    for name, value in pairs(SCHOOL_MASKS) do
        if bit.band(mask, value) ~= 0 then found = name; count = count + 1 end
    end
    if count == 1 then return found end
    if count > 1 then return "mixed" end
    return "unknown"
end

local function GetSchool(spellID)
    if IsSecret(spellID) or type(spellID) ~= "number" then return "unknown" end
    return spellSchools[spellID] or "unknown"
end

local function ReadCast(unit)
    local name, _, _, _, _, _, _, notInterruptible, spellID = UnitCastingInfo(unit)
    local castState = "casting"
    if type(name) == "nil" then
        name, _, _, _, _, _, notInterruptible, spellID = UnitChannelInfo(unit)
        castState = "channel"
    end
    if type(name) == "nil" then return "none", "any", "unknown" end
    if UnitEmpoweredChannelInfo then
        local ok, empoweredName = pcall(UnitEmpoweredChannelInfo, unit)
        if ok and type(empoweredName) ~= "nil" and not IsSecret(empoweredName) then castState = "empowered" end
    end
    local interruptible = "unknown"
    if not IsSecret(notInterruptible) and type(notInterruptible) == "boolean" then
        interruptible = notInterruptible and "uninterruptible" or "interruptible"
    end
    return castState, interruptible, GetSchool(spellID)
end

local function GetTraits(unit)
    local player = SafeBool(UnitIsPlayer(unit))
    local unitType
    if player == true then
        unitType = "player"
    elseif player == false then
        unitType = (UnitPlayerControlled and SafeBool(UnitPlayerControlled(unit))) and "pet" or "npc"
    else
        unitType = "unknown"
    end
    local enemy = SafeBool(UnitCanAttack("player", unit))
    local reaction = enemy == true and "enemy" or "unknown"
    if enemy == false then reaction = "friendly" end
    if enemy == false and UnitReaction then
        local value = UnitReaction("player", unit)
        if not IsSecret(value) and type(value) == "number" and value == 4 then reaction = "neutral" end
    end
    local classification = UnitClassification(unit)
    if IsSecret(classification) then classification = "unknown"
    elseif type(classification) == "nil" then classification = "normal"
    elseif classification == "worldboss" then classification = "boss" end
    local castState, interruptible, spellSchool = ReadCast(unit)
    local isTarget = SafeBool(UnitIsUnit(unit, "target"))
    return {
        unitType = unitType,
        isCreature = player == false,
        reaction = reaction,
        classification = classification,
        target = isTarget,
        castState = castState,
        interruptible = interruptible,
        spellSchool = spellSchool,
    }
end

local function Matches(rule, unit, traits)
    if not rule.enabled then return false end
    local c = rule.conditions or {}
    if c.unitType and c.unitType ~= "any" then
        if c.unitType == "creature" then
            if not traits.isCreature then return false end
        elseif c.unitType ~= traits.unitType then return false end
    end
    if c.reaction and c.reaction ~= "any" and c.reaction ~= traits.reaction then return false end
    if c.classification and c.classification ~= "any" and c.classification ~= traits.classification then return false end
    if c.target == "yes" and traits.target ~= true then return false end
    if c.target == "no" and traits.target ~= false then return false end
    if c.castState == "none" and traits.castState ~= "none" then return false end
    if c.castState == "casting" and traits.castState ~= "casting" then return false end
    if c.castState == "channel" and traits.castState ~= "channel" then return false end
    if c.castState == "empowered" and traits.castState ~= "empowered" then return false end
    if c.castState == "interruptible" and traits.interruptible ~= "interruptible" then return false end
    if c.castState == "uninterruptible" and traits.interruptible ~= "uninterruptible" then return false end
    if c.spellSchool and c.spellSchool ~= "any" then
        if traits.castState == "none" or c.spellSchool ~= traits.spellSchool then return false end
    end
    for key, expected in pairs(c) do
        local predicate = addon.customConditions and addon.customConditions[key]
        if predicate then
            local ok, matches = pcall(predicate, unit, traits, expected, rule)
            if not ok or not matches then return false end
        elseif key ~= "unitType" and key ~= "reaction" and key ~= "classification"
           and key ~= "target" and key ~= "castState" and key ~= "spellSchool" then
            return false
        end
    end
    return true
end

local function FindRule(unit)
    GetSettings()
    if db.enabled == false then return nil end
    local traits = GetTraits(unit)
    for index, rule in ipairs(db.rules) do
        if Matches(rule, unit, traits) then return rule, index, traits end
    end
end

local function UpdateCombatLogRegistration()
    GetSettings()
    local shouldListen = false
    if db.enabled ~= false then
        for _, rule in ipairs(db.rules) do
            local conditions = rule.conditions
            if rule.enabled ~= false and conditions and conditions.spellSchool and conditions.spellSchool ~= "any" then
                shouldListen = true
                break
            end
        end
    end
    if shouldListen and not combatLogActive then
        combatLogActive = TryRegisterEvent(unitFrame, "COMBAT_LOG_EVENT_UNFILTERED")
    elseif not shouldListen and combatLogActive then
        TryUnregisterEvent(unitFrame, "COMBAT_LOG_EVENT_UNFILTERED")
        combatLogActive = false
    end
end

local function SetScaleFactor(plate, state, factor)
    state.scaleFactor = factor
    state.writingScale = true
    plate:SetScale(state.baseScale * factor)
    state.writingScale = nil
end

local function ResetStyle(plate, state)
    if addon.ApplyCastStyle then addon.ApplyCastStyle(plate, nil) end
    if state.border then state.border:Hide() end
    state.writingHealth = true
    if state.hadColor and state.baseColor and plate.health then
        local c = state.baseColor
        plate.health:SetStatusBarColor(c.r, c.g, c.b, c.a)
    end
    if state.hadTexture and state.baseTexture and plate.health then
        plate.health:SetStatusBarTexture(state.baseTexture)
        if plate.absorb and NP and NP.NP_LayoutAbsorbBars then
            NP.NP_LayoutAbsorbBars(plate, plate.health, plate._absEdge)
        end
    end
    state.writingHealth = nil
    if state.scaleFactor and state.scaleFactor ~= 1 and plate.SetScale then
        SetScaleFactor(plate, state, 1)
    end
    if state.alphaFactor and state.alphaFactor ~= 1 and plate.SetAlpha then
        plate:SetAlpha(state.baseAlpha or 1)
    end
    state.hadColor, state.hadTexture = nil, nil
    state.scaleFactor, state.alphaFactor = 1, 1
    state.rule = nil
end

local function ApplyStyle(plate)
    local unit = plate and plate.unit
    if not unit or not UnitExists(unit) or not plate.health then return end
    local state = GetState(plate)
    if state.unit ~= unit then
        if state.border then state.border:Hide() end
        local oldAlphaFactor = state.alphaFactor or 1
        state.unit = unit
        state.hadColor, state.hadTexture = nil, nil
        if NP and type(plate._ntCurAlpha) == "number" then
            state.baseAlpha = plate._ntCurAlpha
        elseif oldAlphaFactor > 0 then
            state.baseAlpha = plate:GetAlpha() / oldAlphaFactor
        end
    end
    local rule = FindRule(unit)
    rule = rule and rule or nil
    if not rule then ResetStyle(plate, state); return end
    local style = rule.style or {}
    state.rule = rule
    state.writingHealth = true
    if style.healthEnabled ~= false and style.healthColorEnabled and style.healthColor then
        local c = style.healthColor
        plate.health:SetStatusBarColor(c.r or 1, c.g or 1, c.b or 1, 1)
        state.hadColor = true
    elseif state.hadColor and state.baseColor then
        local c = state.baseColor
        plate.health:SetStatusBarColor(c.r, c.g, c.b, c.a)
        state.hadColor = nil
    end
    local textureChanged = false
    local texture = style.healthEnabled ~= false and style.texture or "eui"
    if texture == "flat" then
        plate.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8"); state.hadTexture = true; textureChanged = true
    elseif texture == "blizzard" then
        plate.health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar"); state.hadTexture = true; textureChanged = true
    elseif state.hadTexture and state.baseTexture then
        plate.health:SetStatusBarTexture(state.baseTexture)
        state.hadTexture = nil; textureChanged = true
    end
    if textureChanged and plate.absorb and NP and NP.NP_LayoutAbsorbBars then
        NP.NP_LayoutAbsorbBars(plate, plate.health, plate._absEdge)
    end
    state.writingHealth = nil
    ApplyBorder(plate, state, style)
    local scale = math.max(50, math.min(200, tonumber(style.scale) or 100)) / 100
    local opacity = math.max(0, math.min(100, tonumber(style.opacity) or 100)) / 100
    SetScaleFactor(plate, state, scale)
    state.alphaFactor = opacity
    if plate.SetAlpha then plate:SetAlpha((state.baseAlpha or 1) * opacity) end
    if addon.ApplyCastStyle then addon.ApplyCastStyle(plate, style) end
end

local InstallHooks

local function RefreshAll()
    GetSettings()
    if not NP then NP = _G.EllesmereNameplates_NS end
    if not NP then return end
    if InstallHooks then InstallHooks() end
    UpdateCombatLogRegistration()
    local report = geterrorhandler and geterrorhandler()
    local function ApplySafely(plate)
        local ok, err = pcall(ApplyStyle, plate)
        if not ok and report then report(err) end
    end
    for _, plate in pairs(NP.plates or {}) do ApplySafely(plate) end
    for _, plate in pairs(NP.friendlyPlates or {}) do ApplySafely(plate) end
end

local function QueueRefresh()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        if InstallHooks then InstallHooks() end
        RefreshAll()
    end)
end

local function InstallPlateHooks(plate)
    if not plate or hooked[plate] then return end
    hooked[plate] = true
    local state = GetState(plate)
    state.baseColor = ColorOf(plate.health)
    state.baseTexture = TextureOf(plate.health)
    if plate.health then
        -- Capture only actual engine writes. A cached UpdateHealthColor pass may
        -- leave our custom paint in place, which must never become the base.
        hooksecurefunc(plate.health, "SetStatusBarColor", function(_, r, g, b, a)
            if state.writingHealth then return end
            if type(a) == "nil" then a = 1 end
            state.baseColor = { r = r, g = g, b = b, a = a }
            QueueRefresh()
        end)
        hooksecurefunc(plate.health, "SetStatusBarTexture", function(health)
            if state.writingHealth then return end
            state.baseTexture = TextureOf(health)
            QueueRefresh()
        end)
    end
    -- Keep EUI's animation values unmodified; multiply only the rendered scale.
    hooksecurefunc(plate, "SetScale", function(self, scale)
        if state.writingScale then return end
        state.baseScale = scale
        if state.scaleFactor ~= 1 then SetScaleFactor(self, state, state.scaleFactor) end
    end)
    if type(plate.ClearUnit) == "function" then
        hooksecurefunc(plate, "ClearUnit", function(self)
            ResetStyle(self, state)
            state.unit = nil
        end)
    end
    local methods = { "SetUnit", "ApplyAppearance", "ApplyScale", "UpdateHealthColor", "UpdateCast" }
    for _, method in ipairs(methods) do
        if type(plate[method]) == "function" then
            hooksecurefunc(plate, method, QueueRefresh)
        end
    end
end

InstallHooks = function()
    NP = _G.EllesmereNameplates_NS or NP
    if not NP then return end
    for _, plate in pairs(NP.plates or {}) do InstallPlateHooks(plate) end
    for _, plate in pairs(NP.friendlyPlates or {}) do InstallPlateHooks(plate) end
    if NP.NT_Apply and not addon.opacityHooked then
        hooksecurefunc(NP, "NT_Apply", function(plate)
            if not plate then return end
            local state = GetState(plate)
            local factor = state.alphaFactor or 1
            local alpha = plate:GetAlpha()
            if factor > 0 then state.baseAlpha = alpha / factor end
            QueueRefresh()
        end)
        addon.opacityHooked = true
    end
end

local events = {
    "ADDON_LOADED",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD",
    "UNIT_FLAGS", "UNIT_FACTION", "UNIT_NAME_UPDATE",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}
for _, event in ipairs(events) do TryRegisterEvent(unitFrame, event) end
unitFrame:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" then
        if loadedAddon ~= addonName then return end
        GetSettings()
        TryUnregisterEvent(unitFrame, "ADDON_LOADED")
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not CombatLogGetCurrentEventInfo then return end
        local _, subevent, _, _, _, _, _, _, _, _, _, spellID, _, school = CombatLogGetCurrentEventInfo()
        if subevent == "SPELL_CAST_START" and not IsSecret(spellID) and type(spellID) == "number" then
            local schoolName = GetSchoolFromMask(school)
            if schoolName ~= "unknown" then
                spellSchools[spellID] = schoolName
                QueueRefresh()
            end
        end
        return
    end
    InstallHooks()
    QueueRefresh()
end)

addon.RefreshAll = RefreshAll
addon.FindRule = FindRule
addon.RegisterCondition = function(key, predicate)
    if type(key) ~= "string" or key == "" or type(predicate) ~= "function" then return false end
    addon.customConditions = addon.customConditions or {}
    addon.customConditions[key] = predicate
    return true
end
addon.RegisterSpellSchool = function(spellID, school)
    if IsSecret(spellID) or type(spellID) ~= "number" or type(school) ~= "string" then return false end
    local valid = SCHOOL_MASKS[school] or school == "mixed"
    if not valid then return false end
    spellSchools[spellID] = school
    QueueRefresh()
    return true
end

local publicAPI = {
    Refresh = function()
        if InstallHooks then InstallHooks() end
        QueueRefresh()
    end,
    RegisterCondition = addon.RegisterCondition,
    RegisterSpellSchool = addon.RegisterSpellSchool,
    GetSettings = GetSettings,
    GetRules = function() return GetSettings().rules end,
    MaxRules = MAX_RULES,
    DefaultRules = DEFAULT_RULES,
}
-- Keep the previous global name as an alias for existing rule extensions.
_G.EllesmereUINameplateExtras = publicAPI

SLASH_NAMEPLATEEXTRAS1 = "/npextras"
SlashCmdList.NAMEPLATEEXTRAS = function()
    GetSettings()
    local function Text(value)
        if IsSecret(value) then return "<restricted>" end
        return tostring(value)
    end
    local function Report(message)
        print("Nameplate Extras: " .. message)
    end
    Report("diagnostics v3; addon=EllesmereUINameplateExtras; feature=Nameplate Style; enabled=" .. Text(db.enabled ~= false)
        .. "; settings shared with options=" .. Text(db == _G.EllesmereUINameplateExtrasDB))
    NP = _G.EllesmereNameplates_NS
    if not NP then Report("EUI nameplate namespace missing"); return end
    local targetPlate
    for _, plates in ipairs({ NP.plates or {}, NP.friendlyPlates or {} }) do
        for _, plate in pairs(plates) do
            if plate.unit and SafeBool(UnitIsUnit(plate.unit, "target")) then
                targetPlate = plate
                break
            end
        end
        if targetPlate then break end
    end
    if not targetPlate then Report("No EUI full nameplate found for your target"); return end
    Report("unit=" .. Text(targetPlate.unit) .. "; health bar=" .. Text(targetPlate.health ~= nil)
        .. "; hooks installed=" .. Text(hooked[targetPlate] == true))
    local ok, traits = pcall(GetTraits, targetPlate.unit)
    if not ok then Report("Detection ERROR: " .. Text(traits)); return end
    Report("type=" .. Text(traits.unitType) .. "; reaction=" .. Text(traits.reaction)
        .. "; rank=" .. Text(traits.classification) .. "; target=" .. Text(traits.target)
        .. "; cast=" .. Text(traits.castState))
    for index, rule in ipairs(db.rules) do
        local matched, result = pcall(Matches, rule, targetPlate.unit, traits)
        Report("rule " .. index .. " (" .. Text(rule.name) .. "): enabled=" .. Text(rule.enabled)
            .. "; match=" .. (matched and Text(result) or ("ERROR: " .. Text(result))))
    end
    local matched, rule, index = pcall(FindRule, targetPlate.unit)
    if not matched then Report("Matching ERROR: " .. Text(rule)); return end
    if not rule then Report("No winning rule (disabled globally or no match)"); return end
    local style = rule.style or {}
    Report("winner=" .. index .. "; color override=" .. Text(style.healthColorEnabled)
        .. "; scale=" .. Text(style.scale) .. "; opacity=" .. Text(style.opacity))
    local applied, err = pcall(RefreshAll)
    if not applied then Report("Refresh ERROR: " .. Text(err)); return end
    -- Call directly as well: RefreshAll reports per-plate failures via the game's error handler.
    applied, err = pcall(ApplyStyle, targetPlate)
    if not applied then Report("Apply ERROR: " .. Text(err)); return end
    local color = ColorOf(targetPlate.health) or {}
    Report("Applied; health RGB=" .. Text(color.r) .. "," .. Text(color.g) .. "," .. Text(color.b)
        .. "; scale=" .. Text(targetPlate:GetScale()) .. "; alpha=" .. Text(targetPlate:GetAlpha()))
end

InstallHooks()
