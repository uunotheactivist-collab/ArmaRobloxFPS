--!strict
-- Vehicle authority (server). Evidence and values: Shared.Config.Vehicles, ReferenceAnalysis/Truck/Truck_Analysis.md.
--   * Every vehicle in the Workspace with the attribute `Vehicle` (its type) and `VehicleId` is registered. Its state
--     (driver door, key, parking brake, lights, seat occupancy) lives here and is published as model attributes.
--   * A client only asks: ("Interact", vehicleModel, action, targetPart, seatId?, aimDirection?). The request is checked
--     for types, rate, a live character, that the target part belongs to that vehicle, reach (range + line of sight from
--     the server's own eye point: the seat's eye when seated, else the head), and that the action is OFFERED for the
--     server's state and the player's seat (Shared.Vehicles.VehicleActions: the same rules that draw the client's
--     prompt). Positions are never accepted; the aim direction only steers the server's own visibility ray.
--   * Seating is the server's: after the measured press-to-cut delay the character is placed on the seat and welded to
--     the anchored truck (so the client can't move it), Movement is told it is mounted; leaving places it at the
--     seat's exit point (checked free). A seat is reserved at the request, so two players can't take the same one.
--   * Death, respawn, leaving the game: the seat is released through the existing death path (nothing else changes).
--   * The truck never moves in the footage: no driving, engine, damage or destruction is built (UNKNOWN).
-- Studio-only test hook: BindableFunction VehicleDebug.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Vehicles"))
local Actions = require(Shared:WaitForChild("Vehicles"):WaitForChild("VehicleActions"))
local Remotes = Shared:WaitForChild("Remotes")
local Command = Remotes:WaitForChild(Config.Remotes.Command) :: RemoteEvent
local StateOut = Remotes:WaitForChild(Config.Remotes.State) :: RemoteEvent
local MovementControl = ServerScriptService:WaitForChild("Server"):WaitForChild("Movement"):WaitForChild("MovementServer")
	:WaitForChild("MovementControl") :: BindableFunction

local A = Config.Attributes

type Seat = { Id: string, Kind: string, Part: BasePart, Occupant: number, Reserved: number }
type Vehicle = {
	Model: Model,
	Id: string,
	Type: any,
	State: { DriverDoor: string, Key: string, ParkingBrake: boolean, Lights: boolean },
	Seats: { [string]: Seat },
	Door: Model?,
}
type PlayerState = {
	Vehicle: Vehicle?,
	Seat: string?,
	Busy: boolean,
	Weld: WeldConstraint?,
	Window: number,
	Count: number,
	Accepted: number,
	Refused: number,
}

local vehicles: { [Model]: Vehicle } = {}
local states: { [Player]: PlayerState } = {}
local counters = { Requests = 0, Accepted = 0, Refused = 0, Entered = 0, Left = 0, Released = 0, StateClientCalls = 0 }
local log: { any } = {}

local function note(kind: string, who: string, detail: string)
	table.insert(log, { t = os.clock(), Kind = kind, Who = who, Detail = detail })
	while #log > 200 do
		table.remove(log, 1)
	end
	if kind ~= "accept" then
		print(`[Vehicle] {who} {kind}: {detail}`)
	end
end

local function stateFor(p: Player): PlayerState
	local s = states[p]
	if not s then
		s = { Vehicle = nil, Seat = nil, Busy = false, Weld = nil, Window = 0, Count = 0, Accepted = 0, Refused = 0 }
		states[p] = s
	end
	return s
end

local function send(p: Player, msg: any)
	if p.Parent then
		StateOut:FireClient(p, msg)
	end
end

local function refuse(p: Player, action: string, reason: string)
	action = string.sub(action, 1, 40) -- a client's string is never echoed at length
	counters.Refused += 1
	stateFor(p).Refused += 1
	note("refuse", p.Name, `{action}: {reason}`)
	send(p, { Phase = "Refused", Action = action, Reason = reason })
end

-- ── vehicles ──────────────────────────────────────────────────────────────────────────────────────────────────────

local function publish(v: Vehicle)
	local m = v.Model
	m:SetAttribute("DriverDoor", v.State.DriverDoor)
	m:SetAttribute("Key", v.State.Key)
	m:SetAttribute("ParkingBrake", v.State.ParkingBrake)
	m:SetAttribute("Lights", v.State.Lights)
	for id, seat in v.Seats do
		m:SetAttribute("Seat_" .. id, seat.Occupant)
	end
end

local function setDoor(v: Vehicle, open: boolean, by: string)
	v.State.DriverDoor = if open then "Open" else "Closed"
	v.Model:SetAttribute("DriverDoorBy", by) -- presentation: which swing time the clients play
	local door = v.Door
	if door then
		-- the server's door is at its end state at once (collision, line of sight); clients animate the swing
		local closed = door:GetAttribute("ClosedPivot") :: CFrame
		local deg = (door:GetAttribute("OpenDeg") :: number?) or Config.Door.OpenDeg
		door:PivotTo(if open then closed * CFrame.Angles(0, math.rad(deg), 0) else closed)
	end
	publish(v)
end

local function register(model: Model)
	if vehicles[model] then
		return
	end
	local typeName = model:GetAttribute("Vehicle")
	local id = model:GetAttribute("VehicleId")
	local vtype = typeName and Config.Types[typeName :: any]
	if not (vtype and typeof(id) == "string") then
		return
	end
	local v: Vehicle = {
		Model = model,
		Id = id :: string,
		Type = vtype,
		State = { DriverDoor = vtype.Start.DriverDoor, Key = vtype.Start.Key, ParkingBrake = vtype.Start.ParkingBrake,
			Lights = vtype.Start.Lights },
		Seats = {},
		Door = model:FindFirstChild("DriverDoor", true) :: Model?,
	}
	for _, d in model:GetDescendants() do
		local sid = d:GetAttribute("SeatId")
		if d:IsA("BasePart") and typeof(sid) == "string" and d:FindFirstChild("Hip") then
			v.Seats[sid] = { Id = sid, Kind = d:GetAttribute("SeatKind") :: string, Part = d, Occupant = 0, Reserved = 0 }
		end
	end
	vehicles[model] = v
	setDoor(v, v.State.DriverDoor == "Open", "Server")
	note("register", v.Id, `{typeName}, {#model:GetDescendants()} parts`)
end

for _, d in workspace:GetDescendants() do
	if d:IsA("Model") and d:GetAttribute("Vehicle") then
		register(d)
	end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(function()
			if d:GetAttribute("Vehicle") then
				register(d)
			end
		end)
	end
end)

-- ── checks ────────────────────────────────────────────────────────────────────────────────────────────────────────

local function alive(p: Player): (Model?, Humanoid?, BasePart?, BasePart?)
	local c = p.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local root = c and c:FindFirstChild("HumanoidRootPart")
	local head = c and c:FindFirstChild("Head")
	if not (c and hum and root and head and root:IsA("BasePart") and head:IsA("BasePart")) or hum.Health <= 0
		or not c:IsDescendantOf(workspace) then
		return nil, nil, nil, nil
	end
	return c, hum, root, head
end

-- closest point of a part to a position
local function closest(part: BasePart, from: Vector3): Vector3
	local rel = part.CFrame:PointToObjectSpace(from)
	local h = part.Size / 2
	return part.CFrame:PointToWorldSpace(Vector3.new(math.clamp(rel.X, -h.X, h.X), math.clamp(rel.Y, -h.Y, h.Y),
		math.clamp(rel.Z, -h.Z, h.Z)))
end

-- Range + line of sight from where the player sees, as the server knows it: the seat's eye point while seated in this
-- vehicle (the client's camera is exactly there), else the server's head. With the client's aim direction (a unit
-- vector, checked in onCommand) the server's OWN ray from that point along it must reach the target part first — a
-- client can only pick what is really visible from its eye; without one, the straight line to the target's nearest point
-- must be clear (it can be blocked when the target is visible only past an edge, e.g. a bed side over a bench).
local function reachable(character: Model, origin: Vector3, part: BasePart, aimDir: Vector3?): (boolean, string?)
	local point = closest(part, origin)
	local d = point - origin
	if d.Magnitude > Config.Prompt.RangeStuds then
		return false, string.format("out of range (%.1f studs)", d.Magnitude)
	end
	if d.Magnitude < 0.05 then
		return true, nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = false
	if aimDir then
		local along = workspace:Raycast(origin, aimDir * (Config.Prompt.RangeStuds + 0.5), params)
		if along and along.Instance == part then
			return true, nil
		end
	end
	local hit = workspace:Raycast(origin, d * 1.02, params)
	if hit and hit.Instance ~= part and hit.Distance < d.Magnitude - 0.15 and hit.Instance.Transparency < 1 then
		return false, "blocked by " .. hit.Instance:GetFullName()
	end
	return true, nil
end

local function ctxFor(s: PlayerState, v: Vehicle, target: BasePart): any
	local occupied = {}
	for id, seat in v.Seats do
		occupied[id] = seat.Occupant ~= 0 or seat.Reserved ~= 0
	end
	local seatKind = nil
	if s.Vehicle == v and s.Seat then
		seatKind = v.Seats[s.Seat].Kind
	end
	return { DriverDoor = v.State.DriverDoor, Key = v.State.Key, ParkingBrake = v.State.ParkingBrake, Occupied = occupied },
		{ SeatKind = seatKind, Seat = s.Seat, Target = target:GetAttribute("VehicleTarget"), TargetSeat = target:GetAttribute("SeatId") }
end

-- ── seating ───────────────────────────────────────────────────────────────────────────────────────────────────────

local function setCharacterSeat(c: Model, v: Vehicle?, seat: Seat?)
	c:SetAttribute(A.Vehicle, if v then v.Id else nil)
	c:SetAttribute(A.Seat, if seat then seat.Id else nil)
	c:SetAttribute(A.SeatKind, if seat then seat.Kind else nil)
end

local function seatPlayer(p: Player, s: PlayerState, v: Vehicle, seat: Seat): (boolean, string?)
	local c, hum, root = alive(p)
	if not (c and hum and root) then
		return false, "dead"
	end
	if s.Weld then
		s.Weld:Destroy()
		s.Weld = nil
	end
	if s.Vehicle and s.Seat then
		local old = s.Vehicle.Seats[s.Seat]
		if old and old.Occupant == p.UserId then
			old.Occupant = 0
		end
	end
	MovementControl:Invoke("mount", p, true)
	local hip = seat.Part:FindFirstChild("Hip") :: Attachment
	root.AssemblyLinearVelocity = Vector3.zero
	c:PivotTo(hip.WorldCFrame * root.CFrame:ToObjectSpace(c:GetPivot()))
	local weld = Instance.new("WeldConstraint")
	weld.Name = "VehicleSeatWeld"
	weld.Part0, weld.Part1 = seat.Part, root
	weld.Parent = root
	hum.Sit = true
	s.Weld = weld
	s.Vehicle, s.Seat = v, seat.Id
	seat.Occupant, seat.Reserved = p.UserId, 0
	setCharacterSeat(c, v, seat)
	publish(v)
	return true, nil
end

-- The seat's exit point, if a character fits there (nothing solid in a body-sized box above the ground). Exit attachments
-- sit on the ground where the feet go and face the way the player will face [the one bed exit and the cab exit seen:
-- Truck_Analysis §3]. The one on the side the player aimed at (attribute ExitSide of the target part: "L" / "R" / "Rear")
-- is tried first [INFERRED: the bed exit seen was on the side aimed at, 623 → 629], then the others by name.
local function exitPoint(v: Vehicle, seat: Seat, c: Model, side: string?): CFrame?
	local candidates = {}
	for _, a in seat.Part:GetChildren() do
		if a:IsA("Attachment") and string.sub(a.Name, 1, 4) == "Exit" then
			table.insert(candidates, a)
		end
	end
	local preferred = "Exit" .. (side or "")
	table.sort(candidates, function(a, b)
		local pa, pb = a.Name == preferred, b.Name == preferred
		if pa ~= pb then
			return pa
		end
		return a.Name < b.Name
	end)
	local hum = c:FindFirstChildOfClass("Humanoid")
	local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local rootHeight = if hum and root then hum.HipHeight + root.Size.Y / 2 else 3
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { c }
	params.RespectCanCollide = true
	for _, a in candidates do
		local feet = (a :: Attachment).WorldCFrame
		local parts = workspace:GetPartBoundsInBox(feet * CFrame.new(0, 2.6, 0), Vector3.new(2, 4.6, 1.2), params)
		if #parts == 0 then
			return feet + Vector3.new(0, rootHeight, 0)
		end
	end
	return nil
end

local function unseat(p: Player, s: PlayerState, place: CFrame?)
	local v, seatId = s.Vehicle, s.Seat
	local body = p.Character
	local root = body and body:FindFirstChild("HumanoidRootPart") :: BasePart?
	if place and root then
		-- the server holds the body while it is placed at the exit: whatever this client's own copy carries (a forged
		-- velocity or position from while it sat) can't take it anywhere once the weld goes; released a few frames later
		root.Anchored = true
	end
	if s.Weld then
		s.Weld:Destroy()
		s.Weld = nil
	end
	if v and seatId then
		local seat = v.Seats[seatId]
		if seat and seat.Occupant == p.UserId then
			seat.Occupant = 0
		end
		publish(v)
	end
	s.Vehicle, s.Seat = nil, nil
	local c = p.Character
	if c then
		setCharacterSeat(c, nil, nil)
		local hum = c:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.Sit = false
		end
	end
	MovementControl:Invoke("mount", p, false)
	if place then
		MovementControl:Invoke("place", p, place)
		if root then
			task.delay(0.15, function()
				if root.Parent then
					root.Anchored = false
				end
			end)
		end
	end
end

-- release whatever the player holds (death, respawn, leaving the game): no placement
local function release(p: Player, why: string)
	local s = states[p]
	if not s then
		return
	end
	for _, v in vehicles do
		for _, seat in v.Seats do
			if seat.Reserved == p.UserId then
				seat.Reserved = 0
			end
		end
	end
	if s.Vehicle then
		counters.Released += 1
		note("release", p.Name, why)
		local v, seat = s.Vehicle, s.Seat and s.Vehicle.Seats[s.Seat]
		unseat(p, s, nil)
		send(p, { Phase = "Left", Action = "Released", Reason = why, Vehicle = v.Id, Seat = seat and seat.Id,
			SeatKind = seat and seat.Kind })
	end
	s.Busy = false
end

-- ── actions ───────────────────────────────────────────────────────────────────────────────────────────────────────

local CUT: { [string]: string } = { EnterDriver = "EnterDriver", EnterBack = "EnterBack", MoveSeat = "MoveSeat" }

local function entrySeat(v: Vehicle, kind: string): Seat?
	local entry = v.Model:GetAttribute(if kind == "Back" then "EntryBackSeat" else "EntryDriverSeat")
	local first = if typeof(entry) == "string" then v.Seats[entry] else nil
	if first and first.Occupant == 0 and first.Reserved == 0 then
		return first
	end
	local ids = {}
	for id, seat in v.Seats do
		if seat.Kind == kind and seat.Occupant == 0 and seat.Reserved == 0 then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return if ids[1] then v.Seats[ids[1]] else nil
end

local function perform(p: Player, s: PlayerState, v: Vehicle, action: string, target: BasePart, seatArg: string?)
	if action == "OpenDoor" or action == "CloseDoor" then
		setDoor(v, action == "OpenDoor", if s.Vehicle == v then "Inside" else "Outside")
	elseif action == "KeyRun" or action == "KeyStop" then
		v.State.Key = if action == "KeyRun" then "RUN" else "STOP"
		publish(v)
	elseif action == "BrakeRelease" or action == "BrakeSet" then
		v.State.ParkingBrake = action == "BrakeSet"
		publish(v)
	elseif action == "EnterDriver" or action == "EnterBack" or action == "MoveSeat" then
		local seat: Seat?
		if action == "MoveSeat" then
			seat = if seatArg then v.Seats[seatArg] else nil
		else
			seat = entrySeat(v, if action == "EnterBack" then "Back" else "Driver")
		end
		if not seat or seat.Occupant ~= 0 or seat.Reserved ~= 0 then
			return refuse(p, action, "seat taken")
		end
		seat.Reserved = p.UserId -- nobody else can take it during the delay
		s.Busy = true
		local delay = Config.CutDelay[CUT[action]]
		task.delay(delay, function()
			s.Busy = false
			if seat.Reserved ~= p.UserId then
				return -- released meanwhile (death / leaving)
			end
			local ok, why = seatPlayer(p, s, v, seat)
			if not ok then
				seat.Reserved = 0
				return refuse(p, action, why or "failed")
			end
			counters.Entered += 1
			note("seat", p.Name, `{action} → {v.Id}.{seat.Id}`)
			send(p, { Phase = "Entered", Action = action, Vehicle = v.Id, Seat = seat.Id, SeatKind = seat.Kind })
		end)
		return
	elseif action == "Leave" then
		local seat = s.Seat and v.Seats[s.Seat]
		local c = p.Character
		if not (seat and c) then
			return refuse(p, action, "not seated")
		end
		local side = target:GetAttribute("ExitSide")
		local sideName = if typeof(side) == "string" then side else nil
		local cf = exitPoint(v, seat, c, sideName)
		if not cf then
			return refuse(p, action, "exit blocked")
		end
		s.Busy = true
		local delay = if seat.Kind == "Driver" then Config.CutDelay.LeaveDriver else Config.CutDelay.LeaveBack
		task.delay(delay, function()
			s.Busy = false
			if s.Vehicle ~= v or s.Seat ~= seat.Id then
				return
			end
			local c2, hum = alive(p)
			if not (c2 and hum) then
				return
			end
			local place = exitPoint(v, seat, c2, sideName)
			if not place then
				return refuse(p, action, "exit blocked")
			end
			unseat(p, s, place)
			counters.Left += 1
			note("leave", p.Name, `{v.Id}.{seat.Id}`)
			send(p, { Phase = "Left", Action = action, Vehicle = v.Id, Seat = seat.Id, SeatKind = seat.Kind })
		end)
		return
	end
	send(p, { Phase = "Done", Action = action, Vehicle = v.Id })
end

local function onCommand(p: Player, verb: any, model: any, action: any, target: any, seatArg: any, aim: any)
	counters.Requests += 1
	local s = stateFor(p)
	local now = os.clock()
	if now - s.Window >= 1 then
		s.Window, s.Count = now, 0
	end
	s.Count += 1
	if s.Count > Config.RatePerSecond then
		return refuse(p, tostring(action), "rate")
	end
	if verb ~= "Interact" or typeof(action) ~= "string" or #action > 32 then
		return refuse(p, tostring(action), "bad request")
	end
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not vehicles[model] then
		return refuse(p, action, "not a vehicle")
	end
	local v = vehicles[model]
	if typeof(target) ~= "Instance" or not target:IsA("BasePart") or not target:IsDescendantOf(model)
		or typeof(target:GetAttribute("VehicleTarget")) ~= "string" then
		return refuse(p, action, "not a target of this vehicle")
	end
	if seatArg ~= nil and (typeof(seatArg) ~= "string" or not v.Seats[seatArg]) then
		return refuse(p, action, "bad seat")
	end
	if s.Busy then
		return refuse(p, action, "busy")
	end
	local c, _, root, head = alive(p)
	if not (c and root and head) then
		return refuse(p, action, "dead")
	end
	if s.Vehicle and s.Vehicle ~= v then
		return refuse(p, action, "in another vehicle")
	end
	-- the aim direction is only a direction: finite, unit length, else ignored (never a position)
	local aimDir: Vector3? = nil
	if typeof(aim) == "Vector3" and aim.Magnitude == aim.Magnitude and math.abs(aim.Magnitude - 1) < 0.01 then
		aimDir = aim
	end
	local origin = head.Position
	if s.Vehicle == v and s.Seat then
		local eye = v.Seats[s.Seat].Part:FindFirstChild("Eye")
		if eye and eye:IsA("Attachment") then
			origin = eye.WorldPosition
		end
	else
		-- on foot: from the place Movement last VALIDATED (a body the client has just moved — a teleport the validator
		-- hasn't judged yet, or the server catching up through a wall — can't reach anything until it is validated)
		local valid = MovementControl:Invoke("validated", p)
		if typeof(valid) == "CFrame" then
			if (root.Position - valid.Position).Magnitude > 4 then
				return refuse(p, action, "position not validated yet")
			end
			origin = valid.Position + (head.Position - root.Position)
		end
	end
	local ok, why = reachable(c, origin, target, aimDir)
	if not ok then
		return refuse(p, action, why or "unreachable")
	end
	local state, ctx = ctxFor(s, v, target)
	if not Actions.isOffered(state, ctx, action, seatArg) then
		return refuse(p, action, "not offered")
	end
	if Actions.NotBuilt[action] then
		return refuse(p, action, "NotBuilt") -- offered in the reference, never pressed there: UNKNOWN effect
	end
	counters.Accepted += 1
	s.Accepted += 1
	note("accept", p.Name, `{action} {v.Id} {tostring(seatArg or "")}`)
	perform(p, s, v, action, target, seatArg)
end

Command.OnServerEvent:Connect(onCommand)
StateOut.OnServerEvent:Connect(function()
	counters.StateClientCalls += 1 -- never acted on: state flows server → clients only
end)

local function watchCharacter(p: Player, c: Model)
	local hum = c:WaitForChild("Humanoid", 10) :: Humanoid?
	if hum then
		hum.Died:Connect(function()
			release(p, "died") -- the existing death / respawn path does the rest
		end)
	end
end
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(c)
		release(p, "respawned")
		watchCharacter(p, c)
	end)
end)
for _, p in Players:GetPlayers() do
	p.CharacterAdded:Connect(function(c)
		release(p, "respawned")
		watchCharacter(p, c)
	end)
	if p.Character then
		task.spawn(watchCharacter, p, p.Character)
	end
end
Players.PlayerRemoving:Connect(function(p)
	release(p, "left the game")
	states[p] = nil
end)

-- ── Studio-only test hook ─────────────────────────────────────────────────────────────────────────────────────────

if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "VehicleDebug"
	hook.OnInvoke = function(cmd: string, a1: any, a2: any): any
		if cmd == "status" then
			local out = { Counters = table.clone(counters), Vehicles = {}, Players = {} }
			for _, v in vehicles do
				local seats = {}
				for id, seat in v.Seats do
					seats[id] = { Kind = seat.Kind, Occupant = seat.Occupant, Reserved = seat.Reserved }
				end
				out.Vehicles[v.Id] = { State = table.clone(v.State), Seats = seats, Model = v.Model }
			end
			for p, s in states do
				out.Players[p.Name] = { Vehicle = s.Vehicle and s.Vehicle.Id, Seat = s.Seat, Busy = s.Busy,
					Welded = s.Weld ~= nil and s.Weld.Parent ~= nil, Accepted = s.Accepted, Refused = s.Refused }
			end
			return out
		elseif cmd == "log" then
			return table.clone(log)
		elseif cmd == "clearlog" then
			table.clear(log)
			return true
		elseif cmd == "occupy" then
			-- a stand-in for a second player: mark a seat occupied (a2 = user id; 0 frees it)
			for _, v in vehicles do
				if v.Id == a1.Vehicle and v.Seats[a1.Seat] then
					v.Seats[a1.Seat].Occupant = a2 or -1
					publish(v)
					return true
				end
			end
			return false
		elseif cmd == "reset" then
			-- every vehicle back to its start state; seated players are left at their seat's exit
			for p, s in states do
				if s.Vehicle then
					local v, seat = s.Vehicle, s.Seat and s.Vehicle.Seats[s.Seat]
					local c = p.Character
					unseat(p, s, if seat and c then exitPoint(v, seat, c) else nil)
					send(p, { Phase = "Left", Action = "Released", Reason = "reset", Vehicle = v.Id, Seat = seat and seat.Id,
						SeatKind = seat and seat.Kind })
				end
				s.Busy = false
			end
			for _, v in vehicles do
				for _, seat in v.Seats do
					seat.Occupant, seat.Reserved = 0, 0
				end
				v.State.Key, v.State.ParkingBrake, v.State.Lights = v.Type.Start.Key, v.Type.Start.ParkingBrake, v.Type.Start.Lights
				setDoor(v, v.Type.Start.DriverDoor == "Open", "Server")
			end
			return true
		end
		return nil
	end
	hook.Parent = script
end
