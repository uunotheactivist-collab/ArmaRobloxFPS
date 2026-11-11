--!strict
-- Body state (server only; the server owns every value here). Foundation for the reference game's body model as
-- its BALANCE / RAGDOLL debug panels show it (ReferenceAnalysis/BodyState/BodyState_Analysis.md). Rules and numbers
-- are in Shared.Config.BodyState, each tagged confirmed / measured / inferred / placeholder.
--
-- Flow: Server.WeaponServer → Server.Ballistics.trace (target part + point) → BodyState.applyHit → BodyHit.locate
--       (location label, throat zone, wound) → this state machine.
--
-- State per body (model with the attribute BodyModel = true):
--   Phase:     ALIVE → INJURED → DYING → DEAD. It never goes backwards.
--   Stance:    STANDING → FALLING → DOWN.
--   Wound:     the most severe wound so far (Brain > Throat > Lung > Gut > Limb).
--   Behaviour: the dying behaviour shown once down (LIMP, CHOKE, CRYING, SHOCK, …; AGONAL from CRYING at low life).
--   Strength, Legs (0–100) while standing; Life (0–100) drains only while down and dying.
--   Reacting:  the transient flinch flag after a hit while standing (none while dying).
--   Unstable:  legs at 0 — the body goes down after a short delay.
-- Hits on a DYING body: what they do is UNKNOWN in the footage. TEMPORARY implementation choice: recorded only, no
-- state change. This is not a gameplay rule.
-- DEAD at life ≤ 0 is an IMPLEMENTATION RULE, not directly proven by the footage. A DEAD body ignores hits.
-- Gut CRYING and Limb SHOCK once down are PLACEHOLDER / INCOMPLETE (temporary test behaviour); see Config.RuleStatus.
-- Everything is published as model attributes (Body*) and mirrored to the Humanoid's health (life; 0 when DEAD).
-- Clients only display what replicates.
--
-- Bodies: designed for R6 and R15 bots AND R15 player characters through this same server-authoritative system
-- (BodyHit already maps R15 part names). Only models with BodyModel use it today (the R6 test bots).
-- Player integration is NOT built yet. It needs:
--   - the server marking characters;
--   - a death hand-off with the spawner;
--   - no debug view.
--
-- Test bots (attribute BodyDebugView) also get a temporary debug presentation: a tag above the head and a simple
-- pose (flinch tilt, unstable lean, fall, lying). It is NOT the ragdoll; that is a later milestone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("BodyState"))
local BodyHit = require(script.Parent:WaitForChild("BodyHit"))

local BodyState = {}

export type Body = {
	Model: Model,
	Humanoid: Humanoid,
	Phase: string,
	Stance: string,
	Wound: string?,
	Behaviour: string?,
	Strength: number,
	Legs: number,
	Life: number,
	Hits: number,
	LastLocation: string?,
	LastZone: string?,
	ReactUntil: number,
	UnstableSince: number?,
	FallStart: number?,
	FallAt: number?,
	DownAt: number?,
	Rest: CFrame,
	LastPublished: number,
	PoseKey: string,
}

local bodies: { [Model]: Body } = {}
BodyState.Recent = {} :: { any }

-- Debug-pose geometry of the R6 test bots (hip-root 3 studs above the feet, torso 1 deep).
local DEBUG_ROOT_HEIGHT = 3
local DEBUG_HALF_DEPTH = 0.5

local function clock(): number
	return os.clock()
end

local function round(x: number): number
	return math.floor(x + 0.5)
end

function BodyState.modelOf(humanoid: Humanoid): Model?
	local m = humanoid.Parent
	return if m and m:IsA("Model") then m else nil
end

function BodyState.isBody(humanoid: Humanoid): boolean
	local m = BodyState.modelOf(humanoid)
	return m ~= nil and m:GetAttribute(Config.Attribute) == true
end

local function fresh(model: Model, humanoid: Humanoid, rest: CFrame): Body
	return {
		Model = model,
		Humanoid = humanoid,
		Phase = "ALIVE",
		Stance = "STANDING",
		Wound = nil,
		Behaviour = nil,
		Strength = 100,
		Legs = 100,
		Life = 100,
		Hits = 0,
		LastLocation = nil,
		LastZone = nil,
		ReactUntil = 0,
		UnstableSince = nil,
		FallStart = nil,
		FallAt = nil,
		DownAt = nil,
		Rest = rest,
		LastPublished = 0,
		PoseKey = "",
	}
end

-- Status of the current dying behaviour (Config.DownBehaviourStatus). AGONAL comes from the INFERRED CRYING change.
local function behaviourStatus(b: Body): string?
	if not b.Behaviour then
		return nil
	end
	if b.Wound and b.Behaviour == Config.DownBehaviour[b.Wound] then
		return Config.DownBehaviourStatus[b.Wound]
	end
	if b.Behaviour == "AGONAL" then
		return "INFERRED"
	end
	return nil
end

local function snapshot(b: Body): any
	local t = clock()
	return {
		Phase = b.Phase,
		Stance = b.Stance,
		Wound = b.Wound,
		Behaviour = b.Behaviour,
		BehaviourStatus = behaviourStatus(b),
		Strength = round(b.Strength),
		Legs = round(b.Legs),
		Life = math.floor(b.Life * 10 + 0.5) / 10,
		Hits = b.Hits,
		LastLocation = b.LastLocation,
		LastZone = b.LastZone,
		Reacting = t < b.ReactUntil,
		Unstable = b.UnstableSince ~= nil,
		Health = b.Humanoid.Health,
	}
end

-- Temporary debug tag for test bots (the reference's world-tag style: "NAME STATE str NN%" / "NAME STATE life NN%").
local function tagFor(b: Body): (TextLabel?, TextLabel?)
	local model = b.Model
	if model:GetAttribute(Config.DebugViewAttribute) ~= true then
		return nil, nil
	end
	local gui = model:FindFirstChild("BodyStateTag") :: BillboardGui?
	if not gui then
		local g = Instance.new("BillboardGui")
		g.Name = "BodyStateTag"
		g.Adornee = model:FindFirstChild("Head") :: BasePart?
		g.Size = UDim2.fromOffset(300, 38)
		g.StudsOffset = Vector3.new(0, 2.4, 0)
		g.AlwaysOnTop = true
		g.MaxDistance = 150
		g.LightInfluence = 0
		for i, name in { "Line1", "Line2" } do
			local l = Instance.new("TextLabel")
			l.Name = name
			l.BackgroundTransparency = 1
			l.Size = UDim2.new(1, 0, 0.5, 0)
			l.Position = UDim2.fromScale(0, (i - 1) * 0.5)
			l.Font = Enum.Font.Code
			l.TextSize = if i == 1 then 15 else 12
			l.TextStrokeTransparency = 0.4
			l.TextColor3 = Color3.new(1, 1, 1)
			l.Parent = g
		end
		g.Parent = model
		gui = g
	end
	local g = gui :: BillboardGui
	return g:FindFirstChild("Line1") :: TextLabel?, g:FindFirstChild("Line2") :: TextLabel?
end

local function publish(b: Body)
	local m = b.Model
	local s = snapshot(b)
	m:SetAttribute("BodyPhase", s.Phase)
	m:SetAttribute("BodyStance", s.Stance)
	m:SetAttribute("BodyWound", s.Wound)
	m:SetAttribute("BodyBehaviour", s.Behaviour)
	m:SetAttribute("BodyStrength", s.Strength)
	m:SetAttribute("BodyLegs", s.Legs)
	m:SetAttribute("BodyLife", s.Life)
	m:SetAttribute("BodyHits", s.Hits)
	m:SetAttribute("BodyLastHit", if b.LastLocation then b.LastLocation .. (if b.LastZone then "/" .. b.LastZone else "") else nil)
	m:SetAttribute("BodyReacting", s.Reacting)
	m:SetAttribute("BodyUnstable", s.Unstable)
	-- The Humanoid mirrors life so other systems (WeaponServer skips dead targets) agree with the body state.
	local health = if b.Phase == "DEAD" then 0 else math.max(b.Life, 0.1)
	if math.abs(b.Humanoid.Health - health) > 0.05 then
		b.Humanoid.Health = health
	end
	b.LastPublished = clock()

	local l1, l2 = tagFor(b)
	if l1 and l2 then
		local name = m.Name
		if b.Phase == "DEAD" then
			l1.Text = `{name}  DEAD`
			l1.TextColor3 = Color3.fromRGB(255, 80, 80)
		elseif b.Stance == "DOWN" then
			l1.Text = `{name}  {b.Behaviour or "?"}  life {round(b.Life)}%`
			l1.TextColor3 = Color3.fromRGB(255, 170, 60)
		else
			local state = if b.Phase == "DYING" then "DYING" elseif b.UnstableSince then "UNSTABLE" else b.Phase
			l1.Text = `{name}  {state}  str {s.Strength}%  legs {s.Legs}%` .. (if s.Reacting then "  flinch" else "")
			l1.TextColor3 = if b.Phase == "DYING" then Color3.fromRGB(255, 170, 60) else Color3.new(1, 1, 1)
		end
		local status = s.BehaviourStatus
		l2.Text = `{b.Wound or "no"} wound · hit {m:GetAttribute("BodyLastHit") or "-"} · hits {b.Hits}`
			.. (if status and string.find(status, "PLACEHOLDER") then " · behaviour PLACEHOLDER" else "")
	end
end

-- Temporary debug pose (test bots only): rotate the anchored model about its feet. NOT ragdoll.
local function pose(b: Body, t: number)
	-- Bodies with a real presentation (attribute BodyPresentation, Server.BodyPresentation) are posed there instead.
	-- This guard is the only change for the hit-reaction slice.
	if b.Model:GetAttribute(Config.DebugViewAttribute) ~= true or b.Model:GetAttribute("BodyPresentation") ~= nil then
		return
	end
	local back, side = 0, 0
	if b.Stance == "DOWN" then
		back = 90
	elseif b.Stance == "FALLING" and b.FallStart and b.FallAt then
		local a = math.clamp((t - b.FallStart) / math.max(b.FallAt - b.FallStart, 1e-3), 0, 1)
		back = 90 * a * a
	elseif b.UnstableSince then
		side = 12
	elseif t < b.ReactUntil then
		back = 7
	end
	local key = `{back}:{side}`
	if key == b.PoseKey then
		return
	end
	b.PoseKey = key
	local target: CFrame
	if side ~= 0 then
		local hinge = b.Rest * CFrame.new(0, -DEBUG_ROOT_HEIGHT, 0)
		target = hinge * CFrame.Angles(0, 0, math.rad(side)) * CFrame.new(0, DEBUG_ROOT_HEIGHT, 0)
	else
		local hinge = b.Rest * CFrame.new(0, -DEBUG_ROOT_HEIGHT, DEBUG_HALF_DEPTH)
		target = hinge * CFrame.Angles(math.rad(back), 0, 0) * CFrame.new(0, DEBUG_ROOT_HEIGHT, -DEBUG_HALF_DEPTH)
	end
	b.Model:PivotTo(target)
end

local function bodyFor(model: Model, humanoid: Humanoid): Body
	local b = bodies[model]
	if not b then
		b = fresh(model, humanoid, model:GetPivot())
		bodies[model] = b
	end
	return b
end

local function startFall(b: Body, t: number)
	b.Phase = "DYING"
	b.Stance = "FALLING"
	b.FallStart = t
	b.FallAt = t + (Config.FallSeconds[b.Wound or "Limb"] or 0.5)
	b.ReactUntil = 0 -- no flinch while dying [confirmed: "flinch … = 0.00 m/s"]
	b.UnstableSince = nil
end

-- Advance one body by dt (s). Returns true when something structural changed (publish now).
local function step(b: Body, t: number, dt: number): boolean
	if b.Phase == "DEAD" then
		return false
	end
	if b.Stance == "STANDING" then
		if b.Phase == "INJURED" and b.Strength < 100 then
			b.Strength = math.min(100, b.Strength + Config.StrengthRecoveryPerSecond * dt)
		end
		if b.UnstableSince and t - b.UnstableSince >= Config.LegsGoneFallAfter then
			startFall(b, t)
			return true
		end
		return false
	elseif b.Stance == "FALLING" then
		if b.FallAt and t >= b.FallAt then
			b.Stance = "DOWN"
			b.DownAt = t
			b.Behaviour = b.Behaviour or Config.DownBehaviour[b.Wound or "Limb"]
			return true
		end
		return false
	elseif b.Phase == "DYING" then -- down
		local drain = Config.LifeDrainPerSecond[b.Behaviour or ""] or 0
		if drain <= 0 then
			return false
		end
		b.Life = math.max(0, b.Life - drain * dt)
		local change = Config.BehaviourChange[b.Behaviour or ""]
		if change and b.Life < change.BelowLife then
			b.Behaviour = change.To
		end
		if b.Life <= 0 then
			b.Phase = "DEAD" -- IMPLEMENTATION RULE (not directly proven by the footage): life ≤ 0 → DEAD
			return true
		end
	end
	return false
end

local function record(entry: any)
	if not RunService:IsStudio() then
		return
	end
	table.insert(BodyState.Recent, entry)
	while #BodyState.Recent > Config.RecentResults do
		table.remove(BodyState.Recent, 1)
	end
end

-- The single entry point for a bullet reaching a body (called by Server.WeaponServer with the server trace's part and
-- point). Returns the recorded result.
function BodyState.applyHit(humanoid: Humanoid, part: BasePart, position: Vector3, weapon: string?): any
	local model = BodyState.modelOf(humanoid)
	if not model then
		return nil
	end
	local b = bodyFor(model, humanoid)
	local t = clock()
	local result: any = { Body = model.Name, Part = part.Name, Weapon = weapon, PhaseBefore = b.Phase }
	local hit = BodyHit.locate(part, position)
	if not hit then
		result.Ignored = "not anatomy"
	elseif b.Phase == "DEAD" then
		result.Ignored = "dead"
	else
		result.Location, result.Zone, result.Wound, result.LocalY = hit.Location, hit.Zone, hit.Wound, hit.LocalY
		b.Hits += 1
		b.LastLocation, b.LastZone = hit.Location, hit.Zone
		if b.Phase == "DYING" then
			-- UNKNOWN in the footage. TEMPORARY implementation choice: record the hit, change nothing (not a rule).
			result.Ignored = "dying: recorded only"
		else
			b.Phase = "INJURED"
			local w = hit.Wound
			if not b.Wound or Config.Severity[w] > Config.Severity[b.Wound :: string] then
				b.Wound = w
			end
			b.Strength = math.max(0, b.Strength - (Config.StrengthLoss[hit.Location] or 0))
			local legsLoss = Config.LegsLoss[hit.Location]
			if legsLoss then
				b.Legs = math.max(0, b.Legs - legsLoss)
			end
			if Config.ImmediateDying[w] then
				if w == "Brain" then
					b.Strength = 0
					b.Behaviour = "LIMP" -- the LIMP tag appears at the hit, before the body is down [confirmed]
				end
				startFall(b, t)
			else
				b.ReactUntil = t + Config.ReactSeconds
				if b.Strength <= Config.CollapseAtStrength then
					startFall(b, t)
				elseif b.Legs <= 0 and not b.UnstableSince then
					b.UnstableSince = t
				end
			end
		end
	end
	publish(b)
	pose(b, t)
	result.PhaseAfter = b.Phase
	result.State = snapshot(b)
	result.At = t
	record(result)
	return result
end

function BodyState.get(model: Model): any
	local b = bodies[model]
	return if b then snapshot(b) else nil
end

-- Heartbeat: falls, drain, recovery, presentation. Attributes are refreshed at most 10 times a second unless
-- something structural changed.
if RunService:IsServer() and RunService:IsRunning() then
	RunService.Heartbeat:Connect(function(dt)
		local t = clock()
		for model, b in bodies do
			if not model.Parent then
				bodies[model] = nil
				continue
			end
			local changed = step(b, t, dt)
			if b.ReactUntil > 0 and t >= b.ReactUntil then
				b.ReactUntil = 0
				changed = true
			end
			if changed or (b.Phase ~= "DEAD" and t - b.LastPublished >= 0.1) then
				publish(b)
			end
			pose(b, t)
		end
	end)
end

-- Studio-only test hook (server-side BindableFunction; clients can't reach it). Test code runs in another script
-- context with its own module copy, so it talks to this running copy here:
--   Invoke("hit", model, partName, localPoint)  a hit exactly as the ballistic trace would deliver it
--   Invoke("reset", model) / Invoke("get", model) / Invoke("advance", model, seconds) / Invoke("recent") / Invoke("clear")
if RunService:IsStudio() and RunService:IsServer() and RunService:IsRunning() and not script:FindFirstChild("BodyStateDebug") then
	local bf = Instance.new("BindableFunction")
	bf.Name = "BodyStateDebug"
	bf.OnInvoke = function(cmd: string, model: Model?, a: any, c: any): any
		if cmd == "recent" then
			return BodyState.Recent
		elseif cmd == "clear" then
			table.clear(BodyState.Recent)
			return 0
		end
		if typeof(model) ~= "Instance" or not (model :: Instance):IsA("Model") then
			return { Error = "no model" }
		end
		local m = model :: Model
		local humanoid = m:FindFirstChildOfClass("Humanoid")
		if not humanoid or m:GetAttribute(Config.Attribute) ~= true then
			return { Error = "not a body" }
		end
		if cmd == "hit" then
			local part = m:FindFirstChild(a) :: BasePart?
			if not part then
				return { Error = "no part " .. tostring(a) }
			end
			return BodyState.applyHit(humanoid, part, part.CFrame:PointToWorldSpace(c or Vector3.zero), "Debug")
		elseif cmd == "reset" then
			local old = bodies[m]
			local rest = if old then old.Rest else m:GetPivot()
			m:PivotTo(rest)
			-- a Humanoid that has died stays dead (setting its health again doesn't revive it): give the test bot a
			-- fresh one
			if humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then
				local nh = Instance.new("Humanoid")
				nh.RequiresNeck = humanoid.RequiresNeck
				nh.BreakJointsOnDeath = humanoid.BreakJointsOnDeath
				nh.DisplayDistanceType = humanoid.DisplayDistanceType
				nh.HealthDisplayType = humanoid.HealthDisplayType
				nh.MaxHealth = humanoid.MaxHealth
				nh.Health = humanoid.MaxHealth
				humanoid:Destroy()
				nh.Parent = m
				humanoid = nh
			end
			local b = fresh(m, humanoid, rest)
			bodies[m] = b
			humanoid.Health = humanoid.MaxHealth
			publish(b)
			return snapshot(b)
		elseif cmd == "get" then
			return BodyState.get(m)
		elseif cmd == "advance" then
			local b = bodies[m]
			if not b then
				return nil
			end
			local seconds = tonumber(a) or 0
			local dt = 1 / 60
			local n = math.ceil(seconds / dt)
			for _ = 1, n do
				-- move every timestamp back by dt: the body experiences dt of elapsed time
				b.ReactUntil -= dt
				if b.UnstableSince then
					b.UnstableSince -= dt
				end
				if b.FallStart then
					b.FallStart -= dt
				end
				if b.FallAt then
					b.FallAt -= dt
				end
				if b.DownAt then
					b.DownAt -= dt
				end
				step(b, clock(), dt)
			end
			publish(b)
			pose(b, clock())
			return snapshot(b)
		end
		return { Error = "unknown command" }
	end
	bf.Parent = script
end

return BodyState
