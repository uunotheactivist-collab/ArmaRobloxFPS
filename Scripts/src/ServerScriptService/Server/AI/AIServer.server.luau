--!strict
-- AI / bot combat vertical slice (server only). One Heartbeat loop runs every bot; no per-bot threads.
-- Pipeline:
--   perception (Server.AI.Perception: valid / in range / in view / line of sight, staggered, server state only)
--   → decision (the state machine below: target, reaction delay, aim, bursts, reload)
--   → fire request (Server.AI.BotWeapon: the bot's own M4 ammunition, rate and measured reload timings)
--   → the shared authoritative shot (Server.WeaponShot: Ballistics trace from the bot's eye → BodyState.applyHit /
--     placeholder damage → Blood.Impacts → Ballistics.record), the same code a player's validated shot runs
--   → the accepted presentation (BodyPresentation: HitReaction / ActiveRagdoll read the hit body's BodyState).
-- A bot is a model with the server attribute AIBot = true and a team (AITeam). The accepted body systems treat it as
-- any other body (BodyModel, BodyPresentation = "ActiveRagdoll"): its hits, wounds, flinch, fall, dying and death are
-- BodyState's. This script only:
--   * decides, and publishes AIState / AITarget / AIMag (attributes; there is NO bot remote, so a client can't force
--     a state, target, aim, shot, reload or death: local attribute changes never reach the server);
--   * turns the standing body by writing BodyFacingYaw (Server.HitReaction applies it; aim pitch is not shown);
--   * holds the rifle (Server.AI.BotRifle) and lets it go after the body goes down.
-- States: IDLE (disabled) → SEARCH → ACQUIRE (reaction delay) → AIM (turn + settle) → FIRE (bursts) → RELOAD →
--   LOST_TARGET (unseen; reacquire delay if seen again) → DOWN (down / dying: can't fight) → DEAD (BodyPhase DEAD).
-- Every combat number is a placeholder (Config.AI): no bot ever fires in the reference (AI_Analysis.md A2).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("AI"))
local Perception = require(script.Parent:WaitForChild("Perception"))
local BotWeapon = require(script.Parent:WaitForChild("BotWeapon"))
local BotRifle = require(script.Parent:WaitForChild("BotRifle"))

local P, A, F, R, Acc = Config.Perception, Config.Aim, Config.Fire, Config.Reaction, Config.Accuracy
local LOG = true
local STUDIO = RunService:IsStudio()

type Bot = {
	Model: Model,
	Humanoid: Humanoid,
	Head: BasePart,
	Root: BasePart,
	Rifle: Model?,
	Weapon: BotWeapon.State,
	Seed: number,
	AimRng: Random,
	FireRng: Random,
	Enabled: boolean,
	HoldFire: boolean,
	State: string,
	StateAt: number,
	Target: Model?,
	TargetPart: BasePart?,
	TargetPoint: Vector3?,
	Visible: boolean,
	SeenAt: number,
	LostAt: number,
	LastWhy: string?,
	ReadyAt: number,
	AcquiredAt: number,
	Aim: Vector3,
	Desired: Vector3?,
	Yaw: number,
	WrittenYaw: number,
	OnTargetSince: number?,
	NextScanAt: number,
	NextLosAt: number,
	BurstLeft: number,
	PauseUntil: number,
	DownAt: number?,
	DroppedAt: number?,
	FirstShotAt: number?,
	Held: number,
	Errors: number,
	Events: { any },
	ShotLog: { any },
	Counts: { [string]: number },
}

local bots: { [Model]: Bot } = {}
local bound = 0
local Stats = {
	Frames = 0,
	LoopSeconds = 0,
	MaxLoopSeconds = 0,
	Scans = 0,
	ScanSeconds = 0,
	LosChecks = 0,
	LosSeconds = 0,
}

local function log(message: string)
	if LOG then
		print("[AI] " .. message)
	end
end

local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function angleBetween(a: Vector3, b: Vector3): number
	return math.acos(math.clamp(a:Dot(b), -1, 1))
end

local function facingOf(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

-- Rotate unit vector a toward unit vector b by at most maxRad.
local function rotateToward(a: Vector3, b: Vector3, maxRad: number): Vector3
	local th = angleBetween(a, b)
	if th <= maxRad or th < 1e-5 then
		return b
	end
	local s = math.sin(th)
	if s < 1e-4 then
		return (CFrame.fromAxisAngle(Vector3.yAxis, maxRad):VectorToWorldSpace(a)).Unit
	end
	local t = maxRad / th
	return ((a * math.sin((1 - t) * th) + b * math.sin(t * th)) / s).Unit
end

-- A direction inside a cone of `deg` about dir (uniform over the cone's disc), from the bot's seeded generator.
local function scatter(dir: Vector3, deg: number, rng: Random): Vector3
	local u, v = rng:NextNumber(), rng:NextNumber()
	if deg <= 0 then
		return dir
	end
	local th = math.rad(deg) * math.sqrt(u)
	local phi = v * 2 * math.pi
	local up = if math.abs(dir.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local cf = CFrame.lookAt(Vector3.zero, dir, up)
	local offset = Vector3.new(math.sin(th) * math.cos(phi), math.sin(th) * math.sin(phi), -math.cos(th))
	return cf:VectorToWorldSpace(offset).Unit
end

local function count(b: Bot, key: string)
	b.Counts[key] = (b.Counts[key] or 0) + 1
end

local function event(b: Bot, now: number, kind: string, detail: string?)
	if STUDIO then
		table.insert(b.Events, { t = now, kind = kind, detail = detail })
		while #b.Events > 200 do
			table.remove(b.Events, 1)
		end
	end
end

local function setState(b: Bot, state: string, now: number, why: string)
	if b.State == state then
		return
	end
	local from = b.State
	b.State = state
	b.StateAt = now
	b.Model:SetAttribute("AIState", state)
	event(b, now, "state", `{from} -> {state} ({why})`)
	if LOG then
		log(`{b.Model.Name} {from} -> {state} ({why})`)
	end
end

local function publishAmmo(b: Bot)
	b.Model:SetAttribute("AIMag", BotWeapon.rounds(b.Weapon))
	b.Model:SetAttribute("AIReloading", if b.Weapon.Reload then b.Weapon.Reload.Spec else nil)
end

local function ignoreOf(b: Bot): { Instance }
	return if b.Rifle then { b.Model, b.Rifle :: Instance } else { b.Model }
end

local function clearTarget(b: Bot)
	b.Target = nil
	b.TargetPart = nil
	b.TargetPoint = nil
	b.Visible = false
	b.Desired = nil
	b.OnTargetSince = nil
	b.Model:SetAttribute("AITarget", nil)
end

local function setTarget(b: Bot, target: Model, point: Vector3, part: BasePart, now: number, delay: number, why: string)
	b.Target = target
	b.TargetPart = part
	b.TargetPoint = point
	b.Visible = true
	b.SeenAt = now
	b.AcquiredAt = now
	b.ReadyAt = now + delay
	b.OnTargetSince = nil
	b.NextLosAt = now + P.LosSeconds
	b.Model:SetAttribute("AITarget", target.Name)
	count(b, "Acquired")
	event(b, now, "target", `{target.Name} ({why}, first shot allowed in {delay} s)`)
	setState(b, "ACQUIRE", now, `{why} {target.Name}`)
end

-- The closest valid, visible enemy (closest first, so the first visible one wins with the fewest rays).
local function scan(b: Bot): (Model?, Vector3?, BasePart?)
	local eye = b.Head.Position
	local list = {}
	for _, m in Perception.candidates() do
		if Perception.enemy(b.Model, m) and Perception.alive(m) then
			local ref = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
			if ref and ref:IsA("BasePart") then
				local d = (ref.Position - eye).Magnitude
				if d <= P.RangeStuds + 4 then
					table.insert(list, { m, d })
				end
			end
		end
	end
	table.sort(list, function(x, y)
		return x[2] < y[2]
	end)
	for _, e in list do
		local point, part = Perception.look(eye, facingOf(b.Yaw), e[1], ignoreOf(b), true)
		if point and part then
			return e[1], point, part
		end
	end
	return nil, nil, nil
end

local function enterDown(b: Bot, now: number)
	if b.DownAt then
		return
	end
	b.DownAt = now
	BotWeapon.cancel(b.Weapon)
	publishAmmo(b)
	clearTarget(b)
end

local function shoot(b: Bot, now: number)
	local m = b.Model
	local strength = m:GetAttribute("BodyStrength")
	local lost = 100 - (if type(strength) == "number" then strength else 100)
	local cone = Acc.ErrorDeg * (1 + Acc.WeakErrorScale * math.clamp(lost, 0, 100) / 100)
	local dir = scatter(b.Aim, cone, b.AimRng)
	local eye = b.Head.Position -- the server's own copy of the bot's eye, as a player's shot uses its head
	local trace, results = BotWeapon.fire(b.Weapon, { Player = nil, Character = m, Humanoid = b.Humanoid, Name = m.Name }, eye, dir, now)
	b.FirstShotAt = b.FirstShotAt or now
	count(b, "Shots")
	if b.Rifle then
		b.Rifle:SetAttribute(Config.ShotsAttribute, (b.Rifle:GetAttribute(Config.ShotsAttribute) or 0) + 1)
	end
	publishAmmo(b)
	local hits = {}
	for _, r in results do
		local owner = r.Humanoid and r.Humanoid.Parent
		table.insert(hits, {
			Target = owner and owner.Name,
			Part = r.Part,
			Body = r.Body and { Location = r.Body.Location, Wound = r.Body.Wound, PhaseBefore = r.Body.PhaseBefore, PhaseAfter = r.Body.PhaseAfter },
			Dealt = r.Dealt,
		})
	end
	if #hits > 0 then
		count(b, "Hits")
	end
	if STUDIO then
		local first = nil
		for _, e in trace.Events do
			if e.Kind == "Enter" and e.Part then
				first = e.Part.Name
				break
			end
		end
		table.insert(b.ShotLog, {
			t = now,
			Eye = eye,
			Dir = dir,
			Aim = b.Aim,
			Desired = b.Desired,
			ErrorDeg = if b.Desired then math.deg(angleBetween(dir, b.Desired)) else nil,
			AimErrorDeg = if b.Desired then math.deg(angleBetween(b.Aim, b.Desired)) else nil,
			ConeDeg = cone,
			Target = b.Target and b.Target.Name,
			FirstSurface = first,
			Hits = hits,
			Rounds = BotWeapon.rounds(b.Weapon),
			State = b.State,
		})
		while #b.ShotLog > 300 do
			table.remove(b.ShotLog, 1)
		end
	end
end

local function update(b: Bot, now: number, dt: number)
	local m = b.Model
	local w = b.Weapon

	-- 1. can it fight? Only the accepted BodyState says (no AI health / death of its own)
	local phase = m:GetAttribute("BodyPhase") or "ALIVE"
	local stance = m:GetAttribute("BodyStance") or "STANDING"
	if phase == "DEAD" or b.Humanoid.Health <= 0 then
		enterDown(b, now)
		setState(b, "DEAD", now, "BodyPhase " .. tostring(phase))
	elseif phase == "DYING" or stance ~= "STANDING" then
		enterDown(b, now)
		setState(b, "DOWN", now, `BodyPhase {phase}, BodyStance {stance}`)
	end
	if b.DownAt then
		-- the gun is let go a moment after the body goes down [measured 0.2-0.5 s], then stays where it fell
		if b.Rifle and not b.DroppedAt and now >= b.DownAt + Config.Rifle.DropAfterSeconds then
			BotRifle.drop(b.Rifle)
			b.DroppedAt = now
			event(b, now, "rifle", "let go")
		end
		return
	end

	if not b.Enabled then
		if b.State ~= "IDLE" then
			clearTarget(b)
			setState(b, "IDLE", now, "disabled")
		end
		return
	end
	if b.State == "IDLE" then
		setState(b, "SEARCH", now, "enabled")
	end

	-- 2. the held (or lost) target: still valid? still seen? (line of sight every LosSeconds)
	local target = b.Target
	if target then
		if not Perception.alive(target) or not Perception.enemy(m, target) then
			event(b, now, "target", `{target.Name} no longer valid`)
			count(b, "Eliminated")
			clearTarget(b)
			setState(b, if w.Reload then "RELOAD" else "SEARCH", now, `{target.Name} down / invalid`)
		elseif now >= b.NextLosAt then
			b.NextLosAt = now + P.LosSeconds
			local t0 = os.clock()
			local point, part, why = Perception.look(b.Head.Position, facingOf(b.Yaw), target, ignoreOf(b), false)
			Stats.LosChecks += 1
			Stats.LosSeconds += os.clock() - t0
			if point and part then
				b.TargetPoint, b.TargetPart = point, part
				b.SeenAt = now
				b.Visible = true
				if b.State == "LOST_TARGET" then
					b.ReadyAt = now + R.ReacquireSeconds
					b.OnTargetSince = nil
					count(b, "Reacquired")
					event(b, now, "target", `{target.Name} seen again (next shot allowed in {R.ReacquireSeconds} s)`)
					setState(b, "ACQUIRE", now, "reacquired " .. target.Name)
				end
			else
				b.Visible = false
				b.LastWhy = why
				if b.State ~= "LOST_TARGET" and now - b.SeenAt >= P.LostAfterSeconds then
					b.LostAt = now
					count(b, "Lost")
					event(b, now, "target", `{target.Name} lost ({why})`)
					setState(b, "LOST_TARGET", now, `{target.Name} {why}`)
				end
			end
		end
		if b.Target and b.State == "LOST_TARGET" and now - b.LostAt >= P.ForgetSeconds then
			event(b, now, "target", `{b.Target.Name} forgotten`)
			clearTarget(b)
			setState(b, "SEARCH", now, "lost target forgotten")
		end
	end

	-- 3. look for a target (every ScanSeconds, staggered across bots) while it has none or has lost its own
	local searching = b.State == "SEARCH" or b.State == "LOST_TARGET" or (b.State == "RELOAD" and not b.Target)
	if searching and now >= b.NextScanAt then
		b.NextScanAt = if now - b.NextScanAt < P.ScanSeconds then b.NextScanAt + P.ScanSeconds else now + P.ScanSeconds
		local t0 = os.clock()
		local found, point, part = scan(b)
		Stats.Scans += 1
		Stats.ScanSeconds += os.clock() - t0
		if found and point and part and found ~= b.Target then
			setTarget(b, found, point, part, now, R.FirstShotSeconds, "acquired")
		end
	end

	-- 4. aim (a 3D direction, server-owned) converges on the target; the body (yaw only) turns after the aim
	if b.Target then
		local tp = b.TargetPart
		local point = if b.Visible and tp and tp.Parent then tp.Position else b.TargetPoint
		if point then
			local desired = (point - b.Head.Position).Unit
			b.Desired = desired
			b.Aim = rotateToward(b.Aim, desired, math.rad(A.AimDegPerSecond) * dt)
			local delta = wrap(yawOf(b.Aim) - b.Yaw)
			local maxTurn = math.rad(A.TurnDegPerSecond) * dt
			b.Yaw = wrap(b.Yaw + math.clamp(delta, -maxTurn, maxTurn))
			if math.abs(wrap(b.Yaw - b.WrittenYaw)) > A.FacingEpsilonRad then
				m:SetAttribute(Config.FacingAttribute, b.Yaw)
				b.WrittenYaw = b.Yaw
			end
		end
	end

	-- 5. weapon: reload when empty (the M4's Regular timings), advance a reload in progress
	if not BotWeapon.loaded(w) and not w.Reload then
		local spec, why = BotWeapon.startReload(w, now)
		if spec then
			count(b, "Reloads")
			event(b, now, "reload", spec)
			publishAmmo(b)
			setState(b, "RELOAD", now, spec)
		elseif b.Counts["NoAmmo"] == nil then
			count(b, "NoAmmo")
			event(b, now, "reload", "refused: " .. tostring(why))
		end
	end
	if w.Reload then
		local spec = w.Reload.Spec
		if BotWeapon.step(w, now) then
			event(b, now, "reload", spec .. " done")
			publishAmmo(b)
			if b.State == "RELOAD" then
				setState(b, if b.Target and b.Visible then "AIM" elseif b.Target then "LOST_TARGET" else "SEARCH", now, "reload done")
				if b.State == "LOST_TARGET" then
					b.LostAt = now
				end
			end
		end
	end

	-- 6. decide
	local aimErr = if b.Desired then angleBetween(b.Aim, b.Desired) else math.huge
	local yawErr = math.abs(wrap(b.Yaw - yawOf(b.Aim)))
	local onTarget = aimErr <= math.rad(A.FireToleranceDeg) and yawErr <= math.rad(A.BodyToleranceDeg)
	if b.State == "ACQUIRE" then
		if now >= b.ReadyAt then
			setState(b, "AIM", now, "reaction delay over")
		end
	elseif b.State == "AIM" then
		if onTarget and b.Visible then
			b.OnTargetSince = b.OnTargetSince or now
			if now - (b.OnTargetSince :: number) >= A.SettleSeconds and now >= b.ReadyAt then
				b.BurstLeft = b.FireRng:NextInteger(F.BurstMin, F.BurstMax)
				b.PauseUntil = 0
				setState(b, "FIRE", now, "on target")
			end
		else
			b.OnTargetSince = nil
		end
	elseif b.State == "FIRE" then
		if aimErr > math.rad(A.ReaimDeg) then
			b.OnTargetSince = nil
			setState(b, "AIM", now, "target moved off the aim")
		elseif now >= b.PauseUntil and b.Visible and onTarget and BotWeapon.ready(w, now) then
			local reacting = F.HoldWhileReacting and m:GetAttribute("BodyReacting") == true
			local unstable = F.HoldWhileUnstable and m:GetAttribute("BodyUnstable") == true
			if b.HoldFire or reacting or unstable then
				b.Held += 1
			else
				shoot(b, now)
				b.BurstLeft -= 1
				if b.BurstLeft <= 0 then
					b.PauseUntil = now + b.FireRng:NextNumber(F.PauseMinSeconds, F.PauseMaxSeconds)
					b.BurstLeft = b.FireRng:NextInteger(F.BurstMin, F.BurstMax)
				end
			end
		end
	end
end

local function bind(inst: Instance)
	if not inst:IsA("Model") or bots[inst :: Model] then
		return
	end
	local model = inst :: Model
	if model:GetAttribute(Config.TeamAttribute) ~= nil then
		Perception.register(model)
	end
	if model:GetAttribute(Config.BotAttribute) ~= true then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local head = model:FindFirstChild("Head")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not head or not head:IsA("BasePart") or not root or not root:IsA("BasePart") then
		warn(`[AI] {model.Name}: not a bot rig (Humanoid, Head, HumanoidRootPart needed)`)
		return
	end
	bound += 1
	local seed = model:GetAttribute("AISeed")
	local s = if type(seed) == "number" then seed else bound
	local now = os.clock()
	local yaw = yawOf(root.CFrame.LookVector)
	local b: Bot = {
		Model = model,
		Humanoid = humanoid,
		Head = head,
		Root = root,
		Rifle = BotRifle.arm(model),
		Weapon = BotWeapon.new(nil),
		Seed = s,
		AimRng = Random.new(s),
		FireRng = Random.new(s + 7919),
		Enabled = model:GetAttribute("AIEnabled") ~= false,
		HoldFire = false,
		State = "IDLE",
		StateAt = now,
		Target = nil,
		TargetPart = nil,
		TargetPoint = nil,
		Visible = false,
		SeenAt = 0,
		LostAt = 0,
		LastWhy = nil,
		ReadyAt = 0,
		AcquiredAt = 0,
		Aim = facingOf(yaw),
		Desired = nil,
		Yaw = yaw,
		WrittenYaw = yaw,
		OnTargetSince = nil,
		-- staggered: bots bound one after another look at different moments
		NextScanAt = now + ((bound - 1) * 0.037) % P.ScanSeconds,
		NextLosAt = now + ((bound - 1) * 0.023) % P.LosSeconds,
		BurstLeft = 0,
		PauseUntil = 0,
		DownAt = nil,
		DroppedAt = nil,
		FirstShotAt = nil,
		Held = 0,
		Errors = 0,
		Events = {},
		ShotLog = {},
		Counts = {},
	}
	bots[model] = b
	model:SetAttribute(Config.FacingAttribute, yaw)
	model:SetAttribute("AIState", "IDLE")
	publishAmmo(b)
	event(b, now, "state", "bound")
	log(`{model.Name} bound (team {Perception.teamOf(model)}, seed {s}, {b.Weapon.Id})`)
end

local function unbind(model: Model)
	local b = bots[model]
	if b then
		bots[model] = nil
		Perception.unregister(model)
		if b.Rifle and b.Rifle.Parent and not model.Parent then
			b.Rifle:Destroy()
		end
	end
end

workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(bind, d)
	end
end)
for _, d in workspace:GetDescendants() do
	if d:IsA("Model") then
		bind(d)
	end
end

RunService.Heartbeat:Connect(function(dt)
	local t0 = os.clock()
	for model, b in bots do
		if not model.Parent then
			unbind(model)
			continue
		end
		local ok, err = pcall(update, b, t0, dt)
		if not ok then
			b.Errors += 1
			if b.Errors <= 3 then
				warn(`[AI] {model.Name} update failed: {err}`)
			end
		end
	end
	local spent = os.clock() - t0
	Stats.Frames += 1
	Stats.LoopSeconds += spent
	Stats.MaxLoopSeconds = math.max(Stats.MaxLoopSeconds, spent)
end)

-- Studio-only test hook (server BindableFunction; clients can't reach it).
if STUDIO then
	local function find(name: any): Bot?
		for m, b in bots do
			if m.Name == name or m == name then
				return b
			end
		end
		return nil
	end
	local function status(b: Bot): any
		local w = b.Weapon
		return {
			Name = b.Model.Name,
			State = b.State,
			StateAt = b.StateAt,
			Enabled = b.Enabled,
			HoldFire = b.HoldFire,
			Target = b.Target and b.Target.Name,
			TargetPart = b.TargetPart and b.TargetPart.Name,
			Visible = b.Visible,
			SeenAt = b.SeenAt,
			LastWhy = b.LastWhy,
			ReadyAt = b.ReadyAt,
			AcquiredAt = b.AcquiredAt,
			FirstShotAt = b.FirstShotAt,
			Yaw = b.Yaw,
			Aim = b.Aim,
			Desired = b.Desired,
			AimErrorDeg = if b.Desired then math.deg(angleBetween(b.Aim, b.Desired)) else nil,
			Mag = w.Ammo.Mag,
			Chambered = w.Ammo.Chambered,
			Reserve = table.clone(w.Ammo.Reserve),
			Dropped = table.clone(w.Ammo.Dropped),
			Reload = if w.Reload then { Spec = w.Reload.Spec, StartedAt = w.Reload.StartedAt, EndsAt = w.Reload.EndsAt, Swapped = w.Reload.Swapped } else nil,
			WeaponShots = w.Shots,
			WeaponReloads = w.Reloads,
			Held = b.Held,
			Counts = table.clone(b.Counts),
			DownAt = b.DownAt,
			DroppedAt = b.DroppedAt,
			Rifle = b.Rifle,
			RifleHeld = if b.Rifle then BotRifle.held(b.Rifle) else nil,
			Errors = b.Errors,
			Seed = b.Seed,
			Now = os.clock(),
		}
	end
	local bf = Instance.new("BindableFunction")
	bf.Name = "AIDebug"
	bf.OnInvoke = function(cmd: string, a: any, c: any): any
		if cmd == "list" then
			local out = {}
			for m, b in bots do
				table.insert(out, { Name = m.Name, State = b.State, Target = b.Target and b.Target.Name })
			end
			return out
		elseif cmd == "spawn" then
			-- a = { Name, Position, Yaw (deg, 0 = facing -Z), Team, Seed, Enabled, Parent }
			local opts = a or {}
			local folder = ServerStorage:FindFirstChild("AITemplates")
			local template = folder and folder:FindFirstChild(opts.Template or "AIBOT")
			if not template then
				return { Error = "no template" }
			end
			local m = template:Clone() :: Model
			m.Name = opts.Name or "BOT"
			m:SetAttribute(Config.TeamAttribute, opts.Team or "Red")
			if opts.Seed then
				m:SetAttribute("AISeed", opts.Seed)
			end
			if opts.Enabled == false then
				m:SetAttribute("AIEnabled", false)
			end
			local pos = opts.Position or Vector3.new(-740, 3, 150)
			m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(opts.Yaw or 0), 0))
			m.Parent = opts.Parent or workspace:FindFirstChild("AITest") or workspace
			bind(m)
			return m
		elseif cmd == "remove" then
			local b = find(a)
			if b then
				local m = b.Model
				if b.Rifle then
					b.Rifle:Destroy()
				end
				unbind(m)
				m:Destroy()
				return true
			end
			return false
		elseif cmd == "register" then
			if typeof(a) == "Instance" and a:IsA("Model") then
				Perception.register(a)
				return true
			end
			return false
		elseif cmd == "perf" then
			local n = 0
			for _ in bots do
				n += 1
			end
			return {
				Bots = n,
				Frames = Stats.Frames,
				LoopSeconds = Stats.LoopSeconds,
				MaxLoopSeconds = Stats.MaxLoopSeconds,
				Scans = Stats.Scans,
				ScanSeconds = Stats.ScanSeconds,
				LosChecks = Stats.LosChecks,
				LosSeconds = Stats.LosSeconds,
				Rays = Perception.Stats.Rays,
				Looks = Perception.Stats.Looks,
				Shots = BotWeapon.Stats.Shots,
				ShotSeconds = BotWeapon.Stats.ShotSeconds,
				MaxShotSeconds = BotWeapon.Stats.MaxShotSeconds,
				Now = os.clock(),
			}
		elseif cmd == "resetperf" then
			for k in Stats do
				Stats[k] = 0
			end
			Perception.Stats.Rays, Perception.Stats.Looks = 0, 0
			BotWeapon.Stats.Shots, BotWeapon.Stats.ShotSeconds, BotWeapon.Stats.MaxShotSeconds = 0, 0, 0
			return true
		end
		local b = find(a)
		if not b then
			return { Error = "no bot " .. tostring(a) }
		end
		if cmd == "status" then
			return status(b)
		elseif cmd == "events" then
			return table.clone(b.Events)
		elseif cmd == "shots" then
			return table.clone(b.ShotLog)
		elseif cmd == "set" then
			-- c = { Enabled, HoldFire }
			if type(c) == "table" then
				if c.Enabled ~= nil then
					b.Enabled = c.Enabled == true
				end
				if c.HoldFire ~= nil then
					b.HoldFire = c.HoldFire == true
				end
			end
			return status(b)
		elseif cmd == "refill" then
			BotWeapon.refill(b.Weapon)
			publishAmmo(b)
			return status(b)
		elseif cmd == "setammo" then
			-- c = { Mag, Chambered, Reserve }
			if type(c) == "table" then
				b.Weapon.Reload = nil
				b.Weapon.Ammo = {
					Mag = c.Mag or 0,
					Chambered = c.Chambered == true,
					Reserve = c.Reserve or {},
					Dropped = {},
					LabelMarks = 0,
				}
				publishAmmo(b)
			end
			return status(b)
		elseif cmd == "clearlogs" then
			b.Events = {}
			b.ShotLog = {}
			b.Counts = {}
			b.Held = 0
			b.FirstShotAt = nil
			return true
		elseif cmd == "look" then
			-- one perception check now (fov true / false), for the perception tests
			if typeof(c) == "Instance" and c:IsA("Model") then
				local point, part, why = Perception.look(b.Head.Position, facingOf(b.Yaw), c, ignoreOf(b), true)
				local point2, _, why2 = Perception.look(b.Head.Position, facingOf(b.Yaw), c, ignoreOf(b), false)
				return {
					Fov = { Point = point, Part = part and part.Name, Why = why },
					NoFov = { Point = point2, Why = why2 },
					Enemy = Perception.enemy(b.Model, c),
					Alive = Perception.alive(c),
				}
			end
			return { Error = "no model" }
		end
		return { Error = "unknown command" }
	end
	bf.Parent = script
end
