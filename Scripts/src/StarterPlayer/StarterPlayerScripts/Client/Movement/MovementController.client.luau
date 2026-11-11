--!strict
-- Player movement, client side: responsive presentation of a server-owned movement model
-- (Server.Movement.MovementServer owns the stance, the speeds and where the character may be).
--   Input: the move input from the default controls is eased (start / stop time constants) before the humanoid uses
--     it; the client only intervenes while easing. C toggles crouch: predicted at once, sent as an intent, and
--     reconciled with the server's Stance attribute (a refused request reverts within 0.4 s).
--   Camera: eye height 4.05 studs above the floor standing (2.7 crouched), eased between stances, for any avatar; a
--     roll that follows the turn rate (MovementPresentation). FOV is untouched (the weapon owns it).
--   Viewmodel: MovementPresentation is stepped here; WeaponController applies its offset to the rig.
--   The "CROUCHED" toast appears when the server confirms a crouch.
-- Values: Shared.Config.Movement (ReferenceAnalysis/Movement/Movement_Analysis.md). No sprint (UNKNOWN; not built).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Movement"))
local Intent = Shared:WaitForChild("Remotes"):WaitForChild("MovementIntent") :: RemoteEvent
local Presentation = require(script.Parent:WaitForChild("MovementPresentation"))
local Toast = require(script.Parent:WaitForChild("CrouchToast"))
-- truck slice: seated in a vehicle, the eye is the seat's measured eye point (nil on foot: everything below unchanged)
local SeatView = require(script.Parent.Parent:WaitForChild("Vehicles"):WaitForChild("SeatView"))

local player = Players.LocalPlayer
local A = Config.Attributes

local predicted = "STAND"
local predictedAt = 0
local smoothed = Vector3.zero
local eye = Config.Camera.EyeHeight
local floorY: number? = nil -- eased floor height under the feet (camera)
local lastYaw: number? = nil
local lastPitch = 0
local debugInput: Vector3? = nil
local recordLog: { any }? = nil
local perf = { Frames = 0, Seconds = 0, MaxSeconds = 0 }
local stanceConn: RBXScriptConnection? = nil

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
floorParams.RespectCanCollide = true

local function parts(): (Model?, Humanoid?, BasePart?)
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if c and hum and root and hum.Health > 0 then
		return c, hum, root
	end
	return nil, nil, nil
end

local function onCharacter(c: Model)
	predicted, predictedAt = "STAND", 0
	smoothed = Vector3.zero
	eye = Config.Camera.EyeHeight
	floorY = nil
	lastYaw = nil
	Presentation.reset()
	Toast.hide()
	if stanceConn then
		stanceConn:Disconnect()
	end
	local last = c:GetAttribute(A.Stance)
	stanceConn = c:GetAttributeChangedSignal(A.Stance):Connect(function()
		local s = c:GetAttribute(A.Stance)
		if s == "CROUCH" and last ~= "CROUCH" then
			Toast.show(Config.Crouch.Toast.Text)
		end
		last = s
	end)
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end

local function requestCrouch(want: boolean): string
	local c = parts()
	if not c then
		return "dead"
	end
	if c:GetAttribute(A.Locked) ~= nil then
		return "locked"
	end
	predicted = if want then "CROUCH" else "STAND"
	predictedAt = os.clock()
	Intent:FireServer("Crouch", want)
	return predicted
end

if Config.Crouch.Enabled then
	ContextActionService:BindAction("MovementCrouch", function(_, state: Enum.UserInputState, _): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			requestCrouch(predicted ~= "CROUCH")
		end
		return Enum.ContextActionResult.Sink
	end, false, Config.Crouch.Key, Config.Crouch.GamepadKey)
end

-- Ease the move input after the default controls set it this frame (they run at RenderPriority.Input).
RunService:BindToRenderStep("MovementInput", Enum.RenderPriority.Input.Value + 1, function(dt: number)
	local _, hum = parts()
	if not hum then
		smoothed = Vector3.zero
		return
	end
	local target = debugInput or hum.MoveDirection
	if target.Magnitude > 1 then
		target = target.Unit
	end
	local starting = target.Magnitude > 1e-3
		and target.Magnitude >= smoothed.Magnitude - 1e-6
		and (smoothed.Magnitude < 1e-3 or target:Dot(smoothed) > 0)
	local tau = if starting then Config.Accel.StartTau else Config.Accel.StopTau
	smoothed = target + (smoothed - target) * math.exp(-dt / tau)
	if (smoothed - target).Magnitude < 2e-3 then
		smoothed = target
	end
	if debugInput ~= nil or smoothed ~= target then
		hum:Move(smoothed, false)
	end
end)

local function yawPitch(look: Vector3): (number, number)
	return math.deg(math.atan2(-look.X, -look.Z)), math.deg(math.asin(math.clamp(look.Y, -1, 1)))
end

-- After the camera scripts (and before the weapon controller): eye height, roll, presentation state.
RunService:BindToRenderStep("MovementCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	local t0 = os.clock()
	local camera = workspace.CurrentCamera
	local c, hum, root = parts()
	if not (c and hum and root) or camera.CameraSubject ~= hum then
		Presentation.reset()
		lastYaw = nil
		return
	end
	local server = c:GetAttribute(A.Stance) or "STAND"
	if predicted ~= server and os.clock() - predictedAt > 0.4 then
		predicted = server -- the server refused (or changed) the stance
	end

	-- the camera scripts' own rotation this frame (the weapon's offsets were removed before they ran)
	local base = camera.CFrame
	local snap = SeatView.consumeSnap(base) -- truck slice: a seat cut turns the view once (nil otherwise)
	if snap then
		base = CFrame.new(base.Position) * snap
	end
	local yaw, pitch = yawPitch(base.LookVector)
	local turnRight, turnDown = 0, 0
	if lastYaw and dt > 0 then
		local dyaw = (yaw - lastYaw + 180) % 360 - 180
		local dpitch = pitch - lastPitch
		if math.abs(dyaw) <= Config.Viewmodel.LookLag.CutDeg and math.abs(dpitch) <= Config.Viewmodel.LookLag.CutDeg then
			turnRight, turnDown = -dyaw / dt, -dpitch / dt
		end
	end
	lastYaw, lastPitch = yaw, pitch

	local seatEye = SeatView.eye()
	if seatEye then
		-- seated in a vehicle: no walking, the eye is the seat's (look lag and roll keep working)
		floorY = nil
		Presentation.step(dt, turnRight, turnDown, 0, true)
		camera.CFrame = CFrame.new(seatEye.Position) * base.Rotation * Presentation.cameraRoll()
		local spent = os.clock() - t0
		perf.Frames += 1
		perf.Seconds += spent
		perf.MaxSeconds = math.max(perf.MaxSeconds, spent)
		return
	end

	-- eye height above the floor under the feet (presentation ray; airborne: follow the root)
	local target = if predicted == "CROUCH" then Config.Crouch.EyeHeight else Config.Camera.EyeHeight
	local rate = math.abs(Config.Camera.EyeHeight - Config.Crouch.EyeHeight) / Config.Crouch.TransitionSeconds
	eye += math.clamp(target - eye, -rate * dt, rate * dt)
	floorParams.FilterDescendantsInstances = { c }
	local reach = hum.HipHeight + root.Size.Y / 2 + 1.5
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), floorParams)
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local floorTarget = if hit then hit.Position.Y else root.Position.Y - root.Size.Y / 2 - hum.HipHeight
	if floorY == nil or not grounded or not hit then
		floorY = floorTarget -- airborne: the camera follows the body
	else
		floorY = (floorY :: number) + (floorTarget - (floorY :: number)) * (1 - math.exp(-dt / Config.Camera.FloorSmoothTau))
	end
	local feetY = floorY :: number
	local v = root.AssemblyLinearVelocity
	local flatSpeed = Vector3.new(v.X, 0, v.Z).Magnitude
	Presentation.step(dt, turnRight, turnDown, flatSpeed, grounded)

	local p = base.Position
	camera.CFrame = CFrame.new(p.X, feetY + eye, p.Z) * base.Rotation * Presentation.cameraRoll()

	if recordLog then
		table.insert(recordLog, {
			t = os.clock(),
			camera = camera.CFrame,
			eyeAboveFeet = camera.CFrame.Position.Y - feetY,
			feetY = feetY,
			root = root.Position,
			vel = v,
			moveDirection = hum.MoveDirection,
			smoothed = smoothed,
			stance = predicted,
			serverStance = server,
			serverState = c:GetAttribute(A.MoveState),
			roll = Presentation.Roll,
			lagYaw = Presentation.LagYaw,
			lagPitch = Presentation.LagPitch,
			bobYaw = Presentation.BobYaw,
			bobPitch = Presentation.BobPitch,
			turnRight = turnRight,
			fov = camera.FieldOfView,
			grounded = grounded,
		})
	end
	local spent = os.clock() - t0
	perf.Frames += 1
	perf.Seconds += spent
	perf.MaxSeconds = math.max(perf.MaxSeconds, spent)
end)

-- Studio-only debug hook for the focused tests (never created in a live game).
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "MovementClientDebug"
	hook.OnInvoke = function(cmd: string, arg: any): any
		if cmd == "input" then
			debugInput = if typeof(arg) == "Vector3" then arg else nil
		elseif cmd == "crouch" then
			return requestCrouch(arg == true)
		elseif cmd == "record" then
			if arg then
				recordLog = {}
			else
				local out = recordLog
				recordLog = nil
				return out
			end
		elseif cmd == "perf" then
			return table.clone(perf)
		elseif cmd == "resetperf" then
			perf.Frames, perf.Seconds, perf.MaxSeconds = 0, 0, 0
		elseif cmd == "toast" then
			return Toast.read()
		end
		local c, hum = parts()
		return {
			predicted = predicted,
			server = c and c:GetAttribute(A.Stance),
			state = c and c:GetAttribute(A.MoveState),
			eye = eye,
			smoothed = smoothed,
			moveDirection = hum and hum.MoveDirection,
			walkSpeed = hum and hum.WalkSpeed,
			roll = Presentation.Roll,
			lagYaw = Presentation.LagYaw,
			lagPitch = Presentation.LagPitch,
			bobYaw = Presentation.BobYaw,
			bobPitch = Presentation.BobPitch,
			weight = Presentation.Weight,
			camera = workspace.CurrentCamera.CFrame,
			fov = workspace.CurrentCamera.FieldOfView,
		}
	end
	hook.Parent = script
end
