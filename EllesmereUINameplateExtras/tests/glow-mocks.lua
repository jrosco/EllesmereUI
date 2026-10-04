-- Shared glow-engine boundary mock: signature gating and teardown mirror EUI.
local G = { starts = 0, stops = 0, PANEL_EXTRA = { panel = true }, STYLES = {
    [1] = { name = "Pixel Glow", procedural = true }, [2] = { name = "Action Button Glow", buttonGlow = true },
    [3] = { name = "Auto-Cast Shine", autocast = true }, [4] = { name = "Shape Glow" },
    [5] = { name = "GCD", atlas = "gcd-atlas" }, [6] = { name = "Modern WoW Glow", atlas = "modern-atlas" },
    [7] = { name = "Classic WoW Glow", texture = "classic-texture" },
} }
function G.StartSpecGlow(host, spec, width, height, kind, extra)
    local signature = { width = width, height = height, kind = kind, panel = extra and extra.panel }
    for key, value in pairs(spec) do signature[key] = value end
    local previous, same = host._mockGlowSpec, host._mockGlowActive == true
    for key, value in pairs(signature) do if not previous or previous[key] ~= value then same = false end end
    for key in pairs(previous or {}) do if signature[key] ~= previous[key] then same = false end end
    if not same then G.starts = G.starts + 1 end
    host._mockGlowActive, host._mockGlowSpec = true, signature
    host:SetAlpha(1)
    return spec.style
end
function G.StopGlow(host)
    if host._mockGlowActive then G.stops = G.stops + 1 end
    host._mockGlowActive, host._mockGlowSpec = false, nil
    for _, sparkle in ipairs(host._euiAcData and host._euiAcData.sparkles or {}) do sparkle:Hide() end
    host:SetAlpha(0)
end
function G.StartAutoCastShine(host, width, r, g, b, scale, height)
    G.starts = G.starts + 1
    host._mockGlowActive = true
    host._mockGlowSpec = { style = 3, width = width, height = height, kind = "bar", scale = scale,
        r = r, g = g, b = b, lowLevel = true }
    local d = host._euiAcData or { sparkles = {} }
    host._euiAcData = d
    d.w, d.h, d.period, d.dotsPerLayer = 0, 0, 2, 4
    local sizes = { 7, 6, 5, 4 }
    for index = 1, 16 do
        local dot = d.sparkles[index] or host:CreateTexture()
        d.sparkles[index] = dot
        dot:SetSize(sizes[math.ceil(index / 4)] * scale, sizes[math.ceil(index / 4)] * scale)
        dot:SetVertexColor(r, g, b, 1)
        dot:Show()
    end
end
return G
