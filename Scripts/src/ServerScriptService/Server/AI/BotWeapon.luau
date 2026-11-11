--!strict
-- A bot's weapon (server only): a thin adapter over the accepted M4 definition and rules. It owns the bot's
-- ammunition (Shared.Weapon.Ammo, the same rules as a player's), the fire rate (Config.Weapons.M4.Fire.RPM), the
-- reload (the M4's measured Reloads.<Kind>Regular timings, magazine change and chamber at the same moments as
-- WeaponServer's), and hands each shot to Server.WeaponShot, the same authoritative shot a player's validated
-- request gets: trace from the server's copy of the bot's eye, damage / BodyState, blood, record.
-- No client can reach any of this (there is no bot remote).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponRegistry = require(Shared:WaitForChild("WeaponRegistry"))
local Ammo = require(Shared:WaitForChild("Weapon"):WaitForChild("Ammo"))
local AIConfig = require(Shared:WaitForChild("Config"):WaitForChild("AI"))
local WeaponShot = require(script.Parent.Parent:WaitForChild("WeaponShot"))

local BotWeapon = {}
BotWeapon.Stats = { Shots = 0, ShotSeconds = 0, MaxShotSeconds = 0 }

export type Reload = {
	Spec: string,
	Kind: string,
	StartedAt: number,
	SwapAt: number,
	ChamberAt: number?,
	EndsAt: number,
	DropOld: string,
	Swapped: boolean,
	Chambered: boolean,
}

export type State = {
	Id: string,
	Cfg: any,
	Ammo: Ammo.State,
	NextShotAt: number,
	Reload: Reload?,
	Shots: number,
	Reloads: number,
}

function BotWeapon.new(id: string?): State
	local weaponId = id or AIConfig.Weapon
	local cfg = WeaponRegistry.get(weaponId)
	return { Id = weaponId, Cfg = cfg, Ammo = Ammo.full(cfg.Fire), NextShotAt = 0, Reload = nil, Shots = 0, Reloads = 0 }
end

function BotWeapon.refill(w: State)
	w.Ammo = Ammo.full(w.Cfg.Fire)
	w.Reload = nil
end

function BotWeapon.rounds(w: State): number
	return w.Ammo.Mag + (if w.Ammo.Chambered then 1 else 0)
end

function BotWeapon.loaded(w: State): boolean
	return Ammo.canFire(w.Ammo)
end

-- Ready for the next round now: loaded, not reloading, and the M4's cycle time since the last one has passed.
function BotWeapon.ready(w: State, now: number): boolean
	return w.Reload == nil and Ammo.canFire(w.Ammo) and now >= w.NextShotAt
end

-- One round. shooter: { Character, Humanoid, Name } of the bot; eye: the server's own head position.
function BotWeapon.fire(w: State, shooter: WeaponShot.Shooter, eye: Vector3, direction: Vector3, now: number): (any, { any })
	Ammo.consume(w.Ammo)
	w.Shots += 1
	local interval = 60 / w.Cfg.Fire.RPM
	-- keep the cadence while the trigger stays down; never two rounds closer than one cycle
	w.NextShotAt = if now - w.NextShotAt < interval then w.NextShotAt + interval else now + interval
	local t0 = os.clock()
	local trace, results = WeaponShot.resolve(shooter, w.Id, w.Cfg, eye, direction)
	local dt = os.clock() - t0
	BotWeapon.Stats.Shots += 1
	BotWeapon.Stats.ShotSeconds += dt
	BotWeapon.Stats.MaxShotSeconds = math.max(BotWeapon.Stats.MaxShotSeconds, dt)
	return trace, results
end

-- Start a reload if the rules allow one (Ammo.reloadKind). Returns the spec name, or nil and why not.
function BotWeapon.startReload(w: State, now: number): (string?, string?)
	if w.Reload then
		return nil, "busy"
	end
	local kind, why = Ammo.reloadKind(w.Ammo, w.Cfg.Fire)
	if not kind then
		return nil, why
	end
	local specName = kind .. AIConfig.Fire.ReloadSpec
	local spec = w.Cfg.Reloads[specName]
	if not spec then
		return nil, "no spec " .. specName
	end
	w.Reload = {
		Spec = specName,
		Kind = kind,
		StartedAt = now,
		SwapAt = now + spec.SwapAt,
		ChamberAt = if spec.ChamberAt then now + spec.ChamberAt else nil,
		EndsAt = now + spec.Duration,
		DropOld = spec.DropOld,
		Swapped = false,
		Chambered = false,
	}
	w.Reloads += 1
	return specName, nil
end

-- Advance a reload: magazine change at SwapAt, chamber at ChamberAt, done at Duration (the M4's measured times).
-- Returns true on the step it finishes.
function BotWeapon.step(w: State, now: number): boolean
	local r = w.Reload
	if not r then
		return false
	end
	if not r.Swapped and now >= r.SwapAt then
		r.Swapped = Ammo.swapMagazine(w.Ammo, r.DropOld)
		if not r.Swapped then
			r.Swapped = true -- nothing to swap in; the reload still runs to its end
		end
	end
	if r.ChamberAt and not r.Chambered and r.Swapped and now >= r.ChamberAt then
		r.Chambered = Ammo.chamber(w.Ammo) or true
	end
	if now >= r.EndsAt then
		w.Reload = nil
		w.NextShotAt = now
		return true
	end
	return false
end

function BotWeapon.cancel(w: State)
	w.Reload = nil
end

return BotWeapon
