--!strict
-- Grenade client: G throws (asks the server with the camera's aim direction only), the first-person throw swing, the
-- "FRAG OUT  xN" / "NO FRAGS LEFT" label from the server's answers, the detonation effect from the server's one
-- message per detonation, and the red screen-edge pulse when the server says fragments reached this player.
-- First-person fidelity pass: the press also lowers the held weapon (Client.FirstPerson.WeaponLowering) and starts the
-- local view of the grenade in flight (GrenadePrediction), which the server's "Released" message puts on the server's
-- own path. It decides nothing: no position, velocity, fuse, detonation, fragment, hit or damage.
-- Values: Shared.Config.Grenade. Studio-only test hook: BindableFunction GrenadeClientDebug.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Grenade"))
local Label = require(script.Parent:WaitForChild("FragOutLabel"))
local Effect = require(script.Parent:WaitForChild("ExplosionEffect"))
local Presentation = require(script.Parent:WaitForChild("ThrowPresentation"))
local RedEdge = require(script.Parent:WaitForChild("RedEdge"))
local Prediction = require(script.Parent:WaitForChild("GrenadePrediction"))
local WeaponLowering = require(script.Parent.Parent:WaitForChild("FirstPerson"):WaitForChild("WeaponLowering"))
local SeatView = require(script.Parent.Parent:WaitForChild("Vehicles"):WaitForChild("SeatView"))
local Remotes = Shared:WaitForChild("Remotes")
local Command = Remotes:WaitForChild(Config.Remotes.Command) :: RemoteEvent
local StateIn = Remotes:WaitForChild(Config.Remotes.State) :: RemoteEvent
local FxIn = Remotes:WaitForChild(Config.Remotes.Fx) :: RemoteEvent

local player = Players.LocalPlayer
local left: number? = nil -- grenades left, as the server last said
local throwingUntil = 0
local messages: { any } = {} -- Studio: what the server sent
local fxReceived: { any } = {}

local function alive(): boolean
	local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

local function press(): number
	local now = os.clock()
	if not alive() or now < throwingUntil or SeatView.grenadesStowed() then
		return now -- (truck slice: nothing is thrown from a vehicle seat; the server refuses it too)
	end
	local aim = workspace.CurrentCamera.CFrame.LookVector
	Command:FireServer("Throw", aim)
	if left ~= 0 then -- with none left the footage shows no throw animation, only the label
		throwingUntil = now + Config.Throw.Seconds
		Presentation.play(now)
		Prediction.expect(aim, now)
		WeaponLowering.play(Config.Throw.LowerWeapon, now)
	end
	return now
end

local function watch(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.Died:Connect(function()
			Presentation.stop() -- the server releases nothing after a death
			Prediction.cancelPending()
		end)
	end
end
player.CharacterAdded:Connect(function(character: Model)
	Prediction.reset()
	WeaponLowering.reset()
	watch(character)
end)
if player.Character then
	task.spawn(watch, player.Character)
end

StateIn.OnClientEvent:Connect(function(msg: any)
	if typeof(msg) ~= "table" then
		return
	end
	if RunService:IsStudio() then
		table.insert(messages, { At = os.clock(), Phase = msg.Phase, Left = msg.Left, Reason = msg.Reason, Id = msg.Id })
		while #messages > 64 do
			table.remove(messages, 1)
		end
	end
	if typeof(msg.Left) == "number" then
		left = msg.Left
	end
	if msg.Phase == "Released" then
		Label.show(string.format(Config.Label.Out, msg.Left))
		Prediction.released(msg)
	elseif msg.Phase == "Refused" then
		Prediction.refused() -- a throw this client may be showing will not come
		if msg.Reason == "NoFrags" then
			Label.show(Config.Label.None)
		end
	elseif msg.Phase == "FragmentsHit" then
		RedEdge.pulse() -- fragments reached this player's character: the red screen-edge pulse (presentation only)
	end
end)

FxIn.OnClientEvent:Connect(function(msg: any)
	if typeof(msg) ~= "table" or typeof(msg.p) ~= "Vector3" then
		return
	end
	if RunService:IsStudio() then
		table.insert(fxReceived, { At = os.clock(), Id = msg.Id, p = msg.p })
		while #fxReceived > 64 do
			table.remove(fxReceived, 1)
		end
	end
	Effect.play(msg.p)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == Config.Key then
		press()
	end
end)

Command:FireServer("Sync")

if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "GrenadeClientDebug"
	hook.OnInvoke = function(cmd: string, arg: any): any
		if cmd == "press" then
			return press()
		elseif cmd == "view" then
			local v = Label.read()
			v.Left = left
			v.Presenting = Presentation.busy()
			v.Presentations = Presentation.Count
			v.EffectsPlayed = Effect.Played
			v.EffectRigs = Effect.size()
			v.RedEdge = RedEdge.read()
			v.Lever = Presentation.leverInfo()
			return v
		elseif cmd == "redEdge" then
			RedEdge.pulse() -- Studio test hook: show the pulse (captures / timing)
			return RedEdge.read()
		elseif cmd == "redEdgeHold" then
			RedEdge.hold(arg) -- Studio test hook: hold the tint at strength arg (nil: back to the decay)
			return RedEdge.read()
		elseif cmd == "freezeThrow" then
			return Presentation.freeze(arg) -- Studio test hook: hold the throw presentation at t seconds (nil releases)
		elseif cmd == "prediction" then
			return Prediction.read()
		elseif cmd == "predictionClear" then
			Prediction.clear()
			return true
		elseif cmd == "predictReleased" then
			return Prediction.released(arg) -- Studio test hook: a forged / malformed "Released" message (local only)
		elseif cmd == "lowering" then
			return { Amount = WeaponLowering.amount(os.clock()), Count = WeaponLowering.Count }
		elseif cmd == "lowerPlay" then
			WeaponLowering.play(arg or Config.Throw.LowerWeapon, os.clock()) -- Studio test hook: a lowering alone (no throw)
			return true
		elseif cmd == "messages" then
			return messages
		elseif cmd == "fx" then
			return fxReceived
		elseif cmd == "clear" then
			table.clear(messages)
			table.clear(fxReceived)
			return true
		end
		return nil
	end
	hook.Parent = script
end
