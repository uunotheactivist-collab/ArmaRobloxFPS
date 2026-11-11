-- M2 environment lighting (2026-11-11), candidate C9 (= C8 + specular compensation). Run in Studio (command bar / execute_luau). Edit mode writes the
-- place, a Server datamodel in Play writes replicated runtime values. Set MODE below:
--   "apply"  : writes the M2 lighting values
--   "revert" : writes A3 back (= checkpoint 2026-11-11_before_m2_lighting\lighting_before.json)
-- Only Lighting properties and the Lighting children Atmosphere / ColorCorrection are touched. Sky, Bloom, SunRays and
-- DepthOfField are unchanged. Evidence: Fidelity Audit 2026-11-10\m2_lighting\ (EXPERIMENT_LOG.md, RESULTS.md).
local MODE = "apply"

local M2 = {
	-- Sun: the real Nuevo Laredo sun, 27.5 N, June solstice, 08:00 local solar time: elevation 36.20, azimuth 79.94
	-- [geometry MEASURED; date and time PARAMETER]. Roblox keeps the sun's z at sin(GeographicLatitude - 23.44) at every
	-- hour (MEASURED 2026-11-11), so its latitude is not geography. The engine pair that reproduces the real vector
	-- (0.7946, 0.5906, -0.1410) is below [PARAMETER: engine values].
	GeographicLatitude = 15.333,
	ClockTime = 8.4415,
	-- Exposure / sun balance: exposure +0.5 stop over A3 with sun and fill scaled by 2^-0.5. Lit surfaces are unchanged
	-- (measured within 1 luma); the sky rises (158,193,225) -> (183,213,238) [reference MODDED (175,217,250); MEASURED].
	ExposureCompensation = 1.25, -- A3 0.75
	Brightness = 2.404, -- A3 3.4 (3.4 * 2^-0.5)
	-- Shade fill: neutral, because the reference near shade is neutral (B-R -11..+3; MEASURED). Lit:shade walls 3.05 /
	-- ground 3.35 (tuning), 2.91 / 2.91 (held-out); reference MODDED plaster 2.69-3.33, ground 2.86-3.48.
	OutdoorAmbient = Color3.fromRGB(82, 82, 82), -- A3 (78, 78, 80)
	EnvironmentDiffuseScale = 0.0707, -- A3 0.15 (less sky-blue fill in shade)
	EnvironmentSpecularScale = 0.1768, -- A3 0.25 * 2^-0.5: completes the exposure / sun balance (C9). C8 left it at 0.25,
	-- so sky reflections on glossy and dark surfaces came out 1.41x A3 and the weapons' black parts read blue in shade
	-- (fill off B-R +13). Environment metrics: C9 vs C8 mean |d luma| 0.56; held-out E 0.097 -> 0.092
	Atmosphere = { Color = Color3.fromRGB(240, 246, 255), Decay = Color3.fromRGB(150, 170, 200), Haze = 3.5, Density = 0.25 }, -- unchanged (A3: blue sky; far-wall contrast already falls as in the reference)
	ColorCorrection = { Enabled = false }, -- A3 had Saturation -0.1 / Contrast +0.05: no measured benefit, it deepened shade
}
local A3 = {
	GeographicLatitude = 0, ClockTime = 9.5, ExposureCompensation = 0.75, Brightness = 3.4,
	OutdoorAmbient = Color3.fromRGB(78, 78, 80), EnvironmentDiffuseScale = 0.15, EnvironmentSpecularScale = 0.25,
	Atmosphere = { Color = Color3.fromRGB(240, 246, 255), Decay = Color3.fromRGB(150, 170, 200), Haze = 3.5, Density = 0.25 },
	ColorCorrection = { Enabled = true, Saturation = -0.1, Contrast = 0.05, Brightness = 0, TintColor = Color3.new(1, 1, 1) },
}

local L = game:GetService("Lighting")
local v = (MODE == "apply") and M2 or A3
for k, x in v do
	if typeof(x) ~= "table" then L[k] = x end
end
local atm = L:FindFirstChildOfClass("Atmosphere")
if atm then
	for k, x in v.Atmosphere do atm[k] = x end
end
local cc = L:FindFirstChild("ColorCorrection")
if cc then
	for k, x in v.ColorCorrection do cc[k] = x end
end
L:SetAttribute("M2Lighting", (MODE == "apply") and "M2 C9 2026-11-11 (NL June 08:00 sun; neutral fill; exposure 1.25; specular 0.1768); revert: Roblox/Environment/LightingM2/apply_lighting.luau MODE=revert" or nil)
L:SetAttribute("A3Lighting", (MODE == "apply") and nil or "A3 2026-11-10 (YouTube cM2D-CniPXI reference); revert: Roblox/Environment/LightingA3/apply_lighting.luau MODE=revert")
local s = L:GetSunDirection()
return string.format("%s done; sun (%.4f, %.4f, %.4f) elevation %.2f", MODE, s.X, s.Y, s.Z, math.deg(math.asin(s.Y)))
