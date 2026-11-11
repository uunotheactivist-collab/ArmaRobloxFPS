--!strict
-- First-person throw presentation (client only, presentation). Keyed to the normal clip's overhand throws
-- (ReferenceAnalysis/GrenadeFidelity C3, C4, M9, M10). With L = the label's first frame:
--   L-1 arm tip from the top, L a big block arm over the top left, L+1 the arm reaching forward with the grenade at its
--   tip (release; the lever comes off), L+2 the arm sweeping down, L+3 lower left, L+4 only its tip at the bottom
--   centre, L+5 gone.
-- Here the release is the server's (Config.Grenade.Throw.ReleaseSeconds after the press), so the keys sit at
-- release - 2 / 30 ... release + 4 / 30. The arm is the viewmodels' block arm (0.39 x 0.39 x 2.68 studs, white); poses
-- are camera-space (x right, y up, z back), each a hand-end point and an elbow → hand direction, solved by eye from
-- the frames (INFERRED depth). The lever is a small client-only part that leaves at release, up and to the right,
-- and falls (C4). The held weapon is lowered by Client.FirstPerson.WeaponLowering (first-person fidelity pass).
-- In flight the grenade is GrenadePrediction's proxy (from the frame the in-hand grenade goes), then the server's body.
-- Studio test hooks: freeze(t), leverInfo(). stop(): death ends the swing at once (no lever, nothing in hand).

local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Grenade"))

local Presentation = {}

local F = 1 / 30
local ARM_SIZE = Vector3.new(0.392857, 0.392857, 2.67857) -- the viewmodels' block arm
local ARM_COLOR = Color3.fromRGB(235, 235, 235)
-- (time from release, hand end, elbow → hand direction): measured screen path, inferred depth
local KEYS: { { number | Vector3 } } = {
	{ -2 * F, Vector3.new(-0.42, 0.65, -0.8), Vector3.new(0.2, 0.9, -0.4) }, -- L-1: tip from the top
	{ -1 * F, Vector3.new(-0.37, 0.8, -1.0), Vector3.new(0.35, 0.75, -0.55) }, -- L: over the top left
	{ 0, Vector3.new(-0.33, 0.52, -1.4), Vector3.new(0.55, 0.45, -0.7) }, -- L+1: reaching forward, release
	{ 1 * F, Vector3.new(-0.1, -0.28, -1.3), Vector3.new(0.75, 0.05, -0.66) }, -- L+2: sweeping down
	{ 2 * F, Vector3.new(-0.09, -0.43, -1.1), Vector3.new(0.8, -0.1, -0.6) }, -- L+3: lower left
	{ 3 * F, Vector3.new(-0.14, -0.6, -0.9), Vector3.new(0.5, -0.6, -0.62) }, -- L+4: tip at the bottom centre
	{ 4 * F, Vector3.new(-0.1, -1.0, -0.7), Vector3.new(0.4, -0.7, -0.5) }, -- L+5: gone below
}
local GRENADE_IN_HAND = Vector3.new(-0.05, 0.12, 0) -- from the hand end: on the arm's top face near the tip (M9)
local LEVER = { Size = Vector3.new(0.05, 0.02, 0.18), Color = Color3.fromRGB(70, 72, 74), Life = 1.3, Gravity = 35,
	Kick = Vector3.new(5, 7, 0), Carry = 0.35 } -- camera-space kick (right, up) and the share of the grenade's velocity

local model: Model? = nil
local grenade: BasePart? = nil
local arm: BasePart? = nil
local conn: RBXScriptConnection? = nil
local startedAt = 0
local frozenAt: number? = nil
local leverDone = true
local launchDir = Vector3.new(0, 0, -1)
Presentation.Count = 0
local levers: { { Part: BasePart, Vel: Vector3, Spin: Vector3, Born: number } } = {}
local leverConn: RBXScriptConnection? = nil
local leversSpawned = 0

local function part(name: string, size: Vector3, color: Color3, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	return p
end

local function build()
	if model and model.Parent then
		return
	end
	local m = Instance.new("Model")
	m.Name = "GrenadeThrowView"
	local g = part("Grenade", Vector3.new(0.16, 0.16, 0.16), Config.Body.Color, Enum.PartType.Ball)
	g.Parent = m
	local a = part("Arm", ARM_SIZE, ARM_COLOR)
	a.Parent = m
	m.Parent = workspace.CurrentCamera
	model, grenade, arm = m, g, a
end

-- hand end and direction at time u from release (linear between keys)
local function pose(u: number): (Vector3?, Vector3?)
	if u < (KEYS[1][1] :: number) or u > (KEYS[#KEYS][1] :: number) then
		return nil, nil
	end
	for i = 1, #KEYS - 1 do
		local a, b = KEYS[i], KEYS[i + 1]
		local ta, tb = a[1] :: number, b[1] :: number
		if u >= ta and u <= tb then
			local k = (u - ta) / (tb - ta)
			local h = (a[2] :: Vector3):Lerp(b[2] :: Vector3, k)
			local d = (a[3] :: Vector3).Unit:Lerp((b[3] :: Vector3).Unit, k).Unit
			return h, d
		end
	end
	return nil, nil
end

local function stepLevers()
	local now = os.clock()
	local dt = 1 / 60
	for i = #levers, 1, -1 do
		local l = levers[i]
		if now - l.Born > LEVER.Life or not l.Part.Parent then
			l.Part:Destroy()
			table.remove(levers, i)
		else
			l.Vel += Vector3.new(0, -LEVER.Gravity * dt, 0)
			local p = l.Part.Position + l.Vel * dt
			l.Part.CFrame = CFrame.new(p) * (l.Part.CFrame - l.Part.Position) * CFrame.fromAxisAngle(l.Spin.Unit, l.Spin.Magnitude * dt)
		end
	end
	if #levers == 0 and leverConn then
		leverConn:Disconnect()
		leverConn = nil
	end
end

local function spawnLever(at: Vector3, cam: CFrame)
	local l = part("GrenadeLever", LEVER.Size, LEVER.Color)
	l.Material = Enum.Material.Metal
	l.Transparency = 0
	l.CFrame = CFrame.new(at) * cam.Rotation * CFrame.Angles(0.4, 0.2, 0)
	l.Parent = workspace.CurrentCamera
	local vel = launchDir * Config.Throw.Speed * LEVER.Carry + cam:VectorToWorldSpace(LEVER.Kick)
	table.insert(levers, { Part = l, Vel = vel, Spin = Vector3.new(14, 22, 9), Born = os.clock() })
	leversSpawned += 1
	if not leverConn then
		leverConn = RunService.RenderStepped:Connect(stepLevers)
	end
end

local function frame()
	local t = if frozenAt then frozenAt else os.clock() - startedAt
	local u = t - Config.Throw.ReleaseSeconds
	local cam = workspace.CurrentCamera.CFrame
	local g, a = grenade :: BasePart, arm :: BasePart
	local h, d = pose(u)
	if h and d then
		a.Transparency = 0
		local centre = h - d * (ARM_SIZE.Z / 2)
		a.CFrame = cam * CFrame.lookAt(centre, centre + d)
		-- at the tip at L+1 (the release, u = 0), in flight from L+2 (C3). First-person fidelity pass: it leaves the hand at
		-- the release itself (was: rode the hand down until L+2, a frame the 30-fps reference never shows at 60 fps); from
		-- then GrenadePrediction draws it in flight, from the same point
		if u <= 0 then
			g.Transparency = 0
			g.CFrame = cam * CFrame.new(h + GRENADE_IN_HAND)
		else
			g.Transparency = 1 -- released: GrenadePrediction's proxy, then the server's body
			if not leverDone and not frozenAt then
				leverDone = true
				spawnLever((cam * CFrame.new(h + GRENADE_IN_HAND)).Position, cam)
			end
		end
	else
		a.Transparency, g.Transparency = 1, 1
	end
	if not frozenAt and t > Config.Throw.Seconds then
		a.Transparency, g.Transparency = 1, 1
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end
end

-- The launch direction for the cosmetic lever: the server's rule (Server.Grenade.Throw.direction), from the camera.
local function direction(look: Vector3): Vector3
	local T = Config.Throw
	local f = CFrame.lookAt(Vector3.zero, look)
	return (f * CFrame.Angles(0, math.rad(T.YawLeftDeg or 0), 0) * CFrame.Angles(math.rad(T.LiftDeg or 0), 0, 0)).LookVector
end

function Presentation.play(at: number?)
	build()
	startedAt = at or os.clock() -- the press time, shared with GrenadePrediction (the same frame hands over)
	frozenAt = nil
	leverDone = false
	launchDir = direction(workspace.CurrentCamera.CFrame.LookVector)
	Presentation.Count += 1
	if not conn then
		conn = RunService.RenderStepped:Connect(frame)
	end
end

function Presentation.busy(): boolean
	return conn ~= nil and frozenAt == nil
end

-- Death during the throw: the server releases nothing then; end the swing now (no lever, no grenade in hand).
function Presentation.stop()
	if frozenAt then
		return
	end
	leverDone = true
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if arm then
		(arm :: BasePart).Transparency = 1
	end
	if grenade then
		(grenade :: BasePart).Transparency = 1
	end
end

-- Studio test hook: hold the presentation at t seconds after the press (nil releases it).
function Presentation.freeze(t: number?): any
	build()
	frozenAt = t
	if t then
		if not conn then
			conn = RunService.RenderStepped:Connect(frame)
		end
	else
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if arm then
			(arm :: BasePart).Transparency = 1
		end
		if grenade then
			(grenade :: BasePart).Transparency = 1
		end
	end
	return { frozenAt = frozenAt }
end

function Presentation.leverInfo(): any
	return { Spawned = leversSpawned, Active = #levers }
end

return Presentation
