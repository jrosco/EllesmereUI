local addon = EllesmereUIExtendNameplates
if not addon then return end

local PLUGIN_ID = "EllesmereUIExtendNameplates"
local MAX_RULES = addon.MaxRules or 12
local rulesHeaderBuilder, rulesPreview

local UNIT_TYPES = { any = "Any unit", player = "Player", npc = "NPC", pet = "Player-controlled pet", creature = "Any creature" }
local UNIT_ORDER = { "any", "player", "npc", "pet", "creature" }
local REACTIONS = { any = "Any reaction", enemy = "Enemy", friendly = "Friendly", neutral = "Neutral" }
local REACTION_ORDER = { "any", "enemy", "friendly", "neutral" }
local CLASSIFICATIONS = { any = "Any rank", normal = "Normal", elite = "Elite", rare = "Rare", rareelite = "Rare Elite", boss = "Boss", minus = "Minor" }
local CLASSIFICATION_ORDER = { "any", "normal", "elite", "rare", "rareelite", "boss", "minus" }
local TARGETS = { any = "Any target state", yes = "Current target", no = "Not current target", none = "No target selected" }
local TARGET_ORDER = { "any", "yes", "no", "none" }
local THREATS = { any = "Any threat", nonTank = "Non-tank threat", tank = "Tank threat", me = "Threat on me" }
local THREAT_ORDER = { "any", "nonTank", "tank", "me" }
local PLAYER_COMBAT = { any = "Any combat state", inCombat = "In combat", outOfCombat = "Out of combat" }
local PLAYER_COMBAT_ORDER = { "any", "inCombat", "outOfCombat" }
local INSTANCES = { any = "Any instance type", world = "Open world", dungeon = "Dungeon", raid = "Raid",
    battleground = "Battleground", arena = "Arena", scenario = "Scenario", delve = "Delve" }
local INSTANCE_ORDER = { "any", "world", "dungeon", "raid", "battleground", "arena", "scenario", "delve" }
local THREAT_TIPS = {
    nonTank = "Matches when a non-tank (Damage or Healer role) holds this unit's aggro.",
    tank = "Matches when a tank holds this unit's aggro.",
    me = "Matches when you hold this unit's aggro, regardless of your role.",
}
local CAST_STATES = {
    any = "Any cast state", none = "Not casting", casting = "Casting", channel = "Channeling",
    empowered = "Empowered cast", interruptible = "Interruptible cast", interruptOnCD = "Interrupt on CD", uninterruptible = "Uninterruptible cast",
}
local CAST_ORDER = { "any", "none", "casting", "channel", "empowered", "interruptible", "interruptOnCD", "uninterruptible" }
local SCHOOLS = { any = "Any spell school", physical = "Physical", holy = "Holy", fire = "Fire", nature = "Nature", frost = "Frost", shadow = "Shadow", arcane = "Arcane", mixed = "Mixed" }
local SCHOOL_ORDER = { "any", "physical", "holy", "fire", "nature", "frost", "shadow", "arcane", "mixed" }

local CUSTOM_CAST_STATES = { interruptible = true, interruptOnCD = true, uninterruptible = true }
local CUSTOM_CAST_STYLE_TIP = "Enable EUI or Classic WoW UI nameplate style and reload the UI to use this cast-color state."
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
        EllesmereUI.PrintError(err or "Could not export Extend Nameplates rules.")
        return
    end
    EllesmereUI:ShowCopyPopup("Export Nameplate Rules", "Copy this code to share the rule set between characters.", code)
end

local function ImportRuleSet()
    local function OnImport(code)
        local ok, err = addon.ImportRuleSet(code)
        if not ok then
            EllesmereUI.PrintError(err or "Could not import Extend Nameplates rules.")
            return
        end
        Rebuild()
        EllesmereUI.Print("Extend Nameplates rules imported.")
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
        EllesmereUI.PrintError("Update EllesmereUI to import Extend Nameplates rule sets.")
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
                EllesmereUI.PrintError(err or "Could not update Extend Nameplates profiles.")
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
    local borderTextureValues, borderTextureOrder = addon.GetBorderStyleOptions()
    local glowValues, glowOrder = addon.GetRuleGlowOptions()
    local previewUpdates, notifyChanged = {}, Changed
    local function Changed()
        notifyChanged()
        for _, update in ipairs(previewUpdates) do update() end
    end

    local function GlobalLocked() return DB().enabled == false end
    local function RuleLocked()
        return GlobalLocked() or rule.enabled == false or GetRule().enabled == false
    end
    local function LockTip()
        if GlobalLocked() then return "Enable rule styling to edit rules." end
        return "Enable this rule to edit its settings."
    end
    local function LockConfig(cfg, scope)
        if not cfg or cfg.type == "spacer" then return cfg end
        local locked = scope == "global" and GlobalLocked or RuleLocked
        local disabled, disabledTip, setValue = cfg.disabled, cfg.disabledTooltip, cfg.setValue
        cfg.disabled = function() return locked() or (disabled and disabled()) or false end
        cfg.disabledTooltip = function()
            if locked() then return LockTip() end
            if type(disabledTip) == "function" then return disabledTip() end
            return disabledTip
        end
        if setValue then
            cfg.setValue = function(...)
                if cfg.disabled() then return end
                return setValue(...)
            end
        end
        return cfg
    end
    local function LockedRow(left, right, leftScope, rightScope)
        return W:DualRow(parent, y, LockConfig(left, leftScope), LockConfig(right, rightScope))
    end
    local function AttachLock(control, locked, tip, label)
        local block = CreateFrame("Frame", nil, control:GetParent())
        block:SetAllPoints(control)
        block:SetFrameLevel(control:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(control, tip()) end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function Update()
            local off = locked()
            control:SetAlpha(off and 0.3 or 1)
            control:EnableMouse(not off)
            if label then label:SetAlpha(off and 0.3 or 1) end
            if off then block:Show() else block:Hide() end
        end
        EllesmereUI.RegisterWidgetRefresh(Update)
        Update()
    end

    if not EllesmereUI.IsSearchPrebuild() and EllesmereUI.SetContentHeader then
        rulesHeaderBuilder = function(headerParent, headerWidth)
            local height, preview = addon.BuildRulePreview(headerParent, headerWidth, GetRule,
                function() return GlobalLocked() or GetRule().enabled == false end)
            if preview then
                rulesPreview = preview
                previewUpdates[#previewUpdates + 1] = preview.Update
                EllesmereUI.RegisterWidgetRefresh(preview.Update)
            end
            return height
        end
        EllesmereUI:SetContentHeader(rulesHeaderBuilder)
    end

    local function GlowRow(prefix, off, barTip)
        local title = prefix == "health" and "Health" or "Cast"
        local function Locked()
            return RuleLocked() or DB() ~= db or GetRule() ~= rule or off() or not addon.SupportsRuleGlows()
        end
        local function Tip()
            if RuleLocked() then return LockTip() end
            if not addon.SupportsRuleGlows() then return "Update EllesmereUI to use its shared glow engine." end
            return barTip
        end
        local function NoGlow()
            local value = rule.style[prefix .. "GlowStyle"] or 0
            return Locked() or value == 0 or not addon.ValidateRuleGlowStyle(value)
        end
        local row, height = LockedRow({ type = "dropdown", text = title .. " border glow", values = glowValues, order = glowOrder,
            disabled = Locked, disabledTooltip = Tip,
            getValue = function()
                local value = GetRule().style[prefix .. "GlowStyle"] or 0
                return addon.ValidateRuleGlowStyle(value) and value or 0
            end,
            setValue = function(value)
                value = tonumber(value) or 0
                if not addon.ValidateRuleGlowStyle(value) then return end
                GetRule().style[prefix .. "GlowStyle"] = value; Changed(); Rebuild()
            end,
            tooltip = "Animated bar glow alongside the existing border, using this rule's match conditions. The cog edits Pixel Glow parameters or Auto-Cast Shine sparkle size. A plugin cast glow temporarily suppresses EUI's Important Cast Glow. Under restricted Retail visibility, Auto-Cast Shine uses native Pixel Glow instead.",
        }, { type = "colorpicker", text = title .. " glow color", hasAlpha = false,
            disabled = NoGlow, disabledTooltip = "Choose a border glow first.",
            getValue = function()
                local c = addon.GetRuleGlowColor(GetRule().style, prefix)
                return c.r, c.g, c.b, 1
            end,
            setValue = function(r, g, b) GetRule().style[prefix .. "GlowColor"] = { r = r, g = g, b = b }; Changed() end,
        })
        if not EllesmereUI.IsSearchPrebuild() and EllesmereUI.BuildInlineCog then
            local function NotPixel() return Locked() or rule.style[prefix .. "GlowStyle"] ~= 1 end
            local function NotShine() return Locked() or rule.style[prefix .. "GlowStyle"] ~= 3 end
            local function Set(key, value, shine)
                if (shine and NotShine()) or (not shine and NotPixel()) then return end
                rule.style[prefix .. key] = value
                Changed()
            end
            EllesmereUI.BuildInlineCog(row._leftRegion, {
                title = title .. " glow settings", captureRegion = row._leftRegion,
                disabled = function() return Locked() or (NotPixel() and NotShine()) end,
                disabledTooltip = function() return Locked() and Tip() or "Choose Pixel Glow or Auto-Cast Shine to edit its settings." end,
                rows = rule.style[prefix .. "GlowStyle"] == 3 and {
                    { type = "slider", label = "Sparkle size (%)", min = 50, max = 200, step = 5,
                        disabled = NotShine, disabledTooltip = "Choose Auto-Cast Shine first.",
                        tooltip = "Changes the size of the individual sparkles, not the bar, orbit speed or sparkle count. 100% is EUI's normal size.",
                        get = function() return rule.style[prefix .. "GlowShineSize"] or 100 end,
                        set = function(value) Set("GlowShineSize", value, true) end },
                } or {
                    { type = "slider", label = "Lines", min = 2, max = 16, step = 1, disabled = NotPixel,
                        disabledTooltip = "Choose Pixel Glow to edit its parameters.",
                        get = function() return rule.style[prefix .. "GlowLines"] or 8 end,
                        set = function(value) Set("GlowLines", value) end },
                    { type = "slider", label = "Thickness", min = 1, max = 4, step = 1, disabled = NotPixel,
                        disabledTooltip = "Choose Pixel Glow to edit its parameters.",
                        get = function() return rule.style[prefix .. "GlowThickness"] or 2 end,
                        set = function(value) Set("GlowThickness", value) end },
                    { type = "slider", label = "Speed", min = 1, max = 8, step = 1, disabled = NotPixel,
                        disabledTooltip = "Choose Pixel Glow to edit its parameters.",
                        get = function() return 9 - (rule.style[prefix .. "GlowSpeed"] or 4) end,
                        set = function(value) Set("GlowSpeed", 9 - value) end },
                    { type = "toggle", label = "Background", disabled = NotPixel,
                        disabledTooltip = "Choose Pixel Glow to edit its parameters.",
                        get = function() return rule.style[prefix .. "GlowBackground"] == true end,
                        set = function(value) Set("GlowBackground", value) end },
                    { type = "colorpicker", label = "Background Color",
                        disabled = function() return NotPixel() or rule.style[prefix .. "GlowBackground"] ~= true end,
                        disabledTooltip = "Enable Pixel Glow Background first.",
                        get = function()
                            local c = rule.style[prefix .. "GlowBackgroundColor"] or { r = 0, g = 0, b = 0 }
                            return c.r, c.g, c.b
                        end,
                        set = function(r, g, b)
                            if rule.style[prefix .. "GlowBackground"] ~= true then return end
                            Set("GlowBackgroundColor", { r = r, g = g, b = b })
                        end },
                },
            })
        end
        return height
    end

    _, h = W:SectionHeader(parent, "RULE STYLING", y); y = y - h
    _, h = W:Toggle(parent, "Enable rule styling", y,
        function() return DB().enabled ~= false end,
        function(value) DB().enabled = value; Changed(); Rebuild() end,
        "Enable or disable all rule styling in the active profile. Turning this off restores EUI appearance and locks the rule editor without deleting rules or changing their individual enabled settings.")
    y = y - h

    -- Search stores exact section names on first indexing. Keep them stable;
    -- the selector and name field below show the current rule's context.
    _, h = W:SectionHeader(parent, "RULE ORDER", y)
    y = y - h
    local labels, order = {}, {}
    for i, item in ipairs(db.rules) do
        local key = tostring(i)
        labels[key] = ("[%d] %s"):format(i, item.name or ("Rule " .. i))
        order[#order + 1] = key
    end
    _, h = LockedRow({
        type = "dropdown", text = "Edit rule", values = labels, order = order,
        getValue = function() return tostring(DB().selectedRule or 1) end,
        setValue = function(value)
            DB().selectedRule = tonumber(value) or 1
            Rebuild()
        end,
        tooltip = "Rules are checked from top to bottom; the first enabled match wins. New rules start enabled for your current target.",
    }, {
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
    }, "global"); y = y - h
    local actions = {}
    local function Action(text, onClick)
        local locked = text == "Add Rule" and GlobalLocked or RuleLocked
        actions[#actions + 1] = { text = text, locked = locked, onClick = function()
            if locked() then return end
            onClick()
        end }
    end
    Action("Add Rule", function()
        local current = DB()
        if #current.rules >= MAX_RULES then return end
        table.insert(current.rules, 1, NewRule(#current.rules + 1))
        current.selectedRule = 1
        Rebuild()
        Changed()
    end)
    Action("Copy Rule", function()
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
    end)
    Action("Delete Rule", function()
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
                if latest ~= current or GlobalLocked() or rule.enabled == false or #latest.rules <= 1 then return end
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
    end)
    Action("Move Rule Up", function()
        local current = DB()
        local index = current.selectedRule
        if index <= 1 then return end
        current.rules[index], current.rules[index - 1] = current.rules[index - 1], current.rules[index]
        current.selectedRule = index - 1
        Rebuild()
        Changed()
    end)
    Action("Move Rule Down", function()
        local current = DB()
        local index = current.selectedRule
        if index >= #current.rules then return end
        current.rules[index], current.rules[index + 1] = current.rules[index + 1], current.rules[index]
        current.selectedRule = index + 1
        Rebuild()
        Changed()
    end)
    if EllesmereUI.IsSearchPrebuild() then
        -- Index each action through the frameless factory without creating UI.
        for i, action in ipairs(actions) do
            local _, height = W:Button(parent, action.text, y, action.onClick)
            if i == 1 then h = height end
        end
    else
        -- One search/layout row owns all five controls, so search cannot split
        -- independently tagged wrappers into separate vertical positions.
        local row
        row, h = W:Button(parent, actions[1].text, y, actions[1].onClick)
        local PP, pad = EllesmereUI.PanelPP, EllesmereUI.CONTENT_PAD
        local width, gap = parent:GetWidth() - pad * 2, 8
        local buttonWidth = (width - gap * (#actions - 1)) / #actions
        PP.Size(row, width, h)
        PP.Point(row, "TOPLEFT", parent, "TOPLEFT", pad, y)
        local firstButton = row:GetChildren()
        local names, localizedNames = {}, {}
        for i, action in ipairs(actions) do
            names[i], localizedNames[i] = action.text, EllesmereUI.L(action.text)
            local button = firstButton
            if i > 1 then
                button = CreateFrame("Button", nil, row)
                button:SetFrameLevel(row:GetFrameLevel() + 1)
                EllesmereUI.MakeStyledButton(button, action.text, 13, EllesmereUI.RB_COLOURS, action.onClick)
                local wi = EllesmereUI._widgetInternals
                if wi and wi.IndexSlotForSearch then
                    wi.IndexSlotForSearch(parent, action.text)
                elseif EllesmereUI._RegisterSearchEntry then
                    local section = parent._currentSection and parent._currentSection._sectionName
                    local selector = EllesmereUI._buildingSelector
                    EllesmereUI._RegisterSearchEntry(action.text, localizedNames[i], nil,
                        EllesmereUI._buildingModule, EllesmereUI._buildingPage, section,
                        selector and selector.setter, selector and selector.key)
                end
            end
            button:ClearAllPoints()
            PP.Size(button, buttonWidth, 32)
            PP.Point(button, "LEFT", row, "LEFT", (i - 1) * (buttonWidth + gap), 0)
            AttachLock(button, action.locked, LockTip)
        end
        row._labelText = table.concat(names, " ")
        local localized = table.concat(localizedNames, " ")
        row._labelTextLoc = localized ~= row._labelText and localized or nil
    end
    y = y - h

    _, h = W:SectionHeader(parent, "MATCH CONDITIONS", y); y = y - h
    _, h = LockedRow({ type = "toggle", text = "Rule enabled",
        getValue = function() return GetRule().enabled ~= false end,
        setValue = function(value) GetRule().enabled = value; Rebuild(); Changed() end,
    }, nil, "global")
    y = y - h

    local function ConditionMultiDropdown(label, key, values, keys, tooltip)
        local items = {}
        for _, value in ipairs(keys) do
            if value ~= "any" then
                local item = { key = value, label = values[value] }
                if key == "threat" then item.tooltip = THREAT_TIPS[value] end
                local requiresStyle = key == "castState" and CUSTOM_CAST_STATES[value]
                local unavailableInstance = function() return key == "instanceType" and not addon.SupportsInstanceType(value) end
                item.lockedFn = function() return RuleLocked() or (requiresStyle and not addon.SupportsCastColorStates()) or unavailableInstance() or false end
                item.lockedTooltip = function()
                    if RuleLocked() then return LockTip() end
                    if unavailableInstance() then return "This instance type is not available on WoW Forever." end
                    return CUSTOM_CAST_STYLE_TIP
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
                if RuleLocked() then return end
                if key == "castState" and CUSTOM_CAST_STATES[option] and not addon.SupportsCastColorStates() then return end
                if key == "instanceType" and selected and not addon.SupportsInstanceType(option) then return end
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
        AttachLock(ddBtn, RuleLocked, LockTip, label)

        if condition.tooltip then
            local hitFrame = CreateFrame("Frame", nil, region)
            hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
            hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
            hitFrame:SetFrameLevel(region:GetFrameLevel() + 10)
            hitFrame:EnableMouse(true)
            hitFrame:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(label, RuleLocked() and LockTip() or condition.tooltip)
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
        ConditionMultiDropdown("Target state", "target", TARGETS, TARGET_ORDER,
            "Current target matches your selected unit. Not current target requires a selected target and matches all other units. No target selected matches units only while you have no target. Multiple selections combine with OR; leaving the list empty means Any."),
        ConditionMultiDropdown("Cast state", "castState", CAST_STATES, CAST_ORDER,
            "Casting matches all active casts. Interruptible cast, Interrupt on CD, and Uninterruptible cast implicitly enable Casting for size, health styling, texture, opacity and borders without checking Casting. Those effects use the first matching active-cast rule. Custom cast colors remain state-specific: the first matching rule per color state wins and native rendering selects the displayed state. Other filters still combine with AND; cast choices combine with OR."),
        ConditionMultiDropdown("Spell school", "spellSchool", SCHOOLS, SCHOOL_ORDER,
            "Learns spell schools from combat-log cast starts while a school rule is enabled. Unknown spells do not match a specific school."),
        ConditionMultiDropdown("Player combat state", "playerCombat", PLAYER_COMBAT, PLAYER_COMBAT_ORDER,
            "Matches your character's combat state, not the nameplate unit's. Choices combine with OR; empty means Any (both states). Other condition groups still combine with AND."),
        ConditionMultiDropdown("Instance Type", "instanceType", INSTANCES, INSTANCE_ORDER,
            "Matches where your character is: open world, dungeon, raid, battleground, arena, scenario or Retail delve. This is not your party/raid group type. Choices combine with OR; empty means Any. Delves are distinct from scenarios, including after completion. Arena, scenario and delve choices are unavailable on Forever."),
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
    local threat = ConditionMultiDropdown("Threat", "threat", THREATS, THREAT_ORDER,
        "Matches the actual aggro holder: a tank, a non-tank (Damage/Healer), or you. Uses detailed threat data, not temporary spell targets. Multiple selections combine with OR; other filter groups combine with AND. Secret or unavailable threat/role data does not match. Unassigned roles do not count as known tanks or non-tanks.")
    local threatRow
    threatRow, h = LockedRow(
        { type = "spacer", text = threat.text, tooltip = threat.tooltip }, {
        type = "toggle", text = "Quest Objective",
        getValue = function() return GetRule().conditions.questObjective == "yes" end,
        setValue = function(value)
            GetRule().conditions.questObjective = value and "yes" or "any"
            Changed()
        end,
        tooltip = "When on, matches only units shown as incomplete objectives in your own quest log. Uses EUI's quest detector and follows its Show In Instances setting. When off, quest status does not restrict this rule.",
    })
    if not EllesmereUI.IsSearchPrebuild() then BuildConditionMultiDropdown(threatRow._leftRegion, threat) end
    y = y - h
    _, h = W:SectionHeader(parent, "APPEARANCE - NAMEPLATE", y); y = y - h
    local sizeRow
    sizeRow, h = LockedRow({
        type = "slider", text = "Nameplate size (%)", min = 50, max = 200, step = 5,
        getValue = function() return GetRule().style.scale or 100 end,
        setValue = function(value) GetRule().style.scale = value; Changed() end,
        tooltip = "Multiplies EUI's normal size, including its animations. Use the cog to choose which elements scale. All elements scale by default; 100% uses EUI's normal size.",
    }, {
        type = "slider", text = "Opacity (%)", min = 0, max = 100, step = 5,
        getValue = function() return GetRule().style.opacity or 100 end,
        setValue = function(value) GetRule().style.opacity = value; Changed() end,
        tooltip = "Multiplies the nameplate's current EUI opacity by this value.",
    })
    if not EllesmereUI.IsSearchPrebuild() and EllesmereUI.BuildInlineCog then
        -- A popup can outlive its page/profile. Bind it to the rule that opened
        -- it and recheck both editor locks and selection on every write.
        local function CogLocked() return RuleLocked() or DB() ~= db or GetRule() ~= rule end
        local cogRows = {
            { type = "toggle", label = "Scale all", disabled = CogLocked, disabledTooltip = LockTip,
                get = function()
                    for _, option in ipairs(addon.ScaleElementOptions) do
                        if not addon.IsScaleElementEnabled(rule.style, option.key) then return false end
                    end
                    return true
                end,
                set = function(value)
                    if CogLocked() then return end
                    local selection
                    if not value then
                        selection = {}
                        for _, option in ipairs(addon.ScaleElementOptions) do selection[option.key] = false end
                    end
                    rule.style.scaleElements = selection
                    Changed()
                end,
            },
        }
        for _, option in ipairs(addon.ScaleElementOptions) do
            local key = option.key
            cogRows[#cogRows + 1] = {
                type = "toggle", label = option.label, tooltip = option.tooltip,
                disabled = CogLocked, disabledTooltip = LockTip,
                get = function() return addon.IsScaleElementEnabled(rule.style, key) end,
                set = function(value)
                    if CogLocked() then return end
                    local selection = rule.style.scaleElements or {}
                    -- Keep Text independent when changing Other, and persist
                    -- explicit Text-on beside Other-off across legacy migration.
                    if key == "other" and not value and selection.text == nil then selection.text = true end
                    if value then
                        if key == "text" and selection.other == false then selection[key] = true else selection[key] = nil end
                    else
                        selection[key] = false
                    end
                    rule.style.scaleElements = next(selection) and selection or nil
                    Changed()
                end,
            }
        end
        EllesmereUI.BuildInlineCog(sizeRow._leftRegion, {
            title = "Nameplate scaling", rows = cogRows, captureRegion = sizeRow._leftRegion,
            disabled = CogLocked, disabledTooltip = LockTip,
            tip = "Choose which elements the nameplate size rule scales. Unchecked elements retain EUI's normal size and animations.",
        })
    end
    y = y - h
    _, h = W:SectionHeader(parent, "APPEARANCE - HEALTH BAR", y); y = y - h
    _, h = LockedRow({ type = "toggle", text = "Override health bar",
        getValue = function() return GetRule().style.healthEnabled ~= false end,
        setValue = function(value) GetRule().style.healthEnabled = value; Changed(); Rebuild() end,
        tooltip = "Apply the health-bar settings below when this rule wins. Off restores EUI color, fill texture and native border, and stops the rule's health glow. Nameplate size, opacity and cast overrides remain independent.",
    })
    y = y - h
    local function HealthOff() return GetRule().style.healthEnabled == false end
    local function HealthBorderOff()
        local style = GetRule().style
        return HealthOff() or style.borderEnabled == false or (style.borderSize or 0) <= 0 or not addon.SupportsBorderStyles()
    end
    _, h = LockedRow({
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
    _, h = LockedRow({
        type = "dropdown", text = "Health-bar texture", values = barTextureValues, order = barTextureOrder,
        disabled = HealthOff, disabledTooltip = "Enable Override health bar first.",
        tooltip = "Use EUI texture restores the current EUI texture. Choose Flat or Blizzard to override it.",
        getValue = function() return GetRule().style.texture or "eui" end,
        setValue = function(value) GetRule().style.texture = value; Changed() end,
    }, nil)
    y = y - h
    _, h = LockedRow({
        type = "toggle", text = "Override health border", disabled = function() return HealthOff() or not addon.SupportsBorderStyles() end,
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
        disabled = HealthBorderOff, disabledTooltip = "Enable Override health border first.",
        getValue = function()
            local color = GetRule().style.borderColor
            return color.r, color.g, color.b, 1
        end,
        setValue = function(r, g, b) GetRule().style.borderColor = { r = r, g = g, b = b }; Changed() end,
    }); y = y - h
    _, h = LockedRow({
        type = "dropdown", text = "Health border texture", values = borderTextureValues, order = borderTextureOrder,
        disabled = HealthBorderOff, disabledTooltip = "Enable Override health border first.",
        getValue = function() return GetRule().style.borderTexture or "solid" end,
        setValue = function(value) GetRule().style.borderTexture = value; Changed(); Rebuild() end,
        tooltip = "Replaces EUI's native health-bar outline using its shared media border renderer. Off restores EUI's current texture, color and size.",
    }, {
        type = "slider", text = "Health border size", min = 1, max = (GetRule().style.borderTexture or "solid") == "solid" and 8 or 4, step = 1,
        disabled = HealthBorderOff, disabledTooltip = "Enable Override health border first.",
        tooltip = "Border thickness/size step, interpreted by EUI's shared border renderer for the selected media texture. Turning the override off preserves the saved settings.",
        getValue = function() return math.max(1, GetRule().style.borderSize or 2) end,
        setValue = function(value) GetRule().style.borderSize = value; Changed() end,
    }); y = y - h

    h = GlowRow("health", HealthOff, "Enable Override health bar first."); y = y - h
    _, h = W:SectionHeader(parent, "APPEARANCE - CAST BAR", y); y = y - h
    _, h = LockedRow({ type = "toggle", text = "Override cast bar",
        getValue = function() return GetRule().style.castEnabled == true end,
        setValue = function(value) GetRule().style.castEnabled = value; Changed(); Rebuild() end,
        tooltip = "Apply the cast settings below when this rule wins. Off restores EUI styling. Only affects nameplates with an EUI cast bar; friendly plates currently have none.",
    })
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
    _, h = LockedRow(colorToggle,
        CastColor("Cast fill color", "castColor", "castColorEnabled")); y = y - h
    _, h = LockedRow({
        type = "dropdown", text = "Cast-bar texture", values = barTextureValues, order = barTextureOrder,
        disabled = CastOff, disabledTooltip = "Enable Override cast bar first.",
        tooltip = "Use EUI texture leaves the current texture unchanged. Flat and Blizzard apply to EUI and Classic styles; stock Blizzard-style cast artwork retains its atlas.",
        getValue = function() return GetRule().style.castTexture or "eui" end,
        setValue = function(value) GetRule().style.castTexture = value; Changed() end,
    }, nil)
    y = y - h
    _, h = LockedRow(CastToggle("Custom cast opacity", "castOpacityEnabled"), {
        type = "slider", text = "Cast opacity (%)", min = 0, max = 100, step = 5,
        disabled = function() return CastOff() or GetRule().style.castOpacityEnabled ~= true end,
        disabledTooltip = "Enable Custom cast opacity first.",
        tooltip = "Fades the cast bar and its child elements. This also works when EUI lifts casts in front of nameplates.",
        getValue = function() return GetRule().style.castOpacity or defaults.castOpacity end,
        setValue = function(value) GetRule().style.castOpacity = value; Changed() end,
    }); y = y - h
    local castBorderToggle = CastToggle("Override cast border", "castBorderEnabled")
    castBorderToggle.disabled = function() return CastOff() or not addon.SupportsBorderStyles() end
    _, h = LockedRow(castBorderToggle,
        CastColor("Cast border color", "castBorderColor", "castBorderEnabled")); y = y - h
    local function CastBorderOff() return CastOff() or GetRule().style.castBorderEnabled ~= true or not addon.SupportsBorderStyles() end
    _, h = LockedRow({
        type = "dropdown", text = "Cast border texture", values = borderTextureValues, order = borderTextureOrder,
        disabled = CastBorderOff, disabledTooltip = "Enable Override cast border first.",
        getValue = function() return GetRule().style.castBorderTexture or "solid" end,
        setValue = function(value) GetRule().style.castBorderTexture = value; Changed(); Rebuild() end,
        tooltip = "Replaces EUI's native cast-bar outline using the same media textures as the health border, including lifted casts.",
    }, {
        type = "slider", text = "Cast border size", min = 1, max = (GetRule().style.castBorderTexture or "solid") == "solid" and 8 or 4, step = 1,
        disabled = CastBorderOff,
        disabledTooltip = "Enable Override cast border first.",
        tooltip = "Border thickness/size step, interpreted by EUI's shared renderer. The cast icon separator is not replaced.",
        getValue = function() return GetRule().style.castBorderSize or defaults.castBorderSize end,
        setValue = function(value) GetRule().style.castBorderSize = value; Changed() end,
    }); y = y - h

    h = GlowRow("cast", CastOff, "Enable Override cast bar first."); y = y - h
    _, h = W:SectionHeader(parent, "APPEARANCE - TEXT", y); y = y - h
    _, h = LockedRow({ type = "toggle", text = "Override text",
        disabled = function() return DB() ~= db or GetRule() ~= rule end,
        disabledTooltip = "Select this rule again to edit its text.",
        getValue = function() return GetRule().style.textEnabled == true end,
        setValue = function(value) GetRule().style.textEnabled = value; Changed(); Rebuild() end,
        tooltip = "Per-rule content and colors in EUI's existing text slots. Independent of bar fill/border overrides. Off restores EUI's native text. Match conditions and first-rule priority still apply.",
    }); y = y - h
    local function TextOff() return DB() ~= db or GetRule() ~= rule or GetRule().style.textEnabled ~= true end
    local function TextSlot(slot)
        local values, order = addon.GetRuleTextChoices(slot.cast)
        return { type = "dropdown", text = slot.label .. " content", values = values, order = order,
            disabled = TextOff, disabledTooltip = "Enable Override text first.",
            getValue = function() return GetRule().style.textSlots and GetRule().style.textSlots[slot.key] or "eui" end,
            setValue = function(value)
                local style = GetRule().style
                style.textSlots = style.textSlots or {}
                if value == "eui" then style.textSlots[slot.key] = nil else style.textSlots[slot.key] = value end
                Changed()
            end,
            tooltip = "Uses EUI's existing position, font size and offsets. Use EUI setting preserves native content; None hides this slot. Missing restricted data is left blank rather than inspected.",
        }
    end
    for index = 1, #addon.RuleTextSlots, 2 do
        local right = addon.RuleTextSlots[index + 1]
        _, h = LockedRow(TextSlot(addon.RuleTextSlots[index]), right and TextSlot(right) or nil); y = y - h
    end
    _, h = W:SectionHeader(parent, "TEXT COLORS", y); y = y - h
    for _, key in ipairs(addon.RuleTextElements) do
        local label = addon.RuleTextLabels[key]
        local function ColorOff() return TextOff() or not (GetRule().style.textColors and GetRule().style.textColors[key]) end
        _, h = LockedRow({ type = "toggle", text = "Override " .. label .. " color", disabled = TextOff,
            disabledTooltip = "Enable Override text first.",
            getValue = function() return GetRule().style.textColors and GetRule().style.textColors[key] ~= nil or false end,
            setValue = function(value)
                local style = GetRule().style; style.textColors = style.textColors or {}
                if value then style.textColors[key] = { r = 1, g = 1, b = 1 } else style.textColors[key] = nil end
                Changed(); Rebuild()
            end,
        }, { type = "colorpicker", text = label .. " text color", hasAlpha = false,
            disabled = ColorOff, disabledTooltip = "Enable the matching text color override first.",
            getValue = function()
                local c = GetRule().style.textColors and GetRule().style.textColors[key] or { r = 1, g = 1, b = 1 }
                return c.r, c.g, c.b, 1
            end,
            setValue = function(r, g, b) GetRule().style.textColors[key] = { r = r, g = g, b = b }; Changed() end,
        }); y = y - h
    end
    _, h = W:SectionHeader(parent, "APPEARANCE - TARGET ARROWS", y); y = y - h
    local arrowValues, arrowOrder = addon.GetTargetArrowOptions()
    local function ArrowsUnavailable() return not addon.SupportsTargetArrows() end
    _, h = LockedRow({ type = "toggle", text = "Override target arrows",
        disabled = ArrowsUnavailable, disabledTooltip = "Update EllesmereUI Nameplates to use its target-arrow styles.",
        getValue = function() return GetRule().style.targetArrowsEnabled == true end,
        setValue = function(value) GetRule().style.targetArrowsEnabled = value; Changed(); Rebuild() end,
        tooltip = "The first matching rule can show a different arrow style on the current target, even when EUI's general arrows are off. Other plates do not gain target arrows. Turning this off restores EUI's normal arrows. Color and size follow EUI's target-arrow settings.",
    }); y = y - h
    local function ArrowsOff() return ArrowsUnavailable() or GetRule().style.targetArrowsEnabled ~= true end
    _, h = LockedRow({ type = "dropdown", text = "Target-arrow style",
        values = arrowValues, order = arrowOrder, disabled = ArrowsOff,
        disabledTooltip = "Enable Override target arrows first.",
        getValue = function() return GetRule().style.targetArrowStyle or "eui" end,
        setValue = function(value) GetRule().style.targetArrowStyle = value; Changed() end,
    }, nil)
    y = y - h

    return math.abs(y)
end

local function BuildAboutPage(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    local function Paragraph(text)
        local row, height = W:Spacer(parent, y, 56)
        if not EllesmereUI.IsSearchPrebuild() then
            local PP = EllesmereUI.PanelPP
            local pad = EllesmereUI.CONTENT_PAD + 20
            local label = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1, 0.8)
            PP.Point(label, "TOPLEFT", row, "TOPLEFT", pad, -8)
            label:SetWidth(math.max(100, parent:GetWidth() - pad * 2))
            label:SetJustifyH("LEFT")
            label:SetWordWrap(true)
            local displayText = EllesmereUI.L(text)
            label:SetText(displayText)
            height = math.ceil(label:GetStringHeight()) + 20
            PP.Size(row, parent:GetWidth(), height)
            -- Informational rows are searchable text, rather than blank spacers.
            row._isSpacer = nil
            row._labelText = text
            row._labelTextLoc = displayText ~= text and displayText or nil
        end
        y = y - height
    end
    local function Section(title, text)
        _, h = W:SectionHeader(parent, title, y); y = y - h
        Paragraph(text)
    end
    local version
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if type(getMetadata) == "function" then version = getMetadata(PLUGIN_ID, "Version") end
    local versionText = type(version) == "string" and version ~= "" and ("Version " .. version .. ". ") or ""
    Section("NAMEPLATE EXTRAS", versionText ..
        "Adds customizable, rule-based styling to EllesmereUI Nameplates so important units and casts stand out. Requires EllesmereUI and EllesmereUI Nameplates.")
    Section("CUSTOM APPEARANCE",
        "Adjust nameplate size and opacity, health-bar colors and textures, borders, animated border glows, and target-arrow styles. Apply styles based on unit type, reaction, classification, quest objectives, targets, threat and casts.")
    Section("CAST COLORS",
        "Customize cast-bar appearance, including separate colors for interruptible casts, interrupts on cooldown and uninterruptible casts.")
    Section("PROFILES AND SHARING",
        "Save profiles for different characters and export or import your rules. Use Enable rule styling on the Rules page to pause all styling without deleting your setup.")
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
        label = "Extend Nameplates",
        modules = {
            {
                key = "NameplateStyle",
                title = "Nameplate Style",
                description = "Rule-based nameplate styling by unit, target, cast and rank.",
                pages = { "Rules", "Profiles", "Sharing", "About" },
                buildPage = function(pageName, parent, yOffset)
                    if pageName ~= "Rules" and not EllesmereUI.IsSearchPrebuild() and EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
                    if pageName == "Profiles" then return BuildProfilesPage(parent, yOffset) end
                    if pageName == "Sharing" then return BuildSharingPage(parent, yOffset) end
                    if pageName == "About" then return BuildAboutPage(parent, yOffset) end
                    return BuildRulesPage(parent, yOffset)
                end,
                getHeaderBuilder = function(pageName) if pageName == "Rules" then return rulesHeaderBuilder end end,
                onPageCacheRestore = function(pageName)
                    if pageName == "Rules" and rulesPreview then rulesPreview.Update(true) end
                end,
                onReset = function()
                    addon.ResetActiveProfile()
                    Rebuild()
                    Changed()
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
