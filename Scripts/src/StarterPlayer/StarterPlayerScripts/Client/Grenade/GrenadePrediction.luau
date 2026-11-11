--!strict
-- Grenade release prediction (first-person fidelity pass; the thrower's own client only; presentation only).
-- The server owns the grenade: its body, collisions, bounces, fuse, detonation, fragments and damage. On the thrower's
-- client the replicated body sits still at the release point for ≈ 0.2 s and then trails the server's path by ≈ 0.19 s
-- (Studio measurement, ReferenceAnalysis/FirstPerson); the reference's grenade leaves the hand in the frame after the
-- release (L+2). So this client draws a local look-alike ("proxy") and hides the replicated body on this client only
-- (LocalTransparencyModifier) until the two coincide:
--   1 local    from the release on this client's clock (press + ReleaseSeconds), on the path the server's own rule gives
--              for this client's head and the aim it sent (Server.Grenade.Throw.launch / direction); shown from the frame
--              the in-hand grenade of ThrowPresentation disappears (release + 1 frame)
--   2 server   when the server's "Released" message arrives (its release point, launch velocity and time), the proxy
--              moves onto THAT path; the difference to the local path fades out along the flight until stage 3 ends
--   3 catch up the proxy's clock runs evenly slower from the release by the replicated body's lag (planned from the
--              last throws, then measured every frame once the body moves), so it is on the body's track by the
--              predicted first contact, or by CatchUpBy for a long flight (it runs slower; it never jumps back)
--   4 hand over the proxy goes, the replicated body is shown: the same point of the same path
-- The path's first contact with geometry is swept once per path; the server's bounce is never predicted: the proxy
-- reaches the contact point with the replicated body (it holds there only if the lag was larger than planned). A refusal, death, respawn or a missing
-- answer removes a proxy the server never confirmed. Nothing is sent to the server and nothing here changes any game
-- state: the proxy is parented to this client's camera, LocalTransparencyModifier does not replicate. Values:
-- Shared.Config.Grenade.Prediction (all [implementation]).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Grenade"))
local P = Config.Prediction
local B = Config.Body
local T = Config.Throw

local Prediction = {}
Prediction.Stats = { Expected = 0, Released = 0, ServerOnly = 0, HandedOver = 0, AtContact = 0, GaveUp = 0,
	Cancelled = 0, TimedOut = 0, Rejected = 0, ProxiesBuilt = 0 }

local player = Players.LocalPlayer
local G = Vector3.new(0, -B.Gravity, 0)
local items: { any } = {}
local bound = false
local pool: { BasePart } = {}
local records: { any } = {} -- Studio / tests: one per finished item
local maxSeenId = 0 -- the highest grenade id a "Released" message named (older bodies are never claimed)
local lastLags: { number } = {} -- the last measured lags (the next throw plans for their median)

local function finite(v: Vector3): boolean
	for _, n in { v.X, v.Y, v.Z } do
		if n ~= n or n == math.huge or n == -math.huge then
			return false
		end
	end
	return true
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function pathAt(it: any, tau: number): Vector3
	return it.Origin + it.Velocity * tau + G * (0.5 * tau * tau)
end

-- the server's launch rule (Server.Grenade.Throw.direction), for the local start only: the server's message replaces it
local function direction(dir: Vector3): Vector3
	local frame = CFrame.lookAt(Vector3.zero, dir)
	return (frame * CFrame.Angles(0, math.rad(T.YawLeftDeg or 0), 0) * CFrame.Angles(math.rad(T.LiftDeg or 0), 0, 0)).LookVector
end

-- the server's release point rule (Server.Grenade.Throw.launch), from this client's head
local function localLaunch(aim: Vector3): (Vector3?, Vector3?)
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not (character and head) then
		return nil, nil
	end
	local frame = CFrame.lookAt(head.Position, head.Position + aim)
	local hand = frame:PointToWorldSpace(T.HandOffset)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local blocked = workspace:Raycast(head.Position, hand - head.Position, params)
	if blocked then
		hand = blocked.Position - (hand - head.Position).Unit * (B.Diameter * 0.75)
	end
	return hand, direction(aim) * T.Speed
end

local function buildProxy(): BasePart
	local ball = table.remove(pool)
	if ball then
		ball.Parent = workspace.CurrentCamera
		return ball
	end
	ball = Instance.new("Part")
	local b = ball :: BasePart
	b.Name = "GrenadeProxy"
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.new(B.Diameter, B.Diameter, B.Diameter)
	b.Color = B.Color
	b.Material = Enum.Material.SmoothPlastic
	b.Anchored = true
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	b.CastShadow = false
	local band = Instance.new("Part")
	band.Name = "Band"
	band.Shape = Enum.PartType.Cylinder
	band.Size = Vector3.new(B.Diameter * 0.18, B.Diameter * 1.04, B.Diameter * 1.04)
	band.Color = B.BandColor
	band.Material = Enum.Material.SmoothPlastic
	band.Anchored = true
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.CastShadow = false
	band.Parent = b
	b.Parent = workspace.CurrentCamera
	Prediction.Stats.ProxiesBuilt += 1
	return b
end

local function releaseProxy(proxy: BasePart?)
	if not proxy then
		return
	end
	if #pool < P.Pool then
		proxy.Parent = nil
		table.insert(pool, proxy)
	else
		proxy:Destroy()
	end
end

local function place(proxy: BasePart, pos: Vector3, vel: Vector3)
	local cf = if vel.Magnitude > 1e-3 then CFrame.lookAt(pos, pos + vel) else CFrame.new(pos) * proxy.CFrame.Rotation
	proxy.CFrame = cf
	local band = proxy:FindFirstChild("Band") :: BasePart?
	if band then
		band.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	end
end

local function findBody(id: number): BasePart?
	local f = workspace:FindFirstChild("Grenades")
	if not f then
		return nil
	end
	for _, c in f:GetChildren() do
		if c:IsA("BasePart") and c:GetAttribute("GrenadeId") == id then
			return c
		end
	end
	return nil
end

local function setHidden(body: BasePart, hidden: boolean)
	local m = if hidden then 1 else 0
	body.LocalTransparencyModifier = m
	for _, d in body:GetChildren() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = m
		end
	end
end

-- first contact of a ballistic path with collidable geometry (this character, grenades and the camera's parts excluded)
local function firstContact(it: any): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore: { Instance } = { workspace.CurrentCamera }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local grenades = workspace:FindFirstChild("Grenades")
	if grenades then
		table.insert(ignore, grenades)
	end
	params.FilterDescendantsInstances = ignore
	local prev = it.Origin
	local tau = 0
	while tau < P.HorizonSeconds do
		local nxt = tau + P.Step
		local p = pathAt(it, nxt)
		local d = p - prev
		local hit = workspace:Raycast(prev, d + d.Unit * (B.Diameter / 2), params)
		if hit then
			return math.max(0, tau + P.Step * math.clamp((hit.Distance - B.Diameter / 2) / d.Magnitude, 0, 1))
		end
		prev, tau = p, nxt
	end
	return P.HorizonSeconds
end

-- where on the server path the replicated body is (path time), searched near the last answer
local function bodyPathTime(it: any, body: BasePart, vt: number): (number, number)
	local lo, hi, stepT = 0, math.min(vt + 0.1, it.Contact), 1 / 240
	if it.BodyT then
		lo, hi = math.max(0, it.BodyT - 0.05), math.min(it.Contact, it.BodyT + 0.12)
	end
	local best, bestT = math.huge, lo
	local tr = lo
	while tr <= hi do
		local dd = (pathAt(it, tr) - body.Position).Magnitude
		if dd < best then
			best, bestT = dd, tr
		end
		tr += stepT
	end
	-- refine to 1/4800 s (≈ 0.01 studs at the throw speed)
	local a, b = math.max(lo, bestT - stepT), math.min(hi, bestT + stepT)
	tr = a
	while tr <= b do
		local dd = (pathAt(it, tr) - body.Position).Magnitude
		if dd < best then
			best, bestT = dd, tr
		end
		tr += stepT / 20
	end
	return bestT, best
end

local function record(it: any, how: string, extra: any?)
	local r = { Id = it.Id, How = how, Local = it.Local, Lag = it.D, MatchError = it.MatchError, ErrorAtServer = it.Err0Mag,
		MessageDelay = it.MessageDelay, Contact = it.Contact, Held = it.HeldFor, ShownAt = it.ShownAt, Rc = it.Rc,
		PlannedLag = it.D0, Th = it.Th, FinishedAt = os.clock() }
	if extra then
		for k, v in extra do
			r[k] = v
		end
	end
	table.insert(records, r)
	while #records > 32 do
		table.remove(records, 1)
	end
end

local function finish(i: number, how: string)
	local it = items[i]
	if it.Body and it.Body.Parent then
		setHidden(it.Body, false)
	end
	releaseProxy(it.Proxy)
	table.remove(items, i)
	Prediction.Stats[how] += 1
	record(it, how)
	if it.CatchStart and it.D then
		table.insert(lastLags, it.D)
		while #lastLags > 9 do
			table.remove(lastLags, 1)
		end
	end
end

-- the lag to plan for before this throw's body moves: the median of the last measured ones, else the config's
local function expectedLag(): number
	if #lastLags == 0 then
		return P.ExpectedLag
	end
	local s = table.clone(lastLags)
	table.sort(s)
	return s[math.floor((#s + 1) / 2)]
end

-- the proxy is where it should be; from now on it follows the replicated body, its offset fading out
local function startBlend(it: any, pos: Vector3, body: BasePart, how: string)
	if not it.Proxy then
		it.Proxy = buildProxy()
		it.ShownAt = it.ShownAt or 0
	end
	it.Blending, it.BlendAt, it.BlendFrom = how, os.clock(), pos - body.Position
	place(it.Proxy, pos, body.AssemblyLinearVelocity)
end

local function claimed(body: BasePart): boolean
	for _, it in items do
		if it.Body == body then
			return true
		end
	end
	return false
end

local function step()
	local now = os.clock()
	for i = #items, 1, -1 do
		local it = items[i]
		local vt = now - it.Rc -- seconds since the release, on this client's clock
		if vt < 0 then
			continue
		end
		if not it.Origin then -- local start: the server's rule from this client's head and the aim it sent
			local o, v = localLaunch(it.Aim)
			if not (o and v) then
				finish(i, "Cancelled")
				continue
			end
			it.Origin, it.Velocity = o, v
			it.Contact = firstContact(it)
		end
		if not it.Id and vt > P.PendingSeconds then
			finish(i, "TimedOut") -- the server never confirmed this throw
			continue
		end
		if vt > P.GiveUpSeconds then
			finish(i, "GaveUp")
			continue
		end
		local body: BasePart? = nil
		if not it.Id and not it.Body then
			-- the server's body can replicate a frame before its "Released" message: hide a new, unclaimed body at
			-- this throw's release point until the message says whose it is
			local f = workspace:FindFirstChild("Grenades")
			if f then
				for _, c in f:GetChildren() do
					local gid = c:GetAttribute("GrenadeId")
					if c:IsA("BasePart") and typeof(gid) == "number" and gid > maxSeenId and not claimed(c)
						and (c.Position - it.Origin).Magnitude < P.ClaimRadius then
						it.Body = c
						setHidden(c, true)
						break
					end
				end
			end
		end
		if it.Id then
			if not (it.Body and it.Body.Parent) then
				it.Body = findBody(it.Id)
			end
			body = it.Body
			if body and body.Parent then
				it.SeenBody = true
				setHidden(body, true)
			elseif it.SeenBody then
				finish(i, "GaveUp") -- the server removed it (detonated / lost): show what the server shows
				continue
			end
		end
		if it.Blending and body then
			-- hand-over blend: the proxy runs on the replicated body, its last offset fading out, then goes
			local u = (now - it.BlendAt) / P.HandoverBlendSeconds
			if u >= 1 then
				finish(i, it.Blending)
				continue
			end
			place(it.Proxy, body.Position + it.BlendFrom * (1 - smooth(u)), body.AssemblyLinearVelocity)
			continue
		end
		local moving = body ~= nil and it.FromServer and (body.Position - it.Origin).Magnitude > 0.05
		if moving and body then
			local bt, err = bodyPathTime(it, body, vt)
			if bt < it.Contact - 1 / 120 then
				local d = math.clamp(vt - bt, -P.MaxLead, P.MaxLag)
				it.CatchStart = it.CatchStart or vt
				local cur = it.D or it.D0
				it.D = cur + P.LagSmoothing * (d - cur) -- from the planned lag to the measured one, smoothly
			end
			it.BodyT, it.BodyErr = bt, err
		end
		-- the proxy's clock runs evenly slower from the release, by the lag (estimated until the body moves, then
		-- measured), so that it is on the replicated body's track by Th: the predicted contact (it then reaches the
		-- contact point together with the replicated body: no hold) or CatchUpBy for a long flight. Never backwards.
		local D = it.D or it.D0
		local th = math.min(P.CatchUpBy, it.Contact + D)
		it.Th = th
		local floor = (it.LastShown or 0) + P.MinSpeed * math.max(0, vt - (it.LastVt or vt)) -- never slower than MinSpeed
		local shown = math.max(floor, vt - D * math.min(1, vt / th))
		it.LastShown, it.LastVt = shown, vt
		-- the local → server path difference fades out along the flight, gone where the proxy is on track (the
		-- contact point, or by CatchUpBy): a jump or fall can put the server's release point (its own copy of the head)
		-- several studs from this client's hand
		local off = Vector3.zero
		if it.Err0 then
			local endT = math.max(it.ErrFromT + P.ErrorFadeMin, math.min(it.Contact, th - D))
			off = it.Err0 * (1 - smooth((shown - it.ErrFromT) / (endT - it.ErrFromT)))
		end
		local pos, vel
		if shown < it.Contact then
			pos, vel = pathAt(it, shown) + off, it.Velocity + G * shown
			-- hand over once on track: not ahead of the replicated body on the path (a lag larger than planned leaves
			-- the proxy ahead at Th; it then keeps running at MinSpeed until the body has caught up)
			if it.CatchStart and vt >= th and body and shown <= (it.BodyT or math.huge) + P.OnTrackTolerance then
				it.MatchError = (pos - body.Position).Magnitude
				startBlend(it, pos, body, "HandedOver")
				continue
			end
		else
			pos, vel = pathAt(it, it.Contact) + off, Vector3.zero
			it.HoldStart = it.HoldStart or now
			it.HeldFor = now - it.HoldStart
			-- the replicated body has reached the contact point: it is there, or it has turned away from it (its bounce)
			local arrived = false
			if moving and body then
				local dist = (body.Position - pathAt(it, it.Contact)).Magnitude
				arrived = dist < P.ContactArrive or (it.ContactDist ~= nil and it.ContactDist < 1 and dist > it.ContactDist + 0.01)
				it.ContactDist = dist
			end
			if arrived or it.HeldFor > P.HoldMaxSeconds then
				it.MatchError = if body then (pos - body.Position).Magnitude else nil
				if body and it.Proxy then
					startBlend(it, pos, body, "AtContact")
				else
					finish(i, "AtContact")
				end
				continue
			end
		end
		it.Shown, it.ShownVel = pos, vel
		if vt >= P.ShowAfter then
			if not it.Proxy then
				it.Proxy = buildProxy()
				it.ShownAt = vt
			end
			place(it.Proxy, pos, vel)
		end
	end
	if #items == 0 and bound then
		RunService:UnbindFromRenderStep("GrenadePrediction")
		bound = false
	end
end

local function bind()
	if not bound then
		bound = true
		RunService:BindToRenderStep("GrenadePrediction", Enum.RenderPriority.Camera.Value + 3, step)
	end
end

-- A throw this client asked for and presents (GrenadeClient.press): the local start, at press + ReleaseSeconds.
function Prediction.expect(aim: Vector3, pressedAt: number)
	if typeof(aim) ~= "Vector3" or not finite(aim) or aim.Magnitude < 1e-3 then
		return
	end
	table.insert(items, { Local = true, Aim = aim.Unit, Rc = pressedAt + T.ReleaseSeconds, D0 = expectedLag() })
	Prediction.Stats.Expected += 1
	bind()
end

-- The server's "Released" message: { Id, Origin, Velocity, ServerTime }. Joins the oldest unconfirmed local throw, or
-- starts a proxy on the server's path at its present point.
function Prediction.released(msg: any): boolean
	if typeof(msg) ~= "table" or typeof(msg.Id) ~= "number" or typeof(msg.Origin) ~= "Vector3"
		or typeof(msg.Velocity) ~= "Vector3" or typeof(msg.ServerTime) ~= "number" or not finite(msg.Origin)
		or not finite(msg.Velocity) then
		Prediction.Stats.Rejected += 1
		return false
	end
	local now = os.clock()
	local delay = math.max(0, workspace:GetServerTimeNow() - msg.ServerTime)
	local it: any = nil
	for _, c in items do
		if c.Local and not c.Id then
			it = c
			break
		end
	end
	if it then
		Prediction.Stats.Released += 1
		if it.Body and it.Body:GetAttribute("GrenadeId") ~= msg.Id then
			setHidden(it.Body, false) -- hidden as this throw's, but it is another grenade
			it.Body = nil
		end
		-- the local path and the server's, compared at the same point of the flight (the proxy's own clock): that
		-- difference fades out, so the proxy carries on from exactly where it is
		local at = math.clamp(it.LastShown or 0, 0, it.Contact or math.huge)
		local before: Vector3? = if it.Origin then pathAt(it, at) else nil
		it.Origin, it.Velocity = msg.Origin, msg.Velocity
		it.Contact = firstContact(it)
		if before then
			local e = before - pathAt(it, math.min(at, it.Contact))
			it.Err0, it.ErrFromT, it.Err0Mag = e, math.min(at, it.Contact), e.Magnitude
		end
	else
		Prediction.Stats.ServerOnly += 1
		it = { Local = false, Rc = now - delay, Origin = msg.Origin, Velocity = msg.Velocity, D0 = expectedLag() }
		it.Contact = firstContact(it)
		table.insert(items, it)
	end
	it.Id, it.FromServer, it.ServerTime, it.MessageDelay = msg.Id, true, msg.ServerTime, delay
	-- the message's own delay is a lower bound for the replicated body's lag (plus the replication buffer)
	it.D0 = math.max(it.D0 or P.ExpectedLag, delay + P.ReplicationBuffer)
	maxSeenId = math.max(maxSeenId, msg.Id)
	bind()
	return true
end

-- The server refused a throw (or it died before the release): drop the oldest unconfirmed local proxy.
function Prediction.refused()
	for i, c in items do
		if c.Local and not c.Id then
			finish(i, "Cancelled")
			return
		end
	end
end

-- Death: nothing unconfirmed can still be released. Respawn: everything goes back to what the server shows.
function Prediction.cancelPending()
	for i = #items, 1, -1 do
		if items[i].Local and not items[i].Id then
			finish(i, "Cancelled")
		end
	end
end

function Prediction.reset()
	for i = #items, 1, -1 do
		finish(i, "Cancelled")
	end
end

-- Studio / tests
function Prediction.read(): any
	local list = {}
	for _, it in items do
		table.insert(list, { Id = it.Id, Local = it.Local, Lag = it.D, Contact = it.Contact, BodyT = it.BodyT,
			BodyErr = it.BodyErr, Shown = it.Shown, Visible = it.Proxy ~= nil, Rc = it.Rc,
			Phase = if it.Blending then "blend" elseif it.HoldStart then "hold" else "flight" })
	end
	return { Active = list, Stats = table.clone(Prediction.Stats), Records = table.clone(records), Pool = #pool,
		Bound = bound }
end

function Prediction.clear()
	table.clear(records)
end

return Prediction
