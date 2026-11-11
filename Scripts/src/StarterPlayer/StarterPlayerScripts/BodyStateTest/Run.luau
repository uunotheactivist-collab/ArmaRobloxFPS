--!strict
-- Focused body-state test, client side (Studio only; delete the BodyStateTest folders to remove it).
-- Fires REAL shots through the production pipeline: client controller → WeaponFire → Server.WeaponServer →
-- Server.Ballistics → Server.BodyState. The client only stands on a bot's spot, aims at a point on the bot and pulls
-- the trigger. Location, wound and state are decided on the server (ServerScriptService.BodyStateTest.Run checks
-- them).
--   Run({ weapon = "M4" })    the standard plan on BODY1–BODY6
--   Run({ forged = true })    forged client requests against BODY1 (must change nothing but a normal leg hit)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("WeaponController")
	:WaitForChild("ProductionWeaponDebug") :: BindableFunction

local function call(cmd: string, arg: any?): any
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

-- Aim points in the part's own frame (front face toward the shooter is local -Z); "center" = the part's centre.
local POINTS: { [string]: { any } } = {
	head = { "Head", Vector3.new(0, 0, -0.5) },
	throat = { "Torso", Vector3.new(0, 0.85, -0.5) },
	chest = { "Torso", Vector3.new(0, 0.4, -0.5) },
	abdomen = { "Torso", Vector3.new(0, -0.5, -0.5) },
	rightarm = { "Right Arm", Vector3.new(0, 0, -0.5) },
	leftarm = { "Left Arm", Vector3.new(0, 0, -0.5) },
	rightleg = { "Right Leg", Vector3.new(0, 0, -0.5) },
	leftleg = { "Left Leg", Vector3.new(0, 0, -0.5) },
	center = { "Torso", Vector3.zero },
}

local function botFolder(i: number): Instance
	return workspace:WaitForChild("BodyStateTest"):WaitForChild("Bot" .. i)
end

local function body(i: number): Model
	return botFolder(i):WaitForChild("BODY" .. i) :: Model
end

local function standAt(i: number)
	local spot = (botFolder(i):WaitForChild("ShooterSpot") :: BasePart).Position
	local look = body(i):GetPivot().Position
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	assert(root, "no character")
	root.CFrame = CFrame.lookAt(spot + Vector3.new(0, 3, 0), Vector3.new(look.X, spot.Y + 3, look.Z))
	root.AssemblyLinearVelocity = Vector3.zero
	frames(0.6) -- the server validates the shot origin against its own copy of the head
end

-- Point the camera so that the ray from the HEAD (where the server traces from) along the camera's look direction
-- reaches the point.
local function aimAt(point: Vector3)
	local head = (player.Character :: Model):FindFirstChild("Head") :: BasePart
	local cam = workspace.CurrentCamera
	for _ = 1, 2 do
		local dir = (point - head.Position).Unit
		cam.CFrame = CFrame.lookAt(cam.CFrame.Position, cam.CFrame.Position + dir)
		frames(0.12)
	end
end

local function pointOn(i: number, name: string): Vector3
	local spec = POINTS[name]
	local part = body(i):FindFirstChild(spec[1]) :: BasePart
	return part.CFrame:PointToWorldSpace(spec[2])
end

local function fire(n: number): number
	local before = call("state").shotCount
	call("trigger", true)
	local t0 = os.clock()
	while call("state").shotCount < before + n and os.clock() - t0 < 2 do
		RunService.RenderStepped:Wait()
	end
	call("trigger", false)
	return call("state").shotCount - before
end

local PLAN = {
	{ bot = 1, at = "rightarm" },
	{ bot = 2, at = "abdomen" },
	{ bot = 3, at = "throat" },
	{ bot = 4, at = "chest", n = 3 }, -- one short burst (strength recovery would outpace single aimed shots)
	{ bot = 5, at = "head" },
	{ bot = 6, at = "leftleg" },
	{ bot = 6, at = "rightleg" },
	{ bot = 6, at = "center", wait = 2.0 }, -- by now BODY6 is down: a hit on a dying body
}

return function(opts: any): any
	local out = { fired = 0, shots = {} }
	call("stressed", false)
	call("aim", false)
	if opts.weapon then
		player:SetAttribute("EquippedWeapon", opts.weapon)
		frames(0.4)
	end
	call("refill")
	frames(0.6)

	if opts.forged then
		-- 1) a client-side attribute write: stays local, the server never sees it
		local m = body(1)
		m:SetAttribute("BodyPhase", "DEAD")
		m:SetAttribute("BodyLife", 0)
		out.localAttributeAfterWrite = m:GetAttribute("BodyPhase")
		-- 2) a command asking the server to set a body state: no such command exists (ignored)
		local Remotes = ReplicatedStorage.Shared.Remotes
		;(Remotes.WeaponCommand :: RemoteEvent):FireServer("SetBodyState", { body = m, phase = "DEAD", wound = "Brain" })
		-- 3) a real shot at BODY1's left leg with forged hit claims as extra arguments (head, Brain, DEAD, the head part)
		standAt(1)
		local head = (player.Character :: Model):FindFirstChild("Head") :: BasePart
		local target = pointOn(1, "leftleg")
		aimAt(target)
		local dir = (target - head.Position).Unit
		;(Remotes.WeaponFire :: RemoteEvent):FireServer(player:GetAttribute("EquippedWeapon"), head.Position, dir,
			{ Location = "head", Wound = "Brain", Phase = "DEAD" }, (m :: any).Head, "head")
		frames(0.8)
		call("refill") -- the forged shot bypassed the client's ammo prediction
		frames(0.4)
		out.forgedSent = true
		return out
	end

	for _, s in PLAN do
		if s.wait then
			frames(s.wait)
		end
		standAt(s.bot)
		aimAt(pointOn(s.bot, s.at))
		local n = fire(s.n or 1)
		out.fired += n
		table.insert(out.shots, `BODY{s.bot} {s.at} ×{n}`)
		frames(0.45) -- recoil recovers
	end
	frames(1.0)
	return out
end
