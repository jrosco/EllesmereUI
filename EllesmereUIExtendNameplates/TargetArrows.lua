local _, addon = ...
local api = EllesmereUIExtendNameplates
local KEYS = { "simple", "double", "winged", "feathered", "split", "celestial", "rune", "demon",
    "halo", "curved", "barbed", "holyspear", "bracket", "diamond", "crystal", "classic" }
local valid = { eui = true }
for _, key in ipairs(KEYS) do valid[key] = true end
local states = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local namespaces = setmetatable({}, { __mode = "k" })
local layoutStyle
local Reapply
local function Secret(value) return issecretvalue and issecretvalue(value) end
function api.ValidateTargetArrowStyle(key) return key == nil or type(key) == "string" and valid[key] == true end
function api.SupportsTargetArrows()
    local np = _G.EllesmereNameplates_NS
    return np and type(np.TARGET_ARROW_STYLES) == "table" and type(np.TARGET_ARROW_DIR) == "string"
        and type(np.ResolveTargetArrowStyle) == "function" or false
end
function api.GetTargetArrowStyle(key)
    local np = _G.EllesmereNameplates_NS
    if not api.SupportsTargetArrows() then return end
    if key == nil or key == "eui" then return np.ResolveTargetArrowStyle(np.db and np.db.profile) end
    if valid[key] then return np.TARGET_ARROW_STYLES[key] end
end
function api.GetTargetArrowOptions()
    local values, order = { eui = "Use EUI arrow style" }, { "eui" }
    local np = _G.EllesmereNameplates_NS
    for _, key in ipairs(KEYS) do
        local style = np and np.TARGET_ARROW_STYLES and np.TARGET_ARROW_STYLES[key]
        if style then values[key] = style.label; order[#order + 1] = key end
    end
    values._menuOpts = {
        itemHeight = 26,
        icon = function(key)
            local style = api.GetTargetArrowStyle(key)
            return style and np.TARGET_ARROW_DIR .. style.l .. ".png"
        end,
        iconWidth = function(key)
            local style = api.GetTargetArrowStyle(key)
            return style and math.floor(style.w * 24 / 16 + 0.5)
        end,
    }
    return values, order
end
local function InstallNamespace()
    local np = _G.EllesmereNameplates_NS
    if not api.SupportsTargetArrows() or namespaces[np] then return end
    namespaces[np] = true
    -- EUI's existing layout uses this resolver dynamically. Scope the override
    -- to our synchronous positioning pass, without editing its saved profile.
    local original = np.ResolveTargetArrowStyle
    np.ResolveTargetArrowStyle = function(profile) return layoutStyle or original(profile) end
    for _, method in ipairs({ "PositionArrowsOutsideAuras", "NPC_ReanchorArrows" }) do
        if type(np[method]) == "function" then hooksecurefunc(np, method, function(plate) Reapply(plate) end) end
    end
end
local function Friendly(plate, np)
    return plate.unit and np.friendlyPlates and np.friendlyPlates[plate.unit] == plate or false
end
local function Dimensions(plate, spec, np)
    local profile = np.db and np.db.profile or {}
    local scale = Friendly(plate, np) and 1 or math.max(0.1, math.min(5, tonumber(profile.targetArrowScale) or 1))
    return math.floor(spec.w * scale + 0.5), math.floor(16 * scale + 0.5)
end
local function Watch(plate, state, arrow)
    if state.textures[arrow] then return end
    local path = arrow:GetTexture()
    local entry = { path = not Secret(path) and path or nil }
    state.textures[arrow] = entry
    hooksecurefunc(arrow, "SetTexture", function(_, value)
        if not state.writing then entry.path = value end
    end)
end
local function EnsureArrows(plate, np)
    if plate.leftArrow and plate.rightArrow then return true end
    local parent = plate.arrowHost or plate.health
    if not plate.arrowHost then
        -- Retail side-aura anchors require creation-time aspects. Forever and
        -- older clients can reject the template; their plain parent is valid.
        local ok, holder = pcall(CreateFrame, "Frame", nil, plate.health, "DisableUntrustedLayoutScriptsTemplate")
        if ok and holder then
            holder:SetAllPoints(plate.health)
            holder:SetFrameLevel(plate.health:GetFrameLevel())
            plate.arrowHost, parent = holder, holder
        end
    end
    local base = np.ResolveTargetArrowStyle(np.db and np.db.profile)
    plate.leftArrow = plate.leftArrow or parent:CreateTexture(nil, "OVERLAY")
    plate.rightArrow = plate.rightArrow or parent:CreateTexture(nil, "OVERLAY")
    plate.leftArrow:SetTexture(np.TARGET_ARROW_DIR .. base.l .. ".png")
    plate.rightArrow:SetTexture(np.TARGET_ARROW_DIR .. base.r .. ".png")
    if np.GetTargetArrowColor then
        local r, g, b = np.GetTargetArrowColor(np.db and np.db.profile)
        plate.leftArrow:SetVertexColor(r, g, b); plate.rightArrow:SetVertexColor(r, g, b)
    end
    plate.leftArrow:Hide(); plate.rightArrow:Hide()
    return true
end
local function Position(plate, spec, np)
    local width, height = Dimensions(plate, spec, np)
    plate._arrowW, plate._arrowH = width, height
    if not Friendly(plate, np) and np.PositionArrowsOutsideAuras then
        local previous = layoutStyle
        layoutStyle = spec
        local ok = pcall(np.PositionArrowsOutsideAuras, plate)
        layoutStyle = previous
        if ok then
            -- EUI uses the dimensions stashed above to hug modern aura rows.
            if np.NPC_ReanchorArrows then pcall(np.NPC_ReanchorArrows, plate) end
            return
        end
    end
    -- No restricted region measurements: fully defined top/bottom anchors also
    -- work on Forever and on clients whose native layout data is unreadable.
    local anchor = Friendly(plate, np) and plate.name or plate.health
    local friendly = Friendly(plate, np)
    local profile = np.db and np.db.profile or {}
    local barHeight = tonumber(profile.healthBarHeight) or (np.defaults and np.defaults.healthBarHeight) or 10
    for index, arrow in ipairs({ plate.leftArrow, plate.rightArrow }) do
        arrow:ClearAllPoints()
        local side, sign = index == 1 and "LEFT" or "RIGHT", index == 1 and -1 or 1
        local offset = sign * ((friendly and 2 or 8) + width / 2)
        if friendly then
            arrow:SetPoint("TOP", anchor, side, offset, height / 2)
            arrow:SetPoint("BOTTOM", anchor, side, offset, -height / 2)
        else
            local dy = (height - barHeight) / 2
            arrow:SetPoint("TOP", anchor, "TOP" .. side, offset, dy)
            arrow:SetPoint("BOTTOM", anchor, "BOTTOM" .. side, offset, -dy)
        end
        arrow:SetWidth(width)
    end
end
local function Restore(plate, state, released)
    if not state.active then return end
    state.active = nil
    state.writing = true
    for arrow, entry in pairs(state.textures) do if not Secret(entry.path) then arrow:SetTexture(entry.path) end end
    state.writing = nil
    local np = _G.EllesmereNameplates_NS
    local base = api.GetTargetArrowStyle("eui")
    if base and plate.leftArrow and plate.rightArrow then
        local width, height = Dimensions(plate, base, np)
        plate._arrowW, plate._arrowH = width, height
        plate.leftArrow:SetSize(width, height); plate.rightArrow:SetSize(width, height)
        -- Friendly ApplyTarget updates artwork/size but keeps its name anchors.
        -- Restore their offsets too when changing back to a different width.
        if Friendly(plate, np) then Position(plate, base, np) end
    end
    if not released and plate.unit and type(plate.ApplyTarget) == "function" then
        plate:ApplyTarget()
    elseif plate.leftArrow then
        plate.leftArrow:Hide(); plate.rightArrow:Hide()
    end
end
function addon.ApplyTargetArrowStyle(plate, style, released)
    local state = states[plate]
    if state and state.busy then return end
    local np = _G.EllesmereNameplates_NS
    local spec = style and style.targetArrowsEnabled == true and api.GetTargetArrowStyle(style.targetArrowStyle)
    if not spec and not (state and state.active) then
        if state then state.style, state.unit = style, plate.unit end
        return
    end
    -- Restoration also needs this guard: a condition can stop matching because
    -- target identity became secret, before the ordinary renderer clears us.
    local target = plate.unit and UnitIsUnit(plate.unit, "target")
    local enabled = spec and not Secret(target) and target == true
    if not state and not enabled then return end
    if not state then state = { textures = setmetatable({}, { __mode = "k" }) }; states[plate] = state end
    state.style, state.unit, state.busy = style, plate.unit, true
    local ok, err = pcall(function()
        if not enabled then Restore(plate, state, released or Secret(target)); return end
        InstallNamespace()
        if not EnsureArrows(plate, np) then return end
        Watch(plate, state, plate.leftArrow); Watch(plate, state, plate.rightArrow)
        state.active, state.writing = true, true
        plate.leftArrow:SetTexture(np.TARGET_ARROW_DIR .. spec.l .. ".png")
        plate.rightArrow:SetTexture(np.TARGET_ARROW_DIR .. spec.r .. ".png")
        if np.GetTargetArrowColor then
            local r, g, b = np.GetTargetArrowColor(np.db and np.db.profile)
            plate.leftArrow:SetVertexColor(r, g, b); plate.rightArrow:SetVertexColor(r, g, b)
        end
        plate.leftArrow:Show(); plate.rightArrow:Show()
        Position(plate, spec, np)
        state.writing = nil
    end)
    state.busy, state.writing = nil, nil
    if not ok then error(err) end
end
Reapply = function(plate)
    local state = states[plate]
    if state and not state.busy and state.unit == plate.unit then addon.ApplyTargetArrowStyle(plate, state.style) end
end
function addon.InstallTargetArrowHooks(plate)
    InstallNamespace()
    if not plate or hooked[plate] then return end
    hooked[plate] = true
    for _, method in ipairs({ "ApplyTarget", "UpdateRaidIcon", "UpdateClassification", "UpdateFaction", "RefreshCastIconSideReserve" }) do
        if type(plate[method]) == "function" then
            hooksecurefunc(plate, method, function() Reapply(plate) end)
        end
    end
end
InstallNamespace()
