-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("traits")
local api, addon, plate, mocks = f.api, f.namespace, f.plate, f.mocks
local np, checks = EllesmereNameplates_NS, 0
local function Check(value, label) checks = checks + 1; assert(value, label) end
local function Near(actual, expected, label) Check(math.abs(actual - expected) < 0.00001, label) end
local keys = { "simple", "double", "winged", "feathered", "split", "celestial", "rune", "demon", "halo", "curved",
    "barbed", "holyspear", "bracket", "diamond", "crystal", "classic" }
np.TARGET_ARROW_DIR, np.TARGET_ARROW_STYLES = "Arrows/", {}
for _, key in ipairs(keys) do
    np.TARGET_ARROW_STYLES[key] = { l = key .. "-left", r = key .. "-right", label = key,
        w = key == "simple" and 11 or (key == "winged" or key == "barbed") and 28 or 22 }
end
np.db = { profile = { showTargetArrows = false, targetArrowStyle = "double", targetArrowScale = 1.25,
    targetArrowColor = { r = 0.2, g = 0.6, b = 0.9 } } }
function np.ResolveTargetArrowStyle(profile)
    return np.TARGET_ARROW_STYLES[profile and profile.targetArrowStyle or "simple"] or np.TARGET_ARROW_STYLES.simple
end
function np.GetTargetArrowColor(profile) local c = profile.targetArrowColor; return c.r, c.g, c.b end
local selected = "nameplate1"
UnitIsUnit = function(unit, other)
    if mocks.target ~= nil then return mocks.target end
    return other == "target" and unit == selected
end
local function NativeTarget(p)
    local target = UnitIsUnit(p.unit, "target")
    if not issecretvalue(target) and target and np.db.profile.showTargetArrows then
        local spec = np.ResolveTargetArrowStyle(np.db.profile)
        p.leftArrow = p.leftArrow or p.health:CreateTexture()
        p.rightArrow = p.rightArrow or p.health:CreateTexture()
        p.leftArrow:SetTexture(np.TARGET_ARROW_DIR .. spec.l .. ".png")
        p.rightArrow:SetTexture(np.TARGET_ARROW_DIR .. spec.r .. ".png")
        p.leftArrow:SetSize(spec.w, 16); p.rightArrow:SetSize(spec.w, 16)
        p.leftArrow:Show(); p.rightArrow:Show()
    elseif p.leftArrow then p.leftArrow:Hide(); p.rightArrow:Hide() end
    if p.ApplyScale then p:ApplyScale() end
end
plate.health:SetParent(plate)
plate.ApplyTarget = NativeTarget
plate.UpdateRaidIcon = function() end
local layoutCalls, auraCalls = 0, 0
function np.PositionArrowsOutsideAuras(p)
    layoutCalls = layoutCalls + 1
    local spec = np.ResolveTargetArrowStyle(np.db.profile)
    p._arrowW = math.floor(spec.w * np.db.profile.targetArrowScale + 0.5)
    p._arrowH = math.floor(16 * np.db.profile.targetArrowScale + 0.5)
    p.leftArrow:SetWidth(p._arrowW); p.rightArrow:SetWidth(p._arrowW)
end
function np.NPC_ReanchorArrows() auraCalls = auraCalls + 1 end
local other = CreateFrame()
other.unit, other.health, other.ApplyTarget = "nameplate2", CreateFrame("StatusBar", nil, other), NativeTarget
other.health:SetStatusBarColor(1, 1, 1, 1); other.health:SetStatusBarTexture("base")
np.plates.nameplate2 = other
local function Rule(name, conditions, style)
    return { name = name, enabled = true, conditions = conditions,
        style = { healthEnabled = false, scale = 100, opacity = 100, targetArrowsEnabled = true, targetArrowStyle = style } }
end
local elite = Rule("Elite", { target = { yes = true }, classification = { elite = true } }, "winged")
local casting = Rule("Casting", { target = { yes = true }, castState = { casting = true } }, "double")
local target = Rule("Target", { target = { yes = true } }, "simple")
local nontarget = Rule("Not target", { target = { no = true } }, "barbed")
api.GetSettings().rules = { elite, casting, target, nontarget }
local function Refresh() api.Refresh(); f.Flush() end
local function Arrow(p, key, label)
    Check(p.leftArrow:IsShown() and p.rightArrow:IsShown(), label .. " visible")
    Check(p.leftArrow:GetTexture() == "Arrows/" .. key .. "-left.png", label .. " left style")
    Check(p.rightArrow:GetTexture() == "Arrows/" .. key .. "-right.png", label .. " right style")
end
Refresh()
Arrow(plate, "simple", "normal target rule")
Check(not np.db.profile.showTargetArrows, "override never changes EUI's saved arrow-enable setting")
Check(plate.arrowHost.template == "DisableUntrustedLayoutScriptsTemplate", "Retail arrows born with aura-anchor aspects")
Check(other.leftArrow == nil, "matched non-target rule cannot create target indicators")
Check(layoutCalls > 0 and auraCalls > 0, "existing EUI and aura positioning used")
mocks.classification = "elite"
Refresh()
Arrow(plate, "winged", "elite match")
Near(plate._arrowW, 35, "style width uses EUI scale")
Near(plate._arrowH, 20, "style height uses EUI scale")
np.PositionArrowsOutsideAuras(plate)
Near(plate._arrowW, 35, "external layout pass retains the rule's arrow width")
Check(np.ResolveTargetArrowStyle(np.db.profile) == np.TARGET_ARROW_STYLES.double, "layout style scope restores EUI resolver")
mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, false, 123 }
Refresh()
Arrow(plate, "winged", "ordinary first-match priority")
mocks.classification = "normal"
Refresh()
Arrow(plate, "double", "casting match")
mocks.casting = nil
Refresh()
Arrow(plate, "simple", "cast end")
casting.conditions.castState = { interruptible = true }
mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, f.secret, 123 }
Refresh()
Arrow(plate, "double", "implicit active-cast appearance with restricted interruptibility")
mocks.casting = nil
mocks.classification, elite.style.targetArrowsEnabled = "elite", false
Refresh()
Check(not plate.leftArrow:IsShown(), "higher matching rule without arrow override blocks lower rule overrides")
mocks.classification, elite.style.targetArrowsEnabled = "normal", true
Refresh()

-- Native target/settings repaints must not replace the winning override.
np.db.profile.showTargetArrows = true
plate:ApplyTarget(); f.Flush()
Arrow(plate, "simple", "engine target repaint")
np.db.profile.targetArrowStyle = "winged"
plate:ApplyTarget(); f.Flush()
Arrow(plate, "simple", "EUI profile style changes under override")
target.style.targetArrowsEnabled = false
Refresh()
Arrow(plate, "winged", "override off restores latest EUI style")
target.style.targetArrowsEnabled = true
np.db.profile.showTargetArrows = false
Refresh()
Arrow(plate, "simple", "override can show arrows with EUI arrows off")
np.db.profile.targetArrowColor = { r = 0.9, g = 0.3, b = 0.1 }
Refresh()
local r, g, b = plate.leftArrow:GetVertexColor()
Near(r, 0.9, "EUI tint red"); Near(g, 0.3, "EUI tint green"); Near(b, 0.1, "EUI tint blue")

selected = "nameplate2"
f.Fire("PLAYER_TARGET_CHANGED")
Check(not plate.leftArrow:IsShown(), "retarget hides former target")
Arrow(other, "simple", "new target receives matching rule")
selected, mocks.targetExists = nil, false
f.Fire("PLAYER_TARGET_CHANGED")
Check(not plate.leftArrow:IsShown() and not other.leftArrow:IsShown(), "clear target removes rule arrows")
selected, mocks.targetExists = "nameplate1", true
f.Fire("PLAYER_TARGET_CHANGED")
Arrow(plate, "simple", "target reacquired")
mocks.target = f.secret
local originalNative = plate.ApplyTarget
plate.ApplyTarget = function() error("restricted target must not reach native boolean branches") end
Refresh()
Check(not plate.leftArrow:IsShown(), "restricted target comparison fails closed")
plate.ApplyTarget = originalNative
mocks.target = nil
Refresh()
Arrow(plate, "simple", "readable target comparison recovers")
api.GetSettings().enabled = false
Refresh()
Check(not plate.leftArrow:IsShown(), "global disable restores EUI off")
api.GetSettings().enabled = true
Refresh()
target.style.targetArrowStyle = "invalid"
Refresh()
Check(not plate.leftArrow:IsShown(), "invalid saved style fails closed without constructing asset paths")
target.style.targetArrowStyle = "simple"
Refresh()
plate:ClearUnit()
Check(not plate.leftArrow:IsShown(), "recycling hides rule arrows")
plate.unit = "nameplate1"
Refresh()
Arrow(plate, "simple", "reused plate receives fresh rule")

target.style.scale, target.style.scaleElements = 150, { other = false }
Refresh()
Near(plate.leftArrow:GetEffectiveScale(), 1, "target arrows belong to Other independently of health scaling")
target.style.scaleElements = nil
Refresh()
Near(plate.leftArrow:GetEffectiveScale(), 1.5, "target arrows inherit rule scale-all")

-- Older/Forever clients can lack the creation template and modern layout.
local legacy = CreateFrame()
legacy.unit, legacy.health, legacy.ApplyTarget = "nameplate3", CreateFrame("StatusBar", nil, legacy), NativeTarget
legacy.health:SetStatusBarColor(1, 1, 1, 1); legacy.health:SetStatusBarTexture("base")
np.plates.nameplate3 = legacy
selected, mocks.unsupportedArrowTemplate = "nameplate3", true
np.PositionArrowsOutsideAuras, np.NPC_ReanchorArrows = nil, nil
Refresh()
Arrow(legacy, "simple", "Forever-compatible fallback")
Check(legacy.arrowHost == nil and legacy.leftArrow:GetParent() == legacy.health, "plain parent when template unsupported")
Check(legacy.leftArrow.point[1] == "BOTTOM" and legacy.leftArrow.point[3] == "BOTTOMLEFT", "fully anchored fallback geometry")
np.PositionArrowsOutsideAuras = function() error("restricted layout") end
Refresh()
Check(legacy.leftArrow.point[3] == "BOTTOMLEFT", "unreadable native layout uses safe fallback")
Check(np.ResolveTargetArrowStyle(np.db.profile) == np.TARGET_ARROW_STYLES.winged, "failed layout restores resolver scope")

local friendly = CreateFrame()
friendly.unit, friendly.health, friendly.name, friendly.ApplyTarget = "nameplate4", CreateFrame("StatusBar", nil, friendly), CreateFrame("FontString", nil, friendly), NativeTarget
friendly.health:SetStatusBarColor(1, 1, 1, 1); friendly.health:SetStatusBarTexture("base")
np.friendlyPlates.nameplate4 = friendly
selected = "nameplate4"
Refresh()
Arrow(friendly, "simple", "friendly target")
Near(friendly._arrowW, 11, "friendly arrow width follows friendly EUI convention")
Check(friendly.leftArrow.point[2] == friendly.name, "friendly arrows flank name text")
np.db.profile.showTargetArrows, target.style.targetArrowsEnabled = true, false
Refresh()
Arrow(friendly, "winged", "friendly override off restores EUI arrows")
Near(friendly.leftArrow.point[4], -16, "friendly baseline offsets restored with wider EUI style")
for _, key in ipairs(keys) do Check(api.ValidateTargetArrowStyle(key), "known style " .. key) end
Check(not api.ValidateTargetArrowStyle("unknown") and not api.ValidateTargetArrowStyle(1), "unknown/malformed styles rejected")
print("PASS: " .. checks .. " target-arrow matching, native repaint, restoration, Retail aspects, Forever fallback and friendly/scale checks")
