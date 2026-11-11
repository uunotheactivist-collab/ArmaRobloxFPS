-- Builds the body-state test range Workspace.BodyStateTest. Run once in Studio Edit mode; it is saved with the
-- place, and rebuilding replaces it. It sits away from the play area and the ballistic range.
-- Six anchored R6-style test bots BODY1–BODY6 (model attributes BodyModel = true, BodyDebugView = true), each facing
-- its own shooter spot 15 studs away, with a NonPenetrable backstop behind the row.
--   Bot1: limb (arm)      Bot2: gut (abdomen)      Bot3: throat (top of chest)
--   Bot4: lung (chest ×3) Bot5: brain (head)       Bot6: legs ×2, then a hit while down
-- Colours follow the reference test bots: black head, olive torso, white arms, navy legs.

local Z_BOT, Z_SPOT, Z_BACK = 110, 125, 100
local X0, DX = -270, -10

local old = workspace:FindFirstChild("BodyStateTest")
if old then
	old:Destroy()
end
local root = Instance.new("Folder")
root.Name = "BodyStateTest"

local function part(name: string, size: Vector3, cf: CFrame, parent: Instance, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
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

for i = 1, 6 do
	local x = X0 + DX * (i - 1)
	local f = Instance.new("Folder")
	f.Name = "Bot" .. i
	part("ShooterSpot", Vector3.new(4, 0.2, 4), CFrame.new(x, 0.1, Z_SPOT), f,
		{ CanCollide = false, CanQuery = false, CanTouch = false, Color = Color3.fromRGB(80, 160, 80), Material = Enum.Material.Neon, Transparency = 0.4 })

	local m = Instance.new("Model")
	m.Name = "BODY" .. i
	m:SetAttribute("BodyModel", true)
	m:SetAttribute("BodyDebugView", true)
	-- facing the shooter: LookVector (local -Z) points at the spot; the bot's right side is local +X
	local rootCF = CFrame.lookAt(Vector3.new(x, 3, Z_BOT), Vector3.new(x, 3, Z_SPOT))
	local hrp = part("HumanoidRootPart", Vector3.new(2, 2, 1), rootCF, m,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	part("Torso", Vector3.new(2, 2, 1), rootCF, m, { Color = Color3.fromRGB(88, 94, 58) })
	part("Head", Vector3.new(2, 1, 1), rootCF * CFrame.new(0, 1.5, 0), m, { Color = Color3.fromRGB(20, 20, 22) })
	part("Right Arm", Vector3.new(1, 2, 1), rootCF * CFrame.new(1.5, 0, 0), m, { Color = Color3.fromRGB(235, 235, 235) })
	part("Left Arm", Vector3.new(1, 2, 1), rootCF * CFrame.new(-1.5, 0, 0), m, { Color = Color3.fromRGB(235, 235, 235) })
	part("Right Leg", Vector3.new(1, 2, 1), rootCF * CFrame.new(0.5, -2, 0), m, { Color = Color3.fromRGB(38, 44, 74) })
	part("Left Leg", Vector3.new(1, 2, 1), rootCF * CFrame.new(-0.5, -2, 0), m, { Color = Color3.fromRGB(38, 44, 74) })
	m.PrimaryPart = hrp
	local h = Instance.new("Humanoid")
	h.RequiresNeck = false
	h.BreakJointsOnDeath = false
	h.MaxHealth = 100
	h.Health = 100
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	h.Parent = m
	m.Parent = f
	f.Parent = root
end

local back = part("Backstop", Vector3.new(64, 12, 2), CFrame.new(X0 + DX * 2.5, 6, Z_BACK), root,
	{ Material = Enum.Material.Slate, Color = Color3.fromRGB(60, 60, 65) })
back:SetAttribute("BallisticSurface", "NonPenetrable")
root.Parent = workspace
return "built " .. #root:GetChildren() .. " children"
