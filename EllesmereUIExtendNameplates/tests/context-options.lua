-- Run from the repository root with Lua or fengari.
local f = assert(loadfile("EllesmereUIExtendNameplates/tests/runtime.lua"))("ui-locks")
local api, rows, checks = f.api, f.rows, 0
local function Check(value, label) checks = checks + 1; assert(value, label) end
local first = api.GetRules()[1]
Check(#rows["Player combat state"].items == 2 and #rows["Instance Type"].items == 7, "both multi-choice dropdowns built")
Check(rows["Player combat state"].row == rows["Instance Type"].row, "context conditions share a settings row")
Check(not rows["Player combat state"].get("inCombat") and not rows["Player combat state"].get("outOfCombat"), "empty means both combat states/Any")
rows["Player combat state"].set("inCombat", true)
rows["Player combat state"].set("outOfCombat", true)
Check(first.conditions.playerCombat.inCombat and first.conditions.playerCombat.outOfCombat, "combat choices combine rather than replacing each other")
rows["Player combat state"].set("inCombat", false)
Check(not first.conditions.playerCombat.inCombat and first.conditions.playerCombat.outOfCombat, "deselect preserves other combat choice")
rows["Player combat state"].set("outOfCombat", false)
Check(next(first.conditions.playerCombat) == nil, "clear returns to Any")
rows["Instance Type"].set("raid", true); rows["Instance Type"].set("dungeon", true)
Check(first.conditions.instanceType.raid and first.conditions.instanceType.dungeon, "instance multi-selection")
local code = assert(api.ExportRuleSet())
Check(api.ImportRuleSet(code), "context rule sharing imports")
EllesmereUI:RefreshPage()
first = api.GetRules()[1]
Check(first.conditions.instanceType.raid and first.conditions.instanceType.dungeon
    and next(first.conditions.playerCombat) == nil, "context selections sharing roundtrip")
EllesmereUI.IS_FOREVER = true
EllesmereUI:RefreshPage()
for _, item in ipairs(rows["Instance Type"].items) do
    local blocked = item.key == "arena" or item.key == "scenario" or item.key == "delve"
    Check(item.lockedFn() == blocked, "Forever item gate " .. item.key)
end
rows["Instance Type"].set("delve", true)
Check(not first.conditions.instanceType.delve, "blocked Forever selection callback is guarded")
EllesmereUI.IS_FOREVER = false
rows["Instance Type"].set("delve", true)
Check(first.conditions.instanceType.delve, "Retail choice available")
local combat, instance = rows["Player combat state"].set, rows["Instance Type"].set
rows["Enable rule styling"].set(false)
combat("inCombat", true); instance("world", true)
Check(next(first.conditions.playerCombat) == nil and not first.conditions.instanceType.world, "global lock guards stale context callbacks")
rows["Enable rule styling"].set(true)
rows["Rule enabled"].set(false)
rows["Player combat state"].set("inCombat", true)
Check(next(first.conditions.playerCombat) == nil, "disabled rule locks context edits")
rows["Rule enabled"].set(true)
f.Flush()
print("PASS: " .. checks .. " context dropdowns, Any/default semantics, OR selection, sharing, Forever gates and editor locks")
