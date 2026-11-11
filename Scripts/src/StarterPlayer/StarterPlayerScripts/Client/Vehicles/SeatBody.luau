--!strict
-- The seated player's own legs and lap arms (truck slice; presentation, this client only). Looking down in a seat the
-- player sees their own dark-navy legs, and in a bench seat light-grey arm blocks resting across the lap [CONFIRMED:
-- bed 140–184, 283–305, 337–394, 421–455, 553–566, 593–623; cab 1488]; looking level, nothing [CONFIRMED]. Built in the
-- seat's own space from its Hip attachment (the body doesn't turn with the head). The lap arms go while a bench seat's
-- rifle is raised (SeatView.weaponsStowed false). In the driver seat the arms are Client.Vehicles.DriverArms.
-- Proportions: Shared.Config.Vehicles.SeatBody [PLACEHOLDER sizes, INFERRED from the frames].

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Vehicles"))
local SeatView = require(script.Parent:WaitForChild("SeatView"))
local B = Config.SeatBody

local Body = {}

local model: Model? = nil
local parts: { [string]: BasePart } = {}

local function block(name: string, size: Vector3, color: Color3, m: Model)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = m
	parts[name] = p
end

local function build()
	if model then
		return
	end
	local m = Instance.new("Model")
	m.Name = "SeatBody"
	local leg = B.LegSize
	for _, s in { "L", "R" } do
		block("Thigh" .. s, leg, B.LegColor, m)
		block("Shin" .. s, leg, B.LegColor, m)
		block("LapArm" .. s, B.ArmSize, B.ArmColor, m)
	end
	model = m
end

local function between(p: BasePart, a: Vector3, b: Vector3)
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
end

local function step()
	local seat = SeatView.seat()
	local hip = seat and seat.Seat:FindFirstChild("Hip") :: Attachment?
	if not hip then
		if model then
			model.Parent = nil
		end
		return
	end
	build()
	local m = model :: Model
	if m.Parent ~= workspace.CurrentCamera then
		m.Parent = workspace.CurrentCamera
	end
	local h = hip.WorldCFrame -- the body's root: forward is -Z, up is +Y
	local feet = seat.Seat:FindFirstChild("Feet") :: Attachment? -- where the feet rest, if not straight down (driver)
	local legLen = B.LegSize.Z
	for i, s in { "L", "R" } do
		local x = if i == 1 then -0.42 else 0.42
		local hipJoint = h:PointToWorldSpace(Vector3.new(x, -0.75, -0.1))
		local knee = h:PointToWorldSpace(Vector3.new(x, -0.75, -0.1 - legLen))
		local ankle = if feet then (h.Rotation * CFrame.new(x, 0, 0)).Position + feet.WorldPosition
			else h:PointToWorldSpace(Vector3.new(x, -0.75 - legLen, -0.25 - legLen))
		between(parts["Thigh" .. s], hipJoint, knee)
		local shin = parts["Shin" .. s]
		shin.Size = Vector3.new(B.LegSize.X, B.LegSize.Y, math.max(0.2, (ankle - knee).Magnitude))
		between(shin, knee, ankle)
		local lap = parts["LapArm" .. s]
		local show = seat.Kind == "Back" and SeatView.weaponsStowed()
		lap.Transparency = if show then 0 else 1
		if show then
			-- from the shoulder down to the hand resting on the other thigh (the forearms cross over the lap)
			local shoulder = h:PointToWorldSpace(Vector3.new(x * 2, 0.75, -0.05))
			local hand = h:PointToWorldSpace(Vector3.new(-x * 0.4, -0.35, -1.25))
			local d = hand - shoulder
			lap.CFrame = CFrame.lookAt(hand - d.Unit * (lap.Size.Z / 2), hand)
		end
	end
end

RunService:BindToRenderStep("SeatBody", Enum.RenderPriority.Camera.Value + 4, step)

function Body.read(): any
	return { Shown = model ~= nil and model.Parent ~= nil,
		LapArms = parts.LapArmL ~= nil and parts.LapArmL.Transparency == 0 }
end

return Body
