--!strict
-- MP7 audio (MP7 audio fidelity slice, ReferenceAnalysis/Weapons/MP7/MP7_Audio_Analysis.md). Presentation only, read by
-- Client.WeaponAudio exactly like Config.Audio.M4 / AK (same fields; no MP7-specific code anywhere).
-- Every file is cut from the reference recording (Reference/Weapons/MP7/mp7 animation.mp4) by
-- ReferenceAnalysis/Weapons/MP7/Audio/tools/build_sounds.py into Roblox/Assets/Audio/MP7.
-- Delivery: AssetIds[file] when set (an uploaded Roblox audio asset, rbxassetid://), otherwise the local Studio content
-- copy rbxasset://sounds/<Folder>/<file> made by Roblox/Assets/Audio/MP7/sync_to_studio.ps1 [local Studio playback only
-- until the files are uploaded: Roblox/Assets/Audio/MP7/UPLOAD.md].
return {
	Folder = "MP7Reference",
	AssetIds = {} :: { [string]: number }, -- file name -> uploaded audio asset id (nothing uploaded)
	-- Level: every file carries +20 dB over the recording, so Volume 0.1 plays the MP7 at the recording's own level
	-- [MEASURED; the convention the user kept for the M4]. One factor for every MP7 sound keeps their relative levels.
	Volume = 0.1,
	Shot = {
		-- One voice: each shot stops the previous shot's sound (no level build-up; after the last shot the level holds
		-- for one period, then falls) [MEASURED].
		-- The k-th shot of a burst plays variant k of its set: the reference burst's own k-th shot (its period up to the
		-- next shot, then the burst's recorded tail), STEREO: the Regular shots are panned 2 dB right, the Stressed ones
		-- centred [MEASURED]. Every reference shot is a different waveform [MEASURED].
		-- Each set is one sprite file: variant k at (k - 1) * VariantLength s, played with PlaybackRegion. 1.25 s is exact in
		-- binary (PlaybackRegion's NumberRange is single precision: 1.3 s regions came out up to 3 us off).
		Sets = {
			-- B: Regular, 41 rounds (40 tracked + 1 wrapped into its plateau); first period +4.3 dB, flat from shot 8
			Regular = { File = "mp7_shots_regular.wav", Count = 41, VariantLength = 1.25 },
			-- D: Stressed, 41 rounds (39 tracked + 2 wrapped); shots 1-6 loud (+16 ... +7 dB), then a quiet, dark plateau
			-- (-9.5 dB, -8 dB at 1-4 kHz, -17 dB at 8-16 kHz) [MEASURED]
			Stressed = { File = "mp7_shots_stressed.wav", Count = 41, VariantLength = 1.25 },
		},
		PlateauFrom = 8,
		-- A shot continues the burst when it comes exactly one fire interval after the previous shot (the automatic
		-- cycle); any later shot starts a new burst. Every reference burst starts from silence [quick re-press: UNKNOWN].
		CycleTolerance = 0.001,
	},
	-- By clip name (Config.Weapons.MP7.Reloads.*.Clip): the recording of that clip's span from its start frame for its
	-- exact length, only its MP7 events kept, so the sound lines up with the animation as in the reference [MEASURED].
	Reloads = {
		TacticalRegular = "mp7_reload_TacticalRegular.wav",
		TacticalStressed = "mp7_reload_TacticalStressed.wav",
		EmptyRegular = "mp7_reload_EmptyRegular.wav",
		EmptyStressed = "mp7_reload_EmptyStressed.wav",
	},
}
