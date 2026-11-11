--!strict
-- Which interaction a vehicle offers (shared, pure). The client uses it to draw the prompt; the server uses the SAME rules
-- on its own state to decide whether a request is allowed, so a client can never use an action that isn't offered.
-- Evidence: ReferenceAnalysis/Truck/Truck_Analysis.md (prompt texts verbatim [CONFIRMED I9], option pairs [CONFIRMED
-- I10], what each target offers [INFERRED from aim + prompt changing together, I7]).
--
-- state: the vehicle's server state { DriverDoor = "Open" | "Closed", Key = "STOP" | "RUN", ParkingBrake = boolean,
--        Occupied = { [seatId] = true } }
-- ctx:   { SeatKind = "Driver" | "Back" | nil (on foot), Seat = seatId?, Target = target kind?, TargetSeat = seatId? }
-- An option: { Action = string, Text = string, Seat = seatId? }. Up to two (the second is the "○" line).

local VehicleActions = {}

VehicleActions.Texts = table.freeze({
	OpenDoor = "Open door",
	CloseDoor = "Close door",
	EnterDriver = "Get in (driver)",
	EnterPassenger = "Get in (passenger)",
	EnterBack = "Get in (back)",
	MoveSeat = "Move to back seat",
	Leave = "Leave vehicle",
	KeyRun = "Turn key to RUN",
	HoldStart = "Hold START  (WAIT lamp's still on)", -- two spaces before the parenthesis [CONFIRMED]
	KeyStop = "Turn key to STOP",
	LightsOn = "Lights on",
	BrakeRelease = "Release parking brake",
	BrakeSet = "Set parking brake",
})

-- Offered in the reference but never pressed there: what they do is UNKNOWN, so the server answers them with
-- "NotBuilt" and changes nothing (the prompt is still drawn, as in the footage).
VehicleActions.NotBuilt = table.freeze({
	EnterPassenger = true, -- the passenger seat was offered, never entered [CONFIRMED S11]
	HoldStart = true, -- START was never held; the WAIT lamp was still on [CONFIRMED U2 / U3]
	LightsOn = true, -- never pressed; no light is switched on in the video [CONFIRMED U10]
})

local function opt(action: string, seat: string?): any
	return { Action = action, Text = VehicleActions.Texts[action], Seat = seat }
end

function VehicleActions.offer(state: any, ctx: any): { any }
	local doorOpen = state.DriverDoor == "Open"
	local t = ctx.Target
	if ctx.SeatKind == nil then
		-- on foot, outside
		if t == "DriverDoor" then
			if doorOpen then
				return { opt("EnterDriver"), opt("CloseDoor") } -- [CONFIRMED 933–949]
			end
			return { opt("OpenDoor") } -- [CONFIRMED 911–931]
		elseif t == "DriverSeat" then
			if doorOpen then
				return { opt("EnterDriver"), opt("CloseDoor") } -- [CONFIRMED 1012–1026]
			end
		elseif t == "PassengerSeat" then
			if doorOpen then
				return { opt("EnterPassenger") } -- aiming deeper into the cab [CONFIRMED 950–1011]
			end
		elseif t == "Tailgate" or t == "BackSeat" then
			return { opt("EnterBack") } -- [CONFIRMED 91–104, 655–659]
		end
		return {}
	elseif ctx.SeatKind == "Back" then
		if t == "BackSeat" and ctx.TargetSeat and ctx.TargetSeat ~= ctx.Seat and not state.Occupied[ctx.TargetSeat] then
			return { opt("MoveSeat", ctx.TargetSeat) } -- aiming at another bench seat [CONFIRMED text; rule INFERRED S5]
		elseif t == "BedSide" or t == "Tailgate" then
			return { opt("Leave") } -- [CONFIRMED text; where it is offered INFERRED]
		end
		return {}
	elseif ctx.SeatKind == "Driver" then
		if t == "DriverDoor" then
			if doorOpen then
				return { opt("Leave"), opt("CloseDoor") } -- [CONFIRMED 1056–1076, 1472–1490]
			end
			return { opt("OpenDoor") } -- [CONFIRMED 1078–1096, 1435–1469]
		elseif t == "KeySwitch" then
			if state.Key == "RUN" then
				return { opt("HoldStart"), opt("KeyStop") } -- [CONFIRMED 1127–1168]
			end
			local o = { opt("KeyRun") }
			if doorOpen then
				table.insert(o, opt("CloseDoor")) -- [CONFIRMED 1126: "○ Close door" under "Turn key to RUN"]
			end
			return o
		elseif t == "LightsSwitch" then
			return { opt("LightsOn") } -- [CONFIRMED]
		elseif t == "ParkingBrake" then
			return { opt(if state.ParkingBrake then "BrakeRelease" else "BrakeSet") } -- [CONFIRMED U7]
		end
		return {}
	end
	return {}
end

-- Is `action` (with `seat` for MoveSeat) among the options offered for this state and context?
function VehicleActions.isOffered(state: any, ctx: any, action: string, seat: string?): boolean
	for _, o in VehicleActions.offer(state, ctx) do
		if o.Action == action and (action ~= "MoveSeat" or o.Seat == seat) then
			return true
		end
	end
	return false
end

return VehicleActions
