--!strict
-- Glock audio (Glock audio fidelity slice + correction, ReferenceAnalysis/Weapons/Glock/Glock_Audio_Analysis.md).
-- Presentation only, read by Client.WeaponAudio like Config.Audio.M4 / AK / MP7. The correction uses three OPTIONAL
-- WeaponAudio capabilities that only this config enables (Shot.Overlap, Shot.AimedOffset, Hearing); the M4 / AK / MP7
-- configs do not set them and keep their behaviour. No Glock-specific code anywhere.
-- Every file is cut from the reference recording (Reference/Weapons/Glock/glock animation.mp4) by
-- ReferenceAnalysis/Weapons/Glock/Audio/tools/build_sounds.py into Roblox/Assets/Audio/Glock.
-- Delivery: AssetIds[file] when set (an uploaded Roblox audio asset, rbxassetid://), otherwise the local Studio content
-- copy rbxasset://sounds/<Folder>/<file> made by Roblox/Assets/Audio/Glock/sync_to_studio.ps1 [local Studio playback only
-- until the files are uploaded: Roblox/Assets/Audio/Glock/UPLOAD.md].
return {
	Folder = "GlockReference",
	AssetIds = {} :: { [string]: number }, -- file name -> uploaded audio asset id (nothing uploaded)
	-- Level: every file carries +20 dB over the recording, so Volume 0.1 plays the Glock at the recording's own level
	-- [MEASURED; the convention the user kept for the M4]. One factor for every Glock sound keeps their relative levels.
	Volume = 0.1,
	Shot = {
		-- The reference plays one of THREE shot recordings per shot, never the same one twice in a row (31 of 31), at a
		-- playback speed within +-2.6 % [MEASURED]; the shots are not tied to a burst position (a semi-automatic pistol:
		-- every press is its own shot). So the sprite holds the reference's own 32 shots in order - each one its
		-- recording at its measured speed - and the shots step through them: the next shot plays the next variant,
		-- whatever the time since the last one, and after 32 it starts again at 1 (no recording repeats twice in a row,
		-- across the wrap too). A put-down (switch, death, respawn) restarts at 1. 1.0 s slots are exact in float32.
		-- OVERLAP: the reference's shots overlap - each keeps playing under the next ones, up to 5 at once in its strings
		-- [MEASURED]. Every shot is its own voice (a fixed pool of ceil(1.0 / (60 / 450)) + 1 = 9 per set, reused only
		-- after 1.2 s at the fastest legal cadence, i.e. after its 1.0 s region has ended).
		Overlap = true,
		-- STEREO: hip shots 2 dB right, aimed shots centred [MEASURED, analysis Part 4 / correction]. The sprites hold
		-- the 32 variants twice: 1-32 hip (panned), 33-64 the same variants centred; a shot fired aimed (aim blend >= 0.5)
		-- plays its variant + AimedOffset. A shot keeps the stance it was fired in for its whole tail.
		AimedOffset = 32,
		Sets = {
			Regular = { File = "glock_shots_regular.wav", Count = 32, VariantLength = 1.0 },
			-- Stressed: the same recordings and spectrum, -0.5 dB [MEASURED]
			Stressed = { File = "glock_shots_stressed.wav", Count = 32, VariantLength = 1.0 },
		},
		PlateauFrom = 1, -- past position 32 the cycle continues from position 1
		CycleTolerance = math.huge, -- every shot continues the cycle (only a put-down restarts it)
	},
	-- HEARING [INFERRED presentation model, fitted to the reference: data/hearing_fit.json, family F1]: the reference
	-- dulls its shot sounds as the firing goes on (8-16 kHz of a string's later shots down ~6-8 dB against an isolated
	-- shot) and recovers within ~4 s of the last shot; the stress onset muffles everything sharply (-30 dB above 4 kHz)
	-- and recovers within ~3 s. Every shot voice carries an equaliser (Low < 400 Hz, Mid, High > 4 kHz):
	--   history h(t) = sum over the OTHER shots j started Delay or more before t of exp(-(t - t_j - Delay) / Release)
	--   x = 1 - exp(-h / Saturation);  gains = Gains * x  +  StressOnset.Gains * exp(-(t - onset) / StressOnset.Decay)
	-- Fit: calibration RMS 1.22 dB (3.22 without the model), held-out 1.46 dB (4.94 without).
	Hearing = {
		Delay = 0.1, -- s: a shot starts to count 0.1 s after its own start
		Release = 1.5, -- s
		Saturation = 3.0,
		Gains = { Low = -0.84, Mid = -3.52, High = -7.72 }, -- dB at full saturation
		-- the player's Stressed attribute turning on (the reference's stress cut, shot 394)
		StressOnset = { Gains = { Low = 0, Mid = -9, High = -30 }, Decay = 0.9 },
	},
	-- By clip name (Config.Weapons.Glock.Reloads.*.Clip): the recording of that clip's span from its start frame for its
	-- exact length, only its Glock events kept, so the sound lines up with the animation as in the reference [MEASURED].
	-- They are not equalised by Hearing: they already carry the reference's own dulling of their moment.
	-- The Stressed empty reload plays the EmptyRegular clip (placeholder, no footage) and therefore its sound.
	Reloads = {
		TacticalRegular = "glock_reload_TacticalRegular.wav",
		EmptyRegular = "glock_reload_EmptyRegular.wav",
		TacticalStressed = "glock_reload_TacticalStressed.wav",
	},
}
