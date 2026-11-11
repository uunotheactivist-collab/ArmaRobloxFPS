--!strict
-- Focused M4 reload test (Studio playtest only; isolated - delete the M4ReloadTest folder to remove it).
-- Drives StarterPlayerScripts.Client.WeaponController through its Studio-only debug hook (real reload path:
-- client clip + server command), records every frame, and reports timing, joint behaviour and ammunition on both
-- sides. Usage from the client:
--   local Run = require(game.Players.LocalPlayer.PlayerScripts.M4ReloadTest.Run)
--   Run("tactical", { stressed = false })  Run("empty", { stressed = true })  Run("refusals")
--   Run("partialReserve")  Run("whileAiming")  Run("switchDuring")  Run("repeated")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("WeaponController")
	:WaitForChild("ProductionWeaponDebug") :: BindableFunction

local function call(cmd: string, arg: any?): any
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function server(timeout: number?): any
	call("sync")
	local t0 = os.clock()
	local s = call("state")
	while not s.server and os.clock() - t0 < (timeout or 2) do
		task.wait(0.03)
		s = call("state")
	end
	return s
end

local function r3(x: number?): number?
	return if x then math.round(x * 1000) / 1000 else nil
end

local function ammoOf(s: any): any
	return { mag = s.mag, chambered = s.chambered, reserve = s.reserve }
end

local function serverAmmo(s: any): any
	return s.server and { mag = s.server.Mag, chambered = s.server.Chambered, reserve = s.server.Reserve, reloading = s.server.Reloading } or nil
end

local function setup(stressed: boolean)
	player:SetAttribute("EquippedWeapon", "M4")
	call("stressed", stressed)
	call("aim", false)
	call("trigger", false)
	call("refill")
	frames(0.6)
	server()
end

local function fireShots(n: number)
	local before = call("state").shotCount
	call("trigger", true)
	local t0 = os.clock()
	while call("state").shotCount - before < n and os.clock() - t0 < 5 do
		RunService.RenderStepped:Wait()
	end
	call("trigger", false)
	frames(0.3)
	return call("state").shotCount - before
end

-- Weapon-relative magazine offset (studs) and the joint frames relative to the camera, from the per-frame log.
local function analyse(log: { any }, startAt: number): any
	local first, magAway, magBack, chTravel = nil, nil, nil, 0
	local restMag, restCH = nil, nil
	local finishedAt = nil
	for _, e in log do
		local relMag = e.weapon:ToObjectSpace(e.magazine)
		if e.reloadT == nil and not first then
			restMag = relMag.Position
			restCH = e.weapon:ToObjectSpace(e.chargingHandle).Position
		end
		if e.reloadT and not first then
			first = e.t
		end
		if first and restMag then
			local d = (relMag.Position - restMag).Magnitude
			if d > 0.3 and not magAway then
				magAway = e.t - first
			end
			if magAway and d < 0.02 and not magBack then
				magBack = e.t - first
			end
			local ch = e.weapon:ToObjectSpace(e.chargingHandle).Position
			chTravel = math.max(chTravel, ch.Z - (restCH or ch).Z) -- rearward = +Z in the weapon frame (forward is -Z)
		end
		if first and e.reloadT == nil and not finishedAt then
			finishedAt = e.t - first
		end
	end
	local last = log[#log]
	local idle = log[1]
	local function relToCam(e: any, cf: CFrame): CFrame
		return e.camera:ToObjectSpace(cf)
	end
	local wEnd, wIdle = relToCam(last, last.weapon), relToCam(idle, idle.weapon)
	local aEnd, aIdle = relToCam(last, last.arm), relToCam(idle, idle.arm)
	local function angle(a: CFrame, b: CFrame): number
		local _, ang = (a:Inverse() * b):ToAxisAngle()
		return math.deg(math.abs(ang))
	end
	return {
		clientDuration = r3(finishedAt),
		magazineLeftRifleAt = r3(magAway),
		magazineSeatedAgainAt = r3(magBack),
		chargingHandleTravelStuds = r3(chTravel),
		finalPose = {
			weaponPosErrStuds = r3((wEnd.Position - wIdle.Position).Magnitude),
			weaponRotErrDeg = r3(angle(wEnd, wIdle)),
			armPosErrStuds = r3((aEnd.Position - aIdle.Position).Magnitude),
			armRotErrDeg = r3(angle(aEnd, aIdle)),
			magazineSeated = r3((last.weapon:ToObjectSpace(last.magazine).Position - (restMag or Vector3.zero)).Magnitude),
		},
	}
end

local Run = {}

-- One full reload of the given kind: tactical (after 4 shots) or empty (after the whole magazine).
function Run.reload(kind: string, opts: any): any
	local stressed = opts and opts.stressed == true
	setup(stressed)
	local shots = fireShots(if kind == "empty" then 40 else 4)
	local before = server()
	call("record", true)
	frames(0.15)
	local t0 = os.clock()
	local started = call("reload").result
	-- try to fire during the reload: must not shoot
	frames(1.0)
	local shotsBefore = call("state").shotCount
	call("trigger", true)
	frames(0.4)
	call("trigger", false)
	local shotsDuring = call("state").shotCount - shotsBefore
	while call("state").reloading and os.clock() - t0 < 6 do
		RunService.RenderStepped:Wait()
	end
	frames(0.4)
	local rec = call("record", false)
	local after = server()
	-- fire after the reload: must shoot and be accepted
	local acceptedBefore = after.server and after.server.Accepted or 0
	local shotsAfter = fireShots(3)
	local final = server()
	local res = analyse(rec.log, t0)
	res.started = started
	res.shotsBeforeReload = shots
	res.shotsFiredDuringReload = shotsDuring
	res.ammoBefore = { client = ammoOf(before), server = serverAmmo(before) }
	res.ammoAfter = { client = ammoOf(after), server = serverAmmo(after) }
	res.fireAfterReload = { shots = shotsAfter, serverAccepted = final.server and (final.server.Accepted - acceptedBefore) or nil, serverRejectedTotal = final.server and final.server.Rejected }
	res.lastReloadClip = call("state").lastReload
	call("stressed", false)
	return res
end

function Run.refusals(): any
	setup(false)
	local full = call("reload").result -- full magazine + chamber
	call("setAmmo", { Mag = 12, Chambered = true, Reserve = {} })
	frames(0.3)
	local s = server()
	local noReserve = call("reload").result
	frames(0.3)
	return { fullMagazine = full, emptyReserve = noReserve, ammoAfter = ammoOf(s), reloading = call("state").reloading }
end

function Run.partialReserve(): any
	setup(false)
	call("setAmmo", { Mag = 0, Chambered = false, Reserve = { 12, 7 } })
	frames(0.3)
	server()
	local started = call("reload").result
	local t0 = os.clock()
	while call("state").reloading and os.clock() - t0 < 6 do
		RunService.RenderStepped:Wait()
	end
	frames(0.3)
	local after = server()
	return { started = started, client = ammoOf(after), server = serverAmmo(after) }
end

function Run.whileAiming(): any
	setup(false)
	fireShots(2)
	call("aim", true)
	frames(0.8)
	call("record", true)
	local started = call("reload").result
	frames(0.6)
	local rec = call("record", false)
	local aimAtEnd = rec.log[#rec.log].aim
	local t0 = os.clock()
	while call("state").reloading and os.clock() - t0 < 6 do
		RunService.RenderStepped:Wait()
	end
	call("aim", false)
	frames(0.3)
	return { started = started, aimAlphaAfter600ms = r3(aimAtEnd), fovAfter600ms = r3(rec.log[#rec.log].fov) }
end

function Run.switchDuring(): any
	setup(false)
	fireShots(5)
	local before = server()
	local started = call("reload").result
	frames(1.0) -- before the magazine change (2.3 s)
	player:SetAttribute("EquippedWeapon", "TestBlaster")
	frames(0.4)
	local away = call("state")
	player:SetAttribute("EquippedWeapon", "M4")
	frames(0.4)
	local back = server()
	local early = { started = started, clientReloadingAfterSwitch = away.reloading, ammoBefore = { client = ammoOf(before), server = serverAmmo(before) },
		ammoAfter = { client = ammoOf(back), server = serverAmmo(back) } }
	-- after the magazine change: switch at 2.6 s
	local started2 = call("reload").result
	frames(2.6)
	player:SetAttribute("EquippedWeapon", "TestBlaster")
	frames(0.4)
	player:SetAttribute("EquippedWeapon", "M4")
	frames(0.4)
	local back2 = server()
	return { beforeCommit = early, afterCommit = { started = started2, ammoAfter = { client = ammoOf(back2), server = serverAmmo(back2) } } }
end

function Run.repeated(): any
	setup(false)
	local out = {}
	for i = 1, 3 do
		fireShots(3 + i)
		local started = call("reload").result
		frames(0.5)
		local busy = call("reload").result -- pressing R again mid-reload
		local t0 = os.clock()
		while call("state").reloading and os.clock() - t0 < 6 do
			RunService.RenderStepped:Wait()
		end
		frames(0.3)
		local s = server()
		table.insert(out, { started = started, secondPress = busy, client = ammoOf(s), server = serverAmmo(s) })
	end
	return out
end

return function(name: string, opts: any?): any
	if name == "tactical" or name == "empty" then
		return Run.reload(name, opts)
	end
	local f = (Run :: any)[name]
	assert(f, "unknown test " .. tostring(name))
	return f()
end
