local _, addon = ...
local api = EllesmereUIExtendNameplates
local HEALTH = { "name", "level", "healthPercent", "healthCurrent", "healthMax", "healthCurrentMax", "targetOfTarget" }
local CAST = { "spellName", "castTarget", "castRemaining", "castElapsed", "castTotal", "castElapsedTotal" }
local LABELS = { name = "Name", level = "Level", healthPercent = "Health percentage", healthCurrent = "Current health",
    healthMax = "Maximum health", healthCurrentMax = "Current / maximum health", targetOfTarget = "Target of target",
    spellName = "Spell name", castTarget = "Cast target", castRemaining = "Remaining time", castElapsed = "Elapsed time",
    castTotal = "Total time", castElapsedTotal = "Elapsed / total time" }
local SLOTS = {
    { key = "textSlotTop", label = "Top text", anchor = "BOTTOM", point = "TOP", x = 0, y = 4 },
    { key = "textSlotLeft", label = "Left text", anchor = "LEFT", point = "LEFT", x = 4, y = 0 },
    { key = "textSlotCenter", label = "Center text", anchor = "CENTER", point = "CENTER", x = 0, y = 0 },
    { key = "textSlotRight", label = "Right text", anchor = "RIGHT", point = "RIGHT", x = -2, y = 0 },
    { key = "textSlotBottomLeft", label = "Bottom-left text", anchor = "TOPLEFT", point = "BOTTOMLEFT", x = 0, y = -2, bottom = true },
    { key = "textSlotBottomRight", label = "Bottom-right text", anchor = "TOPRIGHT", point = "BOTTOMRIGHT", x = 0, y = -2, bottom = true },
    { key = "castName", label = "Cast name text", cast = true, side = "left" },
    { key = "castTarget", label = "Cast target text", cast = true, side = "right" },
    { key = "castTimer", label = "Cast timer text", cast = true, side = "right" },
}
local validSlots, healthValues, castValues = {}, { eui = true, none = true }, { eui = true, none = true }
for _, slot in ipairs(SLOTS) do validSlots[slot.key] = slot end
for _, key in ipairs(HEALTH) do healthValues[key] = true end
for _, key in ipairs(CAST) do castValues[key] = true end
api.RuleTextSlots, api.RuleTextElements, api.RuleTextLabels = SLOTS, {}, LABELS
for _, group in ipairs({ HEALTH, CAST }) do for _, key in ipairs(group) do api.RuleTextElements[#api.RuleTextElements + 1] = key end end
function api.GetRuleTextChoices(cast)
    local values, order = { eui = "Use EUI setting", none = "None" }, { "eui", "none" }
    for _, key in ipairs(cast and CAST or HEALTH) do values[key] = LABELS[key]; order[#order + 1] = key end
    return values, order
end
function api.ValidateRuleText(style)
    local slots, colors = style.textSlots, style.textColors
    if slots ~= nil then
        if type(slots) ~= "table" then return false end
        for key, value in pairs(slots) do
            local slot = validSlots[key]
            if not slot or type(value) ~= "string" or not (slot.cast and castValues or healthValues)[value] then return false end
        end
    end
    if colors ~= nil then
        if type(colors) ~= "table" then return false end
        for key, color in pairs(colors) do
            if not LABELS[key] or type(color) ~= "table" then return false end
            for _, channel in ipairs({ "r", "g", "b" }) do
                local value = color[channel]
                if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then return false end
            end
        end
    end
    return true
end
local states, hooked = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local overlayHooks = setmetatable({}, { __mode = "k" })
local Apply
local function Secret(value) return issecretvalue and issecretvalue(value) end
local function Setting(key, fallback)
    local np = EllesmereNameplates_NS or {}
    local p, d = np.db and np.db.profile or {}, np.defaults or {}
    if p[key] ~= nil then return p[key] end
    if d[key] ~= nil then return d[key] end
    return fallback
end
local NATIVE = { enemyName = "name", levelName = "name", nameLevel = "name", healthNumber = "healthCurrent",
    healthPercentNoSign = "healthPercent", healthPctNum = "healthCurrent", healthNumPct = "healthCurrent",
    healthPctNumDash = "healthCurrent", healthNumPctDash = "healthCurrent" }
function api.ResolveRuleText(style, slot)
    local choice = style.textEnabled == true and type(style.textSlots) == "table" and style.textSlots[slot.key] or "eui"
    if choice == nil then choice = "eui" end
    if choice == "eui" then
        if slot.cast then
            if slot.key == "castTimer" then return Setting("showCastTimer", true) and "castRemaining" or "none" end
            if Setting(slot.key .. "Side", slot.side) == "none" then return "none" end
            return slot.key == "castName" and "spellName" or "castTarget"
        end
        local element = Setting(slot.key, slot.key == "textSlotTop" and "enemyName" or "none")
        return NATIVE[element] or element
    end
    return choice
end
local function NativeBindings(plate)
    local np = EllesmereNameplates_NS or {}
    local map = {}
    for _, slot in ipairs(SLOTS) do
        if slot.cast then map[slot.key] = plate[slot.key]
        else
            local el = np.GetTextSlot and np.GetTextSlot(slot.key) or Setting(slot.key, "none")
            local key = np.NP_ElementFSKey and np.NP_ElementFSKey(el)
            if not key then key = ({ name = "name", enemyName = "name", levelName = "name", nameLevel = "name",
                level = "levelText", healthPercent = "hpText", healthPercentNoSign = "hpText", healthNumber = "hpNumber",
                targetOfTarget = "totText" })[el] end
            if key == "name" and np.FindNameSlot and np.FindNameSlot() ~= slot.key then key = nil end
            if key then map[slot.key] = plate[key] end
        end
    end
    local cache = plate._cachedHealthSlots
    local owners = {}
    if cache then
        for index = 1, cache._count or #cache do
            local entry = cache[index]
            if entry and entry.fs and entry.slotKey then owners[entry.fs] = entry.slotKey end
        end
        for key, fs in pairs(map) do if owners[fs] and owners[fs] ~= key then map[key] = nil end end
    end
    return map
end
local function Watch(state, fs)
    local entry = state.native[fs]
    if entry then return entry end
    local r, g, b, a = fs:GetTextColor()
    entry = { color = { r, g, b, a }, alpha = fs:GetAlpha() }
    state.native[fs] = entry
    hooksecurefunc(fs, "SetTextColor", function(self, cr, cg, cb, ca)
        if entry.writing then return end
        entry.color = { cr, cg, cb, ca }
        if entry.tint then
            entry.writing = true; self:SetTextColor(entry.tint.r, entry.tint.g, entry.tint.b, 1); entry.writing = nil
        end
        if entry.hide then entry.writing = true; self:SetAlpha(0); entry.writing = nil end
    end)
    hooksecurefunc(fs, "SetAlpha", function(self, alpha)
        if entry.writing then return end
        entry.alpha = alpha
        if entry.hide then entry.writing = true; self:SetAlpha(0); entry.writing = nil end
    end)
    return entry
end
local function AlphaAndColor(fs, entry, hide, tint)
    entry.writing = true
    if tint then fs:SetTextColor(tint.r, tint.g, tint.b, 1)
    elseif entry.tint then fs:SetTextColor(unpack(entry.color)) end
    if hide or entry.hide then fs:SetAlpha(hide and 0 or entry.alpha) end
    entry.hide, entry.tint, entry.writing = hide, tint, nil
end
local function Abbrev(value)
    local np = EllesmereNameplates_NS or {}
    local fn = np.AbbreviateNumbers or AbbreviateNumbers
    if fn then local ok, result = pcall(fn, value); if ok and type(result) ~= "nil" then return result end end
    return value -- sent only to native SetFormattedText, never tostring(secret)
end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
end
local function CastTimes(unit)
    local dur = Call(UnitCastingDuration, unit)
    if type(dur) == "nil" then dur = Call(UnitEmpoweredChannelDuration, unit, true) end
    if type(dur) == "nil" then dur = Call(UnitChannelDuration, unit) end
    if type(dur) ~= "nil" then
        return Call(dur.GetRemainingDuration, dur), Call(dur.GetElapsedDuration, dur), Call(dur.GetTotalDuration, dur)
    end
    -- Forever: cast-info timestamps are plain numbers. Restricted timestamps
    -- never enter arithmetic, even on a client without duration-object APIs.
    local name, _, _, start, finish = UnitCastingInfo(unit)
    if type(name) == "nil" then name, _, _, start, finish = UnitChannelInfo(unit) end
    if Secret(start) or Secret(finish) or type(start) ~= "number" or type(finish) ~= "number" then return end
    local now = GetTime and GetTime() or start / 1000
    local total = math.max(0, (finish - start) / 1000)
    return math.max(0, finish / 1000 - now), math.max(0, math.min(total, now - start / 1000)), total
end
local function Write(fs, element, unit, sample)
    if element == "none" then fs:SetText(""); return end
    if sample then
        local values = { name = "Enemy Name", level = "22", healthPercent = "75%", healthCurrent = "6,600",
            healthMax = "8,800", healthCurrentMax = "6,600 / 8,800", targetOfTarget = "Target Name",
            spellName = "Sample Spell", castTarget = "Target Name" }
        if values[element] then fs:SetText(values[element]); return end
        local elapsed = sample.elapsed or 0
        local time = element == "castRemaining" and 3 - elapsed or element == "castTotal" and 3 or elapsed
        if element == "castElapsedTotal" then fs:SetFormattedText("%.1f / %.1f", elapsed, 3)
        else fs:SetFormattedText("%.1f", time) end
        return
    end
    if element == "name" or element == "targetOfTarget" then
        local value = Call(UnitName, element == "name" and unit or unit .. "target")
        if type(value) == "nil" then value = "" end
        fs:SetText(value)
    elseif element == "level" then
        local np = EllesmereNameplates_NS or {}
        local value = Call(np.GetUnitLevelText, unit)
        if type(value) == "nil" then
            value = Call(UnitEffectiveLevel or UnitLevel, unit)
            if Secret(value) or type(value) ~= "number" or value < 0 then value = "??" end
        end
        fs:SetText(value)
    elseif element == "healthPercent" then
        local pct
        if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then pct = Call(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100) end
        if type(pct) == "nil" then
            local cur, max = Call(UnitHealth, unit), Call(UnitHealthMax, unit)
            if not Secret(cur) and not Secret(max) and type(cur) == "number" and type(max) == "number" and max > 0 then pct = cur / max * 100 end
        end
        if type(pct) == "nil" then fs:SetText("") else fs:SetFormattedText("%.0f%%", pct) end
    elseif element == "healthCurrent" or element == "healthMax" or element == "healthCurrentMax" then
        local cur, max = Call(UnitHealth, unit), Call(UnitHealthMax, unit)
        if element == "healthCurrentMax" and type(cur) ~= "nil" and type(max) ~= "nil" then fs:SetFormattedText("%s / %s", Abbrev(cur), Abbrev(max))
        else
            local value = cur
            if element == "healthMax" then value = max end
            if element == "healthCurrentMax" then value = nil end
            if type(value) == "nil" then fs:SetText("") else fs:SetFormattedText("%s", Abbrev(value)) end
        end
    elseif element == "spellName" then
        local value = UnitCastingInfo(unit)
        if type(value) == "nil" then value = UnitChannelInfo(unit) end
        if type(value) == "nil" then value = "" end
        fs:SetText(value)
    elseif element == "castTarget" then
        local allowed = Call(UnitShouldDisplaySpellTargetName, unit)
        if Secret(allowed) or allowed == false then fs:SetText(""); return end
        local value = Call(UnitSpellTargetName, unit)
        if type(value) == "nil" then value = "" end
        fs:SetText(value)
    else
        local remaining, elapsed, total = CastTimes(unit)
        if element == "castElapsedTotal" then
            if type(elapsed) == "nil" or type(total) == "nil" then fs:SetText("") else fs:SetFormattedText("%.1f / %.1f", elapsed, total) end
        else
            local value = remaining
            if element == "castElapsed" then value = elapsed elseif element == "castTotal" then value = total end
            if type(value) == "nil" then fs:SetText("") else fs:SetFormattedText("%.1f", value) end
        end
    end
end
api.WriteRuleText = Write
local function Position(fs, plate, slot, sample, style)
    local np = EllesmereNameplates_NS or {}
    local PP = EllesmereUI.PP
    local x, y = Setting(slot.key .. (slot.cast and "OffsetX" or "XOffset"), 0), Setting(slot.key .. (slot.cast and "OffsetY" or "YOffset"), 0)
    fs:ClearAllPoints()
    if slot.cast then
        local side = Setting(slot.key .. "Side", slot.side)
        if side == "none" then side = slot.side end
        local pt, ox, justify = side == "right" and "RIGHT" or "LEFT", side == "right" and -3 or 3, side == "right" and "RIGHT" or "LEFT"
        local timer = style and api.ResolveRuleText(style, validSlots.castTimer) or "castRemaining"
        local reserve = Setting("castTimerSize", 10) * (timer == "castElapsedTotal" and 6 or 2.2)
        local pushed = slot.key ~= "castTimer" and timer ~= "none" and Setting("castTimerSide", "right") == side
        if np.GetCastTextAnchor then pt, ox, justify = np.GetCastTextAnchor(side, pushed, reserve, slot.key == "castTimer")
        elseif pushed then ox = side == "right" and ox - reserve or ox + reserve end
        fs:SetPoint(pt, plate.cast, pt, ox + x, y); fs:SetJustifyH(justify)
    else
        if slot.bottom and sample then
            fs:SetPoint(slot.anchor, plate.cast, slot.point, slot.x + x, -2 + y)
            fs:SetJustifyH(slot.key == "textSlotBottomLeft" and "LEFT" or "RIGHT")
        else
            if slot.key == "textSlotTop" then
                y = y + Setting("nameYOffset", 0)
                local push = not sample and Call(np.NP_ClassPowerTopPush, plate)
                if not Secret(push) and type(push) == "number" then y = y + push end
            elseif slot.bottom then
                local visible = plate.cast and Call(plate.cast.IsShown, plate.cast)
                if not Secret(visible) and visible == true then
                    local drop = plate._castDrop
                    if Secret(drop) or type(drop) ~= "number" then drop = -Setting("castBarHeight", 17) - 4 end
                    y = y + drop
                end
            end
            if PP and PP.Point and not sample then PP.Point(fs, slot.anchor, plate.health, slot.point, slot.x + x, slot.y + y)
            else fs:SetPoint(slot.anchor, plate.health, slot.point, slot.x + x, slot.y + y) end
            fs:SetJustifyH(slot.bottom and (slot.key == "textSlotBottomLeft" and "LEFT" or "RIGHT") or slot.anchor == "CENTER" and "CENTER" or slot.anchor == "BOTTOM" and "CENTER" or slot.anchor)
        end
    end
    local size = Setting(slot.key .. "Size", 12)
    if np.SetFSFont and not sample then np.SetFSFont(fs, size)
    else fs:SetFont(EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("nameplates") or "Fonts\\FRIZQT__.TTF", size, "OUTLINE") end
    local wrap = not slot.bottom and Setting(slot.key .. "Wrap", false) == true
    fs:SetWordWrap(wrap); fs:SetMaxLines(wrap and 2 or 1)
    local width = Call(np.GetHealthBarWidth)
    if Secret(width) or type(width) ~= "number" then width = 180 end
    local percent = Setting(slot.key .. "WidthPct", 100)
    if slot.bottom or slot.key == "castTimer" then fs:SetWidth(0) else fs:SetWidth(width * percent / 100) end
end
api.PositionRuleText = Position
function api.UpdateRuleTextPreview(preview, style)
    local enabled = style.textEnabled == true and api.ValidateRuleText(style)
    for _, fs in ipairs({ preview.name, preview.level, preview.hp, preview.spell, preview.timer }) do fs:SetShown(not enabled) end
    preview.textFonts, preview.textElements = preview.textFonts or {}, preview.textElements or {}
    local plate = { health = preview.health._bar, cast = preview.cast._bar }
    for _, slot in ipairs(SLOTS) do
        local fs = preview.textFonts[slot.key]
        if enabled then
            if not fs then
                -- Match the baseline spell/timer tier, not the lower appearance
                -- parent whose child StatusBar paints over its font strings.
                local host = slot.cast and preview.castTextHost or preview.textHost
                fs = host:CreateFontString(nil, "OVERLAY"); preview.textFonts[slot.key] = fs
            end
            local element = api.ResolveRuleText(style, slot)
            preview.textElements[slot.key] = element
            Position(fs, plate, slot, true, style)
            local c = style.textColors and style.textColors[element] or Setting(slot.key .. "Color", { r = 1, g = 1, b = 1 })
            fs:SetTextColor(c.r, c.g, c.b, 1)
            Write(fs, element, nil, preview)
            fs:SetShown(element ~= "none")
        elseif fs then fs:Hide() end
    end
    preview._ruleTextEnabled = enabled
end
function api.TickRuleTextPreview(preview)
    if not preview._ruleTextEnabled then return end
    for _, slot in ipairs(SLOTS) do
        local el = preview.textElements[slot.key]
        if slot.cast and el and el:match("^cast") and el ~= "castTarget" then Write(preview.textFonts[slot.key], el, nil, preview) end
    end
end
local function ApplyBody(plate, state)
    local style = state.style
    local enabled = style and style.textEnabled == true and state.unit == plate.unit and plate.unit
    local desired = {}
    if enabled then
        if state.castHost then
            -- Same text tier as EUI's native castTextFrame. Re-seat it after
            -- cast lifting/strata changes, which can reset descendant layers.
            state.castHost:SetFrameStrata(plate._castOverlayLifted and "HIGH" or "MEDIUM")
            state.castHost:SetFrameLevel(900)
        end
        local bindings = NativeBindings(plate)
        local colors = type(style.textColors) == "table" and style.textColors or {}
        for _, slot in ipairs(SLOTS) do
            if not slot.cast or plate.cast then
                local choice = type(style.textSlots) == "table" and style.textSlots[slot.key] or "eui"
                if choice == nil then choice = "eui" end
                if slot.cast and plate._interrupted then choice = "eui" end
                local element = api.ResolveRuleText(style, slot)
                local original = bindings[slot.key]
                if original then
                    local d = desired[original] or {}; desired[original] = d
                    d.hide = d.hide or choice ~= "eui"
                    if not (slot.cast and plate._interrupted) then d.tint = colors[element] or d.tint end
                end
                local fs = state.fonts[slot.key]
                if choice ~= "eui" and choice ~= "none" then
                    if not fs then
                        local host = slot.cast and state.castHost or (slot.key == "textSlotTop" and plate.topTextFrame or plate.healthTextFrame or state.host)
                        if not slot.cast and plate.healthTextFrame and (EllesmereNameplates_NS or {}).SlotTextHost then
                            local nativeHost = Call(EllesmereNameplates_NS.SlotTextHost, plate, slot.key, Setting(slot.key .. "Strata", "MEDIUM"))
                            if not Secret(nativeHost) and type(nativeHost) ~= "nil" then host = nativeHost end
                        end
                        fs = host:CreateFontString(nil, "OVERLAY")
                        state.fonts[slot.key] = fs
                    end
                    Position(fs, plate, slot, false, style)
                    local color = colors[element] or Setting(slot.key .. "Color", { r = 1, g = 1, b = 1 })
                    fs:SetTextColor(color.r, color.g, color.b, 1)
                    Write(fs, element, plate.unit)
                    fs:Show()
                elseif fs then fs:Hide() end
            end
        end
    else for _, fs in pairs(state.fonts) do fs:Hide() end end
    for fs, d in pairs(desired) do local entry = Watch(state, fs); AlphaAndColor(fs, entry, d.hide, d.tint) end
    for fs, entry in pairs(state.native) do if not desired[fs] then AlphaAndColor(fs, entry, false, nil) end end
    local ticking = false
    state.timerFonts = {}
    if enabled then
        for _, slot in ipairs(SLOTS) do
            local choice = type(style.textSlots) == "table" and style.textSlots[slot.key]
            if slot.cast and choice and choice:match("^cast") and choice ~= "castTarget" and not plate._interrupted then
                ticking = true; state.timerFonts[slot.key] = choice
            end
        end
    end
    if state.castHost then state.castHost:SetScript("OnUpdate", ticking and state.Tick or nil) end
end
Apply = function(plate, state)
    if state.busy then return end
    state.busy = true
    local ok, err = pcall(ApplyBody, plate, state)
    state.busy = nil
    if not ok then error(err) end
end
function addon.ApplyRuleText(plate, style)
    if style and style.textEnabled and not api.ValidateRuleText(style) then style = nil end
    local state = states[plate]
    if not state then
        if not (style and style.textEnabled) then return end
        state = { fonts = {}, native = setmetatable({}, { __mode = "k" }) }
        state.host = CreateFrame("Frame", nil, plate)
        state.host:SetAllPoints(plate.health); state.host:SetFrameStrata("MEDIUM"); state.host:SetFrameLevel(plate.health:GetFrameLevel() + 5)
        if plate.cast then state.castHost = CreateFrame("Frame", nil, plate.cast); state.castHost:SetAllPoints(plate.cast) end
        state.Tick = function(_, elapsed)
            if state.unit ~= plate.unit or not state.style or state.style.textEnabled ~= true then return end
            state.elapsed = (state.elapsed or 0) + elapsed
            if state.elapsed < 0.1 then return end
            state.elapsed = 0
            for key, element in pairs(state.timerFonts) do
                local fs = state.fonts[key]
                if fs then Write(fs, element, plate.unit) end
            end
        end
        states[plate] = state
    end
    state.style, state.unit = style, plate.unit
    Apply(plate, state)
end
function addon.InstallTextHooks(plate)
    local np = EllesmereNameplates_NS
    if np and type(np.RefreshCastOverlay) == "function" and not overlayHooks[np] then
        overlayHooks[np] = true
        hooksecurefunc(np, "RefreshCastOverlay", function(owner)
            local state = states[owner]; if state then Apply(owner, state) end
        end)
    end
    if hooked[plate] then return end
    hooked[plate] = true
    for _, method in ipairs({ "ApplyAppearance", "ApplyHealthTextAppearance", "UpdateHealthValues", "UpdateName", "UpdateToT",
        "RefreshNamePosition", "UpdateCastText", "UpdateCast", "AnchorBottomTexts", "ApplyTarget", "ShowInterrupted" }) do
        if type(plate[method]) == "function" then hooksecurefunc(plate, method, function()
            local state = states[plate]; if state then Apply(plate, state) end
        end) end
    end
end
addon.GetRuleTextFrames = function(plate)
    local state = states[plate]
    if state then return state.host, state.fonts end
end
local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "UNIT_TARGET")
events:SetScript("OnEvent", function(_, _, unit)
    for plate, state in pairs(states) do if plate.unit == unit and state.style then Apply(plate, state) end end
end)
