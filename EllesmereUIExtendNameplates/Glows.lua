local _, addon = ...
local api = EllesmereUIExtendNameplates
local STYLES = { [0] = "None", [1] = "Pixel Glow", [3] = "Auto-Cast Shine" }
local ORDER = { 0, 1, 3 }
local DEFAULT_COLOR = { r = 1, g = 0.788, b = 0.137 }
local states = setmetatable({}, { __mode = "k" })
local hidden = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local Apply
local function Secret(value) return issecretvalue and issecretvalue(value) end
local function Number(value, fallback, min, max)
    if Secret(value) or type(value) ~= "number" or value ~= value then return fallback end
    return math.max(min, math.min(max, value))
end
function api.SupportsRuleGlows()
    local G = EllesmereUI and EllesmereUI.Glows
    return G and type(G.StartSpecGlow) == "function" and type(G.StopGlow) == "function"
        and type(G.StartAutoCastShine) == "function" or false
end
function api.ValidateRuleGlowStyle(value)
    return value == nil or type(value) == "number" and STYLES[value] ~= nil
end
function api.GetRuleGlowOptions()
    local values, order = {}, {}
    local G = EllesmereUI and EllesmereUI.Glows
    for _, key in ipairs(ORDER) do
        values[key] = G and G.STYLES and G.STYLES[key] and G.STYLES[key].name or STYLES[key]
        order[#order + 1] = key
    end
    return values, order
end
function api.GetRuleGlowColor(style, prefix)
    return style[prefix .. "GlowColor"] or DEFAULT_COLOR
end
local function Spec(style, prefix)
    if not style or prefix == "health" and style.healthEnabled == false
        or prefix == "cast" and style.castEnabled ~= true then return end
    local index = style[prefix .. "GlowStyle"]
    if not api.ValidateRuleGlowStyle(index) or index == nil or index == 0 then return end
    local c = api.GetRuleGlowColor(style, prefix)
    local bg = style[prefix .. "GlowBackgroundColor"] or { r = 0, g = 0, b = 0 }
    return { style = index, r = c.r, g = c.g, b = c.b,
        lines = math.floor(Number(style[prefix .. "GlowLines"], 8, 2, 16)),
        thickness = Number(style[prefix .. "GlowThickness"], 2, 1, 4),
        speed = Number(style[prefix .. "GlowSpeed"], 4, 1, 8),
        shineScale = Number(style[prefix .. "GlowShineSize"], 100, 50, 200) / 100,
        bg = style[prefix .. "GlowBackground"] == true, bgR = bg.r, bgG = bg.g, bgB = bg.b }
end
local function Stop(host)
    if not host then return end
    local G = host._extrasGlowEngine
    if G and G.StopGlow then G.StopGlow(host) end
    host._extrasGlowEngine = nil
    host._extrasShineSignature = nil
    host:Hide()
end
function api.StopRuleGlowPreview(host) Stop(host) end
local function Render(host, spec, width, height, preview, restricted)
    if not spec or not api.SupportsRuleGlows() then Stop(host); return false end
    local G = EllesmereUI.Glows
    if host._extrasGlowEngine and host._extrasGlowEngine ~= G then Stop(host) end
    local kind = restricted and "engine" or "bar"
    if restricted and spec.style == 3 then spec.style = 1 end -- native Pixel ants, not an icon-style fallback
    if spec.style == 3 then
        -- The shared StartSpecGlow path fixes Shine's scale at 1. Use EUI's
        -- public lower-level renderer and gate restarts on our own signature.
        local s = host._extrasShineSignature
        if not s or s.w ~= width or s.h ~= height or s.r ~= spec.r or s.g ~= spec.g
            or s.b ~= spec.b or s.scale ~= spec.shineScale then
            Stop(host)
            host._extrasGlowEngine = G
            G.StartAutoCastShine(host, width, spec.r, spec.g, spec.b, spec.shineScale, height)
            -- EUI otherwise probes GetSize on the first animation tick. Seed
            -- its orbit cache from authored dimensions, never restricted rects.
            local d = host._euiAcData
            if type(d) == "table" then
                d.w, d.h, d.perim = width, height, 2 * (width + height)
                d.spacing = d.perim / Number(d.dotsPerLayer, 4, 1, 16)
            end
            host._extrasShineSignature = { w = width, h = height, r = spec.r, g = spec.g, b = spec.b, scale = spec.shineScale }
        end
        host:SetAlpha(1)
    else
        if host._extrasShineSignature then Stop(host) end
        host._extrasGlowEngine = G
        G.StartSpecGlow(host, spec, width, height, kind, preview and G.PANEL_EXTRA or nil)
    end
    host:Show()
    return true
end
function api.RenderRuleGlowPreview(host, style, prefix, width, height)
    host._euiGlowPreview = true
    return Render(host, Spec(style, prefix), width, height, true)
end

local function SuppressImportant(overlay, state)
    if not overlay then return end
    if state.important and state.important ~= overlay then
        local old = hidden[state.important]
        if old and old.owner == state then
            old.owner, old.writing = nil, true; state.important:SetAlpha(old.alpha); old.writing = nil
        end
    end
    local entry = hidden[overlay]
    if not entry then
        entry = { alpha = overlay:GetAlpha() }
        hidden[overlay] = entry
        hooksecurefunc(overlay, "SetAlpha", function(self, value)
            if entry.writing then return end
            entry.alpha = value -- secret values are stored/forwarded, never tested
            if entry.owner then entry.writing = true; self:SetAlpha(0); entry.writing = nil end
        end)
        if type(overlay.SetAlphaFromBoolean) == "function" then
            hooksecurefunc(overlay, "SetAlphaFromBoolean", function(self)
                if entry.writing then return end
                entry.alpha = self:GetAlpha()
                if entry.owner then entry.writing = true; self:SetAlpha(0); entry.writing = nil end
            end)
        end
    end
    state.important, entry.owner = overlay, state
    entry.writing = true; overlay:SetAlpha(0); entry.writing = nil
end
local function ReleaseImportant(state)
    local overlay = state.important
    local entry = overlay and hidden[overlay]
    if entry and entry.owner == state then
        entry.owner, entry.writing = nil, true
        overlay:SetAlpha(entry.alpha)
        entry.writing = nil
    end
    state.important = nil
end
local function AuthoredDimensions(plate, prefix, size)
    local np = _G.EllesmereNameplates_NS or {}
    local friendly = plate.unit and np.friendlyPlates and np.friendlyPlates[plate.unit] == plate
    local function Get(name, fallback)
        if type(np[name]) ~= "function" then return fallback end
        local ok, value = pcall(np[name])
        return ok and Number(value, fallback, 1, 2000) or fallback
    end
    local width = Get(friendly and "GetFriendlyHealthBarWidth" or "GetHealthBarWidth", 180)
    local height = Get(prefix == "cast" and "GetCastBarHeight" or friendly and "GetFriendlyHealthBarHeight" or "GetHealthBarHeight", prefix == "cast" and 17 or 10)
    local profile = np.db and np.db.profile or {}
    if prefix == "cast" then
        local classic = np.NP_Classic and np.NP_Classic()
        if not Secret(classic) and classic == true and np.NP_ClassicCastLayout then
            local ok, _, w = pcall(np.NP_ClassicCastLayout, width, Get("GetHealthBarHeight", 10), height)
            if ok then width = Number(w, width, 1, 2000) end
        elseif profile.castbarIconInWidth and profile.showCastIcon ~= false and not profile.castIconFullSize then
            width = math.max(1, width - height * Number(profile.castIconScale, 1, 0.1, 5))
        end
    end
    -- Observe clean EUI SetSize/SetWidth/SetHeight writes instead of measuring
    -- a secret/aspect-restricted nameplate subtree.
    return size.width or width, size.height or height
end
local function Host(plate, state, prefix, bar)
    local host = state[prefix]
    if not host then
        host = CreateFrame("Frame", nil, bar)
        host:SetAllPoints(bar)
        host:EnableMouse(false)
        state[prefix] = host
        host:SetScript("OnHide", function()
            local G = host._extrasGlowEngine
            if G and G.StopGlow then G.StopGlow(host) end
            host._extrasGlowEngine = nil
            host._extrasShineSignature = nil
            if prefix == "cast" then ReleaseImportant(state); state.castRunning = false end
        end)
        host:SetScript("OnShow", function() if not state.busy then Apply(plate, state) end end)
    end
    host:SetFrameStrata(prefix == "cast" and plate._castOverlayLifted and bar:GetFrameStrata() or "MEDIUM")
    host:SetFrameLevel(bar:GetFrameLevel() + 5)
    return host
end
Apply = function(plate, state)
    if state.busy then return end
    if state.unit ~= plate.unit then
        Stop(state.health); Stop(state.cast); ReleaseImportant(state)
        return
    end
    state.busy = true
    local ok, err = pcall(function()
        for _, prefix in ipairs({ "health", "cast" }) do
            local bar = prefix == "health" and plate.health or plate.cast
            local spec = bar and Spec(state.style, prefix)
            local host = state[prefix]
            local running = false
            if spec and api.SupportsRuleGlows() then
                host = Host(plate, state, prefix, bar)
                local visible, restricted = true, false
                if host.IsVisible then
                    local vok, value = pcall(host.IsVisible, host)
                    restricted = not vok or Secret(value)
                    if not restricted and type(value) == "boolean" then visible = value end
                    -- A stopped host is itself hidden. Determine parent
                    -- visibility so it can restart when the bar is shown.
                    if not visible and bar.IsVisible then
                        vok, value = pcall(bar.IsVisible, bar)
                        restricted = not vok or Secret(value)
                        if not restricted and type(value) == "boolean" then visible = value end
                    end
                end
                if visible or restricted then
                    local width, height = AuthoredDimensions(plate, prefix, state.sizes[prefix])
                    running = Render(host, spec, width, height, false, restricted)
                else Stop(host) end
            else Stop(host) end
            if prefix == "cast" then
                state.castRunning = running
                if running then SuppressImportant(plate._importantCastOverlay, state) else ReleaseImportant(state) end
            end
        end
    end)
    state.busy = nil
    if not ok then
        -- A renderer failure must not leave EUI's own important-cast effect
        -- suppressed while the replacement is broken.
        Stop(state.health); Stop(state.cast); ReleaseImportant(state)
        state.castRunning = false
        error(err)
    end
end
function addon.ApplyRuleGlows(plate, style)
    local state = states[plate]
    if not state then
        if not Spec(style, "health") and not Spec(style, "cast") then return end
        state = { sizes = { health = {}, cast = {} } }
        states[plate] = state
    end
    state.style, state.unit = style, plate.unit
    Apply(plate, state)
end
function addon.InstallGlowHooks(plate)
    if hooked[plate] then return end
    hooked[plate] = true
    for _, prefix in ipairs({ "health", "cast" }) do
        local bar = prefix == "health" and plate.health or plate.cast
        if bar then
            for _, method in ipairs({ "SetSize", "SetWidth", "SetHeight", "Show", "Hide", "SetShown" }) do
                if type(bar[method]) == "function" then
                    hooksecurefunc(bar, method, function(_, a, b)
                        local state = states[plate]
                        if not state then return end
                        local size = state.sizes[prefix]
                        if (method == "SetSize" or method == "SetWidth") and not Secret(a) and type(a) == "number" then size.width = Number(a, 180, 1, 2000) end
                        local height = method == "SetHeight" and a or method == "SetSize" and b
                        if not Secret(height) and type(height) == "number" then size.height = Number(height, 17, 1, 2000) end
                        Apply(plate, state)
                    end)
                end
            end
        end
    end
    for _, method in ipairs({ "UpdateCast", "ApplyAppearance", "UpdateImportantCastGlow", "ClearImportantCastGlow" }) do
        if type(plate[method]) == "function" then
            hooksecurefunc(plate, method, function()
                local state = states[plate]
                if state then Apply(plate, state) end
            end)
        end
    end
end
addon.GetRuleGlowFrames = function(plate)
    local state = states[plate]
    if state then return state.health, state.cast end
end
