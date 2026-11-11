--!strict
-- One authoritative shot, shared by every shooter (AI combat slice): Server.WeaponServer calls it for a player's
-- validated shot, Server.AI.BotWeapon for a bot's. This code was moved here unchanged from WeaponServer.onFire, so a
-- player's shot does exactly what it did before, with the same log lines:
--   1. trace from the shooter's own eye (the server's copy of its Head) along the direction, using the weapon's
--      values (Server.Ballistics);
--   2. each character the bullet reached: BodyState.applyHit for bodies (BodyModel), otherwise the placeholder damage
--      on the Humanoid (x the headshot multiplier);
--   3. blood / impact presentation (Server.Blood.Impacts; it can't change the shot);
--   4. the record (Ballistics.record).
-- Only two steps need a Player, and are skipped for a bot: the creator tag and the hit marker (HitConfirm). There is
-- no bot-only damage, hit test, death, ragdoll or blood.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ballistics = require(script.Parent:WaitForChild("Ballistics"))
local BodyState = require(script.Parent:WaitForChild("BodyState"))
local Impacts = require(script.Parent:WaitForChild("Blood"):WaitForChild("Impacts"))
-- Hit feedback goes to the foundation's test HUD (hitmarker) until the production HUD exists.
local HitConfirm = ReplicatedStorage:WaitForChild("Combat"):WaitForChild("HitConfirm") :: RemoteEvent

local LOG = true

export type Shooter = {
	Player: Player?, -- nil for a bot
	Character: Model,
	Humanoid: Humanoid,
	Name: string, -- the player's name, or the bot model's name
}

local WeaponShot = {}

local function log(message: string)
	if LOG then
		print("[Weapon] " .. message)
	end
end

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

-- cfg: Config.Weapons.<weaponId> (Fire.Range / Damage / HeadshotMultiplier, Ballistics.PenetrationStuds).
-- eye: the server's own shooter head position (never a client position). direction: the aim direction.
-- Returns the trace and the per-target results.
function WeaponShot.resolve(shooter: Shooter, weaponId: string, cfg: any, eye: Vector3, direction: Vector3): (any, { any })
	local fire = cfg.Fire
	local player = shooter.Player
	local character = shooter.Character
	local humanoid = shooter.Humanoid

	-- Authoritative bullet path: from the server's own head position (the eye), never the client's origin or any
	-- client hit position. Shared by every production weapon; only the config values differ.
	local trace = Ballistics.trace(eye, direction, {
		Range = fire.Range,
		PenetrationStuds = cfg.Ballistics.PenetrationStuds,
	}, { character })

	-- Basic damage result: each character the bullet reached takes the weapon's damage once (x the headshot
	-- multiplier when its first part hit is the head). No falloff: the reference establishes none.
	local damageResults = {}
	for _, t in trace.Targets do
		local target = t.Humanoid
		if target == humanoid or target.Health <= 0 then
			continue
		end
		-- Body-state bodies (model attribute BodyModel): the server resolves hit location, wound and body state from
		-- this trace's part and point (Server.BodyState). No direct health damage and no hit marker here.
		if BodyState.isBody(target) then
			local r = BodyState.applyHit(target, t.Part, t.Position, weaponId)
			table.insert(damageResults, { Humanoid = target, Part = t.Part.Name, Dealt = 0, Health = target.Health, Body = r })
			if r then
				log(
					`{shooter.Name} {weaponId} hit body {r.Body}.{r.Location or r.Part}{if r.Zone then "/" .. r.Zone else ""}`
						.. ` → {r.Wound or "-"} wound, {r.PhaseBefore} → {r.PhaseAfter}{if r.Ignored then " (" .. r.Ignored .. ")" else ""}`
				)
			end
			continue
		end
		local isHeadshot = t.Part.Name == "Head"
		local damage = fire.Damage * (if isHeadshot then fire.HeadshotMultiplier else 1)
		local healthBefore = target.Health
		if player then
			tagCreator(target, player)
		end
		target:TakeDamage(damage)
		local dealt = healthBefore - target.Health
		table.insert(damageResults, { Humanoid = target, Part = t.Part.Name, Dealt = dealt, Health = target.Health })
		if dealt <= 0 then
			continue
		end
		local killed = target.Health <= 0
		local crossed = 0 -- surfaces the bullet exited before reaching this target
		for _, e in trace.Events do
			if e.Kind == "Enter" and e.Part == t.Part then
				break
			elseif e.Kind == "Exit" then
				crossed += 1
			end
		end
		log(
			`{shooter.Name} {weaponId} hit {target.Parent and target.Parent.Name}.{t.Part.Name} for {dealt}`
				.. ` ({math.floor(healthBefore)} -> {math.floor(target.Health)}){if killed then " KILL" else ""}`
				.. (if crossed > 0 then ` after penetrating {crossed} surface(s)` else "")
		)
		if player then
			HitConfirm:FireClient(player, { damage = dealt, headshot = isHeadshot, killed = killed })
		end
	end
	-- blood / impact presentation from this authoritative trace (never affects the shot)
	local fxOk, fxErr = pcall(Impacts.onShot, player, weaponId, trace, damageResults)
	if not fxOk then
		warn(`[Weapon] impact presentation failed: {fxErr}`)
	end
	Ballistics.record({
		Player = shooter.Name,
		Bot = if player then nil else shooter.Name,
		Weapon = weaponId,
		At = os.clock(),
		Trace = trace,
		Damage = damageResults,
	})
	return trace, damageResults
end

return WeaponShot
