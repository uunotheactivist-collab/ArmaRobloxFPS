--!strict
-- Focused AI combat test, server side (Studio only; delete the AITest folders to remove it). Everything is read from
-- the server's own state through the Studio debug hooks (AIDebug, BodyStateDebug, BodyPresentationDebug, BloodDebug,
-- Ballistics.RecentResults). Test bots and targets are named T_* and live in Workspace.AITest; the demo bot BOT1 is
-- disabled while the tests run (Run.setup) and re-enabled by Run.cleanup.
--   Run.setup() / Run.cleanup()
--   Run.perception()   in the open / behind the wall / outside the field of view / out of range / friend / dead / self
--   Run.aiming()       turn to a target off to the side, aim settle, body facing applied by HitReaction, determinism
--   Run.firing()       reaction delay, rate, bursts, origin, the M4 reload, no reserve, muzzle counter, shot records
--   Run.integration()  bot vs body: BodyState / flinch / ragdoll / blood; holds fire while reacting; bot vs bot: the
--                      loser goes DOWN / DEAD, stops firing, lets go of its rifle
--   Run.performance(n) n bots in pairs facing targets: loop, scan, line-of-sight and shot costs
--   Run.watchStart(bot) + client { path } + Run.playerChecks(bot, moments)   the player as a moving target
--   Run.playerShot(bot)  the bot shoots the player: placeholder damage, real death, existing respawn
--   client { shootBot } + Run.shotDown(bot)   the player's real M4 puts a bot down (BodyState → AI DOWN → rifle let go)
--   Run.securityBefore(bot) + client { security } + Run.securityAfter(bot, before)   the ten forged inputs
--   Run.status(name) / Run.events(name) / Run.shots(name)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Run = {}

local function ai(...: any): any
	return (ServerScriptService.Server.AI.AIServer:WaitForChild("AIDebug", 5) :: BindableFunction):Invoke(...)
end
local function bodyHook(...: any): any
	return (ServerScriptService.Server.BodyState:WaitForChild("BodyStateDebug", 5) :: BindableFunction):Invoke(...)
end
local function pres(...: any): any
	return (ServerScriptService.Server.BodyPresentation:WaitForChild("BodyPresentationDebug", 5) :: BindableFunction):Invoke(...)
end
local function blood(...: any): any
	return (ServerScriptService.Server.Blood.BloodServer:WaitForChild("BloodDebug", 5) :: BindableFunction):Invoke(...)
end
local function ballistics(): { any }
	return (ServerScriptService.Server.Ballistics:WaitForChild("RecentResults", 5) :: BindableFunction):Invoke()
end

local AIConfig = require(ReplicatedStorage.Shared.Config.AI)
local M4 = require(ReplicatedStorage.Shared.Config.Weapons.M4)

local function r3(x: number?): number?
	return if x then math.floor(x * 1000 + 0.5) / 1000 else nil
end

local function check(list: { any }, name: string, pass: boolean, detail: any)
	table.insert(list, { name = name, pass = pass, detail = detail })
end

local function summary(list: { any }): any
	local passed = 0
	for _, c in list do
		if c.pass then
			passed += 1
		end
	end
	return { passed = passed, total = #list, checks = list }
end

local function range(): Folder
	return workspace:WaitForChild("AITest") :: Folder
end

-- spot name → standing position of a rig's root (feet on the floor)
function Run.spot(name: string): Vector3
	local p = (range():WaitForChild(name) :: BasePart).Position
	return Vector3.new(p.X, 3, p.Z)
end

function Run.setup(): any
	Run.cleanup(true)
	local b1 = ai("status", "BOT1")
	if not b1.Error then
		ai("set", "BOT1", { Enabled = false })
	end
	ai("resetperf")
	return true
end

function Run.cleanup(keepBot1Disabled: boolean?): any
	for _, b in ai("list") do
		if string.sub(b.Name, 1, 2) == "T_" then
			ai("remove", b.Name)
		end
	end
	for _, c in range():GetChildren() do
		if string.sub(c.Name, 1, 2) == "T_" then
			c:Destroy()
		end
	end
	if not keepBot1Disabled then
		local b1 = ai("status", "BOT1")
		if not b1.Error then
			ai("set", "BOT1", { Enabled = true, HoldFire = false })
		end
	end
	return true
end

-- a test bot (team Red by default) at a position, facing yawDeg (0 = -Z, 180 = +Z)
function Run.bot(name: string, pos: Vector3, yawDeg: number, opts: any?): Model
	local o = opts or {}
	local m = ai("spawn", { Name = name, Position = pos, Yaw = yawDeg, Team = o.Team or "Red", Seed = o.Seed, Enabled = o.Enabled })
	if o.HoldFire ~= nil then
		ai("set", name, { HoldFire = o.HoldFire })
	end
	return m
end

-- a target body: the accepted REACT1 test bot (BodyState body, ActiveRagdoll presentation) with a team
function Run.dummy(name: string, pos: Vector3, team: string?, yawDeg: number?): Model
	local d = ServerStorage.HitReactionTemplates.REACT1:Clone()
	d.Name = name
	d:SetAttribute(AIConfig.TeamAttribute, team or "Blue")
	d:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg or 0), 0))
	d.Parent = range()
	return d
end

-- a durable target for the rate / burst / reload checks: the same rig WITHOUT BodyModel (so the shot path gives it the
-- placeholder Humanoid damage, as it does a player) and a very large health, so it never goes down
function Run.tough(name: string, pos: Vector3, team: string?): Model
	local d = ServerStorage.HitReactionTemplates.REACT1:Clone()
	d.Name = name
	for _, a in { "BodyModel", "BodyPresentation", "BodyDebugView" } do
		d:SetAttribute(a, nil)
	end
	d:SetAttribute(AIConfig.TeamAttribute, team or "Blue")
	local h = d:FindFirstChildOfClass("Humanoid") :: Humanoid
	h.MaxHealth = 1e7
	h.Health = 1e7
	d:PivotTo(CFrame.new(pos))
	d.Parent = range()
	return d
end

local function waitFor(seconds: number, pred: () -> boolean): (boolean, number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		if pred() then
			return true, os.clock() - t0
		end
		task.wait()
	end
	return pred(), os.clock() - t0
end

function Run.status(name: string): any
	return ai("status", name)
end
function Run.events(name: string): any
	return ai("events", name)
end
function Run.shots(name: string): any
	return ai("shots", name)
end

local BOT_POS = Vector3.new(-740, 3, 150)

---------------------------------------------------------------------------------------------------------------- perception
function Run.perception(): any
	Run.setup()
	local list = {}
	local bot = Run.bot("T_P", BOT_POS, 180, { Enabled = false })
	task.wait(0.2)
	local function look(target: Model): any
		return ai("look", "T_P", target)
	end
	-- 1 in the open, 30 studs in front
	local open = Run.dummy("T_Open", Run.spot("SpotOpen"), "Blue", 0)
	task.wait(0.1)
	local l = look(open)
	check(list, "1 sees a target in the open", l.Fov.Point ~= nil and l.Enemy and l.Alive, l.Fov)
	open:Destroy()
	-- 2 behind the wall
	local cover = Run.dummy("T_Cover", Run.spot("SpotCover"), "Blue", 0)
	task.wait(0.1)
	l = look(cover)
	check(list, "2 can't see a target behind the wall", l.Fov.Point == nil and l.Fov.Why == "blocked" and l.NoFov.Why == "blocked", { l.Fov.Why, l.NoFov.Why })
	-- 2b the wall is what blocks: removed (server), the same target is visible
	local wall = range():FindFirstChild("WallA") :: BasePart
	wall.Parent = nil
	l = look(cover)
	wall.Parent = range()
	check(list, "2b same spot visible without the wall", l.Fov.Point ~= nil, l.Fov.Why)
	cover:Destroy()
	-- 3 outside the field of view (90 deg to the side), clear line and in range
	local side = Run.dummy("T_Side", Run.spot("SpotSide"), "Blue", 0)
	task.wait(0.1)
	l = look(side)
	check(list, "3 outside the field of view is not acquirable", l.Fov.Point == nil and l.Fov.Why == "fov" and l.NoFov.Point ~= nil, { l.Fov.Why, l.NoFov.Why })
	side:Destroy()
	-- 3b inside the field of view at 55 deg (half FOV 60)
	local a = math.rad(55)
	local edgePos = BOT_POS + Vector3.new(-math.sin(a), 0, math.cos(a)) * 30
	local edge = Run.dummy("T_Edge", edgePos, "Blue", 0)
	task.wait(0.1)
	l = look(edge)
	check(list, "3b inside the field of view at 55 deg", l.Fov.Point ~= nil, l.Fov.Why)
	edge:Destroy()
	local b2 = math.rad(65)
	local outPos = BOT_POS + Vector3.new(-math.sin(b2), 0, math.cos(b2)) * 30
	local out = Run.dummy("T_Out", outPos, "Blue", 0)
	task.wait(0.1)
	l = look(out)
	check(list, "3c outside the field of view at 65 deg", l.Fov.Point == nil and l.Fov.Why == "fov", l.Fov.Why)
	out:Destroy()
	-- 4 out of range (140 studs)
	local far = Run.dummy("T_Far", Run.spot("SpotFar"), "Blue", 0)
	task.wait(0.1)
	l = look(far)
	check(list, "4 out of range", l.Fov.Point == nil and l.Fov.Why == "range", l.Fov.Why)
	far:Destroy()
	-- 5 a friend (Red) in the open is never an enemy
	local friend = Run.dummy("T_Friend", Run.spot("SpotFriend"), "Red", 0)
	task.wait(0.1)
	l = look(friend)
	check(list, "5 a friendly target is not an enemy", l.Enemy == false, l)
	-- 6 a dead body is not a target
	local deadOne = Run.dummy("T_Dead", Run.spot("SpotOpen"), "Blue", 0)
	task.wait(0.2)
	bodyHook("hit", deadOne, "Head", Vector3.new(0, 0, -0.5))
	waitFor(4, function()
		return deadOne:GetAttribute("BodyPhase") == "DEAD" or deadOne:GetAttribute("BodyPhase") == "DYING"
	end)
	l = look(deadOne)
	check(list, "6 a DYING / DEAD body is not a valid target", l.Alive == false, deadOne:GetAttribute("BodyPhase"))
	-- 7 itself
	l = look(bot)
	check(list, "7 never itself", l.Enemy == false, nil)
	-- 8 live: enabled with only a friend and a dead body in view → stays in SEARCH, never fires
	ai("set", "T_P", { Enabled = true })
	task.wait(2)
	local st = ai("status", "T_P")
	check(list, "8 friend / dead in view: no target, no shot", st.State == "SEARCH" and st.Target == nil and st.WeaponShots == 0, { st.State, st.Target, st.WeaponShots })
	-- 9 live: an enemy appears in the open → acquired within one scan
	ai("set", "T_P", { HoldFire = true })
	local t0 = os.clock()
	local enemy = Run.dummy("T_Enemy", Vector3.new(-745, 3, 182), "Blue", 0)
	local ok, dt = waitFor(2, function()
		return ai("status", "T_P").Target == "T_Enemy"
	end)
	check(list, "9 an enemy appearing in view is acquired within one scan (+ bind)", ok and dt <= AIConfig.Perception.ScanSeconds + 0.1, r3(dt))
	-- 10 the held target goes behind the wall (server moves it): lost after LostAfterSeconds
	enemy:Destroy()
	local hidden = Run.dummy("T_Hidden", Run.spot("SpotCover"), "Blue", 0)
	local okLost, dtLost = waitFor(2, function()
		return ai("status", "T_P").State == "SEARCH" -- T_Enemy gone → invalid → SEARCH; T_Hidden never seen
	end)
	check(list, "10 a removed target is dropped; one behind the wall is never acquired", okLost and ai("status", "T_P").Target == nil, r3(dtLost))
	hidden:Destroy()
	friend:Destroy()
	deadOne:Destroy()
	local perf = ai("perf")
	check(list, "11 perception cost recorded", perf.Scans > 0, { scans = perf.Scans, rays = perf.Rays, looks = perf.Looks, scanMs = r3(perf.ScanSeconds * 1000) })
	_ = t0
	Run.cleanup(true)
	return summary(list)
end

-------------------------------------------------------------------------------------------------------------------- aiming
local function angleDeg(a: Vector3, b: Vector3): number
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

function Run.aiming(): any
	Run.setup()
	local list = {}
	-- target 50 deg to the bot's right (inside the 60 deg half field of view), hold fire
	local a = math.rad(50)
	local tpos = BOT_POS + Vector3.new(-math.sin(a), 0, math.cos(a)) * 30
	local bot = Run.bot("T_A", BOT_POS, 180, { HoldFire = true, Seed = 11 })
	task.wait(0.3)
	local yaw0 = ai("status", "T_A").Yaw
	local samples = {}
	local t0 = os.clock()
	local d = Run.dummy("T_Tgt", tpos, "Blue", 0)
	local root = bot:FindFirstChild("HumanoidRootPart") :: BasePart
	while os.clock() - t0 < 1.6 do
		local s = ai("status", "T_A")
		table.insert(samples, { t = os.clock() - t0, yaw = s.Yaw, state = s.State, err = s.AimErrorDeg, look = root.CFrame.LookVector })
		task.wait()
	end
	local s = ai("status", "T_A")
	local want = (d:FindFirstChild("UpperTorso") :: BasePart).Position - (bot:FindFirstChild("Head") :: BasePart).Position
	local turnDeg = math.deg(math.abs(((s.Yaw - yaw0) + math.pi) % (2 * math.pi) - math.pi))
	check(list, "1 body turned toward the target", math.abs(turnDeg - 50) < 3, r3(turnDeg))
	-- turn time: from the first sample that moved to the first within 1 deg of final
	local tStart, tEnd
	for _, x in samples do
		local moved = math.deg(math.abs(((x.yaw - yaw0) + math.pi) % (2 * math.pi) - math.pi))
		if not tStart and moved > 0.5 then
			tStart = x.t
		end
		if tStart and not tEnd and math.abs(moved - turnDeg) < 1 then
			tEnd = x.t
		end
	end
	local rate = if tStart and tEnd and tEnd > tStart then turnDeg / (tEnd - tStart) else nil
	check(list, "2 turn rate limited (aim 240 deg/s, body 360 deg/s)", rate ~= nil and rate <= 260 and rate >= 120, { rate = r3(rate), start = r3(tStart), done = r3(tEnd) })
	-- 3 aim on the target (3D, incl. pitch to the chest) within the fire tolerance
	check(list, "3 aim within the fire tolerance", s.AimErrorDeg ~= nil and s.AimErrorDeg <= AIConfig.Aim.FireToleranceDeg, r3(s.AimErrorDeg))
	-- 4 body facing applied by the accepted HitReaction (root look = server yaw)
	local look = root.CFrame.LookVector
	local yawLook = math.atan2(-look.X, -look.Z)
	local diff = math.deg(math.abs(((yawLook - s.Yaw) + math.pi) % (2 * math.pi) - math.pi))
	check(list, "4 root faces the server yaw (HitReaction applied BodyFacingYaw)", diff < 0.5 and bot:GetAttribute("BodyFacingYaw") ~= nil, r3(diff))
	-- 5 aim and body are separate: aim has pitch (chest is below the eye), the body stays upright
	local aimPitch = math.deg(math.asin(math.clamp(s.Aim.Y, -1, 1)))
	check(list, "5 aim direction has its own pitch; the body stays level", aimPitch < -0.5 and math.abs(look.Y) < 1e-3, { aimPitch = r3(aimPitch), rootLookY = r3(look.Y) })
	-- 6 the rifle turned with the body (still in the hand, pointing along the facing)
	local rifle = range():FindFirstChild("T_A_Rifle") :: Model
	local rl = (rifle.PrimaryPart :: BasePart).CFrame.LookVector
	check(list, "6 rifle held and turned with the body", angleDeg(Vector3.new(rl.X, 0, rl.Z), Vector3.new(look.X, 0, look.Z)) < 2, r3(angleDeg(Vector3.new(rl.X, 0, rl.Z), Vector3.new(look.X, 0, look.Z))))
	-- 7 state sequence: ACQUIRE → AIM → FIRE (held: no shot)
	local seq = {}
	for _, e in ai("events", "T_A") do
		if e.kind == "state" then
			table.insert(seq, e.detail)
		end
	end
	check(list, "7 states SEARCH → ACQUIRE → AIM → FIRE with fire held", s.State == "FIRE" and s.WeaponShots == 0 and s.Held > 0, seq)
	_ = want
	-- 8 accuracy is deterministic: two bots with the same seed scatter identically about their aim
	Run.cleanup(true)
	local function firstErrors(name: string, pos: Vector3, tgt: Vector3): { number }
		Run.bot(name, pos, 180, { Seed = 77, HoldFire = false })
		Run.dummy(name .. "_D", tgt, "Blue", 0)
		waitFor(4, function()
			return #ai("shots", name) >= 3
		end)
		local out = {}
		for i, sh in ai("shots", name) do
			if i <= 3 then
				table.insert(out, r3(angleDeg(sh.Dir, sh.Aim)) :: number)
			end
		end
		ai("set", name, { HoldFire = true })
		return out
	end
	local e1 = firstErrors("T_S1", BOT_POS, Run.spot("SpotOpen"))
	local e2 = firstErrors("T_S2", BOT_POS + Vector3.new(30, 0, 0), Run.spot("SpotOpen") + Vector3.new(30, 0, 0))
	-- (the two aims point differently, so the angles agree to float rounding, not bit for bit)
	local same = #e1 == 3 and #e2 == 3
	for i = 1, math.min(#e1, #e2) do
		same = same and math.abs(e1[i] - e2[i]) < 0.005
	end
	local within = true
	for _, x in e1 do
		within = within and x <= AIConfig.Accuracy.ErrorDeg + 1e-3
	end
	check(list, "8 seeded scatter: same seed → same per-shot error, inside the cone", same and within, { e1, e2 })
	Run.cleanup(true)
	return summary(list)
end

-------------------------------------------------------------------------------------------------------------------- firing
function Run.firing(): any
	Run.setup()
	local list = {}
	local bot = Run.bot("T_F", BOT_POS, 180, { Seed = 5 })
	task.wait(0.3)
	ai("clearlogs", "T_F")
	-- several dummies in a row behind each other would block; use one, replaced when it goes down
	local function target(): Model
		return Run.dummy("T_FD" .. tostring(math.random(1, 1e6)), Run.spot("SpotOpen"), "Blue", 0)
	end
	target()
	local okShot = waitFor(4, function()
		return ai("status", "T_F").FirstShotAt ~= nil
	end)
	local s = ai("status", "T_F")
	local reaction = if s.FirstShotAt then s.FirstShotAt - s.AcquiredAt else nil
	check(list, "1 reaction delay before the first shot (>= 0.6 s + settle)", okShot and reaction ~= nil and reaction >= AIConfig.Reaction.FirstShotSeconds and reaction < AIConfig.Reaction.FirstShotSeconds + 0.4, r3(reaction))
	-- 2 shot origin = the bot's head (server), never anything else; the record is a normal weapon record
	local shots = ai("shots", "T_F")
	local sh = shots[1]
	local head = bot:FindFirstChild("Head") :: BasePart
	local recs = ballistics()
	local rec
	for i = #recs, 1, -1 do
		if recs[i].Player == "T_F" then
			rec = recs[i]
			break
		end
	end
	check(list, "2 shot traced from the bot's head with the M4's values", sh ~= nil and (sh.Eye - head.Position).Magnitude < 0.6 and rec ~= nil and rec.Weapon == "M4" and rec.Bot == "T_F", { eyeOff = sh and r3((sh.Eye - head.Position).Magnitude), rec = rec and { rec.Player, rec.Weapon, rec.Bot } })
	-- keep the bot firing at a target that never goes down until 31 rounds are gone and the reload is done
	for _, c in range():GetChildren() do
		if string.sub(c.Name, 1, 4) == "T_FD" then
			c:Destroy()
		end
	end
	waitFor(2, function()
		return ai("status", "T_F").State == "SEARCH"
	end)
	ai("setammo", "T_F", { Mag = 30, Chambered = true, Reserve = { 30, 30 } })
	ai("clearlogs", "T_F")
	local tough = Run.tough("T_FT", Run.spot("SpotOpen"), "Blue")
	local t0 = os.clock()
	local reloadSeen, reloadDone = nil, nil
	while os.clock() - t0 < 25 do
		local st = ai("status", "T_F")
		if st.Reload and not reloadSeen then
			reloadSeen = st.Reload
		end
		if reloadSeen and not st.Reload and not reloadDone then
			reloadDone = st
			break
		end
		task.wait(0.05)
	end
	local toughHealth = (tough:FindFirstChildOfClass("Humanoid") :: Humanoid).Health
	tough:Destroy()
	shots = ai("shots", "T_F")
	local events = ai("events", "T_F")
	-- 3 rate inside bursts = the M4's 770 RPM (Heartbeat-quantised)
	local gaps, bursts, cur = {}, {}, 1
	for i = 2, #shots do
		local g = shots[i].t - shots[i - 1].t
		if g < 0.2 then
			table.insert(gaps, g)
			cur += 1
		else
			table.insert(bursts, { n = cur, pause = g })
			cur = 1
		end
	end
	local mean = 0
	for _, g in gaps do
		mean += g
	end
	mean = if #gaps > 0 then mean / #gaps else 0
	check(list, "3 rate within a burst ~ 770 RPM (mean gap ~0.078 s)", #gaps >= 5 and math.abs(mean - 60 / M4.Fire.RPM) < 0.01, { meanGap = r3(mean), rpm = r3(60 / math.max(mean, 1e-6)), n = #gaps })
	-- 4 bursts 3-5 rounds, pauses 0.35-0.7 s (bursts cut short by the target going down / the reload are excluded)
	local okB = #bursts >= 2
	for _, b in bursts do
		okB = okB and b.pause >= AIConfig.Fire.PauseMinSeconds - 0.02
	end
	check(list, "4 bursts with pauses >= 0.35 s", okB, bursts)
	-- 5 31 rounds, then the empty reload with the M4's measured Regular timing
	local reloadStart, reloadEnd
	for _, e in events do
		if e.kind == "reload" and e.detail == "EmptyRegular" then
			reloadStart = e.t
		elseif e.kind == "reload" and e.detail == "EmptyRegular done" then
			reloadEnd = e.t
		end
	end
	local before = 0
	for _, x in shots do
		if reloadStart and x.t < reloadStart then
			before += 1
		end
	end
	check(list, "5 31 rounds (30 + 1) before the reload", before == 31, before)
	local dur = if reloadStart and reloadEnd then reloadEnd - reloadStart else nil
	check(list, "6 empty reload lasts the M4 EmptyRegular duration (3.70 s)", dur ~= nil and math.abs(dur - M4.Reloads.EmptyRegular.Duration) < 0.05, r3(dur))
	-- (the bot may already have fired again when the status is read, so the count comes from the first shot after)
	local firstAfter = nil
	for _, x in shots do
		if reloadEnd and x.t >= reloadEnd and not firstAfter then
			firstAfter = x
		end
	end
	check(list, "7 after the reload: 30 rounds loaded (29 left after the next shot), empty magazine dropped, one spare left",
		reloadDone ~= nil and firstAfter ~= nil and firstAfter.Rounds == 29 and #reloadDone.Reserve == 1 and #reloadDone.Dropped == 1 and reloadDone.Dropped[1] == 0,
		reloadDone and { afterNextShot = firstAfter and firstAfter.Rounds, reserve = reloadDone.Reserve, dropped = reloadDone.Dropped })
	local noShotInReload = true
	for _, x in shots do
		if reloadStart and reloadEnd and x.t > reloadStart and x.t < reloadEnd then
			noShotInReload = false
		end
	end
	check(list, "8 no shot during the reload", noShotInReload, nil)
	local hitsOnTough = 0
	for _, x in shots do
		for _, hh in x.Hits do
			if hh.Target == "T_FT" and (hh.Dealt or 0) > 0 then
				hitsOnTough += 1
			end
		end
	end
	check(list, "8b non-body target: the shot path's placeholder damage (25 / 50 head)", hitsOnTough > 0 and toughHealth < 1e7, { hits = hitsOnTough, lost = 1e7 - toughHealth })
	-- 9 muzzle counter = shots (client flash source)
	local rifle = range():FindFirstChild("T_F_Rifle") :: Model
	local st = ai("status", "T_F")
	check(list, "9 rifle shot counter = weapon shots", rifle:GetAttribute("AIShots") == st.WeaponShots, { rifle:GetAttribute("AIShots"), st.WeaponShots })
	-- 10 no reserve: nothing to reload, never fires
	ai("setammo", "T_F", { Mag = 0, Chambered = false, Reserve = {} })
	ai("clearlogs", "T_F")
	target()
	task.wait(2)
	st = ai("status", "T_F")
	check(list, "10 empty with no reserve: no shot, no reload", #ai("shots", "T_F") == 0 and st.Reload == nil and st.Counts.NoAmmo == 1, { st.State, st.Counts })
	Run.cleanup(true)
	return summary(list)
end

--------------------------------------------------------------------------------------------------------------- integration
function Run.integration(): any
	Run.setup()
	local list = {}
	blood("clear")
	-- A: bot vs a body (the accepted REACT1): hits → BodyState → flinch → down → ragdoll → blood
	local bot = Run.bot("T_I", BOT_POS, 180, { Seed = 3 })
	task.wait(0.3)
	local d = Run.dummy("T_ID", Run.spot("SpotOpen"), "Blue", 0)
	waitFor(1, function()
		return pres("status", d).Bound == true -- BodyPresentation binds new bodies on the next frame
	end)
	pres("watch", d, 6)
	local okDown = waitFor(6, function()
		return d:GetAttribute("BodyStance") ~= nil and d:GetAttribute("BodyStance") ~= "STANDING"
	end)
	task.wait(1.5)
	local shots = ai("shots", "T_I")
	local hitShots = 0
	for _, s in shots do
		for _, h in s.Hits do
			if h.Target == "T_ID" and h.Body then
				hitShots += 1
			end
		end
	end
	local rec = bodyHook("get", d)
	check(list, "A1 bot bullets hit the body through BodyState (wound, phase)", hitShots >= 1 and rec ~= nil and (rec.Hits or 0) >= 1, { hitShots = hitShots, phase = rec and rec.Phase, wound = rec and rec.Wound, hits = rec and rec.Hits })
	local samples = pres("samples", d)
	local flinch, ragdoll = false, false
	for _, x in samples do
		if (x.armSwing or 0) > 1 then
			flinch = true
		end
		if x.ragdoll then
			ragdoll = true
		end
	end
	check(list, "A2 the hit body reacted (flinch) and went down in the active ragdoll", okDown and ragdoll and (flinch or (rec and rec.Hits == 1)), { flinch = flinch, ragdoll = ragdoll, stance = d:GetAttribute("BodyStance") })
	local bl = blood("counts")
	local botImpacts = 0
	for _, r in blood("recent") do
		if r.Player == nil and r.Weapon == "M4" then
			botImpacts += 1
		end
	end
	check(list, "A3 blood from the bot's shots (existing Impacts: body stains / marks)", botImpacts >= 1 and (bl.Stains + bl.Marks + bl.Drops + bl.Pools) > 0,
		{ impacts = botImpacts, stains = bl.Stains, marks = bl.Marks, drops = bl.Drops, pools = bl.Pools })
	local st = ai("status", "T_I")
	local after = 0
	local downAt = nil
	for _, e in ai("events", "T_I") do
		if e.kind == "target" and string.find(e.detail or "", "no longer valid") then
			downAt = e.t
		end
	end
	for _, s in shots do
		if downAt and s.t > downAt then
			after += 1
		end
	end
	check(list, "A4 bot stops shooting a body once it is down", downAt ~= nil and after == 0 and st.Target == nil, { after = after, state = st.State })
	-- B: hold fire while the bot itself is reacting (shot by the test through BodyState's own hit entry)
	ai("clearlogs", "T_I")
	ai("refill", "T_I")
	local d2 = Run.dummy("T_ID2", Run.spot("SpotOpen") + Vector3.new(3, 0, 2), "Blue", 0)
	waitFor(3, function()
		return ai("status", "T_I").State == "FIRE"
	end)
	bodyHook("hit", bot, "LeftUpperArm", Vector3.new(0, 0, -0.3))
	local held0 = ai("status", "T_I").Held
	task.wait(0.15)
	local reactingNow = bot:GetAttribute("BodyReacting") == true
	task.wait(0.5)
	st = ai("status", "T_I")
	check(list, "B1 holds fire while its own flinch window is open (BodyReacting)", reactingNow and st.Held > held0, { reacting = reactingNow, held = st.Held - held0 })
	d2:Destroy()
	Run.cleanup(true)
	-- C: bot vs bot
	local red = Run.bot("T_RED", BOT_POS, 180, { Seed = 21, Team = "Red" })
	local blue = Run.bot("T_BLUE", Run.spot("SpotOpen"), 0, { Seed = 22, Team = "Blue" })
	local okC = waitFor(12, function()
		return ai("status", "T_RED").DownAt ~= nil or ai("status", "T_BLUE").DownAt ~= nil
	end)
	task.wait(1.2)
	local sr, sb = ai("status", "T_RED"), ai("status", "T_BLUE")
	local loser = if sr.DownAt then sr else sb
	local winner = if sr.DownAt then sb else sr
	local loserShotsAfter = 0
	for _, s in ai("shots", loser.Name) do
		if s.t > loser.DownAt then
			loserShotsAfter += 1
		end
	end
	local winnerHits = 0
	for _, s in ai("shots", winner.Name) do
		for _, hh in s.Hits do
			if hh.Target == loser.Name and hh.Body then
				winnerHits += 1
			end
		end
	end
	check(list, "C1 bot vs bot: each acquired the other; the loser went down from the winner's bullets (BodyState)", okC and (sr.Counts.Acquired or 0) >= 1 and (sb.Counts.Acquired or 0) >= 1 and winnerHits >= 1,
		{ red = { sr.State, sr.WeaponShots, sr.Counts.Acquired }, blue = { sb.State, sb.WeaponShots, sb.Counts.Acquired }, winnerHits = winnerHits })
	check(list, "C2 the downed bot stopped (DOWN / DEAD, no shot after)", (loser.State == "DOWN" or loser.State == "DEAD") and loserShotsAfter == 0, { loser.Name, loser.State, loserShotsAfter })
	local let = if loser.DroppedAt and loser.DownAt then loser.DroppedAt - loser.DownAt else nil
	check(list, "C3 rifle let go 0.2-0.5 s after going down, now a free prop", let ~= nil and let >= 0.2 and let <= 0.5 and loser.RifleHeld == false, r3(let))
	check(list, "C4 the winner dropped its target (SEARCH / RELOAD)", winner.Target == nil and (winner.State == "SEARCH" or winner.State == "RELOAD"), { winner.Name, winner.State })
	local loserModel = range():FindFirstChild(loser.Name) :: Model
	check(list, "C5 the downed bot's body is BodyState's (persistent body)", loserModel ~= nil and loserModel:GetAttribute("BodyStance") ~= "STANDING", loserModel and { loserModel:GetAttribute("BodyPhase"), loserModel:GetAttribute("BodyStance"), loserModel:GetAttribute("BodyBehaviour") })
	Run.cleanup(true)
	return summary(list)
end

-------------------------------------------------------------------------------------------------------------- performance
function Run.performance(n: number, seconds: number?): any
	Run.setup()
	local secs = seconds or 4
	-- n bots in a line facing +Z. First with nothing to see (searching: scans only), then each with its own target 30
	-- studs ahead (hold fire: line of sight + aim only), then all firing.
	for i = 1, n do
		local x = -790 + (i - 1) * 6
		Run.bot("T_N" .. i, Vector3.new(x, 3, 150), 180, { HoldFire = true, Seed = 100 + i })
	end
	task.wait(0.5)
	ai("resetperf")
	task.wait(secs)
	local p = ai("perf")
	local search = {
		bots = p.Bots,
		frames = p.Frames,
		loopMsPerFrame = r3(p.LoopSeconds / math.max(p.Frames, 1) * 1000),
		maxLoopMs = r3(p.MaxLoopSeconds * 1000),
		scansPerSec = r3(p.Scans / secs),
		usPerScan = r3(p.ScanSeconds / math.max(p.Scans, 1) * 1e6),
		raysPerSec = r3(p.Rays / secs),
	}
	for i = 1, n do
		local x = -790 + (i - 1) * 6
		Run.dummy("T_ND" .. i, Vector3.new(x, 3, 180), "Blue", 0)
	end
	task.wait(1.5)
	ai("resetperf")
	task.wait(secs)
	p = ai("perf")
	local hold = {
		bots = p.Bots,
		frames = p.Frames,
		loopMsPerFrame = r3(p.LoopSeconds / math.max(p.Frames, 1) * 1000),
		maxLoopMs = r3(p.MaxLoopSeconds * 1000),
		scansPerSec = r3(p.Scans / secs),
		losChecksPerSec = r3(p.LosChecks / secs),
		raysPerSec = r3(p.Rays / secs),
		usPerLos = r3(p.LosSeconds / math.max(p.LosChecks, 1) * 1e6),
	}
	-- firing: release all
	for i = 1, n do
		ai("set", "T_N" .. i, { HoldFire = false })
	end
	ai("resetperf")
	task.wait(2)
	p = ai("perf")
	local fire = {
		frames = p.Frames,
		loopMsPerFrame = r3(p.LoopSeconds / math.max(p.Frames, 1) * 1000),
		maxLoopMs = r3(p.MaxLoopSeconds * 1000),
		shots = p.Shots,
		msPerShot = r3(p.ShotSeconds / math.max(p.Shots, 1) * 1000),
		maxShotMs = r3(p.MaxShotSeconds * 1000),
	}
	Run.cleanup(true)
	return { search = search, hold = hold, fire = fire }
end

------------------------------------------------------------------------------------------------------- player as target
-- The client test (StarterPlayerScripts.AITest.Run { path = ... }) walks the player; this samples, on the server clock
-- (the same process clock as the client's in Studio), where the server sees the player and what the bot does.
local watching = { On = false, Samples = {} :: { any } }

function Run.watchStart(botName: string, seconds: number?): number
	watching.On = true
	watching.Samples = {}
	local p = Players:GetPlayers()[1]
	task.spawn(function()
		local t0 = os.clock()
		while watching.On and os.clock() - t0 < (seconds or 30) do
			local s = ai("status", botName)
			local c = p.Character
			local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			table.insert(watching.Samples, { t = os.clock(), pos = root and root.Position, state = s.State, target = s.Target, visible = s.Visible, yaw = s.Yaw })
			task.wait()
		end
	end)
	return os.clock()
end

-- The walk used by the tests: side (outside the field of view) → open (enters it) → side (a held target leaves it)
-- → behind WallA → open again. Feet positions; the client faces the bot at each.
Run.PlayerPath = {
	{ "side", Vector3.new(-780, 3, 150) },
	{ "open", Vector3.new(-740, 3, 180) },
	{ "side (held)", Vector3.new(-780, 3, 150) },
	{ "cover", Vector3.new(-760, 3, 180) },
	{ "open again", Vector3.new(-740, 3, 180) },
}

-- moments: the client's move times. Returns the checks for scenarios 3 / 4 / 5 / 6 / 12-14 with the player as target.
function Run.playerChecks(botName: string, moments: { number }): any
	watching.On = false
	local S = watching.Samples
	local spots = Run.PlayerPath
	local t0 = moments[1]
	local arrive = {}
	for i, m in moments do
		for _, s in S do
			if s.t >= m - 0.2 and s.pos and (Vector3.new(s.pos.X, 3, s.pos.Z) - spots[i][2]).Magnitude < 1.5 then
				arrive[i] = s.t - t0
				break
			end
		end
	end
	local ev = {}
	for _, e in ai("events", botName) do
		if e.t >= t0 - 0.2 then
			table.insert(ev, { t = e.t - t0, kind = e.kind, detail = e.detail or "" })
		end
	end
	local function first(after: number, kind: string, text: string): number?
		for _, e in ev do
			if e.t >= after and e.kind == kind and string.find(e.detail, text, 1, true) then
				return e.t
			end
		end
		return nil
	end
	local list = {}
	local P, Rc = AIConfig.Perception, AIConfig.Reaction
	-- side: no acquisition while outside the field of view
	local acq = first(0, "target", "(acquired")
	check(list, "P1 player outside the field of view (side) is not acquired", arrive[1] ~= nil and (acq == nil or acq >= moments[2] - t0), { arrive = r3(arrive[1]), acquired = r3(acq) })
	-- open: acquired within a scan of the server seeing the player there (or while it arrives)
	check(list, "P2 player entering the field of view is acquired (within one scan)", acq ~= nil and arrive[2] ~= nil and acq - (moments[2] - t0) <= P.ScanSeconds + 0.15, { moved = r3(moments[2] - t0), seen = r3(arrive[2]), acquired = r3(acq) })
	local aim1 = if acq then first(acq, "state", "ACQUIRE -> AIM") else nil
	check(list, "P3 reaction delay after acquiring (0.6 s) before aiming / firing", aim1 ~= nil and acq ~= nil and math.abs((aim1 - acq) - Rc.FirstShotSeconds) < 0.05, r3(if aim1 and acq then aim1 - acq else nil))
	-- side again: the held target is kept and tracked out of the field of view (the body turns 90 deg)
	local dropped = nil
	for _, e in ev do
		if arrive[3] and e.t >= (moments[3] - t0) and e.t < (moments[4] - t0) and e.kind == "state" and string.find(e.detail, "-> SEARCH", 1, true) then
			dropped = e.t
		end
	end
	local yawAtSide = nil
	for _, s in S do
		if s.t < moments[4] - 0.3 then -- (the client logs a move after its teleport frames: stop short of it)
			yawAtSide = s.yaw
		end
	end
	local wantYaw = math.deg(math.atan2(-(spots[3][2].X - BOT_POS.X), -(spots[3][2].Z - BOT_POS.Z)))
	check(list, "P4 a held target leaving the field of view is kept and tracked", dropped == nil and yawAtSide ~= nil and math.abs(math.deg(yawAtSide) - wantYaw) < 6, { yaw = r3(yawAtSide and math.deg(yawAtSide)), want = r3(wantYaw) })
	-- cover: lost after LostAfterSeconds unseen
	local lost = if arrive[4] then first(arrive[4] - 0.3, "target", "lost (blocked)") else nil
	local lostDelay = if lost and arrive[4] then lost - arrive[4] else nil
	check(list, "P5 target behind cover is lost (~0.4 s unseen)", lostDelay ~= nil and lostDelay >= P.LostAfterSeconds - 0.2 and lostDelay <= P.LostAfterSeconds + P.LosSeconds + 0.2, r3(lostDelay))
	local wrongShots = 0
	for _, sh in ai("shots", botName) do
		if lost and sh.t - t0 > lost and sh.t - t0 < (moments[5] - t0) then
			wrongShots += 1
		end
	end
	check(list, "P6 no shot while the target is lost", wrongShots == 0, wrongShots)
	-- open again: reacquired with the reacquire delay
	local re = first(moments[5] - t0 - 0.3, "target", "seen again")
	local aim2 = if re then first(re, "state", "ACQUIRE -> AIM") else nil
	check(list, "P7 reappearing target is reacquired; next shot after the 0.5 s reacquire delay", re ~= nil and aim2 ~= nil and math.abs((aim2 - re) - Rc.ReacquireSeconds) < 0.05, { seenAgain = r3(re), delay = r3(if re and aim2 then aim2 - re else nil) })
	local transitions, last = {}, nil
	for _, s in S do
		local key = tostring(s.state) .. "/" .. tostring(s.target) .. "/" .. tostring(s.visible)
		if key ~= last then
			table.insert(transitions, string.format("%.3f %s yaw %.1f", s.t - t0, key, math.deg(s.yaw)))
			last = key
		end
	end
	local out = summary(list)
	out.transitions = transitions
	out.arrivals = arrive
	return out
end

-- The bot fires at the player standing in the open: the existing placeholder damage (25 / round, as a player's shot
-- at another player), a real death, the existing respawn.
function Run.playerShot(botName: string): any
	local list = {}
	local p = Players:GetPlayers()[1]
	local char = p.Character :: Model
	local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid
	local died = nil
	local conn = hum.Died:Connect(function()
		died = os.clock()
	end)
	ai("clearlogs", botName)
	local t0 = os.clock()
	ai("set", botName, { HoldFire = false })
	waitFor(5, function()
		return died ~= nil
	end)
	conn:Disconnect()
	local hits, dealt = 0, 0
	for _, s in ai("shots", botName) do
		for _, h in s.Hits do
			if h.Target == p.Name then
				hits += 1
				dealt += h.Dealt or 0
			end
		end
	end
	check(list, "Q1 bot rounds hit the player: placeholder damage 25 per round (50 head), the shot path a player's shot takes", hits > 0 and dealt >= 100 and dealt % 25 == 0, { hits = hits, dealt = dealt })
	check(list, "Q2 the player died from them (real Humanoid death)", died ~= nil, r3(died and died - t0))
	task.wait(0.4)
	local st = ai("status", botName)
	check(list, "Q3 the bot dropped the dead player (SEARCH)", st.Target == nil and (st.State == "SEARCH" or st.State == "RELOAD"), st.State)
	check(list, "Q4 no creator tag / hit marker for a bot (no Player)", hum:FindFirstChild("creator") == nil, nil)
	local respawned = waitFor(10, function()
		return p.Character ~= nil and p.Character ~= char and p.Character:FindFirstChildOfClass("Humanoid") ~= nil
	end)
	check(list, "Q5 the existing respawn brings the player back", respawned, nil)
	ai("set", botName, { HoldFire = true })
	return summary(list)
end

-- The player's real M4 (client { shootBot }) put a bot down: through the accepted shot path and BodyState only.
function Run.shotDown(botName: string): any
	local list = {}
	task.wait(0.8)
	local p = Players:GetPlayers()[1]
	local m = range():FindFirstChild(botName) :: Model
	local st = ai("status", botName)
	local lines = {}
	for _, x in game:GetService("LogService"):GetLogHistory() do
		if string.find(x.message, p.Name .. " M4 hit body " .. botName, 1, true) then
			table.insert(lines, x.message)
		end
	end
	check(list, "K1 the player's M4 rounds hit the bot through BodyState (server log)", #lines >= 1, lines)
	check(list, "K2 the bot is down by BodyState (stance not STANDING; phase DYING / DEAD or down)", m:GetAttribute("BodyStance") ~= "STANDING", { m:GetAttribute("BodyPhase"), m:GetAttribute("BodyStance"), m:GetAttribute("BodyWound") })
	check(list, "K3 the AI stopped: DOWN / DEAD, target cleared, reload cancelled", (st.State == "DOWN" or st.State == "DEAD") and st.Target == nil and st.Reload == nil, st.State)
	local let = if st.DroppedAt and st.DownAt then st.DroppedAt - st.DownAt else nil
	check(list, "K4 rifle let go 0.2-0.5 s after going down", let ~= nil and let >= 0.2 and let <= 0.5 and st.RifleHeld == false, r3(let))
	local after = 0
	for _, s in ai("shots", botName) do
		if st.DownAt and s.t > st.DownAt then
			after += 1
		end
	end
	check(list, "K5 no bot shot after going down", after == 0, after)
	local pr = pres("status", m)
	check(list, "K6 the accepted active ragdoll presents the downed bot", pr.Ragdoll ~= nil, pr.Ragdoll ~= nil)
	return summary(list)
end

-- Security: snapshot the bot's server state, let the client send its forged inputs, compare.
local function rejectionsOf(name: string): { string }
	local out = {}
	for _, m in game:GetService("LogService"):GetLogHistory() do
		if string.find(m.message, "[Weapon] rejected shot from " .. name, 1, true) then
			table.insert(out, m.message)
		end
	end
	return out
end

function Run.securityBefore(botName: string): any
	local m = range():FindFirstChild(botName) :: Model
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart
	local p = Players:GetPlayers()[1]
	return {
		Status = ai("status", botName),
		RootLook = root.CFrame.LookVector,
		Facing = m:GetAttribute("BodyFacingYaw"),
		Hits = m:GetAttribute("BodyHits"),
		Phase = m:GetAttribute("BodyPhase"),
		Life = m:GetAttribute("BodyLife"),
		Strength = m:GetAttribute("BodyStrength"),
		Health = (m:FindFirstChildOfClass("Humanoid") :: Humanoid).Health,
		Rejections = #rejectionsOf(p.Name),
	}
end

function Run.securityAfter(botName: string, before: any): any
	local list = {}
	local m = range():FindFirstChild(botName) :: Model
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart
	local p = Players:GetPlayers()[1]
	local s = ai("status", botName)
	local b = before.Status
	local rej = rejectionsOf(p.Name)
	local newRej = {}
	for i = before.Rejections + 1, #rej do
		table.insert(newRej, rej[i])
	end
	local originRejected = false
	for _, x in newRej do
		if string.find(x, "studs from head", 1, true) then
			originRejected = true
		end
	end
	check(list, "S1 force fire: no bot shot, not in FIRE", s.WeaponShots == b.WeaponShots and s.State ~= "FIRE", { s.State, s.WeaponShots })
	check(list, "S2 choose target: the bot has no target (player hidden behind the wall)", s.Target == nil, s.Target)
	check(list, "S3 set aim: server yaw, facing attribute and root unchanged", math.abs(s.Yaw - b.Yaw) < 1e-6 and m:GetAttribute("BodyFacingYaw") == before.Facing and root.CFrame.LookVector:Dot(before.RootLook) > 0.9999, { yaw = r3(math.deg(s.Yaw)) })
	check(list, "S4 shot origin at the bot's head: rejected by the player shot checks", originRejected, newRej)
	check(list, "S5 shot direction: no bot shot, aim unchanged", s.WeaponShots == b.WeaponShots and (s.Aim - b.Aim).Magnitude < 1e-6, nil)
	check(list, "S6 hit position: no hit on the bot (BodyHits unchanged)", m:GetAttribute("BodyHits") == before.Hits, m:GetAttribute("BodyHits"))
	check(list, "S7 damage: life / strength / health unchanged", m:GetAttribute("BodyLife") == before.Life and m:GetAttribute("BodyStrength") == before.Strength and (m:FindFirstChildOfClass("Humanoid") :: Humanoid).Health == before.Health, { m:GetAttribute("BodyLife"), m:GetAttribute("BodyStrength") })
	check(list, "S8 force reload: no reload, magazine unchanged", s.Reload == nil and s.Mag == b.Mag and s.Chambered == b.Chambered and s.WeaponReloads == b.WeaponReloads, { s.Mag, s.WeaponReloads })
	check(list, "S9 force death: still ALIVE and fighting-capable on the server", m:GetAttribute("BodyPhase") == before.Phase and s.State ~= "DOWN" and s.State ~= "DEAD" and s.DownAt == nil, { m:GetAttribute("BodyPhase"), s.State })
	check(list, "S10 line of sight: the wall is still there on the server; the player was never acquired", range():FindFirstChild("WallA") ~= nil and s.Target == nil and (s.Counts.Acquired or 0) == (b.Counts.Acquired or 0), s.Counts)
	return summary(list)
end

return Run
