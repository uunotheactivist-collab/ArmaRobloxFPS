--!strict
-- Body interaction server (pulse check, drag). Basis: ReferenceAnalysis/BodyInteraction/BodyInteraction_Analysis.md.
-- Values: Shared.Config.BodyInteraction (tagged).
--
-- Trust model (as WeaponServer): a client only ASKS, through Shared.Remotes.BodyInteract:
--   ("PulseCheck", body)  ("Drag", body)  ("LetGo")  ("Cancel")
-- Everything else is the server's: whether the player is alive, whether the target is a BodyState body in the world,
-- the distance (from the server's copy of the character), line of sight, one interaction at a time, the request rate,
-- who holds a body, the 3.00 s timing, the pulse result (from BodyState), the drag physics and the blood trail. Results
-- go back to that player only through Shared.Remotes.BodyInteractState; anything a client fires on that remote is
-- ignored (counted for the tests). No remote accepts a position, a state, a result or a player.
--
-- It consumes the accepted systems and changes none of them: BodyState (read), ActiveRagdoll (the body stays its
-- ragdoll), Blood (Server.Blood.Trails for the drag trail). One Heartbeat connection runs only while any interaction
-- is active.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("BodyInteraction"))
local BodyState = require(script.Parent.Parent:WaitForChild("BodyState"))
local Trails = require(script.Parent.Parent:WaitForChild("Blood"):WaitForChild("Trails"))
local Eligibility = require(script.Parent:WaitForChild("Eligibility"))
local PulseCheck = require(script.Parent:WaitForChild("PulseCheck"))
local Drag = require(script.Parent:WaitForChild("Drag"))

local LOG = true

local Remotes = Shared:WaitForChild("Remotes")
local function remote(name: string): RemoteEvent
	local r = Remotes:FindFirstChild(name)
	if r and r:IsA("RemoteEvent") then
		return r
	end
	local n = Instance.new("RemoteEvent")
	n.Name = name
	n.Parent = Remotes
	return n
end
local Request = remote(Config.Remote)
local StateOut = remote(Config.StateRemote)

type Active = {
	Kind: string, -- "PulseCheck" | "Drag"
	Target: Model,
	Start: number,
	Ends: number?,
	Hold: Drag.Hold?,
}

local states: { [Player]: Active } = {}
local lastRequest: { [Player]: number } = {}
local holders: { [Model]: any } = {} -- body → the Player dragging it (or a Studio test reservation)
local loop: RBXScriptConnection? = nil
local counters = { Requests = 0, Accepted = 0, Rejected = 0, Results = 0, Interrupted = 0, Released = 0, StateRemoteCalls = 0 }
local recent: { any } = {} -- Studio only

local ACTIONS = { PulseCheck = true, Drag = true, LetGo = true, Cancel = true }

local function log(message: string)
	if LOG then
		print("[Interact] " .. message)
	end
end

local function record(entry: any)
	if not RunService:IsStudio() then
		return
	end
	entry.At = os.clock()
	table.insert(recent, entry)
	while #recent > 64 do
		table.remove(recent, 1)
	end
end

local function send(player: Player, msg: any)
	if player.Parent then
		StateOut:FireClient(player, msg)
	end
end

local function reject(player: Player, action: string, reason: string, target: any?)
	counters.Rejected += 1
	local name = if typeof(target) == "Instance" then (target :: Instance):GetFullName() else tostring(target)
	log(`{player.Name} {action} rejected: {reason} ({name})`)
	record({ Player = player.Name, Action = action, Outcome = "Rejected", Reason = reason, Target = name })
	send(player, { Kind = action, Phase = "Rejected", Reason = reason })
end

local onStep: (number) -> ()

local function startLoop()
	if not loop then
		loop = RunService.Heartbeat:Connect(function(dt)
			onStep(dt)
		end)
	end
end

local function stopLoopIfIdle()
	if loop and next(states) == nil then
		loop:Disconnect()
		loop = nil
	end
end

-- End a player's interaction. phase: "Result" | "Interrupted" | "Released".
local function finish(player: Player, a: Active, phase: string, reason: string?, extra: any?)
	if states[player] ~= a then
		return
	end
	states[player] = nil
	if a.Kind == "Drag" then
		local hold = a.Hold
		if hold then
			Drag.release(hold)
		end
		Trails.finish(a.Target)
		if holders[a.Target] == player then
			holders[a.Target] = nil
		end
		if a.Target.Parent then
			a.Target:SetAttribute(Config.DraggedAttribute, nil)
		end
		counters.Released += 1
	elseif phase == "Interrupted" then
		counters.Interrupted += 1
	end
	local msg: any = { Kind = a.Kind, Phase = phase, Reason = reason, Target = a.Target }
	if extra then
		for k, v in extra do
			msg[k] = v
		end
	end
	send(player, msg)
	log(`{player.Name} {a.Kind} {phase}{if reason then " (" .. reason .. ")" else ""} on {a.Target.Name}`
		.. (if extra and extra.Text then ": " .. extra.Text else ""))
	record({
		Player = player.Name,
		Action = a.Kind,
		Outcome = phase,
		Reason = reason,
		Target = a.Target:GetFullName(),
		Seconds = os.clock() - a.Start,
		Result = extra and extra.Result,
		Text = extra and extra.Text,
		Phase = extra and extra.BodyPhase,
	})
	stopLoopIfIdle()
end

onStep = function(_dt: number)
	local now = os.clock()
	for player, a in states do
		local character, root, _, perr = Eligibility.player(player)
		if perr or not character or not root then
			finish(player, a, if a.Kind == "Drag" then "Released" else "Interrupted", perr)
			continue
		end
		local model, berr = Eligibility.body(a.Target)
		if berr or not model then
			finish(player, a, if a.Kind == "Drag" then "Released" else "Interrupted", "target " .. tostring(berr))
			continue
		end
		if a.Kind == "PulseCheck" then
			local dist = Eligibility.distance(model, root.Position)
			if dist > Config.KeepStuds then
				finish(player, a, "Interrupted", "out of range")
			elseif a.Ends and now >= a.Ends then
				counters.Results += 1
				local key, text, phase = PulseCheck.result(model)
				finish(player, a, "Result", nil, { Result = key, Text = text, BodyPhase = phase })
			end
		else
			local hold = a.Hold :: Drag.Hold
			local why = if Drag.isPhysical(model) then Drag.update(hold, character) else "not physical"
			if why then
				finish(player, a, "Released", why)
			else
				Trails.step(model)
			end
		end
	end
end

local function onRequest(player: Player, action: any, target: any)
	counters.Requests += 1
	if typeof(action) ~= "string" or not ACTIONS[action] then
		return reject(player, tostring(action), "unknown action", target)
	end
	local now = os.clock()
	if now - (lastRequest[player] or -math.huge) < Config.RequestInterval then
		return reject(player, action, "too fast", target)
	end
	lastRequest[player] = now
	local current = states[player]
	if action == "LetGo" then
		if current and current.Kind == "Drag" then
			counters.Accepted += 1
			finish(player, current, "Released", "let go")
		else
			reject(player, action, "not dragging")
		end
		return
	elseif action == "Cancel" then
		if current and current.Kind == "PulseCheck" then
			counters.Accepted += 1
			finish(player, current, "Interrupted", "cancelled")
		else
			reject(player, action, "not checking")
		end
		return
	end
	if current then
		return reject(player, action, "busy: " .. current.Kind, target)
	end
	local character, root, _, perr = Eligibility.player(player)
	if perr or not character or not root then
		return reject(player, action, perr or "no character", target)
	end
	local model, berr = Eligibility.body(target)
	if berr or not model then
		return reject(player, action, berr or "not a body", target)
	end
	local dist, part = Eligibility.distance(model, root.Position)
	if dist > Config.StartStuds or not part then
		return reject(player, action, `out of range ({math.floor(dist * 10 + 0.5) / 10} studs)`, model)
	end
	if Config.LineOfSight and not Eligibility.lineOfSight(character, model, part) then
		return reject(player, action, "no line of sight", model)
	end

	if action == "PulseCheck" then
		local a: Active = { Kind = "PulseCheck", Target = model, Start = now, Ends = now + Config.Pulse.Seconds, Hold = nil }
		states[player] = a
		counters.Accepted += 1
		send(player, { Kind = "PulseCheck", Phase = "Started", Target = model, Seconds = Config.Pulse.Seconds })
		log(`{player.Name} PulseCheck started on {model.Name}`)
		record({ Player = player.Name, Action = action, Outcome = "Started", Target = model:GetFullName() })
		startLoop()
		return
	end

	-- Drag: a downed (BodyState's own stance) physical ragdoll that nobody else holds
	local s = BodyState.get(model)
	if not s or s.Stance ~= "DOWN" then
		return reject(player, action, "not down", model)
	end
	if not Drag.isPhysical(model) then
		return reject(player, action, "not a physical body", model)
	end
	if holders[model] ~= nil then
		return reject(player, action, "already held", model)
	end
	local hold = Drag.grab(player, character, model)
	if not hold then
		return reject(player, action, "no grip", model)
	end
	holders[model] = player
	model:SetAttribute(Config.DraggedAttribute, player.UserId)
	Trails.begin(model)
	local a: Active = { Kind = "Drag", Target = model, Start = now, Ends = nil, Hold = hold }
	states[player] = a
	counters.Accepted += 1
	send(player, { Kind = "Drag", Phase = "Started", Target = model })
	log(`{player.Name} Drag started on {model.Name} ({s.Phase}, mass {math.floor(hold.Mass * 10 + 0.5) / 10}, turned {math.floor(hold.Turned + 0.5)}°)`)
	record({ Player = player.Name, Action = action, Outcome = "Started", Target = model:GetFullName(), Phase = s.Phase, Turned = hold.Turned })
	startLoop()
end

Request.OnServerEvent:Connect(onRequest)
StateOut.OnServerEvent:Connect(function()
	counters.StateRemoteCalls += 1 -- never acted on: state flows server → client only
end)

Players.PlayerRemoving:Connect(function(player)
	local a = states[player]
	if a then
		finish(player, a, if a.Kind == "Drag" then "Released" else "Interrupted", "player left")
	end
	lastRequest[player] = nil
end)

-- Studio-only test hook (server BindableFunction; clients can't reach it):
--   Invoke("status") / Invoke("recent") / Invoke("clear") / Invoke("holds")
--   Invoke("reserve", body, on)  hold a body for a pretend second player (tests the ownership rule with one client)
if RunService:IsStudio() then
	local bf = Instance.new("BindableFunction")
	bf.Name = "InteractionDebug"
	bf.OnInvoke = function(cmd: string, a: any, b: any): any
		if cmd == "status" then
			local list = {}
			for player, s in states do
				table.insert(list, { Player = player.Name, Kind = s.Kind, Target = s.Target.Name, Seconds = os.clock() - s.Start })
			end
			local held = {}
			for m, who in holders do
				table.insert(held, { Body = m.Name, By = if typeof(who) == "Instance" then who.Name else tostring(who) })
			end
			return { Active = list, Held = held, Loop = loop ~= nil, Counters = table.clone(counters), Trails = Trails.stats() }
		elseif cmd == "recent" then
			return recent
		elseif cmd == "holds" then
			local list = {}
			for player, s in states do
				if s.Hold then
					table.insert(list, Drag.describe(s.Hold, player.Character))
				end
			end
			return list
		elseif cmd == "clear" then
			table.clear(recent)
			for k in counters do
				counters[k] = 0
			end
			table.clear(Trails.Recent)
			return true
		elseif cmd == "reserve" then
			if typeof(a) == "Instance" and a:IsA("Model") then
				holders[a] = if b then "OtherPlayer(test)" else nil
				return true
			end
			return false
		end
		return { Error = "unknown command" }
	end
	bf.Parent = script
end
