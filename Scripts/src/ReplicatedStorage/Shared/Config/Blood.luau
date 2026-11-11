--!strict
-- Blood + impact presentation: data only. Everything here is driven by the server's own ballistic trace and body
-- hits (Server.Blood.Impacts); clients only render what the server sends them.
-- Basis: ReferenceAnalysis/Blood/Blood_Analysis.md (from Library/Systems/Blood_Impacts.md).
-- Tags: [confirmed] [measured] [inferred] [placeholder] UNKNOWN; nothing [placeholder] is reference data.

local Config = {
	Remote = "ImpactFx", -- Shared.Remotes.ImpactFx: server → every client; the server ignores anything a client sends

	-- Colours. Floor drops measured on screen ≈ RGB 25–46 / 0–17 / 4–22 on a floor of ≈74 / 79 / 87: about half the
	-- floor's red, almost no green or blue [measured, relative to the floor]. The values below render about that dark on
	-- this project's grey floor under its lighting [placeholder values].
	Blood = Color3.fromRGB(92, 8, 14),
	BloodDark = Color3.fromRGB(60, 4, 9),
	Spot = Color3.fromRGB(235, 28, 32), -- the bright red spot on the frame after a hit [confirmed look; value placeholder]
	Mist = Color3.fromRGB(150, 38, 44), -- soft, semi-transparent pinkish-red mist [confirmed look; value placeholder]
	Dust = Color3.fromRGB(200, 200, 196), -- grey / white impact puffs [confirmed look; value placeholder]
	Texture = "rbxasset://textures/particles/smoke_main.dds", -- Roblox's built-in soft blob (no uploads needed)
	ParticleGravity = 35, -- studs/s²: the project's gravity (the weapons' ballistics and the ragdolls use it too)

	-- Transient effects (clients). Count, Size {min, max} (studs), Speed {min, max} (studs/s), Spread (degrees around the
	-- direction), Lifetime {min, max} (s), Gravity (1 = ParticleGravity).
	Body = {
		-- a bright red spot at the hit point on the frame after the hit [confirmed: 1–2 frames]; size [placeholder]
		Spot = { Count = 1, Size = { 0.45, 0.45 }, Speed = { 0, 0 }, Spread = 0, Lifetime = { 0.06, 0.08 }, Gravity = 0 },
		-- then a soft red puff [confirmed: within 1–2 frames, gone in a few]; numbers [placeholder]
		Puff = { Count = 5, Size = { 0.35, 1.0 }, Speed = { 1, 3 }, Spread = 40, Lifetime = { 0.15, 0.3 }, Gravity = 0, Transparency = 0.35 },
		-- a little red mist, fading over ≈10+ frames [confirmed]; numbers [placeholder]
		Mist = { Count = 3, Size = { 1.2, 2.6 }, Speed = { 0.3, 0.9 }, Spread = 70, Lifetime = { 0.5, 1.0 }, Gravity = 0, Transparency = 0.35 },
		-- small droplets thrown out of the entry, away from the body (along the entry's surface normal) [inferred]
		Droplets = { Count = 8, Size = { 0.07, 0.14 }, Speed = { 5, 11 }, Spread = 28, Lifetime = { 0.35, 0.7 }, Gravity = 1 },
		-- the occasional larger drop [placeholder]
		LargeDrops = { Count = 2, Size = { 0.18, 0.26 }, Speed = { 3, 7 }, Spread = 30, Lifetime = { 0.4, 0.8 }, Gravity = 1 },
		-- through-and-through: a spray out of the exit along the bullet [inferred; exit effects UNKNOWN]
		ExitSpray = { Count = 10, Size = { 0.07, 0.16 }, Speed = { 8, 16 }, Spread = 18, Lifetime = { 0.3, 0.6 }, Gravity = 1 },
		-- mist hanging around a bleeding body for seconds (> 1.5 s seen) [confirmed]; follows the wound; not for DEAD
		-- bodies; duration and rate [placeholder]
		Bleed = { Seconds = 4, Rate = 3, Size = { 1.5, 3.0 }, Speed = { 0.4, 0.9 }, Spread = 75, Lifetime = { 1.5, 2.5 }, Gravity = 0, Transparency = 0.15 },
		MaxBleeds = 24, -- active bleed emitters per client [placeholder]
	},
	World = {
		-- grey / white puffs at surface impacts [confirmed on the floor and on bodies in a pile]. Penetrable and
		-- NonPenetrable look the same (a difference is UNKNOWN); an exit puff where a bullet leaves a penetrable surface
		-- [inferred]. No bullet holes and no ricochet (none seen: UNKNOWN).
		Puff = { Count = 5, Size = { 0.35, 0.9 }, Speed = { 2, 5 }, Spread = 35, Lifetime = { 0.25, 0.5 }, Gravity = 0, Transparency = 0.35 },
		Chips = { Count = 4, Size = { 0.05, 0.1 }, Speed = { 8, 14 }, Spread = 40, Lifetime = { 0.25, 0.45 }, Gravity = 1 },
		ExitPuff = true,
	},
	EmitterPool = 24, -- pooled world emitter sets per client, reused round-robin [implementation]

	-- Persistent blood (server-created, replicated). No fading in any clip [confirmed]; budgets keep the count bounded.
	Marks = {
		SpatterStuds = 10.7, -- splats lie 1–3 m around and behind where a bot stood [confirmed]; 3 m = 10.7 studs
		FarStuds = 3.6, -- 1 m: the near end of that range
		DropsPerHit = { 2, 4 }, -- [placeholder] (the spawn rule is UNKNOWN)
		DropSize = { 0.25, 0.6 }, -- [placeholder]
		DropNearStuds = { 0.4, 3.5 }, -- most drops land close to the body [placeholder]
		DropFarChance = 0.35, -- some land 1–3 m behind along the shot [range confirmed; share placeholder]
		TailChance = 0.6, -- many drops have one short tail [confirmed look; share placeholder]
		SplatSize = { 1.2, 2.4 }, -- blotchy splats "½–1 small tile" [confirmed relative; tile size UNKNOWN → placeholder]
		DropTransparency = 0.08,
		SplatTransparency = 0.35, -- splats are semi-transparent: the floor shows through [confirmed]
		PatchStuds = 8, -- marks share invisible 8 × 8-stud patches laid on the surface [implementation]
		PixelsPerStud = 32,
		Lift = 0.02, -- patch height above the surface (no z-fighting) [implementation]
		MaxMarks = 600, -- budget [placeholder]; beyond it the oldest mark goes first
		MaxPatches = 150,
	},
	Stains = {
		Size = { 0.35, 0.6 }, -- [placeholder]
		MaxPerBody = 16, -- [placeholder]; beyond it the oldest stain on that body goes first
		Transparency = 0.12,
		PixelsPerStud = 64,
	},
	Pool = {
		-- one pool under a body once it is down (DYING or DEAD) [confirmed: pools under bodies]; it grows, then stays
		StartRadius = 0.3, -- [placeholder]
		MaxRadius = 2.4, -- [placeholder]
		GrowSeconds = 30, -- [placeholder]
		StepSeconds = 0.25, -- growth updates (one loop for all growing pools, only while any grows) [implementation]
		MaxPools = 32, -- [placeholder]
		Transparency = 0.12,
		PixelsPerStud = 16,
		Lift = 0.012, -- just under the drop patches, so drops on a pool stay visible
	},
	-- Drag trail (body-interaction milestone; E7 and bot interaction B1–B6): a continuous, speckled band of blood laid on
	-- the floor under a wounded body while the server drags it (Server.Blood.Trails → SurfaceMarks.trail). It follows the
	-- path, starts once the body moves, stops with the drag and stays (no fading) [confirmed]. Marks share the budget.
	Trail = {
		SpacingStuds = 0.6, -- one smear per 0.6 studs moved; overlapping smears read as one band [placeholder]
		WidthStuds = 0.7, -- ≈0.7 of a leg block wide [measured relative to the leg, B3]; studs [inferred: 1-stud legs]
		Pieces = { 3, 5 }, -- overlapping specks per smear: ragged, mottled edges [confirmed look; count placeholder]
		-- Colour: on screen the trail reads ≈64–75 / 21–39 / 22–39 on a floor of ≈76–82 / 78–85 / 84–90 (bi_3 / bi_4
		-- sheets, 8 frames): red ≈0.9 × the floor's red, green / blue ≈0.35 × the floor's — a thin red smear the floor
		-- shows through, much lighter than the drops [measured, relative to the floor]. Colour and transparency below are
		-- [placeholder] values set to render at about those ratios on this project's floor, seen as in the footage (from
		-- the dragger, past the body): rendered ≈0.9 / 0.3 / 0.35 of the floor (smears overlap, so the band is less
		-- see-through than one smear).
		Color = Color3.fromRGB(110, 10, 14),
		Transparency = 0.55,
		-- laid under the pelvis; seen from the dragger it shows behind the legs [inferred from B1 / B2]
		SourceParts = { "LowerTorso", "Torso" },
		WhenDead = true, -- a dead body still leaves a trail [placeholder: the dragged bot in the footage was alive]
	},
	-- Screen blood: seen in one clip only, trigger UNKNOWN (absent in two others) → not built.
	ScreenBlood = false,
}

local function freeze(t: any): any
	for _, v in t do
		if type(v) == "table" and not table.isfrozen(v) then
			freeze(v)
		end
	end
	return table.freeze(t)
end

return freeze(Config)
