--!strict
-- Grenade throw (server): checks the client's aim and builds the launch from the SERVER's own state. A client sends a
-- direction only; the release point is the server's copy of the head plus a left-hand offset, the speed is the
-- config's. The grenade body is real Roblox physics (bounce, roll) under the project's gravity, owned by the server, and
-- never moved by script after launch. Values: Shared.Config.Grenade (tagged).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Grenade"))

local Throw = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function finite(v: Vector3): boolean
	for _, n in { v.X, v.Y, v.Z } do
		if n ~= n or n == math.huge or n == -math.huge then
			return false
		end
	end
	return true
end

-- The client's aim as a unit direction, or why it is refused. It must be a direction (|v| ≈ 1: never a velocity) and
-- must not point behind the character.
function Throw.aim(character: Model, aim: any): (Vector3?, string?)
	if typeof(aim) ~= "Vector3" then
		return nil, "no direction"
	end
	local v = aim :: Vector3
	if not finite(v) then
		return nil, "not finite"
	end
	if math.abs(v.Magnitude - 1) > Config.Throw.DirectionTolerance then
		return nil, `not a direction (|v| = {math.floor(v.Magnitude * 100 + 0.5) / 100})`
	end
	local dir = v.Unit
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local facing, a = flat(root.CFrame.LookVector), flat(dir)
		if facing.Magnitude > 1e-3 and a.Magnitude > 1e-3 and facing.Unit:Dot(a.Unit) < Config.Throw.MaxBehindDot then
			return nil, "behind the thrower"
		end
	end
	return dir, nil
end

-- The launch direction: the aim turned up by LiftDeg and left by YawLeftDeg in the aim's own axes (the reference's lobs
-- leave ≈ 21° above and 11° left of the screen centre). Server-side, from the validated aim; a client can't choose it.
function Throw.direction(dir: Vector3): Vector3
	local T = Config.Throw
	local frame = CFrame.lookAt(Vector3.zero, dir)
	return (frame * CFrame.Angles(0, math.rad(T.YawLeftDeg or 0), 0) * CFrame.Angles(math.rad(T.LiftDeg or 0), 0, 0)).LookVector
end

-- Release point and velocity from the server's head. The point is pulled back if geometry is between head and hand.
function Throw.launch(character: Model, dir: Vector3): (Vector3?, Vector3?)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return nil, nil
	end
	local frame = CFrame.lookAt(head.Position, head.Position + dir)
	local hand = frame:PointToWorldSpace(Config.Throw.HandOffset)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local blocked = workspace:Raycast(head.Position, hand - head.Position, params)
	if blocked then
		hand = blocked.Position - (hand - head.Position).Unit * (Config.Body.Diameter * 0.75)
	end
	return hand, Throw.direction(dir) * Config.Throw.Speed
end

function Throw.folder(): Folder
	local f = workspace:FindFirstChild("Grenades")
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "Grenades"
	nf.Parent = workspace
	return nf
end

-- The grenade body: one small ball (+ a massless yellow band), the thrower's character can't knock it, the project's
-- gravity, a weak roll brake, then the launch velocity. Server-owned.
function Throw.spawn(id: number, character: Model, origin: Vector3, velocity: Vector3): BasePart
	local B = Config.Body
	local body = Instance.new("Part")
	body.Name = "FragGrenade"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(B.Diameter, B.Diameter, B.Diameter)
	body.Color = B.Color
	body.Material = Enum.Material.SmoothPlastic
	body.CustomPhysicalProperties = PhysicalProperties.new(B.Density, B.Friction, B.Elasticity, 100, 100)
	body.CanTouch = false
	body.CFrame = CFrame.lookAt(origin, origin + velocity)
	body:SetAttribute("GrenadeId", id)

	local band = Instance.new("Part")
	band.Name = "Band"
	band.Shape = Enum.PartType.Cylinder
	band.Size = Vector3.new(B.Diameter * 0.18, B.Diameter * 1.04, B.Diameter * 1.04)
	band.Color = B.BandColor
	band.Material = Enum.Material.SmoothPlastic
	band.Massless = true
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.CFrame = body.CFrame * CFrame.Angles(0, 0, math.rad(90))
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = body, band
	weld.Parent = band
	band.Parent = body

	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0, nc.Part1 = body, d
			nc.Parent = body
		end
	end

	local at = Instance.new("Attachment")
	at.Parent = body
	local lift = workspace.Gravity - B.Gravity
	if lift ~= 0 then
		local vf = Instance.new("VectorForce")
		vf.Attachment0 = at
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		vf.ApplyAtCenterOfMass = true
		vf.Force = Vector3.new(0, body:GetMass() * lift, 0)
		vf.Parent = body
	end
	local brake = Instance.new("AngularVelocity")
	brake.Attachment0 = at
	brake.AngularVelocity = Vector3.zero
	brake.MaxTorque = B.RollDampingTorque
	brake.RelativeTo = Enum.ActuatorRelativeTo.World
	brake.Parent = body

	body.Parent = Throw.folder()
	pcall(function()
		body:SetNetworkOwner(nil) -- server-owned: no client can move it
	end)
	body.AssemblyLinearVelocity = velocity
	return body
end

return Throw
