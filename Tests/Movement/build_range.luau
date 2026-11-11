-- Builds Workspace.MovementTest (Edit mode, run once from the command bar or execute_luau) and the remote
-- ReplicatedStorage.Shared.Remotes.MovementIntent. Isolated from the other ranges: x 200..301, z -140..-48 (the
-- AI / grenade / combat ranges are at x <= 12; grenade fragments reach x -250 at most).
-- Lanes run along +X from the start pad at (210, 0, -100). Floor = the baseplate top (y 0).
--   z -130 SpeedLane   flat 80-stud lane, markers every 10 studs (walk speed, acceleration, stops)
--   z -115 Slope       a 4-stud wedge over 7 studs (29.7 deg) to a flat top (4 high), then a 4-stud drop
--   z -100 Stairs      8 steps of 0.75 x 1.5 to a ledge 6 high, then a 6-stud drop to the LandingPad (fall / landing)
--   z  -85 Obstacles   a 0.6 curb (stepped over) and a 2.0 block (blocks walking)
--   z  -70 Doorway     a wall with a 4 x 7 opening
--   z  -55 CrouchTunnel 4 wide, ceiling underside 3.2 (standing blocked, crouched passes)
--   x  300 Wall        the end wall across every lane

local ensure = function(parent, class, name)
	local x = parent:FindFirstChild(name)
	if not x then
		x = Instance.new(class)
		x.Name = name
		x.Parent = parent
	end
	return x
end
ensure(game.ReplicatedStorage.Shared.Remotes, "RemoteEvent", "MovementIntent")

local old = workspace:FindFirstChild("MovementTest")
if old then
	old:Destroy()
end
local f = Instance.new("Folder")
f.Name = "MovementTest"

local GREY = Color3.fromRGB(163, 162, 165)
local DARK = Color3.fromRGB(99, 95, 98)
local MARK = Color3.fromRGB(196, 170, 60)

local function part(name: string, size: Vector3, cf: CFrame, color: Color3?, solid: boolean?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color or GREY
	p.Material = Enum.Material.Concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if solid == false then
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end
	p.Parent = f
	return p
end

-- markings (not collidable, not queried: they never touch movement or rays)
part("Start", Vector3.new(6, 0.05, 6), CFrame.new(210, 0.025, -100), MARK, false)
part("SpeedLane", Vector3.new(80, 0.05, 2), CFrame.new(250, 0.025, -130), DARK, false)
for i = 0, 8 do
	part("Mark" .. (i * 10), Vector3.new(0.3, 0.06, 3), CFrame.new(210 + i * 10, 0.03, -130), MARK, false)
end

-- slope lane
local wedge = Instance.new("WedgePart")
wedge.Name = "Slope"
wedge.Anchored = true
wedge.Size = Vector3.new(6, 4, 7) -- X = width, Y = rise, Z = run
-- a WedgePart rises toward its -Z... turned so the rise goes toward +X
wedge.CFrame = CFrame.new(233.5, 2, -115) * CFrame.Angles(0, math.rad(90), 0)
wedge.Color = GREY
wedge.Material = Enum.Material.Concrete
wedge.Parent = f
part("SlopeTop", Vector3.new(10, 4, 6), CFrame.new(242, 2, -115))

-- stairs lane: 8 steps 0.75 high, 1.5 deep, 6 wide, then the ledge (6 high) and the landing pad
for i = 1, 8 do
	local h = i * 0.75
	part("Step" .. i, Vector3.new(1.5, h, 6), CFrame.new(229.25 + i * 1.5, h / 2, -100))
end
part("Ledge", Vector3.new(8, 6, 6), CFrame.new(245.5, 3, -100))
part("LandingPad", Vector3.new(10, 0.05, 6), CFrame.new(255.5, 0.025, -100), MARK, false)

-- obstacles lane
part("Curb", Vector3.new(1, 0.6, 6), CFrame.new(230.5, 0.3, -85))
part("LowBlock", Vector3.new(2, 2, 6), CFrame.new(246, 1, -85))

-- doorway lane: wall across z -80..-60 at x 240, opening 4 wide x 7 high centred on z -70
part("DoorLeft", Vector3.new(1, 10, 8), CFrame.new(240, 5, -76), DARK)
part("DoorRight", Vector3.new(1, 10, 8), CFrame.new(240, 5, -64), DARK)
part("DoorLintel", Vector3.new(1, 3, 4), CFrame.new(240, 8.5, -70), DARK)

-- crouch tunnel: inner width 4 (z -57..-53), 12 long (x 230..242), ceiling underside 3.2
part("TunnelLeft", Vector3.new(12, 6, 1), CFrame.new(236, 3, -57.5), DARK)
part("TunnelRight", Vector3.new(12, 6, 1), CFrame.new(236, 3, -52.5), DARK)
part("TunnelCeiling", Vector3.new(12, 0.5, 6), CFrame.new(236, 3.45, -55), DARK)

-- end wall
part("Wall", Vector3.new(1, 12, 92), CFrame.new(300.5, 6, -94), DARK)

f.Parent = workspace
return #f:GetChildren()
