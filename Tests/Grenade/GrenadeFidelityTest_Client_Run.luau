--!strict
-- Grenade fidelity test, client side (Studio only; delete the GrenadeFidelityTest folder to remove it). Driven through
-- execute_luau (Client): require(PlayerScripts.GrenadeFidelityTest.Run).<fn>(...). Measures the behaviour the grenade
-- fidelity slice changed, in the reference's own units (1280 x 720 picture, FOV 70, 30 fps; ReferenceAnalysis/
-- GrenadeFidelity). The generic throw / timing / forged / multi recipes stay in GrenadeTest.Run.
--   Run.launch(pitchDeg)      throw with the camera pitched (default -4.5, the normal clip): the server grenade's screen
--                             path per 30-fps frame after release (line of sight vs the screen centre), release point,
--                             lever spawn
--   Run.presentation()        the throw arm's hand end on screen at the reference's L-1 .. L+5 (frozen poses)
--   Run.label()               label solid / fade times and the text ink box in the 1280 x 720 picture
--   Run.redEdge()             the pulse's strength envelope (hook) at the reference's sample frames
--   Run.fragmentsHit(at)      a throw at the player's own feet: the server's FragmentsHit message, the pulse, no damage
--   Run.security()            forged aims / spam / forged client→server state; returns the client view of each
-- Old suites' client teleports need MovementTest.Run.dbg("allowClientTeleports", nil, true) on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage.Shared.Config.Grenade) :: any
local Remotes = ReplicatedStorage.Shared.Remotes
local Command = Remotes:WaitForChild("GrenadeCommand") :: RemoteEvent
local StateRemote = Remotes:WaitForChild("GrenadeState") :: RemoteEvent
local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Grenade"):WaitForChild("GrenadeClient")
	:WaitForChild("GrenadeClientDebug") :: BindableFunction

local Run = {}

local function call(cmd: string, arg: any?): any
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function r1(v: number): number
	return math.round(v * 10) / 10
end

-- a world point in the reference's 1280 x 720 picture (same vertical FOV; centred 16:9 crop of the viewport)
local function px720(cam: CFrame, fov: number, p: Vector3): (Vector2, number)
	local l = cam:PointToObjectSpace(p)
	local f720 = 360 / math.tan(math.rad(fov) / 2)
	return Vector2.new(640 + l.X / -l.Z * f720, 360 - l.Y / -l.Z * f720), -l.Z
end

local function root(): BasePart
	return (player.Character :: Model):WaitForChild("HumanoidRootPart") :: BasePart
end

-- face `yaw` (deg) with the camera pitched `pitch` (deg); retries until the camera holds
local function aim(pitch: number)
	local r = root()
	local look = r.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z).Unit
	local dir = (flat * math.cos(math.rad(pitch)) + Vector3.new(0, math.sin(math.rad(pitch)), 0)).Unit
	local cam = workspace.CurrentCamera
	for _ = 1, 10 do
		cam.CFrame = CFrame.lookAt(cam.CFrame.Position, cam.CFrame.Position + dir)
		frames(0.1)
		if cam.CFrame.LookVector:Dot(dir) > 0.9995 then
			break
		end
	end
	frames(0.3)
end

function Run.launch(pitchDeg: number?): any
	aim(pitchDeg or -4.5)
	call("refill")
	Command:FireServer("DevRefill")
	frames(0.3)
	local cam0 = workspace.CurrentCamera.CFrame
	local fov = workspace.CurrentCamera.FieldOfView
	local before = {}
	local existing = workspace:FindFirstChild("Grenades") -- made by the server at its first throw
	if existing then
		for _, c in existing:GetChildren() do
			before[c] = true
		end
	end
	local lever0 = call("view").Lever.Spawned
	local tPress = call("press")
	local body: BasePart? = nil
	local samples = {}
	local t0 = os.clock()
	while os.clock() - t0 < 1.2 do
		RunService.RenderStepped:Wait()
		local folder = workspace:FindFirstChild("Grenades")
		if not body and folder then
			for _, c in folder:GetChildren() do
				if not before[c] and c:IsA("BasePart") then
					body = c
				end
			end
		end
		if body and body.Parent then
			local cam = workspace.CurrentCamera.CFrame
			local s, depth = px720(cam, fov, body.Position)
			table.insert(samples, { t = os.clock() - tPress, x = s.X, y = s.Y, depth = depth, p = body.Position })
		end
	end
	-- 30-fps frames counted from the first sample (the release as seen by this client)
	local series = {}
	if #samples > 0 then
		local t1 = samples[1].t
		local k = 0
		for _, s in samples do
			if s.t >= t1 + k / 30 then
				table.insert(series, string.format("+%d (%d, %d) d%.1f", k, math.round(s.x), math.round(s.y), s.depth))
				k += 1
				if k > 12 then
					break
				end
			end
		end
	end
	local first = samples[1]
	local dirUp, dirLeft = nil, nil
	local frozenFrames = 0
	if first then
		-- the replicated body holds at the release point until its motion reaches this client: count those frames, then
		-- take the launch direction (throw-time camera frame) from the first moving samples
		local moved: any = nil
		for _, s in samples do
			if (s.p - first.p).Magnitude > 0.05 then
				moved = s
				break
			end
		end
		if moved then
			frozenFrames = math.floor((moved.t - first.t) * 30 + 0.5)
			local later = moved
			for _, s in samples do
				if s.t >= moved.t + 0.05 then
					later = s
					break
				end
			end
			local v = cam0:VectorToObjectSpace((later.p - moved.p).Unit)
			dirUp = r1(math.deg(math.atan2(v.Y, -v.Z)))
			dirLeft = r1(math.deg(math.atan2(-v.X, -v.Z)))
		end
	end
	frames(0.2)
	return {
		cameraPitchDeg = r1(math.deg(math.asin(cam0.LookVector.Y))),
		releaseSeenAtS = first and math.round(first.t * 1000) / 1000,
		releaseScreen = first and { math.round(first.x), math.round(first.y) },
		releaseDepthStuds = first and r1(first.depth),
		launchAboveAimDeg = dirUp,
		launchLeftOfAimDeg = dirLeft,
		heldAtReleaseFrames = frozenFrames,
		screenPath = series,
		leversSpawned = call("view").Lever.Spawned - lever0,
	}
end

function Run.presentation(): any
	local out = {}
	local view = workspace.CurrentCamera:FindFirstChild("GrenadeThrowView")
	local rel = Config.Throw.ReleaseSeconds
	for k = -1, 5 do -- L + k (release = L + 1)
		local t = rel + (k - 1) / 30
		call("freezeThrow", t)
		frames(0.15)
		view = workspace.CurrentCamera:FindFirstChild("GrenadeThrowView")
		local cam = workspace.CurrentCamera.CFrame
		local fov = workspace.CurrentCamera.FieldOfView
		local arm = view and view:FindFirstChild("Arm") :: BasePart?
		local g = view and view:FindFirstChild("Grenade") :: BasePart?
		local entry: any = { frame = "L" .. (if k >= 0 then "+" else "") .. k }
		if arm and arm.Transparency < 1 then
			local hand = arm.CFrame * Vector3.new(0, 0, -arm.Size.Z / 2)
			local s = px720(cam, fov, hand)
			entry.hand = { math.round(s.X), math.round(s.Y) }
		end
		if g and g.Transparency < 1 then
			local s = px720(cam, fov, g.Position)
			entry.grenade = { math.round(s.X), math.round(s.Y) }
		end
		table.insert(out, entry)
	end
	call("freezeThrow", nil)
	return out
end

function Run.label(): any
	call("refill")
	Command:FireServer("DevRefill")
	frames(0.3)
	local gui = player.PlayerGui:WaitForChild("GrenadeHud", 5)
	call("press")
	local label: TextLabel? = nil
	local shownAt, fadeAt, goneAt = nil, nil, nil
	local t0 = os.clock()
	local box = nil
	while os.clock() - t0 < 2.6 do
		RunService.RenderStepped:Wait()
		gui = gui or player.PlayerGui:FindFirstChild("GrenadeHud")
		label = label or (gui and gui:FindFirstChild("FragOut") :: TextLabel?)
		if label then
			local tr = label.TextTransparency
			if not shownAt and tr < 0.01 then
				shownAt = os.clock()
				local vp = workspace.CurrentCamera.ViewportSize
				local k = 720 / vp.Y
				local tb = label.TextBounds
				local ap = label.AbsolutePosition
				local asz = label.AbsoluteSize
				-- text box (left aligned, vertically centred), in the 1280 x 720 picture (centred 16:9 crop)
				local cropX = (vp.X - vp.Y * 16 / 9) / 2
				local top = ap.Y + (asz.Y - tb.Y) / 2
				box = { left = math.round((ap.X - cropX) * k), top = math.round(top * k), height = r1(tb.Y * k),
					width = math.round(tb.X * k), viewport = { vp.X, vp.Y }, guiInsetIgnored = (gui :: ScreenGui).IgnoreGuiInset }
			elseif shownAt and not fadeAt and tr > 0.01 then
				fadeAt = os.clock()
			elseif fadeAt and not goneAt and tr > 0.99 then
				goneAt = os.clock()
			end
		end
	end
	return {
		text = label and label.Text,
		solidS = shownAt and fadeAt and math.round((fadeAt - shownAt) * 1000) / 1000,
		fadeS = fadeAt and goneAt and math.round((goneAt - fadeAt) * 1000) / 1000,
		textBox720 = box,
	}
end

function Run.redEdge(): any
	call("redEdge")
	local samples = {}
	local t0 = os.clock()
	for _, k in { 0, 3, 6, 9, 12, 19, 24, 34, 54, 62, 70 } do
		while os.clock() - t0 < k / 30 do
			RunService.RenderStepped:Wait()
		end
		table.insert(samples, string.format("+%d %.2f", k, call("view").RedEdge.Strength))
	end
	frames(0.3)
	return { strength = samples, visibleAfter = call("view").RedEdge.Visible }
end

-- Throw at the player's own feet (aim straight down: the launch turns 21° up from it, it still lands close) and read the
-- server's FragmentsHit message and the pulse.
function Run.fragmentsHit(): any
	aim(-89)
	call("refill")
	Command:FireServer("DevRefill")
	frames(0.3)
	local hum = (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
	local health0 = hum.Health
	local count0 = call("view").RedEdge.Count
	local since = os.clock()
	call("press")
	frames(Config.Fuse.Seconds + 0.6)
	local msgs = {}
	for _, m in call("messages") do
		if m.At >= since then
			table.insert(msgs, string.format("+%.3f %s%s", m.At - since, tostring(m.Phase), if m.Id then " id " .. m.Id else ""))
		end
	end
	local v = call("view").RedEdge
	return { messages = msgs, pulses = v.Count - count0, strengthNow = r1(v.Strength * 100) / 100, healthBefore = health0,
		healthAfter = hum.Health }
end

-- Forged requests from this client (server checks: GrenadeServer / Throw.aim). Returns the server's answers.
function Run.security(): any
	call("refill")
	Command:FireServer("DevRefill")
	frames(0.4)
	local since = os.clock()
	local look = workspace.CurrentCamera.CFrame.LookVector
	local cases = {
		{ "nan", Vector3.new(0 / 0, 0, -1) },
		{ "inf", Vector3.new(math.huge, 0, 0) },
		{ "zero", Vector3.zero },
		{ "velocity (|v| 55)", look * 55 },
		{ "string", "up" },
		{ "table", { 0, 1, 0 } },
		{ "nil", nil },
	}
	for _, c in cases do
		Command:FireServer("Throw", c[2])
		frames(0.15)
	end
	-- spam: 10 throws in one frame (one throw at a time; the rest refused)
	for _ = 1, 10 do
		Command:FireServer("Throw", look)
	end
	frames(0.6)
	-- forged server → client message sent to the server, and a forged pulse request
	StateRemote:FireServer({ Phase = "FragmentsHit", Id = 1, Count = 600 })
	Command:FireServer("FragmentsHit", 600)
	Command:FireServer("Detonate", 1)
	Command:FireServer("Explode", Vector3.new(0, 10, 0))
	frames(0.4)
	local msgs = {}
	for _, m in call("messages") do
		if m.At >= since then
			table.insert(msgs, string.format("%s%s", tostring(m.Phase), if m.Reason then " (" .. m.Reason .. ")" else ""))
		end
	end
	return { messages = msgs, pulsesShown = call("view").RedEdge.Count }
end

return Run
