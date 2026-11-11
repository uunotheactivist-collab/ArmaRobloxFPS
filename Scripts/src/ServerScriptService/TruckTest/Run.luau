--!strict
-- Truck test, server side (Studio only; delete the TruckTest folders to remove it). Driven through execute_luau (Server
-- datamodel); the client half is StarterPlayerScripts.TruckTest.Run. Reads the running server through its Studio hooks.
--   Run.prepare()              client teleports allowed (the old suites' rule), vehicles reset, logs cleared, the player
--                              placed (server-side) behind the tailgate
--   Run.placeAt(spot)          a server placement at a TestSpot (production rules); Run.switch(on) the Studio switch
--   Run.status()               VehicleDebug status (counters, vehicles, players)
--   Run.view()                 the player's character as the server sees it: seat attributes, the seat weld, the root
--                              against its seat's Hip, Movement's view (locked / speeds), the truck's pivot
--   Run.occupy(seat, userId)   a stand-in second player on a seat (0 frees it)
--   Run.kill()                 kill the player's character (death in a seat)
--   Run.log()                  the vehicle log; Run.weaponRejects() the weapon / grenade refusals seen in the output
--   Run.netStart() / netStop() count every client → server remote event

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local LogService = game:GetService("LogService")

local Run = {}

local function dbg(): BindableFunction
	return ServerScriptService:FindFirstChild("VehicleDebug", true) :: BindableFunction
end

local function player(): Player
	return Players:GetPlayers()[1]
end

local function truck(): Model?
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("VehicleId") == "TRUCK1" then
			return d
		end
	end
	return nil
end

-- a server placement at one of the truck's TestSpot attachments (production rules: the validator's own baseline)
function Run.placeAt(spot: string): boolean
	local t = truck()
	local a = t and t:FindFirstChild("TestSpot_" .. spot, true) :: Attachment?
	local c = player().Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not (a and root and hum) then
		return false
	end
	local md = ServerScriptService:FindFirstChild("MovementDebug", true) :: BindableFunction
	md:Invoke("teleport", player(), a.WorldCFrame + Vector3.new(0, hum.HipHeight + root.Size.Y / 2, 0))
	task.wait(0.5)
	return true
end

-- the old suites' Studio client-teleport switch (on: tests place the player client-side; off: production rules)
function Run.switch(on: boolean)
	require(ServerScriptService.MovementTest.Run).dbg("allowClientTeleports", nil, on)
end

function Run.prepare(): any
	Run.switch(true)
	dbg():Invoke("reset")
	dbg():Invoke("clearlog")
	local t = truck()
	Run.placeAt("Tailgate") -- by the truck already, so the first client-side placement is a short one
	return { player = player().Name, truck = t and t:GetFullName(), pivot = t and t:GetPivot().Position }
end

function Run.status(): any
	return dbg():Invoke("status")
end

function Run.log(): any
	return dbg():Invoke("log")
end

function Run.occupy(seat: string, userId: number?): boolean
	return dbg():Invoke("occupy", { Vehicle = "TRUCK1", Seat = seat }, userId or -1)
end

function Run.kill(): boolean
	local c = player().Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if h then
		h.Health = 0
		return true
	end
	return false
end

function Run.view(): any
	local p = player()
	local c = p.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local t = truck()
	local out: any = {
		Seat = c and c:GetAttribute("VehicleSeat"),
		SeatKind = c and c:GetAttribute("VehicleSeatKind"),
		Vehicle = c and c:GetAttribute("Vehicle"),
		Locked = c and c:GetAttribute("MoveLocked"),
		WalkSpeed = hum and hum.WalkSpeed,
		JumpHeight = hum and hum.JumpHeight,
		Sit = hum and hum.Sit,
		Health = hum and hum.Health,
		Welded = root ~= nil and root:FindFirstChild("VehicleSeatWeld") ~= nil,
		Root = root and root.Position,
		TruckPivot = t and t:GetPivot(),
		TruckAnchored = (function()
			if not t then
				return nil
			end
			for _, d in t:GetDescendants() do
				if d:IsA("BasePart") and not d.Anchored then
					return false
				end
			end
			return true
		end)(),
	}
	if t and out.Seat then
		for _, d in t:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("SeatId") == out.Seat then
				local hip = d:FindFirstChild("Hip") :: Attachment?
				out.RootFromHip = hip and root and (root.Position - hip.WorldPosition).Magnitude
			end
		end
	end
	local md = ServerScriptService:FindFirstChild("MovementDebug", true) :: BindableFunction?
	out.Movement = md and md:Invoke("status", p)
	return out
end

-- weapon / grenade refusals printed by the servers since the playtest began (newest last)
function Run.weaponRejects(): { string }
	local out = {}
	for _, m in LogService:GetLogHistory() do
		local s = m.message
		if string.find(s, "driver seat", 1, true) or string.find(s, "[Vehicle]", 1, true) then
			table.insert(out, string.sub(s, 1, 160))
		end
	end
	while #out > 40 do
		table.remove(out, 1)
	end
	return out
end

local counts: { [string]: number } = {}
local conns: { RBXScriptConnection } = {}
function Run.netStart(): number
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	table.clear(counts)
	local n = 0
	for _, r in ReplicatedStorage:GetDescendants() do
		if r:IsA("RemoteEvent") then
			n += 1
			table.insert(conns, r.OnServerEvent:Connect(function()
				counts[r.Name] = (counts[r.Name] or 0) + 1
			end))
		end
	end
	return n
end

function Run.netStop(): { [string]: number }
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	return table.clone(counts)
end

return Run
