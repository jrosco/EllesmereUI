local _, addon = ...
local api = EllesmereUIExtendNameplates
local OPTIONS = {
    { key = "healthBar", label = "Health bar", tooltip = "Health bar, its child elements and additional health border." },
    { key = "castBar", label = "Cast bar", tooltip = "Cast bar, icon, text, shield and borders, including lifted casts." },
    { key = "classResources", label = "Class resources", tooltip = "Class-resource pips, backgrounds, decorations and resource bars." },
    { key = "text", label = "Text", tooltip = "Nameplate name, health, level, target-of-target, threat, classification and friendly subtitle text. Cast-bar text follows Cast bar; aura counters follow Other elements." },
    { key = "other", label = "Other elements", tooltip = "Buffs, debuffs, crowd-control icons, cast-lockout indicators, markers, selection indicators and remaining nameplate elements." },
}
api.ScaleElementOptions = OPTIONS
local policies = setmetatable({}, { __mode = "k" })
local entries = setmetatable({}, { __mode = "k" })
local hookedNamespaces = setmetatable({}, { __mode = "k" })
local hookedAuraKits = setmetatable({}, { __mode = "k" })
local auraHolders = setmetatable({}, { __mode = "k" })
local plateHolders = setmetatable({}, { __mode = "k" })
local hostOwners = setmetatable({}, { __mode = "kv" })
local pending = setmetatable({}, { __mode = "k" })
local hookedPlates = setmetatable({}, { __mode = "k" })
local Reconcile
local function QueueReconcile(plate)
    if not plate or not policies[plate] or pending[plate] then return end
    pending[plate] = true
    C_Timer.After(0, function()
        pending[plate] = nil
        Reconcile(plate)
    end)
end

local function Enabled(selection, key)
    return type(selection) ~= "table" or selection[key] ~= false
end
function api.IsScaleElementEnabled(style, key)
    return Enabled(style and style.scaleElements, key)
end
function addon.NormalizeScaleElements(selection)
    if type(selection) ~= "table" then return selection end
    -- Retired aura toggles no longer override Other. Keep Other's existing
    -- choice (missing means enabled) when loading older settings/share codes.
    selection.buffs, selection.debuffs, selection.cc = nil, nil, nil
    -- Text previously belonged to Other. Preserve old opt-outs on load/import;
    -- the editor stores an explicit true when Text is enabled independently.
    if selection.text == nil and selection.other == false then selection.text = false end
    return next(selection) and selection or nil
end
api.NormalizeScaleElements = addon.NormalizeScaleElements
function api.ValidateScaleElements(selection)
    if selection == nil then return true end
    if type(selection) ~= "table" then return false end
    local valid = { buffs = true, debuffs = true, cc = true } -- accepted only for legacy migration
    for _, option in ipairs(OPTIONS) do valid[option.key] = true end
    for key, value in pairs(selection) do
        if not valid[key] or type(value) ~= "boolean" then return false end
    end
    return true
end
local function Secret(value) return issecretvalue and issecretvalue(value) end
local function Set(entry, object, factor)
    local current = object:GetScale()
    if Secret(current) then return end
    if entry.factor == factor and current == entry.base * factor then return end
    local previous = entry.factor
    entry.factor, entry.writing = factor, true
    local ok, err = pcall(object.SetScale, object, entry.base * factor)
    entry.writing = nil
    if not ok then entry.factor = previous; error(err) end
end
local function Watch(object)
    local entry = entries[object]
    if entry then return entry end
    if not object or type(object.GetScale) ~= "function" or type(object.SetScale) ~= "function" then return end
    local scale = object:GetScale()
    if Secret(scale) or type(scale) ~= "number" then return end
    entry = { base = scale, factor = 1 }
    entries[object] = entry
    hooksecurefunc(object, "SetScale", function(self, value)
        if entry.writing then return end
        if Secret(value) or type(value) ~= "number" then return end
        entry.base = value
        if entry.factor ~= 1 then Set(entry, self, entry.factor) end
    end)
    if object.SetParent then
        hooksecurefunc(object, "SetParent", function()
            if entry.owner then Reconcile(entry.owner) end
        end)
    end
    return entry
end
local function Targets(plate, policy)
    local result = {}
    local function Add(object, key)
        if object and type(object.GetScale) == "function" and type(object.SetScale) == "function" then
            result[object] = Enabled(policy.selection, key) and policy.factor or 1
        end
    end
    Add(plate.health, "healthBar")
    Add(policy.border, "healthBar")
    if addon.GetRuleBorderFrames then
        local healthBorder, castBorder = addon.GetRuleBorderFrames(plate)
        Add(healthBorder, "healthBar"); Add(castBorder, "castBar")
    end
    Add(plate.cast, "castBar")
    for _, key in ipairs({ "buffs", "debuffs", "cc" }) do
        for _, object in ipairs(plate[key] or {}) do Add(object, "other") end
    end
    Add(plate.npcLockout, "other")
    Add(plate._cpBar, "classResources")
    for _, pip in ipairs(plate._cpPips or {}) do
        Add(pip, "classResources")
        for _, key in ipairs({ "_bg", "_shapeMask", "_border", "_borderBox", "_secretBar" }) do
            Add(pip[key], "classResources")
        end
    end
    -- Hosts and font strings are both included: friendly plates have direct
    -- health/plate text, and core slot text can be reparented between hosts.
    for _, key in ipairs({ "healthTextFrame", "topTextFrame", "bottomTextFrame", "_classicLevelHost",
        "name", "hpText", "hpNumber", "levelText", "totText", "threatPctText", "focusLetter",
        "classText", "_classicLevel", "subText1" }) do Add(plate[key], "text") end
    for _, host in pairs(plate._slotTextHosts or {}) do Add(host, "text") end
    if addon.GetRuleTextFrames then
        local host, fonts = addon.GetRuleTextFrames(plate)
        Add(host, "text")
        for key, font in pairs(fonts or {}) do
            if not key:match("^cast") then Add(font, "text") end
        end
    end
    -- Name-adjacent raid markers can be parented to a text host, but follow Other.
    for _, key in ipairs({ "raidFrame", "nameRaidFrame", "classFrame", "factionFrame", "glowFrame", "_classicSkull",
        "arrowHost", "leftArrow", "rightArrow",
        "focusClipFill", "focusClipBg", "hoverClipFill", "hoverClipBg", "targetClipFill", "targetClipBg" }) do Add(plate[key], "other") end
    for holder in pairs(plateHolders[plate] or {}) do
        for container, key in pairs(auraHolders[holder].containers) do Add(container, key) end
    end
    return result
end
local function Restore(plate, policy)
    for object in pairs(policy.frames) do
        local entry = entries[object]
        if entry and entry.owner == plate then Set(entry, object, 1); entry.owner = nil end
        policy.frames[object] = nil
    end
end
Reconcile = function(plate)
    local policy = policies[plate]
    if not policy or policy.busy then return end
    policy.busy = true
    local ok, err = pcall(function()
        local targets = Targets(plate, policy)
        -- These are plugin multipliers, not native effective scales. Cancel
        -- only the nearest category/root multiplier; EUI's own scales remain.
        local function Inherited(object, seen)
            seen = seen or {}
            while not Secret(object) and object and not seen[object] do
                seen[object] = true
                if targets[object] and Secret(object:GetScale()) then return nil end
                if object.IsIgnoringParentScale then
                    local ignoring = object:IsIgnoringParentScale()
                    -- Native nameplate getters can return secret booleans even
                    -- when EUI authored the frame. Check before branching.
                    if Secret(ignoring) then return nil end
                    if ignoring then return 1 end
                end
                local parent = object.GetParent and object:GetParent()
                if Secret(parent) then return nil end
                if not parent then return 1 end
                if parent == plate or parent == plate._castLift then return policy.rootFactor end
                if targets[parent] then
                    if Inherited(parent, seen) == nil then return nil end
                    return targets[parent]
                end
                object = parent
            end
            return nil
        end
        for object in pairs(policy.frames) do
            if not targets[object] then
                local entry = entries[object]
                if entry and entry.owner == plate then Set(entry, object, 1); entry.owner = nil end
                policy.frames[object] = nil
            end
        end
        for object, desired in pairs(targets) do
            local inherited = Inherited(object)
            local entry = entries[object]
            if inherited == nil then
                -- Unknown inheritance cannot safely supply a compensation.
                -- Release our previous adjustment and retry on a later refresh.
                if entry and entry.owner == plate then Set(entry, object, 1) end
            else
                local multiplier = desired / inherited
                if multiplier ~= 1 or entry then
                    entry = entry or Watch(object)
                    if entry then
                        entry.owner = plate
                        policy.frames[object] = true
                        Set(entry, object, multiplier)
                    end
                end
            end
        end
    end)
    policy.busy = nil
    if not ok then error(err) end
end
function addon.PrepareScaleSelection(plate, factor, selection, border)
    if not hookedPlates[plate] then
        hookedPlates[plate] = true
        for _, method in ipairs({ "ApplyHealthTextAppearance", "RefreshNamePosition", "EnsureToTText", "UpdateName", "UpdateClassification" }) do
            if type(plate[method]) == "function" then hooksecurefunc(plate, method, function() Reconcile(plate) end) end
        end
    end
    local policy = policies[plate]
    if not policy then
        policy = { frames = setmetatable({}, { __mode = "k" }) }
        policies[plate] = policy
    end
    local rootFactor = Enabled(selection, "other") and factor or 1
    -- Remaining plate children inherit Other; named categories compensate or
    -- apply their own factor, without changing EUI's parents/animation caches.
    local resourceFactor = (Enabled(selection, "classResources") and factor or 1) / rootFactor
    policy.resourcesDirty = policy.resourcesDirty or policy.resourceFactor ~= resourceFactor or policy.rootFactor ~= rootFactor
    policy.factor, policy.selection, policy.border = factor, selection, border
    policy.rootFactor, policy.resourceFactor = rootFactor, resourceFactor
    if plate.health then hostOwners[plate.health] = plate end
    if plate.cast then hostOwners[plate.cast] = plate end
    return policy.rootFactor
end
function addon.ApplyScaleSelection(plate)
    Reconcile(plate)
    local policy, np = policies[plate], _G.EllesmereNameplates_NS
    if policy and policy.resourcesDirty then
        policy.resourcesDirty = nil
        if np and np.RefreshClassPower then np.RefreshClassPower() end
    end
end
function addon.ClearScaleSelection(plate)
    local policy = policies[plate]
    if policy then
        Restore(plate, policy); policies[plate] = nil
        return policy.resourceFactor ~= 1 or policy.rootFactor ~= 1
    end
end
function addon.InstallScaleSelectionHooks()
    local kit = EllesmereUI and EllesmereUI.AuraKit
    if kit and kit.AddGroupToContainer and not hookedAuraKits[kit] then
        hookedAuraKits[kit] = true
        local categories = { ["np:buffs"] = "other", ["np:buffs2"] = "other", ["np:buffsplain"] = "other",
            ["np:debuffs"] = "other", ["np:cc"] = "other" }
        -- Nameplates build their pooled rows through AuraKit's deferred jobs.
        -- Observe the public group specs; never inspect engine aura buttons,
        -- counts, secret layouts, or Nameplates' private bundle tables.
        hooksecurefunc(kit, "AddGroupToContainer", function(container, spec)
            local key = categories[spec.style]
            if not key then return end
            local holder = container:GetParent()
            if Secret(holder) or not holder then return end
            local record = auraHolders[holder]
            if not record then
                record = { containers = setmetatable({}, { __mode = "k" }) }
                auraHolders[holder] = record
                local function Bind(parent)
                    local old = record.plate
                    if old and plateHolders[old] then plateHolders[old][holder] = nil end
                    record.plate = nil
                    if not Secret(parent) and parent and parent.health then
                        record.plate = parent
                        plateHolders[parent] = plateHolders[parent] or setmetatable({}, { __mode = "k" })
                        plateHolders[parent][holder] = true
                    end
                    if old then Reconcile(old) end
                    if record.plate then
                        if not policies[record.plate] then addon.PrepareScaleSelection(record.plate, 1, nil) end
                        Reconcile(record.plate)
                    end
                end
                hooksecurefunc(holder, "SetParent", function(_, parent) Bind(parent) end)
                Bind(holder:GetParent())
            end
            record.containers[container] = key
            QueueReconcile(record.plate)
        end)
    end
    local np = _G.EllesmereNameplates_NS
    if not np or hookedNamespaces[np] then return end
    hookedNamespaces[np] = true
    -- This Lua rendering helper receives readable geometry and is looked up
    -- dynamically by Nameplates. Adapt its input while preserving its output
    -- and native renderer, rather than editing the external addon.
    if np._WCNP_Attach then
        local original = np._WCNP_Attach
        np._WCNP_Attach = function(anchor, rel, left, x, y, width, height, cell, gap, scale, color, empty, bg, power)
            local object, owner = anchor
            while not Secret(object) and object do
                owner = hostOwners[object] or (policies[object] and object)
                if owner then break end
                object = object.GetParent and object:GetParent()
            end
            local policy = owner and policies[owner]
            if policy and not Secret(scale) and type(scale) == "number" then scale = scale * policy.resourceFactor end
            return original(anchor, rel, left, x, y, width, height, cell, gap, scale, color, empty, bg, power)
        end
    end
    -- The getter is shared by local resource refreshes (including poll ticks).
    -- Reconcile after the layout returns, when lazy textures/bars exist.
    if np.GetClassPowerScale then
        hooksecurefunc(np, "GetClassPowerScale", function() QueueReconcile(np._cachedTargetPlate) end)
    end
    if np.ApplyPipShape then hooksecurefunc(np, "ApplyPipShape", function(plate) Reconcile(plate) end) end
    if np.RefreshClassPower then
        hooksecurefunc(np, "RefreshClassPower", function() Reconcile(np._cachedTargetPlate) end)
    end
    if np.RefreshCastOverlay then hooksecurefunc(np, "RefreshCastOverlay", function(plate) Reconcile(plate) end) end
    for _, method in ipairs({ "SlotTextHost", "NPC_UpdateLockout", "NPC_ReanchorArrows" }) do
        if np[method] then hooksecurefunc(np, method, function(plate) Reconcile(plate) end) end
    end
    if np.NPC_AttachPlate then
        hooksecurefunc(np, "NPC_AttachPlate", function(plate)
            -- A pool bundle can arrive from a selectively scaled plate. Always
            -- release/adopt existing entries, including for an all-scaled owner.
            if not policies[plate] then addon.PrepareScaleSelection(plate, 1, nil) end
            Reconcile(plate)
        end)
    end
    if np.NPC_DetachPlate then hooksecurefunc(np, "NPC_DetachPlate", function(plate) Reconcile(plate) end) end
end
addon.InstallScaleSelectionHooks()
