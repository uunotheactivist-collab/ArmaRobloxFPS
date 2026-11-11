-- Builds Workspace.MP7Test (Edit mode, run once through the Studio MCP / command bar). Isolated area on the baseplate
-- at x 400..540, z -350..-150 (checked empty before building: no other test range or world part lives there).
-- Firing point F = (450, 0, -330), facing +Z.
--
--   FiringLane:
--     FiringPoint     pad at F
--     MP7_CLOSE       (450, 3, -320)   10 studs
--     MP7_MEDIUM      (454, 3, -280)   50 studs
--     MP7_DISTANT     (450, 3, -180)   150 studs
--     PenWall         (440, 2.5, -306)  6 x 5 x 1, BallisticSurface = Penetrable (1 stud: cost 1 of the 2.0 budget)
--     MP7_BEHIND_PEN  (440, 3, -302)   the bullet must pass PenWall to reach it
--     SolidWall       (462, 2.5, -306)  6 x 5 x 1, unmarked = NonPenetrable
--     MP7_BEHIND_SOLID (462, 3, -302)  never hit through SolidWall
--     WallTarget      (430, 5, -270)   8 x 10 x 1 white board, NonPenetrable: plain wall-hit / impact target
--   ReloadLane:  pad at (480, 0, -330) facing +Z (nothing in front for 200 studs: reloads, firing without hits)
--   MovementLane: strip x 505..535, z -340..-200 with 10-stud floor markers; Ledge (520, 3, -250) 10 x 6 x 10 (falls)
-- Bots are REACT1 copies (the accepted balanced body bot: BodyModel -> BodyState / reactions / blood); the MP7 test
-- server module re-spawns them fresh (ServerScriptService.MP7Test.Run). Everything else is anchored.

local ServerStorage = game:GetService("ServerStorage")

local old = workspace:FindFirstChild("MP7Test")
if old then
	old:Destroy()
end
local root = Instance.new("Folder")
root.Name = "MP7Test"

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

local F = Vector3.new(450, 0, -330)
local lane = Instance.new("Folder")
lane.Name = "FiringLane"
lane.Parent = root
part("FiringPoint", Vector3.new(6, 0.2, 6), CFrame.new(F + Vector3.new(0, 0.1, 0)), Color3.fromRGB(60, 62, 66), nil, lane)
	:SetAttribute("MP7Role", "FiringPoint")

local pen = part("PenWall", Vector3.new(6, 5, 1), CFrame.new(440, 2.5, -306), Color3.fromRGB(196, 170, 120), Enum.Material.WoodPlanks, lane)
pen:SetAttribute("BallisticSurface", "Penetrable")
pen:SetAttribute("MP7Role", "PenetrableWall")
local solid = part("SolidWall", Vector3.new(6, 5, 1), CFrame.new(462, 2.5, -306), Color3.fromRGB(120, 120, 118), Enum.Material.Concrete, lane)
solid:SetAttribute("MP7Role", "NonPenetrableWall")
local board = part("WallTarget", Vector3.new(8, 10, 1), CFrame.new(430, 5, -270), Color3.fromRGB(235, 235, 235), nil, lane)
board:SetAttribute("MP7Role", "WallTarget")

local bots = Instance.new("Folder")
bots.Name = "Bots"
bots.Parent = root
local spots = Instance.new("Folder")
spots.Name = "BotSpots"
spots.Parent = root
local BOTS = {
	{ "MP7_CLOSE", Vector3.new(450, 3, -320) },
	{ "MP7_MEDIUM", Vector3.new(454, 3, -280) },
	{ "MP7_DISTANT", Vector3.new(450, 3, -180) },
	{ "MP7_BEHIND_PEN", Vector3.new(440, 3, -302) },
	{ "MP7_BEHIND_SOLID", Vector3.new(462, 3, -302) },
}
local template = ServerStorage:WaitForChild("HitReactionTemplates"):WaitForChild("REACT1")
for _, b in BOTS do
	local spot = part(b[1] .. "_Spot", Vector3.new(2, 0.1, 2), CFrame.new(b[2].X, 0.05, b[2].Z), Color3.fromRGB(90, 90, 96), nil, spots)
	spot.CanCollide = false
	spot:SetAttribute("MP7Role", "BotSpot")
	local bot = template:Clone()
	bot.Name = b[1]
	bot:PivotTo(CFrame.new(b[2])) -- facing -Z, towards the firing point (as in the optics range)
	bot.Parent = bots
end

local reload = Instance.new("Folder")
reload.Name = "ReloadLane"
reload.Parent = root
part("ReloadPoint", Vector3.new(6, 0.2, 6), CFrame.new(480, 0.1, -330), Color3.fromRGB(70, 66, 60), nil, reload)
	:SetAttribute("MP7Role", "ReloadPoint")

local move = Instance.new("Folder")
move.Name = "MovementLane"
move.Parent = root
part("MoveStart", Vector3.new(6, 0.2, 6), CFrame.new(520, 0.1, -335), Color3.fromRGB(60, 70, 62), nil, move)
	:SetAttribute("MP7Role", "MoveStart")
for z = -330, -200, 10 do
	local m = part(string.format("Marker%d", -z), Vector3.new(30, 0.05, 0.3), CFrame.new(520, 0.025, z), Color3.fromRGB(230, 170, 30), nil, move)
	m.CanCollide = false
end
part("Ledge", Vector3.new(10, 6, 10), CFrame.new(520, 3, -250), Color3.fromRGB(110, 110, 118), Enum.Material.Concrete, move)
	:SetAttribute("MP7Role", "Ledge")

root.Parent = workspace
local n = 0
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then
		n += 1
	end
end
return "MP7Test built: " .. n .. " parts"
