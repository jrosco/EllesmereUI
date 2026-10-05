local _, addon = ...
local states = setmetatable({}, { __mode = "k" })
local defaults = {
    castColor = { r = 1, g = 0.7, b = 0.15 },
    castBorderColor = { r = 1, g = 1, b = 1 },
    castBorderSize = 2,
    castOpacity = 100,
}
EllesmereUIExtendNameplates.CastStyleDefaults = defaults

local function ResolveTexturePath(key)
    if key == "eui" or key == nil then return nil end
    if key == "flat" then return "Interface\\Buttons\\WHITE8x8" end
    local np = _G.EllesmereNameplates_NS
    if EllesmereUI and EllesmereUI.ResolveTexturePath and np and np.healthBarTextures then
        return EllesmereUI.ResolveTexturePath(np.healthBarTextures, key, "Interface\\Buttons\\WHITE8x8")
    end
    return "Interface\\Buttons\\WHITE8x8"
end

local function PaintColor(plate, state, texture, entry)
    local colors = state.castColors
    local override = colors and next(colors) and not plate._interrupted
    local r, g, b = entry.color[1], entry.color[2], entry.color[3]
    if override then
        local function Color(candidate)
            return candidate and (candidate.style.castColor or defaults.castColor)
        end
        if colors.interruptible and colors.interruptible == colors.interruptOnCD
            and colors.interruptible == colors.uninterruptible then
            -- One all-casts rule does not depend on either secret boolean.
            local color = Color(colors.interruptible)
            r, g, b = color.r, color.g, color.b
        else
            local base = { r = r, g = g, b = b }
            local normal = Color(colors.interruptible) or base
            local onCD = Color(colors.interruptOnCD) or base
            local protectedColor = Color(colors.uninterruptible) or base
            local np = _G.EllesmereNameplates_NS
            local compute = (np and np.ComputeCastBarTint) or (EllesmereUI and EllesmereUI.ComputeCastBarTint)
            if compute then r, g, b = compute(onCD, normal)
            else r, g, b = normal.r, normal.g, normal.b end
            -- Match EUI precedence: cooldown folds first, uninterruptible wins.
            local protected = plate._kickProtected
            local evaluate = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
            if type(protected) ~= "boolean" then override = false
            elseif evaluate then
                r = evaluate(protected, protectedColor.r, r)
                g = evaluate(protected, protectedColor.g, g)
                b = evaluate(protected, protectedColor.b, b)
            elseif not (issecretvalue and issecretvalue(protected)) then
                if protected then r, g, b = protectedColor.r, protectedColor.g, protectedColor.b end
            else override = false end
        end
    end
    if not override and not entry.owned then return end
    state.writing = true
    if override then
        texture:SetVertexColor(r, g, b, entry.color[4])
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

function addon.ApplyCastStyle(plate, style, conditions, castColors)
    local cast = plate.cast
    if not cast then return end -- EUI friendly/name-only plates have no cast bar.
    if not (style and style.castEnabled) then style = nil end
    if castColors == nil then
        -- Preserve direct callers; the runtime supplies a separately prioritized palette.
        castColors = {}
        if style and style.castColorEnabled then
            local mask = addon.CastColorMask(conditions and conditions.castState)
            local candidate = { style = style }
            for key, selected in pairs(mask) do if selected then castColors[key] = candidate end end
        end
    end
    local state = states[plate]
    if not state then
        if not style and not next(castColors) then return end
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
        if type(plate.ApplyCastColor) == "function" then
            hooksecurefunc(plate, "ApplyCastColor", function()
                -- Interruptibility can flip without repainting the overlay RGB.
                -- Refresh both layers using the new raw stamp and saved base paint.
                local currentFill = cast:GetStatusBarTexture()
                local currentOverlay = plate.castBarOverlay
                local fillColor = state.colors[currentFill]
                local overlayColor = currentOverlay and state.colors[currentOverlay]
                if fillColor then PaintColor(plate, state, currentFill, fillColor) end
                if overlayColor then PaintColor(plate, state, currentOverlay, overlayColor) end
            end)
        end
    end
    state.style = style
    state.conditions = style and conditions or nil
    state.castColors = castColors
    local fill = cast:GetStatusBarTexture()
    local engineFill, previousFill = fill, state.fill or fill
    local fillEntry = WatchColor(plate, state, fill)
    local overlay = plate.castBarOverlay
    local overlayEntry = WatchColor(plate, state, overlay)
    -- Stock artwork uses memoized atlases. Leave its texture ownership with EUI.
    local path = style and not plate._blizzCastArt and ResolveTexturePath(style.castTexture)
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
        addon.ApplyCastStyle(plate, state.style, state.conditions, state.castColors)
    end)
end
