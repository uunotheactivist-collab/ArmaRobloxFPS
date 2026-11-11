-- AI combat slice: builds ServerStorage.AITemplates.AIBOT and Workspace.AITest (run once in Edit mode; idempotent).
-- AIBOT = a copy of the accepted R15-joint test bot ServerStorage.HitReactionTemplates.REACT1 (BodyState body,
-- ActiveRagdoll presentation, unchanged) with the arms posed to hold a rifle (its rest pose, so HitReaction's flinch
-- breaks the aim pose and ActiveRagdoll goes down holding it) and the bot attributes AIBot / AITeam.
-- AITest is far from every other range (x -700 .. -800; the nearest, GrenadeTest, is 160+ studs away; detection range
-- is 120), so no bot can see a test running elsewhere.
--   BOT1 at (-800, 3, 100) facing +X, toward the spawn side (team Red): the demo bot, off the test lanes. The AI tests
--   disable it and use their own bots on BotPad.
--   BotPad     (-740, 0, 150): where test bots stand, facing +Z
--   SpotOpen   (-740, 0, 180): 30 studs in front, in the open
--   SpotCover  (-760, 0, 180): behind WallA (seen from BOT1)
--   SpotSide   (-780, 0, 150): 40 studs to the bot's right side (outside a 120 deg field of view)
--   SpotFar    (-740, 0, 290): 140 studs in front (out of the 120-stud range)
--   SpotFriend (-735, 0, 170): a friendly (Red) target stands here in the friend / foe test

local ServerStorage = game:GetService("ServerStorage")

-- template
local folder = ServerStorage:FindFirstChild("AITemplates") or Instance.new("Folder")
folder.Name = "AITemplates"
folder.Parent = ServerStorage
local old = folder:FindFirstChild("AIBOT")
if old then
	old:Destroy()
end
local bot = ServerStorage.HitReactionTemplates.REACT1:Clone()
bot.Name = "AIBOT"
local function motor(name: string): Motor6D
	for _, d in bot:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == name then
			return d
		end
	end
	error("no motor " .. name)
end
-- aim pose (rest pose of this template): right arm down-forward with the forearm raised to the rifle, left arm
-- reaching forward across the chest toward the handguard (this rig's 3-stud shoulders can't reach it)
motor("RightShoulder").C0 = CFrame.new(1.5, 0.4, 0) * CFrame.Angles(0, math.rad(30), 0) * CFrame.Angles(math.rad(55), 0, 0)
motor("RightElbow").C0 = CFrame.new(0, -0.5, 0) * CFrame.Angles(math.rad(40), 0, 0)
motor("LeftShoulder").C0 = CFrame.new(-1.5, 0.4, 0) * CFrame.Angles(0, math.rad(-47), 0) * CFrame.Angles(math.rad(82), 0, 0)
motor("LeftElbow").C0 = CFrame.new(0, -0.5, 0) * CFrame.Angles(math.rad(10), 0, 0)
bot:SetAttribute("AIBot", true)
bot:SetAttribute("AITeam", "Red")
bot.Parent = folder

-- range
local range = workspace:FindFirstChild("AITest")
if range then
	range:Destroy()
end
range = Instance.new("Folder")
range.Name = "AITest"
local function block(name: string, size: Vector3, pos: Vector3, color: Color3, collide: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Anchored = true
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = range
	return p
end
local pad = Color3.fromRGB(90, 110, 140)
block("BotPad", Vector3.new(4, 0.1, 4), Vector3.new(-740, 0.05, 150), Color3.fromRGB(150, 60, 60), false)
block("SpotOpen", Vector3.new(4, 0.1, 4), Vector3.new(-740, 0.05, 180), pad, false)
block("SpotCover", Vector3.new(4, 0.1, 4), Vector3.new(-760, 0.05, 180), pad, false)
block("SpotSide", Vector3.new(4, 0.1, 4), Vector3.new(-780, 0.05, 150), pad, false)
block("SpotFar", Vector3.new(4, 0.1, 4), Vector3.new(-740, 0.05, 290), pad, false)
block("SpotFriend", Vector3.new(4, 0.1, 4), Vector3.new(-735, 0.05, 170), Color3.fromRGB(150, 60, 60), false)
block("WallA", Vector3.new(8, 8, 1), Vector3.new(-752, 4, 170), Color3.fromRGB(163, 162, 165), true)
block("Backstop", Vector3.new(60, 14, 2), Vector3.new(-740, 7, 305), Color3.fromRGB(120, 120, 120), true)
block("Bot1Pad", Vector3.new(4, 0.1, 4), Vector3.new(-800, 0.05, 100), Color3.fromRGB(150, 60, 60), false)
local b1 = bot:Clone()
b1.Name = "BOT1"
b1:PivotTo(CFrame.new(-800, 3, 100) * CFrame.Angles(0, -math.pi / 2, 0))
b1.Parent = range
range.Parent = workspace
return "AITest built"
