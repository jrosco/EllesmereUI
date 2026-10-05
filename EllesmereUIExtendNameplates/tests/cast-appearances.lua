-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("traits")
local api, addon, plate = f.api, f.namespace, f.plate
local checks = 0
local function Near(actual, expected, label)
    checks = checks + 1
    assert(math.abs(actual - expected) < 0.00001,
        label .. ": expected " .. expected .. ", got " .. tostring(actual))
end
local function Check(value, label)
    checks = checks + 1
    assert(value, label)
end
local function HasBorder(parent)
    for _, frame in ipairs(f.frames) do
        if frame.parent == parent and frame.kind == "Frame" and frame.shown then return true end
    end
    return false
end
local function Effects(label)
    Near(plate:GetScale(), 1.4, label .. " size")
    Near(plate:GetAlpha(), 0.65, label .. " opacity")
    Near(plate.health.color[1], 0.15, label .. " health red")
    Near(plate.health.color[2], 0.85, label .. " health green")
    Check(plate.health.texture == "Interface\\Buttons\\WHITE8x8", label .. " health texture")
    Check(HasBorder(plate.health), label .. " health border")
    Near(plate.cast:GetAlpha(), 0.35, label .. " cast opacity")
    Check(plate.cast:GetStatusBarTexture():GetTexture() == "Interface\\Buttons\\WHITE8x8", label .. " cast texture")
    Check(HasBorder(plate.cast), label .. " cast border")
end
for _, state in ipairs({ "interruptible", "interruptOnCD", "uninterruptible" }) do
    local rule = { name = state .. " appearances", enabled = true,
        conditions = { castState = { [state] = true }, target = { yes = true }, reaction = { enemy = true } },
        style = { scale = 140, opacity = 65, healthEnabled = true, healthColorEnabled = true,
            healthColor = { r = 0.15, g = 0.85, b = 0.25 }, texture = "flat", borderEnabled = true,
            borderSize = 3, borderColor = { r = 1, g = 0, b = 0 }, castEnabled = true,
            castOpacityEnabled = true, castOpacity = 35, castTexture = "flat",
            castBorderEnabled = true, castBorderSize = 2, castBorderColor = { r = 0, g = 1, b = 0 } } }
    api.GetSettings().rules = { rule }
    f.mocks.casting = { "Hidden cast", nil, nil, nil, nil, nil, nil, f.secret, f.secret }
    f.mocks.channel = {}
    addon.RefreshAll()
    Effects(state .. " secret interruptibility")
    Check(rule.conditions.castState.casting == nil, "implicit Casting must not be stored or displayed")
    for _, flag in ipairs({ false, true }) do
        f.mocks.casting[8] = flag
        addon.RefreshAll()
        Effects(state .. " readable flag " .. tostring(flag))
    end
    f.mocks.casting[8] = nil
    addon.RefreshAll()
    Effects(state .. " unavailable flag")
    f.mocks.casting = {}
    f.mocks.channel = { "Channel", nil, nil, nil, nil, nil, f.secret, f.secret, false }
    addon.RefreshAll()
    Effects(state .. " channel")
    f.mocks.channel[9] = true
    addon.RefreshAll()
    Effects(state .. " empowered")
    rule.style.castColorEnabled = true
    local colors = addon.FindCastColorOverrides(plate.unit)
    Check(colors[state] and colors[state].rule == rule, "appearance eligibility must retain selected color state")
    for _, other in ipairs({ "interruptible", "interruptOnCD", "uninterruptible" }) do
        if other ~= state then Check(colors[other] == nil, "implicit Casting must not broaden color mask") end
    end
    rule.style.castColorEnabled = false
    f.mocks.channel = {}
    addon.RefreshAll()
    Near(plate:GetScale(), 1, state .. " cast end restores size")
    Near(plate:GetAlpha(), 1, state .. " cast end restores opacity")
    Near(plate.health.color[1], 0.8, state .. " cast end restores health color")
    Check(plate.health.texture == "base", state .. " cast end restores health texture")
    Near(plate.cast:GetAlpha(), 1, state .. " cast end restores cast opacity")
    Check(plate.cast:GetStatusBarTexture():GetTexture() == "cast-base", state .. " cast end restores cast texture")
    local healthBorder, castBorder = addon.GetRuleBorderFrames(plate)
    Check(not healthBorder.shown and not castBorder.shown, state .. " cast end hides rule border hosts")
    f.mocks.casting = { "Cast", nil, nil, nil, nil, nil, nil, f.secret, f.secret }
    rule.conditions.reaction = { friendly = true }
    addon.RefreshAll()
    Near(plate:GetScale(), 1, "other filter groups still AND with implicit Casting")
    Check(next(addon.FindCastColorOverrides(plate.unit)) == nil, "mismatched reaction rejects color candidates too")
end
-- Ordinary appearances use first-match priority even when colors come from later state rules.
local first = { name = "First appearance", enabled = true, conditions = { castState = { interruptible = true } },
    style = { scale = 120, borderSize = 0, castEnabled = true, castColorEnabled = true,
        castColor = { r = 1, g = 0, b = 0 } } }
local second = { name = "Second color", enabled = true, conditions = { castState = { interruptOnCD = true } },
    style = { scale = 160, borderSize = 0, castEnabled = true, castColorEnabled = true,
        castColor = { r = 0, g = 0, b = 1 } } }
api.GetSettings().rules = { first, second }
addon.RefreshAll()
Near(plate:GetScale(), 1.2, "first matching active-cast rule wins appearances")
local colors = addon.FindCastColorOverrides(plate.unit)
Check(colors.interruptible.rule == first and colors.interruptOnCD.rule == second,
    "color priority remains separate for each selected state")
print("PASS: " .. checks .. " implicit Casting appearance, AND filters, priority and restoration checks")
