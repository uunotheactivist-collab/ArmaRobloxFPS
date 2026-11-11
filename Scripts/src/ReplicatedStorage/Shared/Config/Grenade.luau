--!strict
-- Fragmentation grenade: data only. Basis: ReferenceAnalysis/Grenade/Grenade_Analysis.md (grenade.mp4 debug clip,
-- grenades.mp4 normal clip). Tags: [confirmed] [measured] [inferred] [placeholder] UNKNOWN; nothing [placeholder] is
-- reference data. Every decision is the server's (Server.Grenade.GrenadeServer); a client only asks to throw.

local Config = {
	Remotes = {
		Command = "GrenadeCommand", -- client → server: ("Throw", aimDirection) / ("Sync"); Studio: ("DevRefill")
		State = "GrenadeState", -- server → a player: Released (count left) / Refused / Sync / FragmentsHit (fragments
		-- reached that player's character: the red edge pulse, presentation only)
		Fx = "GrenadeFx", -- server → every client: one message per detonation (position); presentation only
	},

	Key = Enum.KeyCode.G, -- [placeholder] the throw input is never visible in the footage
	Count = 5, -- grenades per life (reset on respawn, like the weapons' ammunition) [inferred ≥ 5: x4 … x0; value placeholder]

	Throw = {
		-- No hold: a press throws at once (the normal clip's four throws show no hold) [confirmed]. Holding / cooking is
		-- not built: its input is UNKNOWN and cooking is only [inferred] (grenade clip: 3.27 s after a visible hold).
		ReleaseSeconds = 4 / 30, -- wind-up 24 → release 28 [measured, 4 frames]
		Seconds = 12 / 30, -- wind-up → rifle back 24 → 36 [measured, 12 frames; 0.40–0.57 s in the normal clip]
		Speed = 55, -- studs/s (≈15 m/s) [placeholder: speed in studs UNKNOWN; the footage's speed / size ratio ≈ 250 /s
		-- (ReferenceAnalysis/GrenadeFidelity M11) vs 55 / 0.25 = 220 /s here]
		-- Grenade fidelity slice: the launch leaves ABOVE and LEFT of the aim, in camera axes: the normal clip's three lobs
		-- recede along a line of sight 19.6–21.7° above and 10.1–11.8° left of the screen centre (M8) [measured; the
		-- older debug clip's single low throw differs (≈ 2° / 6°): the rule across builds / throw types is UNKNOWN]
		LiftDeg = 21,
		YawLeftDeg = 11,
		-- release point, in the aim frame from the SERVER head (right, up, back): the grenade in hand at release sits at
		-- ≈ (490–507, 120–130) on the 1280 × 720 screen (M9) [direction measured; depth 1.4 studs from the camera
		-- inferred; the first-person camera sits ≈ 0.5 studs behind the server head (measured in Studio), hence -0.9]
		HandOffset = Vector3.new(-0.445, 0.66, -0.9), -- seen at (500, 125) at 1.4 studs in Studio
		MaxBehindDot = -0.5, -- the aim may not point behind the character (same rule as WeaponServer) [implementation]
		DirectionTolerance = 0.5, -- |aim| must be 1 ± this: a client sends a direction, never a velocity [implementation]
		-- First-person fidelity pass: the held weapon leaves the view for the throw (Client.FirstPerson.WeaponLowering,
		-- seconds from the press). Normal clip, rifle pixels at the bottom centre around the four throws (L = the label's
		-- first frame; the press is L-3 by the accepted timing): going down from ≈ L-5, ≤ 7 % at L-1, none L … L+8 (the
		-- throwing arm fills L+2 … L+5), first pixels again L+8 … L+11 (median ≈ L+9.5), above the pre-throw level by
		-- L+10 … L+12 [measured, ReferenceAnalysis/FirstPerson §2]. How it leaves (down / tilted) and the pose after the
		-- throw are not established: the offset is [placeholder], chosen to clear the view. The older debug clip keeps its
		-- AK visible, lowered and canted [measured; that build differs → not followed].
		LowerWeapon = {
			DownSeconds = 3 / 30, -- press → out of view by L-1 [measured end; the reference starts ≈ 2 frames earlier]
			-- the way back starts at L+8 and eases out: first pixels at L+10 (M4 / AK / Sniper) or L+11 (MP7 / Glock),
			-- half the weapon by L+11 / L+12, all of it by L+12 … L+15 [fitted in Studio to the measured frames, all five
			-- weapons; FirstPersonTest.timing]
			HiddenUntil = 11 / 30,
			BackBy = 18 / 30, -- back in place by L+15 [fitted]
			ReturnPower = 3, -- [fitted]
			DropStuds = 1.2, -- [placeholder: just enough to clear the view for every weapon]
			PitchDeg = 40, -- muzzle down [placeholder]
			BackStuds = 0.3, -- [placeholder]
		},
	},

	-- First-person fidelity pass: the thrower's view of its own grenade (Client.Grenade.GrenadePrediction). Presentation
	-- only: the server's body is the grenade. All [implementation].
	Prediction = {
		ShowAfter = 0, -- the proxy appears when ThrowPresentation's in-hand grenade goes (the release, L+1)
		Step = 1 / 60, -- contact sweep step (s of flight)
		HorizonSeconds = 3, -- contact sweep length
		ErrorFadeMin = 0.1, -- s of flight: the local → server path difference fades out over at least this (normally
		-- until the proxy is on track)
		CatchUpBy = 1.0, -- s: the proxy is on the replicated body's track by then (or by the first contact): it runs at
		-- 1 - lag / CatchUpBy of real speed until then (≈ 0.8 for the 0.19 s Studio lag)
		ExpectedLag = 0.19, -- s: the lag planned for before any has been measured (Studio measurement, this pass)
		MinSpeed = 0.5, -- the proxy never runs slower than this share of real speed (a measured lag larger than planned)
		ReplicationBuffer = 0.14, -- s: the replicated body's lag beyond the "Released" message's own delay (Studio:
		-- lag 0.15-0.16 s with a 0.01 s message delay; 0.31-0.33 s with 0.16 s; 0.48-0.53 s with 0.30 s)
		OnTrackTolerance = 0.01, -- s of flight: the proxy may hand over when no further ahead of the body than this
		LagSmoothing = 0.3, -- per-frame smoothing of the measured lag
		MaxLag = 0.6, -- s; a larger measured lag is clamped
		MaxLead = 0.2, -- s; a replicated body ahead of the proxy
		ContactArrive = 0.15, -- studs: the replicated body has reached the held contact point (or turns away from it)
		HoldMaxSeconds = 0.6, -- the proxy holds at a contact point at most this long
		HandoverBlendSeconds = 0.1, -- at the hand-over the proxy rides the replicated body while its offset fades out
		PendingSeconds = 1.0, -- a local throw the server has not confirmed by then is dropped
		GiveUpSeconds = 2.5, -- any proxy still up by then is dropped (the server's body is shown)
		ClaimRadius = 4, -- studs: a new body this close to an unconfirmed throw's release point is hidden as its own
		Pool = 2, -- pooled proxies
	},

	Body = {
		Diameter = 0.25, -- studs ≈ 64 mm (M67-like body) [inferred from the look]
		Color = Color3.fromRGB(46, 52, 40), -- dark body [confirmed look; value placeholder]
		BandColor = Color3.fromRGB(214, 180, 40), -- yellow band [confirmed look; value placeholder]
		Density = 2.5, -- [placeholder]
		Elasticity = 0.35, -- bounce [placeholder: bounce and roll are UNKNOWN]
		Friction = 0.6, -- [placeholder]
		RollDampingTorque = 0.1, -- a brake on spin: from 20 studs/s it rolls ≈ 7 studs (≈ 28 studs/s²) [placeholder]
		Gravity = 35, -- studs/s²: the project's scale (9.8 m/s² at 3.57 studs/m), as the ragdolls [implementation]
		LostBelowY = -200, -- a grenade that falls out of the world is removed without detonating [implementation]
	},

	Fuse = {
		Seconds = 4.0, -- release → detonation: 4.00–4.13 s over four throws (mean 4.06) [measured]; 4.0 as briefed
		StartsAt = "Release", -- the lever leaves with the grenade [inferred]
	},

	Fragments = {
		Count = 600, -- "GRENADE: 600 FRAGMENTS" [confirmed]
		-- all at once, straight, from one point [confirmed]; in every direction, spread evenly over the sphere
		-- (Fibonacci lattice, turned at random per grenade) [inferred]
		Range = 250, -- studs; rays cross the whole map (≫ 100 studs) [placeholder: maximum UNKNOWN]
		PenetrationStuds = 0, -- stops at the first wall or body [walls inferred; bodies UNKNOWN → no penetration]
		MassKg = 0.0006, -- "0.0006 × 962 × 3" [confirmed text; meaning inferred]; recorded, not simulated
		SpeedMps = 962, -- [confirmed text; meaning inferred]; recorded (fragments are instant [confirmed])
		OriginLift = 0.05, -- studs above the grenade's centre [implementation]
		-- Body hits: one BodyState hit per distinct part reached, at the first fragment's point; the count is kept
		-- ("hit (head) … × 3") [inferred grouping]. A body's hits arrive together: most severe wound first [inferred].
		DamagePerFragment = 10, -- non-BodyState, non-player humanoids only [placeholder]
		DamagePlayers = false, -- whether a grenade hurts players is UNKNOWN in the footage → off
		MaxBloodFragments = 24, -- fragment entries handed to the blood presentation per detonation (budget) [implementation]
		BloodPerPart = 3, -- … at most this many per body part, so every part reached shows blood [implementation]
	},

	Effects = {
		-- Sequence and timings [confirmed / measured, ± 1 frame]; sizes, speeds and colours [placeholder].
		-- No camera shake and no screen flash [confirmed].
		Sparks = { Count = 40, Speed = { 60, 120 }, Lifetime = { 0.06, 0.15 }, Size = 0.4, Brightness = 4, Color = Color3.fromRGB(255, 236, 180) },
		FlashAt = 1 / 30, -- frame 1 [measured]
		FlashSeconds = 4 / 30, -- 3–5 frames [measured]
		Flash = { Count = 3, Size = { 4, 7 }, Color = Color3.fromRGB(255, 244, 214) },
		Glare = { WidthStuds = 22, HeightStuds = 1.4, Color = Color3.fromRGB(255, 236, 200) }, -- long, low, horizontal
		Light = { Brightness = 8, Range = 20, Color = Color3.fromRGB(255, 214, 160) }, -- short warm light [confirmed]
		FadeSeconds = 2.5 / 30, -- the glow fades within 2–3 frames [measured]
		DustAt = 1 / 30, -- the dust dome is visible from frame +1, with the flash (gs 184, 434) [measured; was 2/30]
		Dust = { Count = 14, Size = { 3, 10 }, Speed = { 2, 6 }, Lifetime = { 3.5, 5 }, Color = Color3.fromRGB(176, 148, 112) }, -- visible ≥ 2 s [measured lower bound]
		-- built-in white soft blob (no uploads); the flash and the dust are tinted from it (the built-in "explosion"
		-- textures carry their own orange / near-black colours)
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		SparkTexture = "rbxasset://textures/particles/fire_sparks_main.dds",
		Pool = 4, -- pooled effect rigs per client [implementation]
		-- Red screen-edge pulse (grenade fidelity slice): an edge-only red tint, at full strength in the detonation frame,
		-- then 0.90 / 0.74 / 0.59 / 0.42 / 0.28 / 0.17 / 0.12 of it at +3 / +6 / +9 / +12 / +19 / +34 / +54 frames, gone
		-- by ≈ 2.1 s (debug clip, g 126; also gs 253) [look and envelope measured]. Strength = Fast · exp(−max(0, t − Hold) /
		-- FastTau) + (1 − Fast) · max(0, 1 − t / TailSeconds). Shown when fragments reach the local player's character [trigger
		-- inferred: 2 of 7 detonations, one close and one far; the player still takes no grenade damage (UNKNOWN)]
		RedEdge = {
			-- a dark red at ≈ 45 % at the very edge: the footage's top edge (y 2–14, thin bodycam vignette) goes from grey
			-- (55, 60, 60) to ≈ (78, 32, 32), redness −5 → +46 [measured]; its sides / bottom read only +11–15 because the
			-- bodycam vignette darkens over them (this game has no such vignette)
			Color = Color3.fromRGB(120, 10, 10),
			PeakAlpha = 0.45,
			-- how far the tint reaches inward (fraction of the screen height) and its profile (opacity factor at fractions of
			-- that depth): the footage's top edge holds ≈ 0.87 of its edge redness to 30 px, ≈ 0.5 at 70–90 px, ≈ 0.35 at
			-- 110–130 px; the bottom edge fades out by ≈ 120 px (g 126 vs 125) [measured]
			DepthScale = 0.22,
			Profile = { { 0, 1 }, { 0.18, 0.88 }, { 0.5, 0.5 }, { 0.8, 0.22 }, { 1, 0 } },
			Fast = 0.7,
			Hold = 0.05, -- the fast part starts decaying after this (0.90 of peak at +3 frames) [measured fit]
			FastTau = 0.3,
			TailSeconds = 2.1,
		},
	},

	Label = {
		Out = "FRAG OUT  x%d", -- [confirmed text, two spaces]
		None = "NO FRAGS LEFT", -- [confirmed text]
		SolidSeconds = 42 / 30, -- solid 42–43 frames in all six labels (g 28 → 70; gs 64 → 106 …) [measured; was 46/30,
		-- read as "visible until 74" instead of the start of the fade]
		FadeSeconds = 6 / 30, -- fades over ≈ 6 frames (g 71 → 76) [measured]
		-- bottom left, small light-grey text [confirmed]. Ink at x 24-93 ("FRAG OUT  x3"), caps 688-695 on the
		-- 1280 x 720 picture (M7) [measured]: the box's left at 23 px, its bottom 20 px above the screen bottom, 12 px
		-- Code (70 px wide) [calibrated in Studio; was (14, -14), 13 px]
		Position = UDim2.new(0, 23, 1, -20),
		TextSize = 12,
		Color = Color3.fromRGB(205, 205, 205),
	},
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
