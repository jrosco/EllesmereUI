local addonName, addon = ...

local MULTI_CONDITION_VALUES = {
    unitType = { player = true, npc = true, pet = true, creature = true },
    reaction = { enemy = true, friendly = true, neutral = true },
    classification = { normal = true, elite = true, rare = true, rareelite = true, boss = true, minus = true },
    target = { yes = true, no = true, none = true },
    threat = { nonTank = true, tank = true, me = true },
    playerCombat = { inCombat = true, outOfCombat = true },
    instanceType = { world = true, dungeon = true, raid = true, battleground = true, arena = true, scenario = true, delve = true },
    castState = { none = true, casting = true, channel = true, empowered = true, interruptible = true, interruptOnCD = true, uninterruptible = true },
    spellSchool = { physical = true, holy = true, fire = true, nature = true, frost = true, shadow = true, arcane = true, mixed = true },
}
local SCALAR_CONDITION_VALUES = {
    questObjective = { any = true, yes = true, no = true },
}
local DEFAULT_CONDITIONS = { questObjective = "any" }
local INSTANCE_TYPES = { none = "world", party = "dungeon", raid = "raid", pvp = "battleground",
    arena = "arena", scenario = "scenario", delve = "delve" }

local DEFAULT_RULES = {
    {
        name = "Elite Enemies",
        enabled = true,
        conditions = { unitType = {}, reaction = { enemy = true }, classification = { elite = true }, target = {}, questObjective = "any", castState = {}, spellSchool = {} },
        style = { healthColorEnabled = true, healthColor = { r = 0.72, g = 0.36, b = 1.00 }, scale = 120, opacity = 100, borderSize = 2, borderColor = { r = 1.00, g = 1.00, b = 1.00 }, texture = "eui" },
    },
    {
        name = "Enemy Casting",
        enabled = true,
        conditions = { unitType = {}, reaction = { enemy = true }, classification = {}, target = {}, questObjective = "any", castState = { casting = true }, spellSchool = {} },
        style = { healthColorEnabled = true, healthColor = { r = 1.00, g = 0.28, b = 0.18 }, scale = 120, opacity = 100, borderSize = 2, borderColor = { r = 1.00, g = 1.00, b = 1.00 }, texture = "eui" },
    },
    {
        name = "Current Target",
        enabled = true,
        conditions = { unitType = {}, reaction = {}, classification = {}, target = { yes = true }, questObjective = "any", castState = {}, spellSchool = {} },
        style = { healthColorEnabled = true, healthColor = { r = 0.12, g = 0.92, b = 0.67 }, scale = 110, opacity = 100, borderSize = 2, borderColor = { r = 1.00, g = 1.00, b = 1.00 }, texture = "eui" },
    },
    {
        name = "Non Target",
        enabled = true,
        conditions = { unitType = {}, reaction = {}, classification = {}, target = { no = true, none = true }, questObjective = "any", castState = {}, spellSchool = {} },
        style = { healthColorEnabled = true, healthColor = { r = 0.12, g = 0.92, b = 0.67 }, scale = 100, opacity = 50, borderSize = 1, borderColor = { r = 1.00, g = 1.00, b = 1.00 }, texture = "eui" },
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
local MAX_RULES = 100
local MAX_PROFILES = 100

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
        if addon.NormalizeScaleElements then rule.style.scaleElements = addon.NormalizeScaleElements(rule.style.scaleElements) end
        if rule.enabled == nil then rule.enabled = true end
    end
    profile.selectedRule = math.max(1, math.min(tonumber(profile.selectedRule) or 1, #profile.rules))
    return profile
end

local function GetSettings()
    local saved = _G.EllesmereUIExtendNameplatesDB
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
    _G.EllesmereUIExtendNameplatesDB = saved
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
        return false, "That Extend Nameplates profile does not exist."
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

local function ResetActiveProfile()
    local current = GetSettings()
    local fresh = NormalizeProfile(Copy(DEFAULT_PROFILE))
    -- Keep the active settings object/profile assignment stable for consumers,
    -- but remove every customization instead of resetting only selected keys.
    for key in pairs(current) do current[key] = nil end
    for key, value in pairs(fresh) do current[key] = value end
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
local snapshotState
local watchCastTransitions = false
local pendingPlates = setmetatable({}, { __mode = "k" })
local refreshAllQueued, checkTransitionsQueued = false, false

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

local function ReadCast(unit, includeDebug)
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
    local debugInfo
    if includeDebug then
        local secret = IsSecret(notInterruptible) == true
        debugInfo = {
            source = type(name) == "nil" and "none" or (castState == "casting" and "UnitCastingInfo" or "UnitChannelInfo"),
            secretCheckAvailable = type(issecretvalue) == "function",
            secret = secret,
            knowledge = secret and "unknown (secret)" or
                (type(notInterruptible) == "boolean" and "known" or "unknown (unavailable)"),
        }
    end
    if type(name) == "nil" then return "none", "any", "unknown", debugInfo end
    local interruptible = "unknown"
    if not IsSecret(notInterruptible) and type(notInterruptible) == "boolean" then
        interruptible = notInterruptible and "uninterruptible" or "interruptible"
    end
    return castState, interruptible, GetSchool(spellID), debugInfo
end

local function ReadKnownCastColorState(interruptible)
    if interruptible == "uninterruptible" then return "uninterruptible" end
    if interruptible ~= "interruptible" then return "unknown" end
    local getKick = EllesmereUI and EllesmereUI.GetActiveKickSpell
    local spell = getKick and getKick()
    if not spell or not (C_Spell and C_Spell.GetSpellCooldownDuration)
        or not (C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean) then return "interruptible" end
    local cooldown = C_Spell.GetSpellCooldownDuration(spell)
    if not (cooldown and cooldown.IsZero) then return "interruptible" end
    local ready = SafeBool(cooldown:IsZero())
    if ready == nil then return "unknown" end
    return ready and "interruptible" or "interruptOnCD"
end

local function KnownCastColorState(interruptible)
    local value = ReadKnownCastColorState(interruptible)
    -- Capture the actual ordinary-rule snapshot, not a second API read after
    -- applying it. Direct FindRule/diagnostic calls must not advance this cache.
    if snapshotState and snapshotState.castColorSnapshot == nil then
        snapshotState.castColorSnapshot = value
    end
    return value
end

local function ReadThreat(unit, checkRoles, targetExists, isTarget)
    local result = {}
    if type(UnitDetailedThreatSituation) ~= "function" then return result end
    -- Current-target pairings can be readable when nameplate pairings are not.
    local mob = targetExists == true and isTarget == true and "target" or unit
    local function IsHolding(participant)
        local ok, value = pcall(UnitDetailedThreatSituation, participant, mob)
        if ok then return SafeBool(value) end
    end
    local function Classify(participant)
        local getRole = (EllesmereUI and EllesmereUI.UnitEffectiveRole) or UnitGroupRolesAssigned
        if type(getRole) ~= "function" then return false end
        local ok, role = pcall(getRole, participant)
        if not ok or IsSecret(role) or type(role) ~= "string" then return false end
        if role == "TANK" then result.tank, result.nonTank = true, false
        elseif role == "DAMAGER" or role == "HEALER" then result.tank, result.nonTank = false, true
        else return false end -- NONE is unassigned, not proof of a non-tank role.
        result.holder = participant
        result.role = role
        return true
    end
    result.me = IsHolding("player")
    if result.me == true then result.holder = "player" end
    if not checkRoles then return result end
    if result.me == true then Classify("player"); return result end
    local function CheckHolder(participant)
        if SafeBool(UnitExists(participant)) ~= true or IsHolding(participant) ~= true then return false end
        result.holder = participant
        if SafeBool(UnitIsUnit(participant, "player")) == true then result.me = true end
        return Classify(participant)
    end
    -- The unit's target is only a candidate: casts can temporarily target a
    -- different player. Require detailed threat confirmation before using its role.
    if CheckHolder(mob .. "target") or CheckHolder("pet") then return result end
    local raid = IsInRaid and SafeBool(IsInRaid()) == true
    local count = 0
    if raid and GetNumGroupMembers then count = GetNumGroupMembers()
    elseif GetNumSubgroupMembers then count = GetNumSubgroupMembers()
    elseif GetNumGroupMembers then
        local members = GetNumGroupMembers()
        if not IsSecret(members) and type(members) == "number" then count = members - 1 end
    end
    if IsSecret(count) or type(count) ~= "number" or count ~= count then return result end
    count = math.max(0, math.min(raid and 40 or 4, math.floor(count)))
    for i = 1, count do
        if CheckHolder((raid and "raid" or "party") .. i)
            or CheckHolder((raid and "raidpet" or "partypet") .. i) then return result end
    end
    return result
end

local function SupportsInstanceType(value)
    if MULTI_CONDITION_VALUES.instanceType[value] ~= true then return false end
    if EllesmereUI and EllesmereUI.IS_FOREVER == true then
        return value ~= "arena" and value ~= "scenario" and value ~= "delve"
    end
    return MULTI_CONDITION_VALUES.instanceType[value] == true
end
local function ReadPlayerCombat()
    if type(UnitAffectingCombat) ~= "function" then return "unknown" end
    local ok, result = pcall(UnitAffectingCombat, "player")
    if not ok then return "unknown" end
    local value = SafeBool(result)
    if value == true then return "inCombat" elseif value == false then return "outOfCombat" end
    return "unknown"
end
local function ReadInstanceType()
    if type(GetInstanceInfo) ~= "function" then return "unknown" end
    local ok, _, kind, difficulty = pcall(GetInstanceInfo)
    if not ok or IsSecret(kind) or type(kind) ~= "string" then return "unknown" end
    local value = INSTANCE_TYPES[kind]
    if kind == "scenario" then
        -- Delves report scenario/208 even after completion. Do not classify
        -- them from an in-progress flag that can clear while still inside.
        if IsSecret(difficulty) or type(difficulty) ~= "number" then return "unknown" end
        if difficulty == 208 then value = "delve" end
    end
    return value and SupportsInstanceType(value) and value or "unknown"
end
local function GetTraits(unit, checkQuestObjective, checkThreat, checkThreatRoles, checkCombat, checkInstance)
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
    local targetExists = SafeBool(UnitExists("target"))
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
        targetExists = targetExists,
        threat = checkThreat and ReadThreat(unit, checkThreatRoles, targetExists, isTarget) or nil,
        questObjective = questObjective,
        tapDenied = UnitIsTapDenied and SafeBool(UnitIsTapDenied(unit)),
        castState = castState,
        interruptible = interruptible,
        castColorState = KnownCastColorState(interruptible),
        spellSchool = spellSchool,
        playerCombat = checkCombat and ReadPlayerCombat() or nil,
        instanceType = checkInstance and ReadInstanceType() or nil,
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

local function ThreatRequirements(rules)
    local needed = false
    for _, rule in ipairs(rules) do
        local selection = rule.conditions and rule.conditions.threat
        if rule.enabled ~= false and HasSelection(selection) then
            needed = true
            if selection == "tank" or selection == "nonTank" or (type(selection) == "table"
                and (selection.tank == true or selection.nonTank == true)) then return true, true end
        end
    end
    return needed, false
end
local function ContextRequirements(rules)
    local combat, instance = false, false
    for _, rule in ipairs(rules) do
        if rule.enabled ~= false then
            local conditions = rule.conditions or {}
            combat = combat or HasSelection(conditions.playerCombat)
            instance = instance or HasSelection(conditions.instanceType)
        end
    end
    return combat, instance
end

local CAST_COLOR_STATES = { "interruptible", "interruptOnCD", "uninterruptible" }
local function IsCastColorState(value)
    return value == "interruptible" or value == "interruptOnCD" or value == "uninterruptible"
end

local function SupportsCastColorStates()
    local np = _G.EllesmereNameplates_NS
    if not np then return false end
    -- The rendered style is reload-latched; pending profile flags cannot override it.
    if type(np.NP_Style) == "function" then
        local style = np.NP_Style()
        return style == "eui" or style == "classic"
    end
    if type(np._npStyle) == "string" then return np._npStyle == "eui" or np._npStyle == "classic" end
    local profile = np.db and np.db.profile
    -- Older engines have no latch/accessor. Match their Classic-first default.
    return not profile or profile.useClassicStyle == true or not profile.useBlizzardStyle
end
addon.SupportsCastColorStates = SupportsCastColorStates

local function MatchesReadableConditions(rule, unit, traits)
    local c = rule.conditions or {}
    if not AnySelectionMatches(c.unitType, function(value)
        if value == "creature" then return traits.isCreature == true end
        return value == traits.unitType
    end) then return false end
    if not AnySelectionMatches(c.reaction, function(value) return value == traits.reaction end) then return false end
    if not AnySelectionMatches(c.classification, function(value) return value == traits.classification end) then return false end
    if not AnySelectionMatches(c.playerCombat, function(value) return value == traits.playerCombat end) then return false end
    if not AnySelectionMatches(c.instanceType, function(value) return SupportsInstanceType(value) and value == traits.instanceType end) then return false end
    if not AnySelectionMatches(c.target, function(value)
        if value == "yes" then return traits.targetExists == true and traits.target == true end
        if value == "no" then return traits.targetExists == true and traits.target == false end
        if value == "none" then return traits.targetExists == false end
        return false
    end) then return false end
    if not AnySelectionMatches(c.threat, function(value)
        return traits.threat and traits.threat[value] == true
    end) then return false end
    if c.questObjective == "yes" and traits.questObjective ~= true then return false end
    if c.questObjective == "no" and traits.questObjective ~= false then return false end
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
           and key ~= "target" and key ~= "threat" and key ~= "questObjective" and key ~= "castState" and key ~= "spellSchool"
           and key ~= "playerCombat" and key ~= "instanceType" then
            return false
        end
    end
    return true
end

local function MatchesWithSnapshot(rule, unit, traits, forCastColors, snapshot)
    if not rule.enabled then return false end
    local c = rule.conditions or {}
    -- Color-state choices imply active Casting for appearance eligibility.
    -- Their precise state is consumed only by the native cast-color renderer.
    if not AnySelectionMatches(c.castState, function(value)
        if value == "casting" or IsCastColorState(value) then
            return type(traits.castState) == "string" and traits.castState ~= "none"
        end
        return traits.castState == value
    end) then return false end
    if not snapshot then return MatchesReadableConditions(rule, unit, traits) end
    local results = snapshot[unit]
    if not results then results = {}; snapshot[unit] = results end
    if results[rule] == nil then
        results[rule] = MatchesReadableConditions(rule, unit, traits)
    end
    return results[rule]
end

local function Matches(rule, unit, traits, forCastColors)
    return MatchesWithSnapshot(rule, unit, traits, forCastColors)
end

local function CastColorMask(selection, traits)
    local mask = {}
    local function Selected(key)
        return selection == key or (type(selection) == "table" and selection[key] == true)
    end
    local broad = not HasSelection(selection) or Selected("casting")
    if traits then
        broad = broad or (Selected("channel") and traits.castState == "channel")
            or (Selected("empowered") and traits.castState == "empowered")
            or (Selected("none") and traits.castState == "none")
    end
    -- Broad selections remain generic tints, including mixed broad/state choices.
    -- Unsupported state-only selections contribute nothing; never rewrite saved choices.
    local supportsStates = SupportsCastColorStates()
    for _, key in ipairs(CAST_COLOR_STATES) do mask[key] = broad or (supportsStates and Selected(key)) end
    return mask
end
addon.CastColorMask = CastColorMask

local function FindCastColorOverridesWithSnapshot(unit, traits, snapshot)
    local settings = GetSettings()
    local colors = {}
    if settings.enabled == false then return colors end
    if not traits then
        local checkThreat, checkRoles = ThreatRequirements(settings.rules)
        local checkCombat, checkInstance = ContextRequirements(settings.rules)
        traits = GetTraits(unit, true, checkThreat, checkRoles, checkCombat, checkInstance)
    end
    local matches = snapshot and MatchesWithSnapshot or Matches
    for index, rule in ipairs(settings.rules) do
        local style = rule.style
        if style and style.castEnabled and style.castColorEnabled
           and matches(rule, unit, traits, true, snapshot) then
            local mask = CastColorMask(rule.conditions and rule.conditions.castState, traits)
            local candidate = { rule = rule, style = style, index = index }
            for _, key in ipairs(CAST_COLOR_STATES) do
                if mask[key] and not colors[key] then colors[key] = candidate end
            end
            if colors.interruptible and colors.interruptOnCD and colors.uninterruptible then break end
        end
    end
    return colors
end
local function FindCastColorOverrides(unit, traits)
    return FindCastColorOverridesWithSnapshot(unit, traits)
end
addon.FindCastColorOverrides = FindCastColorOverrides

local function FindRuleWithSnapshot(unit, snapshot)
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
    local checkThreat, checkRoles = ThreatRequirements(db.rules)
    local checkCombat, checkInstance = ContextRequirements(db.rules)
    local traits = GetTraits(unit, checkQuestObjective, checkThreat, checkRoles, checkCombat, checkInstance)
    local matches = snapshot and MatchesWithSnapshot or Matches
    for index, rule in ipairs(db.rules) do
        if matches(rule, unit, traits, false, snapshot) then return rule, index, traits end
    end
    return nil, nil, traits
end

local function FindRule(unit)
    return FindRuleWithSnapshot(unit)
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

local function ResetStyle(plate, state, released, castColors)
    if addon.ApplyRuleText then addon.ApplyRuleText(plate, nil) end
    if addon.ApplyRuleGlows then addon.ApplyRuleGlows(plate, nil) end
    if addon.ApplyRuleBorders then addon.ApplyRuleBorders(plate, nil) end
    if addon.ApplyTargetArrowStyle then addon.ApplyTargetArrowStyle(plate, nil, released) end
    if addon.ApplyCastStyle then addon.ApplyCastStyle(plate, nil, nil, castColors) end
    local refreshResources = addon.ClearScaleSelection and addon.ClearScaleSelection(plate)
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
    if refreshResources and NP and NP.RefreshClassPower and not released then NP.RefreshClassPower() end
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
        state.unit = unit
        state.hadColor, state.hadTexture = nil, nil
    end
    -- Never retain evaluation results on a plate or across rendering refreshes.
    local snapshot = {}
    local rule, _, traits = FindRuleWithSnapshot(unit, snapshot)
    local castColors = FindCastColorOverridesWithSnapshot(unit, traits, snapshot)
    rule = rule and rule or nil
    if not rule then ResetStyle(plate, state, false, castColors); return end
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
    if addon.ApplyRuleText then addon.ApplyRuleText(plate, style) end
    if addon.ApplyRuleBorders then addon.ApplyRuleBorders(plate, style) end
    if addon.ApplyTargetArrowStyle then addon.ApplyTargetArrowStyle(plate, style) end
    local scale = math.max(50, math.min(200, tonumber(style.scale) or 100)) / 100
    local opacity = math.max(0, math.min(100, tonumber(style.opacity) or 100)) / 100
    local rootScale = addon.PrepareScaleSelection and addon.PrepareScaleSelection(plate, scale, style.scaleElements) or scale
    SetScaleFactor(plate, state, rootScale)
    if addon.ApplyScaleSelection then addon.ApplyScaleSelection(plate) end
    state.alphaFactor = opacity
    if plate.SetAlpha then ApplyAlpha(plate, state) end
    if addon.ApplyCastStyle then addon.ApplyCastStyle(plate, style, rule.conditions, castColors) end
    if addon.ApplyRuleGlows then addon.ApplyRuleGlows(plate, style) end
end

local InstallHooks

local function ApplyPlateSafely(plate)
    local state = GetState(plate)
    local previousSnapshotState = snapshotState
    state.castColorSnapshot = nil
    state.snapshotUnit = plate.unit
    snapshotState = state
    local ok, err = pcall(ApplyStyle, plate)
    snapshotState = previousSnapshotState
    if not ok then
        state.castColorSnapshot = nil
        local report = geterrorhandler and geterrorhandler()
        if report then report(err) end
    end
end

local function UpdateCastTransitionTracking()
    watchCastTransitions = false
    if db.enabled == false then return end
    for _, rule in ipairs(db.rules) do
        local selection = rule.conditions and rule.conditions.castState
        if rule.enabled ~= false and (selection == "interruptible" or selection == "interruptOnCD"
            or selection == "uninterruptible" or (type(selection) == "table"
            and (selection.interruptible or selection.interruptOnCD or selection.uninterruptible))) then
            watchCastTransitions = true
            return
        end
    end
end

local function ReadPlateCastColorState(unit)
    local _, interruptible = ReadCast(unit)
    return ReadKnownCastColorState(interruptible)
end

local function CheckCastTransition(plate)
    if not watchCastTransitions or GetSettings().enabled == false then return end
    local state = states[plate]
    if not state or not plate.unit or state.snapshotUnit ~= plate.unit
        or state.castColorSnapshot == nil then return end
    local ok, value = pcall(ReadPlateCastColorState, plate.unit)
    if not ok then value = "unknown" end
    if value ~= state.castColorSnapshot then
        -- Do not advance the snapshot until rules have actually been applied.
        pendingPlates[plate] = plate.unit
        return true
    end
end

local function RefreshAll()
    GetSettings()
    if not NP then NP = _G.EllesmereNameplates_NS end
    if not NP then return end
    if InstallHooks then InstallHooks() end
    UpdateCombatLogRegistration()
    UpdateCastTransitionTracking()
    for _, plate in pairs(NP.plates or {}) do ApplyPlateSafely(plate) end
    for _, plate in pairs(NP.friendlyPlates or {}) do ApplyPlateSafely(plate) end
end

local function ScheduleRefresh()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        local all, check = refreshAllQueued, checkTransitionsQueued
        refreshAllQueued, checkTransitionsQueued = false, false
        if all then
            pendingPlates = setmetatable({}, { __mode = "k" })
            RefreshAll()
            return
        end
        if check and watchCastTransitions and GetSettings().enabled ~= false then
            -- EUI already maintains the active-cast set. Older engines use the
            -- installed plate states, still applying only changed snapshots.
            for plate in pairs((NP and NP._castingPlates) or states) do
                CheckCastTransition(plate)
            end
        end
        local pending = pendingPlates
        pendingPlates = setmetatable({}, { __mode = "k" })
        for plate, unit in pairs(pending) do
            if plate.unit == unit then ApplyPlateSafely(plate) end
        end
    end)
end

QueueRefresh = function()
    refreshAllQueued = true
    ScheduleRefresh()
end

local function QueueCastTransitionCheck()
    if not watchCastTransitions or GetSettings().enabled == false then return end
    if NP and NP._castingPlates and next(NP._castingPlates) == nil then return end
    checkTransitionsQueued = true
    ScheduleRefresh()
end

local function InstallPlateHooks(plate)
    if not plate then return end
    if addon.InstallTextHooks then addon.InstallTextHooks(plate) end
    if addon.InstallGlowHooks then addon.InstallGlowHooks(plate) end
    if addon.InstallBorderHooks then addon.InstallBorderHooks(plate) end
    if addon.InstallTargetArrowHooks then addon.InstallTargetArrowHooks(plate) end
    if hooked[plate] then return end
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
            pendingPlates[self] = nil
            state.castColorSnapshot, state.snapshotUnit = nil, nil
            ResetStyle(self, state, true)
            state.unit = nil
        end)
    end
    if type(plate.ApplyCastColor) == "function" then
        hooksecurefunc(plate, "ApplyCastColor", function(self)
            if snapshotState then return end
            if CheckCastTransition(self) then ScheduleRefresh() end
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
    if addon.InstallScaleSelectionHooks then addon.InstallScaleSelectionHooks() end
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
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_DIFFICULTY_CHANGED", "UPDATE_INSTANCE_INFO",
    "UNIT_FLAGS", "UNIT_FACTION", "UNIT_NAME_UPDATE",
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
    "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM",
    "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "SPELLS_CHANGED", "UNIT_PET",
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
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_USABLE"
        or event == "SPELLS_CHANGED" or event == "UNIT_PET" then
        if event == "UNIT_PET" and loadedAddon ~= "player" then return end
        -- Run after all listeners so EUI's active kick lookup is up to date.
        QueueCastTransitionCheck()
        return
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        for plate in pairs(states) do
            if plate.unit and plate.unit == loadedAddon then
                -- Preserve event-driven custom predicates too, but reevaluate
                -- only the affected unit instead of every visible plate.
                pendingPlates[plate] = plate.unit
                ScheduleRefresh()
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
    SupportsCastColorStates = SupportsCastColorStates,
    SupportsInstanceType = SupportsInstanceType,
    GetSettings = GetSettings,
    GetRules = function() return GetSettings().rules end,
    GetProfileInfo = ProfileInfo,
    SelectProfile = SelectCharacterProfile,
    CreateProfile = CreateCharacterProfile,
    RenameProfile = RenameCharacterProfile,
    DeleteProfile = DeleteCharacterProfile,
    ResetActiveProfile = ResetActiveProfile,
    MaxProfiles = MAX_PROFILES,
    MaxRules = MAX_RULES,
    DefaultRules = Copy(DEFAULT_RULES),
}
-- Public runtime namespace for Extend Nameplates.
_G.EllesmereUIExtendNameplates = publicAPI

SLASH_EXTENDNAMEPLATES1 = "/enp"
SLASH_EXTENDNAMEPLATES2 = "/extendnameplates"
SlashCmdList.EXTENDNAMEPLATES = function(message)
    if type(message) == "string" and message:lower():match("^%s*cast%s*$") then
        local function ReportCast(text) print("Extend Nameplates: " .. text) end
        if not UnitExists("target") then ReportCast("Cast debug: select a target first."); return end
        local ok, castState, interruptible, _, debugInfo = pcall(ReadCast, "target", true)
        if not ok then ReportCast("Cast debug: API read failed; state unknown."); return end
        ReportCast("Target cast=" .. castState .. "; source=" .. debugInfo.source
            .. "; interruptibility=" .. interruptible .. "; knowledge=" .. debugInfo.knowledge)
        ReportCast("issecretvalue available=" .. tostring(debugInfo.secretCheckAvailable)
            .. "; notInterruptible secret=" .. tostring(debugInfo.secret))
        local known, colorState = pcall(KnownCastColorState, interruptible)
        ReportCast("Known EUI color state=" .. (known and colorState or "unknown"))
        if castState == "none" then
            ReportCast("No active cast/channel. Run /enp cast while the target is casting.")
        elseif debugInfo.secret then
            ReportCast("Lua cannot read the active color state; native rendering selects among the per-state overrides.")
        end
        local matched, rule, index = pcall(FindRule, "target")
        if matched then
            if rule then ReportCast("Winning nameplate rule=" .. index .. " (" .. tostring(rule.name) .. ")")
            else ReportCast("No winning nameplate rule.") end
        else
            ReportCast("Target rule evaluation failed.")
        end
        local colorsOK, colors = pcall(FindCastColorOverrides, "target")
        if colorsOK then
            for _, key in ipairs(CAST_COLOR_STATES) do
                local candidate = colors[key]
                ReportCast("Cast color " .. key .. "=" .. (candidate and
                    ("rule " .. candidate.index .. " (" .. tostring(candidate.rule.name) .. ")") or "EUI default"))
            end
        else ReportCast("Cast color evaluation failed.") end
        return
    end
    GetSettings()
    local function Text(value)
        if IsSecret(value) then return "<restricted>" end
        return tostring(value)
    end
    local function Report(message)
        print("Extend Nameplates: " .. message)
    end
    Report("diagnostics v3; addon=EllesmereUIExtendNameplates; feature=Nameplate Style; enabled=" .. Text(db.enabled ~= false)
        .. "; settings shared with options=" .. Text(db == _G.EllesmereUIExtendNameplatesDB))
    local pluginRegistered = EllesmereUI and EllesmereUI.IsPluginRegistered
        and EllesmereUI.IsPluginRegistered("EllesmereUIExtendNameplates") or false
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
    local ok, traits = pcall(GetTraits, targetPlate.unit, false, true, true)
    if not ok then Report("Detection ERROR: " .. Text(traits)); return end
    Report("type=" .. Text(traits.unitType) .. "; reaction=" .. Text(traits.reaction)
        .. "; rank=" .. Text(traits.classification) .. "; target=" .. Text(traits.target)
        .. "; cast=" .. Text(traits.castState) .. "; interruptibility=" .. Text(traits.interruptible))
    local threat = traits.threat or {}
    Report("threat: tank=" .. Text(threat.tank) .. "; non-tank=" .. Text(threat.nonTank)
        .. "; on me=" .. Text(threat.me) .. "; holder=" .. Text(threat.holder) .. "; role=" .. Text(threat.role))
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
