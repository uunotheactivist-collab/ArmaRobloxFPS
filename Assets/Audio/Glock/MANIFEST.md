# Glock audio assets — manifest

Built by `ReferenceAnalysis/Weapons/Glock/Audio/tools/build_sounds.py` from the audio track of
`Reference/Weapons/Glock/glock animation.mp4` (SHA-256 `64D0E6B3…FA98`). Analysis:
`ReferenceAnalysis/Weapons/Glock/Glock_Audio_Analysis.md` (Part 5 = the fidelity correction). Measured and checked by
`tools/check_assets.py` → `data/assets.json` (same folder as the tools; every check passes).

**Glock audio fidelity correction (2026-11-09):** the shot sprites hold every variant twice — 1–32 hip (panned 2 dB
right, as before), 33–64 the same variant centred (aimed shots; `Config.Audio.Glock` `Shot.AimedOffset = 32`). Their
length doubled to 64 s and their hashes changed. The reload files are unchanged (same hashes as the
`2026-11-09_glock_audio_fidelity` checkpoint). The hearing equaliser is applied in the game, not baked into any file.

All files: PCM WAV, 44.1 kHz, 16-bit, stereo, 0 clipped samples, DC offset < 6·10⁻⁵, one shared gain (+20 dB over the
recording), so `Volume = 0.1` plays them at the recording's own level. Loudness below is at Volume 0.1 (momentary max /
integrated, LUFS). Rebuilding with `build_sounds.py` reproduces all five files byte for byte (checked 2026-11-09).

| File | Purpose | Duration | Bytes | Peak | Loudness (Vol 0.1) | L − R | SHA-256 |
|---|---|---|---|---|---|---|---|
| `glock_shots_regular.wav` | 64 slots × 1.0 s (sprite; slot k at (k − 1) s, `PlaybackRegion`): variants 1–32 hip, 33–64 the same centred; Regular | 64.000 s | 11,289,644 | −2.89 dBFS | −40.93 / −44.57 | hip heads −2.00 dB, aimed 0.00 dB | `E24B4FA7671BE9168C048DAEA29CFA27D0CEC2F46AE1C417244BD3893311DDFE` |
| `glock_shots_stressed.wav` | the same 64 slots, Stressed (−0.5 dB) | 64.000 s | 11,289,644 | −3.39 dBFS | −41.43 / −45.07 | hip heads −2.00 dB, aimed 0.00 dB | `769C00AA2B5A0ED596D953B8290271500B9E4F1BAE4BFD5505CB54235936ADF1` |
| `glock_reload_TacticalRegular.wav` | Tactical Regular reload (clip frames 46–135) | 2.9667 s | 523,368 | −8.23 dBFS | −49.55 / −52.73 | −3.90 dB | `A9D6CE255EAFBA859BF5256E6C9450C285D2E0176C12AA6FD21655DD98E9872A` |
| `glock_reload_EmptyRegular.wav` | Empty Regular reload (frames 283–385); also the Stressed empty reload (placeholder clip) | 3.4000 s | 599,804 | −5.10 dBFS | −45.56 / −50.00 | −2.47 dB | `1D44CA45D1E43EE0174E6250F76BD5C4A16474039D293FED08F3A4F7F7146CCE` |
| `glock_reload_TacticalStressed.wav` | Tactical Stressed reload (frames 404–477), high-passed (heartbeat) | 2.4333 s | 429,280 | −14.48 dBFS | −55.51 / −57.97 | −2.50 dB | `30622B8C5727FA53B2A6A18A1E51B2FDB51159855CD8E8AAAF2FCF262D6A7F3A` |
| `sync_to_studio.ps1` | copies the WAVs into Studio's `content\sounds\GlockReference` (local playback) | | 2,160 | | | | `3879C036B2B12E8514EADF8267FB957E6E5A39902266D92C51A698B79AEA96FE` |

**Stance pairs (checked):** slot k and slot k + 32 carry the same signal — their mid (L + R) / 2 differs by at most
1 LSB (1.5·10⁻⁵); the aimed slots have no side signal (−138 dB against the hip slots'). Hip heads (first 60 ms,
> 1 kHz) measure L − R −2.00 dB in all 32 slots, aimed heads 0.00 dB.

**Silence and padding (intended, keep it):**
- **Shot sprites:** each 1.0 s slot holds a variant of about 0.80 s (2 ms fade-in at the recording's true start, 80 ms
  fade-out); the last 0.2 s of each slot is silence (checked: ≥ 0.15 s in all 64 slots). Nothing leads (0 s).
- **Reloads:** the leading silence (0.19 / 0.68 / 0.44 s) is the clip alignment — each file is its clip's span from the
  clip's first frame, so its first event lands where the reference has it. Do not trim.

**Shot sprite order:** position k = the k-th shot of the reference (frames 12, 28, 163, 189 … 557), i.e. its recording
(0 = shot 12, 1 = shot 28, 2 = shot 163) at its measured playback speed; no recording occurs twice in a row, the wrap
32 → 1 included (checked). The sequence with speeds is in `ReferenceAnalysis/Weapons/Glock/Audio/data/build.json`.

**Upload status:** nothing uploaded. See `UPLOAD.md`.
