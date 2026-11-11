--!strict
-- The bolt-action sniper's scope (sniper2.mp4; ReferenceAnalysis/Sniper/Sniper_Analysis.md section 6). Data only, on the
-- accepted optics framework (Client.Optics): a "Magnified" picture-in-picture lens, main camera untouched.
-- Tags: [CONFIRMED] seen / [MEASURED] read from frames / [INFERRED] / [PLACEHOLDER] / [UNKNOWN] (not built as a claim).
-- Screen numbers are 1280 x 720 reference pixels (f = 514.15 px at the project's FOV 70 [INFERRED]); physical numbers are
-- metres in weapon recipe space (+X right, +Y muzzle, +Z up). The scope's body is part of the rifle model
-- (Shared.Assets.Weapons.SniperViewmodelData, Blender/Scripts/sniper_model.py), so this optic adds only the lens and its
-- picture (Housing is empty).
-- Optional fields used here that the accepted ReferenceScope does not have (Client.Optics; absent = the old behaviour):
--   Zoom (levels / wrap / change time), Lens.EyeBox.ObjectiveDiameter (exit pupil = objective / magnification),
--   Reticle.Lines (thin duplex centre lines), Reticle.ScalesWithZoom (first focal plane), Aim.HipPose.FromRest.

local SniperScope = {
	Id = "SniperScope",
	Kind = "Magnified",
	Reference = "C:/Users/cat/Downloads/sniper2.mp4 (SHA-256 C289AFF7...1FBD7), frames 398-843",

	Magnification = 6, -- [INFERRED] the unlabelled first zoom level (labels 9x / 12x / 3x seen; step 3); label value =
	-- picture magnification [INFERRED: the accepted scope.mp4 measurement, 4.5x for its unlabelled 5x-family scope]
	MainCameraZoom = 1.0, -- [CONFIRMED] outside-the-scope scale 1.00-1.01 across ADS and zoom changes

	-- Variable zoom [CONFIRMED labels 9x (540), 12x (553), 3x (635): 12x wraps to 3x; 6x INFERRED]. The input is never
	-- shown [UNKNOWN]: Client.WeaponController maps it to the mouse wheel [PLACEHOLDER]. The level persists across ADS
	-- [CONFIRMED: 3x again at 828-832]. The picture and the reticle change over ChangeTime [MEASURED: 3 frames].
	Zoom = {
		Levels = { 3, 6, 9, 12 },
		DefaultIndex = 2, -- 6x
		Wrap = true,
		ChangeTime = 3 / 30,
		LabelFormat = "%dx", -- [CONFIRMED] "9x", "12x", "3x"
	},

	Layout = {
		AxisHeight = 0.055, -- [PLACEHOLDER] optical axis above the bore (rifle model)
		EyepieceRearY = -0.075, -- [PLACEHOLDER] rear rim of the eyepiece bell
		EyepieceDiameter = 0.042, -- [PLACEHOLDER] eyepiece bell; it sets the scale of every distance below
		LensDiameter = 0.0286, -- [MEASURED ratio] lens 136 px / ring 200 px = 0.68 x 0.042 m
		LensRecess = 0.003, -- [PLACEHOLDER]
		EyeRelief = 0.108, -- [MEASURED] eye to rim: 0.042 m x 514.15 px / 200 px (scoped ring, frames 406-426, 474)
		ObjectiveY = 0.300, -- [PLACEHOLDER]
	},

	Housing = {},

	Lens = {
		CanvasPixels = 512,
		Tint = { 77, 113, 95 }, -- [MEASURED] lens floor (21, 32, 29) / outside floor (70, 72, 78) on frames 420 / 536
		GlassColor = { 92, 96, 104 }, -- [MEASURED] the eyepiece glass at the hip: bright grey-blue (frame 105)
		GlassTransparency = 0,
		Highlight = { -- [CONFIRMED] blue-white blob at the lens upper left (size / strength MEASURED approx, S4 crops)
			CentreU = 0.30, CentreV = 0.28, Radius = 0.22, Strength = 0.35,
		},
		RimColor = { 6, 6, 7 },
		EyeBox = { -- [CONFIRMED behaviour] the lens darkens from one side when the eye is off the axis (kicks, bolt, 12x)
			ExitPupilRadius = 0.004, -- m, at the default zoom (unused when ObjectiveDiameter is set)
			ObjectiveDiameter = 0.048, -- [INFERRED] exit pupil = objective / magnification: smaller at 12x (the lens
			-- goes dark at 12x while moving, frames 566-630) [PLACEHOLDER size]
			ShiftGain = 0.55, -- [PLACEHOLDER, as the accepted scope]
			DepthTolerance = 0.03,
			DepthShrink = 0.30,
			ClearRadius = 1.08,
			Softness = 0.30,
			MinRadius = 0.15,
		},
		Background = { 40, 44, 48 }, -- [PLACEHOLDER] behind the mirrored scene (a ViewportFrame renders no sky)
		Ambient = { 128, 128, 134 },
		LightColor = { 205, 205, 200 },
	},

	-- Duplex reticle [CONFIRMED family], first focal plane [CONFIRMED: it scales with the zoom label]. Sizes are
	-- fractions of the visible lens diameter (136 px) at the default zoom (6x) [MEASURED +-2 px, frames 420 / 530].
	Reticle = {
		Bars = { -- thick posts, all four directions [CONFIRMED in 420]
			Inner = 0.047, Outer = 0.327, Thickness = 0.029,
			Directions = { "Left", "Right", "Up", "Down" },
			Color = { 8, 8, 8 }, Alpha = 0.95,
		},
		Lines = { HalfLength = 0.06, Thickness = 0.009, Color = { 8, 8, 8 }, Alpha = 0.9 }, -- thin centre lines [MEASURED ~1 px]
		Dot = { Diameter = 0.022, Color = { 225, 40, 30 }, Alpha = 0.9 }, -- red centre [MEASURED ~3 px]
		ScalesWithZoom = true, -- [CONFIRMED] first focal plane: drawn size x (level / default level)
		ImagePixels = 512,
	},

	Aim = {
		InTime = 0.20, -- [MEASURED] 398 -> 404 (6 frames); 820 -> 825 (5 frames)
		InEase = "Smooth",
		OutTime = 0.167, -- [MEASURED] 763 -> 768 and 836 -> 841 (5 frames)
		OutEase = "Accelerate", -- [MEASURED] the ring drops 21 / 44 / 71 / 73 px per frame
		SettleStuds = 0.009, -- [MEASURED] arrives 4-20 px low (mean 12 px at the eye relief = 2.5 mm) ...
		SettleTime = 0.30, -- [MEASURED] ... and rises to rest in ~9 frames (825 -> 834)
		HipPose = {
			EyepieceScreen = { 696.5, 615.1 }, -- [MEASURED] rim centre, frames 1-8 and 104-112 (data/hip_eyepiece.csv)
			EyepieceWidthPx = 98, -- [MEASURED] rim width 88-105 px (depth 0.22 m)
			FocalPx = 514.15,
			Level = false, -- the best silhouette fit adds pitch +2.2 / roll -3.3 / yaw +0.6 deg (39_sniper_fit.py)
			FromRest = true, -- the weapon data's rest pose IS this measured hip pose (fitted there); use it as is
		},
	},

	Render = {
		MirrorMaxDistance = 4000,
		MirrorMinSize = 0.05,
		BuildPerFrame = 150,
		StaticChecksPerFrame = 80,
	},
}

return table.freeze(SniperScope)
