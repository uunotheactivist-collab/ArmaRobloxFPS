--!strict
-- Presentation of the aim input's state for one weapon: viewmodel pose (Weapon + LeftArm, relative to the hip rest
-- pose) and the camera zoom factor. Each weapon's state is what its footage shows for the aim input:
--   M4 = ADS (Config.Weapons.M4.ADS, data ADSIn / Poses.ADS; ReferenceAnalysis/M4):
--     in : weapon follows the measured path (reference frames 161-171: de-cant + drop, then rise to the eye),
--          0.33 s; zoom 1.00 -> 1.16 eased over 0.27 s, starting one frame after the weapon.
--     out: weapon straight back to the hip in 0.12 s; zoom back over 0.27 s, trailing the weapon.
--   AK = Raised (Config.Weapons.AK.Raised, data RaisedIn / Poses.Raised; ReferenceAnalysis/AK): rifle upright in
--     0.13 s, back in 0.30 s, NO zoom (the config has no zoom fields, so the camera keeps the hip FOV) and no sight.
-- Interrupting either direction starts from the current pose (no pops).
-- Optional (M4 model-fidelity correction pass): when the ADS-in keys also carry LeftArm, the arm follows that keyed
-- path (same sampling as the weapon) instead of the plain blend to Poses.ADS.LeftArm - the M4's keys keep the hand on
-- the handguard. Data without arm keys (every other weapon) behaves exactly as before.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Easing = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Easing"))

local IDENTITY = CFrame.identity
local CROSSFADE = 0.08 -- s, only used when aiming again mid-exit

local AimController = {}
AimController.__index = AimController

type Key = { T: number, CF: CFrame, Arm: CFrame? }
export type Pose = { Weapon: CFrame, LeftArm: CFrame }
export type AimController = typeof(setmetatable(
	{} :: {
		Config: any,
		Keys: { Key },
		ArmKeys: { Key }?,
		ADSArm: CFrame,
		ADSZoom: number,
		Aiming: boolean,
		T: number,
		From: Pose,
		ZoomFrom: number,
		Current: Pose,
		Zoom: number,
	},
	AimController
))

local function cf(t: { number }): CFrame
	return CFrame.new(table.unpack(t))
end

-- Weapon pose along the measured ADS-in path at time t: Hermite (finite-difference tangents) on position,
-- slerp on rotation between keys.
local function samplePath(keys: { Key }, t: number): CFrame
	local n = #keys
	if t <= keys[1].T then
		return keys[1].CF
	elseif t >= keys[n].T then
		return keys[n].CF
	end
	local i = 1
	while keys[i + 1].T < t do
		i += 1
	end
	local k0, k1 = keys[i], keys[i + 1]
	local h = k1.T - k0.T
	local s = (t - k0.T) / h
	local function tangent(j: number): Vector3
		local a, b = keys[math.max(j - 1, 1)], keys[math.min(j + 1, n)]
		return (b.CF.Position - a.CF.Position) / (b.T - a.T)
	end
	local m0, m1 = tangent(i) * h, tangent(i + 1) * h
	local s2, s3 = s * s, s * s * s
	local p = (2 * s3 - 3 * s2 + 1) * k0.CF.Position + (s3 - 2 * s2 + s) * m0 + (-2 * s3 + 3 * s2) * k1.CF.Position
		+ (s3 - s2) * m1
	local rot = k0.CF.Rotation:Lerp(k1.CF.Rotation, s)
	return CFrame.new(p) * rot
end

function AimController.new(config: any, data: any): AimController
	local keys = {}
	local armKeys: { Key }? = {}
	for _, k in (data.ADSIn or data.RaisedIn) do
		table.insert(keys, { T = k.T, CF = cf(k.Weapon) })
		if armKeys and k.LeftArm then
			table.insert(armKeys, { T = k.T, CF = cf(k.LeftArm) })
		else
			armKeys = nil -- every key must carry the arm, or the accepted blend is used
		end
	end
	return setmetatable({
		-- Zoom timing defaults only matter when a weapon zooms; with no ZoomMagnification the zoom stays 1.
		Config = {
			InTime = config.InTime,
			OutTime = config.OutTime,
			ZoomDelay = config.ZoomDelay or 0,
			ZoomInTime = config.ZoomInTime or config.InTime,
			ZoomOutTime = config.ZoomOutTime or config.OutTime,
		},
		Keys = keys,
		ArmKeys = armKeys,
		ADSArm = cf((data.Poses.ADS or data.Poses.Raised).LeftArm),
		ADSZoom = config.ZoomMagnification or 1,
		Aiming = false,
		T = math.huge,
		From = { Weapon = IDENTITY, LeftArm = IDENTITY },
		ZoomFrom = 1,
		Current = { Weapon = IDENTITY, LeftArm = IDENTITY },
		Zoom = 1,
	}, AimController)
end

function AimController.SetAiming(self: AimController, aiming: boolean)
	if aiming == self.Aiming then
		return
	end
	self.Aiming = aiming
	self.T = 0
	self.From = { Weapon = self.Current.Weapon, LeftArm = self.Current.LeftArm }
	self.ZoomFrom = self.Zoom
end

-- Snap back to the hip immediately (unequip, death).
function AimController.Reset(self: AimController)
	self.Aiming = false
	self.T = math.huge
	self.From = { Weapon = IDENTITY, LeftArm = IDENTITY }
	self.Current = { Weapon = IDENTITY, LeftArm = IDENTITY }
	self.ZoomFrom, self.Zoom = 1, 1
end

-- Returns the pose, the zoom factor and how far into ADS the weapon is (0 hip .. 1 aimed).
function AimController.Step(self: AimController, dt: number): (Pose, number, number)
	local cfgADS = self.Config
	self.T += dt
	local t = self.T
	local weapon: CFrame, arm: CFrame, alpha: number
	if self.Aiming then
		local pathT = math.min(t, cfgADS.InTime) * (self.Keys[#self.Keys].T / cfgADS.InTime)
		local w = Easing.smoothstep(t / CROSSFADE)
		weapon = IDENTITY:Lerp(self.From.Weapon, 1 - w) * samplePath(self.Keys, pathT)
		local armKeys = self.ArmKeys
		if armKeys then
			arm = IDENTITY:Lerp(self.From.LeftArm, 1 - w) * samplePath(armKeys, pathT)
		else
			local armA = Easing.smoothstep(t / cfgADS.InTime)
			arm = IDENTITY:Lerp(self.From.LeftArm, 1 - w) * IDENTITY:Lerp(self.ADSArm, armA)
		end
		alpha = math.clamp(t / cfgADS.InTime, 0, 1)
		local z = Easing.smoothstep((t - cfgADS.ZoomDelay) / cfgADS.ZoomInTime)
		self.Zoom = self.ZoomFrom + (self.ADSZoom - self.ZoomFrom) * z
	else
		local w = Easing.inOutSine(t / cfgADS.OutTime)
		weapon = self.From.Weapon:Lerp(IDENTITY, w)
		arm = self.From.LeftArm:Lerp(IDENTITY, w)
		alpha = 1 - w
		local z = Easing.smoothstep((t - cfgADS.ZoomDelay) / cfgADS.ZoomOutTime)
		self.Zoom = self.ZoomFrom + (1 - self.ZoomFrom) * z
	end
	self.Current = { Weapon = weapon, LeftArm = arm }
	return self.Current, self.Zoom, alpha
end

return AimController
