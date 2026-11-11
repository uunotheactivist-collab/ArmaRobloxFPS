--!strict
-- Focused grenade test, client side (Studio only; delete the GrenadeTest folders to remove it). Real throws go through
-- the production client (GrenadeClientDebug "press": the G-key path, camera aim). Fake requests are fired straight at
-- the remotes. Everything is decided and checked on the server (ServerScriptService.GrenadeTest.Run).
--   Run({ throw = { at = Vector3, dir = Vector3 }, wait = s })   stand at `at` (feet), aim along `dir`, press G
--   Run({ timing = { at, dir } })   presses at 0, 0.30 s (still throwing) and 0.45 s (allowed again)
--   Run({ noFrags = true })         press with none left (the server set 0 first)
--   Run({ forged = { at, dir } })   the ten forged inputs + moving a live grenade locally
--   Run({ multi = { at, dir, n } }) n throws in a row, 0.45 s apart

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Grenade")
	:WaitForChild("GrenadeClient"):WaitForChild("GrenadeClientDebug") :: BindableFunction
local Remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
local Command = Remotes:WaitForChild("GrenadeCommand") :: RemoteEvent
local StateRemote = Remotes:WaitForChild("GrenadeState") :: RemoteEvent
local FxRemote = Remotes:WaitForChild("GrenadeFx") :: RemoteEvent

local function call(cmd: string, arg: any?): any
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function root(): BasePart
	return (player.Character :: Model):WaitForChild("HumanoidRootPart") :: BasePart
end

-- Stand with the feet at `at`, facing dir's heading, and aim the camera along dir. The camera scripts keep their own
-- yaw, so a large turn takes a few tries: set both until the camera holds the aim and the character faces it, then
-- give the server time to see the new facing (it refuses a throw aimed behind the character).
local function standAndAim(at: Vector3, dir: Vector3): boolean
	local flat = Vector3.new(dir.X, 0, dir.Z).Unit
	local r = root()
	local pos = at + Vector3.new(0, 3, 0)
	local cam = workspace.CurrentCamera
	local ok = false
	for _ = 1, 12 do
		r.CFrame = CFrame.lookAt(pos, pos + flat)
		r.AssemblyLinearVelocity = Vector3.zero
		cam.CFrame = CFrame.lookAt(cam.CFrame.Position, cam.CFrame.Position + dir.Unit)
		frames(0.12)
		local look = Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z)
		if cam.CFrame.LookVector:Dot(dir.Unit) > 0.995 and look.Magnitude > 1e-3 and look.Unit:Dot(flat) > 0.98 then
			ok = true
			break
		end
	end
	frames(0.3)
	return ok
end

local function messagesSince(since: number): { string }
	local out = {}
	for _, m in call("messages") do
		if m.At >= since then
			table.insert(out, string.format("+%.3f %s left %s%s%s", m.At - since, tostring(m.Phase), tostring(m.Left),
				if m.Reason then " (" .. m.Reason .. ")" else "", if m.Id then " id " .. m.Id else ""))
		end
	end
	return out
end

local function fxSince(since: number): { any }
	local out = {}
	for _, f in call("fx") do
		if f.At >= since then
			table.insert(out, { dt = f.At - since, Id = f.Id, p = f.p })
		end
	end
	return out
end

return function(opts: any): any
	local out: any = {}
	frames(0.1)
	if opts.throw then
		out.aimSettled = standAndAim(opts.throw.at, opts.throw.dir)
		local t0 = call("press")
		frames(0.05)
		out.presentation = call("view").Presenting
		frames(0.25)
		out.labelAfterRelease = call("view")
		frames(opts.wait or 0.2)
		out.messages = messagesSince(t0)
		out.fx = fxSince(t0)
		out.view = call("view")
		out.aimSent = workspace.CurrentCamera.CFrame.LookVector
	elseif opts.timing then
		standAndAim(opts.timing.at, opts.timing.dir)
		local t0 = call("press")
		frames(0.30)
		Command:FireServer("Throw", workspace.CurrentCamera.CFrame.LookVector) -- 0.30 s: still throwing
		frames(0.15)
		Command:FireServer("Throw", workspace.CurrentCamera.CFrame.LookVector) -- 0.45 s: the 0.40 s throw is over
		frames(0.6)
		out.messages = messagesSince(t0)
	elseif opts.noFrags then
		local t0 = call("press")
		frames(0.4)
		out.view = call("view")
		out.messages = messagesSince(t0)
	elseif opts.forged then
		standAndAim(opts.forged.at, opts.forged.dir)
		local dir = workspace.CurrentCamera.CFrame.LookVector
		local far = Vector3.new(0, 50, 0)
		local t0 = os.clock()
		-- 1 position / 2 velocity / 3 fuse, as extra arguments of a real throw (must be ignored; the throw is real)
		Command:FireServer("Throw", dir, far, dir * 900, 0.1)
		frames(0.5)
		-- 2 a velocity instead of a direction / 1 a position instead of a direction
		Command:FireServer("Throw", dir * 900)
		frames(0.25)
		Command:FireServer("Throw", far)
		frames(0.25)
		-- 3 fuse / 4 detonation / 5–9 fragments / 10 result, as their own actions
		local reactTorso = workspace:FindFirstChild("HitReactionTest") and workspace.HitReactionTest:FindFirstChild("REACT1", true)
		for _, a in {
			{ "SetFuse", 1, 0.1 },
			{ "Detonate", 1 },
			{ "Fragment", far, Vector3.yAxis },
			{ "Fragments", { { o = far, d = Vector3.yAxis } } },
			{ "Hit", reactTorso, Vector3.new(0, 1, 0) },
			{ "Target", reactTorso },
			{ "Damage", reactTorso, 999 },
			{ "Result", { IntoBodies = 600 } },
		} do
			Command:FireServer(table.unpack(a))
			frames(0.12)
		end
		-- 4 / 10 on the server → client channels
		FxRemote:FireServer({ Id = 999, p = far })
		StateRemote:FireServer({ Phase = "Detonated", Id = 1, IntoBodies = 600 })
		-- a live grenade moved / flung locally (server-owned: must not move on the server)
		local live = workspace:FindFirstChild("Grenades") and workspace.Grenades:FindFirstChild("FragGrenade")
		if live and live:IsA("BasePart") then
			out.liveBefore = live.Position
			pcall(function()
				live.CFrame = live.CFrame + Vector3.new(0, 40, 0)
				live.AssemblyLinearVelocity = Vector3.new(0, 200, 0)
			end)
		end
		frames(0.5)
		out.messages = messagesSince(t0)
	elseif opts.multi then
		local m = opts.multi
		standAndAim(m.at, m.dir)
		local t0 = os.clock()
		for _ = 1, m.n do
			call("press")
			frames(0.45)
		end
		frames(m.wait or 4.6)
		out.messages = messagesSince(t0)
		out.fx = fxSince(t0)
		out.view = call("view")
	end
	return out
end
