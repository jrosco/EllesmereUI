local addonName, addon = ...

local MULTI_CONDITION_VALUES = {
    unitType = { player = true, npc = true, pet = true, creature = true },
    reaction = { enemy = true, friendly = true, neutral = true },
    classification = { normal = true, elite = true, rare = true, rareelite = true, boss = true, minus = true },
    target = { yes = true, no = true },
    castState = { none = true, casting = true, channel = true, empowered = true, interruptible = true, uninterruptible = true },
    spellSchool = { physical = true, holy = true, fire = true, nature = true, frost = true, shadow = true, arcane = true, mixed = true },
}
local SCALAR_CONDITION_VALUES = {
    questObjective = { any = true, yes = true, no = true },
}
local DEFAULT_CONDITIONS = { questObjective = "any" }

local DEFAULT_RULES = {
    {
        name = "Current Target",
        enabled = true,
        conditions = { unitType = {}, reaction = {}, classification = {}, target = { yes = true }, questObjective = "any", castState = {}, spellSchool = {} },
        style = { healthColorEnabled = true, healthColor = { r = 0.12, g = 0.92, b = 0.67 }, scale = 115, opacity = 100, borderSize = 2, borderColor = { r = 0.12, g = 0.92, b = 0.67 }, texture = "eui" },
    },
    {
        name = "Elite Enemies",
        enabled = true,
        conditions = { unitType = {}, reaction = { enemy = true }, classification = { elite = true }, target = {}, questObjective = "any", castState = {}, spellSchool = {} },
        style = { healthColorEnabled = true, healthColor = { r = 0.72, g = 0.36, b = 1.00 }, scale = 105, opacity = 100, borderSize = 2, borderColor = { r = 0.72, g = 0.36, b = 1.00 }, texture = "eui" },
    },
    {
        name = "Enemy Casting",
        enabled = true,
        conditions = { unitType = {}, reaction = { enemy = true }, classification = {}, target = {}, questObjective = "any", castState = { casting = true }, spellSchool = {} },
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

local db                 -- active named profile's settings
local profileStore       -- SavedVariables root: profiles + character->profile assignments
local activeCharacterKey
local activeProfileName = "Default"
local QueueRefresh
local DEFAULT_PROFILE = { enabled = true, selectedRule = 1, rules = DEFAULT_RULES }
local MAX_RULES = 12
local MAX_PROFILES = 24

local function CurrentCharacterKey()
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    if type(name) ~= "string" or name == "" then name = UnitName and UnitName("player") end
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) ~= "string" or realm == "" then realm = GetRealmName and GetRealmName() or "" end
    return realm ~= "" and (name .. " - " .. realm) or name
end

local function NormalizeMultiCondition(value, allowed)
    local selected = {}
    if type(value) == "string" then
        if value ~= "any" and allowed[value] then selected[value] = true end
    elseif type(value) == "table" then
        for key, enabled in pairs(value) do
            if enabled == true and allowed[key] then selected[key] = true end
        end
    end
    return selected
end

local function NormalizeRuleConditions(rule)
    if type(rule.conditions) ~= "table" then rule.conditions = {} end
    -- Selection sets are atomic: empty/missing means Any, never starter-rule values.
    for key, allowed in pairs(MULTI_CONDITION_VALUES) do
        rule.conditions[key] = NormalizeMultiCondition(rule.conditions[key], allowed)
    end
    for key, default in pairs(DEFAULT_CONDITIONS) do
        if rule.conditions[key] == nil then rule.conditions[key] = default end
    end
    return rule
end

local function ValidateRuleConditions(conditions)
    if type(conditions) ~= "table" then return false, "conditions" end
    for key, allowed in pairs(SCALAR_CONDITION_VALUES) do
        local value = conditions[key]
        if value ~= nil and (type(value) ~= "string" or not allowed[value]) then return false, key end
    end
    for key, allowed in pairs(MULTI_CONDITION_VALUES) do
        local value = conditions[key]
        if value ~= nil then
            local valid = type(value) == "string" and (value == "any" or allowed[value])
            if type(value) == "table" then
                valid = true
                for choice, selected in pairs(value) do
                    if not allowed[choice] or selected ~= true then valid = false; break end
                end
            end
            if not valid then return false, key end
        end
    end
    -- Extension-owned keys are preserved and validated by RuleIO's safe-tree check.
    return true
end

local function NormalizeProfile(profile)
    if type(profile) ~= "table" then profile = {} end
    if profile.enabled == nil then profile.enabled = DEFAULT_PROFILE.enabled end
    if profile.selectedRule == nil then profile.selectedRule = DEFAULT_PROFILE.selectedRule end
    if type(profile.rules) ~= "table" or #profile.rules == 0 then profile.rules = Copy(DEFAULT_RULES) end
    for index, rule in ipairs(profile.rules) do
        if type(rule) ~= "table" then
            rule = {}
            profile.rules[index] = rule
        end
        if type(rule.style) ~= "table" then rule.style = {} end
        NormalizeRuleConditions(rule)
        MergeMissing(rule.style, DEFAULT_RULES[1].style)
        if rule.enabled == nil then rule.enabled = true end
    end
    profile.selectedRule = math.max(1, math.min(tonumber(profile.selectedRule) or 1, #profile.rules))
    return profile
end

local function GetSettings()
    local saved = _G.EllesmereUINameplateExtrasDB
    if type(saved) ~= "table" then saved = {} end
    local characterKey = CurrentCharacterKey()
    if profileStore == saved and db and characterKey == activeCharacterKey
       and saved.profiles and saved.profiles[activeProfileName] == db
       and (not characterKey or saved.characterProfiles[characterKey] == activeProfileName) then
        return db
    end
    if type(saved.profiles) ~= "table" then
        -- First upgrade from the pre-profile layout: keep existing rules as
        -- the shared Default profile rather than resetting the user's setup.
        local oldDefault
        if type(saved.rules) == "table" then
            oldDefault = {
                rules = saved.rules,
                enabled = saved.enabled,
                selectedRule = saved.selectedRule,
            }
        end
        saved.profiles = { Default = oldDefault or Copy(DEFAULT_PROFILE) }
    end
    if type(saved.characterProfiles) ~= "table" then saved.characterProfiles = {} end
    if type(saved.profiles.Default) ~= "table" then saved.profiles.Default = Copy(DEFAULT_PROFILE) end
    for name, profile in pairs(saved.profiles) do
        if type(name) ~= "string" or name == "" then
            saved.profiles[name] = nil
        else
            saved.profiles[name] = NormalizeProfile(profile)
        end
    end
    saved.rules, saved.enabled, saved.selectedRule = nil, nil, nil
    local selectedProfile = characterKey and saved.characterProfiles[characterKey] or "Default"
    if type(selectedProfile) ~= "string" or type(saved.profiles[selectedProfile]) ~= "table" then
        selectedProfile = "Default"
    end
    if characterKey then saved.characterProfiles[characterKey] = selectedProfile end
    profileStore = saved
    activeCharacterKey = characterKey
    activeProfileName = selectedProfile
    db = saved.profiles[selectedProfile]
    addon.db = { sv = saved, folder = addonName, profile = db, profileName = selectedProfile }
    _G.EllesmereUINameplateExtrasDB = saved
    return db
end

local function ProfileInfo()
    GetSettings()
    local names, other = { "Default" }, {}
    for name in pairs(profileStore.profiles) do
        if name ~= "Default" then other[#other + 1] = name end
    end
    table.sort(other, function(a, b) return a:lower() < b:lower() end)
    for _, name in ipairs(other) do names[#names + 1] = name end
    return {
        character = activeCharacterKey or "Character not available yet",
        active = activeProfileName,
        names = names,
        canManage = activeCharacterKey ~= nil,
    }
end

local function CleanProfileName(name)
    if type(name) ~= "string" then return nil, "Enter a profile name." end
    name = name:gsub("|", ""):gsub("%c", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil, "Profile names cannot be blank." end
    if #name > 32 then return nil, "Profile names must be 32 characters or fewer." end
    if name:lower() == "default" then return nil, "Default is reserved for the shared default profile." end
    return name
end

local function FindProfileName(name)
    local lower = name:lower()
    for existing in pairs(profileStore.profiles) do
        if existing:lower() == lower then return existing end
    end
end

local function SelectCharacterProfile(name)
    GetSettings()
    if not activeCharacterKey then return false, "The character name is not available yet." end
    if type(name) ~= "string" or type(profileStore.profiles[name]) ~= "table" then
        return false, "That Nameplate Extras profile does not exist."
    end
    profileStore.characterProfiles[activeCharacterKey] = name
    GetSettings()
    if QueueRefresh then QueueRefresh() end
    return true
end

local function CreateCharacterProfile(name)
    GetSettings()
    if not activeCharacterKey then return false, "The character name is not available yet." end
    name = CleanProfileName(name)
    if not name then return false, "Enter a valid profile name (1-32 characters)." end
    if FindProfileName(name) then return false, "A profile with that name already exists." end
    local count = 0
    for _ in pairs(profileStore.profiles) do count = count + 1 end
    if count >= MAX_PROFILES then return false, ("You can have up to %d profiles."):format(MAX_PROFILES) end
    profileStore.profiles[name] = Copy(DEFAULT_PROFILE)
    profileStore.characterProfiles[activeCharacterKey] = name
    GetSettings()
    if QueueRefresh then QueueRefresh() end
    return true
end

local function RenameCharacterProfile(name)
    GetSettings()
    local oldName = activeProfileName
    if oldName == "Default" then return false, "The shared Default profile cannot be renamed." end
    name = CleanProfileName(name)
    if not name then return false, "Enter a valid profile name (1-32 characters)." end
    local existing = FindProfileName(name)
    if existing and existing ~= oldName then return false, "A profile with that name already exists." end
    if name == oldName then return true end
    profileStore.profiles[name] = profileStore.profiles[oldName]
    profileStore.profiles[oldName] = nil
    for character, profileName in pairs(profileStore.characterProfiles) do
        if profileName == oldName then profileStore.characterProfiles[character] = name end
    end
    GetSettings()
    if QueueRefresh then QueueRefresh() end
    return true
end

local function DeleteCharacterProfile()
    GetSettings()
    local oldName = activeProfileName
    if oldName == "Default" then return false, "The shared Default profile cannot be deleted." end
    profileStore.profiles[oldName] = nil
    for character, profileName in pairs(profileStore.characterProfiles) do
        if profileName == oldName then profileStore.characterProfiles[character] = "Default" end
    end
    GetSettings()
    if QueueRefresh then QueueRefresh() end
    return true
end

addon.defaultRules = DEFAULT_RULES

local NP = _G.EllesmereNameplates_NS
local unitFrame = CreateFrame("Frame")
local queued = false
local states = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local spellSchools = {}
local combatLogActive = false

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
        state = { baseScale = plate:GetScale(), baseAlpha = plate:GetAlpha(), alphaFactor = 1, scaleFactor = 1 }
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

local function ResolveBarTexturePath(key)
    if key == "eui" then return nil end
    if key == "flat" then return "Interface\\Buttons\\WHITE8x8" end
    local nameplates = _G.EllesmereNameplates_NS
    if EllesmereUI and EllesmereUI.ResolveTexturePath and nameplates and nameplates.healthBarTextures then
        return EllesmereUI.ResolveTexturePath(nameplates.healthBarTextures, key, "Interface\\Buttons\\WHITE8x8")
    end
    return "Interface\\Buttons\\WHITE8x8"
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
        local isEmpowered
        name, _, _, _, _, _, notInterruptible, spellID, isEmpowered = UnitChannelInfo(unit)
        castState = "channel"
        if SafeBool(isEmpowered) == true then
            castState = "empowered"
        elseif IsSecret(isEmpowered) or (type(isEmpowered) ~= "nil" and SafeBool(isEmpowered) == nil) then
            castState = "unknown"
        end
    end
    if type(name) == "nil" then return "none", "any", "unknown" end
    local interruptible = "unknown"
    if not IsSecret(notInterruptible) and type(notInterruptible) == "boolean" then
        interruptible = notInterruptible and "uninterruptible" or "interruptible"
    end
    return castState, interruptible, GetSchool(spellID)
end

local function GetTraits(unit, checkQuestObjective)
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
    -- Neutral takes precedence; attackability still handles duels and unknown reactions.
    if UnitReaction then
        local value = UnitReaction("player", unit)
        if not IsSecret(value) and type(value) == "number" and value == 4 then reaction = "neutral" end
    end
    local classification = UnitClassification(unit)
    if IsSecret(classification) then classification = "unknown"
    elseif type(classification) == "nil" then classification = "normal"
    elseif classification == "worldboss" then classification = "boss" end
    local castState, interruptible, spellSchool = ReadCast(unit)
    local isTarget = SafeBool(UnitIsUnit(unit, "target"))
    local questObjective
    if checkQuestObjective and NP and NP.IsQuestMob then
        local ok, value = pcall(NP.IsQuestMob, unit)
        if ok then questObjective = SafeBool(value) end
    end
    return {
        unitType = unitType,
        isCreature = player == false,
        reaction = reaction,
        classification = classification,
        target = isTarget,
        questObjective = questObjective,
        tapDenied = UnitIsTapDenied and SafeBool(UnitIsTapDenied(unit)),
        castState = castState,
        interruptible = interruptible,
        spellSchool = spellSchool,
    }
end

local function AnySelectionMatches(selection, predicate)
    if selection == nil or selection == "any" then return true end
    if type(selection) == "string" then return predicate(selection) end
    if type(selection) ~= "table" then return false end
    local hasSelection = false
    for value, enabled in pairs(selection) do
        if enabled == true then
            hasSelection = true
            if predicate(value) then return true end
        end
    end
    return not hasSelection
end

local function HasSelection(selection)
    if type(selection) == "string" then return selection ~= "any" end
    if type(selection) == "table" then
        for _, enabled in pairs(selection) do
            if enabled == true then return true end
        end
    end
    return false
end

local function Matches(rule, unit, traits)
    if not rule.enabled then return false end
    local c = rule.conditions or {}
    if not AnySelectionMatches(c.unitType, function(value)
        if value == "creature" then return traits.isCreature == true end
        return value == traits.unitType
    end) then return false end
    if not AnySelectionMatches(c.reaction, function(value) return value == traits.reaction end) then return false end
    if not AnySelectionMatches(c.classification, function(value) return value == traits.classification end) then return false end
    if c.target == "yes" and traits.target ~= true then return false end
    if c.target == "no" and traits.target ~= false then return false end
    if type(c.target) == "table" and HasSelection(c.target) then
        local targetState = traits.target == true and "yes" or traits.target == false and "no" or nil
        if not AnySelectionMatches(c.target, function(value) return value == targetState end) then return false end
    end
    if c.questObjective == "yes" and traits.questObjective ~= true then return false end
    if c.questObjective == "no" and traits.questObjective ~= false then return false end
    if not AnySelectionMatches(c.castState, function(value)
        if value == "interruptible" or value == "uninterruptible" then
            return traits.interruptible == value
        end
        return traits.castState == value
    end) then return false end
    if not AnySelectionMatches(c.spellSchool, function(value)
        return traits.castState ~= "none" and value == traits.spellSchool
    end) then
        return false
    end
    for key, expected in pairs(c) do
        local predicate = addon.customConditions and addon.customConditions[key]
        if predicate then
            local ok, matches = pcall(predicate, unit, traits, expected, rule)
            if not ok or SafeBool(matches) ~= true then return false end
        elseif key ~= "unitType" and key ~= "reaction" and key ~= "classification"
           and key ~= "target" and key ~= "questObjective" and key ~= "castState" and key ~= "spellSchool" then
            return false
        end
    end
    return true
end

local function FindRule(unit)
    GetSettings()
    if db.enabled == false then return nil end
    local checkQuestObjective = false
    for _, candidate in ipairs(db.rules) do
        local conditions = candidate.conditions
        if candidate.enabled ~= false and conditions and conditions.questObjective
           and conditions.questObjective ~= "any" then
            checkQuestObjective = true
            break
        end
    end
    local traits = GetTraits(unit, checkQuestObjective)
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
            if rule.enabled ~= false and conditions and HasSelection(conditions.spellSchool) then
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
    local scale = state.baseScale * factor
    if plate:GetScale() == scale then return end
    state.writingScale = true
    plate:SetScale(scale)
    state.writingScale = nil
    if NP and NP.RefreshCastOverlay then NP.RefreshCastOverlay(plate) end
end

local function ApplyAlpha(plate, state)
    local alpha = state.baseAlpha * state.alphaFactor
    if plate:GetAlpha() == alpha then return end
    state.writingAlpha = true
    plate:SetAlpha(alpha)
    state.writingAlpha = nil
end

local function ResetStyle(plate, state, released)
    if addon.ApplyCastStyle then addon.ApplyCastStyle(plate, nil) end
    if state.border then state.border:Hide() end
    state.writingHealth = true
    if state.hadColor and state.baseColor and plate.health then
        local c = state.baseColor
        plate.health:SetStatusBarColor(c.r, c.g, c.b, c.a)
    end
    if state.hadTexture and state.baseTexture and plate.health then
        plate.health:SetStatusBarTexture(state.baseTexture)
        state.appliedHealthTexture = nil
        if plate.absorb and NP and NP.NP_LayoutAbsorbBars then
            NP.NP_LayoutAbsorbBars(plate, plate.health, plate._absEdge)
        end
    end
    state.writingHealth = nil
    if state.scaleFactor and state.scaleFactor ~= 1 and plate.SetScale then
        SetScaleFactor(plate, state, 1)
    end
    -- ClearUnit has already reset the engine's pool state. Do not restore the
    -- departing unit's alpha, including when the engine skipped its alpha setter.
    if released then state.baseAlpha = 1 end
    local hadAlpha = state.alphaFactor ~= 1
    state.alphaFactor = 1
    if (hadAlpha or released) and plate.SetAlpha then
        ApplyAlpha(plate, state)
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
        state.unit = unit
        state.hadColor, state.hadTexture = nil, nil
    end
    local rule, _, traits = FindRule(unit)
    rule = rule and rule or nil
    if not rule then ResetStyle(plate, state); return end
    local style = rule.style or {}
    state.rule = rule
    state.writingHealth = true
    local applyHealthColor = style.healthEnabled ~= false
        and style.healthColorEnabled and style.healthColor and traits.tapDenied ~= true
    if applyHealthColor then
        local c = style.healthColor
        plate.health:SetStatusBarColor(c.r or 1, c.g or 1, c.b or 1, 1)
        state.hadColor = true
    elseif state.hadColor and state.baseColor then
        local c = state.baseColor
        plate.health:SetStatusBarColor(c.r, c.g, c.b, c.a)
        state.hadColor = nil
    end
    local texture = style.healthEnabled ~= false and style.texture or "eui"
    local texturePath = ResolveBarTexturePath(texture or "eui")
    local textureChanged = false
    if texturePath then
        if state.appliedHealthTexture ~= texturePath or TextureOf(plate.health) ~= texturePath then
            plate.health:SetStatusBarTexture(texturePath)
            state.hadTexture = true
            state.appliedHealthTexture = texturePath
            textureChanged = true
        end
    elseif state.appliedHealthTexture then
        if state.baseTexture then plate.health:SetStatusBarTexture(state.baseTexture) end
        state.hadTexture = nil
        state.appliedHealthTexture = nil
        textureChanged = true
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
    if plate.SetAlpha then ApplyAlpha(plate, state) end
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

QueueRefresh = function()
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
        if state.scaleFactor ~= 1 then
            SetScaleFactor(self, state, state.scaleFactor)
        elseif NP and NP.RefreshCastOverlay then
            NP.RefreshCastOverlay(self)
        end
    end)
    -- Observe actual writes rather than NT_Apply's cache or our multiplied render
    -- value. This also preserves independent writers and works at zero opacity.
    hooksecurefunc(plate, "SetAlpha", function(self, alpha)
        if state.writingAlpha then return end
        state.baseAlpha = alpha
        if state.alphaFactor ~= 1 then ApplyAlpha(self, state) end
    end)
    if type(plate.ClearUnit) == "function" then
        hooksecurefunc(plate, "ClearUnit", function(self)
            ResetStyle(self, state, true)
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
            -- Cached passes do not write alpha and must not recapture our paint.
            QueueRefresh()
        end)
        addon.opacityHooked = true
    end
end

local events = {
    "ADDON_LOADED",
    "QUEST_LOG_UPDATE",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD",
    "UNIT_FLAGS", "UNIT_FACTION", "UNIT_NAME_UPDATE",
    "UNIT_THREAT_LIST_UPDATE",
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
    NormalizeRuleConditions = NormalizeRuleConditions,
    ValidateRuleConditions = ValidateRuleConditions,
    GetSettings = GetSettings,
    GetRules = function() return GetSettings().rules end,
    GetProfileInfo = ProfileInfo,
    SelectProfile = SelectCharacterProfile,
    CreateProfile = CreateCharacterProfile,
    RenameProfile = RenameCharacterProfile,
    DeleteProfile = DeleteCharacterProfile,
    MaxProfiles = MAX_PROFILES,
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
    local pluginRegistered = EllesmereUI and EllesmereUI.IsPluginRegistered
        and EllesmereUI.IsPluginRegistered("EllesmereUINameplateExtras") or false
    Report("EUI plugin section registered=" .. Text(pluginRegistered))
    Report("EUI plugin API available=" .. Text(EllesmereUI and type(EllesmereUI.RegisterPlugin) == "function"))
    if not pluginRegistered and addon.RegisterOptions then
        local ok, result = pcall(addon.RegisterOptions)
        Report("registration retry=" .. Text(ok and result == true)
            .. "; reason=" .. Text(addon.pluginRegistrationError or (not ok and result) or "not reported"))
    elseif addon.pluginRegistrationError then
        Report("registration error=" .. Text(addon.pluginRegistrationError))
    end
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
