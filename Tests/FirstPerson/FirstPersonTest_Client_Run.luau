--!strict
-- First-person fidelity test, client side (Studio only; delete the FirstPersonTest folders to remove it). Driven through
-- execute_luau (Client datamodel); the server half is ServerScriptService.FirstPersonTest.Run. Every rendered frame is
-- sampled after everything else has drawn (render priority Last): the held weapon's presence in the 1280 x 720 picture
-- (corners of the visible viewmodel parts inside the picture / inside the reference's bottom-centre box x 470-830,
-- y 560-716), the visible grenade (in hand / proxy / replicated body) and WeaponLowering's amount.
--   Run.setup(weapon?)        range spot, weapon equipped, grenades refilled
--   Run.timing(weapon?)       presence per 30-fps frame from the press vs the reference's frames
--   Run.release(pitch?)       the grenade leaves the hand at once: no hold, no pop at hand → proxy → body
--   Run.contact()             a throw into the ground just ahead: hold at the contact point, then the server's bounce
--   Run.rapid()               spammed presses, then back-to-back throws: nothing left over
--   Run.switching()           weapon switches during a throw
--   Run.transitions()         reload, ADS, scope, firing, a switch mid-reload, each with a throw
--   Run.movement()            walk, crouch, jump, fall, each with a throw
--   Run.idle(weapon?)         outside a throw the lowering is the identity (fire / recoil / reload / ADS)
--   Run.forged()              malformed / forged "Released" messages (this client only)
--   Run.leftovers()           proxies, hidden bodies, prediction items, lowering after a test
--   Run.death(stage)          "before" / "after" (with the server's killDuringThrow): what is left after the death

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage.Shared.Config.Grenade) :: any
local Command = ReplicatedStorage.Shared.Remotes:WaitForChild("GrenadeCommand") :: RemoteEvent
local scripts = player:WaitForChild("PlayerScripts")
local client = scripts:WaitForChild("Client")
local gHook = client:WaitForChild("Grenade"):WaitForChild("GrenadeClient"):WaitForChild("GrenadeClientDebug") :: BindableFunction
local wHook = client:WaitForChild("WeaponController"):WaitForChild("ProductionWeaponDebug") :: BindableFunction
local mHook = client:WaitForChild("Movement"):WaitForChild("MovementController"):WaitForChild("MovementClientDebug") :: BindableFunction

local Run = {}
local F = 1 / 30
local PARTIAL = { Mag = 5, Chambered = true, Reserve = { 30, 30 } } -- a partial magazine (DevSetAmmo, Studio only)
Run.Spot = Vector3.new(-500, 3, 160) -- the grenade range (open ground, facing +Z)

local function g(cmd: string, arg: any?): any
	return gHook:Invoke(cmd, arg)
end
local function w(cmd: string, arg: any?): any
	return wHook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function r2(v: number?): number?
	return if v then math.round(v * 100) / 100 else nil
end

local function root(): BasePart
	local c = player.Character or player.CharacterAdded:Wait()
	return c:WaitForChild("HumanoidRootPart") :: BasePart
end

local function humanoid(): Humanoid
	local c = player.Character or player.CharacterAdded:Wait()
	return c:WaitForChild("Humanoid") :: Humanoid
end

function Run.equip(id: string)
	player:SetAttribute("EquippedWeapon", id)
	frames(0.3)
end

local function pitchTo(pitch: number)
	local cam = workspace.CurrentCamera
	local look = root().CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z).Unit
	local dir = (flat * math.cos(math.rad(pitch)) + Vector3.new(0, math.sin(math.rad(pitch)), 0)).Unit
	for _ = 1, 10 do
		cam.CFrame = CFrame.lookAt(cam.CFrame.Position, cam.CFrame.Position + dir)
		frames(0.1)
		if cam.CFrame.LookVector:Dot(dir) > 0.9995 then
			break
		end
	end
	frames(0.2)
end

function Run.setup(weapon: string?, pitch: number?): any
	local r = root()
	r.CFrame = CFrame.lookAt(Run.Spot, Run.Spot + Vector3.new(0, 0, 10))
	r.AssemblyLinearVelocity = Vector3.zero
	Run.equip(weapon or "M4")
	w("aim", false)
	w("trigger", false)
	w("refill")
	Command:FireServer("DevRefill")
	frames(0.4)
	pitchTo(pitch or -4.5)
	return { weapon = player:GetAttribute("EquippedWeapon"), at = r.Position }
end

-- ── the per-frame sampler ─────────────────────────────────────────────────────────────────────────────────────────

local CORNERS = {}
for _, x in { -0.5, 0.5 } do
	for _, y in { -0.5, 0.5 } do
		for _, z in { -0.5, 0.5 } do
			table.insert(CORNERS, Vector3.new(x, y, z))
		end
	end
end

local function px720(c: CFrame, f720: number, p: Vector3): (number?, number?, Vector3)
	local l = c:PointToObjectSpace(p)
	if l.Z > -0.05 then
		return nil, nil, l
	end
	return 640 + l.X / -l.Z * f720, 360 - l.Y / -l.Z * f720, l
end

local function newestBody(): BasePart?
	local f = workspace:FindFirstChild("Grenades")
	local best, bestId = nil, -1
	if f then
		for _, c in f:GetChildren() do
			local id = c:GetAttribute("GrenadeId")
			if c:IsA("BasePart") and typeof(id) == "number" and id > bestId then
				best, bestId = c, id
			end
		end
	end
	return best
end

local function sample(t0: number): any
	local cam = workspace.CurrentCamera
	local c = cam.CFrame
	local f720 = 360 / math.tan(math.rad(cam.FieldOfView) / 2)
	local inView, inBox, n = 0, 0, 0
	for _, m in cam:GetChildren() do
		if m:IsA("Model") and string.sub(m.Name, -9) == "Viewmodel" then
			for _, p in m:GetDescendants() do
				if p:IsA("BasePart") and p.Transparency < 0.95 and p.LocalTransparencyModifier < 0.95 then
					for _, k in CORNERS do
						n += 1
						local x, y = px720(c, f720, p.CFrame:PointToWorldSpace(p.Size * k))
						if x and y then
							if x >= 0 and x <= 1280 and y >= 0 and y <= 720 then
								inView += 1
							end
							if x >= 470 and x <= 830 and y >= 560 and y <= 716 then
								inBox += 1
							end
						end
					end
				end
			end
		end
	end
	local which, wp = nil, nil
	for _, ch in cam:GetChildren() do
		if ch.Name == "GrenadeProxy" and ch:IsA("BasePart") then
			which, wp = "proxy", ch.Position
		end
	end
	local view = cam:FindFirstChild("GrenadeThrowView")
	local inHand = view and view:FindFirstChild("Grenade") :: BasePart?
	if not which and inHand and inHand.Transparency < 0.5 then
		which, wp = "hand", inHand.Position
	end
	local body = newestBody()
	if not which and body and body.LocalTransparencyModifier < 0.5 then
		which, wp = "body", body.Position
	end
	local arm = view and view:FindFirstChild("Arm") :: BasePart?
	local x, y = nil, nil
	if wp then
		x, y = px720(c, f720, wp)
	end
	local active = (g("prediction") :: any).Active
	return { t = os.clock() - t0, which = which, wp = wp, x = x, y = y, inView = inView, inBox = inBox, n = n,
		phase = active[#active] and active[#active].Phase, low = (g("lowering") :: any).Amount, arm = arm ~= nil and arm.Transparency < 0.5,
		bodyHidden = body ~= nil and body.LocalTransparencyModifier > 0.5, cam = c }
end

-- run `actions` (list of { at = seconds from the press, fn = function }) around one press; sample `seconds`
local function record(seconds: number, actions: { any }?, noPress: boolean?): (any, number, number)
	local rows = {}
	local t0 = os.clock()
	local done = false
	RunService:BindToRenderStep("FirstPersonTestSampler", Enum.RenderPriority.Last.Value, function()
		if not done then
			table.insert(rows, sample(t0))
		end
	end)
	frames(0.25)
	local tPress = os.clock()
	if not noPress then
		g("press")
	end
	local queue = table.clone(actions or {})
	table.sort(queue, function(a, b)
		return a.at < b.at
	end)
	while os.clock() - tPress < seconds do
		RunService.RenderStepped:Wait()
		while queue[1] and os.clock() - tPress >= queue[1].at do
			local a = table.remove(queue, 1)
			task.spawn(a.fn)
		end
	end
	done = true
	RunService:UnbindFromRenderStep("FirstPersonTestSampler")
	return rows, tPress - t0, t0
end

-- the row closest to time t (seconds from the sampler start)
local function at(rows: { any }, t: number): any
	local best, bd = rows[1], math.huge
	for _, r in rows do
		local d = math.abs(r.t - t)
		if d < bd then
			best, bd = r, d
		end
	end
	return best
end

local function rest(rows: { any }, press: number): number
	local s, n = 0, 0
	for _, r in rows do
		if r.t < press - 0.02 then
			s += r.inView
			n += 1
		end
	end
	return if n > 0 then s / n else 0
end

-- presence per 30-fps frame from the press (k = 0 is the press = L-3), as a fraction of the weapon at rest
local function presence(rows: { any }, press: number, k0: number, k1: number): ({ any }, number)
	local base = rest(rows, press)
	local out = {}
	for k = k0, k1 do
		local r = at(rows, press + k * F)
		table.insert(out, { k = k, L = k - 3, p = if base > 0 then r2(r.inView / base) else nil, low = r2(r.low) })
	end
	return out, base
end

-- ── grenade-in-flight analysis ────────────────────────────────────────────────────────────────────────────────────

local function flight(rows: { any }, press: number): any
	local rel = press + Config.Throw.ReleaseSeconds
	local holdRows, holdMax, run = 0, 0, 0
	local contactHold = 0
	local backward = 0
	local transitions = {}
	local prev = nil
	local steps = {}
	for i, r in rows do
		if r.t >= rel - 2 * F and r.t <= rel + 1.2 then
			if prev and prev.x and r.x and prev.which and r.which then
				local step = Vector2.new(r.x - prev.x, r.y - prev.y).Magnitude
				local stepW = (r.wp - prev.wp).Magnitude
				table.insert(steps, { i = i, step = step, stepW = stepW, from = prev.which, to = r.which, t = r.t - rel })
				-- a hold: the predicted grenade in flight not moving (< 2 studs/s); a hold at a contact point is
				-- counted apart (the server's body may come to rest after its bounce: not counted)
				local dt = r.t - prev.t
				local still = dt > 0 and stepW / dt < 2
				if r.which == "proxy" and prev.which == "proxy" and r.phase == "flight" and still then
					holdRows += 1
					run += 1
					holdMax = math.max(holdMax, run)
				else
					run = 0
				end
				if r.which == "proxy" and r.phase == "hold" and dt > 0 then
					contactHold += dt
				end
			end
			prev = r
		end
	end
	-- direction reversals (world): the visible grenade moving against its previous step before any bounce
	for j = 2, #steps do
		local a, b = rows[steps[j - 1].i], rows[steps[j].i]
		local pa = rows[steps[j - 1].i - 1]
		if pa and pa.wp and a.wp and b.wp and pa.phase == "flight" and a.phase == "flight" and b.phase == "flight"
			and pa.which == "proxy" and a.which == "proxy" and b.which == "proxy" then
			local d1, d2 = a.wp - pa.wp, b.wp - a.wp
			if d1.Magnitude > 0.05 and d2.Magnitude > 0.05 and d1.Unit:Dot(d2.Unit) < -0.2 then
				backward += 1
			end
		end
	end
	for j, s in steps do
		if s.from ~= s.to and s.t >= -0.001 then -- (an older grenade on the ground before the release is not this one)
			local around = {}
			for d = -3, 3 do
				local o = steps[j + d]
				if d ~= 0 and o and o.from == o.to then
					table.insert(around, o.stepW)
				end
			end
			local mx = 0
			for _, v in around do
				mx = math.max(mx, v)
			end
			table.insert(transitions, { kind = s.from .. ">" .. s.to, atS = r2(s.t), stepPx = r2(s.step),
				stepStuds = r2(s.stepW), neighbourMaxStuds = r2(mx) })
		end
	end
	-- 30-fps view from the release (L+1): which, px, step
	local series = {}
	local last = nil
	for k = -1, 12 do
		local r = at(rows, rel + k * F)
		local step = if last and last.x and r.x then r2(Vector2.new(r.x - last.x, r.y - last.y).Magnitude) else nil
		table.insert(series, string.format("L%+d %s %s %s", k + 1, tostring(r.which), if r.x then string.format("(%d,%d)", math.round(r.x), math.round(r.y)) else "-",
			if step then "step " .. step else ""))
		last = r
	end
	-- the old metric: 30-fps frames from the release in which the visible grenade did not move
	local held30 = 0
	for k = 1, 12 do
		local a, b = at(rows, rel + (k - 1) * F), at(rows, rel + k * F)
		if a.wp and b.wp and a.which == "proxy" and b.which == "proxy" and a.phase == "flight" and b.phase == "flight"
			and (b.wp - a.wp).Magnitude < 0.05 then
			held30 += 1
		end
	end
	return { holdRows = holdRows, longestHoldRows = holdMax, heldFrames30 = held30, reversals = backward,
		contactHoldS = r2(contactHold), transitions = transitions, series30 = series }
end

local function lastRecord(): any
	local pr = g("prediction")
	return pr.Records[#pr.Records], pr
end

local function compactRecord(r: any): any
	if not r then
		return nil
	end
	return { id = r.Id, how = r.How, localStart = r.Local, lagS = r2(r.Lag), matchErrorStuds = r2(r.MatchError),
		serverVsLocalStuds = r2(r.ErrorAtServer), messageDelayS = r2(r.MessageDelay), contactS = r2(r.Contact),
		heldS = r2(r.Held), shownAtS = r2(r.ShownAt), plannedLagS = r2(r.PlannedLag), onTrackByS = r2(r.Th),
		speedFactor = if r.Lag and r.Th then r2(1 - r.Lag / r.Th) else nil }
end

-- ── tests ─────────────────────────────────────────────────────────────────────────────────────────────────────────

-- presence per 30-fps frame vs the reference's (normal clip, four throws): L-4 full, L-1 ≤ 12 %, L … L+9 none,
-- back from L+9 / L+10, substantial (≥ 50 %) by L+12, full (≥ 90 %) by L+15
function Run.timing(weapon: string?): any
	Run.setup(weapon)
	local rows, press = record(1.0)
	frames(0.3)
	local series, base = presence(rows, press, -1, 20)
	local byL = {}
	for _, s in series do
		byL[s.L] = s.p or 0
	end
	local hidden = true
	for L = 0, 9 do
		hidden = hidden and (byL[L] or 1) <= 0.02
	end
	local firstBack = nil
	for L = 0, 17 do
		if not firstBack and L > 3 and (byL[L] or 0) > 0.02 then
			firstBack = L
		end
	end
	local checks = {
		fullAtLminus4 = (byL[-4] or 0) >= 0.95,
		smallAtLminus1 = (byL[-1] or 1) <= 0.3,
		hiddenL0toL9 = hidden,
		substantialByL12 = (byL[12] or 0) >= 0.5,
		fullByL15 = (byL[15] or 0) >= 0.9,
		identityAfter = (at(rows, press + 0.7).low or 1) == 0,
	}
	local pass = true
	for _, v in checks do
		pass = pass and v
	end
	local compact = {}
	for _, s in series do
		table.insert(compact, string.format("L%+d %s (%s)", s.L, tostring(s.p), tostring(s.low)))
	end
	return { pass = pass, weapon = weapon or "M4", restCorners = math.round(base), firstBackL = firstBack, checks = checks,
		presence = compact }
end

function Run.release(pitch: number?, weapon: string?): any
	Run.setup(weapon, pitch)
	g("predictionClear")
	local rows, press = record(1.6)
	frames(0.2)
	local f = flight(rows, press)
	local rec, pr = lastRecord()
	local handProxy, proxyBody = nil, nil
	for _, tr in f.transitions do
		if tr.kind == "hand>proxy" then
			handProxy = tr
		elseif tr.kind == "proxy>body" then
			proxyBody = tr
		end
	end
	local checks = {
		noHold = f.longestHoldRows == 0 and f.heldFrames30 == 0,
		-- ≤ 1 frame; ≤ 5 frames when the first contact comes before the replicated body has even started moving
		-- (≈ 0.2 s: a throw into the ground / a wall right ahead; the server's bounce can't be shown earlier)
		contactHoldOk = (f.contactHoldS or 0) <= (if rec and rec.Contact and rec.Contact < 0.25 then 5 * F else F) + 0.005,
		noReversal = f.reversals == 0,
		handToProxySmooth = handProxy ~= nil and (handProxy.stepStuds or 99) <= math.max(0.5, 1.5 * (handProxy.neighbourMaxStuds or 0)),
		proxyToBodySmooth = proxyBody ~= nil and (proxyBody.stepStuds or 99) <= 1.5 * (proxyBody.neighbourMaxStuds or 0) + 0.1,
		handedOver = rec ~= nil and (rec.How == "HandedOver" or rec.How == "AtContact"),
		bodyShownAfter = not at(rows, rows[#rows].t).bodyHidden,
	}
	local pass = true
	for _, v in checks do
		pass = pass and v
	end
	return { pass = pass, checks = checks, flight = f, record = compactRecord(rec), stats = pr.Stats }
end

function Run.contact(): any
	local r = Run.release(-70)
	r.note = "pitched 70° down: the path meets the ground within a few frames; the proxy holds there until the replicated body arrives"
	return r
end

function Run.leftovers(): any
	local cam = workspace.CurrentCamera
	local proxies = 0
	for _, c in cam:GetChildren() do
		if c.Name == "GrenadeProxy" then
			proxies += 1
		end
	end
	local hidden = 0
	local f = workspace:FindFirstChild("Grenades")
	if f then
		for _, c in f:GetDescendants() do
			if c:IsA("BasePart") and c.LocalTransparencyModifier > 0 then
				hidden += 1
			end
		end
	end
	local pr = g("prediction")
	local low = g("lowering")
	local view = cam:FindFirstChild("GrenadeThrowView")
	local arm = view and view:FindFirstChild("Arm") :: BasePart?
	local vms = (w("sync") :: any).viewmodels
	return { proxies = proxies, hiddenBodies = hidden, activeItems = #pr.Active, bound = pr.Bound, pool = pr.Pool,
		lowering = low.Amount, armShown = arm ~= nil and arm.Transparency < 0.5, viewmodels = vms,
		clean = proxies == 0 and hidden == 0 and #pr.Active == 0 and not pr.Bound and low.Amount == 0 }
end

function Run.rapid(): any
	Run.setup("M4")
	g("predictionClear")
	local s0 = (g("prediction") :: any).Stats
	local m0 = #(g("messages") :: any)
	g("clear")
	-- 1) eight presses 50 ms apart, all inside one throw (Throw.Seconds): one throw, one proxy
	local presses = {}
	for i = 0, 7 do
		table.insert(presses, { at = 0.05 * i, fn = function()
			g("press")
		end })
	end
	local rows = record(1.2, presses, true)
	local spamMsgs = g("messages")
	local spamThrows = 0
	for _, m in spamMsgs do
		if m.Phase == "Released" then
			spamThrows += 1
		end
	end
	local f = flight(rows, 0.25)
	frames(1.5)
	local afterSpam = Run.leftovers()
	-- 2) back-to-back throws, each as soon as the last one ends (Throw.Seconds + 2 frames)
	Command:FireServer("DevRefill")
	frames(0.3)
	g("clear")
	local seq = {}
	for i = 0, 3 do
		table.insert(seq, { at = i * (Config.Throw.Seconds + 2 * F), fn = function()
			g("press")
		end })
	end
	local rows2 = record(2.4, seq, true)
	frames(2.0)
	local msgs = g("messages")
	local released, refused = 0, 0
	for _, m in msgs do
		if m.Phase == "Released" then
			released += 1
		elseif m.Phase == "Refused" then
			refused += 1
		end
	end
	local pr = g("prediction")
	local hows = {}
	for _, r in pr.Records do
		hows[r.How] = (hows[r.How] or 0) + 1
	end
	local f2 = flight(rows2, 0.25)
	local after = Run.leftovers()
	local pass = spamThrows == 1 and afterSpam.clean and released == 4 and refused == 0 and after.clean
		and (hows.HandedOver or 0) + (hows.AtContact or 0) == 5 and pr.Stats.ProxiesBuilt - s0.ProxiesBuilt <= Config.Prediction.Pool + 1
	return { pass = pass, spam = { presses = 8, released = spamThrows, longestHoldRows = f.longestHoldRows, after = afterSpam },
		backToBack = { presses = 4, released = released, refused = refused, finished = hows, proxiesBuilt = pr.Stats.ProxiesBuilt - s0.ProxiesBuilt,
			firstThrowLongestHoldRows = f2.longestHoldRows, after = after }, messagesBefore = m0 }
end

function Run.switching(): any
	Run.setup("M4")
	local acts = {
		{ at = 0.1, fn = function() player:SetAttribute("EquippedWeapon", "AK") end },
		{ at = 0.25, fn = function() player:SetAttribute("EquippedWeapon", "Glock") end },
		{ at = 0.33, fn = function() player:SetAttribute("EquippedWeapon", "Sniper") end },
	}
	local rows, press = record(1.0, acts)
	frames(0.2)
	local series, base = presence(rows, press, 0, 22)
	local hidden = true
	for _, s in series do
		if s.L >= 0 and s.L <= 9 then
			hidden = hidden and (at(rows, press + s.k * F).inView <= 2)
		end
	end
	local back = at(rows, press + 0.75)
	local out = { weaponAfter = player:GetAttribute("EquippedWeapon"), hiddenL0toL9 = hidden,
		backAtEnd = back.inView > 0 and back.low == 0, leftovers = Run.leftovers() }
	Run.equip("M4")
	out.pass = out.hiddenL0toL9 and out.backAtEnd and out.leftovers.viewmodels == 1
	local compact = {}
	for _, s in series do
		table.insert(compact, string.format("L%+d %d (%s)", s.L, at(rows, press + s.k * F).inView, tostring(s.low)))
	end
	out.corners = compact
	return out
end

-- One throw during each first-person transition; checks the weapon's own state is the same as without the throw
function Run.transitions(): any
	local out = {}
	-- reload: start a reload, throw during it; the reload keeps its own timing (not cancelled by the throw)
	Run.setup("M4")
	w("setAmmo", PARTIAL)
	frames(0.5)
	w("reload")
	frames(0.05)
	local started = w("sync").reloading
	local rows = record(0.6)
	local st = w("sync")
	out.reload = { started = started ~= nil, stillReloadingAfterThrow = st.reloading,
		lowAfter = at(rows, rows[#rows].t).low }
	frames(3.5)
	st = w("sync")
	out.reload.mag = st.mag
	out.reload.finished = st.reloading == nil and st.mag > PARTIAL.Mag
	-- ADS: aim held through the throw; the aim state is unchanged and the pose returns to ADS
	Run.setup("M4")
	w("aim", true)
	frames(0.6)
	w("record", true)
	local rowsA, pressA = record(0.9)
	local rec = w("record", false)
	local lastAim = rec.log[#rec.log] and rec.log[#rec.log].aim
	w("aim", false)
	out.ads = { aimAlphaAfter = r2(lastAim), lowAfter = at(rowsA, rowsA[#rowsA].t).low, hiddenAtL5 = at(rowsA, pressA + 8 * F).inView <= 2 }
	-- scope (Sniper): scoped through the throw; the optic's own state is unchanged
	Run.setup("Sniper")
	w("aim", true)
	frames(1.0)
	local o0 = w("optic")
	local rowsS, pressS = record(0.9)
	local o1 = w("optic")
	w("aim", false)
	out.scope = { stateBefore = o0.aimState, stateAfter = o1.aimState, alphaAfter = r2(o1.aimAlpha),
		hiddenAtL5 = at(rowsS, pressS + 8 * F).inView <= 2, lowAfter = at(rowsS, rowsS[#rowsS].t).low }
	-- firing: trigger held through the throw (MP7, automatic): shots continue at the weapon's own rate
	Run.setup("MP7")
	local s0 = w("sync")
	local rowsF = record(0.8, {
		{ at = -0.15, fn = function() w("trigger", true) end },
		{ at = 0.55, fn = function() w("trigger", false) end },
	})
	frames(0.3)
	local s1 = w("sync")
	out.firing = { shots = s1.shotCount - s0.shotCount, interval = r2(s1.interval), lowAfter = at(rowsF, rowsF[#rowsF].t).low,
		note = "firing during the throw is not blocked: the reference never shows it (UNKNOWN)" }
	w("refill")
	-- switch mid-reload, then throw, then back
	Run.setup("M4")
	w("setAmmo", PARTIAL)
	frames(0.5)
	w("reload")
	frames(0.4)
	local rowsW, pressW = record(0.9, {
		{ at = 0.05, fn = function() player:SetAttribute("EquippedWeapon", "AK") end },
		{ at = 0.6, fn = function() player:SetAttribute("EquippedWeapon", "M4") end },
	})
	frames(0.4)
	local sw = w("sync")
	out.switchMidReload = { weapon = sw.weapon, reloading = sw.reloading, lowAfter = at(rowsW, rowsW[#rowsW].t).low,
		hiddenAtL5 = at(rowsW, pressW + 8 * F).inView <= 2, viewmodels = sw.viewmodels }
	w("refill")
	out.leftovers = Run.leftovers()
	out.pass = out.reload.started and out.reload.stillReloadingAfterThrow ~= nil and out.reload.finished and out.ads.hiddenAtL5 and out.ads.lowAfter == 0 and (out.ads.aimAlphaAfter or 0) > 0.9
		and out.scope.hiddenAtL5 and out.scope.stateBefore == out.scope.stateAfter and out.firing.shots > 0
		and out.firing.lowAfter == 0 and out.switchMidReload.hiddenAtL5 and out.switchMidReload.viewmodels == 1
		and out.leftovers.clean
	return out
end

function Run.movement(): any
	local out = {}
	local function one(name: string, actions: { any }, before: (() -> ())?)
		Run.setup("M4")
		g("predictionClear")
		if before then
			before()
		end
		local rows, press = record(1.4, actions)
		mHook:Invoke("input", nil)
		frames(0.3)
		local rec = lastRecord()
		local f = flight(rows, press)
		out[name] = { record = compactRecord(rec), longestHoldRows = f.longestHoldRows, reversals = f.reversals,
			hiddenAtL5 = at(rows, press + 8 * F).inView <= 2, lowAfter = at(rows, press + 0.7).low }
	end
	one("walk", { { at = -0.2, fn = function() mHook:Invoke("input", Vector3.new(0, 0, -1)) end } })
	one("crouch", {}, function()
		mHook:Invoke("crouch", true)
		frames(0.6)
	end)
	mHook:Invoke("crouch", false)
	frames(0.5)
	one("jump", { { at = -0.05, fn = function() humanoid().Jump = true end } })
	one("fall", {}, function()
		local r = root()
		r.CFrame = r.CFrame + Vector3.new(0, 25, 0)
		frames(0.1)
	end)
	frames(1.0)
	out.leftovers = Run.leftovers()
	local pass = out.leftovers.clean
	for _, k in { "walk", "crouch", "jump", "fall" } do
		local o = out[k]
		pass = pass and o.record ~= nil and (o.record.how == "HandedOver" or o.record.how == "AtContact")
			and o.longestHoldRows == 0 and o.hiddenAtL5 and o.lowAfter == 0
	end
	out.pass = pass
	return out
end

-- Outside a throw the lowering is exactly the identity: every frame of fire / recoil / reload / ADS has lower == 0
function Run.idle(weapon: string?): any
	Run.setup(weapon or "M4")
	w("record", true)
	w("trigger", true)
	frames(0.6)
	w("trigger", false)
	w("aim", true)
	frames(0.5)
	w("aim", false)
	w("setAmmo", PARTIAL)
	frames(0.3)
	w("reload")
	frames(1.0)
	local rec = w("record", false)
	local nonZero = 0
	for _, e in rec.log do
		if (e.lower or 0) ~= 0 then
			nonZero += 1
		end
	end
	w("refill")
	return { pass = nonZero == 0 and #rec.log > 60, frames = #rec.log, framesLowered = nonZero, shots = #rec.shots }
end

-- Malformed / forged "Released" messages through the client's own handler (what an exploit could do on its own
-- machine): rejected, or a local proxy only; nothing reaches the server (checked by the server half)
function Run.forged(): any
	local before = (g("prediction") :: any).Stats
	local bad = {
		{ Phase = "Released" },
		{ Phase = "Released", Id = "x", Origin = Vector3.zero, Velocity = Vector3.zero, ServerTime = 0 },
		{ Phase = "Released", Id = 1, Origin = Vector3.new(0 / 0, 0, 0), Velocity = Vector3.zero, ServerTime = 0 },
		{ Phase = "Released", Id = 1, Origin = Vector3.zero, Velocity = Vector3.new(math.huge, 0, 0), ServerTime = 0 },
		{ Phase = "Released", Id = 1, Origin = Vector3.zero, Velocity = Vector3.zero },
	}
	local rejected = 0
	for _, m in bad do
		if g("predictReleased", m) == false then
			rejected += 1
		end
	end
	-- a well-formed fake: a grenade id the server never made, launched from a far point
	local fake = { Phase = "Released", Id = 999999, Origin = root().Position + Vector3.new(0, 20, 0),
		Velocity = Vector3.new(0, 0, 30), ServerTime = workspace:GetServerTimeNow() }
	local accepted = g("predictReleased", fake)
	frames(0.3)
	local mid = g("prediction")
	frames(Config.Prediction.GiveUpSeconds + 0.3)
	local after = g("prediction")
	local rec = after.Records[#after.Records]
	return { pass = rejected == #bad and accepted == true and #after.Active == 0 and rec and rec.Id == 999999,
		malformedRejected = rejected, of = #bad, fakeShownLocally = #mid.Active == 1, fakeEndedAs = rec and rec.How,
		rejectedBefore = before.Rejected, rejectedAfter = after.Stats.Rejected }
end

-- death tests: "before" = killed before the release (the server's killDuringThrow(0.05) must be armed first);
-- "after" = killed with the grenade in flight (killDuringThrow(0.3))
function Run.death(stage: string): any
	Run.setup("M4")
	g("clear")
	local hum = humanoid()
	local diedAt: number? = nil
	local c = hum.Died:Connect(function()
		diedAt = os.clock()
	end)
	local rows, press, sampledFrom = record(1.0)
	c:Disconnect()
	local msgs = g("messages")
	local refused, released = nil, 0
	for _, m in msgs do
		if m.Phase == "Refused" then
			refused = m.Reason
		elseif m.Phase == "Released" then
			released += 1
		end
	end
	-- after the death: no arm, no proxy (before) / the proxy's flight ends no later than the respawn (after)
	local armAfterDeath, proxyAfterDeath = false, false
	local t0 = sampledFrom
	for _, r in rows do
		if diedAt and t0 + r.t > diedAt + 0.02 then
			armAfterDeath = armAfterDeath or r.arm
			proxyAfterDeath = proxyAfterDeath or r.which == "proxy"
		end
	end
	local pr = g("prediction")
	local out = { stage = stage, died = diedAt ~= nil, diedAfterPressS = diedAt and r2(diedAt - (t0 + press)),
		refused = refused, released = released, armAfterDeath = armAfterDeath, proxyAfterDeath = proxyAfterDeath,
		lastRecord = compactRecord(pr.Records[#pr.Records]) }
	-- respawn
	local t1 = os.clock()
	while (player.Character == nil or humanoid().Health <= 0) and os.clock() - t1 < 12 do
		frames(0.2)
	end
	frames(1.5)
	out.respawned = humanoid().Health > 0
	out.afterRespawn = Run.leftovers()
	if stage == "before" then
		out.pass = out.died and refused ~= nil and released == 0 and not armAfterDeath and not proxyAfterDeath
			and out.respawned and out.afterRespawn.clean
	else
		out.pass = out.died and released == 1 and not armAfterDeath and out.respawned and out.afterRespawn.clean
	end
	return out
end

-- forged throw arguments: a position / velocity next to the aim (the server takes the aim only; checked server-side)
function Run.forgeThrowArgs(): any
	Command:FireServer("DevRefill")
	frames(0.3)
	g("clear")
	local cam = workspace.CurrentCamera
	Command:FireServer("Throw", cam.CFrame.LookVector, Vector3.new(0, 500, 0), Vector3.new(9999, 0, 0), 1e9)
	frames(0.5)
	local refused = nil
	for _, m in g("messages") do
		if m.Phase == "Refused" then
			refused = m.Reason
		end
	end
	Command:FireServer("Throw", cam.CFrame.LookVector * 55) -- a velocity, not a direction
	frames(0.5)
	for _, m in g("messages") do
		if m.Phase == "Refused" then
			refused = m.Reason
		end
	end
	return { lastRefusal = refused, aim = cam.CFrame.LookVector, head = (player.Character :: any).Head.Position }
end

return Run
