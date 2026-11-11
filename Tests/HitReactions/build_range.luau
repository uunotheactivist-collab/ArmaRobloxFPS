-- Builds the hit-reaction / active-ragdoll test range Workspace.HitReactionTest and its respawn templates
-- (ServerStorage.HitReactionTemplates). Run once in Studio Edit mode; it is saved with the place, and rebuilding
-- replaces both.
-- REACT1–6: blocky test bots with the reference's R15-like joint set (neck, waist, shoulders, elbows, wrists, hips,
--   knees, ankles; R15 part and joint names). They are proportioned like the R6 test bots: 5 studs tall, torso
--   2–4 studs split at 3 into LowerTorso (abdomen) and UpperTorso (chest, throat band on top).
--   Attributes: BodyModel (BodyState), BodyDebugView (tag), BodyPresentation = "ActiveRagdoll".
--   The root is anchored while standing. Each joint has "<Joint>RigAttachment" pairs whose X axis runs along the limb.
-- PRES1: the same rig with only BodyPresentation (no BodyModel). Presentation-only checks write its Body* attributes
--   directly (synthetic states, not BodyState output).
-- Lanes: bots at z = 110, x = -350 … -400 (PRES1 at x = -420), shooter spots at z = 125, NonPenetrable backstop z = 100.

local ServerStorage = game:GetService("ServerStorage")

local Z_BOT, Z_SPOT, Z_BACK = 110, 125, 100
local X0, DX = -350, -10

local function part(name: string, size: Vector3, cf: CFrame, parent: Instance, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props or {} do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local BLACK, OLIVE, WHITE, NAVY = Color3.fromRGB(20, 20, 22), Color3.fromRGB(88, 94, 58), Color3.fromRGB(235, 235, 235), Color3.fromRGB(38, 44, 74)
-- name, size, centre (feet at y = 0, local +X = the bot's right), colour
local PARTS = {
	{ "LowerTorso", Vector3.new(2, 1, 1), Vector3.new(0, 2.5, 0), OLIVE },
	{ "UpperTorso", Vector3.new(2, 1, 1), Vector3.new(0, 3.5, 0), OLIVE },
	{ "Head", Vector3.new(2, 1, 1), Vector3.new(0, 4.5, 0), BLACK },
	{ "RightUpperArm", Vector3.new(1, 1, 1), Vector3.new(1.5, 3.5, 0), WHITE },
	{ "RightLowerArm", Vector3.new(1, 0.7, 1), Vector3.new(1.5, 2.65, 0), WHITE },
	{ "RightHand", Vector3.new(1, 0.3, 1), Vector3.new(1.5, 2.15, 0), WHITE },
	{ "LeftUpperArm", Vector3.new(1, 1, 1), Vector3.new(-1.5, 3.5, 0), WHITE },
	{ "LeftLowerArm", Vector3.new(1, 0.7, 1), Vector3.new(-1.5, 2.65, 0), WHITE },
	{ "LeftHand", Vector3.new(1, 0.3, 1), Vector3.new(-1.5, 2.15, 0), WHITE },
	{ "RightUpperLeg", Vector3.new(1, 1, 1), Vector3.new(0.5, 1.5, 0), NAVY },
	{ "RightLowerLeg", Vector3.new(1, 0.7, 1), Vector3.new(0.5, 0.65, 0), NAVY },
	{ "RightFoot", Vector3.new(1, 0.3, 1), Vector3.new(0.5, 0.15, 0), NAVY },
	{ "LeftUpperLeg", Vector3.new(1, 1, 1), Vector3.new(-0.5, 1.5, 0), NAVY },
	{ "LeftLowerLeg", Vector3.new(1, 0.7, 1), Vector3.new(-0.5, 0.65, 0), NAVY },
	{ "LeftFoot", Vector3.new(1, 0.3, 1), Vector3.new(-0.5, 0.15, 0), NAVY },
}
-- joint, parent, child, position, limb direction (+1 up, -1 down)
local JOINTS = {
	{ "Root", "HumanoidRootPart", "LowerTorso", Vector3.new(0, 2.5, 0), 1 },
	{ "Waist", "LowerTorso", "UpperTorso", Vector3.new(0, 3.0, 0), 1 },
	{ "Neck", "UpperTorso", "Head", Vector3.new(0, 4.0, 0), 1 },
	{ "RightShoulder", "UpperTorso", "RightUpperArm", Vector3.new(1.5, 3.9, 0), -1 },
	{ "RightElbow", "RightUpperArm", "RightLowerArm", Vector3.new(1.5, 3.0, 0), -1 },
	{ "RightWrist", "RightLowerArm", "RightHand", Vector3.new(1.5, 2.3, 0), -1 },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm", Vector3.new(-1.5, 3.9, 0), -1 },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", Vector3.new(-1.5, 3.0, 0), -1 },
	{ "LeftWrist", "LeftLowerArm", "LeftHand", Vector3.new(-1.5, 2.3, 0), -1 },
	{ "RightHip", "LowerTorso", "RightUpperLeg", Vector3.new(0.5, 2.0, 0), -1 },
	{ "RightKnee", "RightUpperLeg", "RightLowerLeg", Vector3.new(0.5, 1.0, 0), -1 },
	{ "RightAnkle", "RightLowerLeg", "RightFoot", Vector3.new(0.5, 0.3, 0), -1 },
	{ "LeftHip", "LowerTorso", "LeftUpperLeg", Vector3.new(-0.5, 2.0, 0), -1 },
	{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", Vector3.new(-0.5, 1.0, 0), -1 },
	{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", Vector3.new(-0.5, 0.3, 0), -1 },
}

local function buildBot(name: string, base: CFrame, isBody: boolean): Model
	local m = Instance.new("Model")
	m.Name = name
	if isBody then
		m:SetAttribute("BodyModel", true)
		m:SetAttribute("BodyDebugView", true)
	end
	m:SetAttribute("BodyPresentation", "ActiveRagdoll")
	local parts: { [string]: BasePart } = {}
	parts.HumanoidRootPart = part("HumanoidRootPart", Vector3.new(2, 2, 1), base * CFrame.new(0, 3, 0), m,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, Anchored = true })
	for _, p in PARTS do
		parts[p[1]] = part(p[1], p[2], base * CFrame.new(p[3]), m, { Color = p[4], Anchored = false })
	end
	for _, j in JOINTS do
		local p0, p1 = parts[j[2]], parts[j[3]]
		local jointCF = base * CFrame.new(j[4])
		local motor = Instance.new("Motor6D")
		motor.Name = j[1]
		motor.Part0, motor.Part1 = p0, p1
		motor.C0 = p0.CFrame:ToObjectSpace(jointCF)
		motor.C1 = p1.CFrame:ToObjectSpace(jointCF)
		motor.Parent = p1
		if j[1] ~= "Root" then
			-- rig attachments for the ragdoll's ball sockets: X axis along the limb (child direction)
			local axisCF = base * CFrame.fromMatrix(j[4], Vector3.new(0, j[5], 0), Vector3.new(1, 0, 0))
			for _, holder in { p0, p1 } do
				local a = Instance.new("Attachment")
				a.Name = j[1] .. "RigAttachment"
				a.CFrame = holder.CFrame:ToObjectSpace(axisCF)
				a.Parent = holder
			end
		end
	end
	m.PrimaryPart = parts.HumanoidRootPart
	local h = Instance.new("Humanoid")
	h.RigType = Enum.HumanoidRigType.R15
	h.AutomaticScalingEnabled = false
	h.RequiresNeck = false
	h.BreakJointsOnDeath = false
	h.HipHeight = 2
	h.MaxHealth = 100
	h.Health = 100
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	h.Parent = m
	return m
end

for _, holder in { workspace, ServerStorage } do
	local old = holder:FindFirstChild(if holder == workspace then "HitReactionTest" else "HitReactionTemplates")
	if old then
		old:Destroy()
	end
end
local root = Instance.new("Folder")
root.Name = "HitReactionTest"
local templates = Instance.new("Folder")
templates.Name = "HitReactionTemplates"

for i = 1, 7 do
	local isPres = i == 7
	local x = if isPres then -420 else X0 + DX * (i - 1)
	local name = if isPres then "PRES1" else "REACT" .. i
	local f = Instance.new("Folder")
	f.Name = if isPres then "Pres1" else "Bot" .. i
	part("ShooterSpot", Vector3.new(4, 0.2, 4), CFrame.new(x, 0.1, Z_SPOT), f,
		{ Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Color = Color3.fromRGB(80, 160, 80), Material = Enum.Material.Neon, Transparency = 0.4 })
	local base = CFrame.lookAt(Vector3.new(x, 0, Z_BOT), Vector3.new(x, 0, Z_SPOT))
	local bot = buildBot(name, base, not isPres)
	bot:Clone().Parent = templates
	bot.Parent = f
	f.Parent = root
end
local back = part("Backstop", Vector3.new(84, 12, 2), CFrame.new(-385, 6, Z_BACK), root,
	{ Anchored = true, Material = Enum.Material.Slate, Color = Color3.fromRGB(60, 60, 65) })
back:SetAttribute("BallisticSurface", "NonPenetrable")
templates.Parent = ServerStorage
root.Parent = workspace
return "built " .. #root:GetChildren() .. " children; templates " .. #templates:GetChildren()
