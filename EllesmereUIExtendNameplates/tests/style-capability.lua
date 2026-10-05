-- Run from the repository root with Lua or fengari. Loads production runtime/rendering.
local fixture = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("traits")
local api, runtime, mocks = fixture.api, fixture.namespace, fixture.mocks
local np = EllesmereNameplates_NS
local plate = np.plates.nameplate1
local cases = 0
local function Equal(actual, expected, label)
    cases = cases + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function Rule(selection)
    return { name = "Saved cast state", enabled = true, conditions = { castState = selection },
        style = { castEnabled = true, castColorEnabled = true, castColor = { r = 0.9, g = 0.1, b = 0.2 },
            healthEnabled = false, borderSize = 0 } }
end
local function SetRules(selection)
    api.GetSettings().enabled = true
    api.GetSettings().rules = { Rule(selection) }
    return api.GetRules()[1]
end
mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, false, 123 }
plate._kickProtected = false
np._npStyle = "blizzard"
SetRules({ interruptible = true })
-- This assertion fails on 804e3f70: saved rules bypass the production editor lock.
Equal(runtime.FindCastColorOverrides("nameplate1").interruptible, nil,
    "Blizzard must reject saved Interruptible color candidate")

local keys = { "interruptible", "interruptOnCD", "uninterruptible" }
local function Palette(expected, label)
    local colors = runtime.FindCastColorOverrides("nameplate1")
    for _, key in ipairs(keys) do Equal(colors[key] ~= nil, expected[key] == true, label .. " " .. key) end
end
local all = { interruptible = true, interruptOnCD = true, uninterruptible = true }
local function Capability(expected, label)
    Equal(api.SupportsCastColorStates(), expected, label .. " public capability")
    Equal(runtime.SupportsCastColorStates(), expected, label .. " runtime capability")
end

-- SavedVariables loading exercises production normalization, including old scalar choices.
for _, style in ipairs({ "eui", "classic", "blizzard", "forever" }) do
    np._npStyle = style
    local supported = style == "eui" or style == "classic"
    Capability(supported, style)
    for _, key in ipairs(keys) do
        for _, selection in ipairs({ key, { [key] = true } }) do
            EllesmereUIExtendNameplatesDB = { enabled = true, rules = { Rule(selection) } }
            local rule = api.GetRules()[1]
            Equal(rule.conditions.castState[key], true, style .. " saved choice retained")
            Palette(supported and { [key] = true } or {}, style .. " saved " .. key)
            mocks.casting[8] = fixture.secret
            Palette(supported and { [key] = true } or {}, style .. " secret saved " .. key)
            mocks.casting[8] = false
        end
    end
end

-- Actual accessor beats both a conflicting latch and pending profile flags.
np.db = { profile = { useBlizzardStyle = true, useClassicStyle = false } }
np._npStyle = "blizzard"
local rendered = "eui"
np.NP_Style = function() return rendered end
Capability(true, "accessor EUI wins over Blizzard latch/profile")
SetRules({ interruptible = true })
Palette({ interruptible = true }, "pending Blizzard does not lock EUI")
rendered = "classic"
Capability(true, "accessor Classic")
rendered = "blizzard"
np._npStyle = "eui"
np.db.profile = { useBlizzardStyle = false, useClassicStyle = true }
np._npForever = true -- Forever's real NP_Style result is Blizzard.
Capability(false, "Forever accessor wins over pending Classic")
Palette({}, "pending Classic does not unlock Forever")
np._npForever = nil
rendered = "unknown"
Capability(false, "unknown accessor fails closed")
np.NP_Style = nil
np._npStyle = "blizzard"
Capability(false, "Blizzard latch wins over pending Classic")
np._npStyle = "classic"
np.db.profile = { useBlizzardStyle = true }
Capability(true, "Classic latch wins over pending Blizzard")
np._npStyle = "unknown"
Capability(false, "unknown latch fails closed")
np._npStyle = nil
np.db.profile = { useClassicStyle = true, useBlizzardStyle = true }
Capability(true, "old engine both flags gives Classic precedence")
np.db.profile = { useBlizzardStyle = true, useForeverStyle = true }
Capability(false, "old engine Forever")
np.db.profile = {}
Capability(true, "old engine default EUI")
np.db = nil
Capability(true, "present namespace without profile defaults EUI")
EllesmereNameplates_NS = nil
Capability(false, "missing namespace")
SetRules({ interruptible = true })
Palette({}, "missing namespace state-only fail closed")
SetRules({ casting = true })
Palette(all, "missing namespace preserves generic tint")
EllesmereNameplates_NS = np

-- OR policy: matching broad choices win; blocked states never broaden a mismatch.
for _, style in ipairs({ "eui", "classic", "blizzard", "forever" }) do
    np._npStyle = style
    for _, selection in ipairs({ "any", {}, "casting", { casting = true, interruptible = true } }) do
        SetRules(selection)
        Palette(all, style .. " Any/Casting/mixed generic tint")
    end
    SetRules({ channel = true, interruptible = true })
    Palette((style == "eui" or style == "classic") and { interruptible = true } or {},
        style .. " mismatched broad channel")
    mocks.casting = {}
    mocks.channel = { "Channel", nil, nil, nil, nil, nil, false, 456, false }
    for _, selection in ipairs({ { channel = true }, { channel = true, interruptOnCD = true } }) do
        SetRules(selection)
        Palette(all, style .. " matching channel/mixed generic tint")
    end
    mocks.channel[9] = true
    for _, selection in ipairs({ { empowered = true }, { empowered = true, uninterruptible = true } }) do
        SetRules(selection)
        Palette(all, style .. " matching empowered/mixed generic tint")
    end
    mocks.channel = {}
    SetRules({ casting = true, interruptible = true })
    Palette({}, style .. " active-cast selection rejects no cast")
    SetRules({ none = true, uninterruptible = true })
    Palette(all, style .. " matching Not casting remains broad")
    mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, false, 123 }
    SetRules(all)
    Palette((style == "eui" or style == "classic") and all or {}, style .. " all state-only choices")
end
np._npStyle = "blizzard"
local blocked = Rule({ interruptible = true })
local broad = Rule({ casting = true })
api.GetSettings().rules = { blocked, broad }
for _, key in ipairs(keys) do
    Equal(runtime.FindCastColorOverrides("nameplate1")[key].rule, broad,
        "blocked saved state cannot steal broad priority " .. key)
end

-- Only the codec boundary is stubbed; import validation/copy/normalization are production.
local payload
local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = Copy(child) end
    return copy
end
EllesmereUI = { _Serializer = {
    Serialize = function(value) payload = Copy(value); return "style" end,
    Deserialize = function() return Copy(payload) end,
} }
local codec = {}
for _, key in ipairs({ "CompressDeflate", "EncodeForPrint", "DecodeForPrint", "DecompressDeflate" }) do
    codec[key] = function(_, value) return value end
end
function LibStub(name) if name == "LibDeflate" then return codec end end
assert(loadfile("EllesmereUIExtendNameplates/RuleIO.lua"))()
for version = 1, 2 do
    for _, key in ipairs(keys) do
        payload = { format = "EllesmereUINameplateExtrasRules", version = version,
            rules = { Rule(version == 1 and key or { [key] = true }) } }
        np._npStyle = "blizzard"
        assert(api.ImportRuleSet("!EUI_NPEX_RULES" .. version .. "!style"))
        local saved = api.GetRules()[1].conditions.castState
        Palette({}, "imported v" .. version .. " Blizzard " .. key)
        np._npForever, np._npStyle = true, "blizzard"
        Palette({}, "imported v" .. version .. " Forever " .. key)
        np._npForever = nil
        for _, style in ipairs({ "eui", "classic" }) do
            np._npStyle = style
            Palette({ [key] = true }, "imported v" .. version .. " " .. style .. " " .. key)
        end
        Equal(saved[key], true, "imported choice retained through style transitions")
        Equal(api.GetRules()[1].conditions.castState, saved, "selection set not replaced by capability")
    end
end

-- Transition the rendered latch and refresh through the real renderer, not a copied painter.
local fill, overlay = plate.cast:GetStatusBarTexture(), plate.castBarOverlay
local engineFill, engineOverlay = { 0.2, 0.3, 0.4, 0.8 }, { 0.5, 0.6, 0.7, 0.9 }
local function Paint(expectedFill, expectedOverlay, label)
    for index = 1, 4 do
        Equal(fill.vertexColor[index], expectedFill[index], label .. " fill " .. index)
        Equal(overlay.vertexColor[index], expectedOverlay[index], label .. " overlay " .. index)
    end
end
runtime.ApplyCastStyle(plate, nil, nil, {})
fill:SetVertexColor(unpack(engineFill))
overlay:SetVertexColor(unpack(engineOverlay))
local rule = SetRules({ interruptible = true })
np._npStyle = "eui"
runtime.RefreshAll()
Paint({ 0.9, 0.1, 0.2, 0.8 }, { 0.9, 0.1, 0.2, 0.9 }, "EUI state tint active")
np._npStyle = "blizzard"
runtime.RefreshAll()
Paint(engineFill, engineOverlay, "style transition restores engine colors")
Equal(rule.conditions.castState.interruptible, true, "transition preserves saved selection")
-- Direct callers already go through the same mask and restore previously owned paint.
runtime.ApplyCastStyle(plate, rule.style, rule.conditions)
Paint(engineFill, engineOverlay, "Blizzard direct caller stays blocked")
np._npStyle = "classic"
runtime.RefreshAll()
Paint({ 0.9, 0.1, 0.2, 0.8 }, { 0.9, 0.1, 0.2, 0.9 }, "Classic re-enables saved tint")
engineFill = { 0.4, 0.2, 0.6, 0.7 }
fill:SetVertexColor(unpack(engineFill))
rule.enabled = false
runtime.RefreshAll()
Paint(engineFill, engineOverlay, "rule disable restores latest engine colors")
rule.enabled = true
runtime.RefreshAll()
api.GetSettings().enabled = false
runtime.RefreshAll()
Paint(engineFill, engineOverlay, "addon disable restores engine colors")
api.GetSettings().enabled = true

-- Load production Options and capture the native-widget boundary's dropdown callbacks.
local function Noop() end
local function Row()
    local row = CreateFrame("Frame")
    row._leftRegion, row._rightRegion = CreateFrame("Frame", nil, row), CreateFrame("Frame", nil, row)
    return row, 50
end
local W = {}
for _, key in ipairs({ "SectionHeader", "Dropdown", "Toggle", "Slider", "DualRow", "WideTripleButton", "WideDualButton" }) do
    W[key] = Row
end
function W:Button(parent)
    local row = CreateFrame("Frame", nil, parent)
    local button = CreateFrame("Button", nil, row)
    function row:GetChildren() return button end
    return row, 50
end
local spec, castDropdown
EllesmereUI.Widgets = W
EllesmereUI.CONTENT_PAD = 20
EllesmereUI.PanelPP = { Point = function(frame, ...) frame:SetPoint(...) end,
    Size = function(frame, ...) frame:SetSize(...) end }
EllesmereUI.MakeStyledButton = Noop
EllesmereUI.MakeFont = function(parent) return parent:CreateFontString() end
EllesmereUI.L = function(text) return text end
EllesmereUI.IsSearchPrebuild = function() return false end
EllesmereUI.RegisterWidgetRefresh = Noop
EllesmereUI.BuildVisOptsCBDropdown = function(parent, _, _, items, get, set, _, _, _, _, _, opts)
    if opts.label == "Cast state" then castDropdown = { items = items, get = get, set = set } end
    return CreateFrame("Button", nil, parent), Noop
end
EllesmereUI.IsPluginRegistered = function() return false end
EllesmereUI.RegisterPlugin = function(_, value) spec = value; return true end
assert(loadfile("EllesmereUIExtendNameplates/Options.lua"))()
assert(spec, "production Options registration failed")
spec.modules[1].buildPage("Rules", CreateFrame("Frame"), 0)
local items = {}
for _, item in ipairs(castDropdown.items) do items[item.key] = item end
for _, style in ipairs({ "eui", "classic", "blizzard", "forever" }) do
    np._npStyle = style
    local supported = api.SupportsCastColorStates()
    for _, key in ipairs(keys) do
        Equal(items[key].lockedFn(), not supported, style .. " editor/runtime lock agreement " .. key)
        Equal(type(items[key].lockedTooltip()), "string", "state lock explains reload requirement")
    end
    Equal(items.casting.lockedFn(), false, style .. " broad Casting remains editable")
end
np._npStyle = "blizzard"
rule.conditions.castState = { interruptible = true }
castDropdown.set("interruptible", false)
Equal(castDropdown.get("interruptible"), true, "locked deselect preserves saved choice")
castDropdown.set("interruptOnCD", true)
Equal(castDropdown.get("interruptOnCD"), false, "locked select cannot add state choice")
castDropdown.set("casting", true)
Equal(castDropdown.get("casting"), true, "broad Casting editable while states locked")
Equal(castDropdown.get("interruptible"), true, "broad edit does not erase locked choice")
Palette(all, "editor mixed broad/state uses generic tint")
np.db = { profile = { useClassicStyle = true } }
Equal(items.interruptible.lockedFn(), true, "pending Classic does not unlock Blizzard editor")
np.NP_Style = function() return "eui" end
Equal(items.interruptible.lockedFn(), false, "rendered accessor beats Blizzard latch in editor")
Palette(all, "rendered accessor beats Blizzard latch in runtime")
np.NP_Style = function() return "blizzard" end
np._npStyle = "eui"
Equal(items.interruptible.lockedFn(), true, "rendered Blizzard accessor beats pending EUI latch")
np.NP_Style = nil
np._npStyle = "classic"
Equal(items.interruptible.lockedFn(), false, "live lock callback observes rendered Classic")
castDropdown.set("interruptible", false)
Equal(castDropdown.get("interruptible"), false, "supported editor can deselect saved choice")
castDropdown.set("interruptOnCD", true)
Equal(castDropdown.get("interruptOnCD"), true, "supported editor can select state")
Equal(castDropdown.get("casting"), false, "explicit subtype edit keeps existing editor semantics")
Palette({ interruptOnCD = true }, "supported editor selection matches runtime")
EllesmereNameplates_NS = nil
Equal(items.interruptOnCD.lockedFn(), true, "missing namespace locks production editor")
castDropdown.set("interruptOnCD", false)
Equal(castDropdown.get("interruptOnCD"), true, "missing namespace preserves saved edit choice")
EllesmereNameplates_NS = np
print("PASS: " .. cases .. " production style-capability checks")
