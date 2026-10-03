local _, addon = ...
local states = setmetatable({}, { __mode = "k" })
local defaults = {
    castColor = { r = 1, g = 0.7, b = 0.15 },
    castBorderColor = { r = 1, g = 1, b = 1 },
    castBorderSize = 2,
    castOpacity = 100,
}
local textures = {
    flat = "Interface\\Buttons\\WHITE8x8",
    blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
}
EllesmereUINameplateExtras.CastStyleDefaults = defaults

local function PaintColor(plate, state, texture, entry)
    local style = state.style
    local override = style and style.castColorEnabled and not plate._interrupted
    if not override and not entry.owned then return end
    state.writing = true
    if override then
        local color = style.castColor or defaults.castColor
        texture:SetVertexColor(color.r, color.g, color.b, entry.color[4])
    else
        texture:SetVertexColor(unpack(entry.color))
    end
    state.writing = nil
    entry.owned = override and true or false
end

local function WatchColor(plate, state, texture)
    if not texture then return end
    local entry = state.colors[texture]
    if entry then return entry end
    local r, g, b, a = texture:GetVertexColor()
    if type(a) == "nil" then a = 1 end
    entry = { color = { r, g, b, a } }
    state.colors[texture] = entry
    hooksecurefunc(texture, "SetVertexColor", function(self, cr, cg, cb, ca)
        if state.writing then return end
        if type(ca) == "nil" then ca = 1 end
        -- Engine colors can be secret on Retail. Store/pass them without comparisons.
        entry.color = { cr, cg, cb, ca }
        if self == plate.cast:GetStatusBarTexture() or self == plate.castBarOverlay then
            PaintColor(plate, state, self, entry)
        end
    end)
    return entry
end

local function ApplyOpacity(plate, state)
    local style = state.style
    local override = style and style.castOpacityEnabled
    if not override and not state.opacityOwned then return end
    local factor = override and math.max(0, math.min(100, tonumber(style.castOpacity) or defaults.castOpacity)) / 100 or 1
    state.writing = true
    plate.cast:SetAlpha(state.baseAlpha * factor)
    state.writing = nil
    state.opacityOwned = override and true or false
end

function addon.ApplyCastStyle(plate, style)
    local cast = plate.cast
    if not cast then return end -- EUI friendly/name-only plates have no cast bar.
    if not (style and style.castEnabled) then style = nil end
    local state = states[plate]
    if not state then
        if not style then return end
        local fill = cast:GetStatusBarTexture()
        state = {
            colors = setmetatable({}, { __mode = "k" }),
            baseTexture = fill and fill:GetTexture(),
            baseOverlay = plate.castBarOverlay and plate.castBarOverlay:GetTexture(),
            baseAlpha = cast:GetAlpha(),
        }
        states[plate] = state
        hooksecurefunc(cast, "SetAlpha", function(_, alpha)
            if state.writing then return end
            state.baseAlpha = alpha
            ApplyOpacity(plate, state)
        end)
    end
    state.style = style
    local fill = cast:GetStatusBarTexture()
    local engineFill, previousFill = fill, state.fill or fill
    local fillEntry = WatchColor(plate, state, fill)
    local overlay = plate.castBarOverlay
    local overlayEntry = WatchColor(plate, state, overlay)
    -- Stock artwork uses memoized atlases. Leave its texture ownership with EUI.
    local path = style and not plate._blizzCastArt and textures[style.castTexture]
    if path ~= state.appliedTexture and (path or state.appliedTexture) then
        local baseColor = fillEntry and fillEntry.color
        state.writing = true
        cast:SetStatusBarTexture(path or state.baseTexture)
        if overlay then overlay:SetTexture(path or state.baseOverlay) end
        state.writing = nil
        state.appliedTexture = path or nil
        local newFill = cast:GetStatusBarTexture()
        if newFill ~= fill then
            fill = newFill
            fillEntry = WatchColor(plate, state, fill)
            if baseColor then fillEntry.color = baseColor end
        end
        if baseColor then
            state.writing = true
            fill:SetVertexColor(unpack(baseColor))
            state.writing = nil
        end
    end
    if fill ~= previousFill then
        -- EUI may replace the fill before our texture hook runs. Track the prior
        -- object as well so its spark/overlay anchors do not stay on a stale fill.
        if overlay then overlay:SetAllPoints(fill) end
        if plate.castSpark then
            local anchors = {}
            for i = 1, plate.castSpark:GetNumPoints() do
                anchors[i] = { plate.castSpark:GetPoint(i) }
            end
            plate.castSpark:ClearAllPoints()
            for _, anchor in ipairs(anchors) do
                if anchor[2] == previousFill or anchor[2] == engineFill then anchor[2] = fill end
                plate.castSpark:SetPoint(unpack(anchor))
            end
        end
    end
    state.fill = fill
    if fillEntry then PaintColor(plate, state, fill, fillEntry) end
    if overlayEntry then PaintColor(plate, state, overlay, overlayEntry) end
    ApplyOpacity(plate, state)

    local borderSize = style and style.castBorderEnabled
        and math.max(0, math.min(8, tonumber(style.castBorderSize) or defaults.castBorderSize)) or 0
    if borderSize == 0 then
        if state.border then state.border:Hide() end
        return
    end
    if not state.border then
        -- Parenting to the cast also follows EUI's optional lifted cast container.
        state.border = CreateFrame("Frame", nil, cast)
        state.border:SetAllPoints(cast)
        state.edges = {}
        for i = 1, 4 do state.edges[i] = state.border:CreateTexture(nil, "OVERLAY") end
    end
    local border = state.border
    border:SetFrameLevel(cast:GetFrameLevel() + 5)
    local top, bottom, left, right = unpack(state.edges)
    top:ClearAllPoints(); top:SetPoint("TOPLEFT", border, "TOPLEFT", -borderSize, borderSize)
    top:SetPoint("TOPRIGHT", border, "TOPRIGHT", borderSize, borderSize); top:SetHeight(borderSize)
    bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", -borderSize, -borderSize)
    bottom:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", borderSize, -borderSize); bottom:SetHeight(borderSize)
    left:ClearAllPoints(); left:SetPoint("TOPLEFT", border, "TOPLEFT", -borderSize, 0)
    left:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", -borderSize, 0); left:SetWidth(borderSize)
    right:ClearAllPoints(); right:SetPoint("TOPRIGHT", border, "TOPRIGHT", borderSize, 0)
    right:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", borderSize, 0); right:SetWidth(borderSize)
    local color = style.castBorderColor or defaults.castBorderColor
    for _, edge in ipairs(state.edges) do edge:SetColorTexture(color.r, color.g, color.b, 1) end
    border:Show()
end

local NP = EllesmereNameplates_NS
if NP and NP.ApplyCastBarTexture then
    hooksecurefunc(NP, "ApplyCastBarTexture", function(plate)
        local state = states[plate]
        if not state or state.writing then return end
        local fill = plate.cast:GetStatusBarTexture()
        state.baseTexture = fill and fill:GetTexture()
        state.baseOverlay = plate.castBarOverlay and plate.castBarOverlay:GetTexture()
        state.appliedTexture = nil
        addon.ApplyCastStyle(plate, state.style)
    end)
end
