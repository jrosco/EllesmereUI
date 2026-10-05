-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("scaling")
local api, plate, np = f.api, f.plate, EllesmereNameplates_NS
local checks = 0
local function Near(actual, expected, label)
    checks = checks + 1
    assert(math.abs(actual - expected) < 0.00001,
        label .. ": expected " .. expected .. ", got " .. tostring(actual))
end
local function Check(value, label) checks = checks + 1; assert(value, label) end
local observations = {}
local function Element(parent, key, scale, kind)
    local object = CreateFrame(kind or "Frame", nil, parent)
    object:SetScale(scale or 1)
    observations[#observations + 1] = { object = object, key = key }
    return object
end
plate.health:SetParent(plate)
plate.health:SetScale(0.9)
plate.cast:SetScale(1.1)
observations[#observations + 1] = { object = plate.health, key = "healthBar" }
observations[#observations + 1] = { object = plate.cast, key = "castBar" }
Element(plate.health, "healthBar", 0.7)
Element(plate.cast, "castBar", 0.8, "FontString")
plate.healthTextFrame = Element(plate.health, "text", 1.2)
plate.nameRaidFrame = Element(plate.healthTextFrame, "other", 0.8)
plate._slotTextHosts = { custom = Element(plate.health, "text", 0.95) }
plate.name = Element(plate, "text", 0.8, "FontString")
plate.hpText = Element(plate.healthTextFrame, "text", 0.7, "FontString")
plate.hpNumber = Element(plate.health, "text", 0.9, "FontString")
plate.subText1 = Element(plate, "text", 0.6, "FontString")
plate.levelText = Element(plate._slotTextHosts.custom, "text", 0.75, "FontString")
plate.classFrame = Element(plate, "other", 0.95)
plate.classText = Element(plate.classFrame, "text", 0.65, "FontString")
plate.targetClipFill = Element(plate.health, "other", 0.85)
plate.buffs = { Element(plate, "other", 0.8) }
plate.debuffs = { Element(plate, "other", 0.7) }
plate.cc = { Element(plate, "other", 1.3) }
plate.cc[1]:SetIgnoreParentScale(true)
plate.npcLockout = Element(plate, "other", 0.6)
plate._cpBar = Element(plate, "classResources", 0.85)
local pip = Element(plate, "classResources", 0.9, "Texture")
plate._cpPips = { pip }
for _, key in ipairs({ "_bg", "_shapeMask", "_border", "_borderBox", "_secretBar" }) do
    pip[key] = Element(plate, "classResources", 0.75, key == "_secretBar" and "StatusBar" or "Texture")
end
local bundle = { holder = CreateFrame("Frame", nil, UIParent) }
function plate:EnsureToTText()
    if not self.totText then
        self.totText = CreateFrame("FontString", nil, self.health)
        self.totText:SetScale(0.65)
    end
    return self.totText
end
for _, key in ipairs({ "buffs", "debuffs", "cc" }) do
    bundle[key] = Element(bundle.holder, "other", 0.8)
    Element(bundle[key], "other", 0.65, "FontString")
    EllesmereUI.AuraKit.AddGroupToContainer(bundle[key], { style = "np:" .. key })
end
np.NPC_AttachPlate(plate, bundle)
for _, observation in ipairs(observations) do observation.base = observation.object:GetEffectiveScale() end
EllesmereUIExtendNameplatesDB = { enabled = true, rules = {
    { name = "Scaling", enabled = true, conditions = {}, style = { scale = 150, healthEnabled = false,
        scaleElements = { buffs = false, debuffs = true, cc = false, other = true } } },
} }
f.Fire("ADDON_LOADED", "EllesmereUIExtendNameplates")
local rule = api.GetRules()[1]
Check(rule.style.scaleElements.buffs == nil and rule.style.scaleElements.debuffs == nil
    and rule.style.scaleElements.cc == nil and rule.style.scaleElements.other == true,
    "saved legacy aura toggles removed while preserving Other")
local function Refresh() api.Refresh(); f.Flush() end

-- All combinations check effective scale, not just the compensation setter.
-- Include nested hosts, independent decoration textures, ignoring-parent-scale
-- regions, legacy icons and modern pooled aura containers.
for _, lifted in ipairs({ false, true }) do
    np.db.profile.castOverlayEnabled = lifted
    np.RefreshCastOverlay(plate)
    for mask = 0, 2 ^ #api.ScaleElementOptions - 1 do
        local selection = {}
        for index, option in ipairs(api.ScaleElementOptions) do
            if math.floor(mask / 2 ^ (index - 1)) % 2 == 1 then selection[option.key] = false end
        end
        rule.style.scaleElements = next(selection) and selection or nil
        Refresh()
        for _, observation in ipairs(observations) do
            Near(observation.object:GetEffectiveScale(), observation.base * (selection[observation.key] == false and 1 or 1.5),
                "combination " .. mask .. " " .. observation.key .. (lifted and " lifted" or " on plate"))
        end
        local scale, marker, power = np._WCNP_Attach(plate.health, nil, nil, nil, nil, nil, nil, nil, nil,
            plate:GetEffectiveScale(), nil, nil, nil, "CHARGES")
        Near(scale, selection.classResources == false and 1 or 1.5, "external warrior-charge geometry compensation")
        Check(marker == "renderer" and power == "CHARGES", "external rendering arguments and returns preserved")
    end
end

rule.style.scaleElements = { castBar = false, text = false, other = false, classResources = false }
Refresh()
plate:SetScale(1.2)
Near(plate:GetScale(), 1.2, "engine animation retained with Other unchecked")
Near(plate.cast:GetEffectiveScale(), 1.1 * 1.2, "lifted unchecked cast retains engine animation")
Near(pip:GetEffectiveScale(), 0.9 * 1.2, "unchecked resource retains engine animation")
Near(plate.name:GetEffectiveScale(), 0.8 * 1.2, "unchecked direct name retains engine animation")
plate.name:SetScale(0.55)
Near(plate.name:GetEffectiveScale(), 0.55 * 1.2, "independent text-scale writer")
plate.name:SetParent(plate.health)
Near(plate.name:GetEffectiveScale(), 0.55 * 0.9 * 1.2, "text compensation follows reparenting into scaled health")
plate.name:SetParent(plate)
local tot = plate:EnsureToTText()
Near(tot:GetEffectiveScale(), 0.65 * 0.9 * 1.2, "lazy target-of-target text follows Text rather than health scaling")
plate.cast:SetScale(0.7)
Near(plate.cast:GetEffectiveScale(), 0.7 * 1.2, "independent cast-scale writer")
plate.buffs[1]:SetScale(0.6)
Near(plate.buffs[1]:GetEffectiveScale(), 0.6 * 1.2, "independent buff-scale writer")
for _ = 1, 5 do Refresh() end
Near(plate.cast:GetEffectiveScale(), 0.7 * 1.2, "refresh does not compound component scale")

-- Resources may appear between rule evaluations.
pip._border = CreateFrame("Texture", nil, plate)
pip._border:SetScale(0.55)
np.GetClassPowerScale()
f.Flush()
Near(pip._border:GetEffectiveScale(), 0.55 * 1.2, "lazy resource decoration")

-- Deferred aura jobs can add a previously missing row to an attached holder.
local lazyBuff = CreateFrame("Frame", nil, bundle.holder)
lazyBuff:SetScale(0.45)
EllesmereUI.AuraKit.AddGroupToContainer(lazyBuff, { style = "np:buffsplain" })
f.Flush()
Near(lazyBuff:GetEffectiveScale(), 0.45 * 1.2, "lazy attached aura row discovered from public group spec")
EllesmereUI.AuraKit.AddGroupToContainer(lazyBuff, { style = "np:buffs2" })
f.Flush()
Near(lazyBuff:GetEffectiveScale(), 0.45 * 1.2, "split buff group retains the same category without compounding")
local ignored = CreateFrame("Frame", nil, bundle.holder)
ignored:SetScale(0.4)
EllesmereUI.AuraKit.AddGroupToContainer(ignored, { style = "player:buffs" })
f.Flush()
Near(ignored:GetScale(), 0.4, "unrelated aura styles are not registered as nameplate rows")

-- Release and transfer a bundle before the old plate's style is cleared.
np.NPC_DetachPlate(plate)
Near(bundle.buffs:GetScale(), 0.8, "pooled aura container restored on detach")
local other = CreateFrame()
other.unit = "nameplate2"
other.health = CreateFrame("StatusBar", nil, other)
f.namespace.PrepareScaleSelection(other, 1.4, nil)
other:SetScale(1.4)
np.NPC_AttachPlate(other, bundle)
Near(bundle.buffs:GetEffectiveScale(), 0.8 * 1.4, "pooled bundle adopted by scale-all plate")
rule.style.scaleElements = { text = false, other = false }
Refresh()
Near(bundle.buffs:GetEffectiveScale(), 0.8 * 1.4, "old owner cannot restore transferred bundle")
np.NPC_DetachPlate(other)
np.NPC_AttachPlate(plate, bundle)
Near(bundle.buffs:GetEffectiveScale(), 0.8 * 1.2, "pooled bundle returns to selective owner")

-- Rule transitions and disable restore engine writes, not initial snapshots.
rule.enabled = false
Refresh()
Near(plate:GetScale(), 1.2, "no matching rule restores engine root")
Near(plate.cast:GetScale(), 0.7, "no matching rule restores latest cast scale")
Near(plate.buffs[1]:GetScale(), 0.6, "no matching rule restores latest buff scale")
Near(plate.name:GetScale(), 0.55, "no matching rule restores latest text scale")
Near(pip._border:GetScale(), 0.55, "no matching rule restores lazy decoration")
Near(np._WCNP_Attach(plate.health, nil, nil, nil, nil, nil, nil, nil, nil, plate:GetEffectiveScale()),
    1.2, "external resource compensation restored")
rule.enabled = true
rule.style.scaleElements = { text = false, other = false }
Refresh()
Near(plate:GetScale(), 1.2, "root stays at engine scale when Other is unchecked")
Near(plate.cast:GetEffectiveScale(), 0.7 * 1.2 * 1.5, "cast scales with unscaled root")
Near(np._WCNP_Attach(plate.cast, nil, nil, nil, nil, nil, nil, nil, nil, plate:GetEffectiveScale()),
    1.2 * 1.5, "external resource finds its owner through a lifted cast anchor")
local restrictedGeometry = np._WCNP_Attach(plate.health, nil, nil, nil, nil, nil, nil, nil, nil, f.secret)
Check(restrictedGeometry == f.secret, "restricted geometry forwarded without arithmetic")
plate:ClearUnit()
Near(plate.cast:GetScale(), 0.7, "recycling restores cast")
Near(pip:GetScale(), 0.9, "recycling restores resource texture")
plate.unit = "nameplate1"
Refresh()
Near(plate.cast:GetEffectiveScale(), 0.7 * 1.5, "reused plate has fresh base scale")
api.GetSettings().enabled = false
Refresh()
Near(plate.cast:GetScale(), 0.7, "global disable restores cast")
Near(plate.health:GetScale(), 0.9, "global disable restores health")

-- Restricted scales must never be used in plugin comparisons/arithmetic.
local restricted = CreateFrame("Frame", nil, plate)
restricted.GetScale = function() return f.secret end
restricted.SetScale = function() error("restricted region must not be scaled") end
plate.buffs[#plate.buffs + 1] = restricted
api.GetSettings().enabled = true
Refresh()

-- Fengari cannot enforce Retail's secret-boolean VM semantics. Flag both
-- boolean values and verify unknown inheritance releases compensation rather
-- than guessing true/false. Native getters themselves remain unmodified.
local originalSecret, originalIgnoring = issecretvalue, plate.health.IsIgnoringParentScale
local function Reconcile() f.namespace.ApplyScaleSelection(plate); f.Flush() end
local function SecretBoolean(value)
    plate.health.IsIgnoringParentScale = function() return value end
    issecretvalue = function(candidate)
        return type(candidate) == "boolean" or originalSecret(candidate)
    end
    Reconcile()
    Near(plate.health:GetScale(), 0.9, "secret parent-scale boolean restores health base")
    Near(plate.healthTextFrame:GetScale(), 1.2, "secret ancestor releases nested text compensation")
    issecretvalue = originalSecret
    plate.health.IsIgnoringParentScale = originalIgnoring
    Reconcile()
    Near(plate.health:GetScale(), 0.9 * 1.5, "readable inheritance reapplies health scaling")
    Near(plate.healthTextFrame:GetScale(), 1.2 / 1.5, "readable ancestor reapplies nested compensation")
end
SecretBoolean(true)
SecretBoolean(false)
local originalParent = plate.health.GetParent
plate.health.GetParent = function() return f.secret end
Reconcile()
Near(plate.health:GetScale(), 0.9, "secret parent reference releases compensation")
plate.health.GetParent = originalParent
Reconcile()
Near(plate.health:GetScale(), 0.9 * 1.5, "readable parent reference reapplies compensation")
local originalScale = plate.health.GetScale
plate.health.GetScale = function() return f.secret end
Reconcile()
Near(plate.healthTextFrame:GetScale(), 1.2, "secret ancestor scale is not assumed to match desired multiplier")
plate.health.GetScale = originalScale
Reconcile()
Near(plate.healthTextFrame:GetScale(), 1.2 / 1.5, "readable ancestor scale reapplies compensation")

Check(api.ValidateScaleElements(nil) and api.ValidateScaleElements({ castBar = false }), "valid scale selection")
Check(np.NPC_GetScalingContainers == nil and np.RefreshExtraElementScaling == nil and np.GetExtraClassPowerScale == nil,
    "no custom APIs required in the external Nameplates addon")
for _, invalid in ipairs({ false, "all", { unknown = true }, { castBar = 1 }, { [1] = false } }) do
    Check(not api.ValidateScaleElements(invalid), "invalid scale selection rejected")
end
print("PASS: " .. checks .. " selective scaling combinations, animation, lifted casts, textures, pool transfer and restoration checks")
