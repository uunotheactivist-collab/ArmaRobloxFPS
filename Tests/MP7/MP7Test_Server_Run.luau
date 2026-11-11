--!strict
-- Focused MP7 test, server side (Studio only; delete the MP7Test folders to remove it). Driven through execute_luau
-- (Server datamodel); the client half is StarterPlayerScripts.MP7Test.Run. Range: Workspace.MP7Test
-- (Roblox/Tests/MP7/build_range.luau). Reads the running server only through its Studio debug hooks.
--   Run.place(where?, offset?, face?)   server teleport to a lane point ("fire" F = (450, 0, -330), "reload", "move")
--   Run.spawnBots()                     fresh REACT1 copies on the five bot spots
--   Run.botState(name)                  the bot's Body* attributes (Server.BodyState) and health
--   Run.clearShots() / Run.shots()      the server's own traces of the player's shots (Server.Ballistics RecentResults)
--   Run.blood(cmd?)                     Server.Blood counts
--   Run.netStart() / Run.netStop()      count every client -> server remote event
--   Run.kill() / Run.alive()            kill the player's character (death test) / its state
--   Run.shotCost(n)                     server cost of one MP7 shot (Server.WeaponShot.resolve against the wall target)
--   Run.remotes()                       remote inventory

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Run = {}
Run.Points = {
	fire = Vector3.new(450, 0, -330),
	reload = Vector3.new(480, 0, -330),
	move = Vector3.new(520, 0, -335),
}

local function hook(path: { string }): BindableFunction
	local cur: Instance = ServerScriptService
	for _, n in path do
		cur = cur:WaitForChild(n)
	end
	return cur :: BindableFunction
end

function Run.player(): Player
	return Players:GetPlayers()[1]
end

function Run.place(where: string?, offset: Vector3?, face: Vector3?): CFrame?
	local p = Run.player()
	local c = p.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then
		return nil
	end
	local above = hum.HipHeight + root.Size.Y / 2
	local pos = Run.Points[where or "fire"] + (offset or Vector3.zero) + Vector3.new(0, above + 0.05, 0)
	local dir = face or Vector3.new(0, 0, 1)
	local cf = CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
	hook({ "Server", "Movement", "MovementServer", "MovementDebug" }):Invoke("teleport", p, cf)
	return cf
end

Run.BotSpots = {
	MP7_CLOSE = Vector3.new(450, 3, -320),
	MP7_MEDIUM = Vector3.new(454, 3, -280),
	MP7_DISTANT = Vector3.new(450, 3, -180),
	MP7_BEHIND_PEN = Vector3.new(440, 3, -302),
	MP7_BEHIND_SOLID = Vector3.new(462, 3, -302),
}

function Run.spawnBots(names: { string }?): { string }
	local folder = workspace:WaitForChild("MP7Test"):WaitForChild("Bots")
	local template = ServerStorage:WaitForChild("HitReactionTemplates"):WaitForChild("REACT1")
	local out = {}
	for name, pos in Run.BotSpots do
		if names == nil or table.find(names, name) then
			local old = folder:FindFirstChild(name)
			if old then
				old:Destroy()
			end
			local bot = template:Clone()
			bot.Name = name
			bot:PivotTo(CFrame.new(pos))
			bot.Parent = folder
			table.insert(out, name)
		end
	end
	return out
end

function Run.bot(name: string): Model?
	local folder = workspace:FindFirstChild("MP7Test")
	local bots = folder and folder:FindFirstChild("Bots")
	return if bots then bots:FindFirstChild(name) :: Model? else nil
end

function Run.botState(name: string): any
	local m = Run.bot(name)
	if not m then
		return nil
	end
	local out = {}
	for k, v in m:GetAttributes() do
		if string.sub(k, 1, 4) == "Body" then
			out[k] = v
		end
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	out.Health = if hum then hum.Health else nil
	local head = m:FindFirstChild("Head") :: BasePart?
	out.HeadPosition = if head then head.Position else nil
	local torso = (m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso")) :: BasePart?
	out.TorsoPosition = if torso then torso.Position else nil
	return out
end

local function ballistics(): BindableFunction
	return hook({ "Server", "Ballistics", "RecentResults" })
end

function Run.clearShots(): number
	return ballistics():Invoke("clear")
end

-- The server's own trace for each shot: origin (server head), direction (client aim), where it ended, what it hit.
function Run.shots(): { any }
	local out = {}
	for _, r in ballistics():Invoke() do
		local tr = r.Trace
		local events = {}
		for _, e in tr.Events do
			table.insert(events, {
				kind = e.Kind,
				part = if e.Part then e.Part:GetFullName() else nil,
				position = e.Position,
				surface = e.Surface,
				reason = e.Reason,
				budget = e.Budget,
			})
		end
		local dmg = {}
		for _, d in r.Damage or {} do
			local b = d.Body
			table.insert(dmg, {
				model = if d.Humanoid and d.Humanoid.Parent then d.Humanoid.Parent.Name else nil,
				part = d.Part,
				location = if b then b.Location else nil,
				zone = if b then b.Zone else nil,
				wound = if b then b.Wound else nil,
				phaseBefore = if b then b.PhaseBefore else nil,
				phaseAfter = if b then b.PhaseAfter else nil,
			})
		end
		table.insert(out, {
			player = r.Player,
			weapon = r.Weapon,
			at = r.At,
			origin = tr.Origin,
			direction = tr.Direction,
			endPosition = tr.EndPosition,
			stoppedBy = if tr.StoppedBy then tr.StoppedBy:GetFullName() else nil,
			events = events,
			damage = dmg,
		})
	end
	return out
end

function Run.blood(cmd: string?, arg: any?): any
	return hook({ "Server", "Blood", "BloodServer", "BloodDebug" }):Invoke(cmd or "counts", arg)
end

-- Network traffic counter (attributes on ServerStorage.MP7NetCounter: each execute_luau call has its own module copy).
local function counter(): Folder
	local f = ServerStorage:FindFirstChild("MP7NetCounter") :: Folder?
	if not f then
		local nf = Instance.new("Folder")
		nf.Name = "MP7NetCounter"
		nf.Parent = ServerStorage
		f = nf
	end
	return f :: Folder
end

function Run.netStart(): number
	local f = counter()
	for k in f:GetAttributes() do
		f:SetAttribute(k, nil)
	end
	local n = 0
	for _, d in ReplicatedStorage:GetDescendants() do
		if d:IsA("RemoteEvent") then
			n += 1
			local key = string.gsub(d:GetFullName(), "%.", "_")
			if not d:GetAttribute("MP7NetCounted") then
				d:SetAttribute("MP7NetCounted", true)
				d.OnServerEvent:Connect(function()
					if f:GetAttribute("Counting") then
						f:SetAttribute(key, (f:GetAttribute(key) or 0) + 1)
					end
				end)
			end
		end
	end
	f:SetAttribute("Counting", true)
	return n
end

function Run.netStop(): { [string]: number }
	local f = counter()
	f:SetAttribute("Counting", false)
	local out = {}
	for k, v in f:GetAttributes() do
		if k ~= "Counting" and typeof(v) == "number" and v > 0 then
			out[k] = v
		end
	end
	return out
end

function Run.kill(): boolean
	local c = Run.player().Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = 0
		return true
	end
	return false
end

function Run.alive(): any
	local c = Run.player().Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	return { character = c ~= nil, health = if hum then hum.Health else nil }
end

-- Server cost of an MP7 shot: Server.WeaponShot.resolve (trace, damage / body state, blood, record) from the player's
-- head at the WallTarget, n times. A separate module copy (execute_luau), same code.
function Run.shotCost(n: number): any
	local WeaponShot = require(ServerScriptService:WaitForChild("Server"):WaitForChild("WeaponShot")) :: any
	local WeaponRegistry = require(ReplicatedStorage.Shared.WeaponRegistry) :: any
	local cfg = WeaponRegistry.get("MP7")
	local p = Run.player()
	local c = p.Character :: Model
	local hum = c:FindFirstChildOfClass("Humanoid") :: Humanoid
	local head = c:FindFirstChild("Head") :: BasePart
	local target = workspace.MP7Test.FiringLane.WallTarget :: BasePart
	local times = {}
	for i = 1, n do
		local aim = (target.Position + Vector3.new(((i % 5) - 2) * 0.5, ((i // 5) % 5 - 2) * 0.5, 0) - head.Position).Unit
		local t0 = os.clock()
		WeaponShot.resolve({ Player = p, Character = c, Humanoid = hum, Name = p.Name }, "MP7", cfg, head.Position, aim)
		table.insert(times, (os.clock() - t0) * 1000)
	end
	table.sort(times)
	local sum = 0
	for _, t in times do
		sum += t
	end
	return { n = n, meanMs = sum / n, medianMs = times[n // 2 + 1], maxMs = times[n] }
end

function Run.remotes(): { string }
	local out = {}
	for _, d in game:GetDescendants() do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then
			table.insert(out, d:GetFullName())
		end
	end
	table.sort(out)
	return out
end

return Run
