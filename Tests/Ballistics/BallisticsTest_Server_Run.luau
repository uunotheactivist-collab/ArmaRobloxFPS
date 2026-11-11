--!strict
-- Focused ballistic test, server side (Studio only; delete the BallisticsTest folders to remove it).
-- Uses the range Workspace.BallisticTest (Roblox/Tests/Ballistics/build_range.luau) and the shared Server.Ballistics.
--   Run.unit({ "M4", "AK" }, repeats)  direct traces from each lane's eye point to its target with each weapon's
--                                       config values (no client involved)
--   Run.arm()                           before the client fires real shots (StarterPlayerScripts.BallisticsTest):
--                                       clears the server's recent results and watches the lane targets' health
--                                       (recorded, then restored to full after each hit)
--   Run.report()                        groups the server's own records of those shots by weapon and lane and checks
--                                       them against the expectations below
--   Run.draw(n) / Run.clearDraw()       Studio debug: draws the last n server traces as thin temporary lines with
--                                       entry/exit/stop markers (test visual only; removed by clearDraw)
-- Expectations:
--   A: Enter Target -> Exit Target -> Enter Backstop -> Stop (NonPenetrable); the target is hit once.
--   B: Enter Penetrable wall -> Exit wall (0.5 studs) -> Enter Target -> Exit -> Enter Backstop -> Stop; target hit.
--   C: Enter NonPenetrable wall -> Stop; no target hit, target health unchanged.
--   Every continued segment starts at its exit point and keeps the shot's direction.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Ballistics = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Ballistics"))
local WeaponRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponRegistry"))

local Run = {}
-- The running server's records (this test runs in its own script context: see Server.Ballistics).
local function recent(cmd: string?): any
	local bf = ServerScriptService.Server.Ballistics:WaitForChild("RecentResults", 5) :: BindableFunction
	return bf:Invoke(cmd)
end
local LANE_BY_X: { [number]: string } = { [-200] = "A", [-175] = "B", [-150] = "C" }
local EYE_HEIGHT = 4.5 -- studs above the ground: an R6 head centre (the server traces from the shooter's head)

local function range(): Folder
	return workspace:WaitForChild("BallisticTest") :: Folder
end

local function lane(name: string): Folder
	return range():WaitForChild("Lane" .. name) :: Folder
end

local function targetOf(name: string): Model
	return lane(name):WaitForChild("Target") :: Model
end

local function r3(x: number): number
	return math.round(x * 1000) / 1000
end

local function laneOf(origin: Vector3): string?
	for x, n in LANE_BY_X do
		if math.abs(origin.X - x) < 3 then
			return n
		end
	end
	return nil
end

-- Compact description of a trace + the checks for its lane.
local function check(name: string, trace: any, damage: { any }?): any
	local seq = {}
	for _, e in trace.Events do
		local label = e.Kind
		if e.Part then
			label ..= ":" .. e.Part.Name
		end
		if e.Kind == "Exit" then
			label ..= string.format("(t=%.3f)", e.Thickness)
		elseif e.Kind == "Stop" then
			label ..= "(" .. tostring(e.Reason) .. ")"
		end
		table.insert(seq, label)
	end
	local target = targetOf(name)
	local hitTarget = false
	for _, t in trace.Targets do
		if t.Humanoid.Parent == target then
			hitTarget = true
		end
	end
	-- continued segments: each outside segment after an exit starts at that exit (+ offset) in the same direction
	local collinear, continuedOk = true, true
	for i, sgt in trace.Segments do
		local d = sgt.To - sgt.From
		if d.Magnitude > 1e-3 and d.Unit:Dot(trace.Direction) < 0.99999 then
			collinear = false
		end
		if i > 1 and not sgt.Inside then
			local prev = trace.Segments[i - 1]
			if prev.Inside and (sgt.From - prev.To).Magnitude > 0.02 then
				continuedOk = false
			end
		end
	end
	local expected
	if name == "A" then
		expected = { "Enter:Torso", "Exit:Torso", "Enter:Backstop", "Stop:Backstop" }
	elseif name == "B" then
		expected = { "Enter:PenetrableWall", "Exit:PenetrableWall", "Enter:Torso", "Exit:Torso", "Enter:Backstop", "Stop:Backstop" }
	else
		expected = { "Enter:NonPenetrableWall", "Stop:NonPenetrableWall" }
	end
	local seqOk = #seq == #expected
	for i, want in expected do
		if not seq[i] or string.sub(seq[i], 1, #want) ~= want then
			seqOk = false
		end
	end
	local wallThickness = nil
	for _, e in trace.Events do
		if e.Kind == "Exit" and e.Part and e.Part.Name == "PenetrableWall" then
			wallThickness = r3(e.Thickness)
		end
	end
	local pass = seqOk and collinear and continuedOk and (hitTarget == (name ~= "C"))
		and (name ~= "B" or (wallThickness ~= nil and math.abs(wallThickness - 0.5) < 0.02))
	local dealt = nil
	if damage then
		dealt = 0
		for _, d in damage do
			if d.Humanoid.Parent == target then
				dealt += d.Dealt
			end
		end
	end
	return {
		lane = name,
		pass = pass,
		sequence = table.concat(seq, " > "),
		targetHit = hitTarget,
		damageDealt = dealt,
		wallThickness = wallThickness,
		collinear = collinear,
		continuedFromExit = continuedOk,
		budgetLeft = r3(trace.Budget),
		endZ = r3(trace.EndPosition.Z),
		stoppedBy = trace.StoppedBy and trace.StoppedBy.Name or nil,
	}
end

function Run.unit(weaponIds: { string }, repeats: number?): any
	local out = {}
	for _, id in weaponIds do
		local cfg = WeaponRegistry.get(id)
		local w = { Range = cfg.Fire.Range, PenetrationStuds = cfg.Ballistics.PenetrationStuds }
		for _, name in { "A", "B", "C" } do
			local spot = (lane(name):WaitForChild("ShooterSpot") :: BasePart).Position
			local eye = Vector3.new(spot.X, EYE_HEIGHT, spot.Z)
			local aim = (targetOf(name):WaitForChild("Torso") :: BasePart).Position
			local passes, last = 0, nil
			for _ = 1, repeats or 1 do
				local trace = Ballistics.trace(eye, aim - eye, w, {})
				last = check(name, trace, nil)
				if last.pass then
					passes += 1
				end
			end
			last.weapon = id
			last.passes = passes .. "/" .. (repeats or 1)
			table.insert(out, last)
		end
	end
	return out
end

local watch: { RBXScriptConnection } = {}
local healthLog: { any } = {}

function Run.arm(): string
	for _, c in watch do
		c:Disconnect()
	end
	table.clear(watch)
	table.clear(healthLog)
	recent("clear")
	for _, name in { "A", "B", "C" } do
		local h = targetOf(name):FindFirstChildOfClass("Humanoid") :: Humanoid
		h.Health = h.MaxHealth
		local last = h.Health
		table.insert(watch, h.HealthChanged:Connect(function(v)
			if v < last then
				table.insert(healthLog, { lane = name, from = last, to = v, at = os.clock() })
				task.delay(0.15, function()
					h.Health = h.MaxHealth
				end)
			end
			last = h.Health
		end))
	end
	return "armed"
end

function Run.report(): any
	local groups: { [string]: any } = {}
	local records = recent()
	for _, rec in records do
		local name = laneOf(rec.Trace.Origin)
		if name then
			local key = rec.Weapon .. " " .. name
			local g = groups[key] or { weapon = rec.Weapon, lane = name, shots = 0, passes = 0, damage = {}, sample = nil }
			groups[key] = g
			local c = check(name, rec.Trace, rec.Damage)
			g.shots += 1
			if c.pass then
				g.passes += 1
			end
			table.insert(g.damage, c.damageDealt)
			g.sample = c
		end
	end
	local hits = { A = 0, B = 0, C = 0 }
	for _, e in healthLog do
		hits[e.lane] += 1
	end
	local list = {}
	for _, g in groups do
		table.insert(list, g)
	end
	table.sort(list, function(a, b)
		return a.weapon .. a.lane < b.weapon .. b.lane
	end)
	return { groups = list, targetHealthDrops = hits, healthLog = healthLog, records = #records }
end

local drawn: Folder? = nil
function Run.clearDraw()
	if drawn then
		drawn:Destroy()
		drawn = nil
	end
end

function Run.draw(n: number): string
	Run.clearDraw()
	local f = Instance.new("Folder")
	f.Name = "BallisticDebug"
	local function line(a: Vector3, b: Vector3, color: Color3, width: number)
		local d = b - a
		if d.Magnitude < 1e-3 then
			return
		end
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Size = Vector3.new(width, width, d.Magnitude)
		p.CFrame = CFrame.lookAt(a + d / 2, b)
		p.Parent = f
	end
	local function dot(at: Vector3, color: Color3, size: number)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Size = Vector3.one * size
		p.Position = at
		p.Parent = f
	end
	local list = recent()
	for i = math.max(1, #list - n + 1), #list do
		local tr = list[i].Trace
		for _, sgt in tr.Segments do
			line(sgt.From, sgt.To, if sgt.Inside then Color3.fromRGB(255, 60, 60) else Color3.fromRGB(255, 220, 60), 0.06)
		end
		for _, e in tr.Events do
			if e.Kind == "Enter" then
				dot(e.Position, Color3.fromRGB(255, 60, 60), 0.35)
			elseif e.Kind == "Exit" then
				dot(e.Position, Color3.fromRGB(255, 150, 40), 0.35)
			elseif e.Kind == "Stop" then
				dot(e.Position, Color3.fromRGB(80, 160, 255), 0.5)
			end
		end
	end
	f.Parent = range()
	drawn = f
	return "drew " .. #f:GetChildren() .. " parts"
end

return Run
