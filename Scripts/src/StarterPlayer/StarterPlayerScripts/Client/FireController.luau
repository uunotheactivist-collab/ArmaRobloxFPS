--!strict
-- Trigger, cadence and predicted ammunition for one weapon (client).
-- Shots are scheduled on a fixed interval (60 / RPM) from the moment the trigger goes down, independent of the
-- frame rate, so the measured 770 RPM holds at any FPS (a long frame can hold more than one shot; catch-up is
-- capped after a hitch). Ammunition uses the server's rules (Shared.Weapon.Ammo) and is corrected by WeaponState.
-- Fire.Mode "Semi" (optics slice, the scoped test rifle): one shot per trigger press, never faster than 60 / RPM;
-- "Auto" weapons (M4, AK) take exactly the same path as before.
-- Fire.Action "Bolt" (Sniper slice, optional): a shot leaves the case in the chamber (Ammo.fireManual) and the bolt
-- cycle chambers the next round at Fire.ChamberAt after the shot (predicted here; the server does the same and its
-- WeaponState wins). The next press is accepted at Fire.CycleTime (Interval = 60 / RPM = the cycle).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ammo = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Weapon"):WaitForChild("Ammo"))

local MAX_CATCH_UP = 3 -- intervals

local FireController = {}
FireController.__index = FireController

export type FireController = typeof(setmetatable(
	{} :: {
		Fire: any,
		Interval: number,
		Trigger: boolean,
		NextShotAt: number,
		LastShotAt: number,
		Ammo: Ammo.State,
		ShotCount: number,
		SemiReady: boolean,
		ChamberDueAt: number?,
	},
	FireController
))

function FireController.new(fire: any): FireController
	return setmetatable({
		Fire = fire,
		Interval = 60 / fire.RPM,
		Trigger = false,
		NextShotAt = -math.huge,
		LastShotAt = -math.huge,
		Ammo = Ammo.full(fire),
		ShotCount = 0,
		SemiReady = false,
	}, FireController)
end

function FireController.SetTrigger(self: FireController, down: boolean, now: number)
	if down and not self.Trigger then
		self.NextShotAt = math.max(self.NextShotAt, now) -- first shot immediately unless still cycling
		self.SemiReady = true -- a new press (semi-automatic weapons fire once per press)
	end
	self.Trigger = down
end

-- Times of the shots due up to `now` (usually none or one per frame).
function FireController.Step(self: FireController, now: number): { number }
	local shots = {}
	if self.ChamberDueAt and now >= self.ChamberDueAt then
		self.ChamberDueAt = nil
		Ammo.chamber(self.Ammo) -- the bolt closes on the next round (if any)
	end
	if not self.Trigger then
		return shots
	end
	if self.Fire.Mode == "Semi" then
		if not self.SemiReady or now < self.NextShotAt or not Ammo.canFire(self.Ammo) then
			return shots -- (a press while still cycling waits, held, for the cycle to end)
		end
		if self.Fire.Action == "Bolt" then
			Ammo.fireManual(self.Ammo)
			self.ChamberDueAt = now + self.Fire.ChamberAt
		else
			Ammo.consume(self.Ammo)
		end
		table.insert(shots, now)
		self.LastShotAt = now
		self.ShotCount += 1
		self.NextShotAt = now + self.Interval
		self.SemiReady = false
		return shots
	end
	if now - self.NextShotAt > MAX_CATCH_UP * self.Interval then
		self.NextShotAt = now - MAX_CATCH_UP * self.Interval
	end
	while now >= self.NextShotAt do
		if not Ammo.canFire(self.Ammo) then
			break -- empty: the trigger stays down and nothing happens
		end
		Ammo.consume(self.Ammo)
		table.insert(shots, self.NextShotAt)
		self.LastShotAt = self.NextShotAt
		self.ShotCount += 1
		self.NextShotAt += self.Interval
	end
	return shots
end

-- Server correction (WeaponState): the server's numbers replace the prediction.
function FireController.SetAmmo(self: FireController, mag: number, chambered: boolean, reserve: { number }?, dropped: { number }?,
	labelMarks: number?)
	self.Ammo = {
		Mag = mag,
		Chambered = chambered,
		Reserve = if reserve then table.clone(reserve) else self.Ammo.Reserve,
		Dropped = if dropped then table.clone(dropped) else self.Ammo.Dropped,
		LabelMarks = if labelMarks then labelMarks else self.Ammo.LabelMarks,
	}
end

function FireController.Refill(self: FireController)
	self.Ammo = Ammo.full(self.Fire)
	self.ChamberDueAt = nil
	if self.Fire.Action == "Bolt" then
		self.NextShotAt = -math.huge -- a fresh rifle (respawn) has no bolt cycle running
	end
end

function FireController.Total(self: FireController): number
	return Ammo.total(self.Ammo)
end

return FireController
