--!strict
-- Focused AI combat test, client side (Studio only; delete the AITest folders to remove it). The player's own character
-- is the moving target, and the player's real M4 (production controller) is what shoots a bot down. The forged inputs
-- below must change nothing on the server; everything is checked there (ServerScriptService.AITest.Run + AIDebug).
--   Run({ stand = { at = Vector3, face = Vector3 } })            feet at `at`, facing the point `face`
--   Run({ path = { { at, face, hold }, ... } })                  stand at each spot for `hold` s; returns the moments
--   Run({ shootBot = { bot = name, at = Vector3, max = n } })    M4 bursts at the bot's chest until it is down
--   Run({ security = { bot = name } })                           the ten forged inputs (player stays where it is)
--   Run({ flashes = true })                                      bot muzzle flashes seen by this client

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")

local function weapon(cmd: string, arg: any?): any
	local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("WeaponController")
		:WaitForChild("ProductionWeaponDebug") :: BindableFunction
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function character(): Model
	return player.Character or player.CharacterAdded:Wait()
end

local function stand(at: Vector3, face: Vector3)
	local root = character():WaitForChild("HumanoidRootPart") :: BasePart
	local pos = at + Vector3.new(0, 3, 0)
	local look = Vector3.new(face.X, pos.Y, face.Z)
	for _ = 1, 3 do
		root.CFrame = CFrame.lookAt(pos, look)
		root.AssemblyLinearVelocity = Vector3.zero
		frames(0.05)
	end
end

local function aimAt(point: Vector3)
	local head = character():FindFirstChild("Head") :: BasePart
	local cam = workspace.CurrentCamera
	for _ = 1, 3 do
		local dir = (point - head.Position).Unit
		cam.CFrame = CFrame.lookAt(cam.CFrame.Position, cam.CFrame.Position + dir)
		frames(0.1)
	end
end

local function botModel(name: string): Model
	return workspace:WaitForChild("AITest"):WaitForChild(name) :: Model
end

return function(opts: any): any
	local out: any = {}
	if opts.stand then
		stand(opts.stand.at, opts.stand.face)
		out.at = os.clock()
	elseif opts.path then
		out.moments = {}
		for _, step in opts.path do
			stand(step.at, step.face)
			table.insert(out.moments, os.clock())
			frames(step.hold or 1)
		end
	elseif opts.shootBot then
		local o = opts.shootBot
		weapon("stressed", false)
		weapon("aim", false)
		player:SetAttribute("EquippedWeapon", "M4")
		frames(0.4)
		weapon("refill")
		frames(0.4)
		local m = botModel(o.bot)
		local torso = m:WaitForChild("UpperTorso") :: BasePart
		stand(o.at, torso.Position)
		frames(0.4)
		local fired = 0
		local t0 = os.clock()
		while os.clock() - t0 < 8 and fired < (o.max or 20) do
			if m:GetAttribute("BodyStance") ~= nil and m:GetAttribute("BodyStance") ~= "STANDING" then
				break
			end
			aimAt(torso.Position)
			local before = weapon("state").shotCount
			weapon("trigger", true)
			frames(0.09) -- one round at 770 RPM, then release
			weapon("trigger", false)
			fired += weapon("state").shotCount - before
			frames(0.35)
		end
		out.fired = fired
		out.stance = m:GetAttribute("BodyStance")
		out.phase = m:GetAttribute("BodyPhase")
		frames(1.0)
	elseif opts.security then
		player:SetAttribute("EquippedWeapon", "M4") -- so forged WeaponFire calls reach the shot checks
		frames(0.4)
		local m = botModel(opts.security.bot)
		local head = m:WaitForChild("Head") :: BasePart
		local root = m:WaitForChild("HumanoidRootPart") :: BasePart
		local WeaponFire = Remotes:WaitForChild("WeaponFire") :: RemoteEvent
		local WeaponCommand = Remotes:WaitForChild("WeaponCommand") :: RemoteEvent
		local BodyInteract = Remotes:WaitForChild("BodyInteract") :: RemoteEvent
		local myHead = character():WaitForChild("Head") :: BasePart
		local sent = {}
		-- 1 force fire
		m:SetAttribute("AIState", "FIRE")
		WeaponCommand:FireServer("BotFire", m)
		WeaponCommand:FireServer("AIFire", m, true)
		table.insert(sent, "1 force fire: AIState=FIRE locally, BotFire / AIFire commands")
		-- 2 choose the target
		m:SetAttribute("AITarget", player.Name)
		WeaponCommand:FireServer("AITarget", m, character())
		table.insert(sent, "2 choose target: AITarget locally, AITarget command")
		-- 3 set the aim
		m:SetAttribute("BodyFacingYaw", 0)
		root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(90), 0)
		WeaponCommand:FireServer("AIAim", m, Vector3.new(1, 0, 0))
		table.insert(sent, "3 set aim: BodyFacingYaw locally, root turned locally, AIAim command")
		-- 4 set the shot origin: a player shot claiming to start at the bot's head
		WeaponFire:FireServer("M4", head.Position, (myHead.Position - head.Position).Unit)
		table.insert(sent, "4 shot origin at the bot's head (player shot)")
		-- 5 set the shot direction for the bot
		WeaponCommand:FireServer("AIDirection", m, (myHead.Position - head.Position).Unit)
		m:SetAttribute("AIAim", Vector3.new(0, 0, 1))
		table.insert(sent, "5 shot direction: AIDirection command, AIAim attribute")
		-- 6 set a hit position (extra WeaponFire arguments naming the bot as hit)
		local torso = m:WaitForChild("UpperTorso") :: BasePart
		WeaponFire:FireServer("M4", myHead.Position, Vector3.new(0, -1, 0.2).Unit, torso.Position, torso, "UpperTorso")
		table.insert(sent, "6 hit position: forged WeaponFire with hit point / part on the bot, aimed at the floor")
		-- 7 set damage
		WeaponFire:FireServer("M4", myHead.Position, Vector3.new(0, -1, 0.2).Unit, torso, 10000)
		m:SetAttribute("BodyLife", 0)
		m:SetAttribute("BodyStrength", 0)
		table.insert(sent, "7 damage: forged WeaponFire with damage 10000; BodyLife / BodyStrength 0 locally")
		-- 8 force a reload
		m:SetAttribute("AIState", "RELOAD")
		m:SetAttribute("AIReloading", "EmptyRegular")
		m:SetAttribute("AIMag", 0)
		WeaponCommand:FireServer("AIReload", m)
		table.insert(sent, "8 reload: AIState / AIReloading / AIMag locally, AIReload command")
		-- 9 force death
		m:SetAttribute("BodyPhase", "DEAD")
		m:SetAttribute("BodyStance", "DOWN")
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum then
			pcall(function()
				hum.Health = 0
			end)
		end
		BodyInteract:FireServer("Kill", m)
		BodyInteract:FireServer("Drag", m)
		table.insert(sent, "9 death: BodyPhase DEAD / stance DOWN / Health 0 locally, BodyInteract Kill / Drag")
		-- 10 bypass line of sight: the wall removed on this client only
		local wall = workspace.AITest:FindFirstChild("WallA")
		if wall then
			wall.Parent = nil
		end
		table.insert(sent, "10 line of sight: WallA removed locally")
		frames(3)
		out.localWallGone = workspace.AITest:FindFirstChild("WallA") == nil
		out.sent = sent
		if wall then
			wall.Parent = workspace.AITest
		end
	elseif opts.flashes then
		local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("AI"):WaitForChild("BotMuzzle")
			:WaitForChild("BotMuzzleDebug") :: BindableFunction
		out = hook:Invoke()
	end
	out.clock = os.clock()
	return out
end
