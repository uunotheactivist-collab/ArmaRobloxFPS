# Glock audio: production upload (prepared, NOT done)

**Status:** **BLOCKED BY EXTERNAL REQUIREMENT**, the same situation as the M4, AK and MP7.
- The game plays these files from Studio's local content folder (`rbxasset://sounds/GlockReference/...`, copied there by
  `sync_to_studio.ps1`). That works in Studio on this PC only.
- Nothing has been uploaded. Standing project rule: never upload or publish; the Glock brief also says not to upload
  with credentials and to leave production uploading to the user. Uploading also needs the owner's Roblox account and a
  published experience, since `Place1` is unpublished (PlaceId 0).

Roblox's requirements, checked 2026-11-09, are in `../M4/UPLOAD.md`: mp3 / ogg / wav / flac, under 20 MB and 7 minutes,
up to 48 kHz, mono or stereo, re-encoded to OGG Vorbis on upload. All five Glock files meet them (largest 11.29 MB,
longest 64.0 s, 44.1 kHz stereo 16-bit). Details and hashes: `MANIFEST.md`.

**Glock audio fidelity correction (2026-11-09):** the two shot sprites are now 64 s (variants 1–32 hip, panned 2 dB
right; 33–64 the same variants centred, for aimed shots: `Shot.AimedOffset = 32`). Their hashes changed; the three
reload files did not. Upload the files as they are now — an id for an older 32 s sprite would play hip shots only and
aimed shots would read past its end.

## Exact mapping: where each id goes

Each id goes into `ReplicatedStorage.Shared.Config.Audio.Glock` → `AssetIds["<file name>"] = <id>`. A file with an id
plays as `rbxassetid://<id>`; a file without one keeps the local path (the same code path as the M4, AK and MP7).

| File | Upload as | `AssetIds` key | Used by |
|---|---|---|---|
| `glock_shots_regular.wav` | one audio asset | `"glock_shots_regular.wav"` | `Shot.Sets.Regular` (all 9 voices) |
| `glock_shots_stressed.wav` | one audio asset | `"glock_shots_stressed.wav"` | `Shot.Sets.Stressed` (all 9 voices) |
| `glock_reload_TacticalRegular.wav` | one audio asset | `"glock_reload_TacticalRegular.wav"` | `Reloads.TacticalRegular` |
| `glock_reload_EmptyRegular.wav` | one audio asset | `"glock_reload_EmptyRegular.wav"` | `Reloads.EmptyRegular` (Regular and Stressed empty reloads) |
| `glock_reload_TacticalStressed.wav` | one audio asset | `"glock_reload_TacticalStressed.wav"` | `Reloads.TacticalStressed` |

Example after upload:

```lua
AssetIds = {
	["glock_shots_regular.wav"] = 0, -- replace 0 with the uploaded id
	["glock_shots_stressed.wav"] = 0,
	["glock_reload_TacticalRegular.wav"] = 0,
	["glock_reload_EmptyRegular.wav"] = 0,
	["glock_reload_TacticalStressed.wav"] = 0,
},
```

**Keep every file exactly as it is.** The game finds shot variant k at `(k − 1) × 1.0 s` with `PlaybackRegion` (k = 1–64;
aimed = hip + 32), so the sprites must not be trimmed, padded, resampled or have silence removed. The reloads' leading
silence is the clip alignment (see `MANIFEST.md`). The hearing equaliser is applied in the game (an
`EqualizerSoundEffect` per shot voice), not baked into the files.

## The remaining user steps

1. Publish `Place1` to an experience owned by the account (or group) that will own the audio.
2. Upload the five files above under that account or group: Studio Asset Manager → Import, or Creator Hub → Audio.
3. Put the ids into `Config.Audio.Glock.AssetIds`. Keep the local copies as the fallback.
4. **Check after the upload:**
   1. Run `GlockAudioTest` `Run.assets()` (lengths 64.0 / 2.967 / 3.4 / 2.433 s).
   2. Run `Run.fire("string")`, `Run.fire("ads")`, `Run.fire("stressed")` and `Run.stance()`, which check that each
      shot plays its whole region of the re-encoded sprite (`regionBad` 0, `minLife` ≥ 0.95 s, nothing truncated), the
      hip / aimed region, and that the variants step 1, 2, 3 … 32, 1.
   3. Run `Run.reloads()` and listen to a few single shots, a fast string (hip and aimed) and each reload.

**Not checked:** seeking accuracy inside a Roblox-encoded OGG (now up to 63 s into a sprite); playback in a published
game.
