--!strict
-- Body presentation (server): visible hit reactions, falling, dying and active ragdoll for bodies whose model has
-- BodyPresentation = "ActiveRagdoll" (the R15 test bots REACT1–6 for now).
-- It CONSUMES the accepted BodyState: it only reads the attributes Server.BodyState publishes on the server (BodyPhase,
-- BodyStance, BodyWound, BodyBehaviour, BodyStrength, BodyLegs, BodyLife, BodyHits, BodyUnstable) and never changes a
-- body's state. BodyState.applyHit stays the only entry for hits and state. Clients can't reach any of this: they
-- only see the replicated, server-owned result.
--   standing (ALIVE / INJURED): Server.HitReaction (flinch on each new hit, weakened pose, stumble when unstable)
--   FALLING / DOWN / DEAD:      Server.ActiveRagdoll (physics body, muscles from the behaviour's measured profile
--                               faded with life, crawl). The body stays in the world.
-- Basis: ReferenceAnalysis/HitReactions/HitReactions_Analysis.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("BodyPresentation"))
local BodyConfig = require(Shared.Config:WaitForChild("BodyState"))
local HitReaction = require(script.Parent:WaitForChild("HitReaction"))
local ActiveRagdoll = require(script.Parent:WaitForChild("ActiveRagdoll"))

type Bound = {
	Model: Model,
	Rig: HitReaction.Rig,
	Ragdoll: ActiveRagdoll.State?,
	RagdollAt: number?,
	Hits: number,
	FlinchAt: number?,
	UnstableAt: number?,
	Pose: any,
	Samples: { any }?,
	SampleUntil: number,
	LastSample: number,
}
local bound: { [Model]: Bound } = {}

local function bind(m: Instance)
	if not m:IsA("Model") or bound[m :: Model] or m:GetAttribute(Config.Attribute) ~= Config.Mode then
		return
	end
	local model = m :: Model
	local rig = HitReaction.rig(model)
	if not rig then
		return
	end
	bound[model] = {
		Model = model,
		Rig = rig,
		Ragdoll = nil,
		RagdollAt = nil,
		Hits = model:GetAttribute("BodyHits") or 0,
		FlinchAt = nil,
		UnstableAt = nil,
		Pose = nil,
		Samples = nil,
		SampleUntil = 0,
		LastSample = 0,
	}
end

workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(bind, d)
	end
end)
for _, d in workspace:GetDescendants() do
	bind(d)
end

-- The behaviour to present: BodyState's own once set; before that (falling) the accepted DownBehaviour of the wound.
local function behaviourOf(m: Model): string
	local b = m:GetAttribute("BodyBehaviour")
	if type(b) == "string" then
		return b
	end
	local w = m:GetAttribute("BodyWound")
	return BodyConfig.DownBehaviour[if type(w) == "string" then w else "Limb"] or "SHOCK"
end

-- Studio-only sampler helpers (used only while a test is watching a body).
local SEG_PARTS = { "Head", "UpperTorso", "LowerTorso", "RightUpperArm", "RightLowerArm", "LeftUpperArm", "LeftLowerArm",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" }
local function lowestY(p: BasePart): number
	local cf, s = p.CFrame, p.Size
	return cf.Position.Y - (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z) / 2
end
local function angleDeg(a: Vector3, c: Vector3): number
	return math.deg(math.acos(math.clamp(a:Dot(c), -1, 1)))
end
local function pairAngle(m: Model, a: string, c: string): number?
	local pa, pc = m:FindFirstChild(a) :: BasePart?, m:FindFirstChild(c) :: BasePart?
	return if pa and pc then angleDeg(pa.CFrame.UpVector, pc.CFrame.UpVector) else nil
end

local function sample(b: Bound, t: number)
	if not b.Samples or t > b.SampleUntil or t - b.LastSample < 1 / Config.DebugSampleHz then
		return
	end
	b.LastSample = t
	local m = b.Model
	local upper = m:FindFirstChild("UpperTorso") :: BasePart?
	local head = m:FindFirstChild("Head") :: BasePart?
	local lower = m:FindFirstChild("LowerTorso") :: BasePart?
	local kSum, kN = 0, 0
	if b.Ragdoll then
		for _, k in b.Ragdoll.K do
			kSum += k
			kN += 1
		end
	end
	-- side view (the body's own forward / up plane) and posture numbers
	local origin, fwd = b.Rig.RootRest.Position, b.Rig.RootRest.LookVector
	local segs, lowest, kneeY, maxSpeed = {}, math.huge, math.huge, 0
	for _, name in SEG_PARTS do
		local p = m:FindFirstChild(name) :: BasePart?
		if p then
			local cf = p.CFrame
			local axis = if string.find(name, "Foot") then cf.LookVector * p.Size.Z / 2 else cf.UpVector * p.Size.Y / 2
			local a, c = cf.Position + axis, cf.Position - axis
			table.insert(segs, string.format("%.2f,%.2f,%.2f,%.2f", (a - origin):Dot(fwd), a.Y, (c - origin):Dot(fwd), c.Y))
			if string.find(name, "LowerLeg") then
				kneeY = math.min(kneeY, a.Y) -- the knee end of the shin
			elseif not string.find(name, "Foot") then
				lowest = math.min(lowest, lowestY(p)) -- torso, head, arms, thighs
			end
			maxSpeed = math.max(maxSpeed, p.AssemblyLinearVelocity.Magnitude)
		end
	end
	local kneeR, kneeL = pairAngle(m, "RightUpperLeg", "RightLowerLeg"), pairAngle(m, "LeftUpperLeg", "LeftLowerLeg")
	local hipR, hipL = pairAngle(m, "LowerTorso", "RightUpperLeg"), pairAngle(m, "LowerTorso", "LeftUpperLeg")
	table.insert(b.Samples :: { any }, {
		pelvisY = lower and lower.Position.Y,
		tilt = upper and angleDeg(upper.CFrame.UpVector, Vector3.yAxis),
		knee = if kneeR and kneeL then (kneeR + kneeL) / 2 else nil,
		hip = if hipR and hipL then (hipR + hipL) / 2 else nil,
		lowest = lowest,
		kneeY = kneeY,
		maxSpeed = maxSpeed,
		holding = b.Ragdoll ~= nil and b.Ragdoll.Fall ~= nil and b.Ragdoll.Fall.Hold ~= nil,
		buckled = b.Ragdoll ~= nil and (b.Ragdoll.Fall == nil or b.Ragdoll.Fall.Buckled),
		seg = table.concat(segs, ";"),
		t = t,
		stance = m:GetAttribute("BodyStance"),
		phase = m:GetAttribute("BodyPhase"),
		behaviour = m:GetAttribute("BodyBehaviour"),
		ragdoll = b.Ragdoll ~= nil,
		torsoY = upper and upper.Position.Y,
		headY = head and head.Position.Y,
		torsoX = upper and upper.Position.X,
		torsoZ = upper and upper.Position.Z,
		waistPitch = b.Pose and b.Pose.WaistPitch,
		armSwing = b.Pose and b.Pose.ArmSwing,
		drop = b.Pose and b.Pose.Drop,
		step = b.Pose and b.Pose.Step,
		kAvg = if kN > 0 then kSum / kN else nil,
	})
end

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for m, b in bound do
		if not m.Parent then
			bound[m] = nil
			continue
		end
		local phase = m:GetAttribute("BodyPhase") or "ALIVE"
		local stance = m:GetAttribute("BodyStance") or "STANDING"
		if stance ~= "STANDING" or phase == "DEAD" or phase == "DYING" then
			-- falling / down / dead: the active ragdoll (no flinch while dying [confirmed])
			local behaviour = behaviourOf(m)
			local dead = phase == "DEAD"
			local life = if dead then 0 else (m:GetAttribute("BodyLife") or 100)
			if not b.Ragdoll then
				b.Ragdoll = ActiveRagdoll.enable(m, behaviour, b.Rig.RestC0, t)
				b.RagdollAt = t
				b.Pose = nil -- the standing pose no longer applies
			end
			if b.Ragdoll then
				ActiveRagdoll.update(b.Ragdoll, behaviour, life, dead)
				ActiveRagdoll.step(b.Ragdoll, t) -- the staged fall; does nothing once it is over
			end
		else
			-- standing: a flinch on every new hit, weakened pose from strength / legs, stumble while unstable
			local hits = m:GetAttribute("BodyHits") or 0
			if hits > b.Hits then
				b.Hits = hits
				b.FlinchAt = t
			end
			if m:GetAttribute("BodyUnstable") == true then
				b.UnstableAt = b.UnstableAt or t
			else
				b.UnstableAt = nil
			end
			local flinch = if b.FlinchAt then HitReaction.flinchAmount(t - b.FlinchAt, BodyConfig.ReactSeconds) else 0
			b.Pose = HitReaction.apply(b.Rig, {
				strength = m:GetAttribute("BodyStrength") or 100,
				legs = m:GetAttribute("BodyLegs") or 100,
				flinch = flinch,
				unstableT = if b.UnstableAt then t - b.UnstableAt else nil,
			})
		end
		sample(b, t)
	end
end)

-- Studio-only test hook (server BindableFunction; clients can't reach it):
--   Invoke("status", model) / Invoke("watch", model, seconds) / Invoke("samples", model)
if RunService:IsStudio() then
	local bf = Instance.new("BindableFunction")
	bf.Name = "BodyPresentationDebug"
	bf.OnInvoke = function(cmd: string, model: Model?, a: any): any
		local b = model and bound[model]
		if cmd == "list" then
			local names = {}
			for m in bound do
				table.insert(names, m.Name)
			end
			return names
		end
		if not b then
			return { Bound = false }
		end
		if cmd == "watch" then
			b.Samples = {}
			b.SampleUntil = os.clock() + (tonumber(a) or 3)
			return true
		elseif cmd == "samples" then
			return b.Samples or {}
		elseif cmd == "status" then
			local owners = 0
			local parts = 0
			for _, d in b.Model:GetDescendants() do
				if d:IsA("BasePart") and not d.Anchored then
					parts += 1
					local ok, owner = pcall(function()
						return d:GetNetworkOwner()
					end)
					if ok and owner ~= nil then
						owners += 1
					end
				end
			end
			return {
				Bound = true,
				Ragdoll = if b.Ragdoll then ActiveRagdoll.status(b.Ragdoll) else nil,
				Pose = b.Pose,
				RootAnchored = b.Rig.Root.Anchored,
				UnanchoredParts = parts,
				ClientOwnedParts = owners,
			}
		end
		return { Error = "unknown command" }
	end
	bf.Parent = script
end
