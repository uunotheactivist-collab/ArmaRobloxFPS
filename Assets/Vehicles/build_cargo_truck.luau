-- build_cargo_truck.luau — builds the cargo truck of truck.mp4 from Roblox parts (truck slice, 2026-11-08).
-- Run in Studio's Edit datamodel (execute_luau / command bar). It replaces Workspace.Vehicles.CargoTruck.
-- No Blender asset, no upload: every part is a stock Part / Cylinder.
--
-- Evidence: ReferenceAnalysis/Truck/Truck_Analysis.md §V (MEASURED with the floor grid of the reference, tools in
-- ReferenceAnalysis/Truck/tools). Every number below is in REFERENCE studs and is multiplied by K when built:
--   K = 4.05 / 4.65. The reference's on-foot eye is 4.65 studs on the same stock-floor scale that gave this project's
--   accepted eye height of 4.05 (other clips). The truck is built at the measured size RELATIVE TO THE PLAYER'S EYE, so
--   the player sees it as in the footage (ratios to the eye don't depend on the floor-scale assumption).
-- Local frame: origin on the ground under the front axle's centre; x = truck right (passenger side), y up, z rearward.
-- Model attributes, target parts, seats and test spots follow Server.Vehicles.VehicleServer's conventions.

local K = 4.05 / 4.65
local ORIGIN = CFrame.new(150, 0, 250) -- replaced below by the ground height at that spot; truck forward = −Z

local TAN = Color3.fromRGB(190, 166, 122)
local TAN_DARK = Color3.fromRGB(150, 131, 96)
local DARK = Color3.fromRGB(62, 60, 54)
local RUBBER = Color3.fromRGB(32, 32, 32)
local CREAM = Color3.fromRGB(224, 214, 188)
local SEAT = Color3.fromRGB(98, 118, 128)
local WHEEL_GREEN = Color3.fromRGB(48, 100, 84)
local WHITE = Color3.fromRGB(235, 235, 230)
local RED = Color3.fromRGB(190, 35, 28)
local BLACK = Color3.fromRGB(22, 22, 22)

local function build(parent: Instance, at: CFrame): Model
	local truck = Instance.new("Model")
	truck.Name = "CargoTruck"
	local count = 0

	-- a part: size and position in reference studs, truck-local; opts: rot, shape, collide, query, target, mat, parent,
	-- transparency, attrs
	local function P(name: string, size: Vector3, pos: Vector3, color: Color3, opts: any?): BasePart
		local o = opts or {}
		local p = Instance.new("Part")
		p.Name = name
		if o.shape then
			p.Shape = o.shape
		end
		p.Size = size * K
		p.CFrame = at * CFrame.new(pos * K) * (o.rot or CFrame.identity)
		p.Color = color
		p.Material = o.mat or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanTouch = false
		p.CanCollide = o.collide ~= false
		-- structure and targets can be hit by the prompt / line-of-sight rays; trim and decoration can't
		p.CanQuery = if o.query ~= nil then o.query else (o.collide ~= false or o.target ~= nil)
		if o.target then
			p.CanQuery = true
			p:SetAttribute("VehicleTarget", o.target)
		end
		if o.transparency then
			p.Transparency = o.transparency
		end
		if o.attrs then
			for k, v in o.attrs do
				p:SetAttribute(k, v)
			end
		end
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = o.parent or truck
		count += 1
		return p
	end

	-- a block from a to b (reference studs), thickness t
	local function Bar(name: string, a: Vector3, b: Vector3, t: number, color: Color3, opts: any?): BasePart
		local o = opts or {}
		local len = (b - a).Magnitude
		local mid = (a + b) / 2
		local look = CFrame.lookAt(mid, b)
		o.rot = look.Rotation
		local p = P(name, Vector3.new(t, t, len), Vector3.zero, color, o)
		p.CFrame = at * CFrame.new(mid * K) * look.Rotation
		return p
	end

	-- an attachment on `part` at a truck-local point (reference studs), facing `dir` (truck-local, horizontal)
	local function A(part: BasePart, name: string, pos: Vector3, dir: Vector3)
		local a = Instance.new("Attachment")
		a.Name = name
		local world = at * CFrame.lookAt(pos * K, pos * K + dir)
		a.CFrame = part.CFrame:ToObjectSpace(world)
		a.Parent = part
		return a
	end

	local AXIS_Z = CFrame.Angles(0, math.rad(90), 0) -- a cylinder (axis X) turned to lie along Z
	local AXIS_Y = CFrame.Angles(0, 0, math.rad(90)) -- … to stand along Y
	local CYL = Enum.PartType.Cylinder

	-- ── running gear [MEASURED: tyre Ø 3.66, axles 0 / 11.4 / 15.3, 7.9 over the front tyres; width INFERRED] ──────
	local TYRE_D, TYRE_W, R = 3.66, 2.2, 1.83
	local WX = 7.9 / 2 - TYRE_W / 2
	for i, z in { 0, 11.4, 15.3 } do
		P("Axle" .. i, Vector3.new(6.0, 0.35, 0.35), Vector3.new(0, R, z), DARK, { collide = false })
		for _, s in { -1, 1 } do
			local side = if s < 0 then "L" else "R"
			P("Tyre" .. i .. side, Vector3.new(TYRE_W, TYRE_D, TYRE_D), Vector3.new(s * WX, R, z), RUBBER,
				{ shape = CYL, mat = Enum.Material.Rubber })
			P("Rim" .. i .. side, Vector3.new(0.2, 1.75, 1.75), Vector3.new(s * (WX + TYRE_W / 2 + 0.02), R, z), TAN_DARK,
				{ shape = CYL, collide = false })
			P("Hub" .. i .. side, Vector3.new(0.35, 0.6, 0.6), Vector3.new(s * (WX + TYRE_W / 2 + 0.12), R, z), DARK,
				{ shape = CYL, collide = false })
		end
	end
	for _, s in { -1, 1 } do
		P("FrameRail" .. (if s < 0 then "L" else "R"), Vector3.new(0.5, 0.7, 20.6), Vector3.new(s * 1.6, 2.75, 7.25), DARK)
		P("Tandem" .. (if s < 0 then "L" else "R"), Vector3.new(0.6, 0.6, 4.6), Vector3.new(s * 1.6, 2.2, 13.35), DARK,
			{ collide = false })
		P("MudFlap" .. (if s < 0 then "L" else "R"), Vector3.new(2.0, 1.2, 0.08), Vector3.new(s * WX, 1.4, 17.35), BLACK,
			{ collide = false })
	end

	-- ── front: bumper [MEASURED 2.3–2.8 / 3.4–3.7, width 8.0–8.9], flat hood [front top 6.1–6.5], grille [top 5.7–6.0,
	-- width 4.7–6.0], two round lamps [centre 4.54, spacing 3.8–4.9], flat fenders [top 4.56] ───────────────────────────
	P("FrontBumper", Vector3.new(8.5, 1.0, 0.55), Vector3.new(0, 3.05, -2.97), TAN)
	P("Engine", Vector3.new(3.8, 1.6, 4.0), Vector3.new(0, 3.4, -0.6), DARK)
	local hood = P("Hood", Vector3.new(5.4, 2.3, 4.6), Vector3.new(0, 5.15, -0.3), TAN)
	P("Grille", Vector3.new(4.4, 1.9, 0.12), Vector3.new(0, 5.05, -2.64), TAN_DARK, { collide = false })
	for i = 0, 6 do
		P("GrilleBar" .. i, Vector3.new(0.16, 1.75, 0.1), Vector3.new(-1.8 + i * 0.6, 5.05, -2.71), DARK, { collide = false })
	end
	for _, s in { -1, 1 } do
		local side = if s < 0 then "L" else "R"
		P("HeadlampRim" .. side, Vector3.new(0.14, 1.15, 1.15), Vector3.new(s * 2.2, 4.54, -2.66), DARK,
			{ shape = CYL, rot = AXIS_Z, collide = false })
		P("Headlamp" .. side, Vector3.new(0.14, 0.9, 0.9), Vector3.new(s * 2.2, 4.54, -2.72), Color3.fromRGB(212, 208, 186),
			{ shape = CYL, rot = AXIS_Z, collide = false })
		P("Fender" .. side, Vector3.new(2.7, 0.18, 4.8), Vector3.new(s * WX, 4.47, -0.2), TAN)
		P("FenderLip" .. side, Vector3.new(2.7, 0.7, 0.18), Vector3.new(s * WX, 4.15, -2.55), TAN, { collide = false })
		P("FenderSkirt" .. side, Vector3.new(0.15, 0.8, 4.8), Vector3.new(s * (WX + 1.33), 4.1, -0.2), TAN,
			{ collide = false })
	end
	-- stencils on the hood sides [CONFIRMED look: USMC stencils]
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.CanvasSize = Vector2.new(400, 170)
		g.LightInfluence = 1
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(0.6, 0.3)
		t.Position = UDim2.fromScale(0.2, 0.3)
		t.Font = Enum.Font.Arimo
		t.TextScaled = true
		t.TextColor3 = BLACK
		t.Text = "USMC"
		t.Parent = g
		g.Parent = hood
	end

	-- ── cab [roof 7.6–8.3 MEASURED, ≥ 8 to fit the driver view; door 3.2–3.5 × 2.2–2.4, height / width 1.45, window the
	-- top ≈ 37 % × 75 %, no glass, hinged at the front edge, MEASURED / INFERRED] ──────────────────────────────────────
	local CAB_Z0, CAB_Z1, FLOOR, ROOF = 2.0, 5.7, 4.5, 8.3
	local zc, zl = (CAB_Z0 + CAB_Z1) / 2, CAB_Z1 - CAB_Z0
	P("CabFloor", Vector3.new(7.0, 0.25, zl), Vector3.new(0, FLOOR - 0.125, zc), DARK)
	P("Cowl", Vector3.new(7.0, 1.9, 0.2), Vector3.new(0, FLOOR + 0.95, CAB_Z0 + 0.1), TAN)
	P("WindshieldTop", Vector3.new(7.0, 0.25, 0.25), Vector3.new(0, 8.15, CAB_Z0 + 0.1), TAN)
	for i, x in { -3.38, 0, 3.38 } do
		P("WindshieldPost" .. i, Vector3.new(0.25, 1.65, 0.25), Vector3.new(x, 7.225, CAB_Z0 + 0.1), TAN)
	end
	for _, s in { -1, 1 } do
		P("Windshield" .. (if s < 0 then "L" else "R"), Vector3.new(3.1, 1.6, 0.05), Vector3.new(s * 1.69, 7.2, CAB_Z0 + 0.12),
			Color3.fromRGB(170, 185, 190), { transparency = 0.88, query = false, mat = Enum.Material.Glass })
	end
	P("Roof", Vector3.new(7.3, 0.2, zl + 0.25), Vector3.new(0, ROOF - 0.1, zc), TAN)
	P("CabRear", Vector3.new(7.0, ROOF - FLOOR, 0.2), Vector3.new(0, (ROOF + FLOOR) / 2, CAB_Z1 - 0.1), TAN)
	local DOOR_Z0, DOOR_Z1, DOOR_TOP = 2.6, 4.9, 7.8
	local doorH, doorW = DOOR_TOP - FLOOR, DOOR_Z1 - DOOR_Z0
	local lowerH = doorH * 0.63
	local winH = doorH - lowerH - 0.15
	local postW = doorW * 0.125
	for _, s in { -1, 1 } do
		local side = if s < 0 then "L" else "R"
		local x = s * 3.4
		P("CabFront" .. side, Vector3.new(0.2, ROOF - FLOOR, DOOR_Z0 - CAB_Z0), Vector3.new(x, (ROOF + FLOOR) / 2,
			(CAB_Z0 + DOOR_Z0) / 2), TAN)
		P("CabBack" .. side, Vector3.new(0.2, ROOF - FLOOR, CAB_Z1 - DOOR_Z1), Vector3.new(x, (ROOF + FLOOR) / 2,
			(DOOR_Z1 + CAB_Z1) / 2), TAN)
		P("DoorHeader" .. side, Vector3.new(0.2, ROOF - DOOR_TOP, doorW), Vector3.new(x, (ROOF + DOOR_TOP) / 2,
			(DOOR_Z0 + DOOR_Z1) / 2), TAN)
	end

	-- the doors: the driver's is a Model pivoting on its front edge; the passenger's is fixed (never opened)
	local function door(side: string, parent: Instance, target: string?)
		local s = if side == "L" then -1 else 1
		local x = s * 3.42
		local zm = (DOOR_Z0 + DOOR_Z1) / 2
		local opts = function(extra: any?)
			local o = { parent = parent, target = target, attrs = if target then { ExitSide = "L" } else nil }
			if extra then
				for k, v in extra do
					o[k] = v
				end
			end
			return o
		end
		local panel = P(if target then "DriverDoorPanel" else "PassengerDoorPanel", Vector3.new(0.2, lowerH, doorW),
			Vector3.new(x, FLOOR + lowerH / 2, zm), TAN, opts())
		P("DoorWindowTop" .. side, Vector3.new(0.2, 0.15, doorW), Vector3.new(x, DOOR_TOP - 0.075, zm), TAN, opts())
		P("DoorWindowFront" .. side, Vector3.new(0.2, winH, postW), Vector3.new(x, FLOOR + lowerH + winH / 2,
			DOOR_Z0 + postW / 2), TAN, opts())
		P("DoorWindowRear" .. side, Vector3.new(0.2, winH, postW), Vector3.new(x, FLOOR + lowerH + winH / 2,
			DOOR_Z1 - postW / 2), TAN, opts())
		-- the white Λ on the outside [CONFIRMED look]
		for _, a in { -1, 1 } do
			P("Chevron" .. side .. (if a < 0 then "a" else "b"), Vector3.new(0.04, 1.1, 0.13),
				Vector3.new(x + s * 0.12, FLOOR + 1.05, zm + a * 0.23), WHITE,
				{ parent = parent, collide = false, rot = CFrame.Angles(math.rad(-a * 24), 0, 0) }) -- tops meet: Λ
		end
		P("HandleOut" .. side, Vector3.new(0.08, 0.15, 0.45), Vector3.new(x + s * 0.14, FLOOR + lowerH - 0.35,
			DOOR_Z1 - 0.45), DARK, { parent = parent, collide = false })
		if target then
			A(panel, "DoorHandleInside", Vector3.new(x - s * 0.15, FLOOR + lowerH - 0.4, DOOR_Z1 - 0.45), Vector3.new(0, 0, -1))
			P("HandleIn", Vector3.new(0.08, 0.15, 0.45), Vector3.new(x - s * 0.14, FLOOR + lowerH - 0.4, DOOR_Z1 - 0.45),
				DARK, { parent = parent, collide = false })
		end
		return panel
	end
	local driverDoor = Instance.new("Model")
	driverDoor.Name = "DriverDoor"
	driverDoor.Parent = truck
	door("L", driverDoor, "DriverDoor")
	local hinge = at * CFrame.new(Vector3.new(-3.42, FLOOR + doorH / 2, DOOR_Z0) * K)
	driverDoor.WorldPivot = hinge
	driverDoor:SetAttribute("ClosedPivot", hinge)
	driverDoor:SetAttribute("OpenDeg", -82) -- outward (to −x) about the front-edge hinge [INFERRED 75–90°]
	local passengerDoor = Instance.new("Model")
	passengerDoor.Name = "PassengerDoor"
	passengerDoor.Parent = truck
	door("R", passengerDoor, nil)

	-- ── cab interior: cream dash with gauges, the green 3-spoke wheel, key switch, white T-lever, black parking-brake
	-- lever, two red dome lamps, blue-grey seats [CONFIRMED look; positions INFERRED from the driver view] ───────────
	P("Dash", Vector3.new(6.6, 1.0, 0.8), Vector3.new(0, 6.0, 2.6), CREAM, { collide = false, query = true })
	for i, x in { -2.75, -2.25, -1.25, 1.2, 1.8 } do
		P("Gauge" .. i, Vector3.new(0.06, 0.38, 0.38), Vector3.new(x, 6.2, 3.02), BLACK,
			{ shape = CYL, rot = AXIS_Z, collide = false })
	end
	P("KeySwitch", Vector3.new(0.42, 0.42, 0.14), Vector3.new(-0.75, 5.85, 3.06), BLACK,
		{ collide = false, target = "KeySwitch" })
	P("LightsSwitch", Vector3.new(0.5, 0.45, 0.1), Vector3.new(-0.15, 6.2, 3.04), CREAM,
		{ collide = false, target = "LightsSwitch" })
	P("LightsLeverStem", Vector3.new(0.1, 0.1, 0.32), Vector3.new(-0.15, 6.2, 3.2), WHITE,
		{ collide = false, target = "LightsSwitch" })
	P("LightsLeverBar", Vector3.new(0.45, 0.1, 0.1), Vector3.new(-0.15, 6.2, 3.36), WHITE,
		{ collide = false, target = "LightsSwitch" })
	P("ParkingBrakeBase", Vector3.new(0.3, 0.2, 0.45), Vector3.new(-0.9, FLOOR + 0.1, 3.35), BLACK, { collide = false })
	Bar("ParkingBrake", Vector3.new(-0.9, FLOOR + 0.15, 3.35), Vector3.new(-0.9, 5.3, 3.6), 0.13, BLACK,
		{ collide = false, target = "ParkingBrake" })
	P("ParkingBrakeKnob", Vector3.new(0.26, 0.26, 0.26), Vector3.new(-0.9, 5.33, 3.61), BLACK,
		{ collide = false, target = "ParkingBrake" })
	for _, s in { -1, 1 } do
		P("DomeLamp" .. (if s < 0 then "L" else "R"), Vector3.new(0.1, 0.3, 0.3), Vector3.new(s * 1.0, ROOF - 0.25, 4.4), RED,
			{ shape = CYL, rot = AXIS_Y, collide = false })
	end

	-- steering wheel: Ø ≈ 0.93 × its distance from the eye [MEASURED angle 50°]; tilt UNKNOWN → faces the eye
	local EYE_D = Vector3.new(-2.0, 7.5, 4.15)
	local W = EYE_D + Vector3.new(0, -1.0, -1.0)
	local n = (EYE_D - W).Unit
	local u = Vector3.new(1, 0, 0)
	local v = n:Cross(u).Unit
	if v.Y < 0 then
		v = -v
	end
	local RADIUS = 0.93 * (EYE_D - W).Magnitude / 2
	local wheelModel = Instance.new("Model")
	wheelModel.Name = "SteeringWheelModel"
	wheelModel.Parent = truck
	local function rimPoint(deg: number): Vector3
		local a = math.rad(deg)
		return W + (u * math.cos(a) + v * math.sin(a)) * RADIUS
	end
	for i = 0, 15 do
		Bar("Rim" .. i, rimPoint(i * 22.5), rimPoint((i + 1) * 22.5), 0.16, WHEEL_GREEN,
			{ collide = false, query = false, parent = wheelModel })
	end
	for i, deg in { 0, 180, 270 } do
		Bar("Spoke" .. i, W, rimPoint(deg), 0.1, WHEEL_GREEN, { collide = false, query = false, parent = wheelModel })
	end
	local hub = P("SteeringWheel", Vector3.new(0.18, 0.42, 0.42), Vector3.zero, WHEEL_GREEN,
		{ shape = CYL, collide = false, query = false, parent = wheelModel })
	hub.CFrame = at * CFrame.lookAt(W * K, (W + n) * K) * AXIS_Z
	A(hub, "GripL", rimPoint(165), n) -- left hand at 9–10 o'clock [MEASURED]
	A(hub, "GripR", rimPoint(45), n) -- right hand at 1–2 o'clock [MEASURED]
	Bar("SteeringColumn", W - n * 0.1, Vector3.new(-2.0, 6.0, 2.75), 0.16, DARK,
		{ collide = false, query = false, parent = wheelModel })

	-- seats: driver (registered), passenger (offered, never entered: NotBuilt)
	local driverSeat = P("DriverSeat", Vector3.new(1.9, 0.5, 1.7), Vector3.new(-2.0, 4.95, 4.65), SEAT,
		{ collide = false, target = "DriverSeat", attrs = { SeatId = "Driver", SeatKind = "Driver" } })
	P("DriverSeatBack", Vector3.new(1.9, 2.0, 0.3), Vector3.new(-2.0, 6.3, 5.35), SEAT,
		{ collide = false, target = "DriverSeat" })
	A(driverSeat, "Hip", Vector3.new(-2.0, 5.2 + 1.15, 4.75), Vector3.new(0, 0, -1))
	A(driverSeat, "Eye", EYE_D, Vector3.new(0, 0, -1)) -- [MEASURED ≈ 7.7 (7.5–8.2), 1.6–2.4 left of centre]
	A(driverSeat, "ExitL", Vector3.new(-(7.9 / 2 + 1.7), 0, 4.8), Vector3.new(0, 0, -1)) -- [MEASURED at 1508]
	A(driverSeat, "Feet", Vector3.new(-2.0, FLOOR + 0.15, 2.55), Vector3.new(0, 0, -1)) -- under the dash (SeatBody)
	P("PassengerSeat", Vector3.new(1.9, 0.5, 1.7), Vector3.new(2.0, 4.95, 4.65), SEAT,
		{ collide = false, target = "PassengerSeat" })
	P("PassengerSeatBack", Vector3.new(1.9, 2.0, 0.3), Vector3.new(2.0, 6.3, 5.35), SEAT,
		{ collide = false, target = "PassengerSeat" })

	-- mirrors [MEASURED top ≈ 7.0–8.0, bottom ≈ 6.5], exhaust and spare tyre behind the cab on the left [CONFIRMED look],
	-- fuel tank "DIESEL OR JP-8 ONLY" [CONFIRMED look], step box
	for _, s in { -1, 1 } do
		local side = if s < 0 then "L" else "R"
		P("Mirror" .. side, Vector3.new(0.12, 1.3, 0.75), Vector3.new(s * 4.45, 7.15, 2.0), DARK, { collide = false })
		P("MirrorArmTop" .. side, Vector3.new(1.0, 0.08, 0.08), Vector3.new(s * 3.95, 7.6, 2.0), DARK, { collide = false })
		P("MirrorArmLow" .. side, Vector3.new(1.0, 0.08, 0.08), Vector3.new(s * 3.95, 6.7, 2.0), DARK, { collide = false })
	end
	P("Exhaust", Vector3.new(4.8, 0.45, 0.45), Vector3.new(-3.25, 6.6, 5.95), DARK, { shape = CYL, rot = AXIS_Y })
	P("SpareTyre", Vector3.new(1.2, 3.4, 3.4), Vector3.new(-1.3, 6.0, 6.35), RUBBER,
		{ shape = CYL, rot = AXIS_Z, mat = Enum.Material.Rubber })
	P("SpareRim", Vector3.new(1.25, 1.5, 1.5), Vector3.new(-1.3, 6.0, 6.35), TAN_DARK,
		{ shape = CYL, rot = AXIS_Z, collide = false })
	P("SpareBracket", Vector3.new(0.3, 3.9, 0.3), Vector3.new(-3.15, 5.15, 6.35), TAN)
	Bar("SpareDavit", Vector3.new(-3.15, 7.1, 6.35), Vector3.new(-1.3, 7.9, 6.35), 0.18, TAN, { collide = false })
	local tank = P("FuelTank", Vector3.new(1.3, 1.3, 2.4), Vector3.new(3.0, 3.3, 3.75), TAN)
	do
		local g = Instance.new("SurfaceGui")
		g.Face = Enum.NormalId.Right
		g.CanvasSize = Vector2.new(240, 130)
		g.LightInfluence = 1
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(0.9, 0.3)
		t.Position = UDim2.fromScale(0.05, 0.35)
		t.Font = Enum.Font.Arimo
		t.TextScaled = true
		t.TextColor3 = BLACK
		t.Text = "DIESEL OR JP-8 ONLY"
		t.Parent = g
		g.Parent = tank
	end
	P("StepBox", Vector3.new(1.0, 0.9, 1.4), Vector3.new(-3.2, 3.35, 3.75), TAN)

	-- ── cargo bed [floor 4.3 INFERRED from the sill MEASURED; side rack middle rail 5.45, top 6.6 MEASURED; rear end of
	-- the rack 2.45 behind the rear axle MEASURED; tailgate top ≈ 5.5 INFERRED; length ≈ 12 INFERRED → built 10.75 so the
	-- spare tyre fits behind the cab; inner width ≈ 7–7.8 INFERRED] ────────────────────────────────────────────────────
	local BED_Z0, BED_Z1, BED_FLOOR, RACK_TOP = 7.0, 15.3 + 2.45, 4.3, 6.6
	local bz, bl = (BED_Z0 + BED_Z1) / 2, BED_Z1 - BED_Z0
	P("BedFloor", Vector3.new(7.6, 0.3, bl), Vector3.new(0, BED_FLOOR - 0.15, bz), TAN)
	for _, s in { -1, 1 } do
		P("Sill" .. (if s < 0 then "L" else "R"), Vector3.new(0.3, 0.35, bl), Vector3.new(s * 3.6, BED_FLOOR - 0.45, bz), TAN_DARK)
	end
	for i, z in { 8.0, 10.5, 13.0, 15.5, 17.4 } do
		P("CrossSill" .. i, Vector3.new(7.2, 0.25, 0.3), Vector3.new(0, BED_FLOOR - 0.43, z), TAN_DARK, { collide = false })
	end
	for _, s in { -1, 1 } do
		local side = if s < 0 then "L" else "R"
		local o = { target = "BedSide", attrs = { ExitSide = side } }
		P("BedSide" .. side, Vector3.new(0.2, 0.7, bl), Vector3.new(s * 3.7, BED_FLOOR + 0.35, bz), TAN, o)
		P("BedRailMid" .. side, Vector3.new(0.2, 0.2, bl), Vector3.new(s * 3.7, 5.35, bz), TAN, o)
		P("BedRailTop" .. side, Vector3.new(0.2, 0.2, bl), Vector3.new(s * 3.7, RACK_TOP - 0.1, bz), TAN, o)
		for i = 0, 7 do
			local z = BED_Z0 + 0.1 + i * (bl - 0.2) / 7
			P("BedPost" .. side .. i, Vector3.new(0.2, RACK_TOP - BED_FLOOR, 0.2), Vector3.new(s * 3.7,
				(RACK_TOP + BED_FLOOR) / 2, z), TAN, o)
		end
	end
	P("Headboard", Vector3.new(7.6, 0.7, 0.2), Vector3.new(0, BED_FLOOR + 0.35, BED_Z0 + 0.1), TAN)
	P("HeadRailMid", Vector3.new(7.6, 0.2, 0.2), Vector3.new(0, 5.35, BED_Z0 + 0.1), TAN)
	P("HeadRailTop", Vector3.new(7.6, 0.2, 0.2), Vector3.new(0, RACK_TOP - 0.1, BED_Z0 + 0.1), TAN)
	for i, x in { -1.25, 1.25 } do
		P("HeadPost" .. i, Vector3.new(0.2, RACK_TOP - BED_FLOOR, 0.2), Vector3.new(x, (RACK_TOP + BED_FLOOR) / 2,
			BED_Z0 + 0.1), TAN)
	end
	P("Tailgate", Vector3.new(7.2, 1.2, 0.2), Vector3.new(0, BED_FLOOR + 0.6, BED_Z1 - 0.1), TAN,
		{ target = "Tailgate", attrs = { ExitSide = "Rear" } })
	P("RearBumper", Vector3.new(7.4, 0.45, 0.35), Vector3.new(0, 3.0, BED_Z1 - 0.05), TAN_DARK)
	for _, s in { -1, 1 } do
		P("TailLamp" .. (if s < 0 then "L" else "R"), Vector3.new(0.15, 0.55, 0.55), Vector3.new(s * 3.0, 3.6, BED_Z1 + 0.05),
			RED, { shape = CYL, rot = AXIS_Z, collide = false })
	end

	-- benches facing inward along both sides [CONFIRMED look]; seats [MEASURED rough, Truck_Analysis §2a]:
	--   Back1 front of the bed, left of centre, facing forward (entry, 105)   Back2 right bench 3.5 behind the front (264)
	--   Back3 right bench 2.8 ahead of the rear (325)   Back4 left bench 3.3 ahead of the rear (408)
	--   Back5 right bench 1.5 ahead of the rear, rear-most (529). Eye 8.75 above the ground [MEASURED at Back4], the same
	--   on every bench seat [INFERRED]; eye ≈ 0.9 in from the near rack [INFERRED from the far-rack distance 6.3].
	local BENCH_TOP, BENCH_IN, BENCH_OUT = 6.2, 2.2, 3.6
	local EYE_BED = 8.75
	local benchX = (BENCH_IN + BENCH_OUT) / 2
	local seats = {
		{ Id = "Back2", s = 1, z = BED_Z0 + 3.5 },
		{ Id = "Back3", s = 1, z = BED_Z1 - 0.2 - 2.8 },
		{ Id = "Back4", s = -1, z = BED_Z1 - 0.2 - 3.3 },
		{ Id = "Back5", s = 1, z = BED_Z1 - 0.2 - 1.5 },
	}
	local SEAT_L = 1.2
	local function addExits(seat: BasePart, x: number, z: number)
		A(seat, "ExitL", Vector3.new(-5.4, 0, z), Vector3.new(-1, 0, 0))
		A(seat, "ExitR", Vector3.new(5.4, 0, z), Vector3.new(1, 0, 0))
		A(seat, "ExitRear", Vector3.new(if x < 0 then -1.5 else 1.5, 0, BED_Z1 + 1.85), Vector3.new(0, 0, 1))
	end
	for _, s in { -1, 1 } do
		local side = if s < 0 then "L" else "R"
		-- bench boards between the seats (plain), the bench front
		local cuts = {}
		for _, st in seats do
			if st.s == s then
				table.insert(cuts, st.z)
			end
		end
		table.sort(cuts)
		local z0 = BED_Z0 + 0.4
		local pieces = 0
		for _, zc2 in cuts do
			local a, b = z0, zc2 - SEAT_L / 2
			if b - a > 0.05 then
				pieces += 1
				P("Bench" .. side .. pieces, Vector3.new(BENCH_OUT - BENCH_IN, 0.25, b - a),
					Vector3.new(s * benchX, BENCH_TOP - 0.125, (a + b) / 2), TAN_DARK)
			end
			z0 = zc2 + SEAT_L / 2
		end
		local zEnd = BED_Z1 - 0.4
		if zEnd - z0 > 0.05 then
			pieces += 1
			P("Bench" .. side .. pieces, Vector3.new(BENCH_OUT - BENCH_IN, 0.25, zEnd - z0),
				Vector3.new(s * benchX, BENCH_TOP - 0.125, (z0 + zEnd) / 2), TAN_DARK)
		end
		P("BenchFront" .. side, Vector3.new(0.12, BENCH_TOP - 0.25 - BED_FLOOR, BED_Z1 - BED_Z0 - 0.8),
			Vector3.new(s * (BENCH_IN + 0.06), (BENCH_TOP - 0.25 + BED_FLOOR) / 2, bz), TAN_DARK)
	end
	for _, st in seats do
		local x = st.s * benchX
		local part = P(st.Id, Vector3.new(BENCH_OUT - BENCH_IN, 0.25, SEAT_L - 0.04), Vector3.new(x, BENCH_TOP - 0.12, st.z),
			TAN_DARK, { target = "BackSeat", attrs = { SeatId = st.Id, SeatKind = "Back" } })
		local inward = Vector3.new(-st.s, 0, 0)
		A(part, "Hip", Vector3.new(st.s * 2.95, BENCH_TOP + 1.15, st.z), inward)
		A(part, "Eye", Vector3.new(st.s * 2.7, EYE_BED, st.z), inward)
		addExits(part, x, st.z)
	end
	-- Back1: a forward-facing seat at the front of the bed, left of centre
	local b1z = BED_Z0 + 2.3
	P("Back1Base", Vector3.new(1.4, BENCH_TOP - 0.25 - BED_FLOOR, 1.1), Vector3.new(-1.2, (BENCH_TOP - 0.25 + BED_FLOOR) / 2,
		b1z), TAN_DARK)
	local back1 = P("Back1", Vector3.new(1.6, 0.25, 1.3), Vector3.new(-1.2, BENCH_TOP - 0.12, b1z), TAN_DARK,
		{ target = "BackSeat", attrs = { SeatId = "Back1", SeatKind = "Back" } })
	P("Back1Rest", Vector3.new(1.6, 1.2, 0.2), Vector3.new(-1.2, BENCH_TOP + 0.6, b1z + 0.75), TAN_DARK)
	A(back1, "Hip", Vector3.new(-1.2, BENCH_TOP + 1.15, b1z + 0.1), Vector3.new(0, 0, -1))
	A(back1, "Eye", Vector3.new(-1.2, EYE_BED, b1z - 0.2), Vector3.new(0, 0, -1))
	addExits(back1, -1.2, b1z)

	-- ── test spots (Roblox/Tests/Truck): where the client test stands the player (ground points, facing) ─────────────
	local spots = P("TestSpots", Vector3.new(1, 0.05, 1), Vector3.new(0, 0.025, 8), TAN,
		{ collide = false, query = false, transparency = 1 })
	A(spots, "TestSpot_Tailgate", Vector3.new(0, 0, BED_Z1 + 2.55), Vector3.new(0, 0, -1))
	A(spots, "TestSpot_DriverDoor", Vector3.new(-5.6, 0, 3.6), Vector3.new(1, 0, 0))
	A(spots, "TestSpot_Far", Vector3.new(-18, 0, 3.6), Vector3.new(1, 0, 0))
	A(spots, "TestSpot_PassengerSide", Vector3.new(5.6, 0, 3.6), Vector3.new(-1, 0, 0))

	truck.WorldPivot = at
	truck:SetAttribute("Vehicle", "CargoTruck")
	truck:SetAttribute("VehicleId", "TRUCK1")
	truck:SetAttribute("EntryBackSeat", "Back1")
	truck:SetAttribute("EntryDriverSeat", "Driver")
	truck:SetAttribute("BuiltBy", "Roblox/Assets/Vehicles/build_cargo_truck.luau")
	truck:SetAttribute("ScaleK", K)
	truck.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- streams in / out whole: seats, targets and spots together
	truck.Parent = parent
	return truck
end

-- ── place it ─────────────────────────────────────────────────────────────────────────────────────────────────────────
local folder = workspace:FindFirstChild("Vehicles")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = workspace
end
local old = folder:FindFirstChild("CargoTruck")
if old then
	old:Destroy()
end
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { folder }
local hit = workspace:Raycast(ORIGIN.Position + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0), params)
local at = if hit then CFrame.new(ORIGIN.Position.X, hit.Position.Y, ORIGIN.Position.Z) else ORIGIN
local t = build(folder, at)
local n = 0
for _, d in t:GetDescendants() do
	if d:IsA("BasePart") then
		n += 1
	end
end
return { parts = n, ground = hit and hit.Position.Y, ground_part = hit and hit.Instance:GetFullName(), size = t:GetExtentsSize(),
	pivot = t:GetPivot().Position }
