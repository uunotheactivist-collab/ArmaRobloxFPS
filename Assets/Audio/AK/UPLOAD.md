# AK audio: production upload (prepared, NOT done)

**Status:** **BLOCKED BY EXTERNAL REQUIREMENT**, the same situation as the M4.
- The game plays these files from Studio's local content folder (`rbxasset://sounds/AKReference/...`, copied there by
  `sync_to_studio.ps1`). That works in Studio on this PC only.
- Nothing has been uploaded. Standing project rule: never upload or publish. Uploading also needs the owner's Roblox
  account and a published experience, since `Place1` is unpublished (PlaceId 0).

Roblox's requirements, checked 2026-11-09, are in `../M4/UPLOAD.md`: mp3 / ogg / wav / flac, under 20 MB and 7 minutes,
up to 48 kHz, mono or stereo, re-encoded to OGG Vorbis on upload. All six AK files meet them.

## Files and where their ids go

Each id goes into `ReplicatedStorage.Shared.Config.Audio.AK` → `AssetIds["<file name>"] = <id>`. A file with an id
plays as `rbxassetid://<id>`; a file without one keeps the local path. This uses the same code path as the M4, verified
with a probe config in the M4 correction pass.

| File | Ch | Length | Bytes | SHA-256 | Used as |
|---|---|---|---|---|---|
| `ak_shots_regular.wav` | 1 | 31.000 s | 2,734,244 | `A7974E4636F04E93A56C57C49F665DF364EFA506968D90E8108E5D970BE09CD6` | 31 shot variants × 1.0 s (Regular) |
| `ak_shots_stressed.wav` | 1 | 31.000 s | 2,734,244 | `D665E895DEA2A44DA0E8AAB295AE1D0D49D3CC255626FFF30A0BF19D16354ABF` | 31 shot variants × 1.0 s (Stressed) |
| `ak_reload_TacticalRegular.wav` | 2 | 2.4333 s | 429,280 | `6CA60544A07B8D8B8B38FE2573FCC0B1330762FE5EF68E61D4330ABEEC0C6D7B` | Tactical Regular reload |
| `ak_reload_EmptyRegular.wav` | 2 | 3.1333 s | 552,760 | `9F836B796065A7A604FF6212FB0E5C4BCB4F3B7DE4996E81EE65B50DE74B8FBD` | Empty Regular reload |
| `ak_reload_TacticalStressed.wav` | 2 | 1.6667 s | 294,048 | `E8F4151A5D6F624367B865B135961CB0D7B7C0E194E1556F054CCA216379F9BA` | Tactical Stressed reload |
| `ak_reload_EmptyStressed.wav` | 2 | 2.7667 s | 488,088 | `E3F3BAA7B690C8F2F53D32E381BC940AE40EB0DA5B96F01BC7CD500BC7C74193` | Empty Stressed reload |

Keep the sprites exactly as they are. The game finds variant k at `(k - 1) × 1.0 s` with `PlaybackRegion`, so the file
must not be trimmed, padded, or have silence removed. Each variant's last 0.15 s fades to silence, and the space after it
is intentional.

## The remaining user steps

1. Publish `Place1` to an experience owned by the account (or group) that will own the audio.
2. Upload the six files above under that account or group: Studio Asset Manager → Import, or Creator Hub → Audio.
3. Put the ids into `Config.Audio.AK.AssetIds`. Keep the local copies as the fallback.
4. **Check after the upload:**
   1. Run `AKAudioTest` `Run.assets()` (lengths 31.0 / 2.433 / 3.133 / 1.667 / 2.767 s).
   2. Run `Run.fire("sustained")`, which checks that each shot plays inside its region of the re-encoded sprite.
   3. Listen to one burst and one reload.

**Not checked:**
- seeking accuracy inside a Roblox-encoded OGG;
- playback in a published game.
