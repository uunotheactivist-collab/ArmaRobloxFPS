--!strict
-- Dragging a body (server). The body stays the accepted active ragdoll the whole time: joints, muscles, ragdoll gravity
-- and server ownership are untouched. At the grab it is turned once, rigidly, so its head end points at the player
-- (the footage's one-frame snap into the drag pose). Then one AlignPosition pulls the top of its torso (the grip)
-- toward the player's hand point like a rope: it follows when the player moves away, is slack when the player comes
-- closer, and has a capped force and speed, so the body slides and its limbs trail behind. Nothing is anchored and
-- nothing is moved by script after the grab. The player walks slowly while dragging (Config.Drag.WalkSpeed). Release
-- removes the grip and restores the walk speed. Values: Config.BodyInteraction.Drag (placeholders, tagged there).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("BodyInteraction"))
local BodyPresentationConfig = require(Shared.Config:WaitForChild("BodyPresentation"))

local Drag = {}

export type Hold = {
	Player: Player,
	Model: Model,
	Part: BasePart,
	Grip: Attachment,
	Align: AlignPosition,
	Mass: number,
	Humanoid: Humanoid,
	WalkSpeedBefore: number,
	Started: number,
	Turned: number, -- degrees the body was turned at the grab
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Drag.gripPart(model: Model): BasePart?
	for _, name in Config.Drag.GripParts do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

-- The body is a physical ragdoll right now (the accepted ActiveRagdoll has taken it over: root unanchored, the Humanoid
-- no longer standing it up). The R6 debug-pose bots are anchored: not physical.
function Drag.isPhysical(model: Model): boolean
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return root ~= nil and root:IsA("BasePart") and not root.Anchored and humanoid ~= nil and humanoid.PlatformStand
end

-- The player's hand point: in front of the root, GripHeight above the feet.
local function handPoint(character: Model): Vector3?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return nil
	end
	local feetY = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
	local look = flat(root.CFrame.LookVector)
	local facing = if look.Magnitude > 1e-3 then look.Unit else Vector3.zero
	local p = root.Position
	return Vector3.new(p.X, feetY + Config.Drag.GripHeight, p.Z) + facing * Config.Drag.HandForward
end

-- The one-frame snap into the drag pose: turn the whole body about the vertical through its pelvis so that its head
-- end points at the player. Rigid (every part moves together), so joints, muscles and pose are kept. Returns degrees.
local function alignToPlayer(model: Model, gripPart: BasePart, playerRoot: BasePart): number
	local pelvis = (model:FindFirstChild("LowerTorso") or model:FindFirstChild("Torso")) :: BasePart?
	local head = (model:FindFirstChild("Head") or gripPart) :: BasePart
	if not pelvis then
		return 0
	end
	local c = pelvis.Position
	local axis = flat(head.Position - c)
	local toward = flat(playerRoot.Position - c)
	if axis.Magnitude < 0.2 or toward.Magnitude < 1e-3 then
		return 0
	end
	local delta = math.atan2(toward.X, toward.Z) - math.atan2(axis.X, axis.Z)
	delta = (delta + math.pi) % (2 * math.pi) - math.pi
	if math.abs(delta) < math.rad(Config.Drag.AlignMinDeg) then
		return 0
	end
	local turn = CFrame.new(c) * CFrame.Angles(0, delta, 0) * CFrame.new(-c)
	model:PivotTo(turn * model:GetPivot())
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
	return math.deg(delta)
end

function Drag.grab(player: Player, character: Model, model: Model): Hold?
	local part = Drag.gripPart(model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local playerRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not part or not humanoid or not playerRoot then
		return nil
	end
	local turned = if Config.Drag.AlignOnGrab then alignToPlayer(model, part, playerRoot) else 0
	local mass = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not d.Massless then
			mass += d:GetMass()
		end
	end
	local grip = Instance.new("Attachment")
	grip.Name = "DragGrip"
	grip.CFrame = CFrame.new(0, part.Size.Y / 2, 0) -- the top of the torso (neck end)
	grip.Parent = part
	local D = Config.Drag
	local align = Instance.new("AlignPosition")
	align.Name = "DragAlign"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = grip
	align.ApplyAtCenterOfMass = false
	align.RigidityEnabled = false
	align.Responsiveness = D.Responsiveness
	align.MaxVelocity = D.MaxSpeed
	align.MaxForce = mass * BodyPresentationConfig.Gravity * D.ForceOverWeight
	align.Position = grip.WorldPosition
	align.Parent = part
	local hold: Hold = {
		Player = player,
		Model = model,
		Part = part,
		Grip = grip,
		Align = align,
		Mass = mass,
		Humanoid = humanoid,
		WalkSpeedBefore = humanoid.WalkSpeed,
		Started = os.clock(),
		Turned = turned,
	}
	humanoid.WalkSpeed = D.WalkSpeed
	Drag.update(hold, character)
	return hold
end

-- One server frame: move the rope target. Returns a release reason, or nil to keep dragging.
function Drag.update(hold: Hold, character: Model): string?
	if not hold.Part:IsDescendantOf(workspace) or not hold.Grip.Parent or not hold.Align.Parent then
		return "grip lost"
	end
	local hand = handPoint(character)
	if not hand then
		return "no character"
	end
	local grip = hold.Grip.WorldPosition
	local rel = flat(grip - hand)
	local dist = rel.Magnitude
	if dist > Config.Drag.BreakStuds then
		return "too far"
	end
	local rope = Config.Drag.RopeStuds
	if dist > rope then
		hold.Align.Position = hand + rel.Unit * rope
	else
		hold.Align.Position = Vector3.new(grip.X, hand.Y, grip.Z)
	end
	return nil
end

-- Remove everything the drag added and give the player their walk speed back.
function Drag.release(hold: Hold)
	hold.Align:Destroy()
	hold.Grip:Destroy()
	if hold.Humanoid.Parent and hold.Humanoid.WalkSpeed == Config.Drag.WalkSpeed then
		hold.Humanoid.WalkSpeed = hold.WalkSpeedBefore
	end
end

-- Studio / tests: where the grip and the hand are.
function Drag.describe(hold: Hold, character: Model?): any
	local hand = if character then handPoint(character) else nil
	return {
		Body = hold.Model.Name,
		Player = hold.Player.Name,
		Grip = hold.Grip.WorldPosition,
		Target = hold.Align.Position,
		Hand = hand,
		GripToHand = if hand then flat(hold.Grip.WorldPosition - hand).Magnitude else nil,
		MaxForce = hold.Align.MaxForce,
		Mass = hold.Mass,
		Turned = hold.Turned,
		Seconds = os.clock() - hold.Started,
	}
end

return Drag
