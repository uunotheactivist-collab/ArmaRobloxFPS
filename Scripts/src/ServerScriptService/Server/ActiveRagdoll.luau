--!strict
-- Active ragdoll (server only): the first physics layer for bodies that go down. Data: Shared.Config.BodyPresentation.
-- Basis: ReferenceAnalysis/HitReactions/HitReactions_Analysis.md §3, §6–7.
--   enable(model, behaviour, restC0)  The body becomes physical. Each Motor6D except the root is replaced by a joint
--                             with anatomical limits (one-way hinges at the knees and elbows, limited ball sockets
--                             elsewhere, set from the rig's rest pose). One "muscle" per joint (AlignOrientation)
--                             holds the pose the body went down in, with torque = limb mass × reach × g × gain × k
--                             (the reference's own panel formula). The Humanoid stops controlling the body. Every
--                             part is server-owned. The body falls under the project's gravity (Config.Gravity),
--                             with g in that formula.
--   step(state, now)          The staged fall (Config.Fall), only while it runs:
--                             A support loss after a short stand; B the knees / hips give way (the leg muscles go
--                             slack, the knees are started forward); C the upper body keeps its orientation
--                             (temporary world hold, not for LIMP / DEAD); D the hold fades out while it folds the
--                             upper body forward (and the go-over, if Fall.GoOverAtRelease is on), the leg muscles
--                             take hold again of the pose the legs went down in, and the body is plain active ragdoll
--                             from then on. LIMP: A and B only, so it sinks straight down.
--   update(state, behaviour, life, dead)  k per joint from the behaviour's measured profile, faded with life;
--                             CRAWL pushes along the head direction at the measured 0.6 studs/s; dead → k 0 and the
--                             muscles are switched off.
-- The body is never destroyed: it stays in the world (no despawn is seen in the footage).
-- Rig requirement: R15 joint names, motors with identity-rotation C0 / C1 on a rig whose part axes are the body's
-- (+X right, +Y up, −Z forward), as built by Roblox/Tests/HitReactions/build_range.luau. Players are not integrated.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("BodyPresentation"))

local ActiveRagdoll = {}

export type Muscle = {
	Key: string,
	Motor: string,
	Align: AlignOrientation,
	Target: Attachment, -- the parent-side attachment; its CFrame is the joint's target pose (a "virtual C0")
	BaseTorque: number,
}
export type Fall = {
	Start: number,
	Limp: boolean,
	Buckled: boolean,
	Hold: AlignOrientation?,
	HoldTorque: number,
	HoldTarget: CFrame,
	ReleaseAt: number?,
}
export type State = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Body: CFrame, -- the body's frame when it went down (forward / right for the fall)
	Rest: { [string]: CFrame }, -- rest C0 per motor
	Sockets: { Constraint },
	Muscles: { Muscle },
	K: { [string]: number },
	Profile: string?,
	Life: number,
	Dead: boolean,
	Crawl: LinearVelocity?,
	TotalMass: number,
	Fall: Fall?,
	LegsLoose: boolean, -- the legs have lost support (staged fall B → end)
}

local KEY_OF: { [string]: string } = {} -- motor name → reference joint key
for key, motors in Config.Joints do
	for _, name in motors do
		KEY_OF[name] = key
	end
end

-- motor name → its Config.Limits entry name
local function kindOf(name: string): string
	for _, k in { "Shoulder", "Elbow", "Wrist", "Hip", "Knee", "Ankle" } do
		if string.find(name, k) then
			return k
		end
	end
	return name -- Waist, Neck
end
local LIMB_UP = { Waist = true, Neck = true } -- the child part lies above the joint; all other limbs hang down
local LEG = { Hip = true, Knee = true, Ankle = true } -- the joints that lose support when the legs give way

-- Parts hanging from a part through the rig's motors (the "limb" beyond a joint, the part itself included).
local function subtree(part: BasePart, children: { [BasePart]: { BasePart } }, out: { BasePart })
	table.insert(out, part)
	for _, c in children[part] or {} do
		subtree(c, children, out)
	end
end

local function massAndCom(parts: { BasePart }): (number, Vector3)
	local mass, com = 0, Vector3.zero
	for _, part in parts do
		mass += part:GetMass()
		com += part.Position * part:GetMass()
	end
	return mass, com / math.max(mass, 1e-6)
end

local function profileOf(behaviour: string?): any
	return Config.Profiles[behaviour or ""] or Config.Profiles.POSTURE
end

local function attach(name: string, parent: BasePart, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = parent
	return a
end

-- The anatomical joint between p0 and p1 (motor m), built from the rest pose. Joint frames: X right, Y up, −Z forward.
local function buildJoint(m: Motor6D, p0: BasePart, p1: BasePart, restC0: CFrame): Constraint
	local kind = kindOf(m.Name)
	local lim = Config.Limits[kind]
	local down = if LIMB_UP[kind] then 1 else -1
	local right, limbDir = Vector3.xAxis, Vector3.new(0, down, 0)
	local c: Constraint
	if lim.Hinge then
		-- axis = the body's right; the angle is the same as HitReaction's / the muscles' Angles(θ) about it
		local axes = CFrame.fromMatrix(Vector3.zero, right, limbDir)
		local h = Instance.new("HingeConstraint")
		h.Attachment0 = attach("RagdollJoint0_" .. m.Name, p0, restC0 * axes)
		h.Attachment1 = attach("RagdollJoint1_" .. m.Name, p1, m.C1 * axes)
		h.LimitsEnabled = true
		if kind == "Knee" then -- knee flexion is negative (the foot goes back)
			h.LowerAngle, h.UpperAngle = -lim.Flex, lim.Back
		else -- elbow flexion is positive (the hand comes forward)
			h.LowerAngle, h.UpperAngle = -lim.Back, lim.Flex
		end
		c = h
	else
		-- cone centre tilted forward of the rest limb direction (forward = −Z)
		local t = math.rad(lim.Tilt)
		local centre = Vector3.new(0, down * math.cos(t), -math.sin(t))
		local s = Instance.new("BallSocketConstraint")
		s.Attachment0 = attach("RagdollJoint0_" .. m.Name, p0, restC0 * CFrame.fromMatrix(Vector3.zero, centre, right))
		s.Attachment1 = attach("RagdollJoint1_" .. m.Name, p1, m.C1 * CFrame.fromMatrix(Vector3.zero, limbDir, right))
		s.LimitsEnabled = true
		s.UpperAngle = lim.Cone
		s.TwistLimitsEnabled = true
		s.TwistLowerAngle, s.TwistUpperAngle = -lim.Twist, lim.Twist
		c = s
	end
	c.Name = "RagdollJoint_" .. m.Name
	c.Parent = p1
	return c
end

function ActiveRagdoll.enable(model: Model, behaviour: string?, restC0: { [string]: CFrame }?, now: number?): State?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return nil
	end
	local motors: { Motor6D } = {}
	local children: { [BasePart]: { BasePart } } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			table.insert(motors, d)
			local p0 = d.Part0 :: BasePart
			children[p0] = children[p0] or {}
			table.insert(children[p0], d.Part1 :: BasePart)
		end
	end
	local g = Config.Gravity
	local rest: { [string]: CFrame } = {}
	for _, m in motors do
		rest[m.Name] = if restC0 and restC0[m.Name] then restC0[m.Name] else m.C0
	end
	local state: State = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Body = root.CFrame,
		Rest = rest,
		Sockets = {},
		Muscles = {},
		K = {},
		Profile = nil,
		Life = 100,
		Dead = false,
		Crawl = nil,
		TotalMass = 0,
		Fall = nil,
		LegsLoose = false,
	}

	-- joints + muscles are built while the rig is still anchored, so the held pose is exact
	for _, m in motors do
		if m.Name == "Root" then
			continue
		end
		local p0, p1 = m.Part0 :: BasePart, m.Part1 :: BasePart
		if not Config.Limits[kindOf(m.Name)] then
			continue
		end
		table.insert(state.Sockets, buildJoint(m, p0, p1, rest[m.Name]))
		local nc = Instance.new("NoCollisionConstraint")
		nc.Name = "RagdollNoCollide_" .. m.Name
		nc.Part0, nc.Part1 = p0, p1
		nc.Parent = p1

		local key = KEY_OF[m.Name]
		if key then
			-- muscle: hold the current relative pose ("holding the pose it went down in")
			local mp = attach("MuscleParent_" .. m.Name, p0, m.C0)
			local mc = attach("MuscleChild_" .. m.Name, p1, m.C1)
			local align = Instance.new("AlignOrientation")
			align.Name = "Muscle_" .. m.Name
			align.Mode = Enum.OrientationAlignmentMode.TwoAttachment
			align.Attachment0, align.Attachment1 = mc, mp
			align.RigidityEnabled = false
			align.ReactionTorqueEnabled = true
			align.Responsiveness = Config.Responsiveness
			align.MaxTorque = 0
			align.Parent = p1
			-- limb weight × reach × g × gain (k multiplies it): the limb is p1 and everything hanging from it
			local limb = {}
			subtree(p1, children, limb)
			local mass, com = massAndCom(limb)
			local reach = (com - (p0.CFrame * m.C0).Position).Magnitude
			table.insert(state.Muscles, { Key = key, Motor = m.Name, Align = align, Target = mp, BaseTorque = mass * reach * g * Config.Gain })
		end
		m.Enabled = false
	end

	-- extra no-collide pairs: blocky parts that would jam where a real body compresses (Config.NoCollidePairs)
	for _, pair in Config.NoCollidePairs do
		local a, c = model:FindFirstChild(pair[1]) :: BasePart?, model:FindFirstChild(pair[2]) :: BasePart?
		if a and c then
			local nc = Instance.new("NoCollisionConstraint")
			nc.Name = "RagdollNoCollide_" .. pair[1] .. "_" .. pair[2]
			nc.Part0, nc.Part1 = a, c
			nc.Parent = c
		end
	end

	-- the Humanoid stops standing / balancing; the body is now physics only
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)
	humanoid.EvaluateStateMachine = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d == root then
				d.CanCollide = false
				d.Massless = true
			else
				d.CanCollide = true
				local S = Config.Surface
				d.CustomPhysicalProperties = PhysicalProperties.new(d.CurrentPhysicalProperties.Density, S.Friction,
					S.Elasticity, S.FrictionWeight, S.ElasticityWeight)
				state.TotalMass += d:GetMass()
				-- the body falls under the project's gravity (Config.Gravity), not workspace.Gravity
				local lift = workspace.Gravity - Config.Gravity
				if lift > 0 then
					local at = attach("RagdollGravityAttachment", d, CFrame.identity)
					local vf = Instance.new("VectorForce")
					vf.Name = "RagdollGravity"
					vf.Attachment0 = at
					vf.RelativeTo = Enum.ActuatorRelativeTo.World
					vf.ApplyAtCenterOfMass = true
					vf.Force = Vector3.new(0, d:GetMass() * lift, 0)
					vf.Parent = d
				end
			end
		end
	end
	root.Anchored = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			pcall(function()
				d:SetNetworkOwner(nil) -- server-owned: no client can move the body
			end)
		end
	end
	ActiveRagdoll.update(state, behaviour, 100, false)

	-- the staged fall (Config.Fall): LIMP gets no upper-body hold
	local limp = behaviour == "LIMP"
	local fall: Fall = {
		Start = now or os.clock(),
		Limp = limp,
		Buckled = false,
		Hold = nil,
		HoldTorque = 0,
		HoldTarget = CFrame.identity,
		ReleaseAt = nil,
	}
	local upper = model:FindFirstChild("UpperTorso") :: BasePart?
	local waist = model:FindFirstChild("Waist", true) :: Motor6D?
	if not limp and upper and waist and waist.Part0 then
		local parts = {}
		subtree(upper, children, parts)
		local mass, com = massAndCom(parts)
		local reach = (com - ((waist.Part0 :: BasePart).CFrame * waist.C0).Position).Magnitude
		local hold = Instance.new("AlignOrientation")
		hold.Name = "RagdollUpperHold"
		hold.Mode = Enum.OrientationAlignmentMode.OneAttachment
		hold.Attachment0 = attach("RagdollUpperHoldAttachment", upper, CFrame.identity)
		hold.CFrame = upper.CFrame.Rotation -- the orientation it went down in
		fall.HoldTarget = hold.CFrame
		hold.RigidityEnabled = false
		hold.Responsiveness = Config.Responsiveness
		fall.HoldTorque = mass * reach * g * Config.Fall.UpperHoldK
		hold.MaxTorque = fall.HoldTorque
		hold.Parent = upper
		fall.Hold = hold
	end
	state.Fall = fall
	return state
end

-- Muscle torques from the current profile, life and fall stage: torque = base × k; while the legs have lost support
-- (between B and the end of the fall) the hip / knee / ankle muscles are scaled by Fall.LegSupportDuringFall.
local function refresh(state: State)
	local profile = profileOf(state.Profile)
	local scale = if state.Dead then 0 elseif Config.FadeWithLife then math.max(state.Life, 0) / profile.Life else 1
	for _, mu in state.Muscles do
		local k = math.clamp((profile.k[mu.Key] or 0) * scale, 0, Config.MaxK)
		state.K[mu.Key] = k
		local loose = state.LegsLoose and LEG[kindOf(mu.Motor)] == true
		mu.Align.MaxTorque = mu.BaseTorque * k * (if loose then Config.Fall.LegSupportDuringFall else 1)
		mu.Align.Enabled = not state.Dead -- a dead body has no muscles: nothing left to solve
	end
end

-- B: the legs give way: their muscles lose support and the knees are started forward.
local function buckle(state: State)
	state.LegsLoose = true
	refresh(state)
	-- knees forward: each thigh turns about its hip and each shin about its ankle, at matching knee speeds, so the
	-- hips and feet stay where they are; the body above the hips moves forward with the knees
	local right, fwd = state.Body.RightVector, state.Body.LookVector
	local w = Config.Fall.BuckleStartRadPerSecond
	for _, side in { "Right", "Left" } do
		local thigh = state.Model:FindFirstChild(side .. "UpperLeg") :: BasePart?
		local shin = state.Model:FindFirstChild(side .. "LowerLeg") :: BasePart?
		if thigh and shin then
			local hip = thigh.Position + thigh.CFrame.UpVector * thigh.Size.Y / 2
			local ankle = shin.Position - shin.CFrame.UpVector * shin.Size.Y / 2
			local wt = right * w
			local ws = right * (-w * thigh.Size.Y / shin.Size.Y)
			thigh.AssemblyAngularVelocity += wt
			thigh.AssemblyLinearVelocity += wt:Cross(thigh.Position - hip)
			shin.AssemblyAngularVelocity += ws
			shin.AssemblyLinearVelocity += ws:Cross(shin.Position - ankle)
		end
	end
	for _, name in { "LowerTorso", "UpperTorso", "Head", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand" } do
		local p = state.Model:FindFirstChild(name) :: BasePart?
		if p then
			p.AssemblyLinearVelocity += fwd * Config.Fall.BuckleForwardStudsPerSecond
		end
	end
end

-- D: going over (forward) "about the feet": everything above the feet turns about the feet's front edge.
local function goOver(state: State)
	local feet, n = Vector3.zero, 0
	for _, name in { "RightFoot", "LeftFoot" } do
		local p = state.Model:FindFirstChild(name) :: BasePart?
		if p then
			feet += p.Position + state.Body.LookVector * p.Size.Z / 2
			n += 1
		end
	end
	if n == 0 then
		return
	end
	local pivot = feet / n
	local omega = state.Body.UpVector:Cross(state.Body.LookVector) * Config.GoOverRadPerSecond
	for _, d in state.Model:GetChildren() do
		if d:IsA("BasePart") and d ~= state.Root and not string.find(d.Name, "Foot") then
			d.AssemblyLinearVelocity += omega:Cross(d.Position - pivot)
			d.AssemblyAngularVelocity += omega
		end
	end
end

-- The staged fall, called every frame while state.Fall exists (it ends itself).
function ActiveRagdoll.step(state: State, now: number)
	local f = state.Fall
	if not f then
		return
	end
	local F = Config.Fall
	local t = now - f.Start
	if not f.Buckled and t >= (if f.Limp then F.LimpSupportLossSeconds else F.SupportLossSeconds) then
		f.Buckled = true
		buckle(state)
	end
	local hold = f.Hold
	if hold then
		if not f.ReleaseAt and (t >= F.UpperHoldSeconds or state.Dead) then
			f.ReleaseAt = t
			if F.GoOverAtRelease and not state.Dead then
				goOver(state)
			end
		end
		local releaseAt = f.ReleaseAt
		if releaseAt then
			local u = (t - releaseAt) / F.ReleaseFadeSeconds
			if u >= 1 then
				local a = hold.Attachment0
				hold:Destroy()
				if a then
					a:Destroy()
				end
				f.Hold = nil
			else
				-- the upper body folds forward while the hold fades out
				local axis = state.Body.UpVector:Cross(state.Body.LookVector)
				hold.CFrame = CFrame.fromAxisAngle(axis, math.rad(F.FoldDeg) * u) * f.HoldTarget
				hold.MaxTorque = f.HoldTorque * (1 - u)
			end
		end
	end
	if f.Buckled and not f.Hold then
		-- the end of the fall: the leg muscles take hold again, of the pose the legs went down in
		for _, mu in state.Muscles do
			if LEG[kindOf(mu.Motor)] then
				local parent = mu.Target.Parent :: BasePart
				local child = mu.Align.Attachment0 :: Attachment
				mu.Target.CFrame = parent.CFrame:ToObjectSpace(child.WorldCFrame)
			end
		end
		state.LegsLoose = false
		refresh(state)
		state.Fall = nil -- plain active ragdoll from here on
	end
end

function ActiveRagdoll.update(state: State, behaviour: string?, life: number, dead: boolean)
	if behaviour ~= state.Profile or math.abs(life - state.Life) >= 0.5 or dead ~= state.Dead then
		state.Profile, state.Life, state.Dead = behaviour, life, dead
		refresh(state)
	end
	-- CRAWL: push along the head direction at the measured speed
	local crawling = behaviour == "CRAWL" and not dead
	if crawling and not state.Crawl then
		local upper = state.Model:FindFirstChild("UpperTorso") :: BasePart?
		if upper then
			local dir = Vector3.new(upper.CFrame.UpVector.X, 0, upper.CFrame.UpVector.Z)
			if dir.Magnitude < 1e-3 then
				dir = Vector3.new(upper.CFrame.LookVector.X, 0, upper.CFrame.LookVector.Z)
			end
			local att = attach("CrawlAttachment", upper, CFrame.identity)
			local lv = Instance.new("LinearVelocity")
			lv.Name = "Crawl"
			lv.Attachment0 = att
			lv.RelativeTo = Enum.ActuatorRelativeTo.World
			lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
			lv.LineDirection = dir.Unit
			lv.LineVelocity = Config.CrawlSpeed
			lv.MaxForce = state.TotalMass * Config.Gravity * Config.Surface.Friction * Config.CrawlForceOverFriction
			lv.Parent = upper
			state.Crawl = lv
		end
	elseif not crawling and state.Crawl then
		local att = state.Crawl.Attachment0
		state.Crawl:Destroy()
		if att then
			att:Destroy()
		end
		state.Crawl = nil
	end
end

function ActiveRagdoll.status(state: State): any
	local enabled = 0
	for _, d in state.Model:GetDescendants() do
		if d:IsA("Motor6D") and d.Enabled then
			enabled += 1
		end
	end
	local hinges = 0
	for _, s in state.Sockets do
		if s:IsA("HingeConstraint") then
			hinges += 1
		end
	end
	local musclesOn = 0
	for _, mu in state.Muscles do
		if mu.Align.Enabled then
			musclesOn += 1
		end
	end
	return {
		Profile = state.Profile,
		Life = state.Life,
		Dead = state.Dead,
		K = table.clone(state.K),
		Sockets = #state.Sockets,
		Hinges = hinges,
		Muscles = #state.Muscles,
		MusclesOn = musclesOn,
		MotorsEnabled = enabled,
		RootAnchored = state.Root.Anchored,
		Crawl = state.Crawl ~= nil,
		Falling = state.Fall ~= nil,
		Holding = state.Fall ~= nil and state.Fall.Hold ~= nil,
		UpperHoldLeft = state.Model:FindFirstChild("RagdollUpperHold", true) ~= nil,
	}
end

return ActiveRagdoll
