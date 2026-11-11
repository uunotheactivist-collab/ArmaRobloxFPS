-- Builds Workspace.OpticsTest (Edit mode, run once through the Studio MCP / command bar). Isolated lane on the +Z half
-- of the baseplate (nothing else lives beyond z = 310). Firing point F = (0, 0, 400), facing +Z.
--
--   FiringPoint            pad at F
--   Bots (REACT1 copies, the accepted balanced body bot; BodyModel -> BodyState / reactions / blood):
--     OPT_NEAR    (0, 3, 425)    25 studs
--     OPT_MEDIUM  (6, 3, 500)    100 studs
--     OPT_COVER   (-6, 3, 560)   160 studs, behind CoverWall (only head / chest above it)
--     OPT_DISTANT (0, 3, 700)    300 studs
--   CoverWall              (-6, 2.1, 556)  6 x 4.2 x 1, unmarked = NonPenetrable (stops bullets)
--   ScaleBoard50/150/400   white boards with a red and a blue marker that subtend the SAME angle from F (0.04 rad =
--                          2.29 deg): 2 studs at 50, 6 at 150, 16 at 400. Marker spacing on screen = magnification check
--   AlignWall              black wall at z 650 (250 studs), x 20..60, y 0..14: its top-left corner (20, 14, 650) is a
--                          sharp light/dark corner for reticle alignment
--   RefPosts               low posts on a 30-stud arc around F at -30..-10 and 10..30 deg (step 5), alternating
--                          1.5 / 2.5 tall: camera reference points below every line of sight to the boards and bots
--   FarBoard               20 x 20 checker board at (0, 10, 950), 550 studs
-- Everything is anchored. Bots are re-spawned fresh by the Optics test server module (ServerScriptService.OpticsTest.Run).

local ServerStorage = game:GetService("ServerStorage")

local old = workspace:FindFirstChild("OpticsTest")
if old then
	old:Destroy()
end
local root = Instance.new("Folder")
root.Name = "OpticsTest"

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or root
	return p
end

local F = Vector3.new(0, 0, 400)
local pad = part("FiringPoint", Vector3.new(6, 0.2, 6), CFrame.new(F + Vector3.new(0, 0.1, 0)), Color3.fromRGB(60, 62, 66))
pad:SetAttribute("OpticsRole", "FiringPoint")

-- bots
local bots = Instance.new("Folder")
bots.Name = "Bots"
bots.Parent = root
local spots = Instance.new("Folder")
spots.Name = "BotSpots"
spots.Parent = root
local BOTS = {
	{ "OPT_NEAR", Vector3.new(0, 3, 425) },
	{ "OPT_MEDIUM", Vector3.new(6, 3, 500) },
	{ "OPT_COVER", Vector3.new(-6, 3, 560) },
	{ "OPT_DISTANT", Vector3.new(0, 3, 700) },
}
local template = ServerStorage:WaitForChild("HitReactionTemplates"):WaitForChild("REACT1")
for _, b in BOTS do
	local spot = part(b[1] .. "_Spot", Vector3.new(2, 0.1, 2), CFrame.new(b[2].X, 0.05, b[2].Z), Color3.fromRGB(90, 90, 96), nil, spots)
	spot.CanCollide = false
	spot:SetAttribute("OpticsRole", "BotSpot")
	local bot = template:Clone()
	bot.Name = b[1]
	bot:PivotTo(CFrame.new(b[2])) -- facing -Z, towards the firing point
	bot.Parent = bots
end

part("CoverWall", Vector3.new(6, 4.2, 1), CFrame.new(-6, 2.1, 556), Color3.fromRGB(120, 120, 118), Enum.Material.Concrete)

-- scale boards: markers 0.04 rad apart seen from F
local function board(name: string, dist: number, x: number, y: number, spacing: number, marker: number)
	local b = part(name, Vector3.new(spacing * 2.2, marker * 4, 0.4), CFrame.new(x, y, F.Z + dist), Color3.fromRGB(235, 235, 235))
	b:SetAttribute("OpticsRole", "ScaleBoard")
	b:SetAttribute("MarkerSpacing", spacing)
	b:SetAttribute("Distance", dist)
	local r = part(name .. "_Red", Vector3.new(marker, marker, 0.2), CFrame.new(x - spacing / 2, y, F.Z + dist - 0.31),
		Color3.fromRGB(255, 0, 0), Enum.Material.Neon)
	local u = part(name .. "_Blue", Vector3.new(marker, marker, 0.2), CFrame.new(x + spacing / 2, y, F.Z + dist - 0.31),
		Color3.fromRGB(0, 60, 255), Enum.Material.Neon)
	r:SetAttribute("OpticsRole", "Marker")
	u:SetAttribute("OpticsRole", "Marker")
end
board("ScaleBoard50", 50, -14, 4, 2, 0.6)
board("ScaleBoard150", 150, -24, 5, 6, 1.4)
board("ScaleBoard400", 400, -50, 20, 16, 3.2) -- raised: at y 8 the 150-stud board hides it from F

local wall = part("AlignWall", Vector3.new(40, 14, 1), CFrame.new(40, 7, 650.5), Color3.fromRGB(12, 12, 14))
wall:SetAttribute("OpticsRole", "AlignWall")
wall:SetAttribute("Corner", Vector3.new(20, 14, 650))

local posts = Instance.new("Folder")
posts.Name = "RefPosts"
posts.Parent = root
local i = 0
for deg = -30, 30, 5 do
	if math.abs(deg) >= 10 then
		i += 1
		local th = math.rad(deg)
		local h = if i % 2 == 0 then 2.5 else 1.5
		local c = if i % 2 == 0 then Color3.fromRGB(230, 170, 30) else Color3.fromRGB(40, 140, 220)
		local p = part(string.format("Post%+03d", deg), Vector3.new(0.6, h, 0.6),
			CFrame.new(F.X + 30 * math.sin(th), h / 2, F.Z + 30 * math.cos(th)), c, nil, posts)
		p:SetAttribute("OpticsRole", "RefPost")
		p:SetAttribute("AngleDeg", deg)
	end
end

local far = Instance.new("Model")
far.Name = "FarBoard"
for gx = 0, 3 do
	for gy = 0, 3 do
		local c = if (gx + gy) % 2 == 0 then Color3.fromRGB(20, 20, 20) else Color3.fromRGB(240, 240, 240)
		part(string.format("Tile%d%d", gx, gy), Vector3.new(5, 5, 0.5), CFrame.new(-7.5 + gx * 5, 2.5 + gy * 5, 950), c, nil, far)
	end
end
far.Parent = root

root.Parent = workspace
local n = 0
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then
		n += 1
	end
end
return "OpticsTest built: " .. n .. " parts"
