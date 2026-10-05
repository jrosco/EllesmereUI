local api = _G.EllesmereUIExtendNameplates
if not api then return end

local LEGACY_PREFIX = "!EUI_NPEX_RULES1!"
local PREFIX = "!EUI_NPEX_RULES2!"
local FORMAT = "EllesmereUINameplateExtrasRules" -- stable wire format: pre-rename codes remain compatible
local VERSION = 2
local MAX_CODE_LENGTH = 64000
local MAX_DATA_LENGTH = 128000
local MAX_RULES = api.MaxRules or 12
api.RuleSetMaxCodeLength = MAX_CODE_LENGTH
local Copy

Copy = function(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Copy(child) end
    return result
end

local BOOLEAN_STYLE_KEYS = {
    "healthEnabled", "healthColorEnabled", "borderEnabled", "castEnabled",
    "castColorEnabled", "castOpacityEnabled", "castBorderEnabled",
    "targetArrowsEnabled",
    "healthGlowBackground", "castGlowBackground",
    "textEnabled",
}
local COLOR_STYLE_KEYS = { "healthColor", "borderColor", "castColor", "castBorderColor",
    "healthGlowColor", "castGlowColor", "healthGlowBackgroundColor", "castGlowBackgroundColor" }
local NUMBER_STYLE_RANGES = {
    scale = { 50, 200 }, opacity = { 0, 100 }, borderSize = { 0, 8 },
    castOpacity = { 0, 100 }, castBorderSize = { 0, 8 },
    healthGlowLines = { 2, 16 }, castGlowLines = { 2, 16 },
    healthGlowThickness = { 1, 4 }, castGlowThickness = { 1, 4 },
    healthGlowSpeed = { 1, 8 }, castGlowSpeed = { 1, 8 },
    healthGlowShineSize = { 50, 200 }, castGlowShineSize = { 50, 200 },
}

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function SafeTree(value, depth, budget)
    depth = depth or 0
    budget.n = budget.n + 1
    if budget.n > 20000 or depth > 20 then return false end
    local kind = type(value)
    if kind == "nil" or kind == "boolean" then return true end
    if kind == "number" then return IsFinite(value) end
    if kind == "string" then return #value <= 4096 end
    if kind ~= "table" then return false end
    for key, child in pairs(value) do
        local keyType = type(key)
        if keyType ~= "string" and not (keyType == "number" and IsFinite(key)) then return false end
        if not SafeTree(child, depth + 1, budget) then return false end
    end
    return true
end

local function ValidateRule(rule, index)
    if type(rule) ~= "table" then return nil, ("Rule %d is not a table."):format(index) end
    if type(rule.name) ~= "string" or #rule.name == 0 or #rule.name > 120
       or rule.name:find("|", 1, true) or rule.name:find("%c") then
        return nil, ("Rule %d has an invalid name."):format(index)
    end
    if type(rule.enabled) ~= "boolean" then return nil, ("Rule %d has an invalid enabled value."):format(index) end
    if type(rule.conditions) ~= "table" or type(rule.style) ~= "table" then
        return nil, ("Rule %d is missing its conditions or style."):format(index)
    end
    local validConditions, invalidKey = api.ValidateRuleConditions(rule.conditions)
    if not validConditions then return nil, ("Rule %d has an invalid %s condition."):format(index, invalidKey) end
    if api.ValidateRuleText and not api.ValidateRuleText(rule.style) then
        return nil, ("Rule %d has invalid text slots or colors."):format(index)
    end
    for _, key in ipairs({ "healthGlowStyle", "castGlowStyle" }) do
        if api.ValidateRuleGlowStyle and not api.ValidateRuleGlowStyle(rule.style[key]) then
            return nil, ("Rule %d has an invalid %s setting."):format(index, key)
        end
    end
    if api.ValidateScaleElements and not api.ValidateScaleElements(rule.style.scaleElements) then
        return nil, ("Rule %d has an invalid scale-elements setting."):format(index)
    end
    for _, key in ipairs({ "borderTexture", "castBorderTexture" }) do
        if api.ValidateBorderStyle and not api.ValidateBorderStyle(rule.style[key]) then
            return nil, ("Rule %d has an invalid %s border texture."):format(index, key)
        end
    end
    if api.ValidateTargetArrowStyle and not api.ValidateTargetArrowStyle(rule.style.targetArrowStyle) then
        return nil, ("Rule %d has an invalid target-arrow style."):format(index)
    end
    for _, key in ipairs(BOOLEAN_STYLE_KEYS) do
        local value = rule.style[key]
        if value ~= nil and type(value) ~= "boolean" then
            return nil, ("Rule %d has an invalid %s setting."):format(index, key)
        end
    end
    for _, key in ipairs(COLOR_STYLE_KEYS) do
        local color = rule.style[key]
        if color ~= nil then
            if type(color) ~= "table" then return nil, ("Rule %d has an invalid %s color."):format(index, key) end
            for _, channel in ipairs({ "r", "g", "b" }) do
                local value = color[channel]
                if not IsFinite(value) or value < 0 or value > 1 then
                    return nil, ("Rule %d has an invalid %s color."):format(index, key)
                end
            end
        end
    end
    for key, range in pairs(NUMBER_STYLE_RANGES) do
        local value = rule.style[key]
        if value ~= nil and (not IsFinite(value) or value < range[1] or value > range[2]) then
            return nil, ("Rule %d has an invalid %s value."):format(index, key)
        end
    end
    for _, key in ipairs({ "texture", "castTexture" }) do
        local value = rule.style[key]
        if value ~= nil and (type(value) ~= "string" or #value > 256 or value:find("%c")) then
            return nil, ("Rule %d has an invalid %s texture key."):format(index, key)
        end
    end
    if not SafeTree(rule, 0, { n = 0 }) then return nil, ("Rule %d contains unsupported data."):format(index) end
    return true
end

local function GetCodec()
    local serializer = EllesmereUI and EllesmereUI._Serializer
    local lib = LibStub and LibStub("LibDeflate", true)
    if not (serializer and serializer.Serialize and serializer.Deserialize and lib) then
        return nil, nil, "EUI serialization libraries are unavailable."
    end
    return serializer, lib
end

function api.ExportRuleSet()
    local serializer, lib, err = GetCodec()
    if not serializer then return nil, err end
    local rules = api.GetRules()
    if type(rules) ~= "table" or #rules == 0 or #rules > MAX_RULES then
        return nil, "The current rule set has an invalid rule count."
    end
    for index, rule in ipairs(rules) do
        local ok, reason = ValidateRule(rule, index)
        if not ok then return nil, reason end
    end
    local payload = { format = FORMAT, version = VERSION, rules = rules }
    local ok, serialized = pcall(serializer.Serialize, payload)
    if not ok or type(serialized) ~= "string" then return nil, "Could not serialize the rule set." end
    local compressedOK, compressed = pcall(lib.CompressDeflate, lib, serialized)
    if not compressedOK or type(compressed) ~= "string" then return nil, "Could not compress the rule set." end
    local encodedOK, encoded = pcall(lib.EncodeForPrint, lib, compressed)
    if not encodedOK or type(encoded) ~= "string" then return nil, "Could not encode the rule set." end
    local code = PREFIX .. encoded
    if #code > MAX_CODE_LENGTH then return nil, "The rule set is too large to export." end
    return code
end

function api.ImportRuleSet(code)
    if type(code) ~= "string" then return false, "Paste an Extend Nameplates rule-set code." end
    code = code:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "")
    local codePrefix, expectedVersion
    if code:sub(1, #PREFIX) == PREFIX then
        codePrefix, expectedVersion = PREFIX, VERSION
    elseif code:sub(1, #LEGACY_PREFIX) == LEGACY_PREFIX then
        codePrefix, expectedVersion = LEGACY_PREFIX, 1
    end
    if not codePrefix or #code < #codePrefix + 1 or #code > MAX_CODE_LENGTH then
        return false, "This is not a valid Extend Nameplates rule-set code."
    end
    local serializer, lib, err = GetCodec()
    if not serializer then return false, err end
    local ok, decoded = pcall(lib.DecodeForPrint, lib, code:sub(#codePrefix + 1))
    if not ok or type(decoded) ~= "string" then return false, "Could not decode the rule-set code." end
    local decompressedOK, serialized = pcall(lib.DecompressDeflate, lib, decoded)
    if not decompressedOK or type(serialized) ~= "string" or #serialized > MAX_DATA_LENGTH then
        return false, "The rule-set code is invalid or too large."
    end
    local deserializeOK, payload = pcall(serializer.Deserialize, serialized)
    if not deserializeOK or type(payload) ~= "table" or payload.format ~= FORMAT or payload.version ~= expectedVersion then
        return false, "The rule-set code is damaged or from an unsupported version."
    end
    local rules = payload.rules
    if type(rules) ~= "table" or #rules == 0 or #rules > MAX_RULES then
        return false, ("Imported rule sets must contain 1-%d rules."):format(MAX_RULES)
    end
    local count = 0
    for key in pairs(rules) do
        if type(key) ~= "number" or key < 1 or key > #rules or key ~= math.floor(key) then
            return false, "Imported rules must be a simple ordered list."
        end
        count = count + 1
    end
    if count ~= #rules then return false, "Imported rules contain an empty entry." end
    for index, rule in ipairs(rules) do
        local valid, reason = ValidateRule(rule, index)
        if not valid then return false, reason end
    end
    local settings = api.GetSettings()
    settings.rules = Copy(rules)
    for _, rule in ipairs(settings.rules) do
        api.NormalizeRuleConditions(rule)
        if api.NormalizeScaleElements then rule.style.scaleElements = api.NormalizeScaleElements(rule.style.scaleElements) end
    end
    settings.selectedRule = 1
    api.Refresh()
    return true
end
