--!strict
-- AK audio (AK audio fidelity slice, ReferenceAnalysis/Weapons/AK/AK_Audio_Analysis.md). Presentation only, read by
-- Client.WeaponAudio exactly like Config.Audio.M4 (same fields; no AK-specific code anywhere).
-- Every file is cut from the reference recording (Reference/Weapons/AK/ak animation.mp4) by
-- ReferenceAnalysis/Weapons/AK/Audio/tools/build_sounds.py into Roblox/Assets/Audio/AK.
-- Delivery: AssetIds[file] when set (an uploaded Roblox audio asset, rbxassetid://), otherwise the local Studio content
-- copy rbxasset://sounds/<Folder>/<file> made by Roblox/Assets/Audio/AK/sync_to_studio.ps1 [local Studio playback only
-- until the files are uploaded: Roblox/Assets/Audio/AK/UPLOAD.md].
return {
	Folder = "AKReference",
	AssetIds = {} :: { [string]: number }, -- file name -> uploaded audio asset id (nothing uploaded)
	-- Level: every file carries +20 dB over the recording, so Volume 0.1 plays the AK at the recording's own level
	-- (first-shot peak -25.9 dBFS, a 31-round burst -37.8 LUFS momentary max / -38.0 integrated) [MEASURED; the same
	-- convention as the M4, whose 0.1 the user kept]. One factor for every AK sound keeps their relative levels.
	Volume = 0.1,
	Shot = {
		-- One voice: each shot stops the previous shot's sound. The level is flat over the burst from the first shot
		-- (no build-up), and after the last shot the level holds for one period, then falls [MEASURED].
		-- The k-th shot of a burst plays variant k of its set: the reference burst's own k-th shot (its period up to
		-- the next shot, then the burst's recorded tail). Every reference shot is a different waveform [MEASURED].
		-- Each set is one sprite file: variant k at (k - 1) * VariantLength s, played with PlaybackRegion.
		Sets = {
			Regular = { File = "ak_shots_regular.wav", Count = 31, VariantLength = 1.0 }, -- B2: Regular, raised, 31 rounds
			-- B4: Stressed, raised (30 tracked + 1 wrapped into its plateau). Its plateau equals Regular's within 0.4 dB;
			-- its first shot is 14-24 dB darker above 4 kHz [MEASURED]
			Stressed = { File = "ak_shots_stressed.wav", Count = 31, VariantLength = 1.0 },
		},
		PlateauFrom = 8,
		-- A shot continues the burst when it comes exactly one fire interval after the previous shot (the automatic
		-- cycle); any later shot starts a new burst. Every reference burst starts from silence [quick re-press: UNKNOWN].
		CycleTolerance = 0.001,
	},
	-- By clip name (Config.Weapons.AK.Reloads.*.Clip): the recording of that clip's span from its start frame for its
	-- exact length, only its AK events kept, so the sound lines up with the animation as in the reference [MEASURED].
	Reloads = {
		TacticalRegular = "ak_reload_TacticalRegular.wav",
		TacticalStressed = "ak_reload_TacticalStressed.wav",
		EmptyRegular = "ak_reload_EmptyRegular.wav",
		EmptyStressed = "ak_reload_EmptyStressed.wav",
	},
}
