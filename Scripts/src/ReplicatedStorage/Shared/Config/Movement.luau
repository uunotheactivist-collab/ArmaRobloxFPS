--!strict
-- Player movement + first-person presentation (data only). Evidence: ReferenceAnalysis/Movement/Movement_Analysis.md.
-- Tags: [MEASURED] a number from the footage (assumptions noted) / [CONFIRMED] seen / [INFERRED] reasoned /
-- [PLACEHOLDER] needed to run, not established / [UNKNOWN] not shown (not built).
-- Read by Server.Movement (authority: stance, speeds, validation) and Client.Movement (input smoothing, camera, the
-- viewmodel movement layers). Only the server's copy is trusted.

local Movement = {
	-- Attribute names. Character attributes are written by the server only (clients' writes never replicate).
	Attributes = {
		Stance = "Stance", -- "STAND" | "CROUCH"
		MoveState = "MoveState", -- "IDLE" | "WALK" | "CROUCH" | "JUMP" | "FALL" | "LAND" | "DEAD"
		Rejections = "MoveRejections", -- count of server corrections for this character (security / tests)
		Locked = "MoveLocked", -- reason the stance can't change right now (e.g. "Interaction"), or nil
	},

	Walk = {
		Speed = 5.6, -- studs/s [MEASURED] 1.37 camera heights/s x 4.05 studs (floor flow, bot interaction 46-61; FOV 70;
		-- +-25 %). The engine default 16 is about 3x the footage. Cross-check ~1.5 h/s (M5); gait 0.46 s/step (M6).
		StepSeconds = 0.46, -- [MEASURED] footstep-like onsets every 13.5-14.1 frames while walking (grenade 254-493)
		MovingSpeed = 0.5, -- studs/s: a walk ends below this (state IDLE) [PLACEHOLDER]
		StartSpeed = 1.5, -- studs/s: a walk starts above this (hysteresis against contact jitter) [PLACEHOLDER]
	},

	-- Input smoothing on the client (the server only caps speed). One stop in the footage fades over ~0.3 s.
	Accel = {
		StartTau = 0.10, -- s, first-order time constant of the move input when starting [PLACEHOLDER; starting is not shown]
		StopTau = 0.10, -- s, when stopping / reversing [MEASURED weakly: one stop, ~0.3 s to rest, bullet pen test 2-17]
	},

	Crouch = {
		Enabled = true, -- [CONFIRMED] "CROUCHED" toast + crouched hip view (scope cool 1-36)
		Key = Enum.KeyCode.C, -- [PLACEHOLDER] the key is never shown
		GamepadKey = Enum.KeyCode.ButtonB, -- [PLACEHOLDER]
		Speed = 2.8, -- studs/s [PLACEHOLDER] (half the walk); crouch-walking is never shown
		EyeHeight = 2.7, -- studs above the feet [PLACEHOLDER]; not measurable in scope cool (floor too foreshortened)
		TransitionSeconds = 0.25, -- camera ease between eye heights [PLACEHOLDER]
		StandClearance = 0.3, -- studs of free space required above the standing body to stand up [PLACEHOLDER]
		AllowJump = false, -- [PLACEHOLDER] no jumping from a crouch (jumping itself is UNKNOWN)
		Toast = {
			Text = "CROUCHED", -- [CONFIRMED] verbatim
			ShowOnStand = false, -- [UNKNOWN] no toast is shown for standing up; none built
			SolidSeconds = 46 / 30, -- [MEASURED on the same toast style] "FRAG OUT  xN" holds 1.53 s (grenade)
			FadeSeconds = 8 / 30, -- [MEASURED] "CROUCHED" fades over frames ~32-40 (scope cool)
			-- the shared bottom-left style (Config.Grenade.Label): small light-grey Code font [CONFIRMED look]
			Position = UDim2.new(0, 14, 1, -14),
			TextSize = 13,
			Color = Color3.fromRGB(205, 205, 205),
		},
	},

	Sprint = {
		Enabled = false, -- [UNKNOWN] never identifiable in the footage; NOT BUILT. A client "Sprint" intent is refused.
	},

	Jump = {
		Enabled = true, -- [PLACEHOLDER] jumping is never shown; the engine default that already existed is kept as it was
		Height = 7.2, -- studs [PLACEHOLDER] engine default (StarterPlayer.CharacterJumpHeight); not tuned, not claimed
	},

	-- Camera (client presentation). The weapon's own camera offsets (recoil climb, shake, Stressed sway, reload camera)
	-- are unchanged; the roll below is applied before them each frame.
	Camera = {
		EyeHeight = 4.05, -- studs above the feet, standing [MEASURED] floor grid 4.04-4.07 (FOV 70) and 0.805 x the
		-- 5-stud test bot (FOV-independent). Applied for every avatar (the camera is placed above the floor each frame).
		FieldOfView = nil, -- unchanged: hip 70 / ADS 1.16x stay with the weapon config [CONFIRMED: no movement FOV change]
		PitchBobDeg = 0, -- [MEASURED] no step-periodic pitch (horizon steady within +-0.1 deg while walking)
		VerticalBobStuds = 0, -- [UNKNOWN] translation bob is not measurable from the horizon; none
		LandDipStuds = 0, -- [UNKNOWN] no landing is ever shown; none
		FloorSmoothTau = 0.05, -- s: the floor under the feet is eased so a stair step doesn't jump the camera in one
		-- frame [PLACEHOLDER; stairs are never walked in the footage]. Airborne, the camera follows the body directly.
		Roll = {
			GainDegPerDegPerSec = 0.07, -- [MEASURED] 0.06-0.1 deg of roll per deg/s of turn (bot interaction, bullet pen)
			-- Sign: turning right rolls the view so the horizon dips to the right [MEASURED]
			Tau = 0.20, -- s, smoothing of the roll [INFERRED]
			MaxDeg = 2.7, -- [MEASURED] largest roll seen (-2.5 .. +2.7)
			CutDeg = 25, -- a camera jump larger than this in one frame is a cut (respawn, scripts): ignored
		},
	},

	-- Viewmodel movement layers (one rotation of the whole viewmodel about the camera, in front of the weapon's own
	-- sway / recoil / reload poses; the rig's internal joints are untouched, so arms stay attached).
	Viewmodel = {
		LookLag = {
			Tau = 0.30, -- s [MEASURED] the weapon trails turns by turn rate x 0.22-0.37 s (grenade 280-320)
			MaxDeg = 7.4, -- [MEASURED] largest trailing offset seen
			CutDeg = 25, -- scripted camera jumps are not turns
			AimReduction = 0.85, -- [INFERRED] aiming while turning is never shown; keep the sight usable
		},
		Walk = {
			PitchDeg = 0.6, -- [MEASURED upper bound] +-8 px vertical per step while walking straight (bot interaction 49-61)
			YawDeg = 1.0, -- [PLACEHOLDER] lateral walk motion is not separable from the turn lag in the footage
			AimReduction = 0.85, -- [INFERRED]
			BlendTau = 0.15, -- s, fade in / out with speed [PLACEHOLDER]
		},
	},

	-- Server authority (validation runs on a timer, not every frame; one ground ray + one path ray per check).
	Server = {
		CheckSeconds = 0.1,
		SpeedTolerance = 1.15, -- allowed = speed cap x this
		BankSeconds = 0.5, -- unused travel allowance can be banked up to this many seconds (network jitter) ...
		BankStuds = 2.0, -- ... plus this many studs
		OverdraftStuds = 1.0, -- more than this beyond the allowance is a violation -> moved back
		-- (in the air the same cap applies: the humanoid keeps its ground speed while airborne)
		RiseMargin = 1.5, -- studs above the highest legal point (support + root height + jump height) before a violation
		GroundProbe = 12, -- studs: downward ray length from the root
		GroundedGap = 1.2, -- studs: root bottom within (hip height + this) of the floor = grounded
		LandSeconds = 0.2, -- MoveState LAND lasts this long after touching down [PLACEHOLDER]
		JumpRiseSpeed = 1.0, -- studs/s upward while airborne = JUMP (else FALL)
		IntentPerSecond = 6, -- MovementIntent remote rate limit
		BlockedPathMaxStuds = 64, -- path ray cap
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

return freeze(Movement)
