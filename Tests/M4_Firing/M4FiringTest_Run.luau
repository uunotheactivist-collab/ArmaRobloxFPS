--!strict
-- Focused M4 firing/recoil test (Studio playtest only; isolated - delete the M4FiringTest folder to remove it).
-- Drives StarterPlayerScripts.Client.WeaponController through its Studio-only debug hook, samples what the camera
-- and viewmodel do at 30 fps (the reference footage rate) and computes the same statistics as the reference
-- analysis (ReferenceAnalysis/M4/Firing). Usage from the client:
--   local Run = require(game.Players.LocalPlayer.PlayerScripts.M4FiringTest.Run)
--   Run("single") | Run("hipBurst") | Run("adsMag") | Run("hipMag") | Run("stressedHip") | Run("stop") | Run("weaponReset")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("WeaponController")
	:WaitForChild("ProductionWeaponDebug") :: BindableFunction

local STUD = 0.28
local WIN_HALF = Vector3.new(0.013 / STUD, 0.010 / STUD, 0) -- sight window half size (studs, weapon space)

local function call(cmd: string, arg: any?): any
	return hook:Invoke(cmd, arg)
end

local function waitFrames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function waitServer(timeout: number): any
	call("sync")
	local t0 = os.clock()
	local s = call("state")
	while not s.server and os.clock() - t0 < timeout do
		task.wait(0.05)
		s = call("state")
	end
	return s
end

-- Resample the per-frame log to 30 fps (nearest frame), like the reference video.
local function at30(log: { any }): { any }
	local out = {}
	if #log == 0 then
		return out
	end
	local t0, i = log[1].t, 1
	local k = 0
	while true do
		local target = t0 + k / 30
		if target > log[#log].t then
			break
		end
		while i < #log and log[i + 1].t <= target do
			i += 1
		end
		table.insert(out, log[i])
		k += 1
	end
	return out
end

local function pct(xs: { number }, p: number): number
	local s = table.clone(xs)
	table.sort(s)
	if #s == 0 then
		return 0 / 0
	end
	return s[math.clamp(math.floor(p * (#s - 1) + 1.5), 1, #s)]
end

local function mean(xs: { number }): number
	local a = 0
	for _, x in xs do
		a += x
	end
	return a / math.max(#xs, 1)
end

local function sd(xs: { number }): number
	local m, a = mean(xs), 0
	for _, x in xs do
		a += (x - m) ^ 2
	end
	return math.sqrt(a / math.max(#xs, 1))
end

local function r3(x: number): number
	return math.round(x * 1000) / 1000
end

-- Screen offsets in degrees relative to the camera axis (what the reference measures on its picture).
local function angleOf(camera: CFrame, world: Vector3): (number, number)
	local p = camera:PointToObjectSpace(world)
	return math.deg(math.atan2(p.X, -p.Z)), math.deg(math.atan2(p.Y, -p.Z))
end

local function shotStats(shots: { number }): any
	local iv = {}
	for i = 2, #shots do
		table.insert(iv, shots[i] - shots[i - 1])
	end
	local dur = if #shots > 1 then shots[#shots] - shots[1] else 0
	return {
		count = #shots,
		meanIntervalS = r3(mean(iv)),
		minIntervalS = r3(pct(iv, 0)),
		maxIntervalS = r3(pct(iv, 1)),
		rpm = if dur > 0 then math.round(60 * (#shots - 1) / dur) else nil,
	}
end

local function burstStats(rec: any, aimed: boolean): any
	local shots = rec.shots
	local s30 = at30(rec.log)
	local first, last = shots[1], shots[#shots]
	local pitch, during, after = {}, {}, {}
	for _, e in s30 do
		local p = e.climb + e.shake.X
		if e.t >= first and e.t <= last then
			table.insert(during, p)
		elseif e.t > last then
			table.insert(after, { t = e.t - last, p = p })
		end
	end
	local n = #during
	local thirds = {}
	for k = 0, 2 do
		local part = {}
		for i = math.floor(k * n / 3) + 1, math.floor((k + 1) * n / 3) do
			table.insert(part, during[i])
		end
		table.insert(thirds, r3(pct(part, 0.5)))
	end
	-- exponential recovery: least squares on log(p) for p > 0.05 deg
	local sx, sy, sxx, sxy, m = 0, 0, 0, 0, 0
	local baselineAt = nil
	for _, a in after do
		if a.p > 0.05 then
			sx += a.t
			sy += math.log(a.p)
			sxx += a.t * a.t
			sxy += a.t * math.log(a.p)
			m += 1
		elseif not baselineAt and a.p < 0.05 then
			baselineAt = a.t
		end
	end
	local slope = if m > 2 then (m * sxy - sx * sy) / (m * sxx - sx * sx) else 0
	local out: any = {
		shots = shotStats(shots),
		cameraPitchDeg = {
			thirdsMedian = thirds,
			p90 = r3(pct(during, 0.9)),
			max = r3(pct(during, 1)),
			frameDiffMAD = nil :: number?,
		},
		recovery = { tauS = if slope < 0 then r3(-1 / slope) else nil, belowPoint05DegAfterS = baselineAt and r3(baselineAt) },
	}
	local diffs = {}
	for i = 2, #during do
		table.insert(diffs, during[i] - during[i - 1])
	end
	local md = pct(diffs, 0.5)
	local dev = {}
	for _, d in diffs do
		table.insert(dev, math.abs(d - md))
	end
	out.cameraPitchDeg.frameDiffMAD = r3(pct(dev, 0.5) * 1.4826)

	if aimed then
		-- Sight window projected on screen (width -> apparent scale; centre -> vertical offset), reticle offset.
		local restW, scales, sightDy, sightDx, retDx, retDy, tilts = nil, {}, {}, {}, {}, {}, {}
		local sightRear = rec.state.sightRear
		for _, e in s30 do
			local cam, w = e.camera, e.weapon
			local lx = angleOf(cam, w * (sightRear - Vector3.new(WIN_HALF.X, 0, 0)))
			local rx = angleOf(cam, w * (sightRear + Vector3.new(WIN_HALF.X, 0, 0)))
			local cx, cy = angleOf(cam, w * sightRear)
			local width = rx - lx
			if e.t < first then
				restW = width
			elseif e.t >= first and e.t <= last + 0.02 and restW then
				table.insert(scales, width / restW)
				table.insert(sightDy, cy)
				table.insert(sightDx, cx)
				if e.reticleVisible then
					local ax, ay = angleOf(cam, e.reticle)
					table.insert(retDx, ax)
					table.insert(retDy, ay)
				end
				local up = cam:VectorToObjectSpace(w.UpVector)
				table.insert(tilts, math.deg(math.atan2(-up.X, up.Y)))
			end
		end
		out.sightScale = { p90 = r3(pct(scales, 0.9)), max = r3(pct(scales, 1)), median = r3(pct(scales, 0.5)), min = r3(pct(scales, 0)) }
		out.sightOffsetDeg = { dyMean = r3(mean(sightDy)), dySd = r3(sd(sightDy)), dyMax = r3(pct(sightDy, 1)), dxSd = r3(sd(sightDx)) }
		out.reticleOffsetDeg = { dxMean = r3(mean(retDx)), dxSd = r3(sd(retDx)), dyMean = r3(mean(retDy)), dySd = r3(sd(retDy)), visibleFrames = #retDx }
		out.sightTiltSdDeg = r3(sd(tilts))
	else
		-- Hip: weapon roll relative to the camera (idle cant vs firing posture).
		local rollRest, rollFire, rollAfter = {}, {}, {}
		for _, e in s30 do
			local up = e.camera:VectorToObjectSpace(e.weapon.UpVector)
			local roll = math.deg(math.atan2(-up.X, up.Y))
			if e.t < first then
				table.insert(rollRest, roll)
			elseif e.t <= last then
				table.insert(rollFire, roll)
			elseif e.t - last > 0.15 and e.t - last < 0.4 then
				table.insert(rollAfter, roll)
			end
		end
		out.weaponRollDeg = { idle = r3(pct(rollRest, 0.5)), firingMedian = r3(pct(rollFire, 0.5)), after150to400ms = r3(pct(rollAfter, 0.5)) }
	end
	return out
end

local function recordBurst(opts: { aim: boolean, stressed: boolean?, seconds: number?, untilEmpty: boolean? }): any
	player:SetAttribute("EquippedWeapon", "M4")
	player:SetAttribute("Stressed", opts.stressed == true)
	call("refill")
	waitServer(2)
	call("aim", opts.aim)
	waitFrames(if opts.aim then 0.9 else 0.4)
	call("record", true)
	waitFrames(0.25)
	call("trigger", true)
	local t0 = os.clock()
	if opts.untilEmpty then
		while call("state").chambered and os.clock() - t0 < 5 do
			RunService.RenderStepped:Wait()
		end
		waitFrames(0.3) -- trigger still held on an empty magazine: must not fire
	else
		waitFrames(opts.seconds or 1)
	end
	local releasedAt = os.clock()
	call("trigger", false)
	waitFrames(1.4)
	local rec = call("record", false)
	rec.state = call("state")
	rec.releasedAt = releasedAt
	call("aim", false)
	player:SetAttribute("Stressed", false)
	local server = waitServer(2)
	return rec, server
end

local Run = {}

function Run.single(): any
	player:SetAttribute("EquippedWeapon", "M4")
	call("refill")
	local s0 = waitServer(2)
	waitFrames(0.4)
	local before = call("state").shotCount
	call("trigger", true)
	RunService.RenderStepped:Wait()
	call("trigger", false)
	waitFrames(0.5)
	local s1 = waitServer(2)
	return {
		shotsFired = s1.shotCount - before,
		clientAmmo = { mag = s1.mag, chambered = s1.chambered },
		server = s1.server and { mag = s1.server.Mag, chambered = s1.server.Chambered, accepted = s1.server.Accepted - (s0.server and s0.server.Accepted or 0), rejected = s1.server.Rejected },
	}
end

function Run.hipBurst(): any
	local rec, server = recordBurst({ aim = false, seconds = 1.0 })
	return { burst = shotStats(rec.shots), server = { mag = server.server.Mag, chambered = server.server.Chambered, rejected = server.server.Rejected }, client = { mag = server.mag, chambered = server.chambered } }
end

function Run.adsMag(): any
	local rec, server = recordBurst({ aim = true, untilEmpty = true })
	local out = burstStats(rec, true)
	out.lastShotToRelease = r3(rec.releasedAt - rec.shots[#rec.shots])
	out.ammoAfter = { client = { mag = server.mag, chambered = server.chambered }, server = { mag = server.server.Mag, chambered = server.server.Chambered, accepted = server.server.Accepted, rejected = server.server.Rejected } }
	return out
end

function Run.hipMag(): any
	local rec = recordBurst({ aim = false, untilEmpty = true })
	return burstStats(rec, false)
end

function Run.stressedHip(): any
	local rec = recordBurst({ aim = false, stressed = true, untilEmpty = true })
	local out = burstStats(rec, false)
	local swayMax = 0
	for _, e in rec.log do
		local _, _, z = e.camSway:ToEulerAnglesXYZ()
		swayMax = math.max(swayMax, math.abs(math.deg(z)))
	end
	out.cameraSwayRollMaxDeg = r3(swayMax)
	return out
end

function Run.stop(): any
	local rec = recordBurst({ aim = false, seconds = 0.5 })
	local late = 0
	for _, t in rec.shots do
		if t > rec.releasedAt + 1e-3 then
			late += 1
		end
	end
	local last = rec.log[#rec.log]
	return { shots = #rec.shots, shotsAfterRelease = late, climbDeg1400msAfter = r3(last.climb), envelopeAfter = r3(last.env) }
end

function Run.weaponReset(): any
	player:SetAttribute("EquippedWeapon", "M4")
	call("refill")
	waitServer(2)
	call("trigger", true)
	waitFrames(0.3)
	local mid = call("state")
	player:SetAttribute("EquippedWeapon", "TestBlaster") -- switch away while firing
	waitFrames(0.3)
	call("trigger", false)
	local away = call("state")
	player:SetAttribute("EquippedWeapon", "M4")
	waitFrames(0.3)
	local back = waitServer(2)
	return {
		climbWhileFiring = r3(mid.climb),
		activeAfterSwitchAway = away.active,
		climbAfterSwitchBack = r3(back.climb),
		envelopeAfterSwitchBack = r3(back.envelope),
		ammoKept = { client = back.mag + (if back.chambered then 1 else 0), server = back.server and (back.server.Mag + (if back.server.Chambered then 1 else 0)) },
	}
end

return function(name: string): any
	local f = (Run :: any)[name]
	assert(f, "unknown test " .. tostring(name))
	return f()
end
