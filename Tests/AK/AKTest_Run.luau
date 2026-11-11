--!strict
-- Focused AK test (Studio playtest only; isolated - delete the AKTest folder to remove it).
-- Drives the shared production weapon controller (StarterPlayerScripts.Client.WeaponController) through its
-- Studio-only debug hook with the AK equipped, records every rendered frame, and compares against the AK footage
-- numbers (ReferenceAnalysis/AK/AK_Analysis.md). Usage from the client:
--   local Run = require(game.Players.LocalPlayer.PlayerScripts.AKTest.Run)
--   Run("equip") Run("hipBurst") Run("raised") Run("fullMag") Run("reload", { kind = "tactical", stressed = false })
--   Run("reload", { kind = "empty", stressed = true }) Run("labelSequence") Run("labelRepeat") Run("refusals")
--   Run("switch") Run("repeated")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("WeaponController")
	:WaitForChild("ProductionWeaponDebug") :: BindableFunction
local F_PX = 216 / math.tan(math.rad(35)) -- the analysis camera (432-px picture, vertical FOV 70)

local function call(cmd: string, arg: any?): any
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function r3(x: number?): number?
	return if x then math.round(x * 1000) / 1000 else nil
end

local function server(): any
	call("sync")
	local t0 = os.clock()
	local s = call("state")
	while not s.server and os.clock() - t0 < 2 do
		task.wait(0.03)
		s = call("state")
	end
	return s
end

local function ammo(s: any): any
	return {
		client = { mag = s.mag, chambered = s.chambered, reserve = s.reserve, label = #s.dropped + (s.labelMarks or 0) },
		server = s.server and { mag = s.server.Mag, chambered = s.server.Chambered, reserve = s.server.Reserve,
			label = #(s.server.Dropped or {}) + (s.server.LabelMarks or 0) } or nil,
	}
end

local function equip(id: string)
	player:SetAttribute("EquippedWeapon", id)
	frames(0.3)
end

local function setup(stressed: boolean)
	equip("AK")
	call("stressed", stressed)
	call("aim", false)
	call("trigger", false)
	call("refill")
	frames(0.6)
	server()
end

local function fireShots(n: number): number
	local before = call("state").shotCount
	call("trigger", true)
	local t0 = os.clock()
	while call("state").shotCount - before < n and os.clock() - t0 < 6 do
		RunService.RenderStepped:Wait()
	end
	call("trigger", false)
	return call("state").shotCount - before
end

-- Screen position (analysis pixels: 432-px-tall picture, centre = principal point) of a world point.
local function toPx(cam: CFrame, p: Vector3): Vector2
	local q = cam:PointToObjectSpace(p)
	return Vector2.new(239 + F_PX * q.X / -q.Z, 229 - F_PX * q.Y / -q.Z)
end

-- 30 fps resampling of a per-frame log (the footage statistics are per 30 fps frame).
local function at30(log: { any }): { any }
	local out, nextT = {}, log[1].t
	for _, e in log do
		if e.t >= nextT then
			table.insert(out, e)
			nextT += 1 / 30
		end
	end
	return out
end

local function median(t: { number }): number
	table.sort(t)
	return if #t == 0 then 0 else t[math.ceil(#t / 2)]
end

local function sd(t: { number }): number
	local m = 0
	for _, v in t do
		m += v
	end
	m /= math.max(#t, 1)
	local s = 0
	for _, v in t do
		s += (v - m) ^ 2
	end
	return math.sqrt(s / math.max(#t, 1))
end

-- Firing statistics with the footage's definitions (27_ak_fire_stats.py / 30_ak_recoil_measure.py): 30 fps samples
-- from the first to the last shot only; camera pitch frame-to-frame change = median |diff| (deg); muzzle (front of
-- the rifle) screen position: sd (deg) and median |frame diff| (px, 432-px picture).
local function fireStats(log: { any }, shots: { number }): any
	local gaps = {}
	for i = 2, #shots do
		table.insert(gaps, shots[i] - shots[i - 1])
	end
	local s30 = at30(log)
	local pitch, postX, postY = {}, {}, {}
	local base = s30[1].camera
	local first, last = shots[1], shots[#shots]
	for _, e in s30 do
		if first and e.t >= first and e.t <= last then
			local look = base:VectorToObjectSpace(e.camera.LookVector)
			table.insert(pitch, math.deg(math.asin(math.clamp(look.Y, -1, 1))))
			local px = toPx(e.camera, e.muzzle)
			table.insert(postX, px.X)
			table.insert(postY, px.Y)
		end
	end
	local dpitch, dpx, dpy = {}, {}, {}
	for i = 2, #pitch do
		table.insert(dpitch, math.abs(pitch[i] - pitch[i - 1]))
		table.insert(dpx, math.abs(postX[i] - postX[i - 1]))
		table.insert(dpy, math.abs(postY[i] - postY[i - 1]))
	end
	local peak = -math.huge
	for _, e in log do
		peak = math.max(peak, e.climb)
	end
	return {
		shots = #shots,
		rpm = if #gaps > 0 then math.round(60 / (((shots[#shots] - shots[1]) / #gaps))) else nil,
		climbPeakDeg = r3(peak),
		pitchFrameDiffMAD = r3(median(dpitch)),
		muzzleSdDeg = { r3(math.deg(math.atan(sd(postX) / F_PX))), r3(math.deg(math.atan(sd(postY) / F_PX))) },
		muzzleFrameDiffMADpx = { r3(median(dpx)), r3(median(dpy)) },
	}
end

local Run = {}

function Run.equip(): any
	equip("M4")
	frames(0.3)
	equip("AK")
	frames(0.3)
	local s = server()
	return { weapon = s.weapon, active = s.active, viewmodelParented = s.viewmodelParented, viewmodelsInCamera = s.viewmodels,
		hud = { visible = s.hud.visible, text = s.hud.text, copies = s.hud.guiCopies }, ammo = ammo(s) }
end

-- Hip burst (5 shots, as B1/B3): cadence, climb, shake, posture (no de-cant on the AK).
function Run.hipBurst(): any
	setup(false)
	call("record", true)
	frames(0.3)
	local n = fireShots(5)
	frames(1.5)
	local rec = call("record", false)
	local st = fireStats(rec.log, rec.shots)
	-- recovery: time from the last shot until the climb is below 0.05 deg
	local last = rec.shots[#rec.shots]
	local recovered
	for _, e in rec.log do
		if e.t > last and e.climb < 0.05 then
			recovered = e.t - last
			break
		end
	end
	-- posture: weapon roll relative to the camera before vs during the burst (the AK hip burst stays canted)
	local function roll(e: any): number
		local rel = e.camera:ToObjectSpace(e.weapon)
		local _, _, z = rel:ToOrientation()
		return math.deg(z)
	end
	local before, during = roll(rec.log[1]), 0
	for _, e in rec.log do
		if e.env > 0.9 then
			during = roll(e)
			break
		end
	end
	st.recoveredAfterS = r3(recovered)
	st.rollBeforeDeg, st.rollDuringDeg = r3(before), r3(during)
	st.fired = n
	local s = server()
	st.serverAccepted, st.serverRejected = s.server and s.server.Accepted, s.server and s.server.Rejected
	return st
end

-- Raised posture (aim): timing, no zoom.
function Run.raised(): any
	setup(false)
	call("record", true)
	frames(0.2)
	call("aim", true)
	frames(0.8)
	call("aim", false)
	frames(0.6)
	local rec = call("record", false)
	local t0, tUp, tRel, tDown = nil, nil, nil, nil
	local fovMin, fovMax = math.huge, -math.huge
	for _, e in rec.log do
		fovMin, fovMax = math.min(fovMin, e.fov), math.max(fovMax, e.fov)
		if e.aim > 0 and not t0 then
			t0 = e.t
		end
		if t0 and e.aim >= 0.999 and not tUp then
			tUp = e.t
		end
		if tUp and e.aim < 0.999 and not tRel then
			tRel = e.t
		end
		if tRel and e.aim <= 0.001 and not tDown then
			tDown = e.t
		end
	end
	return { raiseTimeS = r3(tUp and t0 and tUp - t0), lowerTimeS = r3(tDown and tRel and tDown - tRel),
		fovRange = { r3(fovMin), r3(fovMax) }, expected = { raise = 0.13, lower = 0.30, fov = 70 } }
end

-- Full magazine in the raised posture (as B2/B4): 31 rounds, cadence, climb, shake, muzzle jitter; then empty.
function Run.fullMag(opts: any?): any
	setup(opts and opts.stressed == true)
	call("aim", true)
	frames(0.5)
	call("record", true)
	local n = fireShots(40)
	frames(1.2)
	local rec = call("record", false)
	call("aim", false)
	local st = fireStats(rec.log, rec.shots)
	st.fired = n
	local s = server()
	st.ammoAfter = ammo(s)
	st.serverAccepted, st.serverRejected = s.server and s.server.Accepted, s.server and s.server.Rejected
	-- trigger on an empty rifle does nothing
	local before = call("state").shotCount
	call("trigger", true)
	frames(0.4)
	call("trigger", false)
	st.shotsWhenEmpty = call("state").shotCount - before
	return st
end

-- One reload of a kind; timing, label, ammunition, no firing during it, firing after it.
function Run.reload(opts: any): any
	setup(opts.stressed == true)
	local shotsBefore = fireShots(if opts.kind == "empty" then 40 else 4)
	frames(0.3)
	local before = server()
	call("record", true)
	frames(0.1)
	local t0 = os.clock()
	local started = call("reload").result
	frames(0.5)
	local sc = call("state").shotCount
	call("trigger", true)
	frames(0.3)
	call("trigger", false)
	local firedDuring = call("state").shotCount - sc
	while call("state").reloading and os.clock() - t0 < 6 do
		RunService.RenderStepped:Wait()
	end
	frames(0.3)
	local rec = call("record", false)
	local first, finished, labelAt, labelText
	local labelBefore = rec.log[1].hudText
	for _, e in rec.log do
		if e.reloadT and not first then
			first = e.t
		end
		if first and e.reloadT == nil and not finished then
			finished = e.t - first
		end
		if first and e.reloadT and e.hudText ~= labelBefore and not labelAt then
			labelAt, labelText = e.reloadT, e.hudText
		end
	end
	local after = server()
	local accBefore = after.server and after.server.Accepted or 0
	local shotsAfter = fireShots(3)
	frames(0.3)
	local final = server()
	call("stressed", false)
	return { started = started, shotsBeforeReload = shotsBefore, clientDuration = r3(finished), shotsFiredDuringReload = firedDuring,
		labelChangedAt = r3(labelAt), labelText = labelText, ammoBefore = ammo(before), ammoAfter = ammo(after),
		fireAfter = { shots = shotsAfter, accepted = final.server and final.server.Accepted - accBefore, rejectedTotal = final.server and final.server.Rejected } }
end

-- The footage's order: Regular tactical, Regular empty, Stressed tactical (label appears), Stressed empty.
function Run.labelSequence(): any
	setup(false)
	local out = {}
	local function one(kind: string, stressed: boolean)
		call("stressed", stressed)
		frames(0.3)
		fireShots(if kind == "empty" then 40 else 4)
		frames(0.3)
		call("record", true)
		call("reload")
		local t0 = os.clock()
		while call("state").reloading and os.clock() - t0 < 6 do
			RunService.RenderStepped:Wait()
		end
		frames(0.2)
		local rec = call("record", false)
		local before, at, txt = rec.log[1].hudText, nil, nil
		for _, e in rec.log do
			if e.reloadT and e.hudText ~= before and not at then
				at, txt = e.reloadT, e.hudText
			end
		end
		local s = server()
		table.insert(out, { kind = kind, stressed = stressed, labelBefore = before, labelChangedAt = r3(at), labelAfter = txt or before,
			hudShown = s.hud.visible, ammo = ammo(s) })
	end
	one("tactical", false)
	one("empty", false)
	one("tactical", true)
	one("empty", true)
	call("stressed", false)
	return out
end

-- The label is a flag, not a count: a second Stressed tactical reload leaves "[TAB] 5.45 MAG" unchanged (no "+1").
function Run.labelRepeat(): any
	setup(true)
	local out = {}
	for i = 1, 2 do
		fireShots(4)
		frames(0.3)
		call("reload")
		local t0 = os.clock()
		while call("state").reloading and os.clock() - t0 < 6 do
			RunService.RenderStepped:Wait()
		end
		frames(0.3)
		local s = server()
		table.insert(out, { reload = i, hud = s.hud.text, clientMarks = s.labelMarks,
			serverMarks = s.server and s.server.LabelMarks, ammo = ammo(s) })
	end
	call("stressed", false)
	return out
end

function Run.refusals(): any
	setup(false)
	local full = call("reload").result
	call("setAmmo", { Mag = 12, Chambered = true, Reserve = {} })
	frames(0.4)
	server()
	return { fullMagazine = full, emptyReserve = call("reload").result }
end

-- Weapon switching M4 <-> AK: one viewmodel, separate ammunition, HUD of the other weapon hidden, reload cancelled.
function Run.switch(): any
	setup(false)
	fireShots(7)
	frames(0.3)
	local ak = server()
	equip("M4")
	frames(0.3)
	local m4 = server()
	equip("AK")
	frames(0.3)
	local back = server()
	-- switch during an AK reload
	local started = call("reload").result
	frames(0.6)
	equip("M4")
	frames(0.3)
	local m4Mid = server()
	equip("AK")
	frames(0.3)
	local akAfter = server()
	return {
		akAfter7 = ammo(ak),
		m4 = { weapon = m4.weapon, ammo = ammo(m4), viewmodels = m4.viewmodels },
		backToAK = { ammo = ammo(back), viewmodels = back.viewmodels, active = back.active },
		reloadSwitch = { started = started, m4Reloading = m4Mid.reloading, akReloadingAfter = akAfter.reloading, akAmmo = ammo(akAfter) },
	}
end

function Run.repeated(): any
	setup(false)
	local out = {}
	for i = 1, 3 do
		fireShots(2 + i)
		frames(0.2)
		local started = call("reload").result
		frames(0.3)
		local busy = call("reload").result
		local t0 = os.clock()
		while call("state").reloading and os.clock() - t0 < 6 do
			RunService.RenderStepped:Wait()
		end
		frames(0.3)
		local s = server()
		table.insert(out, { started = started, secondPress = busy, ammo = ammo(s) })
	end
	for i = 1, 3 do
		local n = fireShots(6)
		frames(0.6)
		local s = server()
		table.insert(out, { burst = i, fired = n, accepted = s.server and s.server.Accepted, rejected = s.server and s.server.Rejected })
	end
	return out
end

return function(name: string, opts: any?): any
	local f = (Run :: any)[name]
	assert(f, "unknown test " .. tostring(name))
	return f(opts)
end
