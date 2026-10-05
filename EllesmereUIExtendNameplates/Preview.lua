local api = EllesmereUIExtendNameplates
local function Number(value, fallback, min, max)
    if issecretvalue and issecretvalue(value) or type(value) ~= "number" or value ~= value then return fallback end
    return math.max(min, math.min(max, value))
end
local function Visible(frame)
    if not frame.IsVisible then return true end
    local ok, value = pcall(frame.IsVisible, frame)
    return ok and not (issecretvalue and issecretvalue(value)) and value == true
end
function api.BuildRulePreview(parent, parentWidth, getRule, locked)
    if EllesmereUI.IsSearchPrebuild() then return 0 end
    local PP = EllesmereUI.PanelPP
    local preview = CreateFrame("Frame", nil, parent)
    preview:SetPoint("TOPLEFT", parent, "TOPLEFT")
    preview:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
    preview:SetHeight(150)
    parent._extrasRulePreview = preview
    local title = EllesmereUI.MakeFont(preview, 12, nil, 1, 1, 1)
    PP.Point(title, "TOP", preview, "TOP", 0, -12)
    title:SetAlpha(0.7); title:SetWordWrap(false); title:SetMaxLines(1)
    local plate = CreateFrame("Frame", nil, preview)
    PP.Point(plate, "CENTER", preview, "CENTER", 0, -8)
    preview.plate, preview.title, preview.elapsed = plate, title, 0

    local function Bar()
        local surface = CreateFrame("Frame", nil, plate)
        local appearance = CreateFrame("Frame", nil, surface)
        appearance:SetAllPoints(surface)
        local bar = CreateFrame("StatusBar", nil, appearance)
        bar:SetAllPoints(appearance)
        bar:SetMinMaxValues(0, 100)
        local background = bar:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(bar)
        local border = CreateFrame("Frame", nil, appearance)
        border:SetAllPoints(bar); border:SetFrameLevel(bar:GetFrameLevel() + 1)
        local glow = CreateFrame("Frame", nil, appearance)
        glow:SetAllPoints(bar); glow:SetFrameLevel(bar:GetFrameLevel() + 2); glow:EnableMouse(false)
        surface._bar, surface._appearance, surface._border, surface._glow, surface._background = bar, appearance, border, glow, background
        return surface
    end
    local health, cast = Bar(), Bar()
    preview.health, preview.cast = health, cast
    health._bar:SetValue(75)
    local textHost = CreateFrame("Frame", nil, plate)
    textHost:SetAllPoints(health._bar)
    textHost:SetFrameLevel(health._bar:GetFrameLevel() + 3)
    local level = EllesmereUI.MakeFont(textHost, 12, nil, 1, 1, 1)
    local name = EllesmereUI.MakeFont(textHost, 12, nil, 1, 1, 1)
    local hp = EllesmereUI.MakeFont(textHost, 12, nil, 1, 1, 1)
    level:SetText("22"); name:SetText(EllesmereUI.L("Enemy Name")); hp:SetText("6,600")
    PP.Point(level, "LEFT", textHost, "LEFT", 3, 0)
    PP.Point(name, "LEFT", textHost, "LEFT", 24, 0)
    PP.Point(hp, "RIGHT", textHost, "RIGHT", -3, 0)
    name:SetWordWrap(false); name:SetMaxLines(1)
    preview.textHost, preview.name, preview.level, preview.hp = textHost, name, level, hp
    local castText = CreateFrame("Frame", nil, cast._appearance)
    castText:SetAllPoints(cast._bar); castText:SetFrameLevel(cast._bar:GetFrameLevel() + 3)
    local spell = EllesmereUI.MakeFont(castText, 12, nil, 1, 1, 1)
    local timer = EllesmereUI.MakeFont(castText, 12, nil, 1, 1, 1)
    spell:SetText(EllesmereUI.L("Sample Spell")); spell:SetWordWrap(false); spell:SetMaxLines(1)
    PP.Point(spell, "LEFT", castText, "LEFT", 3, 0); PP.Point(timer, "RIGHT", castText, "RIGHT", -3, 0)
    preview.spell, preview.timer, preview.castTextHost = spell, timer, castText
    local arrowHost = CreateFrame("Frame", nil, plate)
    arrowHost:SetAllPoints(plate)
    local left, right = arrowHost:CreateTexture(nil, "OVERLAY"), arrowHost:CreateTexture(nil, "OVERLAY")
    preview.arrows = { host = arrowHost, left = left, right = right }
    PP.Point(left, "RIGHT", health._bar, "LEFT", -8, 0)
    PP.Point(right, "LEFT", health._bar, "RIGHT", 8, 0)

    local busy, building, headerHeight = false, true, 150
    local function Stop()
        preview:SetScript("OnUpdate", nil)
        api.StopRuleGlowPreview(health._glow); api.StopRuleGlowPreview(cast._glow)
    end
    local function Tick(_, elapsed)
        preview.elapsed = (preview.elapsed + Number(elapsed, 0, 0, 3600)) % 3
        cast._bar:SetValue(preview.elapsed / 3 * 100)
        timer:SetText(("%.1fs"):format(3 - preview.elapsed))
        if api.TickRuleTextPreview then api.TickRuleTextPreview(preview) end
    end
    local function Update(forceHeight)
        if busy then return headerHeight end
        if not Visible(preview) then Stop(); return headerHeight end
        busy = true
        local ok, err = pcall(function()
            parent._extrasRulePreview = preview -- restored header-cache child becomes current again
            local rule, index = getRule()
            local style = rule.style or {}
            local np = EllesmereNameplates_NS or {}
            local profile, defaults = np.db and np.db.profile or {}, np.defaults or {}
            local castDefaults = api.CastStyleDefaults or {}
            local function Setting(key, fallback)
                if profile[key] ~= nil then return profile[key] end
                if defaults[key] ~= nil then return defaults[key] end
                return fallback
            end
            local function Metric(getter, key, fallback)
                local value
                if type(np[getter]) == "function" then
                    local valid, result = pcall(np[getter]); if valid then value = result end
                end
                if type(value) == "nil" then value = Setting(key, fallback) end
                return Number(value, fallback, 1, 2000)
            end
            local width = Metric("GetHealthBarWidth", "healthBarWidth", 180)
            local healthHeight = Metric("GetHealthBarHeight", "healthBarHeight", 14)
            local castHeight = Metric("GetCastBarHeight", "castBarHeight", 17)
            local castWidth = width
            local classic = np.NP_Classic and np.NP_Classic()
            if not (issecretvalue and issecretvalue(classic)) and classic == true and np.NP_ClassicCastLayout then
                local valid, _, w = pcall(np.NP_ClassicCastLayout, width, healthHeight, castHeight)
                if valid then castWidth = Number(w, width, 1, 2000) end
            elseif Setting("castbarIconInWidth", false) and Setting("showCastIcon", true) and not Setting("castIconFullSize", false) then
                castWidth = math.max(1, width - castHeight * Number(Setting("castIconScale", 1), 1, 0.1, 5))
            end
            local factor = Number(tonumber(style.scale), 100, 50, 200) / 100
            local function Factor(key) return api.IsScaleElementEnabled(style, key) and factor or 1 end
            local other, healthScale, castScale, textScale = Factor("other"), Factor("healthBar"), Factor("castBar"), Factor("text")
            local uiScale = UIParent and Number(UIParent:GetEffectiveScale(), 1, 0.1, 10) or 1
            local ratio = uiScale / Number(parent:GetEffectiveScale(), 1, 0.1, 10)
            local available = Number(parent:GetWidth(), parentWidth or 800, 100, 4000)
            local spec = api.GetTargetArrowStyle(style.targetArrowsEnabled == true and style.targetArrowStyle or "eui")
            local showArrows = spec and (style.targetArrowsEnabled == true or Setting("showTargetArrows", false))
            local arrowScale = Number(Setting("targetArrowScale", 1), 1, 0.1, 5)
            local arrowWidth = showArrows and (spec.w * arrowScale + 8) * 2 * other or 0
            ratio = ratio * math.min(1, (available - 64) / ((math.max(width * healthScale, castWidth * castScale) + arrowWidth) * ratio))
            local gap = math.max(1, 4 - Number(Setting("castBarOffsetY", 0), 0, -50, 50))
            local total = healthHeight * healthScale + (castHeight + gap) * castScale
            plate:SetScale(ratio * other)
            PP.Size(plate, math.max(width * healthScale, castWidth * castScale) / other, total / other)
            health:SetScale(healthScale / other); cast:SetScale(castScale / other)
            PP.Size(health, width, healthHeight); PP.Size(cast, castWidth, castHeight)
            health:ClearAllPoints(); cast:ClearAllPoints()
            PP.Point(health, "TOP", plate, "TOP", 0, 0)
            PP.Point(cast, "TOP", health._bar, "BOTTOM", 0, -gap)
            local dim = locked() and 0.3 or 1
            local opacity = Number(tonumber(style.opacity), 100, 0, 100) / 100
            health:SetAlpha(dim); cast:SetAlpha(dim)
            textHost:SetScale(textScale / other); textHost:SetAlpha(dim * opacity)
            local path = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("nameplates") or "Fonts\\FRIZQT__.TTF"
            local fontSize = Number(Setting("textSlotCenterSize", 12), 12, 8, 32)
            for _, font in ipairs({ level, name, hp, spell, timer }) do font:SetFont(path, fontSize, "OUTLINE") end
            name:SetWidth(math.max(20, width - 90) * healthScale / textScale)
            spell:SetWidth(math.max(20, castWidth - 55))
            title:SetWidth(available - 40)
            title:SetText(EllesmereUI.L("Preview") .. ": [" .. (index or 1) .. "] " .. (rule.name or "Unnamed Rule"))
            for prefix, surface in pairs({ health = health, cast = cast }) do
                local isCast = prefix == "cast"
                local enabled = isCast and style.castEnabled == true or not isCast and style.healthEnabled ~= false
                local texture = enabled and (isCast and style.castTexture or not isCast and style.texture) or "eui"
                if not texture or texture == "eui" then texture = Setting(isCast and "castBarTexture" or "healthBarTexture", "none") end
                local fill = "Interface\\Buttons\\WHITE8x8"
                if texture ~= "flat" then
                    local paths = np.healthBarTextures or {}
                    fill = EllesmereUI.ResolveTexturePath and EllesmereUI.ResolveTexturePath(paths, texture, fill) or paths[texture] or fill
                end
                surface._bar:SetStatusBarTexture(fill)
                local color = Setting(isCast and "castBar" or "enemyInCombat", isCast and { r = 0.7, g = 0.4, b = 0.9 } or { r = 0.8, g = 0.14, b = 0.14 })
                if enabled and isCast and style.castColorEnabled == true then
                    color = style.castColor or castDefaults.castColor or color
                elseif enabled and not isCast and style.healthColorEnabled ~= false then
                    color = style.healthColor or color
                end
                surface._bar:SetStatusBarColor(color.r, color.g, color.b, 1)
                local bg = Setting(isCast and "castBgColor" or "bgColor", { r = 0.12, g = 0.12, b = 0.12 })
                surface._background:SetColorTexture(bg.r, bg.g, bg.b, Setting(isCast and "castBgAlpha" or "bgAlpha", 1))
                local alpha = opacity
                if isCast and enabled and style.castOpacityEnabled then alpha = alpha * Number(tonumber(style.castOpacity), 100, 0, 100) / 100 end
                surface._appearance:SetAlpha(alpha)
                local size = enabled and (isCast and style.castBorderEnabled and (style.castBorderSize or 2)
                    or not isCast and style.borderEnabled ~= false and (style.borderSize or 0)) or 0
                size = Number(size, 0, 0, 8)
                local borderColor, borderTexture, native = Setting(isCast and "castBorderColor" or "borderColor", { r = 0, g = 0, b = 0 }), "solid"
                if size > 0 then
                    borderColor = (isCast and style.castBorderColor or not isCast and style.borderColor)
                        or (isCast and castDefaults.castBorderColor) or { r = 1, g = 1, b = 1 }
                    borderTexture = (isCast and style.castBorderTexture or not isCast and style.borderTexture) or "solid"
                elseif not isCast and Setting("customBorderEnabled", false) then
                    native = profile
                    size, borderTexture = Setting("customBorderSize", 1), Setting("customBorderTexture", "solid")
                    local c = Setting("customBorderColor", borderColor)
                    borderColor = { r = c.r, g = c.g, b = c.b, a = Setting("customBorderAlpha", 1) }
                else size = isCast and Setting("castBorderSize", 0) or (Setting("showBorder", true) and Setting("borderSize", 1) or 0) end
                api.RenderBorderStyle(surface._border, size, borderColor, borderTexture, false, native)
                api.RenderRuleGlowPreview(surface._glow, style, prefix, isCast and castWidth or width, isCast and castHeight or healthHeight)
            end
            arrowHost:SetAlpha(dim * opacity)
            if showArrows then
                local r, g, b = 1, 1, 1
                if np.GetTargetArrowColor then r, g, b = np.GetTargetArrowColor(profile) end
                left:SetTexture(np.TARGET_ARROW_DIR .. spec.l .. ".png"); right:SetTexture(np.TARGET_ARROW_DIR .. spec.r .. ".png")
                for _, arrow in ipairs({ left, right }) do PP.Size(arrow, spec.w * arrowScale, 16 * arrowScale); arrow:SetVertexColor(r, g, b); arrow:Show() end
            else left:Hide(); right:Hide() end
            local h = math.max(150, math.ceil((total + 48 * math.max(other, healthScale, castScale, textScale)) * ratio + 32))
            preview:SetHeight(h)
            if not building and (headerHeight ~= h or forceHeight == true) and EllesmereUI.UpdateContentHeaderHeight then EllesmereUI:UpdateContentHeaderHeight(h) end
            headerHeight = h
            Tick(preview, 0)
            if api.UpdateRuleTextPreview then api.UpdateRuleTextPreview(preview, style) end
            preview:SetScript("OnUpdate", Tick)
        end)
        busy = false
        if not ok then Stop(); error(err) end
        return headerHeight
    end
    preview.Update = Update
    health._refresh, cast._refresh = Update, Update
    preview:SetScript("OnHide", Stop)
    preview:SetScript("OnShow", Update)
    preview:SetScript("OnSizeChanged", Update)
    Update()
    building = false
    return headerHeight, preview
end
