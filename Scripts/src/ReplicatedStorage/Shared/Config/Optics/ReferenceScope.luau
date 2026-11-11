--!strict
-- The scope shown in the reference clip scope.mp4 (data only). The first optic built on the shared optics framework
-- (StarterPlayerScripts.Client.Optics; ReferenceAnalysis/Optics/Optics_Analysis.md).
--
-- Tags follow the analysis: [CONFIRMED] seen in the footage, [MEASURED] a number read from the footage,
-- [INFERRED] reasoned from it, [PLACEHOLDER] a stand-in value the footage does not give, [UNKNOWN] not built.
--
-- Framework kinds (Client.Optics.Optic): "Magnified" = picture-in-picture lens with its own scope camera (this one);
-- "Reflex" = red dot / holographic window with a reticle projected at infinity and no lens picture (Magnification 1).
-- Screen numbers are 1280 x 720 reference pixels; physical numbers are metres in weapon recipe space
-- (+X right, +Y muzzle, +Z up; the builders convert to studs: 1 stud = 0.28 m).

local ReferenceScope = {
	Id = "ReferenceScope",
	Kind = "Magnified",
	Reference = "C:/Users/cat/Downloads/scope.mp4 (same scope family as sniper.mp4 / scope cool.mp4)",

	-- Picture-in-picture: only the lens is magnified; the main camera keeps its field of view.
	Magnification = 4.5, -- [MEASURED, approximate] lens image vs the unscoped view, screen scale: 4.29-4.63 over seven
	-- frame pairs (mean 4.49; library 4.40-4.65). No zoom label appears in scope.mp4, so the scope's own zoom
	-- setting is UNKNOWN; variable zoom (5x-25x labels in sniper / scope cool) is not built.
	MainCameraZoom = 1.0, -- [CONFIRMED] outside-the-scope scale 0.98-1.03 in all four scope videos (library); the
	-- main camera FOV is never touched by the optic.

	-- Physical layout on the weapon (metres, recipe space). The test platform is the M4 body (Config.Weapons.ScopeTest).
	Layout = {
		AxisHeight = 0.135, -- [PLACEHOLDER] optical axis above the bore origin: high wide mount clearing the M4 front post
		EyepieceRearY = -0.110, -- [PLACEHOLDER] rear rim of the eyepiece (behind the receiver)
		EyepieceDiameter = 0.046, -- [PLACEHOLDER] real 5-25x eyepiece size; it fixes the eye relief below
		LensDiameter = 0.029, -- [MEASURED ratio] visible lens / ring = 162 / 266 px = 0.61 (scope.mp4 frames 448-452,
		-- 100-108, 181-192) -> 0.61 x 0.046 m (glass seen inside the rim)
		LensRecess = 0.003, -- [PLACEHOLDER] glass behind the rim
		EyeRelief = 0.0888, -- [MEASURED] eye to rim: the ring is 266.5 px wide at rest (circle fits, rms 0.7 px,
		-- frames 100-108 and 181-192) = 0.046 m x 514.15 px / 266.5 px. Assumes the project's hip FOV 70 [INFERRED].
		ObjectiveY = 0.285, -- [PLACEHOLDER] front of the objective bell
	},

	-- Optic housing (scope body, mount and the unused mini red-dot box), separate from the lens and the reticle.
	-- Procedural recipes in the format of Shared.Viewmodel.ProceduralMesh (no asset upload needed).
	Housing = {
		Body = {
			Material = "Optic", -- dark polymer/metal from the weapon data's material table [CONFIRMED black scope]
			Recipes = {
				{ -- eyepiece bell, tube, objective bell [CONFIRMED look: large-objective variable scope; sizes PLACEHOLDER]
					op = "lathe",
					profile = {
						{ -0.110, 0.0150 }, { -0.110, 0.0230 }, { -0.050, 0.0230 }, { -0.035, 0.0170 },
						{ 0.165, 0.0170 }, { 0.215, 0.0300 }, { 0.285, 0.0300 }, { 0.285, 0.0262 },
					},
					segs = 28, cx = 0, cz = 0.135, rx = 1, rz = 1,
				},
				{ -- inner wall of the eyepiece rim (3 mm deep), so the recessed glass sits in a dark well
					op = "lathe",
					profile = { { -0.107, 0.0150 }, { -0.110, 0.0150 } },
					segs = 28, cx = 0, cz = 0.135, rx = 1, rz = 1,
				},
				{ -- objective glass seen from the front (dark) [PLACEHOLDER]
					op = "lathe",
					profile = { { 0.281, 0.0262 }, { 0.281, 0.0001 } }, -- faces the muzzle (+Y)
					segs = 28, cx = 0, cz = 0.135, rx = 1, rz = 1,
				},
				{ -- elevation turret (top) [CONFIRMED turrets in sniper rotations; size PLACEHOLDER]: a lathe about Y
					-- turned upright (rotx 90: y -> z) and moved onto the tube
					op = "translate",
					d = { 0, 0.060, 0.135 },
					geo = {
						op = "rotx",
						deg = 90,
						about = { 0, 0, 0 },
						geo = {
							op = "lathe",
							profile = { { 0.016, 0.0001 }, { 0.016, 0.0130 }, { 0.040, 0.0130 }, { 0.040, 0.0001 } },
							segs = 16, cx = 0, cz = 0, rx = 1, rz = 1,
						},
					},
				},
				{ op = "cylx", c = { 0, 0.060, 0.135 }, x = { 0.016, 0.040 }, r = 0.0125, segs = 16 }, -- windage (right)
				{ op = "cylx", c = { 0, 0.060, 0.135 }, x = { -0.036, -0.016 }, r = 0.0105, segs = 16 }, -- side knob (left)
				{ -- mini red-dot box on top of the scope [CONFIRMED look; never lit and never used: CONFIRMED]
					op = "box", c = { 0, 0.020, 0.1655 }, s = { 0.022, 0.032, 0.027 },
				},
			},
		},
		Mount = {
			Material = "Metal",
			Recipes = {
				-- wide flat mount on the rail [CONFIRMED look "wide flat mount"; sizes PLACEHOLDER]
				{ op = "box", c = { 0, 0.065, 0.0895 }, s = { 0.050, 0.170, 0.016 } },
				{ op = "box", c = { 0, 0.000, 0.1075 }, s = { 0.030, 0.018, 0.022 } },
				{ op = "box", c = { 0, 0.128, 0.1075 }, s = { 0.030, 0.018, 0.022 } },
				{ -- scope rings
					op = "lathe",
					profile = { { -0.009, 0.0170 }, { -0.009, 0.0198 }, { 0.009, 0.0198 }, { 0.009, 0.0170 } },
					segs = 24, cx = 0, cz = 0.135, rx = 1, rz = 1,
				},
				{
					op = "lathe",
					profile = { { 0.119, 0.0170 }, { 0.119, 0.0198 }, { 0.137, 0.0198 }, { 0.137, 0.0170 } },
					segs = 24, cx = 0, cz = 0.135, rx = 1, rz = 1,
				},
			},
		},
	},

	-- Lens presentation (the glass at the eyepiece; the picture itself comes from the scope camera).
	Lens = {
		CanvasPixels = 512, -- render canvas of the lens surface (the lens is ~162 px tall at 720p, ~243 px at 1080p)
		Tint = { 222, 232, 228 }, -- [PLACEHOLDER value; CONFIRMED look] lens picture slightly darker and grey-green
		-- relative to the world (scope.mp4 O7, sniper O11)
		GlassColor = { 24, 30, 30 }, -- [PLACEHOLDER] the glass when no picture is shown (hip): dark grey-green
		GlassTransparency = 0.05,
		Highlight = { -- [CONFIRMED position upper-left of the lens (all four videos); size / strength PLACEHOLDER]
			CentreU = 0.32, CentreV = 0.30, Radius = 0.24, Strength = 0.22,
		},
		RimColor = { 8, 8, 10 }, -- mask outside the round lens (inside the dark eyepiece rim)
		-- Eye box ("scope shadow"): [CONFIRMED behaviour] the lens goes dark from one side when the eye is off the
		-- optical axis (ADS entry / exit, after each shot), clear at rest with a soft dark edge. The numbers are
		-- [PLACEHOLDER]: a point eye at lateral offset d from the axis moves the clear disc by
		-- -d / ExitPupilRadius x ShiftGain lens radii; being nearer / farther than the eye relief shrinks it.
		EyeBox = {
			ExitPupilRadius = 0.0062, -- m [INFERRED] ~56 mm objective / 4.5x / 2
			ShiftGain = 0.55, -- lens radii per exit-pupil radius of lateral offset [PLACEHOLDER]
			DepthTolerance = 0.03, -- m of eye-relief error that shrinks the clear disc by DepthShrink [PLACEHOLDER]
			DepthShrink = 0.30,
			ClearRadius = 1.08, -- lens radii at the ideal eye point: a soft dark edge at the rim [PLACEHOLDER;
			-- CONFIRMED "softly vignetted bright disc"]
			Softness = 0.30, -- edge width as a fraction of the clear radius [PLACEHOLDER]
			MinRadius = 0.15,
		},
		Background = { 150, 186, 214 }, -- [PLACEHOLDER] sky colour behind the mirrored scene (a ViewportFrame does not
		-- render the skybox, atmosphere or clouds)
		Ambient = { 128, 128, 134 }, -- [PLACEHOLDER] lens-picture lighting (a ViewportFrame has one directional light)
		LightColor = { 205, 205, 200 },
	},

	-- Reticle, inside the lens on the optical axis [CONFIRMED family: black bars, red centre, faint red ring].
	-- Sizes are fractions of the visible lens diameter (162 px in the reference).
	Reticle = {
		Bars = { -- [MEASURED, +-2 px] frames 380 / 450: left, right and lower bars from 12 to 29 px off centre, ~2 px thick;
			-- no upper bar seen [CONFIRMED absent in 186 / 380 / 450]
			Inner = 0.074, Outer = 0.179, Thickness = 0.0124,
			Directions = { "Left", "Right", "Down" },
			Color = { 10, 10, 10 }, Alpha = 0.95,
		},
		Dot = { Diameter = 0.019, Color = { 225, 40, 30 }, Alpha = 0.85 }, -- [MEASURED approx 3 px; colour CONFIRMED red]
		Ring = { -- [CONFIRMED faint red ring at this zoom (library O4); radius / gap / strength PLACEHOLDER: too faint to size]
			Radius = 0.055, Thickness = 0.0065, GapDeg = 70, Color = { 225, 40, 30 }, Alpha = 0.30,
		},
		ImagePixels = 512,
	},

	-- Aim transition HIP -> AIMING -> SCOPED and back (Client.Optics.OpticAim). scope.mp4, 30 fps.
	Aim = {
		InTime = 0.14, -- [MEASURED] hip to the eye in 4 frames twice (177 -> 181, 356 -> 360): 0.13 s (+-1 frame)
		InEase = "Smooth", -- [INFERRED] the two entries disagree on the shape (progress per frame 0.1 / 0.1 / 0.83 / 1.0
		-- and 0.38 / 0.87 / 0.93 / 0.98); a smoothstep (0.16 / 0.5 / 0.84 / 1.0) lies between them
		OutTime = 0.15, -- [MEASURED] scope to hip (+330 px): exit 1 drops 10 / 42 / 99 px on frames 109-111 = t^2 over
		-- 5.6 frames (0.19 s); exit 2 drops 7 / 68 / 133 px then reaches the hip on frame 298 (~3.5 frames, 0.12 s); mean
		OutEase = "Accelerate", -- [MEASURED] t^2 (exit 1); the ring keeps its size while it drops (a pure lowering)
		SettleStuds = 0.0033, -- [MEASURED once] the ring arrives 5.4 px low and rises to rest (frames 181 -> 190)
		SettleTime = 0.33, -- [MEASURED once] 10 frames
		-- Hip pose of the scoped rifle, solved from where its eyepiece appears (the borrowed M4 rest pose holds the
		-- receiver at the eye, which would put this scope's eyepiece 7 cm from the eye at the hip).
		HipPose = {
			EyepieceScreen = { 612, 690 }, -- [MEASURED +-15 px] frames 355-356 (part 2, clearest hip frames): the
			-- eyepiece is a large dark disc at the bottom of the screen, rifle seen from behind
			EyepieceWidthPx = 250, -- [MEASURED +-15 px] same frames: only ~6 % farther than scoped (266.5 px), so going
			-- to the scope is a ~6 cm rise; matches the exit, where the ring drops at constant size (frames 109-111)
			FocalPx = 514.15, -- 720 px tall at FOV 70 [INFERRED FOV, as everywhere]
			Level = true, -- [CONFIRMED] not canted (scope.mp4 W5, sniper W4); bore parallel to the view [INFERRED]
		},
	},

	-- Picture-in-picture render layer (Client.Optics.ScopeView / SceneMirror).
	Render = {
		MirrorMaxDistance = 4000, -- studs from the player when a part is first mirrored [PLACEHOLDER]
		MirrorMinSize = 0.05, -- skip parts smaller than this on every axis [PLACEHOLDER]
		BuildPerFrame = 150, -- parts cloned per frame while the mirror is built (no hitch) [implementation]
		StaticChecksPerFrame = 80, -- anchored parts re-checked per live frame for moves / changes [implementation]
	},
}

return table.freeze(ReferenceScope)
