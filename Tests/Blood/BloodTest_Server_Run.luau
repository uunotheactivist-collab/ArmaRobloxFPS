--!strict
-- Focused blood / impact test, server side (Studio only; delete the BloodTest folders to remove it). It checks what the
-- server made from REAL shots (fired by StarterPlayerScripts.HitReactionTest / BallisticsTest / BloodTest) against the
-- authoritative trace (Server.Ballistics.RecentResults) and the bodies, and that client attempts changed nothing.
--   Run.reset()            clear all blood, fresh REACT bots, clear the trace / body / blood records
--   Run.report(weapon)     body hits: positions, locations, stains, floor / wall marks, pools, ragdoll attachment
--   Run.deadHit()          after the client's shot at the dead REACT5: puff and marks, no bleeding mist
--   Run.world()            after the client's lane shots: penetrable / nonpenetrable impacts
--   Run.snapshot() / Run.security(before)   counts before / after the client's fake attempts
--   Run.orphans()          nothing left over: patches all hold marks, no empty guis, no parts inside bodies

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Run = {}

local function blood(...: any): any
	return (ServerScriptService.Server.Blood.BloodServer:WaitForChild("BloodDebug", 5) :: BindableFunction):Invoke(...)
end
local function traces(...: any): any
	return (ServerScriptService.Server.Ballistics:WaitForChild("RecentResults", 5) :: BindableFunction):Invoke(...)
end
local function bodyHook(...: any): any
	return (ServerScriptService.Server.BodyState:WaitForChild("BodyStateDebug", 5) :: BindableFunction):Invoke(...)
end
local function bot(i: number): Model
	return workspace:WaitForChild("HitReactionTest"):WaitForChild("Bot" .. i):WaitForChild("REACT" .. i) :: Model
end

local function stainCount(part: Instance): number
	local n = 0
	for _, g in part:GetChildren() do
		if g:IsA("SurfaceGui") and string.sub(g.Name, 1, 10) == "BloodStain" then
			for _, f in g:GetChildren() do
				if f:IsA("Frame") then
					n += 1
				end
			end
		end
	end
	return n
end

function Run.reset(): any
	blood("clear")
	traces("clear")
	bodyHook("clear")
	local templates = ServerStorage:WaitForChild("HitReactionTemplates")
	for i = 1, 7 do
		local f = workspace.HitReactionTest:WaitForChild(if i == 7 then "Pres1" else "Bot" .. i)
		local name = if i == 7 then "PRES1" else "REACT" .. i
		local old = f:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		templates:WaitForChild(name):Clone().Parent = f
	end
	task.wait(0.3)
	return blood("counts")
end

-- Body events of the recorded shots, by weapon.
local function bodyEvents(weapon: string?): { any }
	local out = {}
	for _, shot in blood("recent") do
		if not weapon or shot.Weapon == weapon then
			for _, e in shot.Events do
				if e.t == "body" then
					table.insert(out, e)
				end
			end
		end
	end
	return out
end

function Run.report(weapon: string): any
	local checks = {}
	local function check(name: string, ok: boolean, detail: any?)
		table.insert(checks, { test = name, pass = ok, detail = detail })
	end
	local events = bodyEvents(weapon)
	-- 1 every trace target hit has a body effect at exactly the trace's own part and point (nothing else decides it)
	local targets, matched = 0, 0
	for _, tr in traces() do
		if tr.Weapon == weapon then
			for _, t in tr.Trace.Targets do
				if t.Part:IsDescendantOf(workspace.HitReactionTest) then
					targets += 1
					for _, e in events do
						if e.part == t.Part and (e.p - t.Position).Magnitude < 1e-4 then
							matched += 1
							break
						end
					end
				end
			end
		end
	end
	check(`{weapon}: body effects at the authoritative hit points`, targets > 0 and matched == targets, { targets = targets, matched = matched })
	-- 2 locations: the effect sits on the part BodyHit labelled, and that part carries a stain
	local want = {
		{ 1, "RightUpperArm", "rightarm" },
		{ 2, "LowerTorso", "abdomen" },
		{ 3, "UpperTorso", "chest" },
		{ 4, "UpperTorso", "chest" },
		{ 5, "Head", "head" },
		{ 6, "LeftUpperLeg", "leftleg" },
		{ 6, "RightUpperLeg", "rightleg" },
	}
	for _, w in want do
		local m = bot(w[1])
		local part = m:FindFirstChild(w[2]) :: BasePart
		local found = false
		for _, e in events do
			if e.part == part and e.loc == w[3] then
				found = true
			end
		end
		check(`{weapon}: {w[3]} hit on {m.Name}.{w[2]} → effect there + stain`, found and stainCount(part) > 0,
			{ effect = found, stains = stainCount(part) })
	end
	-- 3 repeated hits: three chest hits on REACT4 → three effects, more stains
	local r4 = 0
	for _, e in events do
		if e.part and e.part.Parent == bot(4) then
			r4 += 1
		end
	end
	local s4 = stainCount(bot(4):FindFirstChild("UpperTorso") :: Instance)
	check(`{weapon}: repeated hits (REACT4 ×3)`, r4 >= 3 and s4 >= 3, { effects = r4, stains = s4 })
	-- 4 dying / 5 dead: a pool under every body that went down; bleeding mist on hits to living / dying bodies
	local pools = {}
	for _, p in blood("pools") do
		pools[p.Body] = p
	end
	local down = {}
	for i = 2, 6 do
		local m = bot(i)
		table.insert(down, { m.Name, m:GetAttribute("BodyPhase"), pools[m.Name] ~= nil })
	end
	local allPools = true
	for _, d in down do
		if not d[3] then
			allPools = false
		end
	end
	check(`{weapon}: a pool under every downed body (DYING and DEAD)`, allPools, down)
	local bleedOk = true
	for _, e in events do
		if e.part and e.part.Parent == bot(1) and e.bleed ~= true then
			bleedOk = false
		end
	end
	check(`{weapon}: hits on living / dying bodies bleed`, bleedOk)
	-- 6 floor / 7 wall
	local floorMarks, wallMarks, floorLift, wallHeight = 0, 0, {}, {}
	for _, p in blood("marks") do
		if string.find(p.Surface, "Baseplate") and p.Normal.Y > 0.99 then
			floorMarks += p.Count
			table.insert(floorLift, math.floor((p.Position.Y) * 1000 + 0.5) / 1000)
		elseif string.find(p.Surface, "HitReactionTest") and string.find(p.Surface, "Backstop") and p.Normal.Z > 0.99 then
			wallMarks += p.Count
			table.insert(wallHeight, math.floor(p.Position.Y * 10 + 0.5) / 10)
		end
	end
	check(`{weapon}: blood on the floor (patches 0.02–0.05 above it)`, floorMarks > 0, { marks = floorMarks, heights = floorLift })
	check(`{weapon}: blood on the wall behind the bodies (torso height)`, wallMarks > 0, { marks = wallMarks, heights = wallHeight })
	-- 15 ragdoll: stains ride on body parts that have moved since the hit; no parts were added to any body
	local moved, carried = 0, 0
	for _, e in events do
		if e.part and e.part.Parent and (e.part.Position - e.p).Magnitude > 1.5 then
			moved += 1
			if stainCount(e.part) > 0 then
				carried += 1
			end
		end
	end
	local extraParts = 0
	local template = ServerStorage.HitReactionTemplates.REACT1
	local base = 0
	for _, d in template:GetDescendants() do
		if d:IsA("BasePart") then
			base += 1
		end
	end
	for i = 1, 6 do
		local n = 0
		for _, d in bot(i):GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		extraParts += n - base
	end
	check(`{weapon}: stains stay on ragdolled parts that moved; no parts added to bodies`, moved > 0 and carried == moved and extraParts == 0,
		{ moved = moved, carried = carried, extraParts = extraParts })
	local passes = 0
	for _, c in checks do
		if c.pass then
			passes += 1
		end
	end
	return { passed = passes, total = #checks, checks = checks }
end

-- After the client shot the DEAD REACT5 again.
function Run.deadHit(): any
	local m = bot(5)
	local last = nil
	for _, e in bodyEvents(nil) do
		if e.part and e.part.Parent == m then
			last = e
		end
	end
	return {
		phase = m:GetAttribute("BodyPhase"),
		effect = last ~= nil,
		bleed = last and last.bleed,
		pass = m:GetAttribute("BodyPhase") == "DEAD" and last ~= nil and last.bleed == false,
	}
end

-- After the client's lane shots (BallisticsTest lanes A / B / C).
function Run.world(): any
	local pen, penExit, nonpen = 0, 0, 0
	for _, shot in blood("recent") do
		for _, e in shot.Events do
			if e.t == "world" then
				if e.c == "Penetrable" then
					if e.out then
						penExit += 1
					else
						pen += 1
					end
				elseif e.c == "NonPenetrable" then
					nonpen += 1
				end
			end
		end
	end
	return { penetrableEntries = pen, penetrableExits = penExit, nonPenetrable = nonpen, pass = pen > 0 and penExit > 0 and nonpen > 0 }
end

function Run.snapshot(): any
	local c = blood("counts")
	local stains = 0
	for i = 1, 6 do
		for _, d in bot(i):GetDescendants() do
			if d:IsA("BasePart") then
				stains += stainCount(d)
			end
		end
	end
	return { Marks = c.Marks, Pools = c.Pools, Shots = c.Shots, ClientCalls = c.ClientCalls, Stains = stains, Phase1 = bot(1):GetAttribute("BodyPhase") }
end

-- before: Run.snapshot() taken before the client's fake attempts.
function Run.security(before: any): any
	local after = Run.snapshot()
	local lastShot = blood("recent")
	local forged = lastShot[#lastShot]
	local forgedBody = false
	if forged then
		for _, e in forged.Events do
			if e.t == "body" then
				forgedBody = true
			end
		end
	end
	return {
		before = before,
		after = after,
		clientCallsIgnored = after.ClientCalls > before.ClientCalls,
		noNewPools = after.Pools == before.Pools,
		noStainsWithoutHit = after.Stains == before.Stains,
		forgedShotHadNoBodyHit = not forgedBody,
		bodyStillAlive = after.Phase1 == "ALIVE" or after.Phase1 == nil,
		pass = after.ClientCalls > before.ClientCalls and after.Pools == before.Pools and after.Stains == before.Stains
			and not forgedBody and (after.Phase1 == "ALIVE" or after.Phase1 == nil),
	}
end

function Run.orphans(): any
	local folder = workspace:FindFirstChild("BloodMarks")
	local empty, parts = 0, 0
	if folder then
		for _, p in folder:GetChildren() do
			parts += 1
			local frames = 0
			for _, d in p:GetDescendants() do
				if d:IsA("Frame") then
					frames += 1
				end
			end
			if frames == 0 then
				empty += 1
			end
		end
	end
	local c = blood("counts")
	return { bloodParts = parts, emptyBloodParts = empty, patches = c.Patches, pools = c.Pools, growing = c.GrowingPools,
		pass = empty == 0 and parts == c.Patches + c.Pools }
end

return Run
