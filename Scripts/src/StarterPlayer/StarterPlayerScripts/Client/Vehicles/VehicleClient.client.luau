--!strict
-- Vehicle client (truck slice). Presentation and requests only; every decision is the server's.
--   * What the player aims at (one ray from the camera; the first thing hit must be a vehicle target part) + the
--     replicated vehicle state + the player's own seat → the offered options (Shared.Vehicles.VehicleActions, the rules
--     the server also checks) → the prompt (PromptWidget).
--   * F: the key box goes pale (4–5 frames) and the request is sent 2 frames after the press [MEASURED]: ("Interact",
--     vehicle, action, target part, seat id). An enter / move / leave request takes the prompt away at once (its pale
--     lasts 1–2 frames [MEASURED]) until the server answers. The mouse wheel moves the [F] between two options
--     [PLACEHOLDER: how it moves is UNKNOWN].
--   * The server's answers: the CONTROLS panel on entering / leaving (ControlsPanel); the camera turn of a cut is
--     applied by Client.Movement through SeatView.consumeSnap; the seated legs / lap arms are SeatBody, the driver's
--     arms DriverArms (told what the prompt is on and what was pressed).
--   * Door swings are played here from the vehicle's DriverDoor attribute (the server's door jumps to its end state),
--     with the measured durations and easing (Config.Door).
-- Studio-only test hook: BindableFunction VehicleClientDebug.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Vehicles"))
local Actions = require(Shared:WaitForChild("Vehicles"):WaitForChild("VehicleActions"))
local Widget = require(script.Parent:WaitForChild("PromptWidget"))
local Panel = require(script.Parent:WaitForChild("ControlsPanel"))
local SeatView = require(script.Parent:WaitForChild("SeatView"))
local DriverArms = require(script.Parent:WaitForChild("DriverArms"))
local SeatBody = require(script.Parent:WaitForChild("SeatBody"))
local Remotes = Shared:WaitForChild("Remotes")
local Command = Remotes:WaitForChild(Config.Remotes.Command) :: RemoteEvent
local StateIn = Remotes:WaitForChild(Config.Remotes.State) :: RemoteEvent

local P = Config.Prompt
local A = Config.Attributes
local player = Players.LocalPlayer

local current: any = { Model = nil, Part = nil, Options = {} }
local lastKey = ""
local active = 1
local pendingUntil = 0
local cutPendingUntil = 0 -- an enter / move / leave request is out: no prompt until the answer
local CUT_ACTIONS = { EnterBack = true, EnterDriver = true, MoveSeat = true, Leave = true }
local messages: { any } = {}
local sent: { any } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- the vehicle model a part belongs to (parts may sit in nested models: the driver door)
local function vehicleOf(part: Instance): Model?
	local m = part:FindFirstAncestorWhichIsA("Model")
	while m do
		if m:GetAttribute("Vehicle") ~= nil then
			return m
		end
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

-- the aimed target: the first thing on the camera's line, if it is a vehicle target part within reach
local function aim(): (Model?, BasePart?)
	local cam = workspace.CurrentCamera
	local c = player.Character
	rayParams.FilterDescendantsInstances = if c then { c, cam } else { cam }
	local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * (P.RangeStuds + 2), rayParams)
	if not hit or typeof(hit.Instance:GetAttribute("VehicleTarget")) ~= "string" then
		return nil, nil
	end
	local m = vehicleOf(hit.Instance)
	if not m or hit.Distance > P.RangeStuds then
		return nil, nil
	end
	return m, hit.Instance :: BasePart
end

local function stateOf(m: Model): any
	local occupied = {}
	for name, value in m:GetAttributes() do
		if string.sub(name, 1, 5) == "Seat_" then
			occupied[string.sub(name, 6)] = value ~= 0
		end
	end
	return { DriverDoor = m:GetAttribute("DriverDoor"), Key = m:GetAttribute("Key"),
		ParkingBrake = m:GetAttribute("ParkingBrake") == true, Occupied = occupied }
end

local function offered(m: Model?, part: BasePart?): { any }
	if not (m and part) then
		return {}
	end
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if not (h and h.Health > 0) then
		return {}
	end
	local seated = c and c:GetAttribute(A.Vehicle)
	if seated ~= nil and seated ~= m:GetAttribute("VehicleId") then
		return {}
	end
	return Actions.offer(stateOf(m), {
		SeatKind = c and c:GetAttribute(A.SeatKind),
		Seat = c and c:GetAttribute(A.Seat),
		Target = part:GetAttribute("VehicleTarget"),
		TargetSeat = part:GetAttribute("SeatId"),
	})
end

RunService:BindToRenderStep("VehiclePrompt", Enum.RenderPriority.Camera.Value + 3, function()
	local m, part = aim()
	local options = if os.clock() < cutPendingUntil then {} else offered(m, part)
	DriverArms.hover(if #options > 0 then part else nil)
	local texts = {}
	for _, o in options do
		table.insert(texts, o.Text)
	end
	local key = table.concat(texts, "|") .. "@" .. (if part then part:GetFullName() else "")
	if key ~= lastKey then
		lastKey = key
		active = 1
	end
	current = { Model = m, Part = part, Options = options }
	SeatView.PromptActive = #options > 0
	Widget.set(texts, active)
end)

local function send(model: Model, action: string, part: BasePart, seat: string?)
	-- the camera's direction lets the server check visibility with its own ray from its own eye point
	Command:FireServer("Interact", model, action, part, seat, workspace.CurrentCamera.CFrame.LookVector)
	if RunService:IsStudio() then
		table.insert(sent, { At = os.clock(), Action = action, Seat = seat })
		while #sent > 64 do
			table.remove(sent, 1)
		end
	end
end

local function press(): any
	local o = current.Options[active]
	if not o or os.clock() < pendingUntil then
		return nil
	end
	local model, part = current.Model, current.Part
	Widget.press()
	pendingUntil = os.clock() + 1.0
	DriverArms.pressed(part, o.Action) -- the driver's arm goes toward what is used (presentation)
	local cut = CUT_ACTIONS[o.Action] == true
	task.delay(P.SendAfterSeconds, function()
		if cut then
			cutPendingUntil = os.clock() + 1.0
			Widget.withdraw()
		end
		send(model, o.Action, part, o.Seat)
	end)
	return { Action = o.Action, Seat = o.Seat, Text = o.Text }
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == P.Key then
		press()
	end
end)
UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
	if processed or input.UserInputType ~= P.SwitchInput then
		return
	end
	if #current.Options == 2 then
		active = 3 - active
	end
end)

StateIn.OnClientEvent:Connect(function(msg: any)
	if typeof(msg) ~= "table" then
		return
	end
	if RunService:IsStudio() then
		table.insert(messages, { At = os.clock(), Phase = msg.Phase, Action = msg.Action, Reason = msg.Reason,
			Seat = msg.Seat, SeatKind = msg.SeatKind })
		while #messages > 64 do
			table.remove(messages, 1)
		end
	end
	pendingUntil = 0
	cutPendingUntil = 0
	if msg.Phase == "Entered" and typeof(msg.SeatKind) == "string" then
		Panel.show(msg.SeatKind)
	elseif msg.Phase == "Left" and typeof(msg.SeatKind) == "string" then
		Panel.hide(msg.SeatKind)
	end
end)

player.CharacterAdded:Connect(function()
	Panel.hide(nil)
	pendingUntil = 0
end)

-- ── door swings (presentation; the server's door is already at its end state) ─────────────────────────────────────

local doors: { [Model]: any } = {}
local function watchDoor(vehicle: Model)
	local door = vehicle:FindFirstChild("DriverDoor", true) :: Model?
	if not door or doors[vehicle] then
		return
	end
	local rec = { Door = door, Open = vehicle:GetAttribute("DriverDoor") == "Open", From = 0, To = 0, T0 = 0, Dur = 0, Ease = "InOut" }
	rec.From = if rec.Open then 1 else 0
	rec.To = rec.From
	doors[vehicle] = rec
	vehicle:GetAttributeChangedSignal("DriverDoor"):Connect(function()
		local open = vehicle:GetAttribute("DriverDoor") == "Open"
		if open == rec.Open then
			return
		end
		rec.Open = open
		local by = vehicle:GetAttribute("DriverDoorBy")
		local D = Config.Door
		local key = (if open then "Open" else "Close") .. (if by == "Inside" then "Inside" else "Outside")
		rec.Dur = (D :: any)[key .. "Seconds"]
		rec.Ease = (D :: any)[key .. "Ease"]
		rec.From, rec.To, rec.T0 = 1 - (if open then 1 else 0), if open then 1 else 0, os.clock()
	end)
end
for _, d in workspace:GetDescendants() do
	if d:IsA("Model") and d:GetAttribute("Vehicle") ~= nil then
		watchDoor(d)
	end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(function()
			if d:GetAttribute("Vehicle") ~= nil then
				watchDoor(d)
			end
		end)
	end
end)
RunService.RenderStepped:Connect(function() -- before rendering, so the server's end-state door never shows for a frame
	local now = os.clock()
	for _, rec in doors do
		if rec.T0 > 0 then
			local u = if rec.Dur > 0 then math.clamp((now - rec.T0) / rec.Dur, 0, 1) else 1
			local e = if rec.Ease == "Out" then 1 - (1 - u) ^ 3 else u * u * (3 - 2 * u) -- [MEASURED easing]
			local f = rec.From + (rec.To - rec.From) * e
			local closed = rec.Door:GetAttribute("ClosedPivot") :: CFrame
			local deg = (rec.Door:GetAttribute("OpenDeg") :: number?) or Config.Door.OpenDeg
			rec.Door:PivotTo(closed * CFrame.Angles(0, math.rad(deg) * f, 0))
			if u >= 1 then
				rec.T0 = 0
			end
		end
	end
end)

-- ── Studio-only test hook ─────────────────────────────────────────────────────────────────────────────────────────

if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "VehicleClientDebug"
	hook.OnInvoke = function(cmd: string, arg: any): any
		if cmd == "view" then
			local texts = {}
			for _, o in current.Options do
				table.insert(texts, o.Text)
			end
			return { Target = current.Part and current.Part:GetFullName(), Options = texts, Active = active,
				Widget = Widget.read(), Panel = Panel.read(), Seat = SeatView.seat() and SeatView.seat().Id,
				Stowed = SeatView.weaponsStowed(), Eye = SeatView.eye(), Arms = DriverArms.read(), Body = SeatBody.read(),
				Camera = workspace.CurrentCamera.CFrame, Fov = workspace.CurrentCamera.FieldOfView,
				Door = (function()
					for v, rec in doors do
						return { Open = rec.Open, Moving = rec.T0 > 0, Pivot = rec.Door:GetPivot(),
							Closed = rec.Door:GetAttribute("ClosedPivot"), Vehicle = v.Name }
					end
					return nil
				end)() }
		elseif cmd == "press" then
			return press()
		elseif cmd == "switch" then
			if #current.Options == 2 then
				active = 3 - active
			end
			return active
		elseif cmd == "send" then
			-- a raw request (security tests): arg = { model, action, part, seat }
			Command:FireServer("Interact", arg[1], arg[2], arg[3], arg[4], arg[5], arg[6])
			return true
		elseif cmd == "raise" then
			SeatView.raise()
			return true
		elseif cmd == "messages" then
			return messages
		elseif cmd == "sent" then
			return sent
		elseif cmd == "clear" then
			table.clear(messages)
			table.clear(sent)
			return true
		end
		return nil
	end
	hook.Parent = script
end
