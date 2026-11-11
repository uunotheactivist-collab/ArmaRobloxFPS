--!strict
-- Movement presentation layers (client, shared state). Values: Shared.Config.Movement (ReferenceAnalysis/Movement).
--   Look lag: the viewmodel trails camera turns (yaw and pitch) like a first-order lag: steady offset = turn rate x Tau,
--     clamped. Scripted camera jumps (cuts) are not turns.
--   Walk bob: the viewmodel pitches once per step and yaws once per two steps, weighted by ground speed.
--   Camera roll: the view rolls with the turn rate (turning right dips the horizon to the right), smoothed, clamped.
-- MovementController steps it once per frame (before the weapon controller); WeaponController multiplies
-- viewmodelOffset(aimAlpha) in front of its own sway / recoil / reload poses. With no movement and no turning every
-- value decays to exactly zero and both offsets are the identity: the accepted stationary presentation is untouched.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Movement"))

local MovementPresentation = {
	LagYaw = 0, -- deg, + = viewmodel turned left of the view (it trails a right turn)
	LagPitch = 0, -- deg, + = viewmodel pitched up (it trails the view pitching down)
	BobYaw = 0,
	BobPitch = 0,
	Weight = 0, -- walk bob weight 0..1
	Phase = 0, -- steps walked
	Roll = 0, -- deg, + = horizon dips to the right
}

local EPS = 1e-4

local function clamp(v: number, m: number): number
	return math.clamp(v, -m, m)
end

function MovementPresentation.reset()
	local P = MovementPresentation
	P.LagYaw, P.LagPitch, P.BobYaw, P.BobPitch, P.Weight, P.Phase, P.Roll = 0, 0, 0, 0, 0, 0, 0
end

-- turnRight / turnDown in deg/s (the camera's own rotation, no presentation offsets); flatSpeed studs/s.
function MovementPresentation.step(dt: number, turnRight: number, turnDown: number, flatSpeed: number, grounded: boolean)
	local P = MovementPresentation
	if dt <= 0 then
		return
	end
	local L = Config.Viewmodel.LookLag
	local k = math.exp(-dt / L.Tau)
	P.LagYaw = clamp(P.LagYaw * k + turnRight * L.Tau * (1 - k), L.MaxDeg)
	P.LagPitch = clamp(P.LagPitch * k + turnDown * L.Tau * (1 - k), L.MaxDeg)
	if math.abs(P.LagYaw) < EPS then
		P.LagYaw = 0
	end
	if math.abs(P.LagPitch) < EPS then
		P.LagPitch = 0
	end

	local W = Config.Viewmodel.Walk
	local target = if grounded then math.clamp(flatSpeed / Config.Walk.Speed, 0, 1) else 0
	P.Weight += (target - P.Weight) * (1 - math.exp(-dt / W.BlendTau))
	if P.Weight < EPS and target == 0 then
		P.Weight = 0
	end
	if grounded then
		P.Phase = (P.Phase + flatSpeed * dt / (Config.Walk.Speed * Config.Walk.StepSeconds)) % 2
	end
	P.BobPitch = W.PitchDeg * P.Weight * math.sin(2 * math.pi * P.Phase) -- once per step
	P.BobYaw = W.YawDeg * P.Weight * math.sin(math.pi * P.Phase) -- once per two steps

	local R = Config.Camera.Roll
	local rollTarget = clamp(R.GainDegPerDegPerSec * turnRight, R.MaxDeg)
	P.Roll += (rollTarget - P.Roll) * (1 - math.exp(-dt / R.Tau))
	if math.abs(P.Roll) < EPS and rollTarget == 0 then
		P.Roll = 0
	end
end

-- The whole viewmodel's rotation about the camera (in front of the weapon's own layers). Identity when still.
function MovementPresentation.viewmodelOffset(aimAlpha: number): CFrame
	local P = MovementPresentation
	local kl = 1 - Config.Viewmodel.LookLag.AimReduction * aimAlpha
	local kb = 1 - Config.Viewmodel.Walk.AimReduction * aimAlpha
	local pitch = P.LagPitch * kl + P.BobPitch * kb
	local yaw = P.LagYaw * kl + P.BobYaw * kb
	if math.abs(pitch) < EPS and math.abs(yaw) < EPS then
		return CFrame.identity
	end
	return CFrame.Angles(math.rad(pitch), math.rad(yaw), 0)
end

function MovementPresentation.cameraRoll(): CFrame
	local r = MovementPresentation.Roll
	if math.abs(r) < EPS then
		return CFrame.identity
	end
	return CFrame.Angles(0, 0, math.rad(r))
end

return MovementPresentation
