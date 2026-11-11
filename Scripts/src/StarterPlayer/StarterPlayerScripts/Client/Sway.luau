--!strict
-- Idle sway layers (Config.Weapons.<Id>.Sway). Reference: Regular idle is still; Stressed sways irregularly
-- (camera pitch and roll, no clean rhythm) and the viewmodel drifts 5-9 % of the screen width.
-- Smooth value noise (math.noise) gives the irregular motion; the Stressed weight eases in/out.
-- Returns a camera offset (applied to the view, removed again before the camera scripts run next frame) and
-- a viewmodel offset (applied to the rig root). Viewmodel drift is reduced while aiming.

local Sway = {}
Sway.__index = Sway

export type Sway = typeof(setmetatable({} :: { Config: any, T: number, Weight: number }, Sway))

function Sway.new(config: any): Sway
	return setmetatable({ Config = config, T = 0, Weight = 0 }, Sway)
end

local function noise(t: number, freq: number, seed: number): number
	return math.clamp(math.noise(t * freq, seed, 0.37) * 2, -1, 1)
end

function Sway.Step(self: Sway, dt: number, stressed: boolean, aimAlpha: number): (CFrame, CFrame)
	local s = self.Config.Stressed
	self.T += dt
	local target = if stressed then 1 else 0
	self.Weight += (target - self.Weight) * (1 - math.exp(-dt / s.BlendTime))
	local w = self.Weight
	if w < 1e-4 then
		return CFrame.identity, CFrame.identity
	end
	local t = self.T
	local pitch = math.rad(s.CameraPitchDeg) * (0.6 * noise(t, s.FastHz, 1.3) + 0.4 * noise(t, s.SlowHz, 7.1))
	local roll = math.rad(s.CameraRollDeg) * noise(t, s.RollHz, 3.7)
	local yaw = math.rad(s.CameraYawDeg) * noise(t, s.FastHz * 0.8, 5.9)
	local camera = CFrame.Angles(pitch * w, yaw * w, roll * w)

	local vw = w * (1 - s.AimReduction * aimAlpha)
	local wy = math.rad(s.WeaponYawDeg) * noise(t, s.WeaponHz, 9.2)
	local wp = math.rad(s.WeaponPitchDeg) * noise(t, s.WeaponHz * 0.85, 11.5)
	local wr = math.rad(s.WeaponRollDeg) * noise(t, s.WeaponHz * 0.7, 13.3)
	local shift = Vector3.new(noise(t, s.WeaponHz * 0.9, 15.1), noise(t, s.WeaponHz * 0.75, 17.9), 0) * s.WeaponShiftStuds
	local weapon = CFrame.new(shift * vw) * CFrame.Angles(wp * vw, wy * vw, wr * vw)
	return camera, weapon
end

return Sway
