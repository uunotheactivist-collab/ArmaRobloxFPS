-- Builds the controlled ballistic test range Workspace.BallisticTest (run once in Studio Edit mode; the range is
-- saved with the place). Rebuilding replaces the folder. Away from the play area (spawn at the origin).
--   Lane A  shooter -> target                                  (direct hit)
--   Lane B  shooter -> thin Penetrable wall (0.5 studs) -> target
--   Lane C  shooter -> NonPenetrable wall (2 studs) -> target
-- Each lane: ShooterSpot (where the player stands), a target dummy 40 studs downrange and a NonPenetrable backstop
-- 20 studs behind it (shows where a bullet that passed through the target ends). Walls are 20 studs downrange.
-- Surface classes are set with the attribute BallisticSurface (Shared.Config.Ballistics).

local LANES = {
	{ Name = "A", X = -200, Wall = nil },
	{ Name = "B", X = -175, Wall = { Class = "Penetrable", Thickness = 0.5, Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(160, 120, 80) } },
	{ Name = "C", X = -150, Wall = { Class = "NonPenetrable", Thickness = 2, Material = Enum.Material.Concrete, Color = Color3.fromRGB(110, 110, 115) } },
}
local Z_SHOOTER, Z_WALL, Z_TARGET, Z_BACKSTOP = 150, 130, 110, 90

local old = workspace:FindFirstChild("BallisticTest")
if old then
	old:Destroy()
end
local root = Instance.new("Folder")
root.Name = "BallisticTest"

local function part(name: string, size: Vector3, pos: Vector3, parent: Instance, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = pos
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in props or {} do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function dummy(name: string, x: number, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("BallisticSurface", "Target")
	local grey = { Color = Color3.fromRGB(200, 200, 200), Material = Enum.Material.SmoothPlastic }
	local z = Z_TARGET
	local torso = part("Torso", Vector3.new(2, 2, 1), Vector3.new(x, 3, z), m, grey)
	part("Head", Vector3.new(2, 1, 1), Vector3.new(x, 4.5, z), m, grey)
	part("Left Arm", Vector3.new(1, 2, 1), Vector3.new(x - 1.5, 3, z), m, grey)
	part("Right Arm", Vector3.new(1, 2, 1), Vector3.new(x + 1.5, 3, z), m, grey)
	part("Left Leg", Vector3.new(1, 2, 1), Vector3.new(x - 0.5, 1, z), m, grey)
	part("Right Leg", Vector3.new(1, 2, 1), Vector3.new(x + 0.5, 1, z), m, grey)
	local hrp = part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(x, 3, z), m,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	m.PrimaryPart = hrp
	local h = Instance.new("Humanoid")
	h.RequiresNeck = false
	h.BreakJointsOnDeath = false
	h.MaxHealth = 100
	h.Health = 100
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.Parent = m
	m.Parent = parent
	return m
end

for _, lane in LANES do
	local f = Instance.new("Folder")
	f.Name = "Lane" .. lane.Name
	f:SetAttribute("Lane", lane.Name)
	part("ShooterSpot", Vector3.new(4, 0.2, 4), Vector3.new(lane.X, 0.1, Z_SHOOTER), f,
		{ CanCollide = false, CanQuery = false, CanTouch = false, Color = Color3.fromRGB(80, 160, 80), Material = Enum.Material.Neon, Transparency = 0.4 })
	if lane.Wall then
		local w = part(lane.Wall.Class .. "Wall", Vector3.new(10, 10, lane.Wall.Thickness), Vector3.new(lane.X, 5, Z_WALL), f,
			{ Material = lane.Wall.Material, Color = lane.Wall.Color })
		w:SetAttribute("BallisticSurface", lane.Wall.Class)
	end
	dummy("Target", lane.X, f)
	local b = part("Backstop", Vector3.new(12, 12, 2), Vector3.new(lane.X, 6, Z_BACKSTOP), f,
		{ Material = Enum.Material.Slate, Color = Color3.fromRGB(60, 60, 65) })
	b:SetAttribute("BallisticSurface", "NonPenetrable")
	f.Parent = root
end
root.Parent = workspace
return "built " .. #root:GetChildren() .. " lanes"
