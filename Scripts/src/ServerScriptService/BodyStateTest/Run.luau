--!strict
-- Focused body-state test, server side (Studio only; delete the BodyStateTest folders to remove it).
-- It talks to the running server's Server.BodyState through its Studio-only hook BodyStateDebug: this code runs in
-- another script context and must not create its own copy of the state.
-- Range: Workspace.BodyStateTest (Roblox/Tests/BodyState/build_range.luau), bots BODY1–BODY6.
--   Run.unit()      server-side hits delivered exactly as the ballistic trace delivers them (part + point), with
--                   simulated time: locations, wounds, the phase and stance progression, DYING, DEAD, repeated hits,
--                   and invariants
--   Run.arm()       reset every bot and clear the records before the client fires real shots
--                   (StarterPlayerScripts.BodyStateTest)
--   Run.report(w)   checks the server's own records and the bots' published state after the client's run

local ServerScriptService = game:GetService("ServerScriptService")

local Run = {}

local function call(...: any): any
	local bf = ServerScriptService:WaitForChild("Server"):WaitForChild("BodyState"):WaitForChild("BodyStateDebug", 5) :: BindableFunction
	return bf:Invoke(...)
end

local function bot(i: number): Model
	return workspace:WaitForChild("BodyStateTest"):WaitForChild("Bot" .. i):WaitForChild("BODY" .. i) :: Model
end

-- Points in the part's own frame; the front face (toward the shooter) is local -Z.
local POINTS: { [string]: { any } } = {
	head = { "Head", Vector3.new(0, 0, -0.5) },
	throat = { "Torso", Vector3.new(0, 0.85, -0.5) },
	chest = { "Torso", Vector3.new(0, 0.4, -0.5) },
	abdomen = { "Torso", Vector3.new(0, -0.5, -0.5) },
	rightarm = { "Right Arm", Vector3.new(0, 0, -0.5) },
	leftarm = { "Left Arm", Vector3.new(0, 0, -0.5) },
	rightleg = { "Right Leg", Vector3.new(0, 0, -0.5) },
	leftleg = { "Left Leg", Vector3.new(0, 0, -0.5) },
}
local EXPECT: { [string]: { any } } = { -- location, zone, wound
	head = { "head", nil, "Brain" },
	throat = { "chest", "throat", "Throat" },
	chest = { "chest", nil, "Lung" },
	abdomen = { "abdomen", nil, "Gut" },
	rightarm = { "rightarm", nil, "Limb" },
	leftarm = { "leftarm", nil, "Limb" },
	rightleg = { "rightleg", nil, "Limb" },
	leftleg = { "leftleg", nil, "Limb" },
}
local ORDER = { ALIVE = 1, INJURED = 2, DYING = 3, DEAD = 4 }

local function hit(m: Model, name: string): any
	local p = POINTS[name]
	return call("hit", m, p[1], p[2])
end

-- Invariants that must hold for every snapshot; returns a list of violations.
local function invariants(s: any, prev: any?): { string }
	local bad = {}
	if prev and ORDER[s.Phase] < ORDER[prev.Phase] then
		table.insert(bad, `phase went back {prev.Phase} → {s.Phase}`)
	end
	if s.Phase == "DEAD" and (s.Life ~= 0 or s.Health ~= 0) then
		table.insert(bad, "DEAD with life/health > 0")
	end
	if s.Phase ~= "DEAD" and s.Health <= 0 then
		table.insert(bad, "health 0 while not DEAD")
	end
	if s.Life < 100 and s.Stance ~= "DOWN" and s.Phase ~= "DEAD" then
		table.insert(bad, "life drained while not down")
	end
	if s.Stance == "DOWN" and s.Phase ~= "DYING" and s.Phase ~= "DEAD" then
		table.insert(bad, "down but not dying")
	end
	if s.Behaviour and s.Stance ~= "DOWN" and s.Behaviour ~= "LIMP" then
		table.insert(bad, "behaviour before down")
	end
	if s.Reacting and s.Phase ~= "INJURED" then
		table.insert(bad, "flinch while " .. s.Phase)
	end
	if s.Phase == "ALIVE" and s.Hits > 0 then
		table.insert(bad, "ALIVE with hits")
	end
	return bad
end

function Run.unit(): any
	local out = {}
	local function check(name: string, cond: boolean, detail: any?)
		table.insert(out, { test = name, pass = cond, detail = detail })
	end
	local m1 = bot(1)

	-- U1 locations: every point gives its label, zone and wound (fresh body each time)
	for name, exp in EXPECT do
		call("reset", m1)
		local r = hit(m1, name)
		check("U1 location " .. name, r.Location == exp[1] and r.Zone == exp[2] and r.Wound == exp[3],
			`{r.Location}/{r.Zone or "-"}/{r.Wound} localY={r.LocalY}`)
	end
	-- U1b torso boundaries: chest/abdomen at local Y 0, throat band 0.3 studs below the top (Y 0.7)
	for _, case in { { 0.69, "chest", nil }, { 0.71, "chest", "throat" }, { 0.01, "chest", nil }, { -0.01, "abdomen", nil } } do
		call("reset", m1)
		local r = call("hit", m1, "Torso", Vector3.new(0, case[1], -0.5))
		check(`U1b torso y={case[1]}`, r.Location == case[2] and r.Zone == case[3], `{r.Location}/{r.Zone or "-"}`)
	end
	-- U1c distinct results: every location gives a distinct (location, zone) pair
	local seen, distinct = {}, true
	for name in EXPECT do
		call("reset", m1)
		local r = hit(m1, name)
		local key = `{r.Location}/{r.Zone or ""}`
		if seen[key] then
			distinct = false
		end
		seen[key] = true
	end
	check("U1c distinct recorded results", distinct)

	-- U2 limb (arm): INJURED, strength −3, flinch, stays up; strength recovers
	call("reset", m1)
	local r = hit(m1, "rightarm")
	local s = r.State
	check("U2 arm → INJURED standing", s.Phase == "INJURED" and s.Stance == "STANDING" and s.Wound == "Limb" and s.Strength == 97 and s.Reacting == true, s)
	s = call("advance", m1, 1.0)
	check("U2 arm recovers, flinch over", s.Phase == "INJURED" and s.Strength == 100 and s.Reacting == false, s)

	-- U3 gut: DYING at once (no flinch), falls in 0.53 s, CRYING, drains; CRYING → AGONAL below 20 %; DEAD at 0
	local m2 = bot(2)
	call("reset", m2)
	r = hit(m2, "abdomen")
	s = r.State
	check("U3 gut → DYING falling, no flinch", s.Phase == "DYING" and s.Stance == "FALLING" and s.Reacting == false and s.Wound == "Gut", s)
	s = call("advance", m2, 0.6)
	check("U3 gut down → CRYING", s.Stance == "DOWN" and s.Behaviour == "CRYING", s)
	s = call("advance", m2, 10)
	check("U3 CRYING drains ≈3.6 %/s", s.Life > 60 and s.Life < 70 and s.Phase == "DYING", s.Life)
	s = call("advance", m2, 13)
	check("U3 CRYING → AGONAL below 20 %", s.Behaviour == "AGONAL" and s.Life < 20, s)
	s = call("advance", m2, 5)
	check("U3 → DEAD, health 0", s.Phase == "DEAD" and s.Life == 0 and s.Health == 0, s)

	-- U4 throat: DYING, falls in 1.07 s, CHOKE, ≈6 %/s, DEAD
	local m3 = bot(3)
	call("reset", m3)
	r = hit(m3, "throat")
	check("U4 throat → DYING", r.State.Phase == "DYING" and r.State.Wound == "Throat" and r.Zone == "throat", r.State)
	s = call("advance", m3, 1.0)
	check("U4 still falling at 1.0 s", s.Stance == "FALLING", s)
	s = call("advance", m3, 0.2)
	check("U4 down → CHOKE", s.Stance == "DOWN" and s.Behaviour == "CHOKE", s)
	s = call("advance", m3, 17)
	check("U4 → DEAD", s.Phase == "DEAD", s)

	-- U5 lung: chest hits don't kill at once; strength 66 → (recovery) → collapse on the 3rd hit → CRYING (Lung)
	local m4 = bot(4)
	call("reset", m4)
	local s1 = hit(m4, "chest").State
	call("advance", m4, 0.45)
	local s2 = hit(m4, "chest").State
	call("advance", m4, 0.45)
	local s3 = hit(m4, "chest").State
	check("U5 chest 1–2 stay up", s1.Phase == "INJURED" and s1.Strength == 66 and s2.Phase == "INJURED" and s2.Stance == "STANDING", { s1.Strength, s2.Strength })
	check("U5 chest 3 collapses (strength ≤ 15)", s3.Phase == "DYING" and s3.Stance == "FALLING" and s3.Wound == "Lung", s3)
	s = call("advance", m4, 0.6)
	check("U5 down → CRYING, Lung wound", s.Stance == "DOWN" and s.Behaviour == "CRYING" and s.Wound == "Lung", s)

	-- U6 brain: LIMP at the hit, strength 0, down in 0.45 s, DEAD within ≈2 s
	local m5 = bot(5)
	call("reset", m5)
	r = hit(m5, "head")
	s = r.State
	check("U6 head → DYING LIMP at once", s.Phase == "DYING" and s.Behaviour == "LIMP" and s.Strength == 0 and s.Wound == "Brain", s)
	s = call("advance", m5, 0.5)
	check("U6 down by 0.5 s", s.Stance == "DOWN", s)
	s = call("advance", m5, 1.8)
	check("U6 → DEAD", s.Phase == "DEAD" and s.Health == 0, s)

	-- U7 legs: legs 100 → 20 → 0, unstable, goes down after 0.9 s (+0.5 s fall), SHOCK, no drain
	local m6 = bot(6)
	call("reset", m6)
	s1 = hit(m6, "leftleg").State
	s2 = hit(m6, "rightleg").State
	check("U7 legs 20 then 0 → unstable", s1.Legs == 20 and s2.Legs == 0 and s2.Unstable == true and s2.Phase == "INJURED", { s1, s2 })
	s = call("advance", m6, 0.8)
	check("U7 still standing at 0.8 s", s.Stance == "STANDING", s)
	s = call("advance", m6, 0.2)
	check("U7 falling after 0.9 s", s.Stance == "FALLING" and s.Phase == "DYING", s)
	s = call("advance", m6, 0.6)
	check("U7 down → SHOCK, Limb", s.Stance == "DOWN" and s.Behaviour == "SHOCK" and s.Wound == "Limb", s)
	s = call("advance", m6, 10)
	check("U7 SHOCK does not drain", s.Life == 100 and s.Phase == "DYING", s)

	-- U8 repeated hits: on a dying body = recorded only; on a dead body = ignored; wound upgrade while injured
	r = hit(m6, "head")
	check("U8 hit on DYING body: recorded only", r.Ignored == "dying: recorded only" and r.State.Behaviour == "SHOCK" and r.State.Hits == 3 and r.State.Phase == "DYING", r.State)
	r = hit(m5, "chest")
	check("U8 hit on DEAD body ignored", r.Ignored == "dead" and r.State.Phase == "DEAD" and r.State.Hits == 1, r.State)
	call("reset", m1)
	hit(m1, "leftarm")
	r = hit(m1, "head")
	check("U8 limb then brain → Brain, DYING", r.State.Wound == "Brain" and r.State.Phase == "DYING", r.State)
	call("reset", m1)
	hit(m1, "rightleg")
	r = hit(m1, "throat")
	check("U8 limb then throat → Throat (most severe kept)", r.State.Wound == "Throat", r.State)
	-- many hits in a row on one body: phase never goes back; every snapshot keeps the invariants
	call("reset", m1)
	local prev, bad = nil, {}
	for _, name in { "rightarm", "leftarm", "rightarm", "abdomen", "head", "chest", "leftleg" } do
		local st = hit(m1, name).State
		for _, v in invariants(st, prev) do
			table.insert(bad, `{name}: {v}`)
		end
		prev = st
	end
	for _ = 1, 30 do
		local st = call("advance", m1, 0.2)
		for _, v in invariants(st, prev) do
			table.insert(bad, `t: {v}`)
		end
		prev = st
	end
	check("U8 invariants over a hit / time sequence", #bad == 0, bad)
	local tags = 0
	for _, d in m1:GetChildren() do
		if d.Name == "BodyStateTag" then
			tags += 1
		end
	end
	check("U8 one tag per body", tags == 1, tags)

	-- U9 server authority: the published attributes equal the server's own state
	local g = call("get", m4)
	check("U9 attributes = server state", m4:GetAttribute("BodyPhase") == g.Phase and m4:GetAttribute("BodyStance") == g.Stance
		and m4:GetAttribute("BodyWound") == g.Wound and m4:GetAttribute("BodyBehaviour") == g.Behaviour, { attr = m4:GetAttribute("BodyPhase"), server = g.Phase })

	local passes = 0
	for _, c in out do
		if c.pass then
			passes += 1
		end
	end
	return { passed = passes, total = #out, results = out }
end

function Run.arm(): string
	for i = 1, 6 do
		call("reset", bot(i))
	end
	call("clear")
	return "armed"
end

-- After the client's run: the server's own records per bot, plus the final published state.
function Run.report(weapon: string?): any
	local recent = call("recent")
	local per: { [string]: { any } } = {}
	for _, r in recent do
		if not weapon or r.Weapon == weapon then
			per[r.Body] = per[r.Body] or {}
			table.insert(per[r.Body], r)
		end
	end
	local function seq(name: string): string
		local parts = {}
		for _, r in per[name] or {} do
			table.insert(parts, `{r.Location or r.Part}{if r.Zone then "/" .. r.Zone else ""}:{r.Wound or "-"}:{r.PhaseBefore}→{r.PhaseAfter}{if r.Ignored then "(" .. r.Ignored .. ")" else ""}`)
		end
		return table.concat(parts, " | ")
	end
	local function state(i: number): any
		return call("get", bot(i))
	end
	local checks = {}
	local function check(name: string, cond: boolean, detail: any?)
		table.insert(checks, { test = name, pass = cond, detail = detail })
	end
	local b1, b2, b3, b4, b5, b6 = per.BODY1 or {}, per.BODY2 or {}, per.BODY3 or {}, per.BODY4 or {}, per.BODY5 or {}, per.BODY6 or {}
	check("E1 BODY1 arm: rightarm, Limb, INJURED", b1[1] ~= nil and b1[1].Location == "rightarm" and b1[1].Wound == "Limb" and b1[1].PhaseAfter == "INJURED", seq("BODY1"))
	check("E2 BODY2 abdomen: Gut, DYING → down CRYING", b2[1] ~= nil and b2[1].Location == "abdomen" and b2[1].Wound == "Gut" and b2[1].PhaseAfter == "DYING"
		and state(2).Stance == "DOWN" and state(2).Behaviour == "CRYING", { seq = seq("BODY2"), now = state(2) })
	check("E3 BODY3 throat: chest/throat, Throat, DYING → CHOKE", b3[1] ~= nil and b3[1].Location == "chest" and b3[1].Zone == "throat" and b3[1].Wound == "Throat"
		and state(3).Behaviour == "CHOKE", { seq = seq("BODY3"), now = state(3) })
	check("E4 BODY4 chest ×3: Lung, collapse on the 3rd → CRYING", #b4 == 3 and b4[1].Wound == "Lung" and b4[1].PhaseAfter == "INJURED" and b4[2].PhaseAfter == "INJURED"
		and b4[3].PhaseAfter == "DYING" and state(4).Behaviour == "CRYING" and state(4).Wound == "Lung", { seq = seq("BODY4"), now = state(4) })
	check("E5 BODY5 head: Brain, LIMP → DEAD", b5[1] ~= nil and b5[1].Location == "head" and b5[1].Wound == "Brain" and b5[1].State.Behaviour == "LIMP"
		and state(5).Phase == "DEAD" and bot(5):FindFirstChildOfClass("Humanoid").Health == 0, { seq = seq("BODY5"), now = state(5) })
	check("E6 BODY6 legs ×2 → down SHOCK; later hit recorded only", #b6 >= 3 and b6[1].Location == "leftleg" and b6[2].Location == "rightleg"
		and b6[2].State.Unstable == true and b6[3].Ignored == "dying: recorded only" and state(6).Behaviour == "SHOCK", { seq = seq("BODY6"), now = state(6) })
	local passes = 0
	for _, c in checks do
		if c.pass then
			passes += 1
		end
	end
	return { weapon = weapon, passed = passes, total = #checks, checks = checks }
end

-- Forged-request checks (after the client's Run({ forged = true })): BODY1 must show only the server's own result.
function Run.reportForged(): any
	local recent = call("recent")
	local last = nil
	for _, r in recent do
		if r.Body == "BODY1" then
			last = r
		end
	end
	local m = bot(1)
	local s = call("get", m)
	return {
		lastHit = last and `{last.Location}/{last.Zone or "-"}:{last.Wound}` or "none",
		serverPhase = s and s.Phase,
		attrPhase = m:GetAttribute("BodyPhase"),
		attrLife = m:GetAttribute("BodyLife"),
		health = (m:FindFirstChildOfClass("Humanoid") :: Humanoid).Health,
		pass = last ~= nil and last.Location == "leftleg" and last.Wound == "Limb" and s.Phase == "INJURED"
			and m:GetAttribute("BodyPhase") == "INJURED" and (m:FindFirstChildOfClass("Humanoid") :: Humanoid).Health > 0,
	}
end

return Run
