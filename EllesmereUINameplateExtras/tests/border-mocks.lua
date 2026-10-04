-- Mock only the shared renderer boundary; tests assert its arguments and the
-- actual Extras suppression/restoration lifecycle, not custom strip drawing.
local api = {}
local borders = setmetatable({}, { __mode = "k" })
function api.GetBorderTextureDropdown()
    return { solid = "Solid", blizz = "Blizzard", glow = "Glow", pixels = "Pixels", ["sm:Test Border"] = "Test Border" },
        { "solid", "blizz", "glow", "pixels", "sm:Test Border" }
end
api.PP = {
    GetBorders = function(frame) return borders[frame] end,
    CreateBorder = function(frame, r, g, b, a, size, _, _, guarded)
        local border = borders[frame]
        if not border then border = CreateFrame("Frame", nil, frame); borders[frame] = border end
        border.size, border.guarded = size or border.size, guarded
        border.color = r and { r, g, b, a } or border.color
        border:Show()
        return border
    end,
}
function api.ApplyBorderStyle(frame, size, r, g, b, a, texture, x, y, sx, sy, addonKey, sizeKey)
    frame._testBorder = { size = size, color = { r, g, b, a }, texture = texture or "solid", addonKey = addonKey, sizeKey = sizeKey }
    if size <= 0 then frame:Hide(); return end
    frame:Show()
    if texture == "solid" or not texture then api.PP.CreateBorder(frame, r, g, b, a, size) end
end
return api
