local addon = EllesmereUINameplateExtras and EllesmereUINameplateExtras
if not addon then return end

local PLUGIN_ID = "EllesmereUINameplateExtras"
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
    empowered = "Empowered cast", interruptible = "Interruptible cast", interruptOnCD = "Interrupt on CD", uninterruptible = "Uninterruptible cast",
}
local CAST_ORDER = { "any", "none", "casting", "channel", "empowered", "interruptible", "interruptOnCD", "uninterruptible" }
local SCHOOLS = { any = "Any spell school", physical = "Physical", holy = "Holy", fire = "Fire", nature = "Nature", frost = "Frost", shadow = "Shadow", arcane = "Arcane", mixed = "Mixed" }
local SCHOOL_ORDER = { "any", "physical", "holy", "fire", "nature", "frost", "shadow", "arcane", "mixed" }

local CUSTOM_CAST_STATES = { interruptible = true, interruptOnCD = true, uninterruptible = true }
local CUSTOM_CAST_STYLE_TIP = "Enable EUI or Classic WoW UI nameplate style and reload the UI to use this cast-color state."
local function CustomNameplateStyleEnabled()
    local np = _G.EllesmereNameplates_NS
    if not np then return false end
    -- Use the latched rendering style, not a profile change awaiting reload.
    if type(np.NP_Style) == "function" then
        local style = np.NP_Style()
        return style == "eui" or style == "classic"
    end
    if type(np._npStyle) == "string" then return np._npStyle == "eui" or np._npStyle == "classic" end
    local profile = np.db and np.db.profile
    -- Classic takes precedence if both flags are set, matching NP_Style.
    return not profile or profile.useClassicStyle == true or not profile.useBlizzardStyle
end

local function GetBarTextureOptions()
    local np = _G.EllesmereNameplates_NS
    local names = np and np.healthBarTextureNames or {}
    local order = np and np.healthBarTextureOrder or {}
    local paths = np and np.healthBarTextures or {}
    local values = { eui = "Use EUI texture", flat = "Flat" }
    local keys = { "eui", "flat", "---" }
    local seen = { eui = true, flat = true }
    for _, key in ipairs(order) do
        if key == "---" then
            if keys[#keys] ~= "---" then keys[#keys + 1] = key end
        else
            if not seen[key] then
                values[key] = names[key] or key
                keys[#keys + 1] = key
                seen[key] = true
            end
        end
    end
    values._menuOpts = {
        itemHeight = 28,
        background = function(key) return paths[key] end,
    }
    return values, keys
end

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
    local key = EllesmereUI.GetPluginModuleKey(PLUGIN_ID, "NameplateStyle")
    if key then EllesmereUI:InvalidateModulePageCache(key) end
    EllesmereUI:RefreshPage(true)
end

local function ExportRuleSet()
    local code, err = addon.ExportRuleSet()
    if not code then
        EllesmereUI.PrintError(err or "Could not export Nameplate Extras rules.")
        return
    end
    EllesmereUI:ShowCopyPopup("Export Nameplate Rules", "Copy this code to share the rule set between characters.", code)
end

local function ImportRuleSet()
    local function OnImport(code)
        local ok, err = addon.ImportRuleSet(code)
        if not ok then
            EllesmereUI.PrintError(err or "Could not import Nameplate Extras rules.")
            return
        end
        Rebuild()
        EllesmereUI.Print("Nameplate Extras rules imported.")
    end
    if EllesmereUI.ShowImportStringPopup then
        EllesmereUI:ShowImportStringPopup(
            "Import Nameplate Rules",
            "Paste a rule-set code from another character. Import replaces this profile's current rules.",
            "Import Rules", OnImport)
    elseif EllesmereUI.ShowInputPopup then
        -- Older EUI builds do not yet include the scrollable import/export-style
        -- popup. Keep import usable there with the standard one-line code field.
        EllesmereUI:ShowInputPopup({
            title = "Import Nameplate Rules",
            message = "Paste the complete rule-set code. Import replaces this profile's current rules.",
            placeholder = "Paste rule-set code here...",
            confirmText = "Import Rules",
            cancelText = "Cancel",
            maxLetters = addon.RuleSetMaxCodeLength or 64000,
            onConfirm = OnImport,
        })
    else
        EllesmereUI.PrintError("Update EllesmereUI to import Nameplate Extras rule sets.")
    end
end

local function ProfilePrompt(title, initialText, confirmText, submit)
    EllesmereUI:ShowInputPopup({
        title = title,
        message = title:find("^Create")
            and "New profiles start with the built-in default rules and settings. Profiles are shared by name across characters. Use 1-32 characters."
            or "Profiles are shared by name across characters. Use 1-32 characters.",
        placeholder = "Enter profile name...",
        initialText = initialText or "",
        maxLetters = 32,
        confirmText = confirmText,
        cancelText = "Cancel",
        onConfirm = function(name)
            local ok, err = submit(name)
            if not ok then
                EllesmereUI.PrintError(err or "Could not update Nameplate Extras profiles.")
                return
            end
            Changed()
            Rebuild()
        end,
    })
end

local function BuildProfilesPage(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    local info = addon.GetProfileInfo()
    _, h = W:SectionHeader(parent, "CHARACTER PROFILE - " .. info.character, y); y = y - h

    local values, order = {}, {}
    for _, name in ipairs(info.names) do
        values[name] = name
        order[#order + 1] = name
    end
    _, h = W:Dropdown(parent, "Profile for this character", y, values,
        function() return addon.GetProfileInfo().active end,
        function(name)
            local ok, err = addon.SelectProfile(name)
            if not ok then EllesmereUI.PrintError(err or "Could not select profile."); return end
            Changed()
            Rebuild()
        end, order,
        "Each character chooses a profile. Default is shared by characters that have not selected another profile; assigning the same named profile to multiple characters shares those rules.")
    y = y - h

        _, h = W:SectionHeader(parent, "MANAGE PROFILES", y); y = y - h
        if info.active == "Default" then
        _, h = W:WideButton(parent, "Create Profile", y,
            function() ProfilePrompt("Create Nameplate Profile", nil, "Create", addon.CreateProfile) end, 420)
        y = y - h
        _, h = W:SectionHeader(parent, "DEFAULT IS SHARED AND CANNOT BE RENAMED OR DELETED", y); y = y - h
    else
        _, h = W:WideDualButton(parent, "Create Profile", "Rename Profile", y,
            function() ProfilePrompt("Create Nameplate Profile", nil, "Create", addon.CreateProfile) end,
            function() ProfilePrompt("Rename Nameplate Profile", info.active, "Rename", addon.RenameProfile) end,
            210)
        y = y - h
        _, h = W:WideButton(parent, "Delete Active Profile", y, function()
            EllesmereUI:ShowConfirmPopup({
                title = "Delete Nameplate Profile?",
                message = ("Delete '%s'? Characters using it will switch to Default."):format(info.active),
                confirmText = "Delete Profile",
                cancelText = "Cancel",
                onConfirm = function()
                    local ok, err = addon.DeleteProfile()
                    if not ok then EllesmereUI.PrintError(err or "Could not delete profile."); return end
                    Changed()
                    Rebuild()
                end,
            })
        end, 420)
        y = y - h
    end

    return math.abs(y)
end

local function BuildSharingPage(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    _, h = W:SectionHeader(parent, "SHARE THIS PROFILE'S RULES", y); y = y - h
    _, h = W:SectionHeader(parent,
        "Export creates a copyable code. Import replaces the rules in the selected character profile.", y)
    y = y - h
    _, h = W:WideDualButton(parent, "Export Rule Set", "Import Rule Set", y,
        ExportRuleSet, ImportRuleSet, 230)
    y = y - h
    return math.abs(y)
end

local function NewRule(index)
    return {
        name = "Custom Rule " .. index,
        enabled = true,
        conditions = { unitType = {}, reaction = {}, classification = {}, target = { yes = true }, castState = {}, spellSchool = {} },
        style = { healthColorEnabled = true, healthColor = { r = 1, g = 0.72, b = 0.15 }, scale = 100, opacity = 100, borderSize = 2, borderColor = { r = 1, g = 0.72, b = 0.15 }, texture = "eui" },
    }
end

local function BuildRulesPage(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    local db = DB()
    local rule, selected = GetRule()
    local barTextureValues, barTextureOrder = GetBarTextureOptions()

    -- Search stores exact section names on first indexing. Keep them stable;
    -- the selector and name field below show the current rule's context.
    _, h = W:SectionHeader(parent, "RULE ORDER", y)
    y = y - h
    local labels, order = {}, {}
    for i, item in ipairs(db.rules) do
        local key = tostring(i)
        labels[key] = ("%d of %d - %s%s"):format(i, #db.rules,
            item.enabled == false and "Off - " or "", item.name or ("Rule " .. i))
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
    -- Supported composites stay together when inline search reflows tagged rows.
    _, h = W:WideTripleButton(parent, "Add Rule", "Copy Rule", "Delete Rule", y, function()
        local current = DB()
        if #current.rules >= MAX_RULES then return end
        table.insert(current.rules, 1, NewRule(#current.rules + 1))
        current.selectedRule = 1
        Rebuild()
        Changed()
    end, function()
        local current = DB()
        if #current.rules >= MAX_RULES then return end
        local index = current.selectedRule
        local source = current.rules[index]
        if not source then return end
        local copy = CopyRule(source)
        local baseName = source.name or ("Rule " .. index)
        local name = baseName .. " Copy"
        local suffix = 2
        local used = {}
        for _, item in ipairs(current.rules) do used[item.name] = true end
        while used[name] do
            name = baseName .. " Copy " .. suffix
            suffix = suffix + 1
        end
        copy.name = name
        table.insert(current.rules, index + 1, copy)
        current.selectedRule = index + 1
        Rebuild()
        Changed()
    end, function()
        local current = DB()
        if #current.rules <= 1 then return end
        local rule = current.rules[current.selectedRule]
        if not rule then return end
        if not EllesmereUI.ShowConfirmPopup then
            EllesmereUI.PrintError("This EUI version does not provide rule-delete confirmation.")
            return
        end
        EllesmereUI:ShowConfirmPopup({
            title = "Delete Nameplate Rule?",
            message = ("Delete '%s'? This cannot be undone."):format(rule.name or "Unnamed Rule"),
            confirmText = "Delete Rule",
            cancelText = "Keep Rule",
            onConfirm = function()
                -- A popup can remain open while the user changes character profiles
                -- or edits rules. Delete only the rule that opened this dialog.
                local latest = DB()
                if latest ~= current or #latest.rules <= 1 then return end
                local index
                for i, candidate in ipairs(latest.rules) do
                    if candidate == rule then index = i; break end
                end
                if not index then return end
                table.remove(latest.rules, index)
                latest.selectedRule = math.min(index, #latest.rules)
                Rebuild()
                Changed()
            end,
        })
    end, 205)
    y = y - h
    _, h = W:WideDualButton(parent, "Move Rule Up", "Move Rule Down", y, function()
        local current = DB()
        local index = current.selectedRule
        if index <= 1 then return end
        current.rules[index], current.rules[index - 1] = current.rules[index - 1], current.rules[index]
        current.selectedRule = index - 1
        Rebuild()
        Changed()
    end, function()
        local current = DB()
        local index = current.selectedRule
        if index >= #current.rules then return end
        current.rules[index], current.rules[index + 1] = current.rules[index + 1], current.rules[index]
        current.selectedRule = index + 1
        Rebuild()
        Changed()
    end, 205)
    y = y - h

    _, h = W:SectionHeader(parent, "MATCH CONDITIONS", y); y = y - h
    _, h = W:Toggle(parent, "Rule enabled", y,
        function() return GetRule().enabled ~= false end,
        function(value) GetRule().enabled = value; Rebuild(); Changed() end)
    y = y - h

    local function ConditionMultiDropdown(label, key, values, keys, tooltip)
        local items = {}
        for _, value in ipairs(keys) do
            if value ~= "any" then
                local item = { key = value, label = values[value] }
                if key == "castState" and CUSTOM_CAST_STATES[value] then
                    item.lockedFn = function() return not CustomNameplateStyleEnabled() end
                    item.lockedTooltip = CUSTOM_CAST_STYLE_TIP
                end
                items[#items + 1] = item
            end
        end
        local function GetSelection()
            local value = GetRule().conditions[key]
            if type(value) == "table" then return value end
            if type(value) == "string" and value ~= "any" then return { [value] = true } end
            return {}
        end
        return {
            text = label,
            tooltip = tooltip,
            items = items,
            emptyLabel = values.any,
            getSelected = function(option) return GetSelection()[option] == true end,
            setSelected = function(option, selected)
                if key == "castState" and CUSTOM_CAST_STATES[option] and not CustomNameplateStyleEnabled() then return end
                local current = GetRule()
                local value = GetSelection()
                current.conditions[key] = value
                value[option] = selected and true or nil
                if key == "castState" and selected and
                    (option == "empowered" or option == "interruptible" or option == "interruptOnCD" or option == "uninterruptible") then
                    -- A subtype does not expose the broad Casting checkbox as
                    -- selected. Selecting Casting explicitly afterward means all.
                    value.casting = nil
                end
                Changed()
            end,
        }
    end
    local function BuildConditionMultiDropdown(region, condition)
        local PP = EllesmereUI.PanelPP
        local label = EllesmereUI.MakeFont(region, 14, nil, 1, 1, 1)
        PP.Point(label, "LEFT", region, "LEFT", 20, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetMaxLines(1)
        label:SetText(EllesmereUI.L(condition.text))

        local ddBtn, refresh = EllesmereUI.BuildVisOptsCBDropdown(
            region, 170, region:GetFrameLevel() + 2, condition.items,
            condition.getSelected, condition.setSelected, nil, nil, nil, nil, nil,
            { emptyLabel = condition.emptyLabel, label = condition.text })
        PP.Point(ddBtn, "RIGHT", region, "RIGHT", -20, 0)
        EllesmereUI.RegisterWidgetRefresh(refresh)

        if condition.tooltip then
            local hitFrame = CreateFrame("Frame", nil, region)
            hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
            hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
            hitFrame:SetFrameLevel(region:GetFrameLevel() + 10)
            hitFrame:EnableMouse(true)
            hitFrame:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(label, condition.tooltip)
            end)
            hitFrame:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            hitFrame:SetMouseClickEnabled(false)
        end
    end
    local conditions = {
        ConditionMultiDropdown("Unit type", "unitType", UNIT_TYPES, UNIT_ORDER,
            "Matches any selected unit type. Any creature includes NPCs and player-controlled pets."),
        ConditionMultiDropdown("Reaction", "reaction", REACTIONS, REACTION_ORDER),
        ConditionMultiDropdown("Classification", "classification", CLASSIFICATIONS, CLASSIFICATION_ORDER,
            "Matches any selected game classification: normal, elite, rare, rare elite, boss, or minor."),
        ConditionMultiDropdown("Target state", "target", TARGETS, TARGET_ORDER),
        ConditionMultiDropdown("Cast state", "castState", CAST_STATES, CAST_ORDER,
            "Casting matches all active casts. Interruptible cast, Interrupt on CD, and Uninterruptible cast target EUI's three color states. For custom cast color, the first matching rule per state wins and secret-safe rendering selects the displayed state; unselected states keep EUI's colors. Casting need not be checked. Other effects require a readable matching state. Cast choices combine with OR."),
        ConditionMultiDropdown("Spell school", "spellSchool", SCHOOLS, SCHOOL_ORDER,
            "Learns spell schools from combat-log cast starts while a school rule is enabled. Unknown spells do not match a specific school."),
    }
    for index = 1, #conditions, 2 do
        local left, right = conditions[index], conditions[index + 1]
        -- Use spacer slots for the row shell, then attach the shared checkbox
        -- dropdowns directly. This works with installed row factories that
        -- predate custom checkbox-dropdown row types.
        local row, rowHeight = W:DualRow(parent, y,
            { type = "spacer", text = left.text, tooltip = left.tooltip },
            right and { type = "spacer", text = right.text, tooltip = right.tooltip } or nil)
        -- The search factory returns absorbers, whose regions are not native
        -- UI parents. DualRow above still indexes both labels and tooltips.
        if not EllesmereUI.IsSearchPrebuild() then
            BuildConditionMultiDropdown(row._leftRegion, left)
            if right then BuildConditionMultiDropdown(row._rightRegion, right) end
        end
        y = y - rowHeight
    end
    _, h = W:Toggle(parent, "Quest Objective", y,
        function() return GetRule().conditions.questObjective == "yes" end,
        function(value)
            GetRule().conditions.questObjective = value and "yes" or "any"
            Changed()
        end,
        "When on, matches only units shown as incomplete objectives in your own quest log. Uses EUI's quest detector and follows its Show In Instances setting. When off, quest status does not restrict this rule.")
    y = y - h
    _, h = W:SectionHeader(parent, "APPEARANCE - NAMEPLATE", y); y = y - h
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
    _, h = W:SectionHeader(parent, "APPEARANCE - HEALTH BAR", y); y = y - h
    _, h = W:Toggle(parent, "Override health bar", y,
        function() return GetRule().style.healthEnabled ~= false end,
        function(value) GetRule().style.healthEnabled = value; Changed(); Rebuild() end,
        "Apply the health-bar settings below when this rule wins. Off restores EUI color and texture and hides the additional border. Nameplate size, opacity and cast overrides remain independent.")
    y = y - h
    local function HealthOff() return GetRule().style.healthEnabled == false end
    local function HealthBorderOff()
        local style = GetRule().style
        return HealthOff() or style.borderEnabled == false or (style.borderSize or 0) <= 0
    end
    _, h = W:DualRow(parent, y, {
        type = "toggle", text = "Custom health color", disabled = HealthOff,
        disabledTooltip = "Enable Override health bar first.",
        getValue = function() return GetRule().style.healthColorEnabled ~= false end,
        setValue = function(value) GetRule().style.healthColorEnabled = value; Changed(); Rebuild() end,
    }, {
        type = "colorpicker", text = "Health-bar color", hasAlpha = false,
        disabled = function() return HealthOff() or GetRule().style.healthColorEnabled == false end,
        disabledTooltip = "Enable Custom health color first.",
        getValue = function()
            local color = GetRule().style.healthColor
            return color.r, color.g, color.b, 1
        end,
        setValue = function(r, g, b) GetRule().style.healthColor = { r = r, g = g, b = b }; Changed() end,
    }); y = y - h
    _, h = W:DualRow(parent, y, {
        type = "dropdown", text = "Health-bar texture", values = barTextureValues, order = barTextureOrder,
        disabled = HealthOff, disabledTooltip = "Enable Override health bar first.",
        tooltip = "Use EUI texture restores the current EUI texture. Choose Flat or Blizzard to override it.",
        getValue = function() return GetRule().style.texture or "eui" end,
        setValue = function(value) GetRule().style.texture = value; Changed() end,
    }, nil); y = y - h
    _, h = W:DualRow(parent, y, {
        type = "toggle", text = "Additional health border", disabled = HealthOff,
        disabledTooltip = "Enable Override health bar first.",
        getValue = function()
            local style = GetRule().style
            return style.borderEnabled ~= false and (style.borderSize or 0) > 0
        end,
        setValue = function(value)
            local style = GetRule().style
            style.borderEnabled = value
            if value and (style.borderSize or 0) <= 0 then style.borderSize = 2 end
            Changed(); Rebuild()
        end,
    }, {
        type = "colorpicker", text = "Health border color", hasAlpha = false,
        disabled = HealthBorderOff, disabledTooltip = "Enable Additional health border first.",
        getValue = function()
            local color = GetRule().style.borderColor
            return color.r, color.g, color.b, 1
        end,
        setValue = function(r, g, b) GetRule().style.borderColor = { r = r, g = g, b = b }; Changed() end,
    }); y = y - h
    _, h = W:DualRow(parent, y, {
        type = "slider", text = "Health border size", min = 1, max = 8, step = 1,
        disabled = HealthBorderOff, disabledTooltip = "Enable Additional health border first.",
        tooltip = "Thickness of the additional health-bar outline. Turning the border off keeps this value and its color for later.",
        getValue = function() return math.max(1, GetRule().style.borderSize or 2) end,
        setValue = function(value) GetRule().style.borderSize = value; Changed() end,
    }, nil); y = y - h

    _, h = W:SectionHeader(parent, "APPEARANCE - CAST BAR", y); y = y - h
    _, h = W:Toggle(parent, "Override cast bar", y,
        function() return GetRule().style.castEnabled == true end,
        function(value) GetRule().style.castEnabled = value; Changed(); Rebuild() end,
        "Apply the cast settings below when this rule wins. Off restores EUI styling. Only affects nameplates with an EUI cast bar; friendly plates currently have none.")
    y = y - h
    local defaults = addon.CastStyleDefaults
    local function CastOff() return GetRule().style.castEnabled ~= true end
    local function CastToggle(text, key)
        return {
            type = "toggle", text = text, disabled = CastOff,
            disabledTooltip = "Enable Override cast bar first.",
            getValue = function() return GetRule().style[key] == true end,
            setValue = function(value) GetRule().style[key] = value; Changed(); Rebuild() end,
        }
    end
    local function CastColor(text, key, enabledKey)
        return {
            type = "colorpicker", text = text, hasAlpha = false,
            disabled = function() return CastOff() or GetRule().style[enabledKey] ~= true end,
            disabledTooltip = "Enable the matching cast override to edit this color.",
            getValue = function()
                local color = GetRule().style[key] or defaults[key]
                return color.r, color.g, color.b, 1
            end,
            setValue = function(r, g, b) GetRule().style[key] = { r = r, g = g, b = b }; Changed() end,
        }
    end
    local colorToggle = CastToggle("Custom cast color", "castColorEnabled")
    colorToggle.tooltip = "Overrides the selected EUI cast-color states: Interruptible cast (interrupt available), Interrupt on CD, or Uninterruptible cast. Rules are prioritized separately per color state, so separate rules can supply different colors. Explicit Casting overrides all three. Interrupted flashes, shield visibility and kick-ready indicators are preserved."
    _, h = W:DualRow(parent, y, colorToggle,
        CastColor("Cast fill color", "castColor", "castColorEnabled")); y = y - h
    _, h = W:DualRow(parent, y, {
        type = "dropdown", text = "Cast-bar texture", values = barTextureValues, order = barTextureOrder,
        disabled = CastOff, disabledTooltip = "Enable Override cast bar first.",
        tooltip = "Use EUI texture leaves the current texture unchanged. Flat and Blizzard apply to EUI and Classic styles; stock Blizzard-style cast artwork retains its atlas.",
        getValue = function() return GetRule().style.castTexture or "eui" end,
        setValue = function(value) GetRule().style.castTexture = value; Changed() end,
    }, nil); y = y - h
    _, h = W:DualRow(parent, y, CastToggle("Custom cast opacity", "castOpacityEnabled"), {
        type = "slider", text = "Cast opacity (%)", min = 0, max = 100, step = 5,
        disabled = function() return CastOff() or GetRule().style.castOpacityEnabled ~= true end,
        disabledTooltip = "Enable Custom cast opacity first.",
        tooltip = "Fades the cast bar and its child elements. This also works when EUI lifts casts in front of nameplates.",
        getValue = function() return GetRule().style.castOpacity or defaults.castOpacity end,
        setValue = function(value) GetRule().style.castOpacity = value; Changed() end,
    }); y = y - h
    _, h = W:DualRow(parent, y, CastToggle("Additional cast border", "castBorderEnabled"),
        CastColor("Cast border color", "castBorderColor", "castBorderEnabled")); y = y - h
    _, h = W:DualRow(parent, y, {
        type = "slider", text = "Cast border size", min = 1, max = 8, step = 1,
        disabled = function() return CastOff() or GetRule().style.castBorderEnabled ~= true end,
        disabledTooltip = "Enable Additional cast border first.",
        tooltip = "Adds an outline outside the cast bar without replacing EUI's border or icon separator.",
        getValue = function() return GetRule().style.castBorderSize or defaults.castBorderSize end,
        setValue = function(value) GetRule().style.castBorderSize = value; Changed() end,
    }, nil); y = y - h

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
        EllesmereUI.OpenPlugin(PLUGIN_ID, "NameplateStyle", "Rules")
    end); y = y - h
    return math.abs(y)
end

local function Register()
    if not (EllesmereUI and type(EllesmereUI.RegisterPlugin) == "function"
        and type(EllesmereUI.IsPluginRegistered) == "function") then
        addon.pluginRegistrationError = "This EllesmereUI build does not expose the plugin registration API"
        return false
    end
    if EllesmereUI.IsPluginRegistered(PLUGIN_ID) then
        addon.pluginRegistered = true
        return true
    end
    local ok, registered = pcall(EllesmereUI.RegisterPlugin, PLUGIN_ID, {
        label = "Nameplate Extras",
        modules = {
            {
                key = "NameplateStyle",
                title = "Nameplate Style",
                description = "Rule-based nameplate styling by unit, target, cast and rank.",
                pages = { "Rules", "Profiles", "Sharing", "About" },
                buildPage = function(pageName, parent, yOffset)
                    if pageName == "Profiles" then return BuildProfilesPage(parent, yOffset) end
                    if pageName == "Sharing" then return BuildSharingPage(parent, yOffset) end
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
    addon.pluginRegistered = ok and registered == true
    addon.pluginRegistrationError = addon.pluginRegistered and nil
        or (ok and "EllesmereUI rejected the plugin specification" or tostring(registered))
    return addon.pluginRegistered
end

-- Register immediately after EUI's hard dependency has loaded. Retry at login
-- and on addon loads in case an older/LoD EUI load order exposes the API later.
addon.RegisterOptions = Register
if not Register() then
    local retry = CreateFrame("Frame")
    retry:RegisterEvent("ADDON_LOADED")
    retry:RegisterEvent("PLAYER_LOGIN")
    retry:SetScript("OnEvent", function(self)
        if Register() then
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
        end
    end)
end
