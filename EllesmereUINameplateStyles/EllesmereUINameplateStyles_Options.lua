local addon = EllesmereUINameplateStyles and EllesmereUINameplateStyles
if not addon then return end

local PLUGIN_ID = "EllesmereUINameplateStyles"
local MAX_RULES = addon.MaxRules or 12

local UNIT_TYPES = { any = "Any unit", player = "Player", npc = "NPC", pet = "Player-controlled pet", creature = "Any creature" }
local UNIT_ORDER = { "any", "player", "npc", "pet", "creature" }
local REACTIONS = { any = "Any reaction", enemy = "Enemy", friendly = "Friendly", neutral = "Neutral" }
local REACTION_ORDER = { "any", "enemy", "friendly", "neutral" }
local CLASSIFICATIONS = { any = "Any rank", normal = "Normal", elite = "Elite", rare = "Rare", rareelite = "Rare Elite", boss = "Boss", minus = "Minor" }
local CLASSIFICATION_ORDER = { "any", "normal", "elite", "rare", "rareelite", "boss", "minus" }
local TARGETS = { any = "Any target state", yes = "Current target", no = "Not current target" }
local TARGET_ORDER = { "any", "yes", "no" }
local CAST_STATES = {
    any = "Any cast state", none = "Not casting", casting = "Casting", channel = "Channeling",
    empowered = "Empowered cast", interruptible = "Interruptible cast", uninterruptible = "Uninterruptible cast",
}
local CAST_ORDER = { "any", "none", "casting", "channel", "empowered", "interruptible", "uninterruptible" }
local SCHOOLS = { any = "Any spell school", physical = "Physical", holy = "Holy", fire = "Fire", nature = "Nature", frost = "Frost", shadow = "Shadow", arcane = "Arcane", mixed = "Mixed" }
local SCHOOL_ORDER = { "any", "physical", "holy", "fire", "nature", "frost", "shadow", "arcane", "mixed" }
local TEXTURES = { eui = "Use EUI texture", flat = "Flat", blizzard = "Blizzard" }
local TEXTURE_ORDER = { "eui", "flat", "blizzard" }

local function DB()
    return addon.GetSettings()
end

local function GetRule()
    local db = DB()
    local index = math.max(1, math.min(tonumber(db.selectedRule) or 1, #db.rules))
    db.selectedRule = index
    return db.rules[index], index
end

local function Changed()
    addon.Refresh()
end

local function CopyRule(rule)
    local result = {}
    for key, value in pairs(rule) do
        if type(value) == "table" then
            local copy = {}
            for nestedKey, nestedValue in pairs(value) do
                if type(nestedValue) == "table" then
                    local color = {}
                    for colorKey, colorValue in pairs(nestedValue) do color[colorKey] = colorValue end
                    copy[nestedKey] = color
                else
                    copy[nestedKey] = nestedValue
                end
            end
            result[key] = copy
        else
            result[key] = value
        end
    end
    return result
end

local function Rebuild()
    local key = EllesmereUI.GetPluginModuleKey(PLUGIN_ID, "Styles")
    if key then EllesmereUI:InvalidateModulePageCache(key) end
    EllesmereUI:RefreshPage(true)
end

local function NewRule(index)
    return {
        name = "Custom Rule " .. index,
        enabled = true,
        conditions = { unitType = "any", reaction = "any", classification = "any", target = "yes", castState = "any", spellSchool = "any" },
        style = { healthColorEnabled = true, healthColor = { r = 1, g = 0.72, b = 0.15 }, scale = 100, opacity = 100, borderSize = 2, borderColor = { r = 1, g = 0.72, b = 0.15 }, texture = "eui" },
    }
end

local function BuildRulesPage(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    local db = DB()
    local rule, selected = GetRule()

    _, h = W:SectionHeader(parent, "RULE ORDER", y); y = y - h
    local labels, order = {}, {}
    for i, item in ipairs(db.rules) do
        local key = tostring(i)
        labels[key] = (item.enabled == false and "Off - " or "") .. (item.name or ("Rule " .. i))
        order[#order + 1] = key
    end
    _, h = W:Dropdown(parent, "Edit rule", y, labels,
        function() return tostring(DB().selectedRule or 1) end,
        function(value)
            DB().selectedRule = tonumber(value) or 1
            Rebuild()
        end, order,
        "Rules are checked from top to bottom; the first enabled match wins. New rules start enabled for your current target.")
    y = y - h
    _, h = W:DualRow(parent, y, {
        type = "input",
        text = "Rule name",
        inputWidth = 260,
        inputStyle = "popup",
        tooltip = "Rename this rule. Press Enter or click outside the field to save. Blank names are ignored.",
        getValue = function() return rule.name or ("Rule " .. selected) end,
        setValue = function(value)
            local name = value:gsub("|", ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" or name == rule.name then return end
            -- Bind to this page's rule so a focus-loss commit cannot rename a newly selected rule.
            rule.name = name
            Rebuild()
        end,
    }, nil); y = y - h
    _, h = W:Button(parent, "Add Rule", y, function()
        local current = DB()
        if #current.rules >= MAX_RULES then return end
        table.insert(current.rules, 1, NewRule(#current.rules + 1))
        current.selectedRule = 1
        Rebuild()
        Changed()
    end); y = y - h
    _, h = W:Button(parent, "Delete Rule", y, function()
        local current = DB()
        if #current.rules <= 1 then return end
        table.remove(current.rules, current.selectedRule)
        current.selectedRule = math.min(current.selectedRule, #current.rules)
        Rebuild()
        Changed()
    end); y = y - h
    _, h = W:Button(parent, "Move Rule Up", y, function()
        local current = DB()
        local index = current.selectedRule
        if index <= 1 then return end
        current.rules[index], current.rules[index - 1] = current.rules[index - 1], current.rules[index]
        current.selectedRule = index - 1
        Rebuild()
        Changed()
    end); y = y - h
    _, h = W:Button(parent, "Move Rule Down", y, function()
        local current = DB()
        local index = current.selectedRule
        if index >= #current.rules then return end
        current.rules[index], current.rules[index + 1] = current.rules[index + 1], current.rules[index]
        current.selectedRule = index + 1
        Rebuild()
        Changed()
    end); y = y - h

    _, h = W:SectionHeader(parent, "MATCH CONDITIONS", y); y = y - h
    _, h = W:Toggle(parent, "Rule enabled", y,
        function() return GetRule().enabled ~= false end,
        function(value) GetRule().enabled = value; Rebuild(); Changed() end)
    y = y - h

    local function ConditionDropdown(label, key, values, keys, tooltip)
        local _, rowHeight = W:Dropdown(parent, label, y, values,
            function()
                local current = GetRule()
                return current.conditions[key] or "any"
            end,
            function(value)
                local current = GetRule()
                current.conditions[key] = value
                Changed()
            end, keys, tooltip)
        y = y - rowHeight
    end
    ConditionDropdown("Unit type", "unitType", UNIT_TYPES, UNIT_ORDER,
        "Player, NPC, player-controlled pet, or any non-player creature.")
    ConditionDropdown("Reaction", "reaction", REACTIONS, REACTION_ORDER)
    ConditionDropdown("Classification", "classification", CLASSIFICATIONS, CLASSIFICATION_ORDER,
        "Uses the unit's game classification: normal, elite, rare, rare elite, boss, or minor.")
    ConditionDropdown("Target state", "target", TARGETS, TARGET_ORDER)
    ConditionDropdown("Cast state", "castState", CAST_STATES, CAST_ORDER)
    ConditionDropdown("Spell school", "spellSchool", SCHOOLS, SCHOOL_ORDER,
        "Learns spell schools from combat-log cast starts while a school rule is enabled. Unknown spells do not match a specific school.")

    _, h = W:SectionHeader(parent, "APPEARANCE", y); y = y - h
    _, h = W:Toggle(parent, "Override health-bar color", y,
        function() return GetRule().style.healthColorEnabled ~= false end,
        function(value) GetRule().style.healthColorEnabled = value; Changed() end)
    y = y - h
    _, h = W:ColorPicker(parent, "Health-bar color", y,
        function()
            local color = GetRule().style.healthColor
            return color.r, color.g, color.b, 1
        end,
        function(r, g, b) GetRule().style.healthColor = { r = r, g = g, b = b }; Changed() end,
        false)
    y = y - h
    _, h = W:Slider(parent, "Nameplate size (%)", y, 50, 200, 5,
        function() return GetRule().style.scale or 100 end,
        function(value) GetRule().style.scale = value; Changed() end,
        "Scales the whole nameplate. 100% uses EUI's normal size.")
    y = y - h
    _, h = W:Slider(parent, "Opacity (%)", y, 0, 100, 5,
        function() return GetRule().style.opacity or 100 end,
        function(value) GetRule().style.opacity = value; Changed() end,
        "Multiplies the nameplate's current EUI opacity by this value.")
    y = y - h
    _, h = W:Slider(parent, "Border size", y, 0, 8, 1,
        function() return GetRule().style.borderSize or 0 end,
        function(value) GetRule().style.borderSize = value; Changed() end,
        "Adds a simple colored outline around the health bar. Set to 0 to hide it.")
    y = y - h
    _, h = W:ColorPicker(parent, "Border color", y,
        function()
            local color = GetRule().style.borderColor
            return color.r, color.g, color.b, 1
        end,
        function(r, g, b) GetRule().style.borderColor = { r = r, g = g, b = b }; Changed() end,
        false)
    y = y - h
    _, h = W:Dropdown(parent, "Health-bar texture", y, TEXTURES,
        function() return GetRule().style.texture or "eui" end,
        function(value) GetRule().style.texture = value; Changed() end,
        TEXTURE_ORDER,
        "Choose the normal EUI texture, a flat fill, or Blizzard's standard status-bar texture.")
    y = y - h

    return math.abs(y)
end

local function BuildAboutPage(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    _, h = W:SectionHeader(parent, "HOW RULES WORK", y); y = y - h
    _, h = W:Toggle(parent, "Enable rule styling", y,
        function() return DB().enabled ~= false end,
        function(value) DB().enabled = value; Changed() end,
        "Turn off all rules without deleting them.")
    y = y - h
    _, h = W:SectionHeader(parent, "DETECTION", y); y = y - h
    _, h = W:SectionHeader(parent, "CONDITIONS AND PRIORITY", y); y = y - h
    _, h = W:Button(parent, "Open Nameplate Style Rules", y, function()
        EllesmereUI.OpenPlugin(PLUGIN_ID, "Styles", "Rules")
    end); y = y - h
    return math.abs(y)
end

local function Register()
    if not (EllesmereUI and EllesmereUI.RegisterPlugin) then return end
    if EllesmereUI.IsPluginRegistered(PLUGIN_ID) then return end
    EllesmereUI.RegisterPlugin(PLUGIN_ID, {
        label = "Nameplate Styles",
        modules = {
            {
                key = "Styles",
                title = "Rule Styling",
                description = "Style nameplates from unit, target, cast and rank conditions.",
                pages = { "Rules", "About" },
                buildPage = function(pageName, parent, yOffset)
                    if pageName == "About" then return BuildAboutPage(parent, yOffset) end
                    return BuildRulesPage(parent, yOffset)
                end,
                onReset = function()
                    local db = DB()
                    db.rules = {}
                    for index, rule in ipairs(addon.DefaultRules) do db.rules[index] = CopyRule(rule) end
                    db.selectedRule = 1
                    db.enabled = true
                    addon.Refresh()
                end,
            },
        },
    })
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    Register()
end)
