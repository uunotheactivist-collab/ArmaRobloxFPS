--!strict
-- AI / bot combat vertical slice (data only). Basis: ReferenceAnalysis/AI/AI_Analysis.md.
-- No bot ever fires in the reference footage, so every combat number here is a PLACEHOLDER chosen only so one bot can
-- see, aim, shoot and hit; none of it is a fidelity claim. What the footage does fix (aim pose, hits breaking it, the
-- kill crumple, the gun let go, persistent bodies) is done by the accepted body systems, not here.
-- Used by ServerScriptService.Server.AI (all authority) and the client muzzle effect (presentation only).

local AI = {
	BotAttribute = "AIBot", -- model attribute (server-set) that makes a model a bot
	TeamAttribute = "AITeam", -- model / player attribute (server-set): the team. Different team = enemy
	PlayerTeam = "Blue", -- [placeholder] team of a player character without its own AITeam attribute
	FacingAttribute = "BodyFacingYaw", -- read by Server.HitReaction (world yaw, radians); written only by Server.AI
	RifleTag = "AIRifle", -- CollectionService tag on a bot's rifle (client muzzle effect)
	ShotsAttribute = "AIShots", -- rifle attribute: server shot counter (the client flashes when it rises)
	Weapon = "M4", -- [placeholder] the bot carries the accepted M4: Config.Weapons.M4 (rate, magazine, reload times)

	Perception = {
		RangeStuds = 120, -- [placeholder] detection range (eye to target point)
		FovDeg = 120, -- [placeholder] full horizontal field of view for acquiring a target, about the body's facing
		ScanSeconds = 0.2, -- [placeholder] how often a bot looks for targets (staggered across bots)
		LosSeconds = 0.1, -- [placeholder] how often a bot re-checks its current target's line of sight
		LostAfterSeconds = 0.4, -- [placeholder] the target is lost after this long unseen (blocked / out of range)
		ForgetSeconds = 3.0, -- [placeholder] a lost target is forgotten after this long (back to SEARCH)
		-- target points tried in order (first visible one is aimed at); R15 then R6 names
		AimParts = { "UpperTorso", "Torso", "Head" },
	},

	Reaction = {
		FirstShotSeconds = 0.6, -- [placeholder] from acquiring a new target to the first allowed shot
		ReacquireSeconds = 0.5, -- [placeholder] from seeing a lost target again to the next allowed shot
	},

	Aim = {
		TurnDegPerSecond = 360, -- [placeholder] body (root) turn rate; one footage turn took ~0.1 s (angle unknown)
		AimDegPerSecond = 240, -- [placeholder] aim direction convergence rate (separate from the body)
		SettleSeconds = 0.1, -- [placeholder] aim delay: on target this long before the first round of a burst
		FireToleranceDeg = 3, -- [placeholder] aim must be this close to the target direction to fire
		BodyToleranceDeg = 10, -- [placeholder] body facing must be this close to the aim's yaw to fire
		ReaimDeg = 8, -- [placeholder] while firing, an aim error above this goes back to AIM
		FacingEpsilonRad = 0.002, -- the facing attribute is written only when the yaw changes more than this
	},

	Accuracy = {
		ErrorDeg = 1.5, -- [placeholder] each shot leaves the aim direction within this cone (seeded, per bot)
		WeakErrorScale = 1.0, -- [placeholder] cone x (1 + scale x strength lost / 100) while weakened
	},

	Fire = {
		BurstMin = 3, -- [placeholder] rounds per burst (at the M4's measured 770 RPM)
		BurstMax = 5,
		PauseMinSeconds = 0.35, -- [placeholder] pause between bursts
		PauseMaxSeconds = 0.7,
		HoldWhileReacting = true, -- [inferred] no shot while BodyState's flinch window is open (hits break the aim pose)
		HoldWhileUnstable = true, -- [inferred] no shot while the body is unstable (stumbling)
		ReloadSpec = "Regular", -- [placeholder] M4 Reloads.<Kind>Regular timings (bots have no stress state)
	},

	Rifle = {
		DropAfterSeconds = 0.3, -- [measured range 0.2-0.5 s] "the gun: still in the hand -> let go" after RAGDOLL (R8)
		Color = { 20, 20, 22 }, -- [confirmed] black rifle (bot interaction AI1)
		BodySize = { 0.28, 0.4, 2.3 }, -- studs [placeholder] receiver + barrel, sized to read next to the blocky arms
		MagazineSize = { 0.2, 0.55, 0.3 },
		MagazineOffset = { 0, -0.42, -0.2 }, -- rifle-local, tilted 12 deg forward
		StockSize = { 0.22, 0.4, 0.7 },
		Grip = { 0, -0.3, 0.45 }, -- rifle-local point held by the right hand (rifle forward = -Z)
		MuzzleZ = -1.2, -- rifle-local muzzle (attachment "Muzzle")
		Gravity = 35, -- studs/s^2 once dropped (the project's 9.8 m/s^2)
	},

	Muzzle = { -- [placeholder] presentation only: no bot is ever seen firing (A2)
		FlashSeconds = 0.05,
		FlashSizeStuds = 0.45,
		LightColor = { 255, 190, 120 },
		LightBrightness = 4,
		LightRange = 10,
	},
}

return table.freeze(AI)
