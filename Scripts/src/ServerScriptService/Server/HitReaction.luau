--!strict
-- Standing hit reactions (server only): flinch, weakened / broken pose, stumble. They are offsets on the rest C0s of
-- the rig's Motor6Ds (and the anchored root) while the body still stands. Server-side C0 changes replicate.
-- Data: Shared.Config.BodyPresentation. Basis: ReferenceAnalysis/HitReactions/HitReactions_Analysis.md §1.
-- Inputs come only from the accepted BodyState: strength, legs, the Reacting window, Unstable.
--   flinch: waist back + twist, arms swing out; peaks within 2 frames, gone after the Reacting window
--           (timing measured; amplitude placeholder; direction UNKNOWN → the same for every hit)
--   weak:   slump scaled by (100 − strength), knee bend scaled by (100 − legs) (placeholder scales); the pelvis drops
--           by what the bent legs lose in height and the ankles keep the feet flat, so the feet stay on the ground
--   unstable (legs 0): one recovery step + sway until BodyState's fall begins (placeholder values in measured ranges),
--           and the legs sag over BodyState's legs-gone delay, so the body has started to descend when the fall begins

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("BodyPresentation"))
local BodyConfig = require(Shared.Config:WaitForChild("BodyState"))

local HitReaction = {}

export type Rig = {
	Model: Model,
	Root: BasePart,
	RootRest: CFrame,
	Motors: { [string]: Motor6D },
	RestC0: { [string]: CFrame },
	Key: string,
}

function HitReaction.rig(model: Model): Rig?
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local motors, rest = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
			rest[d.Name] = d.C0
		end
	end
	return { Model = model, Root = root, RootRest = root.CFrame, Motors = motors, RestC0 = rest, Key = "" }
end

-- 0 → 1 at the peak, back to 0 at `duration`
function HitReaction.flinchAmount(t: number, duration: number): number
	if t < 0 or t >= duration then
		return 0
	end
	local p = Config.Flinch.PeakSeconds
	if t < p then
		return t / p
	end
	local u = (t - p) / math.max(duration - p, 1e-3)
	return (1 - u) * (1 - u)
end

-- s = { strength, legs, flinch (0–1), unstableT (s since unstable, or nil) }. Returns the pose numbers it applied.
function HitReaction.apply(r: Rig, s: any): any
	local P, F, S = Config.Posture, Config.Flinch, Config.Stumble
	local f = s.flinch or 0
	local weak = 1 - math.clamp(s.strength / 100, 0, 1)
	local legsWeak = 1 - math.clamp(s.legs / 100, 0, 1)
	local sway, step, sag = 0, 0, 0
	if s.unstableT then
		sway = math.sin(s.unstableT / S.SwayPeriod * 2 * math.pi) * S.SwayDeg
		step = math.clamp(s.unstableT / S.StepSeconds, 0, 1) * S.StepStuds
		sag = math.clamp(s.unstableT / BodyConfig.LegsGoneFallAfter, 0, 1)
	end
	local waistPitch = -P.SlumpDegAtZeroStrength * weak + F.WaistBackDeg * f -- + = back
	local knee = P.KneeDegAtZeroLegs * legsWeak + S.SagKneeDeg * sag
	local pose = {
		WaistPitch = waistPitch,
		WaistTwist = F.WaistTwistDeg * f,
		Sway = sway,
		ArmSwing = F.ArmSwingDeg * f,
		Knee = knee,
		Drop = P.LegLengthStuds * (1 - math.cos(math.rad(knee / 2))),
		Step = step,
	}
	local key = string.format("%.2f %.2f %.2f %.2f %.2f %.3f %.3f", pose.WaistPitch, pose.WaistTwist, pose.Sway, pose.ArmSwing, pose.Knee, pose.Drop, pose.Step)
	-- AI combat slice (additive): a body whose model has the server attribute BodyFacingYaw (radians, world yaw; set
	-- only by Server.AI for a bot turning to its target) stands turned to that yaw about its rest position. Without the
	-- attribute nothing here changes. This stays the only code that moves a standing body's root.
	local yaw = r.Model:GetAttribute("BodyFacingYaw")
	local rest = r.RootRest
	if type(yaw) == "number" and yaw == yaw and math.abs(yaw) < 1e4 then
		rest = CFrame.new(r.RootRest.Position) * CFrame.Angles(0, yaw, 0)
		key ..= string.format(" %.4f", yaw)
	end
	if key == r.Key then
		return pose
	end
	r.Key = key
	local function set(name: string, offset: CFrame)
		local m = r.Motors[name]
		if m then
			m.C0 = r.RestC0[name] * offset
		end
	end
	set("Waist", CFrame.Angles(math.rad(waistPitch), math.rad(pose.WaistTwist), math.rad(sway)))
	set("Neck", CFrame.Angles(math.rad(-P.NeckDegAtZeroStrength * weak), 0, 0))
	set("RightShoulder", CFrame.Angles(0, 0, math.rad(pose.ArmSwing)))
	set("LeftShoulder", CFrame.Angles(0, 0, math.rad(-pose.ArmSwing)))
	local kneeRad = math.rad(pose.Knee)
	set("RightHip", CFrame.Angles(kneeRad * 0.5, 0, 0))
	set("LeftHip", CFrame.Angles(kneeRad * 0.5, 0, 0))
	set("RightKnee", CFrame.Angles(-kneeRad, 0, 0))
	set("LeftKnee", CFrame.Angles(-kneeRad, 0, 0))
	set("RightAnkle", CFrame.Angles(kneeRad * 0.5, 0, 0))
	set("LeftAnkle", CFrame.Angles(kneeRad * 0.5, 0, 0))
	r.Root.CFrame = rest * CFrame.new(step, -pose.Drop, 0)
	return pose
end

return HitReaction
