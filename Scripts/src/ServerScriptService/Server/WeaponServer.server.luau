--!strict
-- Production weapon server: equip state, ammunition, fire validation and hit detection (M4 and AK; every number
-- comes from Config.Weapons.<Id>).
--
-- Same trust model as the foundation's CombatServer: a client reports only which weapon fired, from where and
-- in which direction (never a hit position). The server checks the shot is plausible (alive, weapon equipped, fire
-- rate, ammunition, reported origin near the head and not through a wall, direction not behind the shooter), then
-- traces the bullet itself with the shared Server.Ballistics from ITS OWN copy of the shooter's eye (the head),
-- along the client's aim direction: surface hits, penetration, exits, continued path and target hits are all
-- server-side, and it applies the damage. Clients predict ammunition and all presentation locally (no round trip
-- before recoil/flash); the server corrects them via WeaponState.
--
-- Reloads (M4 reload milestone): the server picks the reload from its own state (tactical / empty, Regular /
-- Stressed), times it with the durations measured from the footage (Config.Weapons.<Id>.Reloads), commits the
-- magazine change at the measured moment and blocks firing until the reload is over. A weapon switch or death
-- cancels it (the footage shows no interruption, so nothing else does); before the commit point nothing changes.
--
-- Bodies (model attribute BodyModel) take the trace's hit through Server.BodyState: location, wound and body state
-- (body hit + body state foundation). Every other humanoid keeps the placeholder damage below.
-- Blood / impact presentation (blood milestone): after the damage, this shot's own trace and results go to
-- Server.Blood.Impacts (presentation and persistent blood only; it can't change the shot, and a failure there is caught).
-- Not yet (later milestones): spread, deflection / ricochet / drop, damage model, lag compensation, showing other
-- players' shots.
-- AI combat slice: the steps after validation (trace, damage / body state, blood, record) moved unchanged into
-- Server.WeaponShot, which bots use too, so a bot's bullet is the same shot.
-- DevRefill / DevSetStressed are Studio-only test commands.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponRegistry = require(Shared:WaitForChild("WeaponRegistry"))
local Ammo = require(Shared:WaitForChild("Weapon"):WaitForChild("Ammo"))
local WeaponShot = require(script.Parent:WaitForChild("WeaponShot"))
local Remotes = Shared:WaitForChild("Remotes")
local WeaponFire = Remotes:WaitForChild("WeaponFire") :: RemoteEvent
local WeaponCommand = Remotes:WaitForChild("WeaponCommand") :: RemoteEvent
local WeaponState = Remotes:WaitForChild("WeaponState") :: RemoteEvent

local LOG = true
local PRODUCTION_WEAPONS = { M4 = true, AK = true, ScopeTest = true, MP7 = true, Glock = true, Sniper = true } -- each has
-- Shared/Config/Weapons/<Id> (values from its own footage; ScopeTest = the optics slice's scoped test rifle, validated and
-- traced exactly like the others: the optic is client presentation and sends nothing of its own; MP7 = the MP7 slice,
-- 950 RPM / 40 + 1; Glock = the Glock slice, semi-automatic, 15 + 1 - same validation and the same Server.WeaponShot
-- path. The Glock's slide state is derived from this server's ammunition (Chambered); no client message sets it)
-- Sniper slice: Fire.Action = "Bolt" (the Sniper). This server owns the bolt: an accepted shot leaves the chamber empty
-- (Ammo.fireManual) and starts a cycle; the next round is chambered at Fire.ChamberAt and the next shot is refused until
-- Fire.CycleTime (- ACTION_GRACE for network timing) - that gate replaces the token bucket for bolt weapons. No client
-- message can end a cycle or chamber a round; a reload is refused while the bolt is cycling; a weapon switch does not
-- end or skip the cycle; a respawn resets it.
local OTHER_WEAPONS = { TestBlaster = true }

type PlayerState = {
	Equipped: string?,
	Ammo: { [string]: Ammo.State },
	Tokens: number,
	TokensAt: number,
	Accepted: number,
	Rejected: number,
	Reload: ReloadState?,
	Action: { [string]: ActionState }, -- bolt weapons: the running / last cycle per weapon (Sniper slice)
}
type ActionState = { StartedAt: number, ReadyAt: number, Chambered: boolean }
type ReloadState = {
	Spec: string,
	Kind: string,
	StartedAt: number,
	Swapped: boolean,
	Chambered: boolean,
	DiedConn: RBXScriptConnection?,
}
local states: { [Player]: PlayerState } = {}
local RELOAD_GRACE = 0.1 -- s: the server finishes this much early so a client's first shot after its clip isn't rejected
local ACTION_GRACE = 0.1 -- s: the same allowance for a bolt cycle (client and server clocks / network timing)

local function log(message: string)
	if LOG then
		print("[Weapon] " .. message)
	end
end

local function stateFor(player: Player): PlayerState
	local s = states[player]
	if not s then
		s = { Equipped = nil, Ammo = {}, Tokens = 0, TokensAt = os.clock(), Accepted = 0, Rejected = 0, Reload = nil, Action = {} }
		states[player] = s
	end
	return s
end

local function ammoFor(s: PlayerState, id: string): Ammo.State
	local a = s.Ammo[id]
	if not a then
		a = Ammo.full(WeaponRegistry.get(id).Fire)
		s.Ammo[id] = a
	end
	return a
end

local function sendState(player: Player, id: string, reason: string)
	local s = stateFor(player)
	local a = ammoFor(s, id)
	local act = s.Action[id]
	WeaponState:FireClient(player, {
		BoltReadyIn = if act then math.max(0, act.ReadyAt - os.clock()) else nil, -- bolt weapons only (Sniper slice)
		Weapon = id,
		Mag = a.Mag,
		Chambered = a.Chambered,
		Reserve = table.clone(a.Reserve),
		Dropped = table.clone(a.Dropped),
		LabelMarks = a.LabelMarks or 0,
		Reloading = if s.Reload then s.Reload.Spec else nil,
		Reason = reason,
		Accepted = s.Accepted,
		Rejected = s.Rejected,
	})
end

local function reject(player: Player, reason: string)
	stateFor(player).Rejected += 1
	if LOG then
		warn(`[Weapon] rejected shot from {player.Name}: {reason}`)
	end
end

local function isFiniteVector(v: Vector3): boolean
	for _, n in { v.X, v.Y, v.Z } do
		if n ~= n or n == math.huge or n == -math.huge then
			return false
		end
	end
	return true
end

-- Fire-rate limit as a token bucket (one token per 60 / RPM seconds, capped at BurstAllowance), as the foundation.
local function consumeToken(s: PlayerState, fire: any): boolean
	local now = os.clock()
	local interval = 60 / fire.RPM
	s.Tokens = math.min(fire.BurstAllowance, s.Tokens + (now - s.TokensAt) / interval)
	s.TokensAt = now
	if s.Tokens < 1 then
		return false
	end
	s.Tokens -= 1
	return true
end

local function onFire(player: Player, weaponId: any, origin: any, direction: any)
	if typeof(weaponId) ~= "string" or not PRODUCTION_WEAPONS[weaponId] then
		return reject(player, "unknown weapon")
	end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return reject(player, "bad argument types")
	end
	if not isFiniteVector(origin) or not isFiniteVector(direction) or direction.Magnitude < 1e-3 then
		return reject(player, "non-finite or zero vector")
	end
	local s = stateFor(player)
	if s.Equipped ~= weaponId then
		return reject(player, `{weaponId} is not equipped`)
	end
	if s.Reload then
		return reject(player, "reloading")
	end
	local cfg = WeaponRegistry.get(weaponId)
	local fire = cfg.Fire

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if not character or not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart") then
		return reject(player, "shooter is not alive")
	end
	if character:GetAttribute("VehicleSeatKind") == "Driver" then
		-- truck slice: the driver's hands are on the wheel; no rifle, no fire line in its CONTROLS [CONFIRMED W4]
		return reject(player, "in the driver seat")
	end

	local ignoreShooter = RaycastParams.new()
	ignoreShooter.FilterType = Enum.RaycastFilterType.Exclude
	ignoreShooter.FilterDescendantsInstances = { character }

	local headToOrigin = origin - head.Position
	if headToOrigin.Magnitude > fire.MaxOriginOffset then
		return reject(player, `origin {math.floor(headToOrigin.Magnitude)} studs from head`)
	end
	if headToOrigin.Magnitude > 0.05 and workspace:Raycast(head.Position, headToOrigin, ignoreShooter) then
		return reject(player, "origin is behind geometry")
	end

	-- The aim direction is the client's input (the server can't see the camera), but it must not point behind the
	-- shooter: the character faces the camera's yaw in first person.
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		local aim = Vector3.new(direction.X, 0, direction.Z)
		if facing.Magnitude > 1e-3 and aim.Magnitude > 1e-3 and facing.Unit:Dot(aim.Unit) < -0.5 then
			return reject(player, "direction behind the shooter")
		end
	end

	local ammo = ammoFor(s, weaponId)
	local bolt = fire.Action == "Bolt"
	if bolt then
		local act = s.Action[weaponId]
		if act and os.clock() < act.ReadyAt - ACTION_GRACE then
			return reject(player, "bolt cycling")
		end
	end
	if not Ammo.canFire(ammo) then
		reject(player, "empty")
		return sendState(player, weaponId, "Empty")
	end
	if bolt then
		-- the cycle replaces the token bucket: exactly one shot per cycle
		Ammo.fireManual(ammo)
		local act: ActionState = { StartedAt = os.clock(), ReadyAt = os.clock() + fire.CycleTime, Chambered = false }
		s.Action[weaponId] = act
		task.delay(fire.ChamberAt, function()
			if states[player] == s and s.Action[weaponId] == act then
				act.Chambered = Ammo.chamber(ammoFor(s, weaponId))
				sendState(player, weaponId, "BoltChambered")
			end
		end)
	else
		if not consumeToken(s, fire) then
			return reject(player, "firing faster than the weapon allows")
		end
		Ammo.consume(ammo)
	end
	s.Accepted += 1

	-- Authoritative bullet path from the server's own head position (the eye), never the client's origin or any
	-- client hit position: trace, damage / body state, blood, record (Server.WeaponShot, shared with bots).
	WeaponShot.resolve(
		{ Player = player, Character = character, Humanoid = humanoid, Name = player.Name },
		weaponId,
		cfg,
		head.Position,
		direction
	)
end

local function cancelReload(player: Player, s: PlayerState, reason: string)
	local r = s.Reload
	if r then
		s.Reload = nil
		if r.DiedConn then
			r.DiedConn:Disconnect()
		end
		log(`{player.Name} reload {r.Spec} cancelled ({reason}){if r.Swapped then " after the magazine change" else ""}`)
		if s.Equipped and PRODUCTION_WEAPONS[s.Equipped] then
			sendState(player, s.Equipped, "ReloadCancelled")
		end
	end
end

local function startReload(player: Player, s: PlayerState)
	local id = s.Equipped
	if not id or not PRODUCTION_WEAPONS[id] then
		return
	end
	if s.Reload then
		return sendState(player, id, "ReloadBusy")
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if character and character:GetAttribute("VehicleSeatKind") == "Driver" then
		return sendState(player, id, "ReloadRefused:Driver") -- truck slice: no weapon in the driver seat
	end
	local cfg = WeaponRegistry.get(id)
	local act = s.Action[id]
	if cfg.Fire.Action == "Bolt" and act and os.clock() < act.ReadyAt - ACTION_GRACE then
		return sendState(player, id, "ReloadRefused:Cycling") -- the bolt is still being worked
	end
	local ammo = ammoFor(s, id)
	local kind, why = Ammo.reloadKind(ammo, cfg.Fire)
	if not kind then
		return sendState(player, id, "ReloadRefused:" .. tostring(why))
	end
	local specName = kind .. (if player:GetAttribute("Stressed") == true then "Stressed" else "Regular")
	local spec = cfg.Reloads[specName]
	local r: ReloadState = { Spec = specName, Kind = kind, StartedAt = os.clock(), Swapped = false, Chambered = false }
	s.Reload = r
	-- Death cancels the reload at once (no magazine change while dead); respawn resets the ammunition anyway.
	r.DiedConn = humanoid.Died:Connect(function()
		if s.Reload == r then
			cancelReload(player, s, "died")
		end
	end)
	log(`{player.Name} reload {specName} ({spec.Duration} s, magazine change at {spec.SwapAt} s, old magazine: {spec.DropOld}{if spec.ChamberAt then `, chambered at {spec.ChamberAt} s` else ""})`)
	sendState(player, id, "ReloadStarted")
	-- Swap and chamber happen at the clip times exactly (the HUD label changes at the swap, timed from the footage);
	-- only the end of the reload is brought forward by RELOAD_GRACE.
	task.delay(spec.SwapAt, function()
		if s.Reload == r then
			r.Swapped = Ammo.swapMagazine(ammo, spec.DropOld)
			sendState(player, id, "ReloadSwapped")
		end
	end)
	if spec.ChamberAt then
		task.delay(spec.ChamberAt, function()
			if s.Reload == r and r.Swapped then
				r.Chambered = Ammo.chamber(ammo)
				sendState(player, id, "ReloadChambered")
			end
		end)
	end
	if spec.HudMarkAt then -- HUD label moment measured in the weapon's footage (no ammunition change)
		task.delay(spec.HudMarkAt, function()
			if s.Reload == r then
				Ammo.mark(ammo)
				sendState(player, id, "ReloadMarked")
			end
		end)
	end
	task.delay(math.max(0, spec.Duration - RELOAD_GRACE), function()
		if s.Reload == r then
			s.Reload = nil
			if r.DiedConn then
				r.DiedConn:Disconnect()
			end
			sendState(player, id, "ReloadDone")
		end
	end)
end

local function onCommand(player: Player, command: any, arg: any)
	local s = stateFor(player)
	if command == "Equip" and arg ~= s.Equipped then
		cancelReload(player, s, "weapon switched")
	end
	if command == "Equip" then
		if arg == nil or OTHER_WEAPONS[arg] then
			s.Equipped = arg
		elseif typeof(arg) == "string" and PRODUCTION_WEAPONS[arg] then
			s.Equipped = arg
			sendState(player, arg, "Equip")
		end
	elseif command == "Sync" then
		if typeof(arg) == "string" and PRODUCTION_WEAPONS[arg] then
			sendState(player, arg, "Sync")
		end
	elseif command == "Reload" then
		startReload(player, s)
	elseif command == "DevSetStressed" then
		-- Studio-only until a stress system exists: the server owns the state so it can pick the right reload.
		if RunService:IsStudio() then
			player:SetAttribute("Stressed", arg == true)
		end
	elseif command == "DevSetAmmo" then
		-- Studio-only test helper: set magazine / chamber / reserve exactly (e.g. empty reserve, partial magazine).
		local id = s.Equipped
		if RunService:IsStudio() and id and PRODUCTION_WEAPONS[id] and typeof(arg) == "table"
			and typeof(arg.Mag) == "number" and typeof(arg.Chambered) == "boolean" and typeof(arg.Reserve) == "table" then
			local reserve = {}
			for _, r in arg.Reserve do
				if typeof(r) == "number" then
					table.insert(reserve, math.clamp(math.floor(r), 0, WeaponRegistry.get(id).Fire.MagazineSize))
				end
			end
			local dropped = {}
			if typeof(arg.Dropped) == "table" then
				for _, r in arg.Dropped do
					if typeof(r) == "number" then
						table.insert(dropped, math.clamp(math.floor(r), 0, WeaponRegistry.get(id).Fire.MagazineSize))
					end
				end
			end
			s.Reload = nil
			s.Action[id] = nil
			s.Ammo[id] = {
				Mag = math.clamp(math.floor(arg.Mag), 0, WeaponRegistry.get(id).Fire.MagazineSize),
				Chambered = arg.Chambered,
				Reserve = reserve,
				Dropped = dropped,
				LabelMarks = if typeof(arg.LabelMarks) == "number" then math.clamp(math.floor(arg.LabelMarks), 0, 1) else 0,
			}
			sendState(player, id, "DevSetAmmo")
		end
	elseif command == "DevRefill" then
		-- Studio-only test helper: full magazine, chamber and reserve at once (the M4 key R now reloads).
		if RunService:IsStudio() and s.Equipped and PRODUCTION_WEAPONS[s.Equipped] then
			s.Reload = nil
			s.Action[s.Equipped] = nil
			s.Ammo[s.Equipped] = Ammo.full(WeaponRegistry.get(s.Equipped).Fire)
			log(`{player.Name} dev refill {s.Equipped}`)
			sendState(player, s.Equipped, "DevRefill")
		end
	end
end

WeaponFire.OnServerEvent:Connect(onFire)
WeaponCommand.OnServerEvent:Connect(onCommand)

-- Player reset: every respawn starts with full production weapons.
local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		local s = stateFor(player)
		s.Reload = nil
		s.Ammo = {}
		s.Action = {}
		for id in PRODUCTION_WEAPONS do
			sendState(player, id, "Respawn")
		end
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)
