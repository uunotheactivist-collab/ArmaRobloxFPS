--!strict
-- Shared tuning for the core combat loop. Read by both server and client,
-- but only the server's copy is trusted for damage and validation.

local CombatConfig = {
	PlayerRespawnDelay = 3, -- seconds from death to new character
	DummyRespawnDelay = 3, -- seconds from a target dummy dying to its replacement appearing

	-- Prints accepted hits and rejected shots to the server output.
	LogShots = true,

	Weapon = table.freeze({
		Name = "TestBlaster",
		Damage = 25,
		HeadshotMultiplier = 2,
		FireInterval = 0.12, -- seconds between shots (500 RPM)
		Automatic = true, -- hold to keep firing
		Range = 500, -- studs

		-- Server-side plausibility checks.
		MaxOriginOffset = 8, -- max studs between the reported shot origin and the shooter's head
		BurstAllowance = 3, -- shots allowed to arrive bunched together from network jitter
	}),
}

return table.freeze(CombatConfig)
