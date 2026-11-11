--!strict
-- M4 audio (M4 audio fidelity slice + correction pass, ReferenceAnalysis/Weapons/M4/M4_Audio_Analysis.md). Presentation
-- only, read by Client.WeaponAudio; a weapon without a module here has no sound at all (no generic fallback).
-- Every file is cut from the reference recording (Reference/Weapons/M4/m4 animation.mp4) by
-- ReferenceAnalysis/Weapons/M4/Audio/tools/build_sounds_v2.py into Roblox/Assets/Audio/M4.
-- Delivery: AssetIds[file] when set (an uploaded Roblox audio asset, rbxassetid://), otherwise the local Studio content
-- copy rbxasset://sounds/<Folder>/<file> made by Roblox/Assets/Audio/M4/sync_to_studio.ps1 [local Studio playback only
-- until the files are uploaded: Roblox/Assets/Audio/M4/UPLOAD.md].
return {
	Folder = "M4Reference",
	AssetIds = {} :: { [string]: number }, -- file name -> uploaded audio asset id (nothing uploaded)
	-- Level: every file carries +20 dB over the recording (16-bit headroom), so Volume 0.1 (= -20 dB, Sound.Volume taken
	-- as a linear amplitude factor) plays the M4 at the recording's own level: first-shot peak -23.6 dBFS, a 31-round
	-- burst -40.1 LUFS momentary max [MEASURED in the reference capture; the capture chain's own gain is not known, so this
	-- assumes a unity-gain capture]. One factor for every M4 sound keeps their measured relative levels.
	Volume = 0.1,
	Shot = {
		-- One voice: each shot stops the previous shot's sound (the reference's tail after 3 and 31 shots is the same
		-- level, and the level between shots is that tail's) [MEASURED].
		-- The k-th shot of a burst plays variant k of its set: the reference burst's own k-th shot (its period up to the
		-- next shot, then the recorded continuation / tail). This carries the measured burst envelope (shots 1-4 9-14 dB
		-- over the plateau, 5-7 2-6 dB over it, flat from 8 with 2.4 dB SD) and the shot-to-shot variation (every
		-- reference shot is a different waveform) [MEASURED]. Each set is one sprite file: variant k at
		-- (k - 1) * VariantLength s, played with PlaybackRegion.
		Sets = {
			Regular = { File = "m4_shots_regular.wav", Count = 31, VariantLength = 2.5 }, -- the ADS burst, 31 rounds
			-- Stressed hip B: 29 tracked shots + 2 wrapped into its plateau; darker above 4 kHz [MEASURED]; its low band
			-- (heartbeat) replaced by the Regular one [INFERRED]
			Stressed = { File = "m4_shots_stressed.wav", Count = 31, VariantLength = 2.5 },
		},
		-- positions past Count continue from PlateauFrom (the flat part of the envelope), in order
		PlateauFrom = 8,
		-- A shot continues the burst when it comes exactly one fire interval after the previous shot (FireController's
		-- automatic cycle: trigger held, or pressed again before the next cycle); any later shot starts a new burst at
		-- position 1. Every reference burst starts from silence [the rule for a quick re-press is UNKNOWN in the footage].
		CycleTolerance = 0.001,
	},
	-- By clip name (Config.Weapons.M4.Reloads.*.Clip): the recording of that clip's own span (the clip's exact length),
	-- only its M4 events kept, so the sound lines up with the animation as in the reference [MEASURED]. Starts with the
	-- clip, stops when the reload is cancelled.
	Reloads = {
		TacticalRegular = "m4_reload_TacticalRegular.wav",
		TacticalStressed = "m4_reload_TacticalStressed.wav",
		EmptyRegular = "m4_reload_EmptyRegular.wav",
		EmptyStressed = "m4_reload_EmptyStressed.wav",
	},
}
