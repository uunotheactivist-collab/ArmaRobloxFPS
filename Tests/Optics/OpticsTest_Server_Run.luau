--!strict
-- Focused optics test, server side (Studio only; delete the OpticsTest folders to remove it). Driven through
-- execute_luau (Server datamodel); the client half is StarterPlayerScripts.OpticsTest.Run. Range: Workspace.OpticsTest
-- (Roblox/Tests/Optics/build_range.luau). Reads the running server only through its Studio debug hooks.
--   Run.place(offset?, face?)      server teleport to the firing point F = (0, 0, 400) (+ offset), facing +Z
--   Run.spawnBots()                fresh REACT1 copies on the four bot spots
--   Run.botState(name)             the bot's Body* attributes (Server.BodyState)
--   Run.clearShots() / Run.shots() the server's own traces for the player's shots (Server.Ballistics RecentResults)
--   Run.blood(cmd?)                Server.Blood counts
--   Run.netStart() / Run.netStop() count every client -> server remote event (network traffic while scoped)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Run = {}
Run.F = Vector3.new(0, 0, 400)

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

function Run.place(offset: Vector3?, face: Vector3?): CFrame?
	local p = Run.player()
	local c = p.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then
		return nil
	end
	local above = hum.HipHeight + root.Size.Y / 2
	local pos = Run.F + (offset or Vector3.zero) + Vector3.new(0, above + 0.05, 0)
	local dir = face or Vector3.new(0, 0, 1)
	local cf = CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
	hook({ "Server", "Movement", "MovementServer", "MovementDebug" }):Invoke("teleport", p, cf)
	return cf
end

Run.BotSpots = {
	OPT_NEAR = Vector3.new(0, 3, 425),
	OPT_MEDIUM = Vector3.new(6, 3, 500),
	OPT_COVER = Vector3.new(-6, 3, 560),
	OPT_DISTANT = Vector3.new(0, 3, 700),
}

function Run.spawnBots(): { string }
	local folder = workspace:WaitForChild("OpticsTest"):WaitForChild("Bots")
	local template = ServerStorage:WaitForChild("HitReactionTemplates"):WaitForChild("REACT1")
	local out = {}
	for name, pos in Run.BotSpots do
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
	return out
end

function Run.bot(name: string): Model?
	local folder = workspace:FindFirstChild("OpticsTest")
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
	local head = m:FindFirstChild("Head") :: BasePart?
	out.HeadPosition = if head then head.Position else nil
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
		local enters = {}
		for _, e in tr.Events do
			if e.Kind == "Enter" or e.Kind == "Stop" then
				table.insert(enters, {
					kind = e.Kind,
					part = if e.Part then e.Part:GetFullName() else nil,
					position = e.Position,
					surface = e.Surface,
				})
			end
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
			events = enters,
			damage = dmg,
		})
	end
	return out
end

function Run.blood(cmd: string?, arg: any?): any
	return hook({ "Server", "Blood", "BloodServer", "BloodDebug" }):Invoke(cmd or "counts", arg)
end

-- Network traffic: count every client -> server remote event while counting is on. The counts live as attributes on
-- ServerStorage.OpticsNetCounter, because each execute_luau call gets its own copy of this module; the listeners are
-- connected once per play session and only count while the folder's Counting attribute is true.
local function counter(): Folder
	local f = ServerStorage:FindFirstChild("OpticsNetCounter") :: Folder?
	if not f then
		local nf = Instance.new("Folder")
		nf.Name = "OpticsNetCounter"
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
			if not d:GetAttribute("OpticsNetCounted") then
				d:SetAttribute("OpticsNetCounted", true)
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

-- Remote inventory (the optic must not add any).
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
