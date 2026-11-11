--!strict
-- Focused hit-reaction / active-ragdoll test, client side (Studio only; delete the HitReactionTest folders to remove
-- it). It fires REAL shots through the production pipeline at the R15 test bots REACT1–6
-- (Workspace.HitReactionTest). Hit, state and reaction are all decided on the server; the server half
-- (ServerScriptService.HitReactionTest.Run) checks them.
--   Run({ weapon = "M4" })   the standard plan
--   Run({ tamper = true })   client-side attempts to force a state / ragdoll on REACT1 (must change nothing)

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

-- Aim points in the part's own frame (front face toward the shooter is local -Z). UpperTorso: chest; its top 0.3
-- studs (local Y ≥ 0.2) is the throat zone. LowerTorso: abdomen.
local POINTS: { [string]: { any } } = {
	head = { "Head", Vector3.new(0, 0, -0.5) },
	throat = { "UpperTorso", Vector3.new(0, 0.35, -0.5) },
	chest = { "UpperTorso", Vector3.new(0, -0.15, -0.5) },
	abdomen = { "LowerTorso", Vector3.new(0, 0, -0.5) },
	rightarm = { "RightUpperArm", Vector3.new(0, 0, -0.5) },
	leftleg = { "LeftUpperLeg", Vector3.new(0, 0, -0.5) },
	rightleg = { "RightUpperLeg", Vector3.new(0, 0, -0.5) },
	center = { "UpperTorso", Vector3.zero },
}

local function botFolder(i: number): Instance
	return workspace:WaitForChild("HitReactionTest"):WaitForChild("Bot" .. i)
end

local function body(i: number): Model
	return botFolder(i):WaitForChild("REACT" .. i) :: Model
end

local function standAt(i: number)
	local spot = (botFolder(i):WaitForChild("ShooterSpot") :: BasePart).Position
	local look = Vector3.new(spot.X, spot.Y, spot.Z - 15)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	assert(root, "no character")
	root.CFrame = CFrame.lookAt(spot + Vector3.new(0, 3, 0), Vector3.new(look.X, spot.Y + 3, look.Z))
	root.AssemblyLinearVelocity = Vector3.zero
	frames(0.6)
end

-- Aim so that the ray from the HEAD (where the server traces from) along the camera's look reaches the point.
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
	{ bot = 4, at = "chest", n = 3 },
	{ bot = 5, at = "head" },
	{ bot = 6, at = "leftleg" },
	{ bot = 6, at = "rightleg" },
	{ bot = 6, at = "center", wait = 2.5 },
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

	if opts.tamper then
		-- the client tries to declare REACT1 down / dead and to push it over: local writes only
		local m = body(1)
		m:SetAttribute("BodyStance", "DOWN")
		m:SetAttribute("BodyPhase", "DEAD")
		m:SetAttribute("BodyBehaviour", "LIMP")
		local upper = m:FindFirstChild("UpperTorso") :: BasePart
		pcall(function()
			upper.AssemblyLinearVelocity = Vector3.new(0, 0, -40)
		end)
		local Remotes = ReplicatedStorage.Shared.Remotes
		;(Remotes.WeaponCommand :: RemoteEvent):FireServer("Ragdoll", m)
		;(Remotes.WeaponCommand :: RemoteEvent):FireServer("SetBodyState", { body = m, phase = "DEAD" })
		frames(1.0)
		out.localStance = m:GetAttribute("BodyStance")
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
		table.insert(out.shots, `REACT{s.bot} {s.at} ×{n}`)
		frames(0.45)
	end
	frames(1.0)
	return out
end
