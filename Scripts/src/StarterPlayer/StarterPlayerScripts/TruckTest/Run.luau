--!strict
-- Truck test, client side (Studio only; delete the TruckTest folders to remove it). Driven through execute_luau (Client
-- datamodel); the server half is ServerScriptService.TruckTest.Run. It drives the real client: it stands the player at
-- one of the truck's TestSpot attachments, turns the camera to a target part, presses F through VehicleClientDebug and
-- reads what the server answered. Each function returns its measurements and a pass flag.
--   Run.spawn()          the truck, its start state, its seats
--   Run.back()           enter the bed, change seats, leave (prompts, cuts, eye, yaw / kept pitch, panel, rifle down,
--                        legs and lap arms, exit side and look-down)
--   Run.screen()         the prompt's and the CONTROLS panel's pixel geometry against the reference
--   Run.driver()         door, enter, key, START, parking brake, lights, door from inside, leave (prompts, swing times,
--                        arms on the wheel / hover reach / door reach, weapon stowed, the truck never moves, W/A/S/D do
--                        nothing, exit side, facing and look-down)
--   Run.weapons()        bench seat: rifle down at idle, raised by FIRE, shots server-accepted; nothing from the driver seat
--   Run.repeated(n)      n back + n driver round trips, nothing left over
--   Run.contention()     a stand-in occupant: the seat isn't offered and a forged request for it is refused
--   Run.forged()         malformed / impossible requests (security); ends seated after a client-side teleport attempt:
--                        the server half's Run.view() then checks the server's copy; Run.forgedFinish() rate + leave
--   Run.deathInSeat(s)   "kill" stage after the server killed the player in a seat; "after" once respawned
--   Run.raw(a, part, seat?, aim?)  one raw request, for production-rule security runs (server places the player)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage.Shared.Config.Vehicles) :: any
local Remotes = ReplicatedStorage.Shared.Remotes
local client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local vHook = client:WaitForChild("Vehicles"):WaitForChild("VehicleClient"):WaitForChild("VehicleClientDebug") :: BindableFunction
local wHook = client:WaitForChild("WeaponController"):WaitForChild("ProductionWeaponDebug") :: BindableFunction
local mHook = client:WaitForChild("Movement"):WaitForChild("MovementController"):WaitForChild("MovementClientDebug") :: BindableFunction

local Run = {}
local F = 1 / 30

local function v(cmd: string, arg: any?): any
	return vHook:Invoke(cmd, arg)
end
local function w(cmd: string, arg: any?): any
	return wHook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function r2(x: number?): number?
	return if x then math.round(x * 100) / 100 else nil
end

function Run.truck(): Model
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("VehicleId") == "TRUCK1" then
			return d
		end
	end
	error("no truck")
end

local function find(name: string): Instance
	local x = Run.truck():FindFirstChild(name, true)
	assert(x, "truck has no " .. name)
	return x
end

local function seatPart(id: string): BasePart
	for _, d in Run.truck():GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("SeatId") == id then
			return d
		end
	end
	error("no seat " .. id)
end

local function character(): Model
	return player.Character or player.CharacterAdded:Wait()
end

local function root(): BasePart
	return character():WaitForChild("HumanoidRootPart") :: BasePart
end

-- stand at a TestSpot attachment (client teleport: the old suites' Studio switch must be on)
function Run.standAt(spot: string)
	local a = find("TestSpot_" .. spot) :: Attachment
	local r = root()
	r.CFrame = a.WorldCFrame + Vector3.new(0, r.Size.Y / 2 + (character():FindFirstChildOfClass("Humanoid") :: Humanoid).HipHeight, 0)
	r.AssemblyLinearVelocity = Vector3.zero
	frames(0.4)
end

-- turn the camera to a point (retries until the camera scripts hold it)
local function look(point: Vector3)
	local cam = workspace.CurrentCamera
	for _ = 1, 12 do
		local from = cam.CFrame.Position
		cam.CFrame = CFrame.lookAt(from, point)
		frames(0.08)
		if cam.CFrame.LookVector:Dot((point - cam.CFrame.Position).Unit) > 0.999 then
			break
		end
	end
	frames(0.1)
end

function Run.aimAt(name: string, offset: Vector3?): any
	local p = find(name) :: BasePart
	look(p.CFrame:PointToWorldSpace(offset or Vector3.zero))
	return v("view")
end

local function aimSeat(id: string): any
	look(seatPart(id).Position + Vector3.new(0, 0.3, 0))
	return v("view")
end

-- press F and wait for the server's answer; returns the press, the answer, its delay and the frame of the seat change
local function interact(timeout: number?): any
	v("clear")
	local c = character()
	local seat0 = c:GetAttribute("VehicleSeat")
	local t0 = os.clock()
	local pressed = v("press")
	local seatAt: number? = nil
	local msg = nil
	while os.clock() - t0 < (timeout or 1.5) do
		RunService.RenderStepped:Wait()
		if not seatAt and c:GetAttribute("VehicleSeat") ~= seat0 then
			seatAt = os.clock() - t0
		end
		local m = v("messages")
		if #m > 0 then
			msg = m[#m]
			if msg.Phase ~= "Entered" and msg.Phase ~= "Left" or seatAt then
				break
			end
		end
	end
	frames(0.1)
	return { Pressed = pressed and pressed.Text, Phase = msg and msg.Phase, Reason = msg and msg.Reason,
		Seat = c:GetAttribute("VehicleSeat"), CutFrames = seatAt and math.round(seatAt * 30) }
end

local function texts(view: any): string
	return table.concat(view.Options or {}, " | ")
end

local function panelLines(): { string }
	local out = {}
	local p = v("view").Panel
	for _, l in p.Lines do
		table.insert(out, l.Text)
	end
	return out
end

local function eyeError(): number?
	local e = v("view").Eye
	return e and (workspace.CurrentCamera.CFrame.Position - e.Position).Magnitude
end

-- the camera's yaw against the seat's facing (flat; the pitch is kept through a cut)
local function flat(v3: Vector3): Vector3
	local f = Vector3.new(v3.X, 0, v3.Z)
	return if f.Magnitude > 1e-4 then f.Unit else Vector3.zero
end
local function facingDot(id: string): number
	local eye = seatPart(id):FindFirstChild("Eye") :: Attachment
	return flat(workspace.CurrentCamera.CFrame.LookVector):Dot(flat(eye.WorldCFrame.LookVector))
end

local function pitchDeg(): number
	return math.deg(math.asin(math.clamp(workspace.CurrentCamera.CFrame.LookVector.Y, -1, 1)))
end

-- which side of the truck a point is on, in the truck's frame: "L" / "R" / "Rear" / "Front"
local function sideOf(p: Vector3): string
	local rel = Run.truck():GetPivot():PointToObjectSpace(p)
	local k = Run.truck():GetAttribute("ScaleK") :: number
	if rel.Z > 17.75 * k then
		return "Rear"
	elseif rel.Z < -3.3 * k then
		return "Front"
	end
	return if rel.X < 0 then "L" else "R"
end

local function viewmodels(): number
	local n = 0
	for _, c in workspace.CurrentCamera:GetChildren() do
		if string.sub(c.Name, -9) == "Viewmodel" then
			n += 1
		end
	end
	return n
end

-- ── tests ─────────────────────────────────────────────────────────────────────────────────────────────────────────

function Run.spawn(): any
	local t = Run.truck()
	local seats, targets = {}, {}
	for _, d in t:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("SeatId") and d:FindFirstChild("Hip") then
			table.insert(seats, d:GetAttribute("SeatId"))
		end
		if d:IsA("BasePart") and d:GetAttribute("VehicleTarget") then
			targets[d:GetAttribute("VehicleTarget") :: string] = (targets[d:GetAttribute("VehicleTarget") :: string] or 0) + 1
		end
	end
	table.sort(seats)
	local out = { Door = t:GetAttribute("DriverDoor"), Key = t:GetAttribute("Key"), Brake = t:GetAttribute("ParkingBrake"),
		Lights = t:GetAttribute("Lights"), Seats = seats, Targets = targets, Size = t:GetExtentsSize() }
	out.pass = out.Door == "Closed" and out.Key == "STOP" and out.Brake == true and #seats >= 6
	return out
end

function Run.back(): any
	local out: any = {}
	w("refill")
	Run.standAt("Tailgate")
	local view = Run.aimAt("Tailgate")
	out.tailgatePrompt = texts(view)
	out.pitchBeforeEnter = r2(pitchDeg())
	local e = interact()
	out.enter = e
	out.pitchAfterEnter = r2(pitchDeg())
	frames(0.2)
	out.eyeError = r2(eyeError())
	out.eyeHeight = r2(workspace.CurrentCamera.CFrame.Position.Y - Run.truck():GetPivot().Position.Y)
	out.facing = r2(facingDot(e.Seat or "Back1"))
	out.panel = panelLines()
	out.viewmodels = viewmodels() -- the rifle is down in a bench seat [CONFIRMED]
	out.body = v("view").Body
	-- change seats (aimed down at the seat: the pitch is kept through the cut)
	local target = if e.Seat == "Back4" then "Back2" else "Back4"
	view = aimSeat(target)
	out.movePrompt = texts(view)
	out.pitchBeforeMove = r2(pitchDeg())
	local m = interact()
	out.move = m
	out.pitchAfterMove = r2(pitchDeg())
	frames(0.2)
	out.moveFacing = r2(facingDot(target))
	out.moveEyeError = r2(eyeError())
	-- leave over the left side: placed on the left, looking steeply down
	view = Run.aimAt("BedRailTopL")
	if #view.Options == 0 then
		view = Run.aimAt("Tailgate")
	end
	out.leavePrompt = texts(view)
	local l = interact()
	out.leave = l
	out.pitchAfterExit = r2(pitchDeg())
	out.exitSide = sideOf(root().Position)
	local t0 = os.clock()
	local gone: number? = nil
	while os.clock() - t0 < 1 do
		RunService.RenderStepped:Wait()
		if not gone and v("view").Panel.Kind == nil then
			gone = os.clock() - t0
		end
	end
	out.panelGoneAfterS = r2(gone)
	out.viewmodelsAfter = viewmodels()
	local pe, pm = out.pitchAfterEnter - out.pitchBeforeEnter, out.pitchAfterMove - out.pitchBeforeMove
	out.pass = out.tailgatePrompt == "Get in (back)" and e.Phase == "Entered" and e.Seat == "Back1"
		and (out.eyeError or 9) < 0.2 and (out.facing or 0) > 0.99 and #out.panel == 2 * #Config.Controls.Back - 1
		and out.viewmodels == 0 and out.body.Shown and out.body.LapArms and math.abs(pe) < 2
		and out.movePrompt == "Move to back seat" and m.Seat == target and (out.moveFacing or 0) > 0.99
		and math.abs(pm) < 2 and out.leavePrompt == "Leave vehicle" and l.Phase == "Left" and l.Seat == nil
		and math.abs(out.pitchAfterExit - Config.Exit.PitchDeg) < 2 and out.exitSide == "L" and out.viewmodelsAfter == 1
	return out
end

-- the prompt and the CONTROLS panel against the reference's pixels (scaled by the viewport height) [MEASURED §6 / §7]
function Run.screen(): any
	local out: any = {}
	local vp = workspace.CurrentCamera.ViewportSize
	local s = vp.Y / 720
	local function ref(x: number, y: number): (number, number) -- reference px from screen px (centre-relative)
		return r2((x - vp.X / 2) / s + 640) :: number, r2((y - vp.Y / 2) / s + 360) :: number
	end
	-- two lines at the open door ("Get in (driver)" / "○ Close door")
	Run.standAt("DriverDoor")
	if Run.truck():GetAttribute("DriverDoor") ~= "Open" then
		Run.aimAt("DriverDoorPanel")
		interact()
		frames(0.7)
	end
	aimSeat("Driver")
	frames(0.3)
	local wv = v("view").Widget
	out.lines = #wv.Lines
	if wv.Lines[1] and wv.Lines[2] then
		local b1, b2 = wv.Lines[1].BoxPos, wv.Lines[2].BoxPos
		-- AbsolutePosition is below the top-bar inset; the ScreenGui ignores the inset, so add it back
		local inset = game:GetService("GuiService"):GetGuiInset().Y
		out.box1 = { ref(b1.X, b1.Y + inset) }
		out.boxSize = r2(wv.Lines[1].BoxSize.X / s)
		out.text1 = { ref(wv.Lines[1].TextPos.X, wv.Lines[1].TextPos.Y + inset) }
		out.line2Offset = { r2((b2.X - b1.X) / s), r2((b2.Y - b1.Y) / s) }
		out.textSizeRatio = r2(wv.Lines[2].TextSize / wv.Lines[1].TextSize)
		out.line2HasRing = wv.Lines[2].Ring and not wv.Lines[2].HasKey
	end
	-- into the seat: the panel
	interact()
	frames(0.4)
	local p = v("view").Panel
	local maxRight, ys = 0, {}
	for _, l in p.Lines do
		maxRight = math.max(maxRight, l.Right)
		table.insert(ys, l.Y)
	end
	table.sort(ys)
	local inset = game:GetService("GuiService"):GetGuiInset().Y
	out.panelRight = r2((maxRight - vp.X) / s + 1280)
	out.panelCentreY = r2(((ys[1] + ys[#ys]) / 2 + inset - vp.Y / 2) / s + 360)
	Run.aimAt("DriverDoorPanel")
	interact()
	frames(0.5)
	out.pass = out.lines == 2 and out.box1 ~= nil and math.abs(out.box1[1] - 578.6) < 1.5
		and math.abs(out.box1[2] - 350.6) < 1.5 and math.abs(out.boxSize - 19.4) < 0.6
		and math.abs(out.line2Offset[1] - 25.4) < 1 and math.abs(out.line2Offset[2] - 26) < 1
		and math.abs(out.textSizeRatio - 0.8) < 0.03 and out.line2HasRing and math.abs(out.panelRight - 1262) < 3
		and math.abs(out.panelCentreY - 360.5) < 3
	return out
end

local function angle(door: Model): number
	local closed = door:GetAttribute("ClosedPivot") :: CFrame
	local rel = closed:ToObjectSpace(door:GetPivot())
	local _, y, _ = rel:ToEulerAnglesYXZ()
	return math.deg(y)
end

local function swing(): (number?, number?)
	-- seconds until the door stops moving (sampled every frame), and the final angle
	local door = find("DriverDoor") :: Model
	local t0 = os.clock()
	local last, still, lastMove = angle(door), 0, 0
	while os.clock() - t0 < 1.5 do
		RunService.RenderStepped:Wait()
		local a = angle(door)
		if math.abs(a - last) > 0.05 then
			lastMove = os.clock() - t0
			still = 0
		else
			still += 1
		end
		last = a
		if still > 10 and lastMove > 0 then
			break
		end
	end
	return lastMove, last
end

function Run.driver(): any
	local out: any = {}
	local t = Run.truck()
	local pivot0 = t:GetPivot()
	Run.standAt("DriverDoor")
	out.closedPrompt = texts(Run.aimAt("DriverDoorPanel"))
	v("clear")
	v("press")
	out.openOutsideS, out.openDeg = swing()
	out.openOutsideS = r2(out.openOutsideS)
	out.door = t:GetAttribute("DriverDoor")
	out.seatPrompt = texts(aimSeat("Driver"))
	out.pitchBeforeEnter = r2(pitchDeg())
	local e = interact()
	out.enter = e
	out.pitchAfterEnter = r2(pitchDeg())
	frames(0.3)
	out.eyeError = r2(eyeError())
	out.eyeHeight = r2(workspace.CurrentCamera.CFrame.Position.Y - t:GetPivot().Position.Y)
	out.facing = r2(facingDot("Driver"))
	out.panel = panelLines()
	out.viewmodels = viewmodels()
	out.stowed = v("view").Stowed
	out.arms = v("view").Arms
	out.body = v("view").Body
	-- the door closed from inside first, as in the clip (1072–1083, before the key at 1121)
	out.insidePrompt = texts(Run.aimAt("DriverDoorPanel"))
	v("switch")
	v("clear")
	v("press")
	frames(0.1)
	out.doorReachOnClose = v("view").Arms.Door
	out.closeInsideS = r2((swing()))
	out.closedInsidePrompt = texts(Run.aimAt("DriverDoorPanel"))
	-- engine key (the right arm goes to a hovered control and back after its press)
	out.keyPrompt = texts(Run.aimAt("KeySwitch"))
	frames(0.2)
	out.rightArmHover = r2(v("view").Arms.RightOut)
	out.keyRun = interact()
	frames(0.3)
	out.rightArmAfterPress = r2(v("view").Arms.RightOut)
	out.runPrompt = texts(v("view"))
	out.start = interact() -- "Hold START": the WAIT lamp is still on (not built: UNKNOWN)
	v("switch")
	out.keyStop = interact()
	out.key = t:GetAttribute("Key")
	-- parking brake
	out.brakePrompt = texts(Run.aimAt("ParkingBrake"))
	out.release = interact()
	out.brakePrompt2 = texts(v("view"))
	out.set = interact()
	out.brake = t:GetAttribute("ParkingBrake")
	-- lights
	out.lightsPrompt = texts(Run.aimAt("LightsSwitch"))
	out.lights = interact()
	-- driving keys do nothing: the engine never runs
	local r0 = root().Position
	mHook:Invoke("input", Vector3.new(0, 0, -1))
	frames(0.6)
	mHook:Invoke("input", Vector3.new(1, 0, 0))
	frames(0.4)
	mHook:Invoke("input", nil)
	out.movedWhileSeated = r2((root().Position - r0).Magnitude)
	-- door from inside: open, leave
	Run.aimAt("DriverDoorPanel")
	v("clear")
	v("press")
	out.openInsideS = r2((swing()))
	out.leavePrompt = texts(Run.aimAt("DriverDoorPanel"))
	out.leave = interact()
	out.pitchAfterExit = r2(pitchDeg())
	out.exitSide = sideOf(root().Position)
	out.exitFacingForward = r2(flat(workspace.CurrentCamera.CFrame.LookVector):Dot(flat(t:GetPivot().LookVector)))
	frames(0.5)
	out.panelAfter = v("view").Panel.Kind
	out.viewmodelsAfter = viewmodels()
	out.truckMoved = r2((t:GetPivot().Position - pivot0.Position).Magnitude)
	local D = Config.Door
	local send = Config.Prompt.SendAfterSeconds
	local function near(x: number?, want: number): boolean
		return x ~= nil and math.abs(x - want) < 0.12
	end
	out.pass = out.closedPrompt == "Open door" and out.door == "Open" and out.seatPrompt == "Get in (driver) | Close door"
		and near(out.openOutsideS, send + D.OpenOutsideSeconds) and math.abs(math.abs(out.openDeg) - 82) < 1
		and e.Phase == "Entered" and e.Seat == "Driver" and (out.eyeError or 9) < 0.2 and (out.facing or 0) > 0.99
		and math.abs(out.pitchAfterEnter - out.pitchBeforeEnter) < 2
		and #out.panel == 2 * #Config.Controls.Driver - 1 and out.viewmodels == 0 and out.stowed == true and out.arms.Shown
		and out.body.Shown and not out.body.LapArms and (out.rightArmHover or 0) > 0.95 and (out.rightArmAfterPress or 1) < 0.05
		and out.doorReachOnClose == true and near(out.closeInsideS, send + D.CloseInsideSeconds)
		and near(out.openInsideS, send + D.OpenInsideSeconds) and out.exitSide == "L"
		and math.abs(out.pitchAfterExit - Config.Exit.PitchDeg) < 2 and (out.exitFacingForward or 0) > 0.99
		and out.keyPrompt == "Turn key to RUN" and out.runPrompt == "Hold START  (WAIT lamp's still on) | Turn key to STOP"
		and out.start.Reason == "NotBuilt" and out.key == "STOP" and out.brakePrompt == "Release parking brake"
		and out.brakePrompt2 == "Set parking brake" and out.brake == true and out.lightsPrompt == "Lights on"
		and out.lights.Reason == "NotBuilt" and (out.movedWhileSeated or 9) < 0.05
		and out.insidePrompt == "Leave vehicle | Close door" and out.closedInsidePrompt == "Open door"
		and out.leavePrompt == "Leave vehicle | Close door" and out.leave.Phase == "Left" and out.viewmodelsAfter == 1
		and (out.truckMoved or 9) < 0.001
	return out
end

function Run.weapons(): any
	local out: any = {}
	player:SetAttribute("EquippedWeapon", "M4")
	w("refill")
	frames(0.4)
	Run.standAt("Tailgate")
	Run.aimAt("Tailgate")
	out.enter = interact()
	look(workspace.CurrentCamera.CFrame.Position + Vector3.new(30, 2, 0))
	frames(0.2)
	out.backIdleViewmodels = viewmodels() -- the rifle is down [CONFIRMED]
	local s0 = w("sync")
	w("trigger", true) -- the debug trigger doesn't press the mouse: raise as FIRE would
	v("raise")
	frames(0.5)
	out.backRaisedViewmodels = viewmodels()
	w("trigger", false)
	frames(0.5)
	local s1 = w("sync")
	out.backShots = s1.shotCount - s0.shotCount
	out.backServerShots = s1.server and s0.server and (s0.server.Mag - s1.server.Mag)
	out.backServerMag = s1.server and s1.server.Mag
	Run.aimAt("BedRailTopL")
	out.leave = interact()
	-- driver: no viewmodel, no shot, no reload; forged shots are the server's to refuse
	Run.standAt("DriverDoor")
	Run.aimAt("DriverDoorPanel")
	if Run.truck():GetAttribute("DriverDoor") ~= "Open" then
		interact()
	end
	aimSeat("Driver")
	out.enterDriver = interact()
	frames(0.3)
	local d0 = w("sync")
	w("trigger", true)
	frames(0.5)
	w("trigger", false)
	out.driverShots = w("sync").shotCount - d0.shotCount
	out.driverReload = w("reload").result
	out.viewmodels = viewmodels()
	local head = (character() :: any).Head.Position
	Remotes.WeaponFire:FireServer("M4", head, workspace.CurrentCamera.CFrame.LookVector) -- forged: the server refuses
	Remotes.GrenadeCommand:FireServer("Throw", workspace.CurrentCamera.CFrame.LookVector)
	frames(0.4)
	Run.aimAt("DriverDoorPanel")
	out.leaveDriver = interact()
	out.pass = out.enter.Phase == "Entered" and out.backIdleViewmodels == 0 and out.backRaisedViewmodels == 1
		and out.backShots > 0 and out.leave.Phase == "Left" and out.enterDriver.Phase == "Entered"
		and out.driverShots == 0 and out.viewmodels == 0 and out.leaveDriver.Phase == "Left"
	return out
end

function Run.repeated(n: number?): any
	local ok, total = 0, 0
	for _ = 1, n or 5 do
		Run.standAt("Tailgate")
		Run.aimAt("Tailgate")
		local a = interact()
		Run.aimAt("BedRailTopL")
		local b = interact()
		total += 1
		if a.Phase == "Entered" and b.Phase == "Left" then
			ok += 1
		end
	end
	for _ = 1, n or 5 do
		Run.standAt("DriverDoor")
		Run.aimAt("DriverDoorPanel")
		if Run.truck():GetAttribute("DriverDoor") ~= "Open" then
			interact()
		end
		aimSeat("Driver")
		local a = interact()
		Run.aimAt("DriverDoorPanel")
		local b = interact()
		total += 1
		if a.Phase == "Entered" and b.Phase == "Left" then
			ok += 1
		end
	end
	return { ok = ok, of = total, pass = ok == total, seatAfter = character():GetAttribute("VehicleSeat") }
end

-- the server half must have put a stand-in on Back2 and on Driver first (Run.occupy)
function Run.contention(): any
	local out: any = {}
	Run.standAt("Tailgate")
	Run.aimAt("Tailgate")
	out.enter = interact()
	out.offeredBack2 = texts(aimSeat("Back2"))
	v("clear")
	v("send", { Run.truck(), "MoveSeat", seatPart("Back2"), "Back2" })
	frames(0.4)
	local m = v("messages")
	out.forgedMove = m[#m] and m[#m].Reason
	Run.aimAt("BedRailTopL")
	out.leave = interact()
	Run.standAt("DriverDoor")
	Run.aimAt("DriverDoorPanel")
	if Run.truck():GetAttribute("DriverDoor") ~= "Open" then
		interact()
	end
	aimSeat("Driver")
	out.driver = interact()
	out.pass = out.enter.Phase == "Entered" and out.offeredBack2 == "" and out.forgedMove ~= nil and out.leave.Phase == "Left"
		and out.driver.Phase == "Refused" and out.driver.Reason == "seat taken"
	return out
end

function Run.forged(): any
	local t = Run.truck()
	local results: any = {}
	local function try(name: string, args: { any }, standAt: string?)
		if standAt then
			Run.standAt(standAt)
			-- under the Studio switch the server's copy catches up with a client-side move through whatever lies
			-- between (here: the truck); give it time to settle. Production rules: Run.raw after a server Run.placeAt.
			frames(0.6)
		end
		v("clear")
		local seat0 = character():GetAttribute("VehicleSeat")
		v("send", args)
		frames(0.35)
		local m = v("messages")
		results[name] = { Reason = m[#m] and m[#m].Reason, Phase = m[#m] and m[#m].Phase,
			SeatChanged = character():GetAttribute("VehicleSeat") ~= seat0 }
	end
	local tail = find("Tailgate") :: BasePart
	local door = find("DriverDoorPanel") :: BasePart
	try("notAVehicle", { workspace.Baseplate, "EnterBack", tail }, "Tailgate")
	try("partOfOtherModel", { t, "EnterBack", workspace.Baseplate })
	try("unknownAction", { t, "Teleport", tail })
	try("longAction", { t, string.rep("x", 200), tail })
	try("badSeatType", { t, "MoveSeat", tail, 42 })
	try("unknownSeat", { t, "MoveSeat", tail, "Back99" })
	try("nanArgs", { t, "EnterBack", Vector3.new(0 / 0, 0, 0), "Back1" })
	try("notOffered", { t, "EnterDriver", tail }) -- the tailgate never offers the driver seat
	try("closedDoorDriver", { t, "EnterDriver", find("DriverSeat") }, "DriverDoor") -- the door is closed
	try("farAway", { t, "EnterBack", tail }, "Far")
	try("blocked", { t, "OpenDoor", door }, "PassengerSide") -- through the cab
	-- junk position / direction arguments after a valid request: ignored (the enter itself is legitimate)
	try("extraPositionArgs", { t, "EnterBack", tail, nil, Vector3.new(0, 500, 0), Vector3.new(9e9, 0, 0) }, "Tailgate")
	frames(0.2)
	Run.aimAt("BedRailTopL")
	results.leaveAfterExtra = interact().Phase
	-- duplicate: two enters in the same frame
	Run.standAt("Tailgate")
	v("clear")
	Remotes.VehicleCommand:FireServer("Interact", t, "EnterBack", tail)
	Remotes.VehicleCommand:FireServer("Interact", t, "EnterBack", tail)
	frames(0.4)
	local m = v("messages")
	local entered, refused = 0, 0
	for _, x in m do
		if x.Phase == "Entered" then
			entered += 1
		elseif x.Phase == "Refused" then
			refused += 1
		end
	end
	results.duplicateEnter = { Entered = entered, Refused = refused }
	-- seated: teleport / velocity attempts from the client. Only this client's copy moves (the body is welded to the
	-- anchored truck on the server): the server half checks its own copy (TruckTest server Run.view) before stage "b".
	local r = root()
	local before = r.Position
	r.CFrame = r.CFrame + Vector3.new(0, 40, 0)
	r.AssemblyLinearVelocity = Vector3.new(0, 300, 900)
	frames(0.6)
	results.teleportWhileSeated = { ClientCopyMovedStuds = r2((r.Position - before).Magnitude),
		Seat = character():GetAttribute("VehicleSeat") }
	-- this client's copy is put back (its own view would otherwise sit inside the seat it dragged along); the forged
	-- velocity stays on it, for stage b's exit
	r.CFrame = r.CFrame - Vector3.new(0, 40, 0)
	local pass = true
	for _, k in { "notAVehicle", "partOfOtherModel", "unknownAction", "longAction", "badSeatType", "unknownSeat", "nanArgs",
		"notOffered", "closedDoorDriver", "farAway", "blocked" } do
		pass = pass and results[k].Phase == "Refused" and not results[k].SeatChanged
	end
	results.pass = pass and results.extraPositionArgs.Phase == "Entered" and results.leaveAfterExtra == "Left"
		and results.duplicateEnter.Entered == 1 and results.teleportWhileSeated.Seat ~= nil
	return results
end

-- stage b, after the server has checked its copy: the rate limit, a forged server → client message, leave
function Run.forgedFinish(): any
	local t = Run.truck()
	local tail = find("Tailgate") :: BasePart
	local results: any = {}
	v("clear")
	for _ = 1, 20 do
		Remotes.VehicleCommand:FireServer("Interact", t, "Teleport", tail)
	end
	frames(0.4)
	local rate = 0
	for _, x in v("messages") do
		if x.Reason == "rate" then
			rate += 1
		end
	end
	results.rate = rate
	Remotes.VehicleState:FireServer({ Phase = "Entered", Seat = "Driver" }) -- server → client only: ignored
	frames(1.0) -- the rate window passes
	local seatId = character():GetAttribute("VehicleSeat")
	Run.aimAt("BedRailTopL")
	results.leave = interact()
	-- the body stays where the server placed it, whatever this client's copy carried from the seat
	frames(1.0)
	local exitA = seatId and seatPart(seatId):FindFirstChild("ExitL") :: Attachment?
	local d = exitA and (root().Position - exitA.WorldPosition)
	results.exitOffset = d and r2(Vector3.new(d.X, 0, d.Z).Magnitude)
	results.speedAfter = r2(root().AssemblyLinearVelocity.Magnitude)
	-- clean up: the forged velocity was stored on this client's copy of the (anchored) seat; later tests start clean
	if seatId then
		seatPart(seatId).AssemblyLinearVelocity = Vector3.zero
	end
	results.pass = results.rate > 0 and results.leave.Phase == "Left" and (results.exitOffset or 99) < 1
		and (results.speedAfter or 99) < 1
	return results
end

-- one raw request from where the server placed the player (production-rule security runs: the server half places the
-- player with Run.placeAt and turns the Studio switch off first). aim: send the camera's direction toward the target.
function Run.raw(action: string, targetName: string, seat: string?, aim: boolean?): any
	local t = Run.truck()
	local target = find(targetName) :: BasePart
	local dir = nil
	if aim then
		local from = workspace.CurrentCamera.CFrame.Position
		dir = (target.Position - from).Unit
	end
	v("clear")
	v("send", { t, action, target, seat, dir })
	frames(0.35)
	local m = v("messages")
	return { Phase = m[#m] and m[#m].Phase, Reason = m[#m] and m[#m].Reason, Seat = character():GetAttribute("VehicleSeat") }
end

-- death in a seat: "enter" (sits in the bed; then the server kills), "after" (once respawned)
function Run.deathInSeat(stage: string): any
	if stage == "enter" then
		Run.standAt("Tailgate")
		Run.aimAt("Tailgate")
		return interact()
	end
	local t0 = os.clock()
	while (player.Character == nil or (player.Character :: any).Humanoid.Health <= 0) and os.clock() - t0 < 12 do
		frames(0.2)
	end
	frames(1.5)
	local c = character()
	local view = v("view")
	return { Seat = c:GetAttribute("VehicleSeat"), Panel = view.Panel.Kind, Eye = view.Eye ~= nil, Stowed = view.Stowed,
		viewmodels = viewmodels(), pass = c:GetAttribute("VehicleSeat") == nil and view.Panel.Kind == nil and view.Eye == nil }
end

return Run
