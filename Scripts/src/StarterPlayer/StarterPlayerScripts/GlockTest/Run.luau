--!strict
-- Focused Glock test, client side (Studio only; delete the GlockTest folders to remove it). Driven through execute_luau
-- (Client datamodel): require(PlayerScripts.GlockTest.Run).<fn>(...). Generic helpers come from the MP7 test
-- (PlayerScripts.MP7Test.Run: equip / look / idle / reload / track / perf); this module adds what is Glock-specific.
-- The range is Workspace.MP7Test (reused, Roblox/Tests/MP7/build_range.luau); the server half is ServerScriptService.GlockTest.Run.
--   Run.press(n, gap, opts)        n trigger presses: shots, cadence, server accept / reject, ammunition, recoil and the
--                                  rear-dot / slide motion sampled at 30 fps the way the footage was measured
--   Run.hold(seconds)              trigger held: semi-automatic = one shot
--   Run.empty()                    fire to slide lock: last round, lock, blocked trigger, server state
--   Run.slideCycle()               slide travel per 30-fps frame around one shot
--   Run.ads(inHold, outHold)       aim in / out: times, FOV, red dot in the window, dot vs screen centre
--   Run.reload(ammo, stressed)     the MP7 test's reload measurement + slide lock / release and camera track
--   Run.switchCycle(ids, n)        weapon switching: viewmodels, effects folders, instances, reset state
--   Run.switchDuringReload(...)    switch away mid-reload and back: ammunition, slide, reload state, next shot
--   Run.forge(kind)                forged remote calls with the Glock (security)
--   Run.aimHoldTrack(opts)         the footage's aim / shot / release timing at 30 fps: rear dots, red dot, camera

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local Base = require(script.Parent.Parent:WaitForChild("MP7Test"):WaitForChild("Run")) :: any
local Run = setmetatable({}, { __index = Base }) :: any
local weapon, frames = Base.weapon, Base.frames
local DATA = require(ReplicatedStorage.Shared.Assets.Weapons.GlockViewmodelData) :: any
local CFG = require(ReplicatedStorage.Shared.WeaponRegistry).get("Glock") :: any
local PICTURE_H = 405 -- the footage's game picture height (px)

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

-- Rear night dots (on the slide) in picture pixels (405-px-high picture, centred): position and spacing.
local CH_C0 = CFrame.new(table.unpack(DATA.Joints.ChargingHandle.C0))
local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end
local DOT_L = CH_C0:PointToObjectSpace(v3(DATA.Points.RearDotL))
local DOT_R = CH_C0:PointToObjectSpace(v3(DATA.Points.RearDotR))
local function dots(s: any, vp: Vector2): (Vector2, number)
	local a = project(s.camera, s.fov, vp, s.chargingHandle * DOT_L)
	local b = project(s.camera, s.fov, vp, s.chargingHandle * DOT_R)
	local k = PICTURE_H / vp.Y
	return (a + b) / 2 * k, (a - b).Magnitude * k
end

local function serverDelta(before: any, after: any): (number?, number?)
	if before and before.server and after and after.server then
		return (after.server.Accepted or 0) - (before.server.Accepted or 0), (after.server.Rejected or 0) - (before.server.Rejected or 0)
	end
	return nil, nil
end

-- n presses `gap` seconds apart. opts: { aim, refill (default true), hold (press length, default 0.05), after }
function Run.press(n: number, gap: number, opts: any?): any
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
	local gaps = {}
	for i = 2, #shots do
		table.insert(gaps, shots[i] - shots[i - 1])
	end
	local vp = workspace.CurrentCamera.ViewportSize
	local s30 = at30(log, (shots[1] or tDown) - 4 / 30, log[#log].t)
	local function idxAt(t: number): number
		for i, s in s30 do
			if s.t >= t then
				return i
			end
		end
		return #s30
	end
	-- per shot, the footage's definitions (ReferenceAnalysis/Glock/tools/glock_recoil.py; i = the shot / flash frame):
	-- camera kick = visible pitch on frame i+1 vs the mean of i-1 and i-2; weapon = the rear dots on the frame of i+1..i+3
	-- with the largest |dy| (dx, dy, spacing ratio there); back = first frame i+2..i+8 within 4 px and 5 % of i-1
	local kicks, dys, dxs, ratios, backIn = {}, {}, {}, {}, {}
	local function pitchOf(s: any): number
		return s.climb + s.shake.X
	end
	for _, t in shots do
		local i = idxAt(t)
		local p0 = (pitchOf(s30[math.max(1, i - 1)]) + pitchOf(s30[math.max(1, i - 2)])) / 2
		local c0, sp0 = dots(s30[math.max(1, i - 1)], vp)
		local kick = pitchOf(s30[math.min(#s30, i + 1)]) - p0
		local dy, dx, ratio = 0, 0, 1
		for k = i + 1, math.min(#s30, i + 3) do
			local c, sp = dots(s30[k], vp)
			if math.abs(c.Y - c0.Y) > math.abs(dy) then
				dy, dx, ratio = c.Y - c0.Y, math.abs(c.X - c0.X), sp / sp0
			end
		end
		local back = nil
		for k = i + 2, math.min(#s30, i + 8) do
			local c, sp = dots(s30[k], vp)
			if math.abs(c.X - c0.X) < 4 and math.abs(c.Y - c0.Y) < 4 and math.abs(sp / sp0 - 1) < 0.05 then
				back = k - i
				break
			end
		end
		table.insert(kicks, kick)
		table.insert(dys, dy)
		table.insert(dxs, dx)
		table.insert(ratios, ratio)
		table.insert(backIn, back or 99)
	end
	local lastShot = shots[#shots] or tDown
	local endClimb, climb22 = 0, nil
	local rollIn = {}
	for _, s in log do
		if s.t <= lastShot then
			endClimb = s.climb
			if s.t >= (shots[1] or tDown) then
				table.insert(rollIn, s.shake.Z)
			end
		elseif not climb22 and s.t >= lastShot + 22 / 30 then
			climb22 = s.climb
		end
	end
	local acc, rej = serverDelta(before, after)
	return {
		presses = n,
		shots = #shots,
		medianGapMs = r3((median(gaps) or 0) * 1000),
		minGapMs = r3(if #gaps > 0 then math.min(table.unpack(gaps)) * 1000 else nil),
		magBefore = before.mag, chamberedBefore = before.chambered, magAfter = after.mag, chamberedAfter = after.chambered,
		serverMagAfter = after.server and after.server.Mag, serverChamberedAfter = after.server and after.server.Chambered,
		acceptedDelta = acc, rejectedDelta = rej,
		kickMedianDeg = r3(median(kicks)),
		dotDyMedianPx405 = r3(median(dys)),
		dotDxMedianPx405 = r3(median(dxs)),
		dotSpacingRatioMedian = r3(median(ratios)),
		backInFramesMedian = median(backIn),
		climbEndDeg = r3(endClimb),
		climb22FramesAfterDeg = r3(climb22),
		rollSdDeg = r3(sd(rollIn)),
		stressed = player:GetAttribute("Stressed") == true,
		aimed = opts.aim == true,
	}
end

-- Trigger held down: a semi-automatic weapon fires once per press.
function Run.hold(seconds: number): any
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

-- Slide travel fraction per 30-fps frame from 2 frames before one shot to 5 after (footage: back on the frame after the
-- flash, back home by the third).
function Run.slideCycle(): any
	weapon("refill")
	frames(0.4)
	weapon("record", true)
	frames(0.2)
	weapon("trigger", true)
	frames(0.05)
	weapon("trigger", false)
	frames(0.5)
	local rec = weapon("record", false)
	local t = rec.shots[1]
	if not t then
		return { shots = 0 }
	end
	local series = {}
	for _, s in at30(rec.log, t - 2 / 30, t + 5 / 30) do
		table.insert(series, r3(s.slide))
	end
	-- the slide part's own displacement at the peak (weapon frame, studs)
	local peak = 0
	for _, s in rec.log do
		local rel = s.weapon:ToObjectSpace(s.chargingHandle).Position - CH_C0.Position
		peak = math.max(peak, rel.Magnitude)
	end
	return { shots = #rec.shots, slide30 = series, peakTravelStuds = r3(peak), lockTravelStuds = r3(CFG.Slide.LockTravelStuds) }
end

-- Fire to slide lock from 1 + 1 rounds, then keep pressing: last-round lock, blocked trigger, server agreement.
function Run.empty(): any
	weapon("setAmmo", { Mag = 1, Chambered = true, Reserve = { 15, 15 } })
	frames(0.5)
	weapon("sync")
	frames(0.3)
	local before = weapon("state")
	weapon("record", true)
	for _ = 1, 5 do
		weapon("trigger", true)
		frames(0.05)
		weapon("trigger", false)
		frames(0.25)
	end
	frames(0.5)
	local rec = weapon("record", false)
	weapon("sync")
	frames(0.4)
	local after = weapon("state")
	local acc, rej = serverDelta(before, after)
	local lastShot = rec.shots[#rec.shots]
	local lockedFrom, unlockedAfter = nil, false
	for _, s in rec.log do
		if lastShot and s.t >= lastShot then
			if s.slide >= 0.999 and not lockedFrom then
				lockedFrom = s.t - lastShot
			elseif lockedFrom and s.slide < 0.999 then
				unlockedAfter = true
			end
		end
	end
	return {
		presses = 5, shots = #rec.shots, acceptedDelta = acc, rejectedDelta = rej,
		after = { mag = after.mag, chambered = after.chambered, slide = r3(after.slide),
			server = after.server and { mag = after.server.Mag, chambered = after.server.Chambered } },
		slideLockedAfterLastShotS = r3(lockedFrom), slideLeftLock = unlockedAfter,
	}
end

-- Aim in / out with the red dot: transition times, FOV, the dot shown only in the aim pose, the dot vs screen centre.
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
	local vp = workspace.CurrentCamera.ViewportSize
	local inT, outT, fovMin, fovMax = nil, nil, math.huge, -math.huge
	local hipVisible, aimVisible, aimFrames, dotOff = 0, 0, 0, nil
	for _, s in log do
		fovMin, fovMax = math.min(fovMin, s.fov), math.max(fovMax, s.fov)
		if s.t >= tIn and s.t < tOut and s.aim >= 0.999 and not inT then
			inT = s.t - tIn
		end
		if s.t >= tOut and s.aim <= 0.001 and not outT then
			outT = s.t - tOut
		end
		if s.aim <= 0.001 and s.reticleVisible then
			hipVisible += 1
		end
		if s.t < tOut and s.aim >= 0.999 then
			aimFrames += 1
			if s.reticleVisible then
				aimVisible += 1
				local p = project(s.camera, s.fov, vp, s.reticle)
				dotOff = { r3((p.X - vp.X / 2) / vp.Y * PICTURE_H), r3((p.Y - vp.Y / 2) / vp.Y * PICTURE_H) }
			end
		end
	end
	return {
		inTime = r3(inT), outTime = r3(outT), fov = { r3(fovMin), r3(fovMax) },
		expectedAimFov = r3(math.deg(2 * math.atan(math.tan(math.rad(35)) / CFG.ADS.ZoomMagnification))),
		reticleVisibleHipFrames = hipVisible, reticleVisibleAimFrames = aimVisible, aimFrames = aimFrames,
		redDotFromCentrePx405 = dotOff, frames = #log,
	}
end

-- The MP7 test's reload measurement, plus the slide (locked until the slide release in an empty reload) and the camera
-- track (pitch / roll vs the pre-reload view).
function Run.reload(ammo: any, stressed: boolean?): any
	-- Base.reload owns the frame recorder: the slide / camera are sampled by a parallel watcher
	local samples = {}
	local watching = true
	task.spawn(function()
		while watching do
			local st = weapon("state")
			table.insert(samples, { t = os.clock(), slide = st.slide, reloading = st.reloading, chambered = st.chambered,
				cam = workspace.CurrentCamera.CFrame })
			RunService.RenderStepped:Wait()
		end
	end)
	local res = Base.reload(ammo, stressed)
	watching = false
	-- reload start = first sample with reloading set
	local t0, rest = nil, nil
	for _, s in samples do
		if s.reloading and not t0 then
			t0 = s.t
		elseif not t0 then
			rest = s.cam
		end
	end
	local releaseAt, slideAtStart, minPitch, rollMin, rollMax = nil, nil, 0, 0, 0
	if t0 and rest then
		for _, s in samples do
			if s.t >= t0 then
				slideAtStart = slideAtStart or s.slide
				if s.slide and s.slide < 0.5 and slideAtStart and slideAtStart > 0.5 and not releaseAt then
					releaseAt = s.t - t0
				end
				if s.reloading then
					local rel = rest:ToObjectSpace(s.cam)
					local pitch = math.deg(math.asin(math.clamp(rel.LookVector.Y, -1, 1)))
					local roll = math.deg(math.asin(math.clamp(rel.RightVector.Y, -1, 1)))
					minPitch = math.min(minPitch, pitch)
					rollMin, rollMax = math.min(rollMin, roll), math.max(rollMax, roll)
				end
			end
		end
	end
	res.slideAtStart = r3(slideAtStart)
	res.slideReleaseAtS = r3(releaseAt)
	res.slideAfter = r3(weapon("state").slide)
	res.cameraPitchMinDeg = r3(minPitch)
	res.cameraRollRangeDeg = { r3(rollMin), r3(rollMax) }
	return res
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
	return { viewmodels = vms, effectsFolders = fx, fov = r3(cam.FieldOfView) }
end
Run.scene = scene

-- Equip each id in turn, n times. Reports the scene after every equip of the last cycle and the instance count change.
function Run.switchCycle(ids: { string }, n: number): any
	local inst0 = nil
	local last = {}
	for c = 1, n do
		for _, id in ids do
			player:SetAttribute("EquippedWeapon", id)
			frames(0.35)
			if c == n then
				local st = weapon("state")
				local sc = scene()
				table.insert(last, { id = id, weapon = st.weapon, viewmodels = sc.viewmodels, effectsFolders = sc.effectsFolders,
					fov = sc.fov, hud = st.hud and st.hud.text, hudVisible = st.hud and st.hud.visible, climb = r3(st.climb),
					reloading = st.reloading, slide = r3(st.slide), mag = st.mag, chambered = st.chambered })
			end
		end
		if c == 1 then
			inst0 = Stats.InstanceCount
		end
	end
	return { cycles = n, final = last, instancesAfterCycle1 = inst0, instancesEnd = Stats.InstanceCount }
end

-- Glock reload interrupted by a switch to `other` after `after` seconds, then back: reload state, ammunition, slide,
-- and one press afterwards.
function Run.switchDuringReload(ammo: any, other: string, after: number): any
	player:SetAttribute("EquippedWeapon", "Glock")
	frames(0.5)
	weapon("setAmmo", ammo)
	frames(0.5)
	weapon("sync")
	frames(0.3)
	local before = weapon("state")
	weapon("reload")
	frames(after)
	local mid = weapon("state")
	player:SetAttribute("EquippedWeapon", other)
	frames(0.6)
	player:SetAttribute("EquippedWeapon", "Glock")
	frames(0.6)
	weapon("sync")
	frames(0.4)
	local back = weapon("state")
	local tap = Base.tap()
	return {
		before = { mag = before.mag, chambered = before.chambered, reserve = before.reserve },
		midReload = mid.reloading,
		back = { reloading = back.reloading, mag = back.mag, chambered = back.chambered, reserve = back.reserve, slide = r3(back.slide),
			server = back.server and { mag = back.server.Mag, chambered = back.server.Chambered, reserve = back.server.Reserve, reason = back.server.Reason },
			climb = r3(back.climb), hud = back.hud and back.hud.text },
		tapAfter = tap,
	}
end

-- Security: forged WeaponFire / WeaponCommand calls with the Glock equipped.
function Run.forge(kind: string): any
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
		WeaponFire:FireServer("Glock", hp + look * 40, look)
	elseif kind == "wallOrigin" then
		WeaponFire:FireServer("Glock", Vector3.new(462, 4.5, -303), Vector3.new(0, 0, 1))
	elseif kind == "behind" then
		WeaponFire:FireServer("Glock", hp, -look)
	elseif kind == "nan" then
		WeaponFire:FireServer("Glock", hp, Vector3.new(0 / 0, 0, 1))
	elseif kind == "inf" then
		WeaponFire:FireServer("Glock", Vector3.new(math.huge, 0, 0), look)
	elseif kind == "zero" then
		WeaponFire:FireServer("Glock", hp, Vector3.zero)
	elseif kind == "fakeHit" then -- extra arguments (hit position / part / damage) and a direction straight down
		local bot = workspace.MP7Test.Bots:FindFirstChild("MP7_DISTANT") :: Model?
		local tgt = bot and bot:FindFirstChild("Head") :: BasePart?
		WeaponFire:FireServer("Glock", hp, Vector3.new(0, -1, 0.0001), tgt and tgt.Position, tgt, "Head", { hit = tgt and tgt.Position, damage = 999 })
	elseif kind == "rate" then -- 12 shots in one frame (cap 450 RPM, burst allowance 3)
		for _ = 1, 12 do
			WeaponFire:FireServer("Glock", hp, look)
		end
	elseif kind == "rateSustained" then -- ~2000 RPM for 1 s (an auto-clicker / modified client)
		for _ = 1, 33 do
			WeaponFire:FireServer("Glock", hp, look)
			frames(0.03)
		end
	elseif kind == "wrongWeapon" then -- the MP7 while the Glock is equipped
		WeaponFire:FireServer("MP7", hp, look)
	elseif kind == "unknownWeapon" then
		WeaponFire:FireServer("Glock_GOLD", hp, look)
	elseif kind == "equipUnknown" then -- equip a weapon that does not exist, then fire it
		WeaponCommand:FireServer("Equip", "Glock_GOLD")
		frames(0.2)
		WeaponFire:FireServer("Glock_GOLD", hp, look)
	elseif kind == "ammo" then -- client-claimed ammunition / reload results are not commands the server knows
		WeaponCommand:FireServer("SetAmmo", { Mag = 999, Chambered = true, Reserve = { 999 } })
		WeaponCommand:FireServer("ReloadDone")
		WeaponCommand:FireServer("ReloadSwapped")
	elseif kind == "slide" then -- forced slide / chamber state (no such commands exist; the slide is derived from ammo)
		WeaponCommand:FireServer("SlideRelease")
		WeaponCommand:FireServer("Chamber")
		WeaponCommand:FireServer("SetSlide", 0)
		WeaponCommand:FireServer("ReloadChambered")
	elseif kind == "badTypes" then
		WeaponFire:FireServer({ "Glock" }, "origin", 42)
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
		serverReserve = after.server and after.server.Reserve,
		equipped = player:GetAttribute("EquippedWeapon"),
	}
end

-- Instant reload / impossible transitions: Reload, then fire immediately (server: reloading), and a forged early
-- completion; reports server ammunition at 0.3 s (before the swap at 2.23 s) and the shots' fate.
function Run.instantReload(): any
	local WeaponFire = ReplicatedStorage.Shared.Remotes:WaitForChild("WeaponFire") :: RemoteEvent
	local WeaponCommand = ReplicatedStorage.Shared.Remotes:WaitForChild("WeaponCommand") :: RemoteEvent
	weapon("setAmmo", { Mag = 3, Chambered = true, Reserve = { 15, 15 } })
	frames(0.5)
	weapon("sync")
	frames(0.3)
	local before = weapon("state")
	local cam = workspace.CurrentCamera
	WeaponCommand:FireServer("Reload")
	WeaponCommand:FireServer("ReloadDone")
	WeaponCommand:FireServer("Reload") -- a second start while busy
	frames(0.1)
	for _ = 1, 3 do
		WeaponFire:FireServer("Glock", cam.CFrame.Position, cam.CFrame.LookVector)
		frames(0.05)
	end
	frames(0.15)
	weapon("sync")
	frames(0.2)
	local mid = weapon("state")
	frames(3.3)
	weapon("sync")
	frames(0.3)
	local done = weapon("state")
	local acc, rej = serverDelta(before, mid)
	return {
		acceptedDuringReload = acc, rejectedDuringReload = rej,
		serverAt04 = mid.server and { mag = mid.server.Mag, reloading = mid.server.Reloading, reason = mid.server.Reason },
		serverDone = done.server and { mag = done.server.Mag, chambered = done.server.Chambered, reserve = done.server.Reserve, reloading = done.server.Reloading },
	}
end

-- Aim-hold drift (2026-11-10): the footage's Regular aim event on its own timing. Aim input = frame 147, one shot on
-- frame 163 (opts.shotAt s after the aim input; < 0 = no shot), release on frame 175 (opts.releaseAt). Sampled at 30 fps
-- from the aim input and labelled with the footage frame number: rear dots, red dot (when shown) and the camera as a
-- horizon height, all in 405-px picture px (+ = down; horizon = 202.5 + f * tan(camera pitch)).
function Run.aimHoldTrack(opts: any?): any
	opts = opts or {}
	local shotAt = opts.shotAt or 16 / 30
	local releaseAt = opts.releaseAt or 28 / 30
	local tail = opts.tail or 0.4
	weapon("aim", false)
	weapon("refill")
	frames(0.8)
	weapon("record", true)
	frames(0.15)
	local t0 = os.clock()
	weapon("aim", true)
	local fired = false
	while os.clock() - t0 < releaseAt do
		if shotAt >= 0 and not fired and os.clock() - t0 >= shotAt then
			weapon("trigger", true)
			fired = true
			frames(0.05)
			weapon("trigger", false)
		end
		RunService.RenderStepped:Wait()
	end
	weapon("aim", false)
	frames(tail)
	local rec = weapon("record", false)
	local vp = workspace.CurrentCamera.ViewportSize
	local shotT = rec.shots[1]
	local out = {}
	-- aimed-shot recoil (2026-11-10): the optic window's top edge (a slide point placed on the edge measured in the
	-- aimed capture, 193.5 px at rest) and the muzzle angle relative to the camera
	local winTop = CH_C0:PointToObjectSpace(Vector3.new(0, 0.12258, 0.114286))
	for k, s in at30(rec.log, t0 - 3 / 30, t0 + releaseAt + tail - 0.05) do
		local d, spacing = dots(s, vp)
		local wt = project(s.camera, s.fov, vp, s.chargingHandle * winTop)
		local m = s.camera:VectorToObjectSpace(s.weapon.LookVector)
		local f405 = (PICTURE_H / 2) / math.tan(math.rad(s.fov) / 2)
		local look = s.camera.LookVector
		local red = nil
		if s.reticleVisible then
			red = r3(project(s.camera, s.fov, vp, s.reticle).Y / vp.Y * PICTURE_H)
		end
		table.insert(out, {
			frame = 147 + k - 4, aim = r3(s.aim),
			dotsY = r3(d.Y), -- picture px from the top (the footage's dots_y)
			dotsX = r3(d.X - vp.X / 2 * PICTURE_H / vp.Y), -- px from the picture centre
			spacing = r3(spacing),
			winTop = r3(wt.Y / vp.Y * PICTURE_H),
			muzzle = r3(math.deg(math.asin(m.Y))), -- weapon axis pitch vs the camera (deg, + = up)
			red = red, -- picture px from the top (centre 202.5)
			horizon = r3(PICTURE_H / 2 + f405 * math.tan(math.asin(look.Y))),
			hold = s.aimHold and { r3(s.aimHold[1]), r3(s.aimHold[2] * 1000) } or nil,
		})
	end
	return { frames = out, shotFrame = shotT and r3(147 + (shotT - t0) * 30) or nil, shots = #rec.shots }
end

return Run
