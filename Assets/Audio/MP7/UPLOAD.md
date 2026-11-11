# MP7 audio: production upload (prepared, NOT done)

**Status:** **BLOCKED BY EXTERNAL REQUIREMENT**, the same situation as the M4 and the AK.
- The game plays these files from Studio's local content folder (`rbxasset://sounds/MP7Reference/...`, copied there by
  `sync_to_studio.ps1`). That works in Studio on this PC only.
- Nothing has been uploaded. Standing project rule: never upload or publish; the MP7 brief also says not to upload with
  credentials or external accounts unless explicitly authorised. Uploading also needs the owner's Roblox account and a
  published experience, since `Place1` is unpublished (PlaceId 0).

Roblox's requirements, checked 2026-11-09, are in `../M4/UPLOAD.md`: mp3 / ogg / wav / flac, under 20 MB and 7 minutes,
up to 48 kHz, mono or stereo, re-encoded to OGG Vorbis on upload. All six MP7 files meet them (largest 9.04 MB, longest
51.25 s, 44.1 kHz stereo 16-bit).

## Files and where their ids go

Each id goes into `ReplicatedStorage.Shared.Config.Audio.MP7` → `AssetIds["<file name>"] = <id>`. A file with an id
plays as `rbxassetid://<id>`; a file without one keeps the local path. This is the same code path as the M4 and the AK
(verified with a probe config in the M4 correction pass).

| File | Ch | Length | Bytes | SHA-256 | Used as |
|---|---|---|---|---|---|
| `mp7_shots_regular.wav` | 2 | 51.250 s | 9,040,544 | `33D8082C777244658E605562184DD29457CB437AA3B1239EACC4287B680DC517` | 41 shot variants × 1.25 s (Regular) |
| `mp7_shots_stressed.wav` | 2 | 51.250 s | 9,040,544 | `D196D965C64A3027A20E68882259D7371B8E6333D27DA01BEC5B59702C5791CD` | 41 shot variants × 1.25 s (Stressed) |
| `mp7_reload_TacticalRegular.wav` | 2 | 3.2667 s | 576,288 | `F918E17367E36B34F424AAFFE180A3CCE261619BD6B56FD58BBACEF0B087AE2D` | Tactical Regular reload |
| `mp7_reload_EmptyRegular.wav` | 2 | 4.9333 s | 870,280 | `1525A9BE2D4A91949E36F6801BAB4B1C01026064AFE843C11DD90B352EB78E11` | Empty Regular reload |
| `mp7_reload_TacticalStressed.wav` | 2 | 2.1 s | 370,484 | `57135CD65951E5EDAB05551780061B735B3FED7D25F1DA13FCEB51910F565CFE` | Tactical Stressed reload |
| `mp7_reload_EmptyStressed.wav` | 2 | 3.4 s | 599,804 | `30A5B5D1BAF1D2C3C708FDD7F973741F7B2364F63D0ADDD82776DBB147C1CEFE` | Empty Stressed reload |

**Keep every file exactly as it is.**
- **Shot sprites:** the game finds variant k at `(k − 1) × 1.25 s` with `PlaybackRegion`, so the file must not be
  trimmed, padded, resampled or have silence removed. Each variant's last 0.15 s fades to silence; the space after it is
  intentional. 1.25 s was chosen because it is exact in binary: `PlaybackRegion` is single precision, and with 1.3 s
  some regions came out up to 3 µs off their variant.
- **Reloads:** each file is its reload clip's span from the clip's first frame, so the silence before the first event
  (up to 1.1 s) is the clip alignment, not padding. Do not trim it, or the sound will run ahead of the animation.

## The remaining user steps

1. Publish `Place1` to an experience owned by the account (or group) that will own the audio.
2. Upload the six files above under that account or group: Studio Asset Manager → Import, or Creator Hub → Audio.
3. Put the ids into `Config.Audio.MP7.AssetIds`. Keep the local copies as the fallback.
4. **Check after the upload:**
   1. Run `MP7AudioTest` `Run.assets()` (lengths 51.25 / 3.267 / 4.933 / 2.1 / 3.4 s).
   2. Run `Run.fire("sustained")` and `Run.fire("stressed")`, which check that each shot plays inside its region of the
      re-encoded sprite (`regionBad` 0).
   3. Run `Run.reloads()` and listen to one burst and one reload of each state.

**Not checked:**
- seeking accuracy inside a Roblox-encoded OGG (the 1.25 s regions are exact for the WAV; OGG seek granularity is
  unknown);
- playback in a published game.
