-- A3 lighting (2026-11-10): environment lighting re-graded to the YouTube reference cM2D-CniPXI (the M1 map's lighting
-- reference, DECISIONS D4). Run in Studio EDIT mode (command bar / execute_luau). Set MODE below:
--   "apply"  : writes the A3 values (and creates Lighting.ColorCorrection if missing)
--   "revert" : writes the pre-A3 values back (= checkpoint 2026-11-10_before_a3 / the 2026-11-09 lighting correction)
-- Only Lighting properties and Lighting children are touched; Sky textures, Bloom, SunRays, DepthOfField are unchanged.
-- Evidence: Fidelity Audit 2026-11-10\a3_lighting\ (reference_light.json, RESULTS.md).
local MODE = "apply"

local A3 = {
	ClockTime = 9.5, -- sun from the north-east at 46.7 deg (was 14.5: north-west, same elevation) [I: 4 of 6 reference views' lit / shaded sides]
	Brightness = 3.4, -- was 1.8 (lit plaster ~215-220 vs reference 228 [M])
	OutdoorAmbient = Color3.fromRGB(78, 78, 80), -- was (150, 151, 153): shade fill; lit / shade plaster ~3 : 1 (reference 3.3 [M])
	EnvironmentDiffuseScale = 0.15, -- was 0.3: less sky-blue fill in shade
	EnvironmentSpecularScale = 0.25, -- was 1: less sky sheen on glossy parts (windows, black weapon parts)
	ExposureCompensation = 0.75, -- was 0: brighter sky / highlights (reference p95 ~220 [M])
	Atmosphere = { Color = Color3.fromRGB(240, 246, 255), Decay = Color3.fromRGB(150, 170, 200), Haze = 3.5, Density = 0.25 }, -- was (230, 200, 166) / (106, 112, 125) / 10 / 0.3: blue sky [M (174, 216, 251)]
	ColorCorrection = { Enabled = true, Saturation = -0.1, Contrast = 0.05, Brightness = 0, TintColor = Color3.new(1, 1, 1) }, -- new
}
local BEFORE = {
	ClockTime = 14.5, Brightness = 1.8, OutdoorAmbient = Color3.fromRGB(150, 151, 153), EnvironmentDiffuseScale = 0.3,
	EnvironmentSpecularScale = 1, ExposureCompensation = 0,
	Atmosphere = { Color = Color3.fromRGB(230, 200, 166), Decay = Color3.fromRGB(106, 112, 125), Haze = 10, Density = 0.3 },
	ColorCorrection = { Enabled = false },
}

local L = game:GetService("Lighting")
local v = (MODE == "apply") and A3 or BEFORE
for k, x in v do
	if typeof(x) ~= "table" then L[k] = x end
end
local atm = L:FindFirstChildOfClass("Atmosphere")
if atm then
	for k, x in v.Atmosphere do atm[k] = x end
end
local cc = L:FindFirstChild("ColorCorrection")
if not cc and MODE == "apply" then
	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "ColorCorrection"
	cc.Parent = L
end
if cc then
	for k, x in v.ColorCorrection do cc[k] = x end
end
L:SetAttribute("A3Lighting", (MODE == "apply") and "A3 2026-11-10 (YouTube cM2D-CniPXI reference); revert: Roblox/Environment/LightingA3/apply_lighting.luau MODE=revert" or nil)
return MODE .. " done; sun " .. tostring(L:GetSunDirection())
