--!strict
-- Viewmodel fill v2 (2026-11-10; Config.ViewmodelFill). Presentation only, client only, nothing sent to the server.
-- DARK-FINISH SHADE LIFT driven by the weapon's own light (not the eye). Every frame the active "...Viewmodel" model
-- under the camera is tested against the sun at Config.SunSamples points on its bounding box; the shaded share ^
-- PartialExponent is the shade level s (eased: FadeInTau into shade, FadeOutTau into sun). Dark parts (original Color
-- luma < DarkLumaMax; Neon / Glass / ForceField / partly transparent excluded) get their Color raised in linear light by
-- 1 + s * (gain[c] - 1) per channel, gain[c] = max(1, ShadeAlbedo / (the part's linear luminance) * ShadeTint[c]).
-- While a first-person muzzle-flash light is on (MuzzleEffects: "ProductionWeaponEffects" folder under the camera,
-- part "FlashLight", PointLight Enabled) the level drops to 0 at once and is held for FireHold after the last flash, so
-- the flash lights the weapon exactly as in the accepted look (a lifted albedo would multiply the flash light too).
-- Original colours are kept per part and restored exactly at s = 0, when the
-- model leaves the camera (rigs are cached while holstered) and when disabled; a colour written by another script is
-- adopted as the new original. Runs after the viewmodel is posed (render step Camera + 3; "ProductionViewmodel" is
-- Camera + 2). Studio tuning: attribute Enabled = false on this script disables it (restores colours); attribute Level
-- reports the current level (rounded to 0.01).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("ViewmodelFill")) :: any
if not Config.Enabled then
	return
end

local player = Players.LocalPlayer
local TINT = Config.ShadeTint

local function toLinear(c: number): number
	return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
end
local function toSrgb(l: number): number
	l = math.clamp(l, 0, 1)
	return if l <= 0.0031308 then 12.92 * l else 1.055 * l ^ (1 / 2.4) - 0.055
end

type Entry = { base: Color3, lr: number, lg: number, lb: number, gr: number, gg: number, gb: number, written: Color3? }
local entries: { [BasePart]: Entry } = setmetatable({}, { __mode = "k" }) :: any
local tracked: { BasePart } = {}
local model: Model? = nil
local conns: { RBXScriptConnection } = {}
local level = 0
local applied = -1

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local SKIP = { [Enum.Material.Neon] = true, [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true }

local function entryFor(p: BasePart): Entry
	local e = entries[p]
	if e == nil or p.Color ~= (e.written or e.base) then
		local c = p.Color -- first sight, or another script changed the colour: adopt it as the original
		local lr, lg, lb = toLinear(c.R), toLinear(c.G), toLinear(c.B)
		local k = Config.ShadeAlbedo / math.max(0.2126 * lr + 0.7152 * lg + 0.0722 * lb, 1e-4)
		e = {
			base = c,
			lr = lr,
			lg = lg,
			lb = lb,
			gr = math.max(1, k * TINT[1]),
			gg = math.max(1, k * TINT[2]),
			gb = math.max(1, k * TINT[3]),
			written = nil,
		}
		entries[p] = e
	end
	return e :: Entry
end

local function paint(p: BasePart, t: number)
	local e = entryFor(p)
	if t <= 0 then
		if e.written ~= nil then
			p.Color = e.base
			e.written = nil
		end
		return
	end
	p.Color = Color3.new(
		toSrgb(e.lr * (1 + (e.gr - 1) * t)),
		toSrgb(e.lg * (1 + (e.gg - 1) * t)),
		toSrgb(e.lb * (1 + (e.gb - 1) * t))
	)
	e.written = p.Color
end

local function detach()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	for _, p in tracked do
		paint(p, 0)
	end
	table.clear(tracked)
	model = nil
	applied = -1
end

local function rescan()
	for _, p in tracked do
		paint(p, 0)
	end
	table.clear(tracked)
	local m = model
	if not m then
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			-- classify on the ORIGINAL colour; see-through parts (glass, partly transparent) and emitters are never touched
			local b = entryFor(d).base
			local seeThrough = d.Transparency > 0.05 and d.Transparency < 0.95
			if not SKIP[d.Material] and not seeThrough and (0.2126 * b.R + 0.7152 * b.G + 0.0722 * b.B) * 255 < Config.DarkLumaMax then
				table.insert(tracked, d)
			end
		end
	end
	applied = -1
end

local function attach(m: Model)
	detach()
	model = m
	rescan()
	table.insert(conns, m.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			task.defer(rescan)
		end
	end))
	table.insert(conns, m.DescendantRemoving:Connect(function(d)
		if d:IsA("BasePart") then
			paint(d, 0)
			task.defer(rescan)
		end
	end))
end

-- false if the ray reaches the sky (steps through parts that cast no shadow: invisible / non-shadow geometry)
local function blocked(origin: Vector3, dir: Vector3): boolean
	for _ = 1, 4 do
		local hit = workspace:Raycast(origin, dir, params)
		if not hit then
			return false
		end
		local inst = hit.Instance
		if inst:IsA("BasePart") and (inst.Transparency > 0.9 or not inst.CastShadow) then
			origin = hit.Position + dir.Unit * 0.05
		else
			return true
		end
	end
	return true
end

-- share of sample points on the viewmodel that are out of direct sun (0 = fully sunlit, 1 = fully shaded)
local function shadeShare(m: Model): number
	local sun = Lighting:GetSunDirection()
	if sun.Y <= 0 then
		return 1
	end
	local cf, size = m:GetBoundingBox()
	local axis = cf.RightVector
	local ext = size.X
	if size.Y > ext then
		axis, ext = cf.UpVector, size.Y
	end
	if size.Z > ext then
		axis, ext = cf.LookVector, size.Z
	end
	local n = math.max(1, Config.SunSamples)
	local shaded = 0
	for i = 1, n do
		local f = if n == 1 then 0 else (i - 1) / (n - 1) * 0.7 - 0.35 -- -0.35 .. +0.35 of the long axis
		if blocked(cf.Position + axis * (ext * f), sun * Config.SunRayLength) then
			shaded += 1
		end
	end
	return shaded / n
end

-- first-person muzzle-flash lights (MuzzleEffects); cached per camera, refreshed when camera children change
local flashLights: { PointLight } = {}
local flashCamera: Camera? = nil
local flashConns: { RBXScriptConnection } = {}
local lastFlash = -math.huge

local function refreshFlashLights()
	table.clear(flashLights)
	local camera = flashCamera
	if not camera then
		return
	end
	for _, f in camera:GetChildren() do
		if f.Name == "ProductionWeaponEffects" then
			local part = f:FindFirstChild("FlashLight")
			local light = part and part:FindFirstChildOfClass("PointLight")
			if light then
				table.insert(flashLights, light)
			end
		end
	end
end

local function watchCamera(camera: Camera)
	if flashCamera == camera then
		return
	end
	for _, c in flashConns do
		c:Disconnect()
	end
	table.clear(flashConns)
	flashCamera = camera
	table.insert(flashConns, camera.ChildAdded:Connect(function()
		task.defer(refreshFlashLights)
	end))
	table.insert(flashConns, camera.ChildRemoved:Connect(function()
		task.defer(refreshFlashLights)
	end))
	refreshFlashLights()
end

local function flashing(): boolean
	for _, light in flashLights do
		if light.Enabled and light.Brightness > 0 and light.Parent ~= nil then
			return true
		end
	end
	return false
end

RunService:BindToRenderStep("ViewmodelFill", Enum.RenderPriority.Camera.Value + 3, function(dt: number)
	local camera = workspace.CurrentCamera
	local current: Model? = nil
	if camera then
		for _, c in camera:GetChildren() do
			if c:IsA("Model") and string.sub(c.Name, -9) == "Viewmodel" then
				current = c
				break
			end
		end
	end
	if script:GetAttribute("Enabled") == false then
		current = nil
	end
	if current ~= model then
		if current then
			attach(current)
		else
			detach()
		end
	end
	local m = model
	if not m or not camera then
		return -- keep the level across a weapon switch (the next model is painted at once); it re-converges next frame
	end
	params.FilterDescendantsInstances = { player.Character :: any, camera }
	watchCamera(camera)
	local now = os.clock()
	if flashing() then
		lastFlash = now
		level = 0 -- at once: the flash itself covers the change
	end
	local goal = if now - lastFlash < Config.FireHold then 0 else shadeShare(m) ^ Config.PartialExponent
	level += (goal - level) * math.min(1, dt / (if goal > level then Config.FadeInTau else Config.FadeOutTau))
	if level < 0.002 then
		level = 0
	end
	if math.abs(level - applied) >= Config.MinStep or (level == 0 and applied ~= 0) then
		for _, p in tracked do
			paint(p, level)
		end
		applied = level
		script:SetAttribute("Level", math.round(level * 100) / 100)
	end
end)
