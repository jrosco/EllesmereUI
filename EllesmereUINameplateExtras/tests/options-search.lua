-- Run from the repository root with Lua/fengari; optional case: prebuild, sections, actions.
-- Loads actual GlobalSearch prebuild/index and composite factories; models native UI and Panel reflow.
unpack = unpack or table.unpack
local case = arg and arg[1]
local frameCount, dropdowns, refreshes = 0, {}, {}
local function Noop() end
function CreateFrame(kind, _, parent)
    assert(parent == nil or rawget(parent, "nativeFrame"), "native UI parent required (absorber is not a frame)")
    frameCount = frameCount + 1
    local frame = { nativeFrame = true, parent = parent, kind = kind, children = {}, height = 50 }
    if parent then parent.children[#parent.children + 1] = frame end
    function frame:GetWidth() return self.width or 800 end
    function frame:GetHeight() return self.height end
    function frame:GetFrameLevel() return 10 end
    function frame:SetSize(w, h) self.width, self.height = w, h end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetText(text) self.text = text end
    function frame:SetScript(event, fn) self[event] = fn end
    function frame:GetChildren() return unpack(self.children) end
    function frame:CreateFontString() return CreateFrame("FontString", nil, self) end
    for _, key in ipairs({ "SetJustifyH", "SetWordWrap", "SetMaxLines", "SetFrameLevel",
        "EnableMouse", "SetMouseClickEnabled", "Hide", "Show" }) do frame[key] = Noop end
    return frame
end

local function Rule(name)
    return { name = name, enabled = true, conditions = { unitType = {}, reaction = {}, classification = {},
        target = { yes = true }, castState = {}, spellSchool = {} },
        style = { healthColor = { r = 1, g = 1, b = 1 }, borderColor = { r = 1, g = 1, b = 1 } } }
end
local db = { selectedRule = 1, rules = { Rule("First rule"), Rule("Second rule") } }
EllesmereUINameplateExtras = { GetSettings = function() return db end, Refresh = Noop,
    CastStyleDefaults = {} }
local spec, currentSection, pageRows, index, fields = nil, nil, {}, {}, {}
local searchEntries
local parent = CreateFrame("Frame") -- GlobalSearch also passes a real wrapper, not an absorber parent.
local function UpdateIndex()
    for _, entry in ipairs(searchEntries) do
        if entry.page == "Rules" then index[entry.label] = entry end
    end
end
local function Register(label, tooltip, section)
    EllesmereUI._RegisterSearchEntry(label, nil, tooltip, "plugin:test:NameplateStyle", "Rules",
        section or currentSection)
    UpdateIndex()
end
local function Row(label, y, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth() - 40, height or 50)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
    row._origAnchor = { "TOPLEFT", parent, "TOPLEFT", 20, y }
    row._labelText, row.section = label, currentSection
    pageRows[#pageRows + 1] = row
    return row, row.height
end
local W = {}
function W:SectionHeader(_, text, y)
    currentSection = text
    Register(text, nil, text)
    local row, h = Row(nil, y, 40)
    row._sectionName = text
    return row, h
end
function W:Dropdown(_, text, y, values, get, set, order, tooltip)
    Register(text, tooltip); fields[text] = { get = get, set = set, values = values }
    return Row(text, y)
end
function W:Toggle(_, text, y, get, set, tooltip)
    Register(text, tooltip); fields[text] = { get = get, set = set }; return Row(text, y)
end
function W:Slider(_, text, y, min, max, step, get, set, tooltip)
    Register(text, tooltip); fields[text] = { get = get, set = set }; return Row(text, y)
end
function W:DualRow(_, y, left, right)
    Register(left and left.text, left and left.tooltip)
    Register(right and right.text, right and right.tooltip)
    local row, h = Row((left and left.text or "") .. " " .. (right and right.text or ""), y)
    row._leftRegion = CreateFrame("Frame", nil, row)
    row._rightRegion = CreateFrame("Frame", nil, row)
    for i, cfg in ipairs({ left, right }) do
        local region = i == 1 and row._leftRegion or row._rightRegion
        region._slotLabel = cfg.text
        fields[cfg.text] = { get = cfg.getValue, set = cfg.setValue }
    end
    return row, h
end
function W:Button(_, text, y, click)
    Register(text)
    local row, h = Row(text, y)
    local button = CreateFrame("Button", nil, row)
    button.OnClick = click
    fields[text] = { click = click, row = row, button = button }
    return row, h
end
EllesmereUI = {
    Widgets = W, CONTENT_PAD = 20, L = function(text) return text end,
    PanelPP = { Size = function(f, ...) f:SetSize(...) end, Point = function(f, ...) f:SetPoint(...) end },
    IsSearchPrebuild = function() return EllesmereUI._prebuilding == true end,
    MakeFont = function(p) return p:CreateFontString() end,
    RegisterWidgetRefresh = function(fn) refreshes[#refreshes + 1] = fn end,
    BuildVisOptsCBDropdown = function(p, width, level, items, get, set, _, _, _, _, _, opts)
        local button = CreateFrame("Button", nil, p)
        dropdowns[opts.label] = { parent = p, items = items, get = get, set = set, emptyLabel = opts.emptyLabel }
        return button, Noop
    end,
    RegisterPlugin = function(_, s) spec = s; return true end,
    IsPluginRegistered = function() return false end,
    GetPluginModuleKey = function() return "plugin:test:NameplateStyle" end,
    InvalidateModulePageCache = Noop,
    IsDevModeActive = function() return true end,
    Show = Noop,
}
-- Inspect private closures without copying production implementation into the fixture.
local function Upvalue(fn, wanted)
    for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        assert(name, "missing production upvalue: " .. wanted)
        if name == wanted then return value end
    end
end
local searchNS = { modules = {}, pageCache = {} }
assert(loadfile("EllesmereUI_GlobalSearch.lua"))("EllesmereUI", searchNS)
searchEntries = Upvalue(EllesmereUI._RegisterSearchEntry, "_searchIndex")
local ensureSearchUI = Upvalue(EllesmereUI.Show, "EnsureSearchUI")
local runPrebuild = Upvalue(ensureSearchUI, "RunPrebuildPass")
local pending = {}
C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
function InCombatLockdown() return false end
function debugprofilestop() return 0 end
EllesmereUI._SnapshotAndClearWidgetRefreshList = function()
    local saved = refreshes
    refreshes = {}
    return saved
end
EllesmereUI._RestoreWidgetRefreshList = function(saved) refreshes = saved end
-- Load all row definitions, keeping lightweight UI-boundary stubs except for
-- the actual composites whose anchors, labels and callbacks are under test.
local mockRows = {}
for key, value in pairs(W) do mockRows[key] = value end
EllesmereUI._deferredInits = {}
EllesmereUI.DUAL_GAP = 42
function GetLocale() return "enUS" end
EllesmereUI._widgetInternals = {
    TagOptionRow = function(row, _, label)
        row._labelText, row.section = label, currentSection
        pageRows[#pageRows + 1] = row
        Register(label)
    end,
    IndexSlotForSearch = function(_, text) Register(text) end,
}
EllesmereUI.MakeStyledButton = function(button, text, _, _, click)
    button.OnClick = click
    fields[text] = { click = click, row = button.parent, button = button }
end
assert(loadfile("EllesmereUIOptions/EllesmereUI_Widgets_Rows.lua"))()
EllesmereUI._deferredInits[1]()
for key, value in pairs(mockRows) do W[key] = value end
local function Build()
    currentSection, pageRows = nil, {}
    local h = spec.modules[1].buildPage("Rules", parent, -6)
    -- Panel captures final anchors after the builder finishes, including manual moves.
    for _, row in ipairs(pageRows) do row._origAnchor = { unpack(row.point) } end
    return h
end
EllesmereUI.RefreshPage = Build
assert(loadfile("EllesmereUINameplateExtras/EllesmereUINameplateExtras_Options.lua"))()
searchNS.modules["plugin:test:NameplateStyle"] = {
    pages = { "Rules", "About" }, buildPage = spec.modules[1].buildPage,
}

local actions = { "Add Rule", "Copy Rule", "Delete Rule", "Move Rule Up", "Move Rule Down" }
local function PrebuildTest()
    local ok = pcall(CreateFrame, "Frame", nil, {})
    assert(not ok, "fixture must reject non-native parents")
    local previousPageRefresh = function() error("previous live page refresh invoked during prebuild") end
    refreshes[1] = previousPageRefresh
    local before = frameCount
    local built, err = pcall(function()
        runPrebuild()
        while #pending > 0 do table.remove(pending, 1)() end
    end)
    assert(built, "absorber prebuild aborted: " .. tostring(err))
    UpdateIndex()
    -- The real pass allocates its hidden parent and reused wrapper, but no controls.
    assert(frameCount == before + 2, "prebuild built controls")
    assert(#refreshes == 1 and refreshes[1] == previousPageRefresh,
        "prebuild leaked refresh callbacks or lost the prior live page's registry")
    assert(EllesmereUI.Widgets == W and not EllesmereUI._prebuilding, "prebuild state not restored")
    assert(index["Enable rule styling"] and index["Enable rule styling"].section == "RULE STYLING",
        "global styling toggle must be indexed on Rules")
    local aboutIndexed = false
    for _, entry in ipairs(searchEntries) do
        assert(not (entry.page == "About" and entry.label == "Enable rule styling"),
            "global toggle is still indexed on About")
        if entry.page == "About" and entry.label == "CAST COLORS" then aboutIndexed = true end
    end
    assert(aboutIndexed, "About sections must be indexed without creating live paragraph controls")
    refreshes = {}
    for _, label in ipairs({ "Unit type", "Reaction", "Classification", "Target state", "Threat", "Cast state",
        "Spell school", "Quest Objective", "Nameplate size (%)", "Opacity (%)", "Health-bar texture",
        "Cast-bar texture", "Cast border size" }) do
        assert(index[label], "prebuild missed " .. label)
    end
    assert(index["Unit type"].tooltip:find("Any creature", 1, true), "condition tooltip lost")
    for _, text in ipairs(actions) do assert(index[text], "action search entry lost: " .. text) end
    Build()
    assert(#refreshes == 7, "live condition refresh registrations missing")
    for _, label in ipairs({ "Unit type", "Reaction", "Classification", "Target state", "Cast state", "Spell school", "Threat" }) do
        assert(dropdowns[label] and rawget(dropdowns[label].parent, "nativeFrame"), "live dropdown missing: " .. label)
        assert(dropdowns[label].parent._slotLabel == label, "slot highlight metadata lost")
    end
    local paired = false
    for _, row in ipairs(pageRows) do
        if row._labelText == "Threat Quest Objective" then
            paired = dropdowns["Threat"].parent == row._leftRegion and type(fields["Quest Objective"].set) == "function"
        end
    end
    assert(paired, "Threat dropdown and Quest Objective toggle must share one settings row")
    local unit = dropdowns["Unit type"]
    assert(unit.emptyLabel == "Any unit" and #unit.items == 4)
    unit.set("npc", true); unit.set("player", true)
    assert(unit.get("npc") and unit.get("player"), "multi-selection callbacks lost")
    unit.set("npc", false)
    assert(not unit.get("npc") and unit.get("player"), "deselect erased another selection")
    unit.set("player", false)
    assert(next(db.rules[1].conditions.unitType) == nil, "empty selection must mean Any")
    print("PASS prebuild: actual GlobalSearch pass/index; two wrapper frames, zero controls; seven live dropdowns")
end
local function SectionsTest()
    Build() -- first registration is retained, exactly like GlobalSearch.
    local destinations = {}
    for label, entry in pairs(index) do destinations[label] = entry.section end
    fields["Edit rule"].set("2")
    fields["Rule name"].set("Renamed second rule")
    local liveSections = {}
    for _, row in ipairs(pageRows) do if row._sectionName then liveSections[row._sectionName] = true end end
    for _, label in ipairs({ "Edit rule", "Unit type", "Target state", "Cast state", "Nameplate size (%)",
        "Health-bar texture", "Cast border size" }) do
        local section = destinations[label]
        assert(liveSections[section], "stale exact search destination for " .. label .. ": " .. section)
        local target
        for _, row in ipairs(pageRows) do
            if row.section == section and row._labelText and row._labelText:find(label, 1, true) then target = row; break end
        end
        assert(target, "search destination has no matching setting row: " .. label)
    end
    for label, section in pairs(destinations) do
        assert(liveSections[section], "stale exact search destination for " .. label .. ": " .. section)
    end
    assert(fields["Rule name"].get() == "Renamed second rule", "selected rule context missing")
    assert(fields["Edit rule"].values["2"]:find("Renamed second rule", 1, true), "selector context stale")
    assert(fields["Edit rule"].values["2"] == "[2] Renamed second rule", "rule priority/name format incorrect")
    print("PASS sections: first-indexed exact destinations survive selection and rename; current name/position visible")
end
local function ActionsTest()
    db.selectedRule = 1
    Build()
    local actionRows, seen = {}, {}
    for _, text in ipairs(actions) do
        local action = assert(fields[text], "action missing: " .. text)
        if not seen[action.row] then seen[action.row] = true; actionRows[#actionRows + 1] = action.row end
    end
    -- Panel ApplyInlineSearch preserves each row's original X and consumes its height, once per tagged member.
    local y, height = -46, 0
    for _, row in ipairs(actionRows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", row._origAnchor[4], y)
        y, height = y - row:GetHeight(), height + row:GetHeight()
    end
    print("Action reflow evidence: " .. #actionRows .. " tagged rows, " .. height .. "px consumed")
    assert(#actionRows == 2 and height == 114, "five actions must reflow as two supported composite rows")
    for i, text in ipairs(actions) do
        local action = fields[text]
        assert(action.row.point[4] == 20, "search retained a staircase horizontal offset")
        assert(action.button.point[2] == action.row, "button detached from reflow container")
        assert(action.button.point[5] == 0, "buttons must share their row's vertical center")
        assert(math.abs(action.button.point[4]) + action.button.width / 2 <= action.row.width / 2,
            "action button extends beyond its row")
        assert(action.row == actionRows[i <= 3 and 1 or 2], "action grouping/order changed")
        assert(index[text], "individual action search label missing")
        assert(type(action.click) == "function", "action callback missing")
    end
    -- Clearing search restores row anchors, preserving every child-relative anchor.
    for _, row in ipairs(actionRows) do row:SetPoint(unpack(row._origAnchor)) end
    assert(actionRows[2].point[5] == actionRows[1].point[5] - 57, "normal rows overlap")
    fields["Move Rule Down"].click()
    assert(db.selectedRule == 2 and db.rules[2].name == "First rule", "move callback changed")
    fields["Copy Rule"].click()
    assert(db.selectedRule == 3 and db.rules[3].name == "First rule Copy", "copy callback changed")
    fields["Add Rule"].click()
    assert(db.selectedRule == 1 and #db.rules == 4, "add callback changed")
    print("PASS actions: two full-width search rows; child-relative buttons; restore and action callbacks")
end
if not case or case == "prebuild" then PrebuildTest() end
if not case or case == "sections" then SectionsTest() end
if not case or case == "actions" then ActionsTest() end
