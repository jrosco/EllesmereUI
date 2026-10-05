local _, addon = ...
local api = EllesmereUIExtendNameplates
local states = setmetatable({}, { __mode = "k" })
local hidden = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local Apply

function api.SupportsBorderStyles()
    return EllesmereUI and type(EllesmereUI.ApplyBorderStyle) == "function"
        and type(EllesmereUI.GetBorderTextureDropdown) == "function" or false
end
function api.GetBorderStyleOptions()
    if api.SupportsBorderStyles() then return EllesmereUI.GetBorderTextureDropdown() end
    return { solid = "Solid" }, { "solid" }
end
function api.ValidateBorderStyle(key)
    if key == nil then return true end
    if type(key) ~= "string" or #key == 0 or #key > 256 or key:find("%c") then return false end
    -- SharedMedia names can be unavailable on the recipient's client. Keep
    -- their keys for sharing; the shared renderer resolves them at runtime.
    if key:match("^sm:.+") then return true end
    local values = api.GetBorderStyleOptions()
    return key == "solid" or values[key] ~= nil
end
function addon.RenderBorderStyle(frame, size, color, texture, guarded, native)
    if not api.SupportsBorderStyles() then return end
    -- EUI's textured media sizes are four registered steps; solid sizes are
    -- pixel thicknesses. Preserve legacy solid rules up to eight pixels.
    if texture and texture ~= "solid" then size = math.min(4, size) end
    local px
    if native and EllesmereUI.BorderPx then px = EllesmereUI.BorderPx(native.customBorderSizePx, size, texture) end
    EllesmereUI.ApplyBorderStyle(frame, size, color.r, color.g, color.b, color.a or 1,
        texture or "solid", native and native.customBorderOffset, native and native.customBorderOffsetY,
        native and native.customBorderShiftX, native and native.customBorderShiftY, "nameplates", size, nil, px)
    local PP = EllesmereUI.PP
    if guarded and PP and PP.GetBorders and PP.CreateBorder and PP.GetBorders(frame) then
        PP.CreateBorder(frame, nil, nil, nil, nil, nil, nil, nil, true)
    end
end
api.RenderBorderStyle = addon.RenderBorderStyle

local function Suppress(object, owner)
    if not object or type(object.SetAlpha) ~= "function" then return end
    local entry = hidden[object]
    if not entry then
        entry = { alpha = object:GetAlpha() }
        hidden[object] = entry
        hooksecurefunc(object, "SetAlpha", function(self, alpha)
            if entry.writing then return end
            entry.alpha = alpha -- may be secret: only forward to a setter
            if entry.owner then
                entry.writing = true; self:SetAlpha(0); entry.writing = nil
            end
        end)
        -- Textures' vertex alpha shares state with SetAlpha. Stock backgrounds
        -- may be repainted while suppressed; retain the latest engine alpha.
        for _, method in ipairs({ "SetVertexColor", "SetColorTexture" }) do
            if type(object[method]) == "function" then
                hooksecurefunc(object, method, function(self)
                    if entry.writing or not entry.owner then return end
                    entry.alpha = self:GetAlpha()
                    entry.writing = true; self:SetAlpha(0); entry.writing = nil
                end)
            end
        end
    end
    entry.owner = owner
    owner.suppressed[object] = true
    entry.writing = true; object:SetAlpha(0); entry.writing = nil
end
local function Release(state)
    for object in pairs(state.suppressed) do
        local entry = hidden[object]
        if entry and entry.owner == state then
            entry.owner, entry.writing = nil, true
            object:SetAlpha(entry.alpha)
            entry.writing = nil
        end
        state.suppressed[object] = nil
    end
end
local function NativeBorders(plate, state, health, cast)
    local PP = EllesmereUI.PP
    local function Basic(bar)
        if PP and PP.GetBorders and bar then Suppress(PP.GetBorders(bar), state) end
    end
    if health then
        Basic(plate.health)
        Suppress(plate._customBorder, state)
        Suppress(plate._classicHealthHost, state)
        if plate._blizzBarBg then Suppress(plate.healthBG, state) end
    end
    if cast then
        Basic(plate.cast)
        Suppress(plate._classicCastHost, state)
        if plate._blizzCastArt then Suppress(plate.castBG, state) end
    end
    if health or cast then
        Suppress(plate.castWrapRegion, state)
        Suppress(plate._cbWrapLower, state)
    end
end
local function Host(plate, state, key, bar)
    local frame = state[key]
    if not frame then
        frame = CreateFrame("Frame", nil, bar)
        frame:SetAllPoints(bar)
        state[key] = frame
    end
    -- Match native Custom Border's MEDIUM escape from the nameplate's
    -- flattened health render layers. Lifted casts retain their HIGH tier.
    frame:SetFrameStrata(key == "cast" and plate._castOverlayLifted and bar:GetFrameStrata() or "MEDIUM")
    frame:SetFrameLevel(bar:GetFrameLevel() + 1)
    return frame
end
local function StockBackground(plate, state, key, on)
    local stock = key == "health" and plate._blizzBarBg or key == "cast" and plate._blizzCastArt
    local texture = state[key .. "Background"]
    if not on or not stock then if texture then texture:Hide() end; return end
    local bar = key == "health" and plate.health or plate.cast
    if not texture then
        texture = bar:CreateTexture(nil, "BACKGROUND")
        texture:SetAllPoints(bar)
        state[key .. "Background"] = texture
    end
    local np = _G.EllesmereNameplates_NS or {}
    local profile, defaults = np.db and np.db.profile or {}, np.defaults or {}
    local colorKey, alphaKey = key == "health" and "bgColor" or "castBgColor", key == "health" and "bgAlpha" or "castBgAlpha"
    local c = profile[colorKey] or defaults[colorKey] or { r = 0.12, g = 0.12, b = 0.12 }
    texture:SetColorTexture(c.r, c.g, c.b, profile[alphaKey] or defaults[alphaKey] or 1)
    texture:Show()
end
Apply = function(plate, state)
    if state.busy then return end
    state.busy = true
    local ok, err = pcall(function()
        local style = state.style
        local health = style and style.healthEnabled ~= false and style.borderEnabled ~= false
            and math.max(0, math.min(8, tonumber(style.borderSize) or 0)) or 0
        local cast = style and style.castEnabled == true and style.castBorderEnabled == true and plate.cast
            and math.max(0, math.min(8, tonumber(style.castBorderSize) or 2)) or 0
        health, cast = health > 0, cast > 0
        if not api.SupportsBorderStyles() then health, cast = false, false end
        -- Release when a category turns off; keep EUI's current size, texture,
        -- tint, visibility and target/threat effects underneath, not snapshots.
        local changed = health ~= state.healthActive or cast ~= state.castActive
        if changed then
            Release(state)
            if state.castActive and not cast and type(plate.UpdateBorderWrap) == "function" then plate:UpdateBorderWrap() end
        end
        state.healthActive, state.castActive = health, cast
        local np = _G.EllesmereNameplates_NS
        -- Independent cast overrides must not leave a native custom health
        -- outline spanning both bars. Native wrap can reconstruct on release.
        if cast and not health then
            if plate._cbWrapActive and np and np.NP_UnwrapCustomBorder then np.NP_UnwrapCustomBorder(plate) end
            local PP = EllesmereUI.PP
            local hb = PP and PP.GetBorders and PP.GetBorders(plate.health)
            if hb and hb._hideBottom then
                hb._hideBottom = nil
                local size = np and np.NP_BorderSize and np.NP_BorderSize() or 1
                if plate._targetBorderSized and np.GetTargetBorderSizeValue then size = np.GetTargetBorderSizeValue() or size end
                if PP.SetBorderSize then PP.SetBorderSize(plate.health, size) end
            end
        end
        NativeBorders(plate, state, health, cast)
        StockBackground(plate, state, "health", health)
        StockBackground(plate, state, "cast", cast)
        if health then
            local host = Host(plate, state, "health", plate.health)
            addon.RenderBorderStyle(host, math.max(1, math.min(8, tonumber(style.borderSize) or 1)),
                style.borderColor or { r = 1, g = 1, b = 1 }, style.borderTexture, true)
        elseif state.health then
            if EllesmereUI and EllesmereUI.ApplyBorderStyle then EllesmereUI.ApplyBorderStyle(state.health, 0) else state.health:Hide() end
        end
        if cast then
            local host = Host(plate, state, "cast", plate.cast)
            addon.RenderBorderStyle(host, math.max(1, math.min(8, tonumber(style.castBorderSize) or 2)),
                style.castBorderColor or { r = 1, g = 1, b = 1 }, style.castBorderTexture, true)
        elseif state.cast then
            if EllesmereUI and EllesmereUI.ApplyBorderStyle then EllesmereUI.ApplyBorderStyle(state.cast, 0) else state.cast:Hide() end
        end
    end)
    state.busy = nil
    if not ok then error(err) end
end
function addon.ApplyRuleBorders(plate, style)
    local state = states[plate]
    if not state then
        if not style then return end
        state = { suppressed = setmetatable({}, { __mode = "k" }) }
        states[plate] = state
    end
    state.style = style
    Apply(plate, state)
end
function addon.InstallBorderHooks(plate)
    if hooked[plate] then return end
    hooked[plate] = true
    for _, method in ipairs({ "ApplyBorder", "ApplyBorderColor", "ApplyCastBorder", "ApplyCastBorderColor",
        "ApplyTarget", "UpdateBorderWrap", "ApplyAppearance", "UpdateCast" }) do
        if type(plate[method]) == "function" then
            hooksecurefunc(plate, method, function()
                local state = states[plate]
                if state and (state.healthActive or state.castActive) then Apply(plate, state) end
            end)
        end
    end
end
addon.GetRuleBorderFrames = function(plate)
    local state = states[plate]
    if state then return state.health, state.cast end
end
