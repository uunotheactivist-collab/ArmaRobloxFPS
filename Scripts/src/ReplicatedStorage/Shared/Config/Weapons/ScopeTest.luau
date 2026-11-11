--!strict
-- Scoped TEST weapon (data only): the platform that demonstrates the optics framework with the scope from scope.mp4
-- (Config.Optics.ReferenceScope; ReferenceAnalysis/Optics/Optics_Analysis.md). It is NOT a finished weapon.
--
-- The reference rifle (a semi-automatic 7.62 marksman rifle with a large scope) has no model, animations or recoil
-- measurements of its own in this project, so the test platform BORROWS the accepted M4: its viewmodel body
-- (without the holographic sight, which the scope replaces), reload clips, recoil, sway, muzzle effects and HUD
-- rules are the M4's own tables, referenced (not copied), so they cannot drift from the accepted values and no
-- second recoil tuning exists. The M4 itself is unchanged.
-- Only what the scope footage shows is the scope's / this rifle's own: semi-automatic fire, the fastest cadence,
-- the magazine count, the label text, and everything optical (Config.Optics.ReferenceScope).
-- Tags: [CONFIRMED] / [MEASURED] / [INFERRED] / [PLACEHOLDER] / [BORROWED M4] (accepted M4 value, placeholder here).

local M4 = require(script.Parent:WaitForChild("M4")) :: any

local ScopeTest = {
	Id = "ScopeTest",
	DisplayName = "Scope test rifle",
	Reference = "scope.mp4 (optic, fire mode); sniper.mp4 (same rifle INFERRED: cadence, magazine, label)",

	Optic = "ReferenceScope", -- Shared.Config.Optics.<Optic>: the optic replaces the weapon's own aim (Client.Optics)

	Viewmodel = {
		Data = M4.Viewmodel.Data, -- [BORROWED M4] AR-pattern body (the reference rifle is an AR-10 / SR-25-like DMR)
		OmitParts = { "Weapon_Optic", "Weapon_Glass", "Weapon_Reticle" }, -- the M4's holographic sight, replaced by
		-- the scope (the M4's own data and viewmodel are untouched)
		HoloReticle = false,
		HipFieldOfView = M4.Viewmodel.HipFieldOfView, -- 70 [assumed, as every weapon]; the optic never changes it
		ReloadAnimations = M4.Viewmodel.ReloadAnimations, -- [BORROWED M4]
	},

	Fire = {
		Mode = "Semi", -- [CONFIRMED] scope.mp4 W3: one shot per pull, gaps 14-55 frames, no bolt manipulation
		RPM = 600, -- [MEASURED] cadence cap: fastest gap 3 frames (100 ms) in sniper.mp4 (same rifle INFERRED); the
		-- server's rate check uses it, the trigger itself is one shot per press
		MagazineSize = 20, -- [INFERRED] sniper.mp4: 21 shots in each sequence = 20 + 1
		ChamberRound = true, -- [INFERRED] same
		SpareMagazines = 4, -- [PLACEHOLDER] as the M4
		Range = M4.Fire.Range, -- [BORROWED M4]
		Damage = M4.Fire.Damage, -- [BORROWED M4] (bodies use BodyState, not this number)
		HeadshotMultiplier = M4.Fire.HeadshotMultiplier,
		SpreadDeg = 0, -- [not measurable] no tracers or impacts through the scope (scope.mp4 B1)
		MaxOriginOffset = M4.Fire.MaxOriginOffset, -- server check, as every production weapon
		BurstAllowance = M4.Fire.BurstAllowance,
	},

	Ballistics = M4.Ballistics, -- [BORROWED M4] penetration budget and recorded muzzle velocity (no 7.62 debug text)

	-- Hip posture: the optic's aim rest pose is already upright (Config.Optics.ReferenceScope.Aim.HipUpright), so no
	-- extra de-cant while firing; the envelope timings are the M4's.
	HipFire = {
		Upright = 0,
		Pivot = M4.HipFire.Pivot,
		AttackTime = M4.HipFire.AttackTime,
		ReleaseTau = M4.HipFire.ReleaseTau,
	},

	Recoil = M4.Recoil, -- [BORROWED M4] the accepted recoil, unchanged (sniper.mp4's scoped kick 12-18 px is reported
	-- as a mismatch, not tuned)
	Sway = M4.Sway, -- [BORROWED M4] (scoped sway drift in sniper.mp4 O12 is CONFIRMED but its model is UNKNOWN)
	Muzzle = M4.Muzzle, -- [BORROWED M4]
	Reloads = M4.Reloads, -- [BORROWED M4] (the reference never shows this rifle's reload)

	Hud = {
		MagazineLabel = {
			BaseText = "[TAB] 7.62 MAG", -- [CONFIRMED text] sniper.mp4 frames 750-1252 (meaning UNKNOWN, as the M4's)
			CountSuffix = M4.Hud.MagazineLabel.CountSuffix, -- [BORROWED M4] behaviour
			MinDropped = M4.Hud.MagazineLabel.MinDropped,
			CentreX = M4.Hud.MagazineLabel.CentreX,
			CentreYFromMiddle = M4.Hud.MagazineLabel.CentreYFromMiddle,
			WidthOfScreenHeight = M4.Hud.MagazineLabel.WidthOfScreenHeight,
			InkFraction = M4.Hud.MagazineLabel.InkFraction,
			Font = M4.Hud.MagazineLabel.Font,
			Color = M4.Hud.MagazineLabel.Color,
			HideWhenNotEquipped = true,
		},
	},

	Animations = {},
}

return table.freeze(ScopeTest)
