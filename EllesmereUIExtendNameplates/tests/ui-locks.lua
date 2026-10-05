-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("ui-locks")
local api, rows = f.api, f.rows
local checks = 0
local function Check(value, label) checks = checks + 1; assert(value, label) end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end
local function Same(actual, expected, label)
    Check(type(actual) == type(expected), label .. " type")
    if type(actual) ~= "table" then Check(actual == expected, label .. " value"); return end
    for key, item in pairs(expected) do Same(actual[key], item, label .. "." .. tostring(key)) end
    for key in pairs(actual) do Check(expected[key] ~= nil, label .. " unexpected key") end
end
local first = api.GetRules()[1]
local second = Copy(first)
second.name, second.enabled = "Other rule", true
api.GetSettings().rules = { first, second }
api.GetSettings().selectedRule = 1
EllesmereUI:RefreshPage()
local dropdowns = { "Unit type", "Reaction", "Classification", "Target state", "Cast state", "Spell school", "Threat", "Player combat state", "Instance Type" }
local actions = { "Add Rule", "Copy Rule", "Delete Rule", "Move Rule Up", "Move Rule Down" }
local settings = { "Rule name", "Quest Objective", "Nameplate size (%)", "Opacity (%)", "Override health bar",
    "Custom health color", "Health-bar color", "Health-bar texture", "Override health border", "Health border texture",
    "Health border color", "Health border size", "Override cast bar", "Custom cast color", "Cast fill color",
    "Cast-bar texture", "Custom cast opacity", "Cast opacity (%)", "Override cast border", "Cast border texture", "Cast border color", "Cast border size",
    "Override target arrows", "Target-arrow style", "Health border glow", "Health glow color", "Cast border glow", "Cast glow color",
    "Override text", "Top text content", "Cast timer text content", "Override Name color", "Name text color" }
local function Locks(expected, label)
    for _, name in ipairs(settings) do
        if expected then
            Check(rows[name].disabled and rows[name].disabled(), label .. " locked " .. name)
            Check(rows[name].disabledTooltip():find("Enable", 1, true), label .. " tooltip " .. name)
        end
    end
    for _, name in ipairs(dropdowns) do
        for _, item in ipairs(rows[name].items) do
            if expected then
                Check(item.lockedFn(), label .. " item " .. name)
                Check(item.lockedTooltip():find("Enable", 1, true), label .. " item tooltip " .. name)
            end
        end
        Check(rows[name].button.mouseEnabled == not expected, label .. " dropdown mouse " .. name)
        Check(rows[name].button.alpha == (expected and 0.3 or 1), label .. " dropdown dim " .. name)
    end
end
local oldName, oldSize = rows["Rule name"].set, rows["Nameplate size (%)"].set
rows["Delete Rule"].click()
local deletePopup = assert(f.GetConfirm())
local before = Copy(api.GetRules())
rows["Enable rule styling"].set(false); f.Flush()
Locks(true, "global off")
Check(rows["Edit rule"].disabled() and rows["Rule enabled"].disabled(), "global off locks selector and individual enable")
Check(not rows["Enable rule styling"].disabled, "global toggle must remain usable")
for _, name in ipairs(actions) do
    Check(rows[name].button.alpha == 0.3 and rows[name].button.mouseEnabled == false, "global off action " .. name)
    rows[name].click()
end
oldName("Blocked rename")
oldSize(180)
for _, name in ipairs(settings) do rows[name].set(0.2, 0.3, 0.4) end
rows["Edit rule"].set("2")
rows["Rule enabled"].set(false)
rows["Quest Objective"].set(true)
for _, name in ipairs(dropdowns) do rows[name].set(rows[name].items[1].key, true) end
deletePopup.onConfirm()
local tooltip, previousTooltip = nil, EllesmereUI.ShowWidgetTooltip
EllesmereUI.ShowWidgetTooltip = function(_, text) tooltip = text end
local explained = false
for _, frame in ipairs(f.frames) do
    if frame.allPoints == rows["Unit type"].button and frame.shown and frame.scripts.OnEnter then
        frame.scripts.OnEnter()
        explained = tooltip and tooltip:find("Enable rule styling", 1, true) ~= nil
    end
end
EllesmereUI.ShowWidgetTooltip = previousTooltip
Check(explained, "locked native dropdown overlay must explain the global lock on hover")
Same(api.GetRules(), before, "global off must preserve all rule data and block stale callbacks")
Check(api.GetSettings().selectedRule == 1, "global off keeps selection")

rows["Enable rule styling"].set(true); f.Flush()
Check(not rows["Edit rule"].disabled() and not rows["Rule enabled"].disabled(), "global on restores selector and rule toggle")
Locks(false, "global on")
rows["Override health bar"].set(false)
rows["Override cast bar"].set(false)
rows["Delete Rule"].click()
deletePopup = assert(f.GetConfirm())
oldName, oldSize = rows["Rule name"].set, rows["Nameplate size (%)"].set
rows["Rule enabled"].set(false); f.Flush()
Locks(true, "selected rule off")
Check(not rows["Edit rule"].disabled() and not rows["Rule enabled"].disabled(), "disabled rule can be selected and reenabled")
Check(rows["Add Rule"].button.alpha == 1 and rows["Add Rule"].button.mouseEnabled, "adding a new rule stays available")
before = Copy(api.GetRules())
for _, name in ipairs({ "Copy Rule", "Delete Rule", "Move Rule Up", "Move Rule Down" }) do
    Check(rows[name].button.alpha == 0.3 and not rows[name].button.mouseEnabled, "selected rule off action " .. name)
    rows[name].click()
end
oldName("Blocked disabled rename")
oldSize(200)
for _, name in ipairs(settings) do rows[name].set(0.2, 0.3, 0.4) end
rows["Quest Objective"].set(true)
for _, name in ipairs(dropdowns) do rows[name].set(rows[name].items[1].key, true) end
deletePopup.onConfirm()
Same(api.GetRules(), before, "disabled rule data remains unchanged")
rows["Rule enabled"].set(true); f.Flush()
Check(not rows["Rule name"].disabled() and not rows["Nameplate size (%)"].disabled(), "reenabling restores ordinary editing")
Check(not rows["Override health bar"].disabled() and not rows["Override cast bar"].disabled(), "override masters remain editable")
Check(rows["Custom health color"].disabled(), "health override off still locks dependents after rule reenable")
Check(rows["Custom health color"].disabledTooltip():find("Override health bar", 1, true), "health requirement tooltip retained")
Check(rows["Custom cast color"].disabled(), "cast override off still locks dependents after rule reenable")
rows["Nameplate size (%)"].set(125)
Check(first.style.scale == 125, "enabled settings change normally")
rows["Rule enabled"].set(false)
rows["Edit rule"].set("2")
Check(not rows["Rule name"].disabled(), "selecting an enabled rule unlocks its editor")
oldName("Old disabled input")
Check(first.name ~= "Old disabled input" and second.name == "Other rule", "stale disabled-rule name callback cannot change another rule")
rows["Enable rule styling"].set(false)
rows["Enable rule styling"].set(true)
Check(first.enabled == false and second.enabled == true, "global toggle preserves individual disabled flags")
rows["Edit rule"].set("1")
rows["Add Rule"].click()
Check(#api.GetRules() == 3 and api.GetSettings().selectedRule == 1 and api.GetRules()[1].enabled,
    "can add a new enabled rule while an older rule is disabled")
print("PASS: " .. checks .. " global/rule editor locks, tooltips, stale callbacks and restoration checks")
