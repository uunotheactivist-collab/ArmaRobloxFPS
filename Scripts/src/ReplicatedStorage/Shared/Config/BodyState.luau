--!strict
-- Body hit + body state foundation: data only. The logic lives in ServerScriptService.Server.BodyHit and BodyState.
-- Basis: ReferenceAnalysis/BodyState/BodyState_Analysis.md (the reference game's own BALANCE / RAGDOLL debug panels).
-- Tags:
--   [confirmed]   read or seen in the footage;
--   [measured]    a number read or timed in the footage;
--   [inferred]    reasoned from the footage;
--   [placeholder] needed to run, not established by the footage;
--   [IMPLEMENTATION RULE] an internal condition the footage doesn't directly prove;
--   UNKNOWN       the footage doesn't show it.
-- RuleStatus at the bottom lists the status of every rule. Only CONFIRMED / MEASURED items are reference behaviour.
-- Only bodies whose model has the attribute `BodyModel` = true use this path (test bots for now). Everything else
-- keeps the existing placeholder damage.

local Config = {
	Attribute = "BodyModel",
	DebugViewAttribute = "BodyDebugView", -- Studio test bots: temporary tag + pose presentation (not ragdoll)

	-- Hit location labels: exactly the set seen in "hit (<label>)" [confirmed].
	Locations = { "head", "chest", "abdomen", "leftarm", "rightarm", "leftleg", "rightleg" },

	-- Part name → location. R6 first; R15 names map the same way. The R6 "Torso" is split by hit height (below).
	PartLocation = {
		Head = "head",
		["Left Arm"] = "leftarm",
		["Right Arm"] = "rightarm",
		["Left Leg"] = "leftleg",
		["Right Leg"] = "rightleg",
		UpperTorso = "chest",
		LowerTorso = "abdomen",
		LeftUpperArm = "leftarm",
		LeftLowerArm = "leftarm",
		LeftHand = "leftarm",
		RightUpperArm = "rightarm",
		RightLowerArm = "rightarm",
		RightHand = "rightarm",
		LeftUpperLeg = "leftleg",
		LeftLowerLeg = "leftleg",
		LeftFoot = "leftleg",
		RightUpperLeg = "rightleg",
		RightLowerLeg = "rightleg",
		RightFoot = "rightleg",
	},
	SplitTorso = "Torso", -- R6: the upper half (hit point's local Y ≥ 0) is "chest", the lower half "abdomen" [inferred]
	ChestParts = { Torso = true, UpperTorso = true }, -- parts whose top band is the throat zone
	-- Studs below the top of the chest part = the throat zone (still labelled "chest").
	-- [INFERRED / PLACEHOLDER]: a practical value. The footage shows a Throat wound from a "chest" hit, not a band size.
	ThroatBand = 0.3,

	-- Location / zone → wound [confirmed: head→Brain, chest→Throat or Lung, abdomen→Gut, legs→Limb; arms→Limb inferred].
	Wound = {
		head = "Brain",
		throat = "Throat",
		chest = "Lung",
		abdomen = "Gut",
		leftarm = "Limb",
		rightarm = "Limb",
		leftleg = "Limb",
		rightleg = "Limb",
	},
	-- The most severe wound is the one a body shows. Severity order: [inferred] (LINEBOT2: leg then chest → Throat);
	-- the order among the vital wounds is [placeholder].
	Severity = { Brain = 5, Throat = 4, Lung = 3, Gut = 2, Limb = 1 },
	-- A hit with these wounds enters DYING at once. [PLACEHOLDER rule] built from confirmed cases (LINEBOT5 brain,
	-- LINEBOT2 throat, DUMMY1 and MOVER5JOG gut). DUMMY4 shows a gut hit without DYING, so the true rule is UNKNOWN.
	ImmediateDying = { Brain = true, Throat = true, Gut = true },

	-- Per-hit losses (percent points), single readings rounded [measured]; the formula and weapon dependence are UNKNOWN.
	StrengthLoss = { head = 100, chest = 34, abdomen = 18, leftarm = 3, rightarm = 3, leftleg = 30, rightleg = 30 },
	LegsLoss = { leftleg = 80, rightleg = 80 }, -- legs read 0 / 15 / 24 % after leg hits [measured]
	StrengthRecoveryPerSecond = 15, -- while standing and not dying; LINEBOT8 66 → 82 → 86 % (8–24 %/s) [inferred]
	-- Strength at or below this goes down. [PLACEHOLDER]: not established by the footage (DYING bots read 12–24 %, but
	-- LINEBOT8 went down at 86 %). Kept configurable for testing.
	CollapseAtStrength = 15,
	LegsGoneFallAfter = 0.9, -- s from legs reaching 0 to starting to go down; a leg-hit trip 0.93 s [measured]
	ReactSeconds = 0.3, -- the transient flinch flag; the flinch is 0 while DYING [confirmed]; duration [placeholder]

	-- DYING → down (s): brain 0.45, throat 1.07, gut 0.53 [measured, single sequences]; others [placeholder].
	FallSeconds = { Brain = 0.45, Throat = 1.07, Gut = 0.53, Lung = 0.5, Limb = 0.5 },
	-- Dying behaviour once down.
	--   Brain LIMP and Throat CHOKE: [confirmed] in every observed case.
	--   Lung CRYING: the only case observed.
	--   Gut CRYING and Limb SHOCK: [PLACEHOLDER / INCOMPLETE]. Temporary test behaviour only. The footage shows several
	--   behaviours for these wounds (ObservedBehaviours) and no selection rule. No selection formula is invented; the
	--   final rule is open.
	DownBehaviour = { Brain = "LIMP", Throat = "CHOKE", Lung = "CRYING", Gut = "CRYING", Limb = "SHOCK" },
	DownBehaviourStatus = {
		Brain = "CONFIRMED",
		Throat = "CONFIRMED",
		Lung = "CONFIRMED (one case)",
		Gut = "PLACEHOLDER",
		Limb = "PLACEHOLDER",
	},
	-- Every behaviour seen per wound [confirmed]; the alternatives' triggers are UNKNOWN (not used as rules).
	ObservedBehaviours = {
		Brain = { "LIMP", "AGONAL", "POSTURE" },
		Throat = { "CHOKE" },
		Lung = { "CRYING" },
		Gut = { "CRYING", "WRITHE", "FADING" },
		Limb = { "SHOCK", "WRITHE", "CRYING", "CRAWL", "PANIC" },
	},
	-- Life drain while down (%/s) [measured]. LIMP 47–79 → 60; unknown rates → 0 (no drain = never dies).
	LifeDrainPerSecond = {
		LIMP = 60,
		AGONAL = 9,
		CHOKE = 6,
		CRYING = 3.6,
		CRAWL = 2,
		POSTURE = 1.6,
		WRITHE = 1.1,
		SHOCK = 0,
		PANIC = 0,
		FADING = 0,
	},
	-- Behaviour changes while down: CRYING → AGONAL below 20 % life [inferred, one sequence: LINEBOT3 26 % → 19 %].
	BehaviourChange = { CRYING = { BelowLife = 20, To = "AGONAL" } },

	-- DEAD when life reaches 0 (life ≤ 0). [IMPLEMENTATION RULE / NOT DIRECTLY PROVEN BY FOOTAGE]: no frame shows a bot
	-- at 0 %. The footage shows life draining toward 0 and a "No pulse" reading later on one bot.
	Phases = { "ALIVE", "INJURED", "DYING", "DEAD" },
	Stances = { "STANDING", "FALLING", "DOWN" },
	PhaseOrder = { ALIVE = 1, INJURED = 2, DYING = 3, DEAD = 4 },
	RecentResults = 64, -- Studio only: last hit results kept for the focused test

	-- Status of every rule (data only: for review and tests, not read by the logic). Nothing marked INFERRED,
	-- PLACEHOLDER, UNKNOWN or IMPLEMENTATION RULE is an accepted reference behaviour.
	RuleStatus = {
		Locations = "CONFIRMED (the seven labels)",
		TorsoSplit = "INFERRED (chest / abdomen by height)",
		ThroatBand = "INFERRED / PLACEHOLDER",
		Wounds = "CONFIRMED (arms → Limb INFERRED)",
		Severity = "INFERRED (order PLACEHOLDER)",
		ImmediateDying = "PLACEHOLDER (from confirmed cases; a counter-example exists)",
		StrengthLegsLoss = "MEASURED (single readings; formula UNKNOWN)",
		StrengthRecovery = "INFERRED (one sequence)",
		CollapseAtStrength = "PLACEHOLDER",
		LegsGoneFallAfter = "MEASURED (one trip)",
		ReactSeconds = "PLACEHOLDER",
		FallSeconds = "MEASURED (brain / throat / gut, single cases); PLACEHOLDER (lung / limb)",
		DownBehaviour = "see DownBehaviourStatus (Gut and Limb: PLACEHOLDER / INCOMPLETE)",
		LifeDrain = "MEASURED (unobserved rates set to 0)",
		CryingToAgonal = "INFERRED (one sequence)",
		HitsWhileDying = "UNKNOWN (temporary implementation choice: recorded only, no state change)",
		DeadAtZeroLife = "IMPLEMENTATION RULE / NOT DIRECTLY PROVEN BY FOOTAGE",
		PlayerCharacters = "NOT INTEGRATED (the design covers R6 / R15 bots and R15 players; not built)",
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
