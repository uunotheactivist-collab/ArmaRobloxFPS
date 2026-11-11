--!strict
-- Player movement authority (server). Evidence and values: Shared.Config.Movement, ReferenceAnalysis/Movement.
--   * Owns the stance (STAND / CROUCH) and the movement state (IDLE, WALK, CROUCH, JUMP, FALL, LAND, DEAD) as character
--     attributes. Clients only send an intent ("Crouch", true/false) through Remotes.MovementIntent; it is validated
--     (type, alive, rate, interaction lock, room to stand) before anything changes.
--   * Sets the speeds: Humanoid.WalkSpeed / JumpHeight / HipHeight per stance. Crouching lowers the whole body, so hit
--     boxes and AI aim points drop with the camera.
--   * Validates where the client-simulated character goes, on a 10 Hz timer (no per-frame work): a travel budget against
--     the server's own WalkSpeed (a client that raises its local speed, teleports or flies is moved back), a ceiling on
--     how high it can be above the floor it last stood on, no passing through anchored walls, no hovering, no body held
--     higher than its stance. One downward ray and at most one path ray per character per check.
--   * Never fights an interaction: when something else (dragging) sets the walk speed, it leaves the speed alone and
--     refuses stance changes until the speed is handed back.
--   * Vehicles (truck slice): the server-only BindableFunction MovementControl lets Server.Vehicles mount a character
--     (welded to a vehicle seat: no walking, no jumping, no stance change, validation paused and re-baselined), place
--     it (a server placement the validator accepts, as the Studio test teleport does) and read the last place this
--     validator accepted ("validated"). Clients can't reach it.
-- No sprint (UNKNOWN in the footage; not built). Jump stays the engine default (PLACEHOLDER, never shown).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Movement"))
local Rules = require(script.Parent:WaitForChild("MovementRules"))
local Intent = Shared:WaitForChild("Remotes"):WaitForChild("MovementIntent") :: RemoteEvent

local A = Config.Attributes
local S = Config.Server

type Track = {
	Player: Player,
	Character: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Stance: string,
	State: string,
	LandUntil: number,
	Budget: number,
	LastPos: Vector3,
	LastValid: CFrame,
	LastCheck: number,
	SupportY: number,
	Grounded: boolean,
	AirSince: number?,
	HighSince: number?, -- body held above its stance since
	LastWritten: number,
	StandHip: number,
	Crouched: boolean, -- the hip height is currently lowered
	StandRoot: number, -- standing root centre above the feet
	StandTop: number, -- standing head top above the feet
	StanceChangedAt: number,
	GraceUntil: number, -- just spawned: re-baseline instead of validating
	Pending: { CFrame: CFrame, Until: number }?, -- a server placement the client hasn't reported yet
	Locked: string?,
	Mounted: boolean, -- seated in a vehicle (Server.Vehicles): validation paused
	Dead: boolean,
	Rejections: number,
	IntentWindow: number,
	IntentCount: number,
}

local tracks: { [Player]: Track } = {}
local wake = Instance.new("BindableEvent")
local allowClientTeleports = false -- Studio test switch only (see the debug hook)

local log: { any } = {}
local function note(kind: string, player: Player?, detail: string)
	table.insert(log, { t = os.clock(), kind = kind, player = player and player.Name or "", detail = detail })
	if #log > 600 then
		table.remove(log, 1)
	end
end

local perf = { Checks = 0, Seconds = 0, MaxSeconds = 0, Rays = 0 }

local function setAttr(t: Track, name: string, value: any)
	if t.Character:GetAttribute(name) ~= value then
		t.Character:SetAttribute(name, value)
	end
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local function ground(t: Track, from: Vector3): RaycastResult?
	groundParams.FilterDescendantsInstances = { t.Character }
	perf.Rays += 1
	return workspace:Raycast(from, Vector3.new(0, -S.GroundProbe, 0), groundParams)
end

-- Apply the stance's speeds unless an interaction currently owns the walk speed.
local function apply(t: Track)
	local hum = t.Humanoid
	if t.Dead then
		return
	end
	if hum.WalkSpeed ~= t.LastWritten then
		return -- someone else (an interaction) set it: leave it; the lock is tracked by the check loop
	end
	hum.WalkSpeed = Rules.speedFor(t.Stance, Config)
	t.LastWritten = hum.WalkSpeed -- read back: the property is single precision
	hum.JumpHeight = Rules.jumpFor(t.Stance, Config)
	-- the hip height is only touched across a stance change (the avatar's own scaling owns it while standing)
	if t.Stance == "CROUCH" and not t.Crouched then
		t.StandHip = hum.HipHeight
		hum.HipHeight = Rules.hipFor("CROUCH", t.StandHip, Config)
		t.Crouched = true
	elseif t.Stance == "STAND" and t.Crouched then
		hum.HipHeight = t.StandHip
		t.Crouched = false
	end
end

-- Standing body measurements (the avatar's scaling can change them after spawn).
local function measure(t: Track)
	if t.Crouched then
		return
	end
	local hum, root = t.Humanoid, t.Root
	local feetY = root.Position.Y - root.Size.Y / 2 - hum.HipHeight
	local head = t.Character:FindFirstChild("Head") :: BasePart?
	t.StandHip = hum.HipHeight
	t.StandRoot = hum.HipHeight + root.Size.Y / 2
	t.StandTop = if head then head.Position.Y + head.Size.Y / 2 - feetY else t.StandRoot + root.Size.Y / 2 + 1
end

local function standBlocked(t: Track): boolean
	local root, hum = t.Root, t.Humanoid
	local feetY = root.Position.Y - root.Size.Y / 2 - hum.HipHeight
	local bottom = root.Position.Y + root.Size.Y / 2
	local top = feetY + t.StandTop + Config.Crouch.StandClearance
	if top <= bottom then
		return false
	end
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local cf = CFrame.new(root.Position.X, (top + bottom) / 2, root.Position.Z) * CFrame.Angles(0, yaw, 0)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { t.Character }
	params.RespectCanCollide = true
	return #workspace:GetPartBoundsInBox(cf, Vector3.new(root.Size.X, top - bottom, math.max(root.Size.Z, 1)), params) > 0
end

local function setStance(t: Track, stance: string, why: string)
	if t.Stance == stance then
		return
	end
	t.Stance = stance
	t.StanceChangedAt = os.clock()
	apply(t)
	setAttr(t, A.Stance, stance)
	note("stance", t.Player, stance .. " (" .. why .. ")")
end

-- Move the character back to its last legal place (server write; it replicates to the owning client).
local function correct(t: Track, reason: string)
	if allowClientTeleports then
		-- Studio test switch: the accepted regression tests place the player by client-side teleports.
		t.LastValid = t.Root.CFrame
		t.LastPos = t.Root.Position
		t.Budget = S.BankStuds
		local hit = ground(t, t.Root.Position)
		if hit then
			t.SupportY = hit.Position.Y
		end
		note("allowed", t.Player, reason .. " (Studio client-teleport switch on)")
		return
	end
	t.Root.CFrame = t.LastValid
	t.Root.AssemblyLinearVelocity = Vector3.zero
	t.LastPos = t.LastValid.Position
	t.Budget = 0 -- no fresh allowance right after a correction
	t.AirSince = nil
	t.Rejections += 1
	setAttr(t, A.Rejections, t.Rejections)
	note("reject", t.Player, reason)
end

local function check(t: Track, now: number)
	local root, hum = t.Root, t.Humanoid
	local dt = now - t.LastCheck
	t.LastCheck = now
	if t.Dead or hum.Health <= 0 then
		if not t.Dead then
			t.Dead = true
		end
		if t.State ~= "DEAD" then
			t.State = "DEAD"
			setAttr(t, A.MoveState, "DEAD")
			note("state", t.Player, "DEAD")
		end
		return
	end
	if t.Mounted then
		-- welded to a vehicle seat (an anchored assembly the client can't move): nothing to validate; keep the baseline
		t.LastPos, t.LastValid, t.Budget = root.Position, root.CFrame, S.BankStuds
		t.AirSince, t.HighSince = nil, nil
		return
	end
	-- an interaction owns the walk speed (dragging): lock the stance until it hands it back
	local locked = if hum.WalkSpeed ~= t.LastWritten then "Interaction" else nil
	if locked ~= t.Locked then
		t.Locked = locked
		setAttr(t, A.Locked, locked)
		note("lock", t.Player, tostring(locked))
		if not locked then
			apply(t)
		end
	end

	local pos = root.Position
	if Rules.invalidPosition(pos) then
		correct(t, "invalid position")
		return
	end
	local pending = t.Pending
	if pending then
		if (pos - pending.CFrame.Position).Magnitude > 3 and now < pending.Until then
			root.CFrame = pending.CFrame -- the client is still reporting where it was before the placement
			return
		end
		t.Pending = nil
	end
	local hit = ground(t, pos)
	if now < t.GraceUntil then
		t.LastPos, t.LastValid, t.Budget = pos, root.CFrame, S.BankStuds
		if hit then
			t.SupportY = hit.Position.Y
		end
		return
	end
	local rootBottom = pos.Y - root.Size.Y / 2
	local grounded = hit ~= nil and rootBottom - hit.Position.Y <= hum.HipHeight + S.GroundedGap
	local prevPos = t.LastPos
	local flat = Vector3.new(pos.X - prevPos.X, 0, pos.Z - prevPos.Z)
	local moved = flat.Magnitude
	local rise = if dt > 0 then (pos.Y - prevPos.Y) / dt else 0

	local reason: string? = nil
	local budget, over = Rules.budgetStep(t.Budget, hum.WalkSpeed, dt, moved, Config)
	t.Budget = budget
	if over then
		reason = string.format("too fast: %.2f studs in %.2f s (cap %.1f studs/s)", moved, dt, hum.WalkSpeed)
	end
	if not reason and pos.Y > Rules.riseLimit(t.SupportY, t.StandRoot, Config) then
		reason = string.format("too high: %.2f studs above the last floor", pos.Y - t.SupportY)
	end
	if not reason and moved > 0.25 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { t.Character }
		params.RespectCanCollide = true
		local d = pos - prevPos
		if d.Magnitude > S.BlockedPathMaxStuds then
			d = d.Unit * S.BlockedPathMaxStuds
		end
		perf.Rays += 1
		local wall = workspace:Raycast(prevPos, d, params)
		if wall and wall.Instance.Anchored then
			reason = "through a wall: " .. wall.Instance:GetFullName()
		end
	end
	if not reason then
		if grounded then
			t.AirSince = nil
		elseif t.AirSince == nil then
			t.AirSince = now
		elseif now - t.AirSince > 1.5 and rise > -2 then
			reason = "hovering"
		end
	end
	-- a body held above its stance for 0.5 s (a jump passes through this band in well under 0.1 s)
	if not reason and grounded and hit and now - t.StanceChangedAt > 0.6 and rootBottom - hit.Position.Y > hum.HipHeight + 0.9 then
		t.HighSince = t.HighSince or now
		if now - (t.HighSince :: number) > 0.5 then
			reason = string.format("body held %.2f studs above its stance", rootBottom - hit.Position.Y - hum.HipHeight)
			t.HighSince = nil
		end
	else
		t.HighSince = nil
	end
	if reason then
		correct(t, reason)
		if not allowClientTeleports then
			return
		end
	else
		t.LastPos = pos
		t.LastValid = root.CFrame
	end
	if grounded and hit then
		t.SupportY = hit.Position.Y
		if t.Stance == "STAND" then
			measure(t)
		end
	end
	t.Grounded = grounded

	local state, landUntil = Rules.nextState({ State = t.State, LandUntil = t.LandUntil }, {
		Dead = false,
		Grounded = grounded,
		RiseSpeed = rise,
		FlatSpeed = if dt > 0 then moved / dt else 0,
		Stance = t.Stance,
		Now = now,
		Settling = now - t.StanceChangedAt < 0.4,
	}, Config)
	t.LandUntil = landUntil
	if state ~= t.State then
		t.State = state
		setAttr(t, A.MoveState, state)
		note("state", t.Player, state)
	end
end

local function unbind(player: Player)
	tracks[player] = nil
end

local function bind(player: Player, character: Model)
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not hum or not root or player.Character ~= character then
		return
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	local feetY = root.Position.Y - root.Size.Y / 2 - hum.HipHeight
	local now = os.clock()
	local t: Track = {
		Player = player,
		Character = character,
		Humanoid = hum,
		Root = root,
		Stance = "STAND",
		State = "IDLE",
		LandUntil = 0,
		Budget = S.BankStuds,
		LastPos = root.Position,
		LastValid = root.CFrame,
		LastCheck = now,
		SupportY = feetY,
		Grounded = true,
		AirSince = nil,
		HighSince = nil,
		LastWritten = hum.WalkSpeed,
		StandHip = hum.HipHeight,
		Crouched = false,
		StandRoot = hum.HipHeight + root.Size.Y / 2,
		StandTop = if head then head.Position.Y + head.Size.Y / 2 - feetY else hum.HipHeight + root.Size.Y + 1,
		StanceChangedAt = now,
		GraceUntil = now + 0.5,
		Pending = nil,
		Locked = nil,
		Mounted = false,
		Dead = false,
		Rejections = 0,
		IntentWindow = now,
		IntentCount = 0,
	}
	tracks[player] = t
	character:SetAttribute(A.Stance, "STAND")
	character:SetAttribute(A.MoveState, "IDLE")
	character:SetAttribute(A.Rejections, 0)
	apply(t)
	note("bind", player, string.format("walk %.1f, hip %.2f, top %.2f", hum.WalkSpeed, hum.HipHeight, t.StandTop))
	hum.Died:Connect(function()
		if tracks[player] ~= t then
			return
		end
		t.Dead = true
		t.State = "DEAD"
		character:SetAttribute(A.MoveState, "DEAD")
		hum.WalkSpeed = 0
		hum.JumpHeight = 0
		t.LastWritten = hum.WalkSpeed
		note("state", player, "DEAD (died)")
	end)
	wake:Fire()
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		bind(player, character)
	end)
	player.CharacterRemoving:Connect(function(character)
		local t = tracks[player]
		if t and t.Character == character then
			unbind(player)
		end
	end)
	if player.Character then
		task.spawn(bind, player, player.Character)
	end
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(unbind)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end

Intent.OnServerEvent:Connect(function(player: Player, verb: any, value: any)
	local t = tracks[player]
	if not t then
		note("intent", player, "refused: no character")
		return
	end
	local now = os.clock()
	if now - t.IntentWindow >= 1 then
		t.IntentWindow, t.IntentCount = now, 0
	end
	t.IntentCount += 1
	if t.IntentCount > S.IntentPerSecond then
		note("intent", player, "refused: rate")
		return
	end
	local ok, stance, why = Rules.intent(verb, value, {
		Alive = not t.Dead and t.Humanoid.Health > 0,
		Stance = t.Stance,
		Locked = t.Locked or (if t.Mounted then "Vehicle" else nil),
		StandBlocked = verb == "Crouch" and value == false and t.Stance == "CROUCH" and standBlocked(t),
	}, Config)
	note("intent", player, string.format("%s %s -> %s (%s)", tostring(verb), tostring(value), if ok then "ok" else "refused", why))
	if ok then
		setStance(t, stance, "intent")
	end
end)

-- Server placement: moves the character and resets the validator's baseline (vehicles, tests, spawners).
local function place(t: Track, cf: CFrame)
	t.Root.CFrame = cf
	t.Root.AssemblyLinearVelocity = Vector3.zero
	t.LastValid = cf
	t.LastPos = cf.Position
	t.Budget = S.BankStuds
	t.AirSince = nil
	t.Pending = { CFrame = cf, Until = os.clock() + 0.6 }
	local hit = ground(t, cf.Position)
	if hit then
		t.SupportY = hit.Position.Y
	end
	note("place", t.Player, tostring(cf.Position))
end

-- Mounted in a vehicle seat: no walking, jumping or stance change; dismounted: the stance's speeds come back.
local function mount(t: Track, on: boolean)
	if t.Mounted == on then
		return
	end
	t.Mounted = on
	local hum = t.Humanoid
	if on then
		hum.WalkSpeed = 0
		t.LastWritten = hum.WalkSpeed
		hum.JumpHeight = 0
	else
		t.LastWritten = hum.WalkSpeed -- this server owns the speed again
		apply(t)
		-- no grace: the vehicle's exit is a server placement (place) that sets the validated baseline itself, so
		-- validation resumes at once and nothing the client's copy carried from the seat can become a new baseline
	end
	setAttr(t, A.Locked, if on then "Vehicle" else t.Locked)
	note("mount", t.Player, tostring(on))
end

-- Production server-only control (Server.Vehicles); a BindableFunction is unreachable from clients.
local control = Instance.new("BindableFunction")
control.Name = "MovementControl"
control.OnInvoke = function(cmd: string, player: any, arg: any): any
	local t = typeof(player) == "Instance" and player:IsA("Player") and tracks[player :: Player] or nil
	if not t then
		return false
	end
	if cmd == "mount" then
		mount(t, arg == true)
		return true
	elseif cmd == "place" and typeof(arg) == "CFrame" then
		place(t, arg)
		return true
	elseif cmd == "validated" then
		return t.LastValid -- the last place this validator accepted (read-only)
	end
	return false
end
control.Parent = script

-- One timer for every character (no Heartbeat work, sleeps while nobody is alive).
task.spawn(function()
	while true do
		if next(tracks) == nil then
			wake.Event:Wait()
		end
		task.wait(S.CheckSeconds)
		local t0 = os.clock()
		for player, t in tracks do
			if t.Character.Parent and t.Root.Parent then
				local ok, err = pcall(check, t, os.clock())
				if not ok then
					note("error", player, tostring(err))
				end
			end
		end
		local spent = os.clock() - t0
		perf.Checks += 1
		perf.Seconds += spent
		perf.MaxSeconds = math.max(perf.MaxSeconds, spent)
	end
end)

-- Studio-only debug hook for the focused tests (never created in a live game; clients can't reach a BindableFunction).
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "MovementDebug"
	hook.OnInvoke = function(cmd: string, arg: any, arg2: any): any
		local player = (if typeof(arg) == "Instance" and arg:IsA("Player") then arg else Players:GetPlayers()[1]) :: Player?
		local t = player and tracks[player]
		if cmd == "status" then
			if not t then
				return nil
			end
			return {
				Stance = t.Stance,
				State = t.State,
				WalkSpeed = t.Humanoid.WalkSpeed,
				JumpHeight = t.Humanoid.JumpHeight,
				HipHeight = t.Humanoid.HipHeight,
				StandHip = t.StandHip,
				StandTop = t.StandTop,
				Budget = t.Budget,
				Locked = t.Locked,
				Rejections = t.Rejections,
				SupportY = t.SupportY,
				Grounded = t.Grounded,
				Dead = t.Dead,
				Position = t.Root.Position,
				Feet = t.Root.Position.Y - t.Root.Size.Y / 2 - t.Humanoid.HipHeight,
				StandBlocked = standBlocked(t),
			}
		elseif cmd == "events" then
			return table.clone(log)
		elseif cmd == "clearlog" then
			table.clear(log)
		elseif cmd == "teleport" then
			-- server-side placement (tests, spawners): moves the character and resets the validator's baseline
			if t and typeof(arg2) == "CFrame" then
				place(t, arg2)
				note("teleport", t.Player, tostring(arg2.Position))
			end
		elseif cmd == "allowClientTeleports" then
			allowClientTeleports = arg2 == true
			note("switch", nil, "allowClientTeleports " .. tostring(allowClientTeleports))
		elseif cmd == "perf" then
			return table.clone(perf)
		elseif cmd == "resetperf" then
			perf.Checks, perf.Seconds, perf.MaxSeconds, perf.Rays = 0, 0, 0, 0
		elseif cmd == "count" then
			local n = 0
			for _ in tracks do
				n += 1
			end
			return n
		end
		return true
	end
	hook.Parent = script
end
