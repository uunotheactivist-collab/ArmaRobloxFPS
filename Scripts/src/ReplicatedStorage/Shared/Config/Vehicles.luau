--!strict
-- Vehicles (data only). Evidence: ReferenceAnalysis/Truck/Truck_Analysis.md (truck.mp4, 1519 frames, measured with the
-- tools in ReferenceAnalysis/Truck/tools; the library entry Library/Videos/Truck.md re-verified and corrected there).
-- Tags: [CONFIRMED] seen / [MEASURED] a number from the frames / [INFERRED] reasoned / [PLACEHOLDER] needed to run, not
-- established / [UNKNOWN] not shown → not built. Frame numbers are 1-based at 30 fps.
-- THE TRUCK NEVER MOVES IN THE FOOTAGE: the key is turned to RUN but START is never held and the "WAIT lamp" text is still
-- up 10.2 s later; no engine sound (MEASURED: no level or band change after RUN). Driving, steering, braking, engine,
-- collision damage and destruction are UNKNOWN → not built.
-- Screen values are pixels of the 1280 × 720 reference picture and scale with the viewport height. The video's white
-- point is 197 (Roblox's own white icons read 197): colours here are the measured values × 1.29 [INFERRED rescale].
-- Every decision is the server's (Server.Vehicles.VehicleServer); a client only asks for an offered action.

local Vehicles = {
	Remotes = {
		Command = "VehicleCommand", -- client → server: ("Interact", vehicleModel, action, targetPart, seatId?)
		State = "VehicleState", -- server → one player: Entered / Left / Refused / Done (presentation and tests)
	},

	-- Character attributes (server-written; a client's own writes never replicate)
	Attributes = {
		Vehicle = "Vehicle", -- the VehicleId of the vehicle the character sits in, or nil
		Seat = "VehicleSeat", -- seat id ("Driver", "Back1" …), or nil
		SeatKind = "VehicleSeatKind", -- "Driver" | "Back", or nil
	},

	-- The interaction prompt: fixed in screen space, no backing panel [CONFIRMED]. [MEASURED, Truck_Analysis §6]
	Prompt = {
		Key = Enum.KeyCode.F, -- [CONFIRMED] the key letter is always F
		BoxLeftFromCentre = -61.4, -- px: key box x 578.6–598.0 (centre x 640) [MEASURED]
		BoxTopFromCentre = -9.4, -- px: y 350.6–370.0 (centre y 360) [MEASURED]
		BoxSize = 19.4, -- px, square, corners rounded 1–2 px [MEASURED]
		BoxCorner = 1.5, -- px [MEASURED]
		LetterHeight = 8.4, -- px, the near-black "F" [MEASURED]
		TextGap = 10, -- px from the box's right edge to the text ink (x 608.0) [MEASURED]
		SecondLineDown = 26.0, -- px: the second line's box … [MEASURED]
		SecondLineIndent = 25.4, -- … is this far right [MEASURED]
		CapHeight = 12.0, -- px, line 1 text [MEASURED]; line 2 is 0.8× smaller [MEASURED: cap 9.0–9.6]
		SecondLineScale = 0.8,
		RingDiameter = 12, -- px, the "○" of the inactive line, ≈ 1.5 px stroke, centred where its key box would be [MEASURED]
		RingStroke = 1.5,
		Font = Enum.Font.BuilderSans, -- proportional sans-serif [MEASURED]; the family is not identified [PLACEHOLDER]
		CapPerTextSize = 0.7, -- cap height ÷ TextSize for that font [implementation constant]
		BoxColor = Color3.fromRGB(255, 193, 106), -- raw (197, 149, 82) [MEASURED, rescaled]
		BoxPressedColor = Color3.fromRGB(255, 228, 184), -- raw (199, 176, 142) while pale [MEASURED, rescaled]
		LetterColor = Color3.fromRGB(25, 25, 25), -- near-black [MEASURED]
		TextColor = Color3.fromRGB(250, 250, 250), -- active line, raw ≈ 193 [MEASURED, rescaled]
		InactiveColor = Color3.fromRGB(226, 227, 230), -- the "○" line, raw ≈ 172 [MEASURED, rescaled]
		RingColor = Color3.fromRGB(205, 205, 205), -- raw 145–170 [MEASURED, rescaled]
		TextStrokeColor = Color3.fromRGB(15, 15, 15), -- dark ≈ 1 px outline [MEASURED look; TextStroke INFERRED]
		TextStrokeTransparency = 0.45,
		-- Fades [MEASURED]: in ≥ 0.9 after 3–4 frames, full after 5–7 (e.g. .57 .84 .92 .98 at 91–95) → an exponential
		-- approach; out over 4–6 frames. Swapping between targets is instant.
		FadeInTau = 1.6 / 30,
		FadeOutSeconds = 5 / 30,
		-- F press [MEASURED]: the box is pale for 4–5 frames when the prompt stays (1121–1124, 1237–1240 …); the action's
		-- effect (sound, door start) follows 1.6–2.4 frames after the first pale frame, so the request goes then. When the
		-- action takes the prompt away (enter / move / leave) the pale lasts only 1–2 frames (103–104, 259, 1024 …).
		PaleSeconds = 4.5 / 30,
		SendAfterSeconds = 2 / 30,
		SwitchInput = Enum.UserInputType.MouseWheel, -- moving the [F] between the two lines [PLACEHOLDER: UNKNOWN]
		RangeStuds = 9, -- an outside target this close to the eye can be used [PLACEHOLDER: the range is UNKNOWN]
	},

	-- The CONTROLS panel at the right edge while seated [CONFIRMED text, verbatim; three spaces between name and key]
	Controls = {
		Back = { "—  CONTROLS", "FIRE   LMB", "AIM   RMB", "RELOAD   R", "FREE LOOK   ALT", "CHANGE SEAT   F",
			"RADIO   CAPS", "DOOR / LEAVE   F" },
		Driver = { "—  CONTROLS", "THROTTLE / BRAKE   W / S", "REVERSE   HOLD S", "STEER   A / D", "HANDBRAKE   SPACE",
			"FULL POWER   SHIFT", "ENGINE KEY   F", "RADIO   CAPS", "DOOR / LEAVE   F" },
		-- Appears / vanishes within one frame: back from the entry cut (105), driver 4 frames after it (1027 → 1031);
		-- the last frame shown is 10 (back, 629 → 639) / 8 (driver, 1495 → 1503) frames after the exit cut [MEASURED].
		ShowDelay = { Back = 0, Driver = 4 / 30 },
		Linger = { Back = 11 / 30, Driver = 9 / 30 },
		Layout = { -- [MEASURED, Truck_Analysis §7]
			RightX = 1262.0, -- every line right-aligned here (the keys do not form a column)
			CentreY = 360.5, -- the block is centred vertically here
			LineSpacing = 14.7, -- 14.66 (back) / 14.71 (driver)
			CharAdvance = 5.35, -- px per character: monospace grid
			Font = Enum.Font.RobotoMono, -- a monospace face [family PLACEHOLDER]; its TextSize is chosen at run time so
			-- one character advances CharAdvance (TextService), which leaves its cap height ≈ 6.4 px against 7.0 measured
			KeyColor = Color3.fromRGB(186, 186, 186), -- raw ≈ 144 [MEASURED, rescaled]
			NameColor = Color3.fromRGB(170, 170, 170), -- raw ≈ 132: names ≈ 12 darker than keys [MEASURED]
			TitleColor = Color3.fromRGB(182, 182, 182), -- raw ≈ 141 [MEASURED]
		},
	},

	-- Seated presentation [CONFIRMED / MEASURED, Truck_Analysis §8]
	SeatBody = {
		-- Looking down while seated the player sees their own dark-navy legs and light-grey arm blocks across the lap (bed
		-- 140–184, 283–305, 421–455 …; cab 1488). Looking level, no rifle and no arm are visible in a bench seat.
		LegColor = Color3.fromRGB(58, 64, 82), -- raw ≈ (45, 50, 64) [MEASURED look, rescaled]
		LegSize = Vector3.new(0.6, 0.6, 1.7), -- thigh / shin block [PLACEHOLDER: proportions INFERRED from the frames]
		ArmColor = Color3.fromRGB(205, 205, 205), -- the viewmodels' block arm
		ArmSize = Vector3.new(0.392857, 0.392857, 2.67857),
		-- Bench seats: FIRE / AIM / RELOAD are listed on the CONTROLS panel [CONFIRMED text] but never used in the clip
		-- [UNKNOWN look]. The rifle is down (not shown) until one of them is pressed, then the existing weapon system runs
		-- as on foot, and goes down again this long after the last such input [PLACEHOLDER].
		RaiseHoldSeconds = 4,
	},

	-- The driver's arms [CONFIRMED / MEASURED, Truck_Analysis §8]: the left arm stays on the wheel's left rim (9–10
	-- o'clock) and goes with the door when the door is used; the right arm rests at 1–2 o'clock and goes to whatever cab
	-- control is hovered (out 1–2 frames, e.g. 1236 → 1237), and back once its press is over (retraction ends 4–5 frames
	-- after the pale period). The wheel never turns.
	DriverArms = {
		Size = Vector3.new(0.392857, 0.392857, 2.67857), -- the viewmodels' block arm
		Color = Color3.fromRGB(205, 205, 205),
		Shoulder = { L = Vector3.new(-0.95, -1.35, 0.25), R = Vector3.new(0.95, -1.35, 0.25) }, -- camera space [INFERRED:
		-- the arms enter from the lower left / lower right]
		DoorSide = "L", -- the door reach is the left arm (1072–1094 close, 1470–1488 open) [MEASURED]
		HoverSide = "R", -- the right arm reaches to hovered controls (key, lights, parking brake) [MEASURED]
		OutSeconds = 2 / 30,
		BackSeconds = 4.5 / 30,
		DoorBackSeconds = 10 / 30, -- back on the rim ≈ 11 frames after the door has shut (1083 → 1094) [MEASURED]
	},

	-- The view at a cut [MEASURED / INFERRED, Truck_Analysis §2 / §3]. Into a seat: the yaw becomes the seat's facing and
	-- the pitch is KEPT (driver entry +15.4° before → +16° after [MEASURED]; the bench cuts start 26–33° down after aiming
	-- down at the seat, the bed entry +3.8° [consistent, INFERRED]). Out of a seat: standing at the exit, facing as the exit
	-- point faces, looking steeply down (≈ 49° at 640, ≈ 56° at 629 [MEASURED]).
	Exit = {
		PitchDeg = -53,
	},

	-- Server-timed delay from the request (sent 2 frames after the press) to the cut. One frame, no animation
	-- [CONFIRMED]. Press-to-cut [MEASURED]: bed entry 103 → 105, seat changes 259 → 264 / 321 → 325 / 403 → 408 / 524 →
	-- 529, bed exit 624 → 629, driver entry 1024 → 1027, driver exit 1489 → 1495 (±1 frame; one frame of it is the seat
	-- replicating to the client).
	CutDelay = {
		EnterBack = 0,
		MoveSeat = 2 / 30,
		LeaveBack = 2 / 30,
		EnterDriver = 0,
		LeaveDriver = 3 / 30,
	},

	-- Driver door swing (presentation on every client; the server's door is at its end state at once) [MEASURED §4]
	Door = {
		OpenOutsideSeconds = 16 / 30, -- 931 → ≈ 947 (end from the sound), eased in-out
		OpenOutsideEase = "InOut",
		CloseInsideSeconds = 8.5 / 30, -- 1075 → 1083, eased in-out
		CloseInsideEase = "InOut",
		OpenInsideSeconds = 17 / 30, -- 1470 → ≈ 1487: fast 1470–1475, then an ease-out tail
		OpenInsideEase = "Out",
		CloseOutsideSeconds = 8.5 / 30, -- [PLACEHOLDER] never shown from outside; as from inside
		CloseOutsideEase = "InOut",
		OpenDeg = 82, -- [INFERRED 75–90° from 1008 / 1048]
	},

	-- Sounds heard [MEASURED §9]: outside door press 930, door swing end 947, door slam 1084.75 (the loudest, 1.75 frames
	-- after the door shuts), key 1122.78, parking brake ≈ 7 frames after the press (1244, 1275, 1300), inside door press
	-- 1468 and swing end 1485; nothing at any cut; NO ENGINE. The project has no sound assets and nothing may be uploaded:
	-- not built [PLACEHOLDER: timings kept here for when sounds exist].
	Sounds = nil,

	RatePerSecond = 8, -- VehicleCommand requests per player per second [implementation]

	-- Which vehicle types exist. One: the cargo truck (M923-family proportions INFERRED; built at the measured size,
	-- scaled to this project's eye height: Roblox/Assets/Vehicles/build_cargo_truck.luau).
	Types = {
		CargoTruck = {
			-- Start state [CONFIRMED: the first parking-brake prompt is "Release parking brake"; the key starts at STOP]
			Start = { DriverDoor = "Closed", Key = "STOP", ParkingBrake = true, Lights = false },
			Engine = {
				-- "Hold START  (WAIT lamp's still on)": the WAIT lamp is still on 10.2 s after RUN and START is never held
				-- [CONFIRMED]; when the lamp goes out and what START does are UNKNOWN → the engine never starts here.
				WaitLampSeconds = math.huge, -- [UNKNOWN → never]
			},
		},
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

return freeze(Vehicles)
