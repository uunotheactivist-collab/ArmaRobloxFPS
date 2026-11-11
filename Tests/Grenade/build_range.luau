-- Grenade test range (Edit mode, run once; saved in the place as Workspace.GrenadeTest). Clear of the other ranges
-- (BallisticTest x -200…-150, BodyStateTest x -270…-320, HitReactionTest x -350…-420).
--   PadOpen  (-500, 0.1, 160)  stand here: +Z is open ground; -Z faces WallA 20 studs away (wall / floor bounces)
--   WallA    (-500, 5, 140)    24 × 10 × 1, unmarked = NonPenetrable (fragments stop)
--   Room     centre (-540, 0, 150): 10 × 10 inside, walls 7 high, no roof; PadRoom in the middle (confined space)
-- Bodies: the HitReactionTest bots REACT1–6 (z 110, shooter pads z 125) and BodyStateTest BODY1–6.
local old = workspace:FindFirstChild("GrenadeTest")
if old then
	old:Destroy()
end
local f = Instance.new("Folder")
f.Name = "GrenadeTest"
f.Parent = workspace
local function block(name: string, size: Vector3, pos: Vector3, color: Color3, parent: Instance?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or f
	return p
end
local grey = Color3.fromRGB(150, 150, 155)
local pad = Color3.fromRGB(90, 200, 120)
block("PadOpen", Vector3.new(4, 0.2, 4), Vector3.new(-500, 0.1, 160), pad).CanCollide = false
block("WallA", Vector3.new(24, 10, 1), Vector3.new(-500, 5, 140), grey)
local room = Instance.new("Folder")
room.Name = "Room"
room.Parent = f
local c = Vector3.new(-540, 0, 150)
block("WallN", Vector3.new(12, 7, 1), c + Vector3.new(0, 3.5, -5.5), grey, room)
block("WallS", Vector3.new(12, 7, 1), c + Vector3.new(0, 3.5, 5.5), grey, room)
block("WallW", Vector3.new(1, 7, 10), c + Vector3.new(-5.5, 3.5, 0), grey, room)
block("WallE", Vector3.new(1, 7, 10), c + Vector3.new(5.5, 3.5, 0), grey, room)
block("PadRoom", Vector3.new(3, 0.2, 3), c + Vector3.new(0, 0.1, 2), pad, room).CanCollide = false
return "built"
