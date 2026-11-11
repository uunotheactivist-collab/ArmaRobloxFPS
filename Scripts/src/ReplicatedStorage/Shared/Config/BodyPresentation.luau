--!strict
-- Hit reaction + active ragdoll presentation: data only. It consumes the accepted BodyState (Config.BodyState rules
-- are not changed here). Basis: ReferenceAnalysis/HitReactions/HitReactions_Analysis.md.
-- Tags: [confirmed] [measured] [inferred] [placeholder] UNKNOWN; nothing [placeholder] is reference behaviour.

local Config = {
	Attribute = "BodyPresentation", -- models with BodyPresentation = "ActiveRagdoll" are presented by Server.BodyPresentation
	Mode = "ActiveRagdoll",

	-- Reference joint names → R15 Motor6D names (in the child part) [confirmed joint set: neck, waist, shoulders,
	-- elbows, hips, knees]. Wrists use the elbow k and ankles the knee k [placeholder].
	Joints = {
		neck = { "Neck" },
		waist = { "Waist" },
		rshld = { "RightShoulder" },
		lshld = { "LeftShoulder" },
		relb = { "RightElbow", "RightWrist" },
		lelb = { "LeftElbow", "LeftWrist" },
		rhip = { "RightHip" },
		lhip = { "LeftHip" },
		rknee = { "RightKnee", "RightAnkle" },
		lknee = { "LeftKnee", "LeftAnkle" },
	},

	-- Muscles: torque = limb weight × reach × g × gain × k [confirmed formula, RAGDOLL panel]. "Limb" = the part
	-- beyond the joint and everything attached to it.
	Gain = 1.0, -- [inferred] from "k = 1: enough to hold the limb up against gravity"
	Responsiveness = 15, -- AlignOrientation responsiveness [placeholder]
	-- Gravity a ragdoll falls under, studs/s²: the project's own scale, the same value the accepted weapon ballistics
	-- use for 9.8 m/s² (Config.Weapons.M4 / AK Gravity = 35). workspace.Gravity (196.2) would make bodies fall about
	-- 2.4× faster than the reference (first kill: kneeling ≈ 0.6 s, settled ≈ 1.1 s [measured]). A per-part upward
	-- force supplies the difference; nothing else in the world changes. Muscle torques and the crawl force use it too.
	Gravity = 35,

	-- Per-behaviour k snapshots: one panel reading each [measured]. Which reading is used when several exist is
	-- [placeholder]; alternatives are in the analysis. Life = the life % at that reading (for fading).
	Profiles = {
		SHOCK = { Life = 100, k = { neck = 0.47, waist = 0.21, rshld = 0.47, lshld = 0.42, relb = 0.47, lelb = 0.47, rhip = 0.26, lhip = 0.21, rknee = 0.21, lknee = 0.21 } },
		CRYING = { Life = 100, k = { neck = 0.67, waist = 0.41, rshld = 0.69, lshld = 0.69, relb = 0.69, lelb = 0.69, rhip = 0.37, lhip = 0.37, rknee = 0.41, lknee = 0.41 } },
		CHOKE = { Life = 97, k = { neck = 1.02, waist = 1.02, rshld = 1.02, lshld = 1.02, relb = 1.02, lelb = 1.02, rhip = 1.02, lhip = 1.02, rknee = 1.02, lknee = 1.02 } },
		WRITHE = { Life = 92, k = { neck = 1.28, waist = 1.28, rshld = 1.28, lshld = 1.28, relb = 1.28, lelb = 1.28, rhip = 1.28, lhip = 1.28, rknee = 1.28, lknee = 1.28 } },
		CRAWL = { Life = 99, k = { neck = 1.04, waist = 0.73, rshld = 1.04, lshld = 2.09, relb = 1.04, lelb = 1.04, rhip = 0.73, lhip = 0.73, rknee = 0.73, lknee = 0.73 } },
		PANIC = { Life = 94, k = { neck = 2.36, waist = 0.76, rshld = 1.18, lshld = 1.18, relb = 1.18, lelb = 1.18, rhip = 0.76, lhip = 0.76, rknee = 0.76, lknee = 0.76 } },
		AGONAL = { Life = 19, k = { neck = 0.02, waist = 0.02, rshld = 0.02, lshld = 0.02, relb = 0.02, lelb = 0.02, rhip = 0.02, lhip = 0.02, rknee = 0.02, lknee = 0.02 } },
		FADING = { Life = 99, k = { neck = 1.10, waist = 1.47, rshld = 1.20, lshld = 1.20, relb = 1.20, lelb = 1.20, rhip = 1.29, lhip = 1.29, rknee = 1.47, lknee = 1.47 } },
		LIMP = { Life = 100, k = { neck = 0, waist = 0, rshld = 0, lshld = 0, relb = 0, lelb = 0, rhip = 0, lhip = 0, rknee = 0, lknee = 0 } }, -- [confirmed]
		POSTURE = { Life = 100, k = { neck = 0.5, waist = 0.5, rshld = 0.5, lshld = 0.5, relb = 0.5, lelb = 0.5, rhip = 0.5, lhip = 0.5, rknee = 0.5, lknee = 0.5 } }, -- never read: [placeholder]
	},
	-- k = profile k × (life / profile Life) [inferred from CHOKE 1.02@97 → 0.98@93 → 0.85@81]; DEAD → 0.
	FadeWithLife = true,
	MaxK = 3,

	-- CRAWL moves the body along its head direction [measured: "crawling 0.6 studs/s"].
	CrawlSpeed = 0.6,
	-- The push's force cap, × body weight × Surface.Friction: it has to beat the body's sliding friction to reach the
	-- measured speed [placeholder factor]. (Fidelity pass: was 0.6 × weight at friction 0.2; with friction 0.8 that
	-- stalled the crawl at 0.11 studs/s.)
	CrawlForceOverFriction = 2,

	-- Going over: toppling rate about the feet [measured: world tags "GOES OVER 3.11 m/s, 2.2 rad/s about the feet"
	-- (Ragdoll) and "… 1.5 rad/s about the feet" (Ragdoll Physics); which reading to use is a placeholder choice: 2.2
	-- (with 1.5, from the folded body, it was down ≈1.2 s / still ≈1.9 s, against F1's ≈0.6 / ≈1.1 s)]. Applied at
	-- the end of the staged fall (Fall.GoOverAtRelease). LIMP never gets it: it sinks straight down [confirmed].
	-- Direction forward [inferred from F1, which folds forward]; the general rule is UNKNOWN (F7).
	GoOverRadPerSecond = 2.2,

	-- Staged fall (fidelity pass; analysis §7). Times from the start of the fall (DYING, or BodyState's fall after
	-- unstable legs).
	Fall = {
		-- A. "Fighting the fall": the body stands on its held muscles before the legs go.
		--    [measured range 0.0–0.4 s: F1 legs give ≤ 0.13 s after the first shot; F2 0.33–0.4 s after DYING; panels
		--    "goes over in 0.0–0.2 s"]; the chosen value [placeholder] within it.
		SupportLossSeconds = 0.15,
		LimpSupportLossSeconds = 0.17, -- LIMP stays upright ≈5 frames, then sinks [measured, F3, one case]
		-- B. Knees / hips give way [confirmed F1: knees first]: the hip / knee / ankle muscles go slack (× this) and the
		--    knees are started forward (a straight leg is a balanced column). At the end of the fall (D) they take
		--    hold again, at the profile's k, of the pose the legs went down in. Values [placeholder].
		LegSupportDuringFall = 0,
		BuckleStartRadPerSecond = 2.5, -- knee-forward start: thighs about the hips, shins about the ankles [placeholder]
		BuckleForwardStudsPerSecond = 0.5, -- the body above the hips moves forward with the knees [placeholder]
		-- C. The upper body keeps its orientation while the legs fail [confirmed F1: upper body, arms and rifle keep the
		--    aim pose while sinking, 230–241; F4 "fighting the fall … holding the pose it went down in"]: a temporary
		--    world-orientation hold on the UpperTorso. Torque = upper-body weight × reach × g × k [k placeholder]. LIMP
		--    and DEAD bodies get none (no control).
		UpperHoldK = 1.0,
		UpperHoldSeconds = 0.4, -- [measured, F1: the aim pose held until ≈241, 0.4 s after the first shot]
		-- D. Hand-over to physics: the hold fades out while it folds the upper body forward [confirmed F1 242–247: "the
		--    arms drop and the body folds", ≈0.17 s measured]; the fold angle [placeholder]. The hold is destroyed
		--    afterwards (nothing stays active).
		ReleaseFadeSeconds = 0.17,
		FoldDeg = 35,
		-- At the hand-over the folded body goes over forward (GoOverRadPerSecond, about the feet) onto its knees and
		-- front [inferred: F1 folds forward; F2 lies flat]. F1 itself then stays seated, but with the reference's own
		-- muscle strengths (k ≈ 0.2–0.4 of a limb's weight; no balance controller is modelled) nothing can hold a
		-- seated trunk up: off, the body sits down behind its heels and rolls onto its back. Which end a body takes
		-- is UNKNOWN (no rule in the footage). Non-LIMP bodies topple, LIMP bodies sink (kept from the accepted slice).
		GoOverAtRelease = true,
	},

	-- Ragdoll surfaces: feet grip and bodies don't bounce or slide on the ground [inferred: bodies "crumple where they
	-- stand" and settle (F1, F6)]; values [placeholder]. Density is kept, so masses and muscle torques don't change.
	-- (The test bots are SmoothPlastic, friction 0.2: their feet slid forward ≈1 stud during the fold.)
	Surface = { Friction = 0.8, Elasticity = 0, FrictionWeight = 10, ElasticityWeight = 10 },
	-- Part pairs that don't collide besides the jointed pairs: the test rig's cube thighs jam on their own heels in a
	-- deep knee bend, where a real thigh and calf compress [placeholder; rig-specific].
	NoCollidePairs = { { "RightUpperLeg", "RightFoot" }, { "LeftUpperLeg", "LeftFoot" } },

	-- Ragdoll joint limits, degrees [inferred: conservative human range of motion. The footage shows only that the bots
	-- bend at the waist, elbows and knees (R2), that the knees fold fully when kneeling / sitting (F1) and that nothing
	-- bends backwards; no angle is measurable]. Values [placeholder].
	Limits = {
		-- One-way hinges about the body's right axis: flexion only, no hyperextension.
		Knee = { Hinge = true, Flex = 140, Back = 0 },
		Elbow = { Hinge = true, Flex = 145, Back = 0 },
		-- Ball sockets: a cone of half-angle Cone whose centre is tilted Tilt degrees forward of the rest direction
		-- (flexion range Cone + Tilt, extension Cone − Tilt), and a twist range ±Twist.
		Waist = { Cone = 35, Tilt = 10, Twist = 25 },
		Neck = { Cone = 45, Tilt = 10, Twist = 40 },
		Shoulder = { Cone = 90, Tilt = 30, Twist = 45 },
		Wrist = { Cone = 60, Tilt = 0, Twist = 10 },
		Hip = { Cone = 60, Tilt = 40, Twist = 30 },
		Ankle = { Cone = 35, Tilt = 5, Twist = 10 }, -- shin forward over the foot 40° (a deep knee bend), heel up 30°
	},

	-- Standing reactions (procedural, on the Motor6D C0s of the anchored standing rig).
	Flinch = {
		-- timing: peak within 2 frames, back within BodyState's 0.3 s Reacting window [measured 3–6-frame swing]
		PeakSeconds = 0.067,
		-- amplitude [placeholder]; the direction is UNKNOWN, so the flinch is the same for every hit
		WaistBackDeg = 12,
		WaistTwistDeg = 8,
		ArmSwingDeg = 22,
	},
	-- Broken / weakened pose, following BodyState strength and legs (a broken pose exists [confirmed]; scales
	-- [placeholder]).
	-- Knee bend = hips +½, knees −1, ankles +½ (feet stay flat); the pelvis drops by what the bent legs lose in height
	-- (LegLengthStuds = hip → ankle of the test rig), so the feet stay on the ground. (Fidelity pass: replaces a fixed
	-- 0.45-stud drop that pushed the feet into the ground.)
	Posture = {
		SlumpDegAtZeroStrength = 30,
		NeckDegAtZeroStrength = 15,
		KneeDegAtZeroLegs = 40,
		LegLengthStuds = 1.7,
	},
	-- Unstable (legs 0) until BodyState's fall begins: one recovery step plus a sway [measured range "lands 0.02–0.37 m
	-- in 0.23–0.38 s"; chosen values placeholder], and the legs sag (more knee bend, the body starts to descend) over
	-- BodyState's own legs-gone delay (Config.BodyState.LegsGoneFallAfter, 0.9 s) [placeholder: the footage shows the
	-- broken pose but no measurable sag].
	Stumble = {
		StepStuds = 0.5,
		StepSeconds = 0.3,
		SwayDeg = 9,
		SwayPeriod = 0.6,
		SagKneeDeg = 30,
	},
	DebugSampleHz = 30, -- Studio-only sampler for the focused test
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
