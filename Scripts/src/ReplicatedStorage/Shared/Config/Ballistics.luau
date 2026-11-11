--!strict
-- Shared ballistic data for the minimum ballistic slice (ReferenceAnalysis/Ballistics/Ballistics_Analysis.md).
-- Used by Server.Ballistics for every production weapon. Weapon-specific values live in
-- Config.Weapons.<Id>.Ballistics (penetration budget) and Config.Weapons.<Id>.Fire (range, damage).
--
-- Surfaces: a part's class comes from its attribute BallisticSurface (or its model's). Characters with a Humanoid
-- count as Target without an attribute; anything else unmarked counts as NonPenetrable.
-- Penetration budget unit: studs of "Penetrable" reference material (CostPerStud 1). Crossing a part costs
-- thickness (studs, along the shot) x CostPerStud.

return table.freeze({
	Attribute = "BallisticSurface",
	Surfaces = table.freeze({
		-- [placeholder] The footage has no penetrable walls (analysis B13). This is the reference material, so a thin
		-- wall is crossed and a target behind it can still be passed through.
		Penetrable = table.freeze({ Stops = false, CostPerStud = 1.0, Hit = false }),
		-- [inferred] The footage's bullet path ends at the solid structure (B5): the bullet stops at the entry point.
		NonPenetrable = table.freeze({ Stops = true, CostPerStud = 0, Hit = false }),
		-- [confirmed] Bodies are hit and passed through, several in a row on one path (B1, B2). [placeholder] The cost
		-- is low enough for that; the footage gives no number.
		Target = table.freeze({ Stops = false, CostPerStud = 0.25, Hit = true }),
	}),
	Default = "NonPenetrable", -- unmarked world geometry stops the bullet
	HumanoidDefault = "Target", -- character parts (a Humanoid in an ancestor model)
	MaxSurfaces = 16, -- safety cap on surfaces entered by one shot
	MaxThicknessProbe = 12, -- studs: a part thicker than this along the shot can't be exited (the bullet stops inside)
	ExitOffset = 0.01, -- studs past the exit point before the trace continues
	RecentResults = 64, -- Studio only: results kept for tests (Server.Ballistics.Recent)
})
