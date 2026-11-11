--!strict
-- Grenade server (fragmentation grenade vertical slice). Basis: ReferenceAnalysis/Grenade/Grenade_Analysis.md.
-- Values: Shared.Config.Grenade (tagged).
--
-- Lifecycle, all on the server:
--   READY → THROWING (wind-up, 0.133 s) → released: the grenade body flies, bounces and rolls (Roblox physics,
--   server-owned) while the 4.0 s fuse runs on the server clock → DETONATED (once): 600 fragment traces, hits, damage,
--   blood, one effect message → CLEANUP (the body is removed at detonation; the throw ends at 0.40 s).
--
-- Trust model (as WeaponServer): a client sends only ("Throw", aim direction). It can't give a position, a velocity, a
-- fuse, a detonation, a fragment, a hit, a target, damage or a result: no remote accepts any of those. Anything a
-- client fires on GrenadeFx / GrenadeState is ignored (counted for the tests).
--
-- Integration (no second hit / state / ragdoll / blood system): fragment traces are Server.Ballistics.trace; a fragment
-- reaching a BodyState body becomes BodyState.applyHit(humanoid, part, point, "Grenade") (one per part reached); hit
-- reactions and ragdolls follow from BodyState as for bullets; blood is Server.Blood.Impacts.onBurst (one message).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Grenade"))
local BodyConfig = require(Shared.Config:WaitForChild("BodyState"))
local BodyState = require(script.Parent.Parent:WaitForChild("BodyState"))
local BodyHit = require(script.Parent.Parent:WaitForChild("BodyHit"))
local Impacts = require(script.Parent.Parent:WaitForChild("Blood"):WaitForChild("Impacts"))
local Throw = require(script.Parent:WaitForChild("Throw"))
local Fragments = require(script.Parent:WaitForChild("Fragments"))

local LOG = true

local Remotes = Shared:WaitForChild("Remotes")
local function remote(name: string): RemoteEvent
	local r = Remotes:FindFirstChild(name)
	if r and r:IsA("RemoteEvent") then
		return r
	end
	local n = Instance.new("RemoteEvent")
	n.Name = name
	n.Parent = Remotes
	return n
end
local Command = remote(Config.Remotes.Command)
local StateOut = remote(Config.Remotes.State)
local FxOut = remote(Config.Remotes.Fx)

type PlayerState = { Left: number, Throwing: number?, Accepted: number, Rejected: number }
type Grenade = {
	Id: number,
	Owner: Player,
	Body: BasePart,
	ReleasedAt: number,
	DetonateAt: number,
	Detonated: boolean,
	Origin: Vector3,
	Velocity: Vector3,
	HeadAt: Vector3,
	Path: { any },
	LastSample: number,
}

local states: { [Player]: PlayerState } = {}
local active: { [number]: Grenade } = {}
local nextId = 0
local loop: RBXScriptConnection? = nil
local counters = { Requests = 0, Throws = 0, Rejected = 0, Detonations = 0, Lost = 0, FxClientCalls = 0, StateClientCalls = 0 }
local recent: { any } = {} -- Studio only: detonations and rejections
local SAMPLE = 1 / 30

local function log(message: string)
	if LOG then
		print("[Grenade] " .. message)
	end
end

local function record(entry: any)
	if RunService:IsStudio() then
		entry.At = os.clock()
		table.insert(recent, entry)
		while #recent > 48 do
			table.remove(recent, 1)
		end
	end
end

local function stateFor(player: Player): PlayerState
	local s = states[player]
	if not s then
		s = { Left = Config.Count, Throwing = nil, Accepted = 0, Rejected = 0 }
		states[player] = s
	end
	return s
end

local function send(player: Player, msg: any)
	if player.Parent then
		StateOut:FireClient(player, msg)
	end
end

local function reject(player: Player, action: string, reason: string)
	counters.Rejected += 1
	stateFor(player).Rejected += 1
	log(`{player.Name} {action} rejected: {reason}`)
	record({ Kind = "Rejected", Player = player.Name, Action = action, Reason = reason })
	send(player, { Phase = "Refused", Reason = reason, Left = stateFor(player).Left })
end

local function alive(player: Player): (Model?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or not character:IsDescendantOf(workspace) then
		return nil, nil
	end
	return character, humanoid
end

local onStep: () -> ()
local function startLoop()
	if not loop then
		loop = RunService.Heartbeat:Connect(function()
			onStep()
		end)
	end
end
local function stopLoopIfIdle()
	if loop and next(active) == nil then
		loop:Disconnect()
		loop = nil
	end
end

-- All fragments arrive in the same frame [confirmed], so the order of one body's part hits carries no meaning. They are
-- applied most severe wound first (BodyHit's own wound, Config.BodyState.Severity), then by fragment count: the body
-- ends in the state of its worst wound, as BodyState keeps the most severe wound. [inferred]
local function ordered(hits: { Fragments.PartHit }): { Fragments.PartHit }
	local bodyOrder: { [Humanoid]: number } = {}
	local key: { [Fragments.PartHit]: { number } } = {}
	for i, h in hits do
		bodyOrder[h.Humanoid] = bodyOrder[h.Humanoid] or i
		local loc = BodyHit.locate(h.Part, h.Position)
		local sev = if loc and loc.Wound then BodyConfig.Severity[loc.Wound] or 0 else 0
		key[h] = { bodyOrder[h.Humanoid], -sev, -h.Count, i }
	end
	local list = table.clone(hits)
	table.sort(list, function(a, b)
		local ka, kb = key[a], key[b]
		for k = 1, 4 do
			if ka[k] ~= kb[k] then
				return ka[k] < kb[k]
			end
		end
		return false
	end)
	return list
end

-- Damage from the fragments: BodyState bodies through BodyState (one hit per part reached); other non-player humanoids
-- a placeholder amount per fragment; players none (UNKNOWN in the footage).
local function applyHits(g: Grenade, hits: { Fragments.PartHit }): ({ any }, { any }, { any }, { [Player]: number })
	local F = Config.Fragments
	local damageResults, report, bloodTraces = {}, {}, {}
	local otherCounts: { [Humanoid]: { Count: number, Part: string } } = {}
	local playersReached: { [Player]: number } = {} -- fragments that reached each player's character (red edge pulse)
	for _, h in ordered(hits) do
		local humanoid = h.Humanoid
		local model = humanoid.Parent
		local hitPlayer = if model then Players:GetPlayerFromCharacter(model) else nil
		local isPlayer = hitPlayer ~= nil
		local entry: any = { Body = model and model.Name, Part = h.Part.Name, Fragments = h.Count, Player = isPlayer,
			MomentumEach = F.MassKg * F.SpeedMps }
		if hitPlayer then
			playersReached[hitPlayer] = (playersReached[hitPlayer] or 0) + h.Count
			entry.Outcome = if F.DamagePlayers then "player" else "player: no grenade damage (UNKNOWN in footage)"
		elseif BodyState.isBody(humanoid) then
			local r = BodyState.applyHit(humanoid, h.Part, h.Position, "Grenade")
			entry.Outcome = "BodyState"
			if r then
				entry.Location, entry.Zone, entry.Wound = r.Location, r.Zone, r.Wound
				entry.PhaseBefore, entry.PhaseAfter, entry.Ignored = r.PhaseBefore, r.PhaseAfter, r.Ignored
				log(`grenade {g.Id} fragments ×{h.Count} → {r.Body}.{r.Location or r.Part}{if r.Zone then "/" .. r.Zone else ""}`
					.. ` → {r.Wound or "-"} wound, {r.PhaseBefore} → {r.PhaseAfter}{if r.Ignored then " (" .. r.Ignored .. ")" else ""}`)
			end
			table.insert(damageResults, { Humanoid = humanoid, Part = h.Part.Name, Dealt = 0, Health = humanoid.Health, Body = r, Fragments = h.Count })
		else
			local o = otherCounts[humanoid]
			if not o then
				o = { Count = 0, Part = h.Part.Name }
				otherCounts[humanoid] = o
			end
			o.Count += h.Count
			entry.Outcome = "placeholder damage"
		end
		if not isPlayer then
			for k, tr in h.Traces do
				if k > F.BloodPerPart or #bloodTraces >= F.MaxBloodFragments then
					break
				end
				table.insert(bloodTraces, tr)
			end
		end
		table.insert(report, entry)
	end
	for humanoid, o in otherCounts do
		if humanoid.Health > 0 then
			local before = humanoid.Health
			humanoid:TakeDamage(F.DamagePerFragment * o.Count)
			table.insert(damageResults, { Humanoid = humanoid, Part = o.Part, Dealt = before - humanoid.Health, Health = humanoid.Health, Fragments = o.Count })
			log(`grenade {g.Id} fragments ×{o.Count} → {humanoid.Parent and humanoid.Parent.Name} for {before - humanoid.Health}`)
		end
	end
	return damageResults, report, bloodTraces, playersReached
end

local function detonate(g: Grenade)
	if g.Detonated then
		return
	end
	g.Detonated = true
	active[g.Id] = nil
	local now = os.clock()
	local at = g.Body.Position
	g.Body:Destroy() -- the body is gone before the fragments are traced
	counters.Detonations += 1
	local origin = at + Vector3.new(0, Config.Fragments.OriginLift, 0)
	local frag = Fragments.trace(origin, g.Id * 7919 + 17, {})
	local damageResults, report, bloodTraces, playersReached = applyHits(g, frag.Hits)
	if #bloodTraces > 0 then
		local ok, err = pcall(Impacts.onBurst, g.Owner, "Grenade", bloodTraces, damageResults)
		if not ok then
			warn(`[Grenade] blood presentation failed: {err}`)
		end
	end
	FxOut:FireAllClients({ Id = g.Id, p = at, n = frag.Count })
	-- presentation only: each player whose character the fragments reached gets the red screen-edge pulse (the trigger
	-- is INFERRED; no damage is applied to players)
	local reachedNames = {}
	for p, n in playersReached do
		send(p, { Phase = "FragmentsHit", Id = g.Id, Count = n })
		reachedNames[p.Name] = n
	end
	log(`grenade {g.Id} detonated after {math.floor((now - g.ReleasedAt) * 1000 + 0.5) / 1000} s: GRENADE: {frag.Count} FRAGMENTS`
		.. ` / {frag.IntoBodies} INTO BODIES   {frag.IntoWalls} INTO WALLS   {frag.Clear} CLEAR ({math.floor(frag.Seconds * 10000 + 0.5) / 10} ms)`)
	record({
		Kind = "Detonation",
		Id = g.Id,
		Player = g.Owner.Name,
		ReleasedAt = g.ReleasedAt,
		DetonatedAt = now,
		Fuse = now - g.ReleasedAt,
		Position = at,
		Origin = g.Origin,
		Velocity = g.Velocity,
		HeadAt = g.HeadAt,
		Fragments = frag.Count,
		IntoBodies = frag.IntoBodies,
		IntoWalls = frag.IntoWalls,
		Clear = frag.Clear,
		WallStops = frag.WallStops,
		Octants = frag.Octants,
		Mean = frag.Mean,
		TraceMs = frag.Seconds * 1000,
		TotalMs = (os.clock() - now) * 1000,
		Hits = report,
		PlayersReached = reachedNames,
		BloodTraces = #bloodTraces,
		Path = g.Path,
	})
	stopLoopIfIdle()
end

onStep = function()
	local now = os.clock()
	for id, g in active do
		if not g.Body.Parent or g.Body.Position.Y < Config.Body.LostBelowY then
			active[id] = nil
			counters.Lost += 1
			if g.Body.Parent then
				g.Body:Destroy()
			end
			log(`grenade {id} lost (left the world) without detonating`)
			record({ Kind = "Lost", Id = id, Player = g.Owner.Name })
			continue
		end
		if now >= g.DetonateAt then
			detonate(g)
			continue
		end
		if RunService:IsStudio() and now - g.LastSample >= SAMPLE then
			g.LastSample = now
			local owner = nil
			pcall(function()
				owner = g.Body:GetNetworkOwner()
			end)
			table.insert(g.Path, { t = now - g.ReleasedAt, p = g.Body.Position, v = g.Body.AssemblyLinearVelocity, serverOwned = owner == nil })
		end
	end
	stopLoopIfIdle()
end

local function release(player: Player, s: PlayerState, token: number, dir: Vector3)
	if s.Throwing ~= token then
		return
	end
	local character = alive(player)
	if not character then
		s.Throwing = nil
		reject(player, "Throw", "died before the release")
		return
	end
	local origin, velocity = Throw.launch(character, dir)
	if not origin or not velocity then
		s.Throwing = nil
		reject(player, "Throw", "no head")
		return
	end
	nextId += 1
	local id = nextId
	local body = Throw.spawn(id, character, origin, velocity)
	s.Left -= 1
	local now = os.clock()
	local head = character:FindFirstChild("Head") :: BasePart
	active[id] = {
		Id = id,
		Owner = player,
		Body = body,
		ReleasedAt = now,
		DetonateAt = now + Config.Fuse.Seconds,
		Detonated = false,
		Origin = origin,
		Velocity = velocity,
		HeadAt = head.Position,
		Path = {},
		LastSample = 0,
	}
	counters.Throws += 1
	-- the server's own launch (release point, velocity, time): the thrower's client draws its grenade on this path at once
	-- instead of waiting for the replicated body (Client.Grenade.GrenadePrediction; presentation only)
	send(player, { Phase = "Released", Id = id, Left = s.Left, Origin = origin, Velocity = velocity,
		ServerTime = workspace:GetServerTimeNow() })
	log(`{player.Name} threw grenade {id} ({s.Left} left)`)
	startLoop()
	task.delay(math.max(0, Config.Throw.Seconds - Config.Throw.ReleaseSeconds), function()
		if s.Throwing == token then
			s.Throwing = nil
		end
	end)
end

local function onCommand(player: Player, action: any, aim: any)
	counters.Requests += 1
	local s = stateFor(player)
	if action == "Sync" then
		send(player, { Phase = "Sync", Left = s.Left })
		return
	elseif action == "DevRefill" then
		if RunService:IsStudio() then
			s.Left = Config.Count
			send(player, { Phase = "Sync", Left = s.Left })
		end
		return
	elseif action ~= "Throw" then
		return reject(player, tostring(action), "unknown action")
	end
	if s.Throwing then
		return reject(player, "Throw", "already throwing")
	end
	local character = alive(player)
	if not character then
		return reject(player, "Throw", "dead")
	end
	if character:GetAttribute("VehicleSeat") ~= nil then
		-- truck slice: no grenade from a vehicle seat (on neither seat's CONTROLS list [INFERRED]; never shown)
		return reject(player, "Throw", "in a vehicle seat")
	end
	if s.Left <= 0 then
		return reject(player, "Throw", "NoFrags")
	end
	local dir, why = Throw.aim(character, aim)
	if not dir then
		return reject(player, "Throw", why or "bad direction")
	end
	local token = os.clock()
	s.Throwing = token
	s.Accepted += 1
	send(player, { Phase = "Throwing", Left = s.Left })
	task.delay(Config.Throw.ReleaseSeconds, release, player, s, token, dir)
end

Command.OnServerEvent:Connect(onCommand)
FxOut.OnServerEvent:Connect(function()
	counters.FxClientCalls += 1 -- never acted on: effects flow server → clients only
end)
StateOut.OnServerEvent:Connect(function()
	counters.StateClientCalls += 1
end)

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		local s = stateFor(player)
		s.Left = Config.Count -- every life starts with full grenades (as the weapons' ammunition)
		s.Throwing = nil
		send(player, { Phase = "Sync", Left = s.Left })
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil -- grenades already in the world still detonate
end)

-- Studio-only test hook (server BindableFunction; clients can't reach it):
--   Invoke("status") / Invoke("recent") / Invoke("clear") / Invoke("refill", player) / Invoke("left", player, n)
if RunService:IsStudio() then
	local bf = Instance.new("BindableFunction")
	bf.Name = "GrenadeDebug"
	bf.OnInvoke = function(cmd: string, a: any, b: any): any
		if cmd == "status" then
			local list = {}
			for id, g in active do
				local owner = nil
				pcall(function()
					owner = g.Body:GetNetworkOwner()
				end)
				table.insert(list, { Id = id, Position = g.Body.Position, Velocity = g.Body.AssemblyLinearVelocity,
					Age = os.clock() - g.ReleasedAt, ServerOwned = owner == nil })
			end
			local players = {}
			for p, s in states do
				players[p.Name] = { Left = s.Left, Throwing = s.Throwing ~= nil, Accepted = s.Accepted, Rejected = s.Rejected }
			end
			local folder = workspace:FindFirstChild("Grenades")
			return { Active = list, Loop = loop ~= nil, Counters = table.clone(counters), Players = players,
				FolderChildren = if folder then #folder:GetChildren() else 0 }
		elseif cmd == "recent" then
			return recent
		elseif cmd == "clear" then
			table.clear(recent)
			for k in counters do
				counters[k] = 0
			end
			return true
		elseif cmd == "refill" or cmd == "left" then
			if typeof(a) == "Instance" and a:IsA("Player") then
				local s = stateFor(a)
				s.Left = if cmd == "left" then tonumber(b) or 0 else Config.Count
				send(a, { Phase = "Sync", Left = s.Left })
				return s.Left
			end
			return nil
		end
		return { Error = "unknown command" }
	end
	bf.Parent = script
end
