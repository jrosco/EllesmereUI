-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("ui-locks")
local api, rows, checks = f.api, f.rows, 0
local function Check(value, label) checks = checks + 1; assert(value, label) end
Check(api.CreateProfile("Reset test"), "create profile for isolated reset")
local current = api.GetSettings()
local assignment = api.GetProfileInfo().active
local defaults = {}
for _, r in ipairs(api.DefaultRules) do defaults[r.name] = r end
current.rules = { { name = "Customized disabled rule", enabled = false,
    conditions = { playerCombat = { inCombat = true }, instanceType = { raid = true } },
    style = { scale = 200, opacity = 5, healthColor = { r = 0, g = 0, b = 0 },
        borderColor = { r = 0, g = 0, b = 0 }, textEnabled = true, textSlots = { castName = "none" },
        healthGlowStyle = 3, targetArrowsEnabled = true } } }
current.enabled, current.selectedRule, current.extraSetting = false, 10, "remove on reset"
-- Exported defaults should not be writable aliases of the pristine template.
api.DefaultRules[1].name = "Externally changed public default"
f.spec.modules[1].onReset()
f.Flush()
Check(api.GetSettings() == current, "reset retains active settings object identity")
Check(api.GetProfileInfo().active == assignment, "reset preserves active profile assignment")
Check(current.enabled == true and current.selectedRule == 1 and current.extraSetting == nil,
    "reset restores profile-wide defaults and removes extra settings")
Check(#current.rules == 4, "reset restores all four starter rules")
local reset = {}
for _, r in ipairs(current.rules) do reset[r.name] = r end
Check(reset["Elite Enemies"] and not reset["Externally changed public default"], "reset uses pristine defaults, not public-template mutations")
Check(reset["Non Target"].conditions.target.no and reset["Non Target"].conditions.target.none
    and not reset["Non Target"].conditions.target.yes, "reset restores both default non-target choices")
for _, r in ipairs(current.rules) do
    Check(r.enabled == true, "starter enabled " .. r.name)
    Check(type(r.conditions.playerCombat) == "table" and next(r.conditions.playerCombat) == nil, "combat selection normalized to Any")
    Check(type(r.conditions.instanceType) == "table" and next(r.conditions.instanceType) == nil, "instance selection normalized to Any")
    Check(r.style.textEnabled == nil and r.style.healthGlowStyle == nil and r.style.targetArrowsEnabled == nil,
        "custom text/glow/arrow settings removed")
end
Check(rows["Rule name"].get() == "Elite Enemies" and not rows["Rule name"].disabled(), "reset rebuilds editor, clearing old disabled-rule lock")
Check(f.GetPreview().title.text:find("Elite Enemies", 1, true), "reset refreshes pinned preview with selected starter")
current.rules[1].conditions.instanceType.raid = true
current.rules[1].style.healthColor.r = 0
Check(api.ResetActiveProfile(), "runtime reset callable directly")
Check(next(current.rules[1].conditions.instanceType) == nil and current.rules[1].style.healthColor.r > 0,
    "repeated reset deep-copies nested defaults without template contamination")
Check(api.SelectProfile("Default"), "switch back to shared Default")
Check(api.GetSettings() ~= current and api.GetProfileInfo().active == "Default", "reset does not replace other profiles")
f.Flush()
print("PASS: " .. checks .. " active-profile reset, pristine/deep-copied defaults, non-target selections, normalized conditions and editor/header refresh")
