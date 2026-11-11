--!strict
-- The driver's arms (truck slice; presentation, this client only). In the driver seat no rifle is shown and two blocky
-- arms hold the steering wheel [CONFIRMED] (MEASURED behaviour, ReferenceAnalysis/Truck §8):
--   * left arm: on the wheel's left rim (Attachment GripL on the vehicle's SteeringWheel); when the door is used it goes
--     to the door's inside handle from the first pale frame, follows the door's swing and comes back to the rim
--     Config.DriverArms.DoorBackSeconds after the swing ends (close 1072 → ≈ 1094, open 1470 → held to 1488);
--   * right arm: on the rim at GripR; it goes to whatever cab control (key switch, lights switch, parking brake) the
--     prompt is on while hovered (out in 1–2 frames, e.g. 1236 → 1237), and back once that control's press is over
--     (retraction ends 4–5 frames after the pale period) until the aim leaves the control.
-- Each arm is a block from a shoulder point in camera space to its hand point. Values: Shared.Config.Vehicles.DriverArms.
-- Made once; updated every frame only while seated as the driver.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Vehicles"))
local SeatView = require(script.Parent:WaitForChild("SeatView"))
local D = Config.DriverArms
local CONTROLS = { KeySwitch = true, LightsSwitch = true, ParkingBrake = true }

local Arms = {}

local model: Model? = nil
local parts: { [string]: BasePart } = {}
local hovered: BasePart? = nil
local used: BasePart? = nil
local usedAt = 0
local rightF = 0
local rightTarget: BasePart? = nil
local door: any = nil -- { T0, SwingEnd }
local reaches = { Door = 0, Hover = 0 }

local function build()
	if model and model.Parent then
		return
	end
	local m = Instance.new("Model")
	m.Name = "DriverArms"
	for _, side in { "L", "R" } do
		local p = Instance.new("Part")
		p.Name = "Arm" .. side
		p.Size = D.Size
		p.Color = D.Color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = m
		parts[side] = p
	end
	m.Parent = workspace.CurrentCamera
	model = m
end

local function place(p: BasePart, from: Vector3, to: Vector3)
	local d = to - from
	if d.Magnitude < 1e-3 then
		return
	end
	-- the block's far end sits on the hand point; its length is the arm's own (not stretched)
	p.CFrame = CFrame.lookAt(to - d.Unit * (p.Size.Z / 2), to)
end

local function closest(part: BasePart, from: Vector3): Vector3
	local rel = part.CFrame:PointToObjectSpace(from)
	local h = part.Size / 2
	return part.CFrame:PointToWorldSpace(Vector3.new(math.clamp(rel.X, -h.X, h.X), math.clamp(rel.Y, -h.Y, h.Y),
		math.clamp(rel.Z, -h.Z, h.Z)))
end

local function attachment(root: Instance, name: string): Attachment?
	local a = root:FindFirstChild(name, true)
	return if a and a:IsA("Attachment") then a else nil
end

local function smooth(f: number): number
	f = math.clamp(f, 0, 1)
	return f * f * (3 - 2 * f)
end

local lastT = os.clock()
local function step()
	local now = os.clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now
	local seat = SeatView.seat()
	if not (seat and seat.Kind == "Driver") then
		if model then
			model.Parent = nil
		end
		door, used, hovered, rightF = nil, nil, nil, 0
		return
	end
	build()
	local m = model :: Model
	if m.Parent ~= workspace.CurrentCamera then
		m.Parent = workspace.CurrentCamera
	end
	local cam = workspace.CurrentCamera.CFrame
	local wheel = seat.Vehicle:FindFirstChild("SteeringWheel", true)
	local function rim(side: string): Vector3
		local a = wheel and attachment(wheel, "Grip" .. side)
		return if a then a.WorldPosition else cam:PointToWorldSpace(D.Shoulder[side] + Vector3.new(0, 0.6, -1.6))
	end

	-- left: the rim, or the door's inside handle during a door use
	local shoulderL = cam:PointToWorldSpace(D.Shoulder.L)
	local handL = rim("L")
	if door then
		local t = now - door.T0
		local back = now - door.SwingEnd
		local f = if back <= 0 then smooth(t / D.OutSeconds) else 1 - smooth(back / D.DoorBackSeconds)
		local handle = attachment(seat.Vehicle, "DoorHandleInside")
		if handle then
			handL = handL:Lerp(handle.WorldPosition, f)
		end
		if back > D.DoorBackSeconds then
			door = nil
		end
	end
	place(parts.L, shoulderL, handL)

	-- right: the rim, or the hovered cab control
	local shoulderR = cam:PointToWorldSpace(D.Shoulder.R)
	if hovered ~= used then
		used = nil
	end
	local want = hovered ~= nil and (used == nil or now < usedAt + Config.Prompt.PaleSeconds)
	if want then
		rightTarget = hovered
	end
	rightF = math.clamp(rightF + (if want then dt / D.OutSeconds else -dt / D.BackSeconds), 0, 1)
	local handR = rim("R")
	if rightTarget and rightTarget.Parent and rightF > 0 then
		handR = handR:Lerp(closest(rightTarget, shoulderR), smooth(rightF))
	end
	place(parts.R, shoulderR, handR)
end

RunService:BindToRenderStep("DriverArms", Enum.RenderPriority.Camera.Value + 4, step)

-- the part the prompt is on this frame (VehicleClient); only cab controls draw the right arm
function Arms.hover(part: BasePart?)
	local kind = part and part:GetAttribute("VehicleTarget")
	local h = if part and CONTROLS[kind :: any] then part else nil
	if h and h ~= hovered then
		reaches.Hover += 1
	end
	hovered = h
end

-- F pressed on a target (VehicleClient, at the first pale frame)
function Arms.pressed(part: BasePart?, action: string)
	local seat = SeatView.seat()
	if not (part and seat and seat.Kind == "Driver") then
		return
	end
	if action == "OpenDoor" or action == "CloseDoor" then
		local D2 = Config.Door
		local swing = if action == "OpenDoor" then D2.OpenInsideSeconds else D2.CloseInsideSeconds
		door = { T0 = os.clock(), SwingEnd = os.clock() + Config.Prompt.SendAfterSeconds + swing }
		reaches.Door += 1
	elseif part == hovered then
		used, usedAt = part, os.clock()
	end
end

function Arms.read(): any
	return { Shown = model ~= nil and model.Parent ~= nil, Door = door ~= nil, RightOut = rightF,
		Hovered = hovered and hovered.Name, Reaches = table.clone(reaches),
		L = parts.L and parts.L.Position, R = parts.R and parts.R.Position }
end

return Arms
