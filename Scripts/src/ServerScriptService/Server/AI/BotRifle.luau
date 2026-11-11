--!strict
-- A bot's rifle (server only): a black rifle held in the right hand, pointing along the body's facing (the template's
-- arms are in the aim pose), and let go once the body is down. It is presentation and a world prop: the bullet is
-- traced from the bot's eye by Server.WeaponShot like a player's, never from this model.
-- The rifle is kept OUTSIDE the bot model (next to it), so the accepted ActiveRagdoll and BodyState never see it: it is
-- welded to the RightHand, massless and not collidable / queryable while held, so it adds nothing to the body's
-- physics, ballistics or line of sight.
-- Basis: bots hold black rifles in an aim pose [confirmed]; the gun is let go ~0.2-0.5 s after RAGDOLL [measured] and
-- stays where it fell [confirmed] (ReferenceAnalysis/AI/AI_Analysis.md A1, A9).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("AI"))

local BotRifle = {}

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function part(name: string, size: Vector3, cf: CFrame, parent: Instance): Part
	local R = Config.Rifle
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = Color3.fromRGB(R.Color[1], R.Color[2], R.Color[3])
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p.Parent = parent
	return p
end

-- Builds the rifle in the bot's right hand along the root's facing. Returns the rifle model (parented next to the bot).
function BotRifle.arm(model: Model): Model?
	local hand = model:FindFirstChild("RightHand") :: BasePart?
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hand or not root then
		return nil
	end
	local R = Config.Rifle
	local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local aim = CFrame.lookAt(hand.Position, hand.Position + forward)
	local cf = aim * CFrame.new(-v3(R.Grip)) -- the grip point sits in the hand

	local rifle = Instance.new("Model")
	rifle.Name = model.Name .. "_Rifle"
	local body = part("Body", v3(R.BodySize), cf, rifle)
	local mag = part("Magazine", v3(R.MagazineSize), cf * CFrame.new(v3(R.MagazineOffset)) * CFrame.Angles(math.rad(-12), 0, 0), rifle)
	local stock = part("Stock", v3(R.StockSize), cf * CFrame.new(0, -0.04, R.BodySize[3] / 2 + R.StockSize[3] / 2 - 0.1), rifle)
	for _, p in { mag, stock } do
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = body, p
		w.Parent = p
	end
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, R.MuzzleZ)
	muzzle.Parent = body
	local grip = Instance.new("WeldConstraint")
	grip.Name = "HandGrip"
	grip.Part0, grip.Part1 = hand, body
	grip.Parent = body
	rifle.PrimaryPart = body
	rifle:SetAttribute(Config.ShotsAttribute, 0)
	rifle:SetAttribute("AIBotName", model.Name)
	rifle.Parent = model.Parent
	CollectionService:AddTag(rifle, Config.RifleTag)
	return rifle
end

-- Let go: the weld goes, the rifle becomes an ordinary server-owned physics prop that stays where it falls.
function BotRifle.drop(rifle: Model)
	local body = rifle.PrimaryPart
	if not body or rifle:GetAttribute("Dropped") == true then
		return
	end
	local grip = body:FindFirstChild("HandGrip")
	if grip then
		grip:Destroy()
	end
	local mass = 0
	for _, d in rifle:GetDescendants() do
		if d:IsA("BasePart") then
			d.Massless = false
			d.CanCollide = true
			mass += d:GetMass()
		end
	end
	-- falls under the project's gravity (35 studs/s^2), as the ragdoll and the grenade do
	local lift = workspace.Gravity - Config.Rifle.Gravity
	if lift > 0 then
		local at = Instance.new("Attachment")
		at.Name = "RifleGravityAttachment"
		at.Parent = body
		local vf = Instance.new("VectorForce")
		vf.Name = "RifleGravity"
		vf.Attachment0 = at
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		vf.ApplyAtCenterOfMass = true
		vf.Force = Vector3.new(0, mass * lift, 0)
		vf.Parent = body
	end
	pcall(function()
		body:SetNetworkOwner(nil) -- server-owned: no client can move it
	end)
	rifle:SetAttribute("Dropped", true)
end

function BotRifle.held(rifle: Model): boolean
	local body = rifle.PrimaryPart
	return body ~= nil and body:FindFirstChild("HandGrip") ~= nil
end

return BotRifle
