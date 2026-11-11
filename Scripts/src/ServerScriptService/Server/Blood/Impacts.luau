--!strict
-- Blood + impact events (server). Entries: Impacts.onShot, called by Server.WeaponServer with the trace it has just
-- computed itself (Server.Ballistics, from the server's own head position) and its body-hit results
-- (Server.BodyState); and Impacts.onBurst (grenade slice), the same for several server traces at once (a grenade's
-- fragments that reached bodies), sent in one message. From that authoritative data alone it makes:
--   - one presentation event per shot for every client (Shared.Remotes.ImpactFx, server → client only):
--       body entries (spot, puff, mist, droplets away from the body, an exit spray if the bullet left the part, a
--       bleeding mist unless the body is DEAD) and world entries / exits (grey puffs);
--   - the persistent blood: stains on the hit parts (entry and exit), drops on the floor around and behind the body,
--     and a splat on the next surface behind it (a wall within 3 m) or on the floor behind.
-- It does no hit test, applies no damage and changes no state. Nothing a client sends reaches it.
-- Basis: ReferenceAnalysis/Blood/Blood_Analysis.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Blood"))
local Marks = require(script.Parent:WaitForChild("SurfaceMarks"))
local Stains = require(script.Parent:WaitForChild("Stains"))

local Impacts = {}

-- The presentation remote: server → clients. A client firing it is ignored (only counted, for the tests).
local remotes = Shared:WaitForChild("Remotes")
local remote = remotes:FindFirstChild(Config.Remote) :: RemoteEvent?
if not remote then
	local r = Instance.new("RemoteEvent")
	r.Name = Config.Remote
	r.Parent = remotes
	remote = r
end
local fx = remote :: RemoteEvent
Impacts.ClientCalls = 0
fx.OnServerEvent:Connect(function()
	Impacts.ClientCalls += 1 -- never acted on: presentation flows server → client only
end)

Impacts.Recent = {} :: { any } -- Studio only: the last shots' events, for the tests
local rng = Random.new()

local function characterOf(part: Instance): Model?
	local m = part:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") then
			return m
		end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function flat(v: Vector3): Vector3
	local h = Vector3.new(v.X, 0, v.Z)
	return if h.Magnitude > 1e-3 then h.Unit else Vector3.zero
end

-- Floor drops for one body hit: most near the body, some 1–3 m behind it along the shot.
local function drops(model: Model, at: Vector3, dir: Vector3, placed: { any })
	local M = Config.Marks
	local fwd = flat(dir)
	local side = Vector3.yAxis:Cross(fwd)
	for _ = 1, rng:NextInteger(M.DropsPerHit[1], M.DropsPerHit[2]) do
		local offset
		if fwd ~= Vector3.zero and rng:NextNumber() < M.DropFarChance then
			offset = fwd * rng:NextNumber(M.FarStuds, M.SpatterStuds) + side * rng:NextNumber(-1, 1)
		else
			local a = rng:NextNumber(0, 2 * math.pi)
			local r = rng:NextNumber(M.DropNearStuds[1], M.DropNearStuds[2])
			offset = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r) + fwd * 0.5
		end
		local part, pos, normal = Marks.floorBelow(at + offset, { model })
		if part and pos and normal then
			if Marks.place(part, pos, normal, rng:NextNumber(M.DropSize[1], M.DropSize[2]), "drop", if fwd == Vector3.zero then offset else fwd) then
				table.insert(placed, { Kind = "drop", Surface = part.Name, Position = pos })
			end
		end
	end
end

-- After a through-and-through: a splat on the next surface the bullet reaches within 3 m (a wall behind the body),
-- else on the floor 1–3 m behind.
local function spatter(events: { any }, from: number, exitPos: Vector3, model: Model, dir: Vector3, placed: { any })
	local M = Config.Marks
	for j = from, #events do
		local e = events[j]
		if e.Kind == "Enter" and e.Part then
			if e.Surface ~= "Target" and (e.Position - exitPos).Magnitude <= M.SpatterStuds then
				if Marks.place(e.Part, e.Position, e.Normal or -dir, rng:NextNumber(M.SplatSize[1], M.SplatSize[2]), "splat", nil) then
					table.insert(placed, { Kind = "splat", Surface = e.Part.Name, Position = e.Position })
					return
				end
			end
			break
		end
	end
	local fwd = flat(dir)
	if fwd == Vector3.zero then
		return
	end
	local part, pos, normal = Marks.floorBelow(exitPos + fwd * rng:NextNumber(M.FarStuds, M.SpatterStuds), { model })
	if part and pos and normal then
		if Marks.place(part, pos, normal, rng:NextNumber(M.SplatSize[1], M.SplatSize[2]), "splat", nil) then
			table.insert(placed, { Kind = "splat", Surface = part.Name, Position = pos })
		end
	end
end

local function locations(damageResults: { any }?): { [Humanoid]: { Part: string?, Location: string? } }
	local locationOf: { [Humanoid]: { Part: string?, Location: string? } } = {}
	for _, r in damageResults or {} do
		if r.Humanoid and r.Body then
			locationOf[r.Humanoid] = { Part = r.Body.Part, Location = r.Body.Location }
		end
	end
	return locationOf
end

-- One trace's presentation events (into `out`) and persistent marks (into `placed`); returns the stains added. Shared by
-- onShot and onBurst, so both make exactly the same blood from a trace.
local function collect(trace: any, locationOf: { [Humanoid]: { Part: string?, Location: string? } }, out: { any }, placed: { any }): number
	local dir: Vector3 = trace.Direction
	local events = trace.Events
	local stains = 0
	for i, e in events do
		if e.Kind == "Enter" and e.Part then
			local normal: Vector3 = e.Normal or -dir
			local model = if e.Surface == "Target" then characterOf(e.Part) else nil
			if model then
				local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
				local nextEvent = events[i + 1]
				local exitPos: Vector3? = nil
				local exitNormal: Vector3? = nil
				if nextEvent and nextEvent.Kind == "Exit" and nextEvent.Part == e.Part then
					exitPos, exitNormal = nextEvent.Position, nextEvent.Normal
				end
				local dead = model:GetAttribute("BodyPhase") == "DEAD" or humanoid.Health <= 0
				local loc = locationOf[humanoid]
				table.insert(out, {
					t = "body",
					p = e.Position,
					n = normal,
					d = dir,
					part = e.Part,
					x = exitPos,
					bleed = not dead,
					loc = if loc and loc.Part == e.Part.Name then loc.Location else nil,
				})
				if Stains.add(e.Part, e.Position, normal) then
					stains += 1
				end
				if exitPos and Stains.add(e.Part, exitPos, exitNormal or dir) then
					stains += 1
				end
				drops(model, e.Position, dir, placed)
				if exitPos then
					spatter(events, i + 2, exitPos, model, dir, placed)
				end
			else
				table.insert(out, { t = "world", p = e.Position, n = normal, d = dir, c = e.Surface })
			end
		elseif e.Kind == "Exit" and e.Part and e.Surface ~= "Target" and Config.World.ExitPuff then
			table.insert(out, { t = "world", p = e.Position, n = e.Normal or dir, d = dir, c = e.Surface, out = true })
		end
	end
	return stains
end

local function record(shooter: Player?, weaponId: string, origin: Vector3?, out: { any }, placed: { any }, stains: number)
	if RunService:IsStudio() then
		table.insert(Impacts.Recent, {
			At = os.clock(),
			Player = shooter and shooter.Name,
			Weapon = weaponId,
			Origin = origin,
			Events = out,
			Placed = placed,
			Stains = stains,
		})
		while #Impacts.Recent > 64 do
			table.remove(Impacts.Recent, 1)
		end
	end
end

-- shooter / weaponId: who fired (records only). trace: Server.Ballistics.trace's result. damageResults:
-- WeaponServer's per-target results ({ Humanoid, Body = BodyState record }), used only for the hit location label.
function Impacts.onShot(shooter: Player?, weaponId: string, trace: any, damageResults: { any }?)
	local out = {}
	local placed = {}
	local stains = collect(trace, locations(damageResults), out, placed)
	if #out > 0 then
		fx:FireAllClients(out)
	end
	record(shooter, weaponId, trace.Origin, out, placed, stains)
end

-- Several server traces from one event (a grenade's fragments that reached bodies, Server.Grenade): for each trace the
-- same events and marks as onShot, sent to clients in ONE message. Additive (grenade slice); onShot is unchanged.
function Impacts.onBurst(source: Player?, weaponId: string, traces: { any }, damageResults: { any }?)
	local out = {}
	local placed = {}
	local locationOf = locations(damageResults)
	local stains = 0
	for _, trace in traces do
		stains += collect(trace, locationOf, out, placed)
	end
	if #out > 0 then
		fx:FireAllClients(out)
	end
	record(source, weaponId, if traces[1] then traces[1].Origin else nil, out, placed, stains)
end

return Impacts
