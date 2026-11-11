--!strict
-- Body interaction (client): the temporary F menu near a body. It only ASKS the server (Shared.Remotes.BodyInteract:
-- "PulseCheck" / "Drag" with the body, "LetGo") and shows what the server answers (Shared.Remotes.BodyInteractState):
-- the 3.00 s check, the result line, "Let go" while dragging. It never decides a result, a range, a state or a body's
-- position. Values: Shared.Config.BodyInteraction. Studio-only test hook: BindableFunction BodyInteractionDebug.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("BodyInteraction"))
local Menu = require(script.Parent:WaitForChild("InteractionMenu"))
-- truck slice: seated, or with a vehicle prompt on screen, the body menu stands down (one F press, one action)
local SeatView = require(script.Parent.Parent:WaitForChild("Vehicles"):WaitForChild("SeatView"))
local Remotes = Shared:WaitForChild("Remotes")
local Request = Remotes:WaitForChild(Config.Remote) :: RemoteEvent
local StateIn = Remotes:WaitForChild(Config.StateRemote) :: RemoteEvent

local player = Players.LocalPlayer

local bodies: { [Model]: boolean } = {}
local candidate: Model? = nil
local selected = 1
local activity: string? = nil -- "PulseCheck" while checking, "Drag" while dragging (set from the server's messages)
local activityTarget: Model? = nil
local activityStart = 0
local activitySeconds = 0
local pulse: any? = nil -- { Target, Text, Color }: the last result, a snapshot (cleared when a drag ends, I6)
local messages: { any } = {} -- Studio: what the server sent, with arrival times

local function track(d: Instance)
	if d:IsA("Model") and d:GetAttribute(Config.BodyAttribute) == true then
		bodies[d] = true
	end
end
for _, d in workspace:GetDescendants() do
	track(d)
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(track, d)
	end
end)

-- Closest point of a body to a position (same measure the server uses; the server re-checks everything).
local function distanceTo(model: Model, from: Vector3): number
	local best = math.huge
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			local rel = d.CFrame:PointToObjectSpace(from)
			local h = d.Size / 2
			local c = Vector3.new(math.clamp(rel.X, -h.X, h.X), math.clamp(rel.Y, -h.Y, h.Y), math.clamp(rel.Z, -h.Z, h.Z))
			best = math.min(best, (rel - c).Magnitude)
		end
	end
	return best
end

-- The body the menu offers: the nearest one in range, roughly in front of the camera.
local function findCandidate(): Model?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local cam = workspace.CurrentCamera
	local best, bestDist = nil, math.huge
	for m in bodies do
		if not m:IsDescendantOf(workspace) then
			bodies[m] = nil
			continue
		end
		local dist = distanceTo(m, root.Position)
		if dist <= Config.StartStuds and dist < bestDist then
			local torso = (m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m.PrimaryPart) :: BasePart?
			local toward = if torso then torso.Position - cam.CFrame.Position else nil
			if toward and toward.Magnitude > 1e-3 and cam.CFrame.LookVector:Dot(toward.Unit) >= Config.FacingDot then
				best, bestDist = m, dist
			end
		end
	end
	return best
end

local function render()
	local target = if activity then activityTarget else candidate
	if not target then
		Menu.show(nil)
		return
	end
	local result = if pulse and pulse.Target == target then pulse else nil
	if activity == "Drag" then
		Menu.show({ items = { "[F] " .. Config.LetGoLabel }, selected = 1, busy = false, result = result })
		return
	end
	local items = {}
	for i, it in Config.Items do
		local text = it.Label
		if activity == "PulseCheck" and it.Action == "PulseCheck" then
			text = it.Busy
		end
		items[i] = text
	end
	local sel = if activity == "PulseCheck" then 1 else selected
	Menu.show({ items = items, selected = sel, busy = activity == "PulseCheck", result = result })
end

local function press()
	if activity == "Drag" then
		Request:FireServer("LetGo")
		return
	end
	if activity or not candidate then
		return -- during a check F does nothing (what it does in the footage is UNKNOWN)
	end
	local item = Config.Items[selected]
	Request:FireServer(item.Action, candidate)
end

local function moveSelection(step: number)
	if activity or not candidate then
		return
	end
	selected = (selected - 1 + step) % #Config.Items + 1
	render()
end

StateIn.OnClientEvent:Connect(function(msg: any)
	if typeof(msg) ~= "table" then
		return
	end
	if RunService:IsStudio() then
		table.insert(messages, { At = os.clock(), Kind = msg.Kind, Phase = msg.Phase, Reason = msg.Reason, Result = msg.Result,
			Text = msg.Text, Target = if typeof(msg.Target) == "Instance" then msg.Target.Name else nil })
		while #messages > 64 do
			table.remove(messages, 1)
		end
	end
	local target = if typeof(msg.Target) == "Instance" and msg.Target:IsA("Model") then msg.Target :: Model else nil
	if msg.Phase == "Started" and target then
		activity, activityTarget, activityStart = msg.Kind, target, os.clock()
		activitySeconds = if typeof(msg.Seconds) == "number" then msg.Seconds else 0
		render()
		if msg.Kind == "PulseCheck" then
			Menu.startProgress(activitySeconds, 0)
		end
	elseif msg.Phase == "Result" and target then
		local res = Config.Pulse.Results[msg.Result]
		pulse = if res then { Target = target, Text = res.Text, Color = res.Color } else nil
		activity, activityTarget = nil, nil
		-- after a completed check the highlight moves to the next item by itself [confirmed I3]
		selected = selected % #Config.Items + 1
		render()
	elseif msg.Phase == "Interrupted" or msg.Phase == "Released" then
		if msg.Kind == "Drag" then
			pulse = nil -- the result line disappears on release [confirmed I6]
		end
		activity, activityTarget = nil, nil
		render()
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Config.Key and not (SeatView.busy() and activity == nil) then
		press()
	end
end)
UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	moveSelection(if input.Position.Z < 0 then 1 else -1) -- [placeholder input: UNKNOWN in the footage]
end)

-- The menu follows what is near (10 Hz); nothing per frame.
task.spawn(function()
	while true do
		local c = if activity or SeatView.busy() then nil else findCandidate()
		if c ~= candidate then
			candidate = c
			if c == nil or (pulse and pulse.Target ~= c) then
				selected = 1
			end
			render()
		end
		task.wait(0.1)
	end
end)

if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "BodyInteractionDebug"
	hook.OnInvoke = function(cmd: string, arg: any): any
		if cmd == "press" then
			press()
			return os.clock()
		elseif cmd == "select" then
			selected = math.clamp(tonumber(arg) or 1, 1, #Config.Items)
			render()
			return selected
		elseif cmd == "wheel" then
			moveSelection(tonumber(arg) or 1)
			return selected
		elseif cmd == "refresh" then
			candidate = if activity then nil else findCandidate()
			render()
			return candidate and candidate.Name
		elseif cmd == "view" then
			local v = Menu.read()
			v.Candidate = candidate and candidate.Name
			v.Activity = activity
			v.SelectedItem = selected
			return v
		elseif cmd == "messages" then
			return messages
		elseif cmd == "clear" then
			table.clear(messages)
			return true
		end
		return nil
	end
	hook.Parent = script
end
