# MP7 model fidelity — capture harness and results (2026-11-09)

Analysis and every number: `ReferenceAnalysis/Weapons/MP7/Model/MP7_Model_Analysis.md`.

## Files

| File | What |
|---|---|
| `StarterPlayer.StarterPlayerScripts.MP7ModelFidelityTest.Run` (src `Roblox/Scripts/src/StarterPlayer/StarterPlayerScripts/MP7ModelFidelityTest/Run.luau`) | Studio-only harness: `capture(states)`, `status()`, `parts()`. Drives only WeaponController's debug hook (equip, `freeze`, `record`) and the viewmodel parts' `LocalTransparencyModifier`. Delete the folder to remove it |
| `capture_states.ps1` | PrintWindow poller: finds the viewport from the magenta calibration frame, saves `s###_p1..3.png` when the marker shows a state / phase |
| `run_capture.ps1` | runs the poller with Studio in the foreground (an occluded Studio window stops presenting new frames), then gives the foreground back |
| `studio_focus.ps1` | the foreground helper (nothing is typed or clicked) |
| `make_evidence.ps1` | `ReferenceAnalysis/Weapons/MP7/Model/evidence/roblox_reference_before_after.png` |
| `captures/before`, `captures/after` | 36 states × 3 phases each, `viewport_rect.json`, `saved.txt`; `before/poses.json` = the logged camera-relative rig frames (identical with the AFTER model) |

## Protocol

```lua
-- Client datamodel, playtest; start run_capture.ps1 -OutDir <dir> first (in the background)
local Run = require(game.Players.LocalPlayer.PlayerScripts.MP7ModelFidelityTest.Run)
local states = { { id = "REST" } }  -- + { id = "R1_f0125", clip = "TacticalRegular", t = (125 - 60) / 30 }, ...
Run.capture(states, { settleS = 0.5, phaseS = 0.7 })
Run.status()  -- JSON when done: viewport, fov, poses (camera-relative CFrames of Weapon / Magazine / ChargingHandle / LeftArm)
```
State list used: REST and R1 63, 75, 93, 104, 114, 125, 131, 146, 157; R2 293, 305, 320, 340, 355, 360, 385, 410, 417,
428, 436; R3 588, 600, 612, 621, 636, 644; R4 778, 795, 810, 813, 840, 856, 858, 867, 874 (clip t = (frame − start) / 30;
starts 60 / 289 / 582 / 773). Viewport 1452 × 753 (this Studio layout), FOV 70, default place lighting, player at spawn.
Normalisation to the reference: scale 720 / 753, centre crop 1280 (same vertical FOV).

## Results

| Check | BEFORE | AFTER |
|---|---|---|
| Captures saved | 108 / 108 | 108 / 108 |
| Logged poses | — | identical to BEFORE (rest, R2 410, R4 856 charging handle compared to 1e-5) |
| Pipeline: offline render vs Studio capture, visible weapon IoU | reload states 0.84–0.99 (rest 0.80: the in-game arm leaves a thin strip of weapon) | mean 0.971, min 0.835, rest 0.989 (46 states) |
| Viewmodel parts (Studio) | Weapon_Polymer, Weapon_Metal, Magazine_Polymer, ChargingHandle_Metal (MeshParts) + LeftArm (Part), SmoothPlastic, CastShadow false | the same names / classes / materials / colours; sizes Weapon_Metal 0.227 × 0.466 × 1.602, Weapon_Polymer 0.223 × 0.810 × 1.433, Magazine 0.138 × 0.783 × 0.322, ChargingHandle 0.174 × 0.052 × 0.108 studs |
| Console | 0 errors | 0 errors |

**Harness defects found and fixed during the slice (none in production code):** the first poller scanned the window
with `GetPixel` (seconds per pass: missed the 1.6 s calibration) → a compiled scan; captures with Studio behind other
windows showed a stale frame without the viewmodel → `run_capture.ps1` brings Studio to the front.

## Lower-body correction (2026-11-09, analysis §12)

| File | What |
|---|---|
| `captures/after_correction` | the corrected model, same 36 states (108 / 108 PNGs, 97.8 s); `pose_compare.txt` = the logged rig frames vs `captures/before/poses.json` (1,728 values, max difference 7.0e-6 = identical within the file's 1e-5) + the part list; `pose_digest_studio.txt` = per-state digest |
| `make_evidence_correction.ps1` | `ReferenceAnalysis/Weapons/MP7/Model/Correction/evidence/roblox_reference_before_after_lower.png`: reference / BEFORE / AFTER Studio captures, lower-body crops at full scale |

Pipeline (offline render vs Studio, `50_mp7_metrics.py --pipe-min-bg 0.35`): raw mean 0.966 (min 0.802); within 15 px of
the silhouette 0.973 (BEFORE run 0.975). The raw minimum is an ENVIRONMENT effect of that session: a large white object
behind the viewmodel at the bottom of the view (present with the viewmodel hidden, constant across states) moved slightly
between the capture phases, so its edges entered the phase difference (near-hip states R1/R2/R3/R4_FINAL, R1_CANTED).
The geometry-only lower-body comparison is `55_mp7_lower_fit.py` (free poses, clean lower-body truth).

**Full regression after the correction (2026-11-09, background agent, one playtest):** no REAL REGRESSION; listing 154 /
`11028:3541121999` before and after; 0 game-code errors; MP7 41 / 41 ×3, reloads 3.270 / 4.940 / 2.113 / 3.403 s, muzzle
on screen unchanged (677.1, 494.6). The session ran throttled to 60 fps (ENVIRONMENT: MP7 climb 4.038–4.097°, ADS in
0.258–0.268 s, all frame times) and someone used the play window for 48 s (BodyState forged check passed on the third
run). Uncapped MP7 afterwards: idle 5.19 / fire 5.36 ms. Details: analysis §12.9 and the correction checkpoint's
`_tests/regression_mp7_model_fidelity_correction.md`.

**Full regression (2026-11-09, background agent, one playtest):** no REAL REGRESSION; MP7 suite all pass (41 / 41 ×3,
climb 4.13°, ADS 0.252 / 0.148 s, reloads 3.269 / 4.939 / 2.102 / 3.403 s, forged set identical, muzzle effects on the
new Points.Muzzle); MP7 frame time idle 4.75 / fire 5.02 ms uncapped (no measurable cost); 0 game-code errors. Details:
`ReferenceAnalysis/Weapons/MP7/Model/MP7_Model_Analysis.md` §8.
