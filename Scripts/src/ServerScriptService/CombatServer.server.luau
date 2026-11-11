--!strict
-- Server authority for weapon fire.
--
-- The client reports only where it fired from and which way it was aiming.
-- The server checks the shot is plausible, raycasts again itself, and applies
-- damage. The client never tells the server what it hit.
--
-- Known limit: there is no lag compensation. The server ray uses current
-- positions, so a fast-moving target can be missed on a high-ping client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local CombatConfig = require(Combat:WaitForChild("CombatConfig"))
local FireWeapon = Combat:WaitForChild("FireWeapon") :: RemoteEvent
local HitConfirm = Combat:WaitForChild("HitConfirm") :: RemoteEvent

local Weapon = CombatConfig.Weapon

local function log(message: string)
	if CombatConfig.LogShots then
		print("[Combat] " .. message)
	end
end

local function reject(player: Player, reason: string)
	if CombatConfig.LogShots then
		warn(`[Combat] rejected shot from {player.Name}: {reason}`)
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

-- Fire-rate limit as a token bucket: one token per FireInterval, capped at
-- BurstAllowance. Packets that arrive bunched up from jitter still count,
-- but sustained fire faster than the weapon allows is dropped.
type FireBudget = { tokens: number, updatedAt: number }
local budgets: { [Player]: FireBudget } = {}

local function consumeShot(player: Player): boolean
	local now = os.clock()
	local budget = budgets[player]
	if not budget then
		budget = { tokens = Weapon.BurstAllowance, updatedAt = now }
		budgets[player] = budget
	end

	budget.tokens = math.min(Weapon.BurstAllowance, budget.tokens + (now - budget.updatedAt) / Weapon.FireInterval)
	budget.updatedAt = now

	if budget.tokens < 1 then
		return false
	end
	budget.tokens -= 1
	return true
end

-- Walks up through nested models so a dummy inside a folder model still counts.
local function findHumanoid(part: Instance): Humanoid?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Standard Roblox kill-credit tag, read by leaderboards and kill feeds.
local function tagCreator(humanoid: Humanoid, player: Player)
	local tag = humanoid:FindFirstChild("creator") :: ObjectValue?
	if not tag then
		local newTag = Instance.new("ObjectValue")
		newTag.Name = "creator"
		newTag.Parent = humanoid
		tag = newTag
	end
	(tag :: ObjectValue).Value = player
end

local function onFireWeapon(player: Player, origin: any, direction: any)
	-- Remote arguments are untrusted: check types before touching them.
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return reject(player, "bad argument types")
	end
	if not isFiniteVector(origin) or not isFiniteVector(direction) or direction.Magnitude < 1e-3 then
		return reject(player, "non-finite or zero vector")
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if not character or not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart") then
		return reject(player, "shooter is not alive")
	end

	local ignoreShooter = RaycastParams.new()
	ignoreShooter.FilterType = Enum.RaycastFilterType.Exclude
	ignoreShooter.FilterDescendantsInstances = { character }

	-- The origin must be near the shooter's head and not on the far side of a wall.
	local headToOrigin = origin - head.Position
	if headToOrigin.Magnitude > Weapon.MaxOriginOffset then
		return reject(player, `origin {math.floor(headToOrigin.Magnitude)} studs from head`)
	end
	if headToOrigin.Magnitude > 0.05 and workspace:Raycast(head.Position, headToOrigin, ignoreShooter) then
		return reject(player, "origin is behind geometry")
	end

	if not consumeShot(player) then
		return reject(player, "firing faster than the weapon allows")
	end

	local result = workspace:Raycast(origin, direction.Unit * Weapon.Range, ignoreShooter)
	if not result then
		return -- clean miss
	end

	local target = findHumanoid(result.Instance)
	if not target or target == humanoid or target.Health <= 0 then
		return -- hit the world, or something already dead
	end

	local isHeadshot = result.Instance.Name == "Head"
	local damage = Weapon.Damage * (if isHeadshot then Weapon.HeadshotMultiplier else 1)

	local healthBefore = target.Health
	tagCreator(target, player)
	target:TakeDamage(damage) -- respects ForceFields
	local dealt = healthBefore - target.Health
	if dealt <= 0 then
		return log(`{player.Name} hit {target.Parent and target.Parent.Name} but it was protected`)
	end

	local killed = target.Health <= 0
	log(
		`{player.Name} hit {target.Parent and target.Parent.Name}.{result.Instance.Name} for {dealt}`
			.. ` ({math.floor(healthBefore)} -> {math.floor(target.Health)}){if killed then " KILL" else ""}`
	)

	HitConfirm:FireClient(player, {
		damage = dealt,
		headshot = isHeadshot,
		killed = killed,
	})
end

FireWeapon.OnServerEvent:Connect(onFireWeapon)

Players.PlayerRemoving:Connect(function(player)
	budgets[player] = nil
end)
