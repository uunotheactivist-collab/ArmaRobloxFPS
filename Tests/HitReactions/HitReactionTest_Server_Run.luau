--!strict
-- Focused hit-reaction / active-ragdoll test, server side (Studio only; delete the HitReactionTest folders to remove
-- it). Range: Workspace.HitReactionTest (Roblox/Tests/HitReactions/build_range.luau). It talks to the running server
-- through the Studio-only hooks Server.BodyState.BodyStateDebug and Server.BodyPresentation.BodyPresentationDebug.
--   Run.spawn()       fresh REACT1–6 + PRES1 from ServerStorage.HitReactionTemplates; clear BodyState's records;
--                     start sampling every bot for `seconds`
--   Run.report(w)     after the client's real shots (StarterPlayerScripts.HitReactionTest): the BodyState records
--                     plus the presentation samples / status of every bot, checked against the expected reactions
--   Run.synthetic()   presentation-only: PRES1 driven through every dying behaviour by writing its Body* attributes
--                     (synthetic states, not BodyState output) → distinct muscle profiles, life fading, crawl, dead
--   Run.tamperCheck() after the client's tamper attempt: REACT1's server presentation unchanged

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local PConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("BodyPresentation"))

local Run = {}

local function bodyHook(...: any): any
	return (ServerScriptService.Server.BodyState:WaitForChild("BodyStateDebug", 5) :: BindableFunction):Invoke(...)
end
local function presHook(...: any): any
	return (ServerScriptService.Server.BodyPresentation:WaitForChild("BodyPresentationDebug", 5) :: BindableFunction):Invoke(...)
end
local function folder(i: number): Instance
	return workspace:WaitForChild("HitReactionTest"):WaitForChild(if i == 7 then "Pres1" else "Bot" .. i)
end
local function bot(i: number): Model
	return folder(i):WaitForChild(if i == 7 then "PRES1" else "REACT" .. i) :: Model
end

function Run.spawn(seconds: number?): any
	local templates = ServerStorage:WaitForChild("HitReactionTemplates")
	for i = 1, 7 do
		local f = folder(i)
		local name = if i == 7 then "PRES1" else "REACT" .. i
		local old = f:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		templates:WaitForChild(name):Clone().Parent = f
	end
	bodyHook("clear")
	task.wait(0.3)
	local bound = presHook("list")
	for i = 1, 6 do
		presHook("watch", bot(i), seconds or 30)
	end
	return { bound = #bound }
end

local function r2(x: number?): number?
	return if x then math.floor(x * 100 + 0.5) / 100 else nil
end

-- Profile k × life scale, as ActiveRagdoll computes it.
local function expectK(behaviour: string, life: number): { [string]: number }
	local p = PConfig.Profiles[behaviour]
	local out = {}
	for key, k in p.k do
		out[key] = math.clamp(k * life / p.Life, 0, PConfig.MaxK)
	end
	return out
end
local function kMatches(status: any, behaviour: string, tolerance: number): (boolean, number)
	if not status.Ragdoll then
		return false, -1
	end
	local exp = expectK(behaviour, status.Ragdoll.Life)
	local worst = 0
	for key, k in exp do
		worst = math.max(worst, math.abs((status.Ragdoll.K[key] or -1) - k))
	end
	return worst <= tolerance, worst
end

-- Summaries of one bot's samples.
local function analyse(samples: { any }): any
	local out = { n = #samples }
	if #samples == 0 then
		return out
	end
	local t0 = samples[1].t
	local maxSwing, swingAt, ragAt, fallAt, lowAt, startY, minY, lastY = 0, nil, nil, nil, nil, samples[1].torsoY, math.huge, nil
	local maxStep, unstableSway = 0, 0
	local midFall = 0
	for _, s in samples do
		if (s.armSwing or 0) > maxSwing then
			maxSwing, swingAt = s.armSwing, s.t - t0
		end
		maxStep = math.max(maxStep, s.step or 0)
		if s.ragdoll and not ragAt then
			ragAt = s.t - t0
		end
		if s.stance == "FALLING" and not fallAt then
			fallAt = s.t - t0
		end
		if s.torsoY then
			minY = math.min(minY, s.torsoY)
			lastY = s.torsoY
			-- "down" = the chest has dropped ≥ 1.2 studs (lying, or kneeling / sitting as in the reference's first kill)
			if ragAt and s.torsoY <= (startY or 3.5) - 1.2 and not lowAt then
				lowAt = s.t - t0
			end
			if ragAt and not lowAt and s.torsoY < (startY or 3.5) - 0.3 then
				midFall += 1 -- samples caught between standing and down: the fall is a motion, not a teleport
			end
		end
	end
	out.maxArmSwing, out.swingAt = r2(maxSwing), r2(swingAt)
	out.maxStep = r2(maxStep)
	out.ragdollAt, out.fallingAt = r2(ragAt), r2(fallAt)
	out.fallSeconds = if ragAt and lowAt then r2(lowAt - ragAt) else nil -- ragdoll start → chest down
	out.startTorsoY, out.minTorsoY, out.lastTorsoY = r2(startY), r2(minY), r2(lastY)
	out.midFallSamples = midFall
	local last = samples[#samples]
	out.lastArmSwing = r2(last.armSwing)
	return out
end

-- Fall stages of one bot (times in s from the ragdoll start, i.e. from DYING / the start of the fall).
--   supportLoss: pelvis 0.1 studs below its height before the fall
--   halfDrop: pelvis halfway to its lowest point (tilt / knee there show whether the legs or the whole body led)
--   tilt45: upper torso 45° from vertical
--   groundContact: a knee (shin top end within 0.55 studs: the shin lying on the ground) or the torso, head, arms or
--                  thighs within 0.12 studs of the ground
--   down: chest 1.2 studs below its height before the fall (the H2–H5 criterion)
--   settle: from here on every part moves slower than 0.3 studs/s (a body whose muscles fade with life keeps
--           sagging slowly, so this can be long)
--   still: the first time every part stays slower than 0.3 studs/s for 0.5 s (the fall has come to rest)
local function stages(samples: { any }): any
	local out: any = {}
	local ragI
	for i, s in samples do
		if s.ragdoll then
			ragI = i
			break
		end
	end
	if not ragI or not samples[ragI].pelvisY then
		return out
	end
	local t0 = samples[ragI].t
	local s0 = samples[math.max(ragI - 1, 1)]
	local pelvis0, chest0 = s0.pelvisY, s0.torsoY
	local pelvisMin = math.huge
	for i = ragI, #samples do
		pelvisMin = math.min(pelvisMin, samples[i].pelvisY or math.huge)
	end
	local half = pelvis0 - (pelvis0 - pelvisMin) / 2
	local quietFrom = nil
	for i = ragI, #samples do
		local s = samples[i]
		local dt = s.t - t0
		if not out.supportLoss and s.pelvisY <= pelvis0 - 0.1 then
			out.supportLoss = r2(dt)
		end
		if not out.halfDrop and s.pelvisY <= half then
			out.halfDrop, out.tiltAtHalfDrop, out.kneeAtHalfDrop = r2(dt), r2(s.tilt), r2(s.knee)
		end
		if not out.tilt45 and (s.tilt or 0) >= 45 then
			out.tilt45, out.kneeAtTilt45, out.pelvisDropAtTilt45 = r2(dt), r2(s.knee), r2(pelvis0 - s.pelvisY)
		end
		if not out.groundContact and (s.lowest <= 0.12 or (s.kneeY or 9) <= 0.55) then
			out.groundContact, out.tiltAtContact, out.kneeAtContact = r2(dt), r2(s.tilt), r2(s.knee)
		end
		if not out.down and s.torsoY <= chest0 - 1.2 then
			out.down = r2(dt)
		end
		if s.maxSpeed < 0.3 then
			quietFrom = quietFrom or dt
			if not out.still and quietFrom and dt - quietFrom >= 0.5 and out.supportLoss then
				out.still = r2(quietFrom)
			end
		else
			quietFrom = nil
		end
		out.maxKnee = math.max(out.maxKnee or 0, s.knee or 0)
	end
	local last = samples[#samples]
	out.settle = if quietFrom and quietFrom < (last.t - t0) - 0.3 then r2(quietFrom) else nil
	out.maxKnee = r2(out.maxKnee)
	out.final = { pelvisY = r2(last.pelvisY), chestY = r2(last.torsoY), tilt = r2(last.tilt), knee = r2(last.knee), hip = r2(last.hip) }
	out.recorded = r2(last.t - t0)
	return out
end

-- Stage numbers for REACT2–6 (and PRES1 with i = 7), after a run.
function Run.stages(list: { number }?): any
	local out = {}
	for _, i in list or { 2, 3, 4, 5, 6 } do
		out[bot(i).Name] = stages(presHook("samples", bot(i)))
	end
	return out
end

-- Side-view segments of one bot every `step` s from `from` to `to` (s, relative to the ragdoll start).
function Run.frames(i: number, from: number, to: number, step: number): { any }
	local samples = presHook("samples", bot(i))
	local t0
	for _, s in samples do
		if s.ragdoll then
			t0 = s.t
			break
		end
	end
	local out = {}
	if not t0 then
		return out
	end
	local want = from
	for _, s in samples do
		local dt = s.t - t0
		if dt >= want - 0.017 and want <= to + 1e-6 then
			table.insert(out, string.format("%.2f|%s", dt, s.seg or ""))
			want += step
		end
	end
	return out
end

function Run.report(weapon: string?): any
	local recent = bodyHook("recent")
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
	local checks = {}
	local function check(name: string, cond: boolean, detail: any?)
		table.insert(checks, { test = name, pass = cond, detail = detail })
	end
	local info = {}
	for i = 1, 6 do
		local m = bot(i)
		info[i] = {
			seq = seq(m.Name),
			state = bodyHook("get", m),
			status = presHook("status", m),
			a = analyse(presHook("samples", m)),
			present = m.Parent ~= nil and m:FindFirstChild("UpperTorso") ~= nil,
		}
	end
	local function owned(i: number): boolean
		return info[i].status.ClientOwnedParts == 0
	end
	-- 1 arm: flinch only
	local a1 = info[1]
	check("H1 REACT1 arm: flinch seen and over, no ragdoll, still standing",
		string.find(a1.seq, "rightarm:Limb:ALIVE→INJURED") ~= nil and (a1.a.maxArmSwing or 0) >= 0.5 * PConfig.Flinch.ArmSwingDeg
			and (a1.a.lastArmSwing or 1) == 0 and a1.status.Ragdoll == nil and a1.status.RootAnchored == true, { seq = a1.seq, a = a1.a })
	-- 2 gut: ragdoll at the hit, visible fall, CRYING profile faded with life
	local a2 = info[2]
	local ok2, w2 = kMatches(a2.status, "CRYING", 0.03)
	check("H2 REACT2 abdomen: ragdoll, falls (not a teleport), CRYING muscles", string.find(a2.seq, "abdomen:Gut:ALIVE→DYING") ~= nil
		and a2.status.Ragdoll ~= nil and (a2.a.fallSeconds or 99) < 3 and a2.a.midFallSamples >= 5 and ok2 and owned(2),
		{ seq = a2.seq, a = a2.a, kErr = w2, profile = a2.status.Ragdoll and a2.status.Ragdoll.Profile })
	-- 3 throat: CHOKE
	local a3 = info[3]
	local ok3, w3 = kMatches(a3.status, "CHOKE", 0.03)
	check("H3 REACT3 throat: ragdoll, CHOKE muscles", string.find(a3.seq, "chest/throat:Throat") ~= nil and a3.status.Ragdoll ~= nil
		and (a3.a.fallSeconds or 99) < 3.5 and ok3 and owned(3), { seq = a3.seq, a = a3.a, kErr = w3 })
	-- 4 chest burst: 2 standing hits, collapse on the 3rd, CRYING (Lung)
	local a4 = info[4]
	local ok4, w4 = kMatches(a4.status, "CRYING", 0.03)
	check("H4 REACT4 chest ×3: stays up for 2, ragdoll on the 3rd, CRYING", string.find(a4.seq, "chest:Lung:INJURED→DYING") ~= nil
		and a4.status.Ragdoll ~= nil and a4.state.Wound == "Lung" and ok4, { seq = a4.seq, a = a4.a, kErr = w4 })
	-- 5 head: LIMP (all 0), sinks, DEAD, body stays
	local a5 = info[5]
	local limp = a5.status.Ragdoll ~= nil
	if limp then
		for _, k in a5.status.Ragdoll.K do
			if k ~= 0 then
				limp = false
			end
		end
	end
	check("H5 REACT5 head: LIMP muscles 0, sinks, DEAD, body stays", string.find(a5.seq, "head:Brain") ~= nil and limp
		and a5.state.Phase == "DEAD" and a5.status.Ragdoll.Dead == true and a5.present and (a5.a.fallSeconds or 99) < 3 and owned(5),
		{ seq = a5.seq, a = a5.a })
	-- 6 legs: unstable stumble step, then ragdoll, SHOCK; the later hit is recorded only
	local a6 = info[6]
	local ok6, w6 = kMatches(a6.status, "SHOCK", 0.03)
	check("H6 REACT6 legs ×2: stumble step, then ragdoll SHOCK; later hit recorded only",
		string.find(a6.seq, "rightleg:Limb:INJURED→INJURED") ~= nil and string.find(a6.seq, "recorded only") ~= nil
			and (a6.a.maxStep or 0) >= PConfig.Stumble.StepStuds * 0.9 and a6.status.Ragdoll ~= nil and ok6 and owned(6),
		{ seq = a6.seq, a = a6.a, kErr = w6 })
	local passes = 0
	for _, c in checks do
		if c.pass then
			passes += 1
		end
	end
	return { weapon = weapon, passed = passes, total = #checks, checks = checks }
end

-- Presentation-only: drive PRES1 through every behaviour (synthetic Body* attributes, not BodyState output).
function Run.synthetic(): any
	local m = bot(7)
	local function set(phase: string, stance: string, behaviour: string?, life: number)
		m:SetAttribute("BodyPhase", phase)
		m:SetAttribute("BodyStance", stance)
		m:SetAttribute("BodyBehaviour", behaviour)
		m:SetAttribute("BodyLife", life)
	end
	local out, profiles = {}, {}
	local function grab(label: string, behaviour: string, life: number)
		task.wait(0.4)
		local st = presHook("status", m)
		local ok, worst = kMatches(st, behaviour, 0.02)
		local key = ""
		local names = {}
		for name in st.Ragdoll.K do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			key ..= string.format("%.2f,", st.Ragdoll.K[name])
		end
		profiles[label] = key
		table.insert(out, { test = label, pass = ok, detail = { profile = st.Ragdoll.Profile, kErr = worst, life = life } })
	end
	set("DYING", "DOWN", "SHOCK", 100)
	grab("SHOCK @100", "SHOCK", 100)
	set("DYING", "DOWN", "WRITHE", 92)
	grab("WRITHE @92", "WRITHE", 92)
	set("DYING", "DOWN", "CHOKE", 97)
	grab("CHOKE @97", "CHOKE", 97)
	set("DYING", "DOWN", "CHOKE", 81)
	grab("CHOKE @81 (fades with life)", "CHOKE", 81)
	set("DYING", "DOWN", "PANIC", 94)
	grab("PANIC @94", "PANIC", 94)
	set("DYING", "DOWN", "AGONAL", 19)
	grab("AGONAL @19", "AGONAL", 19)
	set("DYING", "DOWN", "LIMP", 60)
	grab("LIMP @60", "LIMP", 60)
	-- CRAWL: measured 0.6 studs/s along the head direction
	set("DYING", "DOWN", "CRAWL", 99)
	task.wait(0.5)
	local upper = m:FindFirstChild("UpperTorso") :: BasePart
	local p0 = upper.Position
	task.wait(3)
	local moved = Vector3.new(upper.Position.X - p0.X, 0, upper.Position.Z - p0.Z).Magnitude
	local st = presHook("status", m)
	table.insert(out, { test = "CRAWL moves ≈0.6 studs/s", pass = st.Ragdoll.Crawl == true and moved > 1.0 and moved < 2.6,
		detail = { moved3s = r2(moved), speed = r2(moved / 3) } })
	grab("CRAWL @99", "CRAWL", 99)
	-- dead: everything 0, crawl off, body stays
	m:SetAttribute("BodyPhase", "DEAD")
	m:SetAttribute("BodyLife", 0)
	task.wait(0.4)
	st = presHook("status", m)
	local zero = true
	for _, k in st.Ragdoll.K do
		if k ~= 0 then
			zero = false
		end
	end
	table.insert(out, { test = "DEAD: muscles 0, crawl off, body stays", pass = zero and st.Ragdoll.Crawl == false and m.Parent ~= nil, detail = st.Ragdoll })
	-- the profiles are distinct
	local seen, distinct = {}, true
	for label, key in profiles do
		if string.find(label, "@81") then
			continue
		end
		if seen[key] then
			distinct = false
		end
		seen[key] = true
	end
	table.insert(out, { test = "behaviour profiles are distinct", pass = distinct })
	local passes = 0
	for _, c in out do
		if c.pass then
			passes += 1
		end
	end
	return { passed = passes, total = #out, results = out }
end

function Run.tamperCheck(): any
	local m = bot(1)
	local st = presHook("status", m)
	return {
		serverStance = m:GetAttribute("BodyStance"),
		serverPhase = m:GetAttribute("BodyPhase"),
		ragdoll = st.Ragdoll ~= nil,
		rootAnchored = st.RootAnchored,
		pass = st.Ragdoll == nil and st.RootAnchored == true and m:GetAttribute("BodyPhase") ~= "DEAD",
	}
end

return Run
