--!strict
-- Aim-hold drift (Glock, 2026-11-10; ReferenceAnalysis/Weapons/Glock/AimDrift). Presentation only: an offset of the
-- whole viewmodel (weapon and arms) relative to the camera while a weapon is held aimed. The camera, the shot direction
-- and the accepted aim pose are not touched. Built only for a weapon whose config has ADS.HoldDrift (the Glock); every
-- other weapon has no AimHold and its viewmodel root is computed exactly as before.
--
-- Footage (glock animation.mp4, Regular aim 147-178): from 0.200 s after the aim input the sight pitches down about the
-- eye (red dot and rear dots move together) linearly for 0.300 s, while it drops (rear dots only) on a quadratic ease-in
-- over 0.533 s; then it holds. Time-based only: the one aimed shot (163) needs no rule of its own.
--   pitch(t) = PitchDeg * clamp((t - Onset) / PitchTime, 0, 1)
--   drop(t)  = DropStuds * clamp((t - Onset) / DropTime, 0, 1) ^ 2
-- Offset = CFrame.Angles(-pitch, 0, 0) * CFrame.new(0, -drop, 0), applied last on the viewmodel root (camera space).
-- Aim out: the drift shown at the release is scaled by the aim blend (gone at the hip). Aim in again mid-exit: what was
-- still shown fades out over the raise, then the drift restarts from zero.

local AimHold = {}
AimHold.__index = AimHold

export type AimHold = typeof(setmetatable(
	{} :: {
		Def: any,
		WasAiming: boolean,
		Pitch: number, -- degrees, shown this frame
		Drop: number, -- studs, shown this frame
		FromPitch: number, -- carried in from a release (aim in again mid-exit) or held at a release
		FromDrop: number,
		DebugT: number?, -- Studio tests: hold time (s since the aim input) to show instead of the real one
	},
	AimHold
))

function AimHold.new(def: any): AimHold
	return setmetatable({
		Def = def,
		WasAiming = false,
		Pitch = 0,
		Drop = 0,
		FromPitch = 0,
		FromDrop = 0,
		DebugT = nil,
	}, AimHold)
end

-- aiming: the aim input as the AimController has it; t: seconds since that input changed (AimController.T);
-- alpha: the aim blend (0 hip .. 1 aimed). Returns the root offset, or nil when there is none to apply.
function AimHold.Step(self: AimHold, aiming: boolean, t: number, alpha: number): CFrame?
	local def = self.Def
	if aiming then
		if not self.WasAiming then
			self.WasAiming = true
			self.FromPitch, self.FromDrop = self.Pitch, self.Drop -- still on screen from a release
		end
		local h = (self.DebugT or t) - def.Onset
		local u = math.clamp(h / def.PitchTime, 0, 1)
		local v = math.clamp(h / def.DropTime, 0, 1)
		local k = 1 - alpha
		self.Pitch = def.PitchDeg * u + self.FromPitch * k
		self.Drop = def.DropStuds * v * v + self.FromDrop * k
	else
		if self.WasAiming then
			self.WasAiming = false
			self.FromPitch, self.FromDrop = self.Pitch, self.Drop -- shown at the release
		end
		self.Pitch = self.FromPitch * alpha
		self.Drop = self.FromDrop * alpha
	end
	if self.Pitch == 0 and self.Drop == 0 then
		return nil
	end
	return CFrame.Angles(math.rad(-self.Pitch), 0, 0) * CFrame.new(0, -self.Drop, 0)
end

-- Unequip / death: nothing carried over.
function AimHold.Reset(self: AimHold)
	self.WasAiming = false
	self.Pitch, self.Drop, self.FromPitch, self.FromDrop = 0, 0, 0, 0
end

return AimHold
