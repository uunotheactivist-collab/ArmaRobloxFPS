--!strict
-- Focused optics test, client side (Studio only; delete the OpticsTest folders to remove it). Driven through
-- execute_luau (Client datamodel): require(PlayerScripts.OpticsTest.Run).<fn>(...). The server half is
-- ServerScriptService.OpticsTest.Run; the range is Workspace.OpticsTest. Everything here reads the running game
-- through its Studio debug hooks (Client.WeaponController ProductionWeaponDebug, Client.Movement MovementClientDebug).
--   Run.equip(id)                 equip a weapon, report the optic / rig state
--   Run.look(point)               point the camera at a world point (repeated until it holds)
--   Run.lens()                    lens / ring / axis on screen, scope camera, visibility, magnification from geometry
--   Run.transition(inHold, outHold)   HIP -> AIMING -> SCOPED -> AIMING -> HIP, per-frame states and lens track
--   Run.track(opts)               scoped camera sweep / walk / crouch / jump: scope camera vs main camera every frame
--   Run.fire(n, gap, aim)         n trigger presses (semi-automatic): shots, recoil, lens kick and eye-box shadow
--   Run.forge(kind)               forged remote calls (security): what the client can send, never what it can't
--   Run.perf(seconds, aim)        per-frame optic / mirror cost, frame time, memory, instance counts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local Run = {}

local function weapon(cmd: string, arg: any?): any
	local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("WeaponController")
		:WaitForChild("ProductionWeaponDebug") :: BindableFunction
	return hook:Invoke(cmd, arg)
end
Run.weapon = weapon

local function move(cmd: string, arg: any?): any
	local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Movement")
		:WaitForChild("MovementController"):WaitForChild("MovementClientDebug") :: BindableFunction
	return hook:Invoke(cmd, arg)
end
Run.move = move

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end
Run.frames = frames

local function r3(v: number?): number?
	return if v then math.round(v * 1000) / 1000 else nil
end

local function angle(a: Vector3, b: Vector3): number
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

-- Screen projection with a logged camera (vertical FOV in degrees, viewport W x H); y grows downward.
local function project(cam: CFrame, fov: number, vp: Vector2, p: Vector3): Vector2
	local l = cam:PointToObjectSpace(p)
	local f = (vp.Y / 2) / math.tan(math.rad(fov) / 2)
	return Vector2.new(vp.X / 2 + l.X / -l.Z * f, vp.Y / 2 - l.Y / -l.Z * f)
end
Run.project = project

local STUD = 0.28
local function opticGeometry(): any
	local def = require(ReplicatedStorage.Shared.Config.Optics.ReferenceScope) :: any
	return def, def.Layout.LensDiameter / STUD / 2, def.Layout.EyepieceDiameter / STUD / 2
end

-- Lens (and eyepiece rim) on screen for a log sample; sizes as fractions of the viewport height.
local function lensOnScreen(s: any, vp: Vector2): any
	if not s.lensCF then
		return nil
	end
	local def, lr, rr = opticGeometry()
	local cam, fov, lens = s.camera, s.fov, s.lensCF
	local c = project(cam, fov, vp, lens.Position)
	local l = project(cam, fov, vp, lens * Vector3.new(-lr, 0, 0))
	local r = project(cam, fov, vp, lens * Vector3.new(lr, 0, 0))
	local rim = lens * CFrame.new(0, 0, def.Layout.LensRecess / STUD) -- the rim is LensRecess nearer the eye (+Z)
	local rl = project(cam, fov, vp, rim * Vector3.new(-rr, 0, 0))
	local rrp = project(cam, fov, vp, rim * Vector3.new(rr, 0, 0))
	return {
		x = (c.X - vp.X / 2) / vp.Y, -- offset from the screen centre, in screen heights
		y = (c.Y - vp.Y / 2) / vp.Y,
		lensD = (r - l).Magnitude / vp.Y,
		ringD = (rrp - rl).Magnitude / vp.Y,
	}
end
Run.lensOnScreen = lensOnScreen

function Run.equip(id: string): any
	player:SetAttribute("EquippedWeapon", id)
	frames(0.6)
	local st = weapon("optic", "ScopeTest")
	local cam = workspace.CurrentCamera
	local vm = cam:FindFirstChild(id .. "Viewmodel")
	local housing = {}
	if vm then
		for _, p in vm:GetChildren() do
			if string.sub(p.Name, 1, 6) == "Optic_" then
				table.insert(housing, p.Name)
			end
		end
	end
	table.sort(housing)
	local hud = player.PlayerGui:FindFirstChild(id .. "Hud")
	return {
		equipped = player:GetAttribute("EquippedWeapon"),
		viewmodels = weapon("state").viewmodels,
		viewmodelParented = vm ~= nil,
		opticParts = housing,
		optic = {
			active = st.active, live = st.live, state = st.aimState, gui = st.gui,
			mirrorStarted = st.mirrorStarted, mirror = st.mirror,
		},
		cameraFov = r3(cam.FieldOfView),
		hud = if hud then { enabled = (hud :: ScreenGui).Enabled } else nil,
		server = weapon("state").server,
	}
end

function Run.look(point: Vector3, holds: number?)
	local cam = workspace.CurrentCamera
	for _ = 1, holds or 4 do
		cam.CFrame = CFrame.lookAt(cam.CFrame.Position, point)
		frames(0.12)
	end
end

function Run.lens(): any
	local d = weapon("optic", "ScopeTest")
	local cam = workspace.CurrentCamera
	local vp = cam.ViewportSize
	local out: any = {
		state = d.aimState, live = d.live, gui = d.gui, cameraFov = r3(cam.FieldOfView),
		scopeFov = r3(d.scopeFov), eyeDistance = r3(d.eyeDistance), shadow = d.shadow, viewport = vp,
	}
	if d.lensScreen then
		local ls = d.lensScreen
		out.lensCentrePx = { r3(ls.x - vp.X / 2), r3(ls.y - vp.Y / 2) }
		out.axisPx = { r3(d.axisScreen.x - vp.X / 2), r3(d.axisScreen.y - vp.Y / 2) }
		out.lensDiameterH = r3(ls.w / vp.Y) -- reference 162 / 720 = 0.225
		out.lensDiameterRef720 = r3(ls.w / vp.Y * 720)
		-- magnification from the render geometry: lens pixels per radian of scene vs main-view pixels per radian
		if d.scopeFov then
			local fMain = (vp.Y / 2) / math.tan(math.rad(cam.FieldOfView) / 2)
			local fLens = (ls.w / 2) / math.tan(math.rad(d.scopeFov) / 2)
			out.magnificationGeometry = r3(fLens / fMain)
		end
	end
	local log = nil
	weapon("record", true)
	frames(0.1)
	log = weapon("record", false).log
	local s = log[#log]
	if s and s.lensCF then
		out.fromLog = lensOnScreen(s, vp)
		out.fromLog.x, out.fromLog.y = r3(out.fromLog.x), r3(out.fromLog.y)
		out.fromLog.lensD, out.fromLog.ringD = r3(out.fromLog.lensD), r3(out.fromLog.ringD)
		out.ringRef720 = r3(out.fromLog.ringD * 720) -- reference 266.5 px
		if s.scopeCF then
			out.scopeVsCameraDeg = r3(angle(s.scopeCF.LookVector, s.camera.LookVector))
			out.scopeCameraOffset = r3((s.scopeCF.Position - s.camera.Position).Magnitude)
		end
	end
	return out
end

-- HIP -> AIMING -> SCOPED, hold, then back to HIP; every frame logged.
function Run.transition(inHold: number?, outHold: number?): any
	weapon("aim", false)
	frames(0.5)
	local vp = workspace.CurrentCamera.ViewportSize
	weapon("record", true)
	frames(0.1)
	local tIn = os.clock()
	weapon("aim", true)
	frames(inHold or 0.8)
	local tOut = os.clock()
	weapon("aim", false)
	frames(outHold or 0.5)
	local log = weapon("record", false).log
	local samples = {}
	local seq = {}
	local last = nil
	local firstScoped, firstHipAfter, firstAiming, firstAimingOut = nil, nil, nil, nil
	for _, s in log do
		local st = s.opticState
		if st ~= last then
			table.insert(seq, { t = r3(s.t - tIn), state = st })
			last = st
		end
		if s.t >= tIn and st == "AIMING" and not firstAiming then
			firstAiming = s.t
		end
		if s.t >= tIn and s.t < tOut and st == "SCOPED" and not firstScoped then
			firstScoped = s.t
		end
		if s.t >= tOut and st == "AIMING" and not firstAimingOut then
			firstAimingOut = s.t
		end
		if s.t >= tOut and st == "HIP" and not firstHipAfter then
			firstHipAfter = s.t
		end
		local ls = lensOnScreen(s, vp)
		table.insert(samples, {
			t = r3(s.t - tIn), aim = r3(s.aim), state = st, live = s.opticLive,
			lensY = if ls then r3(ls.y) else nil, lensX = if ls then r3(ls.x) else nil,
			ringD = if ls then r3(ls.ringD) else nil, fov = r3(s.fov),
		})
	end
	-- settle: lens centre height over the 0.4 s after arrival
	local settle = {}
	if firstScoped then
		for _, s in samples do
			if s.t >= firstScoped - tIn and s.t <= firstScoped - tIn + 0.4 and s.lensY then
				table.insert(settle, s.lensY)
			end
		end
	end
	return {
		sequence = seq,
		inTime = if firstScoped then r3(firstScoped - tIn) else nil, -- press -> SCOPED (one frame of input latency)
		outTime = if firstHipAfter then r3(firstHipAfter - tOut) else nil,
		firstAimingIn = if firstAiming then r3(firstAiming - tIn) else nil,
		firstAimingOut = if firstAimingOut then r3(firstAimingOut - tOut) else nil,
		settleLensY = { settle[1], settle[#settle] },
		fovs = { samples[1] and samples[1].fov, samples[#samples] and samples[#samples].fov },
		samples = samples,
	}
end

-- Scoped camera tracking under turning / movement / crouch / jump. opts: { aim = true, rate = deg/s, seconds,
-- move = Vector3?, crouch = boolean?, jump = boolean?, after = s }
function Run.track(opts: any): any
	local rate = opts.rate or 0
	local turning = false
	RunService:BindToRenderStep("OpticsTestTurn", Enum.RenderPriority.Camera.Value - 2, function(dt: number)
		if not turning then
			return
		end
		local cam = workspace.CurrentCamera
		local p = cam.CFrame.Position
		cam.CFrame = CFrame.new(p) * CFrame.Angles(0, -math.rad(rate) * dt, 0) * cam.CFrame.Rotation
	end)
	if opts.aim ~= false then
		weapon("aim", true)
		frames(0.6)
	end
	if opts.crouch ~= nil then
		move("crouch", opts.crouch)
		frames(0.6)
	end
	weapon("record", true)
	move("record", true)
	if opts.move then
		move("input", opts.move)
	end
	frames(0.15)
	if opts.jump then
		local hum = (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
		hum.Jump = true
	end
	turning = rate ~= 0
	frames(opts.seconds or 1.5)
	turning = false
	if opts.move then
		move("input", nil)
	end
	frames(opts.after or 1.0)
	local log = weapon("record", false).log
	local mlog = move("record", false)
	RunService:UnbindFromRenderStep("OpticsTestTurn")
	local vp = workspace.CurrentCamera.ViewportSize
	local maxAxisDeg, lastAxisDeg, maxRollDiff, maxPosOff, live, scoped, n = 0, 0, 0, 0, 0, 0, 0
	local maxCamRoll, fovMin, fovMax = 0, math.huge, -math.huge
	local maxLensOff, endLensOff = 0, 0
	local maxSpeed, minEyeY, maxEyeY = 0, math.huge, -math.huge
	for i, s in log do
		n += 1
		minEyeY, maxEyeY = math.min(minEyeY, s.camera.Position.Y), math.max(maxEyeY, s.camera.Position.Y)
		-- horizontal camera speed over ~0.25 s windows (walking while scoped)
		for j = i - 1, 1, -1 do
			local q = log[j]
			if s.t - q.t >= 0.25 then
				local d = s.camera.Position - q.camera.Position
				maxSpeed = math.max(maxSpeed, Vector3.new(d.X, 0, d.Z).Magnitude / (s.t - q.t))
				break
			end
		end
		fovMin, fovMax = math.min(fovMin, s.fov), math.max(fovMax, s.fov)
		local camRoll = math.deg(math.asin(math.clamp(s.camera.RightVector.Y, -1, 1)))
		maxCamRoll = math.max(maxCamRoll, math.abs(camRoll))
		if s.scopeCF then
			live += 1
			local a = angle(s.scopeCF.LookVector, s.camera.LookVector)
			maxAxisDeg = math.max(maxAxisDeg, a)
			lastAxisDeg = a
			-- roll of the scope image vs the camera: angle between up vectors after removing the axis difference
			local upS = s.scopeCF.UpVector
			local upC = s.camera.UpVector
			maxRollDiff = math.max(maxRollDiff, angle(upS, upC))
			maxPosOff = math.max(maxPosOff, (s.scopeCF.Position - s.camera.Position).Magnitude)
			local ls = lensOnScreen(s, vp)
			if ls then
				local off = math.sqrt(ls.x * ls.x + ls.y * ls.y)
				maxLensOff = math.max(maxLensOff, off)
				endLensOff = off
			end
		end
		if s.opticState == "SCOPED" then
			scoped += 1
		end
	end
	if opts.crouch ~= nil then
		move("crouch", false)
		frames(0.5)
	end
	if opts.aim ~= false then
		weapon("aim", false)
		frames(0.3)
	end
	return {
		frames = n,
		liveFrames = live,
		scopedFrames = scoped,
		maxScopeVsCameraDeg = r3(maxAxisDeg),
		endScopeVsCameraDeg = r3(lastAxisDeg),
		maxScopeUpVsCameraUpDeg = r3(maxRollDiff),
		maxScopeCameraOffset = r3(maxPosOff),
		maxCameraRollDeg = r3(maxCamRoll),
		maxLensOffsetH = r3(maxLensOff), -- lens centre off the screen centre, in screen heights
		endLensOffsetH = r3(endLensOff),
		fov = { r3(fovMin), r3(fovMax) },
		currentCameraIsScope = workspace.CurrentCamera.Name == "ScopeCamera",
		maxWalkSpeed = r3(maxSpeed),
		eyeY = { r3(minEyeY), r3(maxEyeY) },
		movementRecorded = mlog ~= nil,
	}
end

-- n trigger presses `gap` seconds apart (semi-automatic: one shot per press), optionally scoped.
function Run.fire(n: number, gap: number?, aim: boolean?): any
	if aim ~= false then
		weapon("aim", true)
		frames(0.6)
	end
	weapon("sync")
	frames(0.3)
	local before = weapon("state")
	weapon("record", true)
	frames(0.1)
	local pressAt = {}
	for _ = 1, n do
		table.insert(pressAt, os.clock())
		weapon("trigger", true)
		frames(0.05)
		weapon("trigger", false)
		frames(math.max(0, (gap or 0.5) - 0.05))
	end
	frames(0.6)
	local rec = weapon("record", false)
	weapon("sync")
	frames(0.3)
	local after = weapon("state")
	local log, shots = rec.log, rec.shots
	local vp = workspace.CurrentCamera.ViewportSize
	-- per shot: lens kick (ring size / position) on the following frames and recovery time; shot direction vs camera
	local kicks = {}
	for _, t in shots do
		local base, peak, back = nil, nil, nil
		local peakRing, peakDy, baseRing, baseY = 0, 0, 0, 0
		for i, s in log do
			local ls = lensOnScreen(s, vp)
			if ls then
				if s.t < t then
					base = s
					baseRing, baseY = ls.ringD, ls.y
				elseif s.t - t <= 0.35 then
					if ls.ringD > peakRing then
						peakRing, peakDy, peak = ls.ringD, ls.y - baseY, s
					end
					if not back and peak and s.t > peak.t and math.abs(ls.ringD - baseRing) < 0.01 * baseRing
						and math.abs(ls.y - baseY) < 0.005 then
						back = s
					end
				end
			end
		end
		local sh = nil
		for _, s in log do
			if s.t >= t and s.shadow then
				sh = s.shadow
				break
			end
		end
		table.insert(kicks, {
			ringGrowth = if baseRing > 0 then r3(peakRing / baseRing) else nil,
			peakDyH = r3(peakDy),
			peakAfter = if peak then r3(peak.t - t) else nil,
			backAfter = if back then r3(back.t - t) else nil,
			shadowAfterShot = if sh then { r3(sh[1]), r3(sh[2]), r3(sh[3]) } else nil,
		})
	end
	local climb = {}
	for _, s in log do
		table.insert(climb, s.climb)
	end
	local maxClimb = 0
	for _, c in climb do
		maxClimb = math.max(maxClimb, c)
	end
	if aim ~= false then
		weapon("aim", false)
		frames(0.3)
	end
	return {
		presses = n,
		shots = #shots,
		magBefore = before.mag, magAfter = after.mag,
		acceptedDelta = if before.server and after.server then (after.server.Accepted or 0) - (before.server.Accepted or 0) else nil,
		rejectedDelta = if before.server and after.server then (after.server.Rejected or 0) - (before.server.Rejected or 0) else nil,
		maxClimbDeg = r3(maxClimb),
		kicks = kicks,
		fovs = { r3(log[1] and log[1].fov), r3(log[#log] and log[#log].fov) },
	}
end

-- Security: forged WeaponFire calls. Returns the server's Accepted / Rejected change for each attempt.
function Run.forge(kind: string): any
	local Remotes = ReplicatedStorage.Shared.Remotes
	local WeaponFire = Remotes:WaitForChild("WeaponFire") :: RemoteEvent
	weapon("sync") -- the server answers with its Accepted / Rejected counters
	frames(0.3)
	local before = weapon("state").server
	local cam = workspace.CurrentCamera
	local head = (player.Character :: Model):FindFirstChild("Head") :: BasePart
	local look = cam.CFrame.LookVector
	if kind == "farOrigin" then -- shot origin 40 studs from the head (e.g. "from the scope's view point")
		WeaponFire:FireServer("ScopeTest", head.Position + look * 40, look)
	elseif kind == "fakeHit" then -- extra arguments: a hit position and a target (the server takes neither)
		local bot = workspace.OpticsTest.Bots:FindFirstChild("OPT_DISTANT") :: Model?
		local tgt = bot and bot:FindFirstChild("Head") :: BasePart?
		WeaponFire:FireServer("ScopeTest", head.Position, Vector3.new(0, -1, 0.0001), tgt and tgt.Position, tgt, "Head")
	elseif kind == "behind" then -- direction behind the shooter
		WeaponFire:FireServer("ScopeTest", head.Position, -look)
	elseif kind == "nan" then
		WeaponFire:FireServer("ScopeTest", head.Position, Vector3.new(0 / 0, 0, 1))
	elseif kind == "rate" then -- 6 shots in one frame (cap 600 RPM, burst allowance 3)
		for _ = 1, 6 do
			WeaponFire:FireServer("ScopeTest", head.Position, look)
		end
	elseif kind == "wrongWeapon" then -- a production weapon that is not equipped on the server
		WeaponFire:FireServer("AK", head.Position, look)
	elseif kind == "opticArgs" then -- the optic's own view (scope camera) as origin / direction: no such channel exists
		WeaponFire:FireServer("ScopeTest", head.Position, look, { scopeCamera = cam.CFrame, magnification = 99 })
	end
	frames(0.6)
	weapon("sync")
	frames(0.3)
	local after = weapon("state").server
	return {
		kind = kind,
		accepted = if after and before then (after.Accepted or 0) - (before.Accepted or 0) else nil,
		rejected = if after and before then (after.Rejected or 0) - (before.Rejected or 0) else nil,
	}
end

-- The left arm holds the handguard grip in every aim state (no firing): hand end vs the weapon's HandGrip point.
function Run.attach(): any
	weapon("aim", false)
	frames(0.4)
	weapon("record", true)
	frames(0.1)
	weapon("aim", true)
	frames(0.6)
	weapon("aim", false)
	frames(0.4)
	local log = weapon("record", false).log
	local data = require(ReplicatedStorage.Shared.Assets.Weapons.M4ViewmodelData) :: any
	local g = data.Points.HandGrip
	local grip = Vector3.new(g[1], g[2], g[3])
	local len = 0
	for _, p in data.Parts do
		if p.Name == "LeftArm" then
			len = p.Size[3]
		end
	end
	local maxD, states = 0, {}
	for _, s in log do
		local hand = s.arm * Vector3.new(0, 0, -len)
		maxD = math.max(maxD, (hand - s.weapon * grip).Magnitude)
		local st = s.opticState or "?"
		states[st] = (states[st] or 0) + 1
	end
	return { frames = #log, maxHandToGripStuds = maxD, states = states }
end

function Run.perf(seconds: number, aim: boolean): any
	weapon("aim", aim)
	frames(0.6)
	weapon("record", true)
	local dts = {}
	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function(dt)
		table.insert(dts, dt)
	end)
	frames(seconds)
	conn:Disconnect()
	local log = weapon("record", false).log
	local optic, mirror, nO, nM, maxO, maxM = 0, 0, 0, 0, 0, 0
	for _, s in log do
		if s.opticMs then
			optic += s.opticMs
			nO += 1
			maxO = math.max(maxO, s.opticMs)
		end
		if s.mirrorMs then
			mirror += s.mirrorMs
			nM += 1
			maxM = math.max(maxM, s.mirrorMs)
		end
	end
	table.sort(dts)
	local sum = 0
	for _, d in dts do
		sum += d
	end
	local d = weapon("optic", "ScopeTest")
	local st: any = {}
	pcall(function()
		st.memoryMb = r3(Stats:GetTotalMemoryUsageMb())
		st.graphicsMb = r3(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.GraphicsTexture))
		st.guiMb = r3(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Gui))
		st.instances = Stats.InstanceCount
	end)
	local gui = player.PlayerGui:FindFirstChild("ScopeTestOptic")
	local mirrorCount = 0
	if gui then
		local wm = gui:FindFirstChild("Mirror", true)
		mirrorCount = if wm then #wm:GetChildren() else 0
	end
	weapon("aim", false)
	return {
		aim = aim,
		frames = #dts,
		meanFrameMs = r3(sum / math.max(1, #dts) * 1000),
		p95FrameMs = r3((dts[math.max(1, math.floor(#dts * 0.95))] or 0) * 1000),
		opticMeanMs = r3(optic / math.max(1, nO)),
		opticMaxMs = r3(maxO),
		mirrorMeanMs = r3(mirror / math.max(1, nM)),
		mirrorMaxMs = r3(maxM),
		mirror = d.mirror,
		mirrorInstances = mirrorCount,
		stats = st,
		elapsed = r3(os.clock() - t0),
	}
end

return Run
