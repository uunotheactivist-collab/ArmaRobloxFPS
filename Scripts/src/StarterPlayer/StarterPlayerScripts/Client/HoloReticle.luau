--!strict
-- Holographic-sight reticle. In the reference the red dot does not ride with the sight window when the rifle
-- kicks: it stays where the barrel points (it is projected at infinity). So each frame the dot is placed where
-- the line from the eye along the sight axis crosses the glass, and hidden when that point is outside the window
-- (e.g. at the hip). At rest in ADS this is exactly the screen centre.

local STUD = 0.28
local HALF_W, HALF_H = 0.0125 / STUD, 0.0095 / STUD -- window 0.026 x 0.020 m, minus the dot radius

local HoloReticle = {}

-- rig: ViewmodelRig after Update; part: the reticle part; glass: SightGlass point (weapon bone space, studs).
-- window (optional, Glock slice): { HalfW, HalfH } in metres for a weapon whose sight window differs from the M4's.
-- pitch (optional, Glock reticle alignment F-G10): degrees about the weapon's own X axis (negative = lower) between the
-- bore and the dot's line, for a sight whose dot is not zeroed on the bore. nil (the M4) = the bore axis exactly.
function HoloReticle.Update(rig: any, part: BasePart, glass: Vector3, eye: Vector3, window: { number }?, pitch: number?)
	local weapon: CFrame = rig.World.Weapon
	local axis = if pitch then (weapon * CFrame.Angles(math.rad(pitch), 0, 0)).LookVector else weapon.LookVector
	local centre = weapon * glass
	local p = eye + axis * (centre - eye):Dot(axis)
	local local_ = weapon:PointToObjectSpace(p) - glass
	local hw = if window then window[1] / STUD else HALF_W
	local hh = if window then window[2] / STUD else HALF_H
	if math.abs(local_.X) <= hw and math.abs(local_.Y) <= hh then
		part.CFrame = weapon.Rotation + p
		part.Transparency = 0
	else
		part.Transparency = 1
	end
end

return HoloReticle
