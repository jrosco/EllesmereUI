-- Run from the repository root: npx.cmd --yes --package fengari-node-cli fengari tests/profile-sync.lua
local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = deepCopy(v) end
    return copy
end

_G.EllesmereUI = { Lite = { DeepCopy = deepCopy } }
function CreateFrame()
    return { RegisterEvent = function() end, SetScript = function() end }
end
function wipe(t) for k in pairs(t) do t[k] = nil end end
assert(loadfile("EllesmereUI_ProfileSync.lua"))("EllesmereUI", {})
local EUI = _G.EllesmereUI

local failed, passed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end
local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function overlay(src, dst, ex)
    EUI._SelectiveOverlay(src, dst, ex or {}, deepCopy)
    return dst
end

test("exact override exclusions compose with wildcard geometry in copy", function()
    local ex = { ["bars.*.buttonWidth"] = true, ["bars.main.bgOpacity"] = true }
    local src = { bars = { main = { buttonWidth = 30, bgOpacity = 0.2, enabled = true } } }
    local copy = EUI._SelectiveCopy(src, ex)
    equal(copy.bars.main.buttonWidth, nil)
    equal(copy.bars.main.bgOpacity, nil, "override-owned opacity")
    equal(copy.bars.main.enabled, true)
    equal(src.bars.main.bgOpacity, 0.2, "source untouched")
end)

test("exact override exclusions compose with wildcard geometry in overlay", function()
    local dst = { bars = { main = { buttonWidth = 50, bgOpacity = 0.8 } } }
    overlay({ bars = { main = { buttonWidth = 30, bgOpacity = 0.2, enabled = false } } }, dst,
        { ["bars.*.buttonWidth"] = true, ["bars.main.bgOpacity"] = true })
    equal(dst.bars.main.buttonWidth, 50)
    equal(dst.bars.main.bgOpacity, 0.8, "override-owned opacity")
    equal(dst.bars.main.enabled, false)
end)

test("nil border resets and destination-only values propagate", function()
    local dst = { borderOffset = 7, bars = { main = { borderOffset = 9, buttonWidth = 50, stale = true } } }
    overlay({ bars = { main = { enabled = true } } }, dst, { ["bars.*.buttonWidth"] = true })
    equal(dst.borderOffset, nil, "top-level reset")
    equal(dst.bars.main.borderOffset, nil, "nested reset")
    equal(dst.bars.main.stale, nil)
    equal(dst.bars.main.buttonWidth, 50)
end)

test("absent and scalar source containers retain only excluded descendants", function()
    for _, src in ipairs({ {}, { panel = false }, { panel = 12 } }) do
        local color = { r = 0.9, g = 0.8, b = 0.7 }
        local panel = { color = color, stale = 1 }
        local dst = { panel = panel }
        overlay(src, dst, { ["panel.color.r"] = true })
        equal(dst.panel, panel, "panel identity")
        equal(dst.panel.color, color, "color identity")
        equal(color.r, 0.9)
        equal(color.g, nil)
        equal(color.b, nil)
        equal(panel.stale, nil)
    end
end)

test("scalar replacement wins when no excluded descendant exists", function()
    local dst = { panel = { color = { g = 0.8 }, stale = 1 } }
    overlay({ panel = false }, dst, { ["panel.color.r"] = true })
    equal(dst.panel, false)
    dst = { panel = { stale = 1 } }
    overlay({}, dst, { ["panel.color.r"] = true })
    equal(dst.panel, nil)
end)

test("nested wildcard and exact color paths compose at every level", function()
    local ex = { ["bars.*.color.r"] = true, ["bars.main.color.g"] = true,
        ["bars.*.layers.*.color.a"] = true }
    local src = { bars = { main = { color = { r = 0.1, g = 0.2, b = 0.3 },
        layers = { { color = { a = 0.4, r = 0.5 } } } }, other = { color = { r = 0.6, g = 0.7 } } } }
    local copy = EUI._SelectiveCopy(src, ex)
    equal(copy.bars.main.color.r, nil)
    equal(copy.bars.main.color.g, nil)
    equal(copy.bars.main.color.b, 0.3)
    equal(copy.bars.other.color.r, nil)
    equal(copy.bars.other.color.g, 0.7)
    equal(copy.bars.main.layers[1].color.a, nil)
    local dst = { bars = { main = { color = { r = 0.9, g = 0.8, stale = 1 },
        layers = { { color = { a = 0.7, stale = 1 } } } } } }
    local color, layerColor = dst.bars.main.color, dst.bars.main.layers[1].color
    overlay(src, dst, ex)
    equal(dst.bars.main.color, color)
    equal(color.r, 0.9)
    equal(color.g, 0.8)
    equal(color.b, 0.3)
    equal(color.stale, nil)
    equal(dst.bars.main.layers[1].color, layerColor)
    equal(layerColor.a, 0.7)
    equal(layerColor.r, 0.5)
    equal(layerColor.stale, nil)
end)

test("arrays and sparse source remove stale entries without losing protected geometry", function()
    local src = { bars = { [1] = { value = "new" }, [3] = { value = "third" } }, order = { "one" } }
    local dst = { bars = { { value = "old", width = 40 }, { value = "stale", width = 50 },
        { value = "old" }, { value = "remove" } }, order = { "old", "stale" } }
    local bars, first, second, third, order = dst.bars, dst.bars[1], dst.bars[2], dst.bars[3], dst.order
    overlay(src, dst, { ["bars.*.width"] = true })
    equal(dst.bars, bars)
    equal(bars[1], first)
    equal(first.value, "new")
    equal(first.width, 40)
    equal(bars[2], second)
    equal(second.value, nil)
    equal(second.width, 50)
    equal(bars[3], third)
    equal(third.value, "third")
    equal(bars[4], nil)
    equal(dst.order, order, "unexcluded live array identity")
    equal(order[1], "one")
    equal(order[2], nil)
    equal(src.bars[2], nil, "source stays sparse")
    first.value = "changed"
    equal(src.bars[1].value, "new", "no source alias")
end)

test("whole excluded subtrees including empty tables stay intact", function()
    local position, empty = { x = 10 }, {}
    local dst = { position = position, panel = { owned = empty, stale = 1 }, stale = 2 }
    overlay({}, dst, { position = true, ["panel.owned"] = true })
    equal(dst.position, position)
    equal(dst.panel.owned, empty)
    equal(dst.panel.stale, nil)
    equal(dst.stale, nil)
end)

test("parentPath API and full-path wildcard matching", function()
    local ex = { ["outer.bars.*.color.r"] = true, ["outer.bars.main.color.g"] = true }
    local src = { bars = { main = { color = { r = 1, g = 2, b = 3 } } },
        unrelated = { bars = { main = { color = { r = 4 } } } } }
    local copy = EUI._SelectiveCopy(src, ex, "outer")
    equal(copy.bars.main.color.r, nil)
    equal(copy.bars.main.color.g, nil)
    equal(copy.unrelated.bars.main.color.r, 4)
    local dst = { bars = { main = { color = { r = 8, g = 9 } } } }
    EUI._SelectiveOverlay(src, dst, ex, deepCopy, "outer")
    equal(dst.bars.main.color.r, 8)
    equal(dst.bars.main.color.g, 9)
    equal(dst.bars.main.color.b, 3)
end)

test("real sync APIs retain override ownership, geometry and live identities", function()
    local folder = "EllesmereUIActionBars"
    local srcData = { bars = { main = { buttonWidth = 30, bgOpacity = 0.2, enabled = true } } }
    local dstData = { bars = { main = { buttonWidth = 50, bgOpacity = 0.8, borderOffset = 7 } } }
    local bars, main = dstData.bars, dstData.bars.main
    local source = { addons = { [folder] = srcData }, specOverrides = {
        { values = { default = { [folder .. "\31bars\30main\30bgOpacity"] = 0.2 } } } } }
    local destination = { addons = { [folder] = dstData } }
    EllesmereUIDB = { activeProfile = "Source", profiles = { Source = source, Destination = destination,
        Fresh = {} } }
    EUI.SyncModuleToProfiles(folder, { Source = true, Destination = true, Fresh = true })
    equal(dstData.bars.main.bgOpacity, 0.8)
    equal(dstData.bars.main.buttonWidth, 50)
    equal(dstData.bars.main.borderOffset, nil)
    equal(EllesmereUIDB.profiles.Fresh.addons[folder].bars.main.bgOpacity, nil)
    equal(EllesmereUIDB.profiles.Fresh.addons[folder].bars.main.buttonWidth, nil)
    EllesmereUIDB.activeProfile = "Destination"
    local refreshes, merges = 0, 0
    EUI.RefreshAllAddons = function() refreshes = refreshes + 1 end
    EUI.Lite._dbRegistry = { { folder = folder, profile = dstData, _profileDefaults = {} } }
    EUI.Lite.DeepMergeDefaults = function(profile) equal(profile, dstData); merges = merges + 1 end
    EUI.SyncModuleFromProfile(folder, "Source", { Destination = true })
    equal(destination.addons[folder], dstData)
    equal(dstData.bars, bars)
    equal(dstData.bars.main, main)
    equal(main.bgOpacity, 0.8)
    equal(main.buttonWidth, 50)
    equal(refreshes, 1)
    equal(merges, 1)
    equal(EUI._syncExclusions[folder]["bars.main.bgOpacity"], nil, "registry stays static")
end)

test("destination conditional override paths remain owned when source containers disappear", function()
    local folder = "EllesmereUIActionBars"
    local main = { color = { r = 0.8, g = 0.7 }, buttonWidth = 50, stale = 1 }
    local dstData = { bars = { main = main } }
    local overrides = { { values = { condition = {
        [folder .. "\31bars\30main\30color\30r"] = false,
    } } } }
    local source = { addons = { [folder] = {} } }
    local destination = { addons = { [folder] = dstData }, condOverrides = overrides }
    EllesmereUIDB = { activeProfile = "Source", profiles = { Source = source, Destination = destination } }
    EUI.SyncModuleToProfiles(folder, { Destination = true })
    equal(dstData.bars.main, main)
    equal(main.buttonWidth, 50)
    equal(main.color.r, 0.8)
    equal(main.color.g, nil)
    equal(main.stale, nil)
    equal(destination.condOverrides, overrides)
    equal(overrides[1].values.condition[folder .. "\31bars\30main\30color\30r"], false)
    equal(source.specOverrides, nil, "no override store creation")
    equal(source.condOverrides, nil)
end)

print(string.format("profile-sync: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
