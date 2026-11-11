--!strict
-- Focused body-interaction test, client side (Studio only; delete the InteractionTest folders to remove it). Real
-- requests go through the production client (the F menu: BodyInteractionDebug select / press); the fake ones are fired
-- straight at the remotes. Everything is decided and checked on the server (ServerScriptService.InteractionTest.Run).
--   Run({ pulse = i })          stand by REACTi, choose "Check pulse", press F; wait for the server's answer
--   Run({ far = i })            requests from 20 studs away
--   Run({ invalid = true })     requests naming things that are not bodies
--   Run({ interrupt = i })      start a check, walk away after 1.5 s
--   Run({ forge = i })          fake results / states / early completion
--   Run({ localState = i })     write BodyPhase = DEAD locally on REACTi, then check its pulse for real
--   Run({ drag = i, back = n, hold = s })  grab REACTi from the menu, walk back n studs, let go after s more seconds
--   Run({ dragAway = i })       grab, then jump 30 studs away
--   Run({ dragInvalid = true }) drag a standing body, an injured one, an R6 debug-pose body, a far body
--   Run({ tamper = i })         move / fling the body locally, fake drag requests and states

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Interaction")
	:WaitForChild("BodyInteraction"):WaitForChild("BodyInteractionDebug") :: BindableFunction
local Remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
local Request = Remotes:WaitForChild("BodyInteract") :: RemoteEvent
local StateRemote = Remotes:WaitForChild("BodyInteractState") :: RemoteEvent

local function call(cmd: string, arg: any?): any
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function bot(i: number): Model
	return workspace:WaitForChild("HitReactionTest"):WaitForChild("Bot" .. i):WaitForChild("REACT" .. i) :: Model
end

local function root(): BasePart
	return (player.Character :: Model):WaitForChild("HumanoidRootPart") :: BasePart
end

-- Stand `dist` studs from the body's torso on its +Z side (open floor toward the shooter spots), facing it.
local function standBy(m: Model, dist: number)
	local torso = (m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso")) :: BasePart
	local at = Vector3.new(torso.Position.X, 3, torso.Position.Z + dist)
	local r = root()
	r.CFrame = CFrame.lookAt(at, Vector3.new(torso.Position.X, 3, torso.Position.Z))
	r.AssemblyLinearVelocity = Vector3.zero
	frames(0.3)
	local cam = workspace.CurrentCamera
	cam.CFrame = CFrame.lookAt(cam.CFrame.Position, torso.Position)
	frames(0.3)
end

-- The server's messages since `since` (times relative to `since`).
local function messagesSince(since: number): { string }
	local out = {}
	for _, m in call("messages") do
		if m.At >= since then
			table.insert(out, string.format("+%.3f %s %s%s%s%s", m.At - since, tostring(m.Kind), tostring(m.Phase),
				if m.Reason then " (" .. m.Reason .. ")" else "", if m.Text then " " .. m.Text else "",
				if m.Target then " " .. m.Target else ""))
		end
	end
	return out
end

local function waitFor(since: number, phases: { string }, timeout: number): any?
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		for _, m in call("messages") do
			if m.At >= since and table.find(phases, m.Phase) then
				return m
			end
		end
		RunService.RenderStepped:Wait()
	end
	return nil
end

local function menuPress(m: Model, item: number): (number, any)
	standBy(m, 3.5)
	call("refresh")
	call("select", item)
	local view = call("view")
	return call("press"), view
end

return function(opts: any): any
	local out: any = {}
	frames(0.25) -- the server's request spacing (0.2 s) between test calls
	if opts.pulse then
		local m = bot(opts.pulse)
		local t0, before = menuPress(m, 1)
		out.menuBefore = before
		frames(1.5)
		out.menuChecking = call("view")
		local done = waitFor(t0, { "Result", "Interrupted", "Rejected" }, 5)
		frames(0.1)
		out.menuAfter = call("view")
		out.clientSeconds = done and (done.At - t0)
		out.messages = messagesSince(t0)
	elseif opts.far then
		local m = bot(opts.far)
		standBy(m, 20)
		local t0 = os.clock()
		Request:FireServer("PulseCheck", m)
		frames(0.3)
		Request:FireServer("Drag", m)
		frames(0.4)
		out.messages = messagesSince(t0)
	elseif opts.invalid then
		standBy(bot(1), 3.5)
		local t0 = os.clock()
		local lane = workspace:FindFirstChild("BallisticTest")
		local laneTarget = lane and lane:FindFirstChild("Target", true)
		local targets: { any } = { workspace:FindFirstChild("Baseplate"), "REACT1", 42, laneTarget, player.Character, ReplicatedStorage }
		for _, t in targets do
			Request:FireServer("PulseCheck", t)
			frames(0.25)
		end
		Request:FireServer("PulseCheck") -- nothing at all
		frames(0.25)
		Request:FireServer("Drag", player.Character) -- the player's own character
		frames(0.4)
		out.messages = messagesSince(t0)
	elseif opts.interrupt then
		local m = bot(opts.interrupt)
		local t0 = menuPress(m, 1)
		frames(1.5)
		local r = root()
		r.CFrame = r.CFrame + Vector3.new(0, 0, 15)
		r.AssemblyLinearVelocity = Vector3.zero
		frames(2.5)
		out.messages = messagesSince(t0)
		out.menuAfter = call("view")
	elseif opts.forge then
		local m = bot(opts.forge)
		standBy(m, 3.5)
		local t0 = os.clock()
		Request:FireServer("PulseResult", m, "NoPulse") -- a result named by the client
		frames(0.25)
		StateRemote:FireServer({ Kind = "PulseCheck", Phase = "Result", Result = "NoPulse", Target = m }) -- the server's own channel
		frames(0.25)
		Request:FireServer("Complete", m)
		frames(0.25)
		Request:FireServer("SetPulse", m, { Phase = "DEAD" })
		frames(0.25)
		local tStart = os.clock()
		Request:FireServer("PulseCheck", m) -- a real check …
		frames(0.25)
		Request:FireServer("PulseCheck", m) -- … asked again to restart / skip it
		frames(0.25)
		Request:FireServer("Drag", m) -- … and a drag on top
		local done = waitFor(tStart, { "Result" }, 5)
		out.resultSeconds = done and (done.At - tStart)
		out.messages = messagesSince(t0)
	elseif opts.localState then
		local m = bot(opts.localState)
		m:SetAttribute("BodyPhase", "DEAD")
		m:SetAttribute("BodyStance", "DOWN")
		m:SetAttribute("BodyLife", 0)
		local t0 = menuPress(m, 1)
		local done = waitFor(t0, { "Result", "Rejected", "Interrupted" }, 5)
		out.localPhase = m:GetAttribute("BodyPhase")
		out.result = done and done.Text
		out.messages = messagesSince(t0)
	elseif opts.drag then
		local m = bot(opts.drag)
		local t0, before = menuPress(m, 2)
		out.menuBefore = before
		frames(0.3)
		out.menuDragging = call("view")
		local hum = (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
		out.walkSpeedDragging = hum.WalkSpeed
		local r = root()
		local start = r.Position
		local tWalk = os.clock()
		hum:MoveTo(start + Vector3.new(0, 0, opts.back or 12))
		local reached = false
		local conn = hum.MoveToFinished:Connect(function()
			reached = true
		end)
		while not reached and os.clock() - tWalk < 6 do
			RunService.RenderStepped:Wait()
		end
		conn:Disconnect()
		out.walkSeconds = os.clock() - tWalk
		out.walked = (r.Position - start).Magnitude
		frames(opts.hold or 1.0)
		local tLet = call("press") -- "[F] Let go"
		waitFor(tLet, { "Released" }, 2)
		frames(0.2)
		out.menuAfter = call("view")
		out.walkSpeedAfter = hum.WalkSpeed
		out.messages = messagesSince(t0)
	elseif opts.dragAway then
		local m = bot(opts.dragAway)
		local t0 = menuPress(m, 2)
		frames(0.6)
		local r = root()
		r.CFrame = r.CFrame + Vector3.new(0, 0, 30)
		r.AssemblyLinearVelocity = Vector3.zero
		frames(0.8)
		out.messages = messagesSince(t0)
		out.walkSpeedAfter = ((player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid).WalkSpeed
	elseif opts.dragInvalid then
		local t0 = os.clock()
		for _, i in { 1, 2 } do -- standing ALIVE, standing INJURED
			standBy(bot(i), 3.5)
			Request:FireServer("Drag", bot(i))
			frames(0.3)
		end
		local f = workspace:FindFirstChild("BodyStateTest")
		local b3 = f and f:FindFirstChild("BODY3", true) :: Model?
		if b3 then -- down, but the R6 debug pose: not a physical body
			standBy(b3, 3.5)
			Request:FireServer("Drag", b3)
			frames(0.3)
		end
		standBy(bot(3), 25) -- a downed body out of range
		Request:FireServer("Drag", bot(3))
		frames(0.4)
		out.messages = messagesSince(t0)
	elseif opts.tamper then
		local m = bot(opts.tamper)
		local upper = m:FindFirstChild("UpperTorso") :: BasePart
		out.before = upper.Position
		standBy(m, 3.5)
		local t0 = os.clock()
		-- local physics writes on a server-owned body
		pcall(function()
			upper.CFrame = upper.CFrame + Vector3.new(0, 10, 0)
			upper.AssemblyLinearVelocity = Vector3.new(0, 0, 80)
		end)
		-- drag requests carrying positions / another "player" / a speed
		Request:FireServer("Drag", m, Vector3.new(0, 50, 0), "OtherPlayer", 999)
		frames(0.4)
		Request:FireServer("LetGo", m)
		frames(0.25)
		Request:FireServer("MoveBody", m, Vector3.new(0, 0, 200))
		frames(0.25)
		Request:FireServer("Trail", m, upper.Position)
		frames(0.25)
		StateRemote:FireServer({ Kind = "Drag", Phase = "Started", Target = m })
		frames(0.5)
		out.localAfter = upper.Position
		out.messages = messagesSince(t0)
	end
	return out
end
