--!strict
-- Focused MP7 test, client side (Studio only; delete the MP7Test folders to remove it). Driven through execute_luau
-- (Client datamodel): require(PlayerScripts.MP7Test.Run).<fn>(...). The server half is ServerScriptService.MP7Test.Run;
-- the range is Workspace.MP7Test. Reads the running game only through its Studio debug hooks
-- (Client.WeaponController ProductionWeaponDebug, Client.Movement MovementClientDebug).
--   Run.equip(id)                     equip a weapon; viewmodels, HUD, FOV, server state
--   Run.look(point)                   point the camera at a world point
--   Run.idle(seconds)                 camera / viewmodel stillness (Regular or Stressed, as set)
--   Run.burst(seconds, opts)          hold the trigger: shots, cadence, server accept / reject, ammunition, recoil
--                                     statistics sampled at 30 fps the way the footage was measured
--   Run.tap()                         one short press (single shot)
--   Run.ads(inHold, outHold)          aim in / out: times, FOV, sight line vs the camera axis
--   Run.reload(ammo, stressed)        a reload from a set ammunition state: clip, timing, HUD label, ammunition after
--   Run.track(opts)                   movement with the MP7 out (walk / crouch / jump / turn): speed, eye, lag, roll
--   Run.forge(kind)                   forged remote calls (security)
--   Run.perf(seconds, firing)         frame cost, effect pool use, instances

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

local function project(cam: CFrame, fov: number, vp: Vector2, p: Vector3): Vector2
	local l = cam:PointToObjectSpace(p)
	local f = (vp.Y / 2) / math.tan(math.rad(fov) / 2)
	return Vector2.new(vp.X / 2 + l.X / -l.Z * f, vp.Y / 2 - l.Y / -l.Z * f)
end

local function median(t: { number }): number?
	if #t == 0 then
		return nil
	end
	local c = table.clone(t)
	table.sort(c)
	return c[#c // 2 + 1]
end

local function sd(t: { number }): number?
	if #t < 2 then
		return nil
	end
	local m = 0
	for _, v in t do
		m += v
	end
	m /= #t
	local s = 0
	for _, v in t do
		s += (v - m) ^ 2
	end
	return math.sqrt(s / (#t - 1))
end

-- Resample a log at 30 fps (the footage's rate): the last sample at or before each 1/30 s tick.
local function at30(log: { any }, t0: number, t1: number): { any }
	local out = {}
	local i = 1
	local t = t0
	while t <= t1 do
		while i < #log and log[i + 1].t <= t do
			i += 1
		end
		table.insert(out, log[i])
		t += 1 / 30
	end
	return out
end

function Run.state(): any
	return weapon("state")
end

function Run.equip(id: string): any
	player:SetAttribute("EquippedWeapon", id)
	frames(0.6)
	weapon("sync")
	frames(0.3)
	local st = weapon("state")
	local cam = workspace.CurrentCamera
	local vms = {}
	for _, c in cam:GetChildren() do
		if string.sub(c.Name, -9) == "Viewmodel" then
			table.insert(vms, c.Name)
		end
	end
	local parts = {}
	local vm = cam:FindFirstChild(id .. "Viewmodel")
	if vm then
		for _, p in vm:GetChildren() do
			table.insert(parts, p.Name)
		end
	end
	table.sort(parts)
	local huds = {}
	for _, g in player.PlayerGui:GetChildren() do
		if string.sub(g.Name, -3) == "Hud" and g:IsA("ScreenGui") then
			local l = g:FindFirstChild("MagazineLabel") :: TextLabel?
			huds[g.Name] = { enabled = g.Enabled, labelVisible = if l then l.Visible else nil, text = if l then l.Text else nil }
		end
	end
	return {
		equipped = player:GetAttribute("EquippedWeapon"),
		viewmodels = vms,
		parts = parts,
		cameraFov = r3(cam.FieldOfView),
		huds = huds,
		mag = st.mag, chambered = st.chambered, reserve = st.reserve,
		server = st.server and { weapon = st.server.Weapon, mag = st.server.Mag, chambered = st.server.Chambered,
			reserve = st.server.Reserve, reason = st.server.Reason },
		weaponId = st.weapon, active = st.active,
	}
end

function Run.look(point: Vector3, holds: number?)
	local cam = workspace.CurrentCamera
	for _ = 1, holds or 4 do
		cam.CFrame = CFrame.lookAt(cam.CFrame.Position, point)
		frames(0.12)
	end
end

-- Stillness while idle: camera pitch / roll and the weapon relative to the camera (p-p over the window).
function Run.idle(seconds: number): any
	weapon("record", true)
	frames(seconds)
	local log = weapon("record", false).log
	local pmin, pmax, rmin, rmax = math.huge, -math.huge, math.huge, -math.huge
	local wmin, wmax = Vector3.one * math.huge, -Vector3.one * math.huge
	local vp = workspace.CurrentCamera.ViewportSize
	local mx = {}
	for _, s in log do
		local look = s.camera.LookVector
		local pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
		local roll = math.deg(math.asin(math.clamp(s.camera.RightVector.Y, -1, 1)))
		pmin, pmax = math.min(pmin, pitch), math.max(pmax, pitch)
		rmin, rmax = math.min(rmin, roll), math.max(rmax, roll)
		local rel = s.camera:PointToObjectSpace(s.muzzle)
		wmin, wmax = wmin:Min(rel), wmax:Max(rel)
		table.insert(mx, project(s.camera, s.fov, vp, s.muzzle).X)
	end
	local muzzleScreen = if #log > 0 then project(log[#log].camera, log[#log].fov, vp, log[#log].muzzle) else nil
	return {
		frames = #log,
		weapon = log[1] and log[1].weaponId,
		cameraPitchP2PDeg = r3(pmax - pmin),
		cameraRollP2PDeg = r3(rmax - rmin),
		muzzleRelP2PStuds = r3((wmax - wmin).Magnitude),
		muzzleScreen720 = if muzzleScreen then { r3((muzzleScreen.X - vp.X / 2) / vp.Y * 720 + 640), r3(muzzleScreen.Y / vp.Y * 720) } else nil,
		fov = log[1] and r3(log[1].fov),
		stressed = player:GetAttribute("Stressed") == true,
	}
end

-- Hold the trigger for `seconds`. opts: { aim = bool, refill = bool (default true), after = s (log after release) }
function Run.burst(seconds: number, opts: any?): any
	opts = opts or {}
	if opts.refill ~= false then
		weapon("refill")
		frames(0.4)
	end
	if opts.aim then
		weapon("aim", true)
		frames(0.6)
	end
	weapon("sync")
	frames(0.3)
	local before = weapon("state")
	weapon("record", true)
	frames(0.15)
	local tDown = os.clock()
	weapon("trigger", true)
	frames(seconds)
	local tUp = os.clock()
	weapon("trigger", false)
	frames(opts.after or 1.2)
	local rec = weapon("record", false)
	weapon("sync")
	frames(0.4)
	local after = weapon("state")
	if opts.aim then
		weapon("aim", false)
		frames(0.3)
	end
	local log, shots = rec.log, rec.shots
	-- cadence
	local gaps = {}
	for i = 2, #shots do
		table.insert(gaps, shots[i] - shots[i - 1])
	end
	local span = if #shots > 1 then shots[#shots] - shots[1] else 0
	-- recoil at 30 fps from the first shot to `after`
	local first = shots[1] or tDown
	local lastShot = shots[#shots] or tUp
	local s30 = at30(log, first - 3 / 30, log[#log].t)
	local vp = workspace.CurrentCamera.ViewportSize
	local base = s30[1]
	local pitchSeries, rollIn, dPitch, dMuzzleX = {}, {}, {}, {}
	local prevP, prevMx = nil, nil
	local endClimb, peakClimb = 0, 0
	for _, s in s30 do
		local p = s.climb + s.shake.X -- visible camera pitch above the pre-burst view (deg)
		table.insert(pitchSeries, r3(p))
		local mxp = project(s.camera, s.fov, vp, s.muzzle)
		local mx = mxp.X / vp.Y * 720 -- in 720-p pixels (the footage is 1280 x 720)
		if s.t >= first and s.t <= lastShot then
			table.insert(rollIn, s.shake.Z)
			if prevP then
				table.insert(dPitch, math.abs(p - prevP))
				table.insert(dMuzzleX, math.abs(mx - prevMx))
			end
			endClimb = s.climb
		end
		peakClimb = math.max(peakClimb, s.climb)
		prevP, prevMx = p, mx
	end
	-- climb 26 frames (0.867 s) after the last shot (burst D: 4.25 -> ~2.1 deg)
	local climbAfter = nil
	for _, s in log do
		if s.t >= lastShot + 26 / 30 then
			climbAfter = s.climb
			break
		end
	end
	local recoveredAt = nil
	for _, s in log do
		if s.t > lastShot and s.climb <= 0.05 then
			recoveredAt = s.t - lastShot
			break
		end
	end
	local envMax = 0
	for _, s in log do
		envMax = math.max(envMax, s.env)
	end
	return {
		held = r3(tUp - tDown),
		shots = #shots,
		rpmFromSpan = if span > 0 then r3((#shots - 1) / span * 60) else nil,
		medianGapMs = r3((median(gaps) or 0) * 1000),
		maxGapMs = r3(if #gaps > 0 then math.max(table.unpack(gaps)) * 1000 else 0),
		firstShotDelayMs = r3((first - tDown) * 1000),
		magBefore = before.mag, chamberedBefore = before.chambered, magAfter = after.mag, chamberedAfter = after.chambered,
		serverMagAfter = after.server and after.server.Mag,
		acceptedDelta = if before.server and after.server then (after.server.Accepted or 0) - (before.server.Accepted or 0) else nil,
		rejectedDelta = if before.server and after.server then (after.server.Rejected or 0) - (before.server.Rejected or 0) else nil,
		climbEndOfBurstDeg = r3(endClimb),
		climbPeakDeg = r3(peakClimb),
		climb26FramesAfterDeg = r3(climbAfter),
		recoveredAfterS = r3(recoveredAt),
		shakeMedianAbsDeltaPitchDeg30fps = r3(median(dPitch)),
		rollSdDeg = r3(sd(rollIn)),
		muzzleMedianAbsDeltaX720 = r3(median(dMuzzleX)), -- footage: top point |dx| median 13 px (D), 1-4 idle (1280 x 720)
		envelopeMax = r3(envMax),
		pitchSeries30 = if opts.series then pitchSeries else nil,
		base = base and r3(base.climb),
	}
end

function Run.tap(): any
	weapon("sync")
	frames(0.3)
	local before = weapon("state")
	weapon("record", true)
	weapon("trigger", true)
	frames(0.03)
	weapon("trigger", false)
	frames(0.5)
	local rec = weapon("record", false)
	weapon("sync")
	frames(0.3)
	local after = weapon("state")
	return {
		shots = #rec.shots,
		magBefore = before.mag, magAfter = after.mag,
		acceptedDelta = if before.server and after.server then (after.server.Accepted or 0) - (before.server.Accepted or 0) else nil,
		rejectedDelta = if before.server and after.server then (after.server.Rejected or 0) - (before.server.Rejected or 0) else nil,
	}
end

-- Aim in / out. The MP7 ADS is a PLACEHOLDER posture (the footage never aims): measures the transition and whether the
-- iron-sight line (rear notch -> front post) lies on the camera axis when aimed.
function Run.ads(inHold: number?, outHold: number?): any
	weapon("aim", false)
	frames(0.5)
	weapon("record", true)
	frames(0.1)
	local tIn = os.clock()
	weapon("aim", true)
	frames(inHold or 0.8)
	local tOut = os.clock()
	weapon("aim", false)
	frames(outHold or 0.6)
	local log = weapon("record", false).log
	local data = require(ReplicatedStorage.Shared.Assets.Weapons.MP7ViewmodelData) :: any
	local rn, fp = data.Points.RearNotch, data.Points.FrontPostTip
	local rear, front = Vector3.new(rn[1], rn[2], rn[3]), Vector3.new(fp[1], fp[2], fp[3])
	local inT, outT, fovMin, fovMax = nil, nil, math.huge, -math.huge
	local sightDeg, sightCentrePx = nil, nil
	local vp = workspace.CurrentCamera.ViewportSize
	for _, s in log do
		fovMin, fovMax = math.min(fovMin, s.fov), math.max(fovMax, s.fov)
		if s.t >= tIn and s.t < tOut and s.aim >= 0.999 and not inT then
			inT = s.t - tIn
		end
		if s.t >= tOut and s.aim <= 0.001 and not outT then
			outT = s.t - tOut
		end
		if s.t < tOut and s.aim >= 0.999 then
			local r = s.weapon * rear
			local f = s.weapon * front
			local line = (f - r).Unit
			sightDeg = math.deg(math.acos(math.clamp(line:Dot(s.camera.LookVector), -1, 1)))
			local fpx = project(s.camera, s.fov, vp, f)
			sightCentrePx = { r3(fpx.X - vp.X / 2), r3(fpx.Y - vp.Y / 2) }
		end
	end
	return {
		inTime = r3(inT), outTime = r3(outT), fov = { r3(fovMin), r3(fovMax) },
		sightLineVsCameraDeg = r3(sightDeg), frontPostFromCentrePx = sightCentrePx, frames = #log,
	}
end

-- A reload from a given server ammunition state. ammo = { Mag, Chambered, Reserve, Dropped? }; stressed = Stressed mode.
function Run.reload(ammo: any, stressed: boolean?): any
	weapon("stressed", stressed == true)
	frames(0.3)
	weapon("setAmmo", ammo)
	frames(0.5)
	weapon("sync")
	frames(0.3)
	local before = weapon("state")
	weapon("record", true)
	frames(0.1)
	local t0 = os.clock()
	local res = weapon("reload")
	local labels = {}
	local lastText = before.hud and before.hud.text
	local swapAt, chamberAt, doneAt = nil, nil, nil
	local maxWeaponMove, maxArmMove, maxMagMove, maxChMove = 0, 0, 0, 0
	local restW, restA = nil, nil
	while os.clock() - t0 < 6.5 do
		RunService.RenderStepped:Wait()
		local st = weapon("state")
		local txt = st.hud and st.hud.text
		if txt ~= lastText then
			table.insert(labels, { t = r3(os.clock() - t0), text = txt })
			lastText = txt
		end
		if st.reloadSwapped and not swapAt then
			swapAt = os.clock() - t0
		end
		if st.chambered and not before.chambered and not chamberAt and st.reloadSwapped then
			chamberAt = os.clock() - t0
		end
		if not st.reloading and not doneAt then
			doneAt = os.clock() - t0
		end
		if doneAt and os.clock() - t0 > doneAt + 0.4 then
			break
		end
	end
	local log = weapon("record", false).log
	local restM, restC = nil, nil
	for _, s in log do
		if s.t < t0 then
			restW, restA = s.camera:ToObjectSpace(s.weapon), s.camera:ToObjectSpace(s.arm)
			restM, restC = s.weapon:ToObjectSpace(s.magazine), s.weapon:ToObjectSpace(s.chargingHandle)
		elseif restW and s.reloadT then
			local w = s.camera:ToObjectSpace(s.weapon)
			maxWeaponMove = math.max(maxWeaponMove, (w.Position - restW.Position).Magnitude)
			maxArmMove = math.max(maxArmMove, (s.camera:ToObjectSpace(s.arm).Position - restA.Position).Magnitude)
			local magRel = s.weapon:ToObjectSpace(s.magazine)
			maxMagMove = math.max(maxMagMove, (magRel.Position - restM.Position).Magnitude)
			local chRel = s.weapon:ToObjectSpace(s.chargingHandle)
			maxChMove = math.max(maxChMove, (chRel.Position - restC.Position).Magnitude)
		end
	end
	-- end pose: weapon vs rest after the clip
	local endW = log[#log] and log[#log].camera:ToObjectSpace(log[#log].weapon)
	weapon("sync")
	frames(0.3)
	local after = weapon("state")
	weapon("stressed", false)
	return {
		spec = res and res.result,
		clientDone = r3(doneAt), lastReload = after.lastReload,
		clientSwapAt = r3(swapAt), clientChamberAt = r3(chamberAt),
		labels = labels,
		before = { mag = before.mag, chambered = before.chambered, reserve = before.reserve, dropped = before.dropped },
		after = { mag = after.mag, chambered = after.chambered, reserve = after.reserve, dropped = after.dropped,
			server = after.server and { mag = after.server.Mag, chambered = after.server.Chambered, reserve = after.server.Reserve,
				dropped = after.server.Dropped, reason = after.server.Reason } },
		maxWeaponMoveStuds = r3(maxWeaponMove), maxArmMoveStuds = r3(maxArmMove),
		maxMagazineOffsetStuds = r3(maxMagMove), maxChargingOffsetStuds = r3(maxChMove),
		endPoseOffsetStuds = if endW and restW then r3((endW.Position - restW.Position).Magnitude) else nil,
		endPoseAngleDeg = if endW and restW then r3(math.deg(math.acos(math.clamp(endW.LookVector:Dot(restW.LookVector), -1, 1)))) else nil,
	}
end

-- Movement with the MP7 out. opts: { rate = deg/s turn, seconds, move = Vector3?, crouch = bool?, jump = bool?, aim = bool? }
function Run.track(opts: any): any
	local rate = opts.rate or 0
	local turning = false
	RunService:BindToRenderStep("MP7TestTurn", Enum.RenderPriority.Camera.Value - 2, function(dt: number)
		if not turning then
			return
		end
		local cam = workspace.CurrentCamera
		local p = cam.CFrame.Position
		cam.CFrame = CFrame.new(p) * CFrame.Angles(0, -math.rad(rate) * dt, 0) * cam.CFrame.Rotation
	end)
	if opts.aim then
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
	local mlog = move("record", false) or {}
	RunService:UnbindFromRenderStep("MP7TestTurn")
	local maxSpeed, minEye, maxEye, maxRoll, maxLag = 0, math.huge, -math.huge, 0, 0
	for i, s in mlog do
		minEye, maxEye = math.min(minEye, s.eyeAboveFeet), math.max(maxEye, s.eyeAboveFeet)
		maxRoll = math.max(maxRoll, math.abs(s.roll or 0)) -- MovementPresentation keeps Roll / Lag* in degrees
		maxLag = math.max(maxLag, math.sqrt((s.lagYaw or 0) ^ 2 + (s.lagPitch or 0) ^ 2))
		for j = i - 1, 1, -1 do
			local q = mlog[j]
			if s.t - q.t >= 0.25 then
				local d = s.root - q.root
				maxSpeed = math.max(maxSpeed, Vector3.new(d.X, 0, d.Z).Magnitude / (s.t - q.t))
				break
			end
		end
	end
	local minY, maxY = math.huge, -math.huge
	-- weapon lag as seen on the viewmodel: angle between the weapon's forward and the camera's forward vs at rest
	local rest = log[1] and log[1].camera:ToObjectSpace(log[1].weapon)
	local maxVmDeg = 0
	for _, s in log do
		minY, maxY = math.min(minY, s.camera.Position.Y), math.max(maxY, s.camera.Position.Y)
		if rest then
			local rel = s.camera:ToObjectSpace(s.weapon)
			maxVmDeg = math.max(maxVmDeg, math.deg(math.acos(math.clamp(rel.LookVector:Dot(rest.LookVector), -1, 1))))
		end
	end
	if opts.crouch ~= nil then
		move("crouch", false)
		frames(0.5)
	end
	if opts.aim then
		weapon("aim", false)
		frames(0.3)
	end
	local st = move("state")
	return {
		frames = #log, movementFrames = #mlog,
		weaponId = log[1] and log[1].weaponId,
		maxWalkSpeed = r3(maxSpeed),
		eyeAboveFeet = { r3(minEye), r3(maxEye) },
		cameraY = { r3(minY), r3(maxY) },
		maxCameraRollDeg = r3(maxRoll),
		maxLagDeg = r3(maxLag),
		maxViewmodelAngleDeg = r3(maxVmDeg),
		stance = st and st.predicted,
	}
end

-- Security: forged WeaponFire / WeaponCommand calls with the MP7. Returns the server's Accepted / Rejected changes
-- and its ammunition before / after.
function Run.forge(kind: string): any
	local Remotes = ReplicatedStorage.Shared.Remotes
	local WeaponFire = Remotes:WaitForChild("WeaponFire") :: RemoteEvent
	local WeaponCommand = Remotes:WaitForChild("WeaponCommand") :: RemoteEvent
	weapon("sync")
	frames(0.3)
	local before = weapon("state").server
	local cam = workspace.CurrentCamera
	local c = player.Character
	local head = c and c:FindFirstChild("Head") :: BasePart?
	local hp = if head then head.Position else cam.CFrame.Position
	local look = cam.CFrame.LookVector
	local bots = workspace.MP7Test.Bots
	if kind == "farOrigin" then -- origin 40 studs ahead (next to a target)
		WeaponFire:FireServer("MP7", hp + look * 40, look)
	elseif kind == "wallOrigin" then -- origin behind the solid wall (a few studs, within the offset limit? no: 24 studs)
		WeaponFire:FireServer("MP7", Vector3.new(462, 4.5, -303), Vector3.new(0, 0, 1))
	elseif kind == "behind" then
		WeaponFire:FireServer("MP7", hp, -look)
	elseif kind == "nan" then
		WeaponFire:FireServer("MP7", hp, Vector3.new(0 / 0, 0, 1))
	elseif kind == "zero" then
		WeaponFire:FireServer("MP7", hp, Vector3.zero)
	elseif kind == "fakeHit" then -- extra arguments: hit position, target part, "Head"; direction straight down
		local bot = bots:FindFirstChild("MP7_DISTANT") :: Model?
		local tgt = bot and bot:FindFirstChild("Head") :: BasePart?
		WeaponFire:FireServer("MP7", hp, Vector3.new(0, -1, 0.0001), tgt and tgt.Position, tgt, "Head", { hit = tgt and tgt.Position, damage = 999 })
	elseif kind == "rate" then -- 12 shots in one frame (cap 950 RPM, burst allowance 3)
		for _ = 1, 12 do
			WeaponFire:FireServer("MP7", hp, look)
		end
	elseif kind == "rateSustained" then -- 2000 RPM for 1 s
		for _ = 1, 33 do
			WeaponFire:FireServer("MP7", hp, look)
			frames(0.03)
		end
	elseif kind == "wrongWeapon" then -- the AK while the MP7 is equipped
		WeaponFire:FireServer("AK", hp, look)
	elseif kind == "unknownWeapon" then
		WeaponFire:FireServer("MP7_GOLD", hp, look)
	elseif kind == "ammo" then -- client claims ammunition: DevSetAmmo is Studio-only; a fake command / table is ignored
		WeaponCommand:FireServer("SetAmmo", { Mag = 999, Chambered = true, Reserve = { 999 } })
		WeaponCommand:FireServer("ReloadDone")
		WeaponCommand:FireServer("ReloadSwapped")
	elseif kind == "badTypes" then
		WeaponFire:FireServer({ "MP7" }, "origin", 42)
	end
	frames(0.6)
	weapon("sync")
	frames(0.3)
	local after = weapon("state").server
	return {
		kind = kind,
		accepted = if after and before then (after.Accepted or 0) - (before.Accepted or 0) else nil,
		rejected = if after and before then (after.Rejected or 0) - (before.Rejected or 0) else nil,
		serverMag = { before and before.Mag, after and after.Mag },
		serverReserve = after and after.Reserve,
	}
end

-- Raw single remote shot (security tests that need exact control): origin / direction as given.
function Run.rawShot(id: string, origin: Vector3, dir: Vector3): any
	local WeaponFire = ReplicatedStorage.Shared.Remotes:WaitForChild("WeaponFire") :: RemoteEvent
	weapon("sync")
	frames(0.3)
	local before = weapon("state").server
	WeaponFire:FireServer(id, origin, dir)
	frames(0.5)
	weapon("sync")
	frames(0.3)
	local after = weapon("state").server
	return {
		accepted = if after and before then (after.Accepted or 0) - (before.Accepted or 0) else nil,
		rejected = if after and before then (after.Rejected or 0) - (before.Rejected or 0) else nil,
	}
end

-- Effects folder of the equipped weapon: pooled parts, how many are visible now.
local function effectsInfo(): any
	local cam = workspace.CurrentCamera
	local out = { folders = 0, parts = 0, visible = 0 }
	for _, f in cam:GetChildren() do
		if f.Name == "ProductionWeaponEffects" then
			out.folders += 1
			for _, p in f:GetDescendants() do
				if p:IsA("BasePart") then
					out.parts += 1
					if p.Position.Y > -5000 then
						out.visible += 1
					end
				end
			end
		end
	end
	return out
end
Run.effectsInfo = effectsInfo

function Run.perf(seconds: number, firing: boolean): any
	weapon("refill")
	frames(0.4)
	local inst0 = Stats.InstanceCount
	local dts = {}
	local maxVisible = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		table.insert(dts, dt)
	end)
	if firing then
		weapon("trigger", true)
	end
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
		maxVisible = math.max(maxVisible, effectsInfo().visible)
	end
	weapon("trigger", false)
	conn:Disconnect()
	frames(0.6)
	local inst1 = Stats.InstanceCount
	table.sort(dts)
	local sum = 0
	for _, d in dts do
		sum += d
	end
	local st: any = {}
	pcall(function()
		st.memoryMb = r3(Stats:GetTotalMemoryUsageMb())
		st.dataSendKbps = r3(Stats.DataSendKbps)
		st.dataReceiveKbps = r3(Stats.DataReceiveKbps)
	end)
	return {
		firing = firing,
		frames = #dts,
		meanFrameMs = r3(sum / math.max(1, #dts) * 1000),
		p95FrameMs = r3((dts[math.max(1, math.floor(#dts * 0.95))] or 0) * 1000),
		effects = effectsInfo(),
		maxVisibleEffectParts = maxVisible,
		instancesBefore = inst0, instancesAfter = inst1,
		stats = st,
	}
end

return Run
