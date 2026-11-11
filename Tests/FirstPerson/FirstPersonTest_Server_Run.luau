--!strict
-- First-person fidelity test, server side (Studio only; delete the FirstPersonTest folders to remove it). Driven through
-- execute_luau (Server datamodel); the client half is StarterPlayerScripts.FirstPersonTest.Run. Reads the running
-- server through its Studio debug hooks only.
--   Run.prepare()                 client teleports allowed (the range spot), grenade records cleared
--   Run.killDuringThrow(delay)    arms a watcher: the next accepted throw kills the player `delay` s after it starts
--   Run.watchLaunch()             arms a watcher: the next released grenade's first server position / velocity vs the
--                                 server's own launch rule from the head (forged arguments must not matter)
--   Run.launchResult()            what watchLaunch saw
--   Run.grenades()                GrenadeDebug status (counters, players) + recent records
--   Run.serverView()              what the server sees of the client-only parts (proxy, LocalTransparencyModifier)
--   Run.netStart() / netStop()    count every client → server remote event (the first-person changes add none)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config.Grenade) :: any
local Throw = require(ServerScriptService.Server.Grenade.Throw) :: any

local Run = {}

local function grenadeDebug(): BindableFunction
	return ServerScriptService:FindFirstChild("GrenadeDebug", true) :: BindableFunction
end

local function player(): Player
	return Players:GetPlayers()[1]
end

function Run.prepare(): any
	require(ServerScriptService.MovementTest.Run).dbg("allowClientTeleports", nil, true)
	grenadeDebug():Invoke("clear")
	return { player = player().Name }
end

function Run.grenades(): any
	local d = grenadeDebug()
	return { status = d:Invoke("status"), recent = d:Invoke("recent") }
end

local killArmed: any = nil
function Run.killDuringThrow(delay: number): boolean
	local p = player()
	local token = {}
	killArmed = token
	task.spawn(function()
		local t0 = os.clock()
		while killArmed == token and os.clock() - t0 < 8 do
			local st = grenadeDebug():Invoke("status")
			local ps = st.Players and st.Players[p.Name]
			if ps and ps.Throwing then
				task.wait(delay)
				local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.Health = 0
				end
				killArmed = nil
				return
			end
			RunService.Heartbeat:Wait()
		end
		killArmed = nil
	end)
	return true
end

local launch: any = nil
function Run.watchLaunch(): boolean
	launch = { armed = true }
	local p = player()
	task.spawn(function()
		local t0 = os.clock()
		local folder = workspace:FindFirstChild("Grenades")
		local known = {}
		if folder then
			for _, c in folder:GetChildren() do
				known[c] = true
			end
		end
		while os.clock() - t0 < 8 do
			folder = workspace:FindFirstChild("Grenades")
			if folder then
				for _, c in folder:GetChildren() do
					if not known[c] and c:IsA("BasePart") then
						local head = (p.Character :: Model):FindFirstChild("Head") :: BasePart
						local cam = (p.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
						launch = { armed = false, id = c:GetAttribute("GrenadeId"), position = c.Position,
							velocity = c.AssemblyLinearVelocity, head = head.Position, rootLook = cam.CFrame.LookVector,
							distFromHead = (c.Position - head.Position).Magnitude, speed = c.AssemblyLinearVelocity.Magnitude }
						return
					end
				end
			end
			RunService.Heartbeat:Wait()
		end
	end)
	return true
end

-- the server's own launch for a given aim (what the first sample must match, whatever else the client sent)
function Run.launchResult(aim: Vector3?): any
	local out = table.clone(launch or {})
	if aim and out.position then
		local o, v = Throw.launch(player().Character, aim)
		if o and v then
			out.expectedOrigin = o
			out.originError = (out.position - o).Magnitude
			out.velocityError = (out.velocity - v).Magnitude
			out.expectedSpeed = v.Magnitude
		end
	end
	return out
end

function Run.serverView(): any
	local proxies = 0
	for _, d in workspace:GetDescendants() do
		if d.Name == "GrenadeProxy" then
			proxies += 1
		end
	end
	local ltm = 0
	local f = workspace:FindFirstChild("Grenades")
	if f then
		for _, d in f:GetDescendants() do
			if d:IsA("BasePart") and (d.LocalTransparencyModifier ~= 0 or d.Transparency ~= 0) then
				ltm += 1
			end
		end
	end
	return { proxiesOnServer = proxies, bodiesNotOpaqueOnServer = ltm }
end

local counts: { [string]: number } = {}
local conns: { RBXScriptConnection } = {}
function Run.netStart(): number
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	table.clear(counts)
	local n = 0
	for _, r in ReplicatedStorage:GetDescendants() do
		if r:IsA("RemoteEvent") then
			n += 1
			table.insert(conns, r.OnServerEvent:Connect(function()
				counts[r.Name] = (counts[r.Name] or 0) + 1
			end))
		end
	end
	return n
end

function Run.netStop(): { [string]: number }
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	return table.clone(counts)
end

Run.Config = Config
return Run
