--!strict
-- Focused Sniper test, client side (Studio only; delete the SniperTest folders to remove it). Driven through execute_luau
-- (Client datamodel): require(PlayerScripts.SniperTest.Run).<fn>(...). Generic helpers come from the MP7 test
-- (PlayerScripts.MP7Test.Run: equip / look / idle / reload / track / perf / tap); this module adds what is Sniper-specific.
-- The range is Workspace.MP7Test (reused); the server half is ServerScriptService.SniperTest.Run.
-- Measurements use the footage's own definitions (ReferenceAnalysis/Sniper/tools/sniper_recoil.py; i = the shot frame,
-- resampled at 30 fps): camera kick = pitch on i+1 minus the mean of i-1 and i-2; residual = pitch on i+6 / i+30.
--   Run.shots(n, gap, opts)      n presses gap s apart: shots, cadence, server accept / reject, ammunition, camera kick,
--                                residual climb, hip muzzle / eyepiece motion or the scoped lens (ring) motion per frame
--   Run.hold(seconds)            trigger held: one shot
--   Run.cycle(aim)               one shot: bolt (lift / stroke), right arm on screen, casing, chamber (client / server),
--                                next shot availability, per 30-fps frame
--   Run.empty()                  5 + 1 -> 0: the last round's cycle, blocked trigger, server state
--   Run.ads()                    scope in / out: times, main FOV, lens size / place, magnification, reticle, lens layer
--   Run.zoom()                   zoom steps (wrap), magnification, reticle scale, label, persistence across ADS
--   Run.check()                  the rounds check: timing, panel text / alpha / place, blocks
--   Run.switchCycle(ids, n)      switching: viewmodels, effects, instances, reset state (incl. bolt / zoom / scope)
--   Run.switchDuringCycle(other) fire, switch away mid-cycle and back: presentation reset, cycle kept, next shot time
--   Run.forge(kind)              forged remote calls with the Sniper (security)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local Base = require(script.Parent.Parent:WaitForChild("MP7Test"):WaitForChild("Run")) :: any
local Run = setmetatable({}, { __index = Base }) :: any
local weapon, frames = Base.weapon, Base.frames
local CFG = require(ReplicatedStorage.Shared.WeaponRegistry).get("Sniper") :: any
local SCOPE = require(ReplicatedStorage.Shared.Config.Optics.SniperScope) :: any
local STUD = 0.28
local LENS_R = SCOPE.Layout.LensDiameter / 2 / STUD -- studs
local RING_PER_LENS = 200 / 136 -- the footage's ring / lens width ratio
local ARM_LEN = 2.67857 -- studs (block arm length)

local function r3(v: number?): number?
	return if v then math.round(v * 1000) / 1000 else nil
end

local function project(cam: CFrame, fov: number, vp: Vector2, p: Vector3): (Vector2, number)
	local l = cam:PointToObjectSpace(p)
	local f = (vp.Y / 2) / math.tan(math.rad(fov) / 2)
	return Vector2.new(vp.X / 2 + l.X / -l.Z * f, vp.Y / 2 - l.Y / -l.Z * f), -l.Z
end

-- screen point / size in the footage's 1280 x 720 picture
local function px720(cam: CFrame, fov: number, vp: Vector2, p: Vector3): (Vector2, number)
	local s, depth = project(cam, fov, vp, p)
	local k = 720 / vp.Y
	local f720 = 360 / math.tan(math.rad(fov) / 2)
	return Vector2.new(640 + (s.X - vp.X / 2) * k, 360 + (s.Y - vp.Y / 2) * k), f720 / depth
end

local function median(t: { number }): number?
	if #t == 0 then
		return nil
	end
	local c = table.clone(t)
	table.sort(c)
	return c[#c // 2 + 1]
end

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

local function serverDelta(before: any, after: any): (number?, number?)
	if before and before.server and after and after.server then
		return (after.server.Accepted or 0) - (before.server.Accepted or 0), (after.server.Rejected or 0) - (before.server.Rejected or 0)
	end
	return nil, nil
end

local function pitchOf(s: any): number
	return s.climb + s.shake.X
end

local function lensOf(s: any, vp: Vector2): (Vector2?, number?)
	if not s.lensCF then
		return nil, nil
	end
	local c, scale = px720(s.camera, s.fov, vp, s.lensCF.Position)
	return c, 2 * LENS_R * scale * RING_PER_LENS -- ring (eyepiece) width in 720-px pixels
end

local function ensureSniper()
	if player:GetAttribute("EquippedWeapon") ~= "Sniper" then
		player:SetAttribute("EquippedWeapon", "Sniper")
		frames(0.6)
	end
end

-- n presses `gap` s apart. opts: { aim, refill (default true), hold (press length, default 0.05), after (s), ammo }
function Run.shots(n: number, gap: number, opts: any?): any
	opts = opts or {}
	ensureSniper()
	if opts.ammo then
		weapon("setAmmo", opts.ammo)
		frames(0.5)
	elseif opts.refill ~= false then
		weapon("refill")
		frames(0.4)
	end
	if opts.aim then
		weapon("aim", true)
		frames(0.8)
	end
	weapon("sync")
	frames(0.3)
	local before = weapon("state")
	weapon("record", true)
	frames(0.2)
	local hold = opts.hold or 0.05
	local tDown = os.clock()
	for i = 1, n do
		weapon("trigger", true)
		frames(hold)
		weapon("trigger", false)
		if i < n then
			frames(math.max(0, gap - hold))
		end
	end
	frames(opts.after or 1.7)
	local rec = weapon("record", false)
	weapon("sync")
	frames(0.4)
	local after = weapon("state")
	if opts.aim then
		weapon("aim", false)
		frames(0.4)
	end
	local log, shots = rec.log, rec.shots
	local gaps = {}
	for i = 2, #shots do
		table.insert(gaps, shots[i] - shots[i - 1])
	end
	local vp = workspace.CurrentCamera.ViewportSize
	local s30 = at30(log, (shots[1] or tDown) - 3 / 30, log[#log].t)
	local function idxAt(t: number): number
		for i, s in s30 do
			if s.t >= t then
				return i
			end
		end
		return #s30
	end
	local perShot = {}
	local kicks, r6s, r30s = {}, {}, {}
	for _, t in shots do
		local i = idxAt(t)
		local p0 = (pitchOf(s30[math.max(1, i - 1)]) + pitchOf(s30[math.max(1, i - 2)])) / 2
		local function rel(k: number): number?
			local s = s30[i + k]
			return if s then r3(pitchOf(s) - p0) else nil
		end
		local series = {}
		for k = 0, 9 do
			table.insert(series, rel(k))
		end
		-- weapon: hip = muzzle row and eyepiece (lens) row vs the frame before; scoped = the ring centre / width
		local w = {}
		local m0 = select(1, px720(s30[math.max(1, i - 1)].camera, s30[math.max(1, i - 1)].fov, vp, s30[math.max(1, i - 1)].muzzle))
		local e0, d0 = lensOf(s30[math.max(1, i - 1)], vp)
		for k = 0, 13 do
			local s = s30[i + k]
			if s then
				local m = select(1, px720(s.camera, s.fov, vp, s.muzzle))
				local e, d = lensOf(s, vp)
				table.insert(w, {
					k = k,
					muzzleDy = r3(m.Y - m0.Y),
					eyeDx = if e and e0 then r3(e.X - e0.X) else nil,
					eyeDy = if e and e0 then r3(e.Y - e0.Y) else nil,
					ringScale = if d and d0 then r3(d / d0) else nil,
				})
			end
		end
		table.insert(perShot, { kickSeries = series, weapon = w })
		table.insert(kicks, rel(1) or 0)
		table.insert(r6s, rel(6) or 0)
		table.insert(r30s, rel(30) or 0)
	end
	local acc, rej = serverDelta(before, after)
	local e0, d0 = lensOf(s30[1], vp)
	return {
		presses = n, shots = #shots,
		minGapMs = r3(if #gaps > 0 then math.min(table.unpack(gaps)) * 1000 else nil),
		medianGapMs = r3((median(gaps) or 0) * 1000),
		magBefore = before.mag, chamberedBefore = before.chambered, magAfter = after.mag, chamberedAfter = after.chambered,
		serverMagAfter = after.server and after.server.Mag, serverChamberedAfter = after.server and after.server.Chambered,
		acceptedDelta = acc, rejectedDelta = rej,
		kickMedianDeg = r3(median(kicks)), residual6MedianDeg = r3(median(r6s)), residual30MedianDeg = r3(median(r30s)),
		climbEndDeg = r3(log[#log].climb),
		restRing = if e0 then { x = r3(e0.X), y = r3(e0.Y), width = r3(d0) } else nil,
		perShot = perShot,
		aimed = opts.aim == true,
	}
end

-- Trigger held down: one shot (one shot per trigger activation; a bolt gun can't fire again until the cycle ends).
function Run.hold(seconds: number): any
	ensureSniper()
	weapon("refill")
	frames(0.4)
	weapon("sync")
	frames(0.3)
	local before = weapon("state")
	weapon("record", true)
	weapon("trigger", true)
	frames(seconds)
	weapon("trigger", false)
	frames(0.4)
	local rec = weapon("record", false)
	weapon("sync")
	frames(0.3)
	local after = weapon("state")
	local acc, rej = serverDelta(before, after)
	return { held = seconds, shots = #rec.shots, magBefore = before.mag, magAfter = after.mag, acceptedDelta = acc, rejectedDelta = rej }
end

-- One shot and the whole cycle, per 30-fps frame: bolt lift (deg) / stroke (studs), right hand on screen, the casing,
-- chambered (client prediction), plus the server's chamber and the next-shot time.
function Run.cycle(aim: boolean?): any
	ensureSniper()
	weapon("refill")
	frames(0.4)
	if aim then
		weapon("aim", true)
		frames(0.8)
	end
	weapon("record", true)
	frames(0.15)
	weapon("trigger", true)
	frames(0.05)
	weapon("trigger", false)
	local serverChamberAt = nil
	local t0 = os.clock()
	while os.clock() - t0 < 1.9 do
		frames(0.03)
		local st = weapon("state")
		if not serverChamberAt and st.server and st.server.Reason == "BoltChambered" then
			serverChamberAt = os.clock()
		end
	end
	local rec = weapon("record", false)
	local st = weapon("state")
	if aim then
		weapon("aim", false)
		frames(0.4)
	end
	local t = rec.shots[1]
	if not t then
		return { shots = 0 }
	end
	local vp = workspace.CurrentCamera.ViewportSize
	local series = {}
	local ejectAt, chamberAt, handIn, handOut = nil, nil, nil, nil
	for _, s in rec.log do
		if s.t >= t then
			if s.eject and not ejectAt then
				ejectAt = s.t - t
			end
			if s.chamberedPredicted and not chamberAt then
				chamberAt = s.t - t
			end
		end
	end
	for k, s in at30(rec.log, t, t + 48 / 30) do
		local rel = s.weapon:ToObjectSpace(s.chargingHandle)
		local _, _, rz = rel:ToEulerAnglesXYZ()
		local hand = s.rightArm * Vector3.new(0, 0, -ARM_LEN)
		local hp = px720(s.camera, s.fov, vp, hand)
		local onScreen = hp.X >= 0 and hp.X <= 1280 and hp.Y >= 0 and hp.Y <= 720
		if onScreen and not handIn then
			handIn = k - 1
		elseif not onScreen and handIn and not handOut then
			handOut = k - 1
		end
		table.insert(series, { f = k - 1, boltT = r3(s.boltT), liftDeg = r3(math.deg(rz)), strokeStuds = r3(rel.Position.Z),
			hand = { r3(hp.X), r3(hp.Y) }, chambered = s.chamberedPredicted })
	end
	return {
		shots = #rec.shots, aimed = aim == true,
		ejectAtS = r3(ejectAt), clientChamberAtS = r3(chamberAt),
		serverChamberAtS = r3(if serverChamberAt then serverChamberAt - t else nil),
		handOnScreenFrames = { handIn, handOut },
		nextShotInS = r3(st.nextShotAt - t), cycleTimeCfg = r3(CFG.Fire.CycleTime),
		series = series,
	}
end

-- From 1 + 1: two shots (the last round's bolt cycle still runs), then the trigger does nothing; server agrees.
function Run.empty(): any
	ensureSniper()
	weapon("setAmmo", { Mag = 1, Chambered = true, Reserve = { 5, 5 } })
	frames(0.5)
	weapon("sync")
	frames(0.3)
	local before = weapon("state")
	weapon("record", true)
	for _ = 1, 5 do
		weapon("trigger", true)
		frames(0.05)
		weapon("trigger", false)
		frames(1.62)
	end
	local rec = weapon("record", false)
	weapon("sync")
	frames(0.4)
	local after = weapon("state")
	local acc, rej = serverDelta(before, after)
	local cycles = 0
	local prev = nil
	for _, s in rec.log do
		if s.boltT and (prev == nil) then
			cycles += 1
		end
		prev = s.boltT
	end
	return {
		presses = 5, shots = #rec.shots, boltCycles = cycles, acceptedDelta = acc, rejectedDelta = rej,
		after = { mag = after.mag, chambered = after.chambered,
			server = after.server and { mag = after.server.Mag, chambered = after.server.Chambered } },
	}
end

-- Scope in / out: transition times, the main camera FOV (never changed), the ring on the 720-px screen, the lens picture
-- (live only when aiming), the magnification and the scope camera vs the main camera.
function Run.ads(inHold: number?, outHold: number?): any
	ensureSniper()
	weapon("aim", false)
	frames(0.5)
	weapon("record", true)
	frames(0.1)
	local tIn = os.clock()
	weapon("aim", true)
	frames(inHold or 0.9)
	local opt = weapon("optic")
	local tOut = os.clock()
	weapon("aim", false)
	frames(outHold or 0.6)
	local log = weapon("record", false).log
	local vp = workspace.CurrentCamera.ViewportSize
	local inT, outT, fovMin, fovMax, liveHip, liveAim, aimFrames = nil, nil, math.huge, -math.huge, 0, 0, 0
	local ring, ringW, axisDeg, hip = nil, nil, nil, nil
	for _, s in log do
		fovMin, fovMax = math.min(fovMin, s.fov), math.max(fovMax, s.fov)
		if s.t >= tIn and s.t < tOut and s.aim >= 0.999 and not inT then
			inT = s.t - tIn
		end
		if s.t >= tOut and s.aim <= 0.001 and not outT then
			outT = s.t - tOut
		end
		if s.aim <= 0.001 and s.opticLive then
			liveHip += 1
		end
		if s.t < tIn and s.lensCF then
			local e, d = lensOf(s, vp)
			hip = { x = r3(e and e.X), y = r3(e and e.Y), ringWidth = r3(d) }
		end
		if s.t < tOut and s.aim >= 0.999 then
			aimFrames += 1
			if s.opticLive then
				liveAim += 1
			end
			local e, d = lensOf(s, vp)
			ring, ringW = e, d
			if s.scopeCF then
				axisDeg = math.deg(math.acos(math.clamp(s.scopeCF.LookVector:Dot(s.camera.LookVector), -1, 1)))
			end
		end
	end
	return {
		inTime = r3(inT), outTime = r3(outT), mainFov = { r3(fovMin), r3(fovMax) },
		lensLiveHipFrames = liveHip, lensLiveAimFrames = liveAim, aimFrames = aimFrames,
		hipEyepiece = hip,
		scopedRing = if ring then { x = r3(ring.X), y = r3(ring.Y), width = r3(ringW) } else nil,
		scopeAxisVsCameraDeg = r3(axisDeg),
		magnification = r3(opt.magnification), zoomLevel = opt.zoomLevel, scopeFov = r3(opt.scopeFov),
		gui = opt.gui, shadow = opt.shadow,
	}
end

-- Zoom: four steps up (6 -> 9 -> 12 -> 3 -> 6), one down; magnification after the change time, reticle scale, the label
-- text / lifetime, and the level after leaving and re-entering the scope.
function Run.zoom(): any
	ensureSniper()
	weapon("aim", true)
	frames(0.9)
	local steps = {}
	local function snap(tag: string)
		frames(0.15)
		local o = weapon("optic")
		local st = weapon("state")
		table.insert(steps, { step = tag, level = o.zoomLevel, magnification = r3(o.magnification), reticleScale = r3(o.reticleScale),
			scopeFov = r3(o.scopeFov), label = st.hud.zoom and st.hud.zoom.text, labelVisible = st.hud.zoom and st.hud.zoom.visible })
	end
	snap("start")
	for _ = 1, 4 do
		weapon("zoom", 1)
		snap("up")
	end
	weapon("zoom", -1)
	snap("down")
	-- the label's lifetime after the last change
	local shown, gone = os.clock(), nil
	while os.clock() - shown < 2.0 do
		frames(0.05)
		local z = weapon("state").hud.zoom
		if z and not z.visible and not gone then
			gone = os.clock() - shown
		end
	end
	weapon("aim", false)
	frames(0.6)
	local hipZoom = weapon("zoom", 1) -- no zoom at the hip
	weapon("aim", true)
	frames(0.9)
	local again = weapon("optic")
	-- restore the default level (6x)
	local guard = 0
	while again.zoomLevel ~= 6 and guard < 6 do
		weapon("zoom", 1)
		frames(0.15)
		again = weapon("optic")
		guard += 1
	end
	weapon("aim", false)
	frames(0.5)
	return { steps = steps, labelGoneAfterS = r3(gone), zoomAtHip = hipZoom.level, levelAfterReScope = steps[#steps].level,
		restored = again.zoomLevel }
end

-- The rounds check from the hip: duration, panel alpha over time, its text and place, and that a scope / fire input is
-- held while it runs. Then a refused check right after a shot (bolt cycling).
function Run.check(): any
	ensureSniper()
	weapon("setAmmo", { Mag = 5, Chambered = true, Reserve = { 5, 5 } })
	frames(0.5)
	weapon("record", true)
	frames(0.1)
	local t0 = os.clock()
	local res = weapon("check")
	local panelFirst, panelFull, panelOut, panelGone, text, pos, size = nil, nil, nil, nil, nil, nil, nil
	local triedFire = false
	local shotsDuring = 0
	while os.clock() - t0 < 3.5 do
		frames(0.02)
		local st = weapon("state")
		local p = st.hud.panel
		local t = os.clock() - t0
		if p and p.visible and not panelFirst then
			panelFirst = t
		end
		if p and p.alpha >= 0.999 and not panelFull then
			panelFull = t
			text = { p.rounds, p.capacity }
			pos, size = p.position, p.size
		end
		if panelFull and p and p.alpha < 0.999 and not panelOut then
			panelOut = t
		end
		if panelOut and p and not p.visible and not panelGone then
			panelGone = t
		end
		if t > 1.5 and not triedFire then
			triedFire = true
			weapon("trigger", true)
			frames(0.05)
			weapon("trigger", false)
		end
	end
	local rec = weapon("record", false)
	shotsDuring = #rec.shots
	local checkLen = nil
	for _, s in rec.log do
		if s.t > t0 and s.panelAlpha then
			checkLen = s.t - t0 -- refined below by the bolt state
		end
	end
	local st = weapon("state")
	-- refused while the bolt cycles
	weapon("trigger", true)
	frames(0.05)
	weapon("trigger", false)
	frames(0.2)
	local refused = weapon("check")
	frames(1.6)
	return {
		start = res and res.result, panelFirstS = r3(panelFirst), panelFullS = r3(panelFull), panelFadeStartS = r3(panelOut),
		panelGoneS = r3(panelGone), panelText = text, panelPosition = pos, panelSize = size,
		shotsWhileChecking = shotsDuring, checkingAfter = st.bolt and st.bolt.checking, refusedDuringCycle = refused and refused.result,
		_logEnd = r3(checkLen),
	}
end

local function scene(): any
	local cam = workspace.CurrentCamera
	local vms, fx = {}, 0
	for _, c in cam:GetChildren() do
		if string.sub(c.Name, -9) == "Viewmodel" then
			table.insert(vms, c.Name)
		elseif c.Name == "ProductionWeaponEffects" then
			fx += 1
		end
	end
	table.sort(vms)
	local lensGuis = {}
	for _, g in player.PlayerGui:GetChildren() do
		if g:IsA("SurfaceGui") and string.sub(g.Name, -5) == "Optic" and g.Enabled then
			table.insert(lensGuis, g.Name)
		end
	end
	return { viewmodels = vms, effectsFolders = fx, fov = r3(cam.FieldOfView), enabledLensGuis = lensGuis }
end
Run.scene = scene

-- Equip each id in turn, n times. Reports the scene after every equip of the last cycle and the instance count change.
function Run.switchCycle(ids: { string }, n: number): any
	local inst0 = nil
	local last = {}
	for c = 1, n do
		for _, id in ids do
			player:SetAttribute("EquippedWeapon", id)
			frames(0.4)
			if c == n then
				local st = weapon("state")
				local sc = scene()
				table.insert(last, { id = id, weapon = st.weapon, viewmodels = sc.viewmodels, effectsFolders = sc.effectsFolders,
					lensGuis = sc.enabledLensGuis, fov = sc.fov, hudText = st.hud and st.hud.text, climb = r3(st.climb),
					reloading = st.reloading, bolt = st.bolt and st.bolt.cycling, checking = st.bolt and st.bolt.checking,
					mag = st.mag, chambered = st.chambered, zoom = st.zoomLevel })
			end
		end
		if c == 1 then
			inst0 = Stats.InstanceCount
		end
	end
	return { cycles = n, final = last, instancesAfterCycle1 = inst0, instancesEnd = Stats.InstanceCount }
end

-- Fire, switch to `other` 0.3 s into the bolt cycle (scoped and zoomed to 12x first), come back: the presentation is
-- reset (no cycle clip, not scoped), the server's cycle and chamber still happen, and the next shot is not possible before
-- the cycle time; switching can't skip the bolt.
function Run.switchDuringCycle(other: string): any
	ensureSniper()
	weapon("refill")
	frames(0.4)
	weapon("aim", true)
	frames(0.9)
	weapon("zoom", 1)
	frames(0.15)
	weapon("zoom", 1)
	frames(0.15)
	local zoomBefore = weapon("state").zoomLevel
	weapon("sync")
	frames(0.3)
	local before = weapon("state")
	weapon("trigger", true)
	frames(0.05)
	weapon("trigger", false)
	local tShot = os.clock()
	frames(0.3)
	player:SetAttribute("EquippedWeapon", other)
	frames(0.3)
	local away = scene()
	player:SetAttribute("EquippedWeapon", "Sniper")
	frames(0.3)
	local back = weapon("state")
	local opt = weapon("optic")
	-- press at once (should not fire: the cycle is not over), then after the cycle
	weapon("trigger", true)
	frames(0.05)
	weapon("trigger", false)
	local early = weapon("state")
	frames(math.max(0, CFG.Fire.CycleTime + 0.15 - (os.clock() - tShot)))
	weapon("sync")
	frames(0.3)
	local ready = weapon("state")
	local tap = Base.tap()
	local acc, rej = serverDelta(before, ready)
	return {
		zoomBefore = zoomBefore, awayScene = away,
		back = { bolt = back.bolt, aimState = opt.aimState, live = opt.live, zoom = opt.zoomLevel, mag = back.mag,
			chambered = back.chambered, nextShotInS = r3(back.nextShotAt - back.now) },
		earlyPressShots = early.shotCount - back.shotCount,
		serverAfterCycle = ready.server and { mag = ready.server.Mag, chambered = ready.server.Chambered, reason = ready.server.Reason },
		acceptedDelta = acc, rejectedDelta = rej, tapAfterCycle = tap,
	}
end

-- Security: forged WeaponFire / WeaponCommand calls with the Sniper equipped.
function Run.forge(kind: string): any
	ensureSniper()
	local Remotes = ReplicatedStorage.Shared.Remotes
	local WeaponFire = Remotes:WaitForChild("WeaponFire") :: RemoteEvent
	local WeaponCommand = Remotes:WaitForChild("WeaponCommand") :: RemoteEvent
	weapon("sync")
	frames(0.3)
	local before = weapon("state")
	local cam = workspace.CurrentCamera
	local c = player.Character
	local head = c and c:FindFirstChild("Head") :: BasePart?
	local hp = if head then head.Position else cam.CFrame.Position
	local look = cam.CFrame.LookVector
	if kind == "farOrigin" then
		WeaponFire:FireServer("Sniper", hp + look * 40, look)
	elseif kind == "wallOrigin" then
		WeaponFire:FireServer("Sniper", Vector3.new(462, 4.5, -303), Vector3.new(0, 0, 1))
	elseif kind == "behind" then
		WeaponFire:FireServer("Sniper", hp, -look)
	elseif kind == "nan" then
		WeaponFire:FireServer("Sniper", hp, Vector3.new(0 / 0, 0, 1))
	elseif kind == "inf" then
		WeaponFire:FireServer("Sniper", Vector3.new(math.huge, 0, 0), look)
	elseif kind == "zero" then
		WeaponFire:FireServer("Sniper", hp, Vector3.zero)
	elseif kind == "fakeHit" then -- extra arguments (hit position / part / damage) and a direction straight down
		local bot = workspace.MP7Test.Bots:FindFirstChild("MP7_DISTANT") :: Model?
		local tgt = bot and bot:FindFirstChild("Head") :: BasePart?
		WeaponFire:FireServer("Sniper", hp, Vector3.new(0, -1, 0.0001), tgt and tgt.Position, tgt, "Head", { hit = tgt and tgt.Position, damage = 999 })
	elseif kind == "rate" then -- 12 shots in one frame
		for _ = 1, 12 do
			WeaponFire:FireServer("Sniper", hp, look)
		end
	elseif kind == "rateSustained" then -- a shot every 0.5 s for 4 s (an auto-clicker ignoring the bolt)
		for _ = 1, 9 do
			WeaponFire:FireServer("Sniper", hp, look)
			frames(0.5)
		end
	elseif kind == "cycleFire" then -- shots at 0.3 / 0.9 / 1.3 s after an accepted one (inside the cycle)
		WeaponFire:FireServer("Sniper", hp, look)
		for _, d in { 0.3, 0.6, 0.4 } do
			frames(d)
			WeaponFire:FireServer("Sniper", hp, look)
		end
		frames(0.6)
	elseif kind == "wrongWeapon" then -- the M4 while the Sniper is equipped
		WeaponFire:FireServer("M4", hp, look)
	elseif kind == "unknownWeapon" then
		WeaponFire:FireServer("Sniper_GOLD", hp, look)
	elseif kind == "equipUnknown" then
		WeaponCommand:FireServer("Equip", "Sniper_GOLD")
		frames(0.2)
		WeaponFire:FireServer("Sniper_GOLD", hp, look)
	elseif kind == "ammo" then -- client-claimed ammunition / reload results are not commands the server knows
		WeaponCommand:FireServer("SetAmmo", { Mag = 999, Chambered = true, Reserve = { 999 } })
		WeaponCommand:FireServer("ReloadDone")
		WeaponCommand:FireServer("ReloadSwapped")
	elseif kind == "bolt" then -- forced bolt / action state right after a shot (no such commands exist)
		WeaponFire:FireServer("Sniper", hp, look)
		WeaponCommand:FireServer("BoltReady")
		WeaponCommand:FireServer("Chamber")
		WeaponCommand:FireServer("CycleDone")
		WeaponCommand:FireServer("BoltChambered")
		WeaponFire:FireServer("Sniper", hp, look)
		frames(0.2)
		WeaponFire:FireServer("Sniper", hp, look)
	elseif kind == "reloadDuringCycle" then -- reload request right after a shot
		WeaponFire:FireServer("Sniper", hp, look)
		frames(0.1)
		WeaponCommand:FireServer("Reload")
	elseif kind == "switchFire" then -- equip the M4 and fire the Sniper in the same frame
		WeaponCommand:FireServer("Equip", "M4")
		WeaponFire:FireServer("Sniper", hp, look)
		WeaponCommand:FireServer("Equip", "Sniper")
	elseif kind == "badTypes" then
		WeaponFire:FireServer({ "Sniper" }, "origin", 42)
	elseif kind == "dead" then -- the server kills the player (run S.killPlayer() / set Health = 0 on the server): fire while dead
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		local t0 = os.clock()
		while hum and hum.Health > 0 and os.clock() - t0 < 5 do
			frames(0.03)
		end
		for _ = 1, 3 do
			WeaponFire:FireServer("Sniper", hp, look)
			frames(0.3)
		end
	end
	frames(0.6)
	weapon("sync")
	frames(0.3)
	local after = weapon("state")
	local acc, rej = serverDelta(before, after)
	return {
		kind = kind, accepted = acc, rejected = rej,
		serverMag = { before.server and before.server.Mag, after.server and after.server.Mag },
		serverChambered = { before.server and before.server.Chambered, after.server and after.server.Chambered },
		serverReloading = after.server and after.server.Reloading, serverReason = after.server and after.server.Reason,
		serverReserve = after.server and after.server.Reserve,
		equipped = player:GetAttribute("EquippedWeapon"),
	}
end

-- Instant reload: Reload + a forged completion + a second start, then fire: shots refused while the server reloads;
-- the magazine changes only at the clip's seat time.
function Run.instantReload(): any
	ensureSniper()
	local WeaponFire = ReplicatedStorage.Shared.Remotes:WaitForChild("WeaponFire") :: RemoteEvent
	local WeaponCommand = ReplicatedStorage.Shared.Remotes:WaitForChild("WeaponCommand") :: RemoteEvent
	weapon("setAmmo", { Mag = 2, Chambered = true, Reserve = { 5, 5 } })
	frames(0.5)
	weapon("sync")
	frames(0.3)
	local before = weapon("state")
	local cam = workspace.CurrentCamera
	WeaponCommand:FireServer("Reload")
	WeaponCommand:FireServer("ReloadDone")
	WeaponCommand:FireServer("Reload")
	frames(0.1)
	for _ = 1, 3 do
		WeaponFire:FireServer("Sniper", cam.CFrame.Position, cam.CFrame.LookVector)
		frames(0.05)
	end
	frames(0.15)
	weapon("sync")
	frames(0.2)
	local mid = weapon("state")
	frames(4.3)
	weapon("sync")
	frames(0.3)
	local done = weapon("state")
	local acc, rej = serverDelta(before, mid)
	return {
		acceptedDuringReload = acc, rejectedDuringReload = rej,
		serverAt05 = mid.server and { mag = mid.server.Mag, reloading = mid.server.Reloading, reason = mid.server.Reason },
		serverDone = done.server and { mag = done.server.Mag, chambered = done.server.Chambered, reserve = done.server.Reserve, reloading = done.server.Reloading },
	}
end

return Run
