# M4 audio: production upload (prepared, NOT done)

**Status:** **BLOCKED BY EXTERNAL REQUIREMENT.**
- The game plays these files from Studio's local content folder (`rbxasset://sounds/M4Reference/...`, copied there by
  `sync_to_studio.ps1`). That works in Studio on this PC only; a published game cannot play them.
- Nothing has been uploaded. The project's standing rule is "never upload or publish". Uploading also needs the owner's
  Roblox account, and `Place1` is unpublished (PlaceId 0). In earlier sessions the Studio MCP asset permissions
  (`asset:read` / `asset:write`) never showed as granted for it.

## What Roblox requires (checked 2026-11-09)

Roblox's [Audio assets](https://create.roblox.com/docs/audio/assets) page and the Open Cloud
[assets usage guide](https://create.roblox.com/docs/cloud/guides/usage-assets) say:

| Requirement | Roblox's figure | These files |
|---|---|---|
| Format | mp3, ogg, wav or flac | wav, 16-bit PCM |
| Size per file | under 20 MB | 0.54–6.84 MB |
| Length per file | under 7 minutes | 3.07–77.5 s |
| Sample rate | up to 48 kHz | 44.1 kHz |
| Channels | mono or stereo | shot sprites mono, reloads stereo |

- **Processing:** Roblox resamples uploads and converts them to OGG Vorbis. The game hears the re-encoded version: the
  waveforms change slightly, and the level and the regions do not.
- **Monthly upload quotas:** the two pages differ (100 / 10 per month in the Open Cloud guide; 2,000 / 100 per 30 days in
  the Studio page, ID-verified / not). Six files fit every figure.
- **Moderation:** uploads are moderated.
- **Permissions:** an audio asset is usable in experiences of the account (or group) that owns it, or ones it grants.

## Files and where their ids go

All six are in this folder. Each uploaded id goes into `Shared.Config.Audio.M4` →
`AssetIds["<file name>"] = <id>`. A file with an id plays as `rbxassetid://<id>`; a file without one keeps the local
path, so the files can be switched over one at a time.

| File | Ch | Length | Bytes | SHA-256 | Used as |
|---|---|---|---|---|---|
| `m4_shots_regular.wav` | 1 | 77.500 s | 6,835,544 | `F3917FCE5390717E952F95C256C85944D757F21E2CE9E30B743C4EA61A60DADA` | 31 shot variants × 2.5 s (Regular) |
| `m4_shots_stressed.wav` | 1 | 77.500 s | 6,835,544 | `6D1AA99F93AD3816FF94465E6DF92562E1881C3FC5B505A677056C4510270708` | 31 shot variants × 2.5 s (Stressed) |
| `m4_reload_TacticalRegular.wav` | 2 | 3.5333 s | 623,320 | `229558CC399C92296FAF941305AB402C77C3DA610AA141BE270428648395A9BE` | Tactical Regular reload |
| `m4_reload_EmptyRegular.wav` | 2 | 3.7000 s | 652,724 | `2CF1EE6F5E011AC69FF4F4966F753E99A9BF32CDE01E92EC4BD8C2E3F18BB7D0` | Empty Regular reload |
| `m4_reload_TacticalStressed.wav` | 2 | 3.0667 s | 541,008 | `5BB2587E16861EC2533668B0BDC23C68E36AF26B2A2077092909D14B71C24B68` | Tactical Stressed reload |
| `m4_reload_EmptyStressed.wav` | 2 | 3.6000 s | 635,084 | `8D2C746DC4CDF7A0228CD4A67B2172CC1F5C7D9900C94EB5B71DC3DC309A9AD5` | Empty Stressed reload |

Keep the sprites exactly as they are. The game finds variant k at `(k - 1) × 2.5 s` with `PlaybackRegion`, so the file
must not be trimmed, padded, or have silence removed.

## The remaining user steps

1. Publish `Place1` to an experience owned by the account (or group) that will own the audio. Until then, uploaded ids
   cannot be granted to it.
2. Upload the six files from this folder: Studio Asset Manager → Import, or Creator Hub → Creations → Audio, under that
   account or group.
3. Put the ids into `ReplicatedStorage.Shared.Config.Audio.M4` (`AssetIds`). Keep the local copies as the fallback.
4. **Check after the upload:**
   1. Run `M4AudioTest` `Run.assets()` (the lengths must still be 77.5 / 3.533 / 3.7 / 3.067 / 3.6 s).
   2. Run `Run.fire("sustained")`, which checks that each shot plays inside its region of the re-encoded sprite.
   3. Listen to one burst.

## Checked in this environment, without uploading

- **The id path:** a temporary probe config with ids for two files (removed afterwards). Those files resolved to
  `rbxassetid://<id>`; the other six kept `rbxasset://sounds/M4Reference/<file>`. Weapons without audio stayed silent.
- **`PlaybackRegion` on a long local WAV:** played from 10.0 to 10.3 s, then stopped by itself.

**Not checked:**
- seeking accuracy inside a Roblox-encoded OGG;
- playback in a published game.
