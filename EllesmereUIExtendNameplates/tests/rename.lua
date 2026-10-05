-- Run from repository root with Lua or fengari.
SlashCmdList = {}
function UnitFullName() return "RenameCharacter", "TestRealm" end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
C_Timer = { After = function() end }
local checks = 0
local function Check(value, label) checks = checks + 1; assert(value, label) end
EllesmereUINameplateExtrasDB = { profiles = { Default = { rules = { { name = "Do not migrate", enabled = true, conditions = {}, style = {} } } } } }
local legacy = EllesmereUINameplateExtrasDB
assert(loadfile("EllesmereUIExtendNameplates/Nameplates.lua"))("EllesmereUIExtendNameplates", {})
local api = assert(EllesmereUIExtendNameplates)
Check(EllesmereUINameplateExtras == nil, "no legacy public API alias")
Check(EllesmereUIExtendNameplatesDB == nil, "settings do not initialize before an accessor/addon load")
local settings = api.GetSettings()
Check(settings == EllesmereUIExtendNameplatesDB.profiles.Default, "new SavedVariables namespace used")
Check(settings.rules[1].name ~= "Do not migrate" and EllesmereUINameplateExtrasDB == legacy, "old settings ignored without mutation/migration")
Check(SLASH_EXTENDNAMEPLATES1 == "/enp" and SLASH_EXTENDNAMEPLATES2 == "/extendnameplates", "renamed diagnostic commands")
Check(SLASH_EXTENDNAMEPLATES3 == nil and SlashCmdList.NAMEPLATEEXTRAS == nil, "no old slash alias")
Check(type(SlashCmdList.EXTENDNAMEPLATES) == "function", "new slash handler registered")
local newStore = { rules = { { name = "New namespace settings", enabled = true, conditions = {}, style = {} } } }
EllesmereUIExtendNameplatesDB = newStore
Check(api.GetSettings().rules[1].name == "New namespace settings", "new saved settings/table replacement preserved")
Check(EllesmereUINameplateExtrasDB == legacy, "new operations never touch legacy settings")
print("PASS: " .. checks .. " renamed API/SavedVariables/commands, fresh settings and no legacy migration or aliases")
