# M4 model fidelity tests (2026-11-08)

> The latest results are in **"Correction pass"** at the end. The sections before it record the first (WIP) pass.

The checks for the M4 model fidelity slice. The slice changed only the M4's visual asset:
- `Shared.Assets.Weapons.M4ViewmodelData`: Blender meshes as `"mesh"` recipes;
- `Shared.Viewmodel.ProceduralMesh`: the `"mesh"` op.

Record: `ReferenceAnalysis/Weapons/M4/M4_Model_Analysis.md`.

## Files and hooks
- **`M4ModelFidelityTest.Run.client-module.luau`** is a copy of `StarterPlayer.StarterPlayerScripts.M4ModelFidelityTest.Run`.
  - It runs on the client only and uses WeaponController's Studio-only `ProductionWeaponDebug` hook.
  - To remove it, delete the `M4ModelFidelityTest` folder.
- **The test import** (before the live module was replaced) was run once from the Edit datamodel. Its recipe is under
  "Test import" below and in `Documentation/Pipeline_Blender_to_Roblox.md` §8.

## How to run (one playtest, Client datamodel)
```lua
local Run = require(game.Players.LocalPlayer.PlayerScripts.M4ModelFidelityTest.Run)
Run.model()  Run.fit()  Run.hands()  Run.muzzle()  Run.perf()
Run.fire()   Run.reloads()   Run.switching()
Run.respawn("before")  -- then on the Server: game.Players:GetPlayers()[1].Character.Humanoid.Health = 0
Run.respawn("after")
```
Keep each `execute_luau` batch under about 60 s: `reloads()` takes about 20 s.

## Test import (Edit datamodel, before replacing the live M4)

**Setup.**
- The generated module was placed in `ServerStorage._M4HDImport.M4ViewmodelData`.
  - It was pasted through the clipboard; the hash `211774:47558098` equals the local file.
- `ProceduralMesh` and `ViewmodelRig` were loaded as fresh clones, because the plugin's `require` cache held the
  previous ProceduralMesh.
- The rig was built into `Workspace._M4ModelImportTest`.

| Check | Result |
|---|---|
| Joints, Poses, ADSIn, Camera, PartOrigins equal the accepted data | yes |
| Points equal the accepted data (except Muzzle, SightGlass) | yes. Muzzle y −1.7 → −1.42857 studs; SightGlass z −0.108929 → −0.007143 |
| Per part: MeshPart, size and centre vs the decoded mesh (< 0.002 studs) | 9 / 9 |
| Per part: triangle counts, colours, bones | 9 / 9 |
| Orientation: muzzle ahead of the sight; optic above the magazine | yes |
| Driven by the viewmodel system: the ADS pose puts SightGlass on the view axis | (−0.0001, 0, −0.6007) studs |
| Driven by the viewmodel system: a Weapon transform moves the parts | yes |
| Build time, whole rig, Edit | 60.9 ms |
| Visual check (edit-time capture) | correct shapes and materials |

**Result.** All checks passed. Only then was the live module replaced; hash parity was verified.

## Results (final scripts, playtest)

| Test | Result | Pass |
|---|---|---|
| `model()` | 10 parts = 10 specs; every mesh part is a MeshPart from `"mesh"` recipes; size error 0 (rebuilt independently); colours and materials match; 10,230 triangles | ✔ |
| `fit()` | Hip front post 0.064 below centre (accepted 0.065 ± 0.02). ADS sight glass and front post at (0.500, 0.500). ADS hood top 0.121 above centre (reference 0.1225). ADS FOV 62.233 | ✔ |
| `hands()` | Hand to grip: hip 0.139, ADS 0.070 studs (the accepted rig: 0.039 / 0.020 m). The ADS-in transition peaks at 0.207 (a rig property, reported only) | ✔ |
| `muzzle()` | The Muzzle point sits on the device axis (0, 0); 0.030 m ahead of the grey device, at the end of the 30 mm cap | ✔ |
| `fire()` | 8 shots: server magazine 30 → 22, server Accepted +8, Rejected +0, client 8. The viewmodel moved 0.16 studs (recoil) | ✔ |
| `reloads()` | Tactical Regular 3.538 s, Empty Regular 3.704 s, Tactical Stressed 3.071 s, Empty Stressed 3.601 s (config 3.5333 / 3.7 / 3.0667 / 3.6). Magazine moved 1.54–1.79 studs and returned to 0.000. The charging handle moved 0.214 studs in the empty reloads only. The `Magazine_Metal` feed end drifted 0.000 from the tan body. Parts 10 → 10 | ✔ |
| `switching()` | M4 → AK → M4 → TestBlaster → M4: exactly one viewmodel each time, at most one M4 model | ✔ |
| `respawn()` | After death and respawn: one M4 viewmodel, the same model, 10 parts, one M4 model anywhere | ✔ |
| `perf()` | Client build of the whole viewmodel: 54.5 / 56.3 / 55.2 ms (Studio). Frame 4.71 ms at the hip, 4.75 ms in ADS | ✔ |

The first run of `fire()` and `hands()` failed on the test itself:
- `fire()` read the ammo from the wrong debug command. The server's ammo comes from `state` after a `sync`, as
  M4FiringTest reads it.
- `hands()` used a 0.2-stud limit over the whole ADS transition.

Both were corrected (the hold values are compared with the accepted rig; the transition is reported) and both pass.
The console showed 0 errors in both playtests.

## Visual (in game)

**ADS.**
- The tunnel opening and the window.
- The dot on the front post (co-witness).
- The lower body with the X relief, corner bolts and pins.
- The charging-handle tongue below.

**Hip.** The sight, seen from behind and below.

**Before / after against the reference frames.** `ReferenceAnalysis/Weapons/M4/ModelFidelity/compare/`, numbers in
`M4_Model_Analysis.md` §3.1.

**Weapon switching.** It is not in the reference video, so it was checked in game only (`switching()`).

## Final rerun (after restoring the accepted near-black colours)

The data's only change after the regression was three colour lines: Metal / Polymer / Optic went back to the accepted
(34,34,37) / (27,27,29) / (36,37,40). The final hash is `211774:3207763271`.

| Check | Result |
|---|---|
| `model()` | Pass; every colour and material matches; 10 parts; 10,230 triangles |
| `fit()` | Pass; same numbers as above |
| Scoped test rifle (borrows the M4 body) | Builds 10 parts: no holo parts, scope parts present. Normal at the hip. Its optics suite passed in the regression |
| Console | 0 errors |

## M4 security (forged requests; the model is presentation only)

**The server never reads the viewmodel data.** Nothing in `ServerScriptService.Server` reads `M4ViewmodelData` or its
points. The client sends the camera position as the shot origin, not the muzzle, so moving the muzzle point cannot
change validation.

**Legitimate M4 fire: every shot accepted, 0 rejected.**
- Hip: single +1, burst +13, magazine / stressed / stop / reset +73, range taps +3, range burst +16.
- ADS: 31-shot aimed magazine +31, taps +3, burst +16.
- After respawn: +4.

**Forged requests:**

| Request | Accepted / rejected |
|---|---|
| Bad origin / direction | 0 / 1 |
| Wrong or unknown weapon | 0 / 1 |
| Bad types | 0 / 1 |
| Fake hit | 1 / 0: a plain shot traced from the server's head into the floor, 0 damage |
| Origin at the moved muzzle | 1 / 0, traced from the server's head |
| 12 in one frame | 3 / 9 |
| Sustained over the rate | 17 / 16 |
| Ammo / ReloadDone / ReloadSwapped messages | Ignored |
| Instant reload | 0 / 3 ("reloading"); the reload then completed normally |
| Empty shot | 0 / 1 |
| Reload on a full magazine | Ignored |

There was no earlier M4 forged suite, so these numbers have no baseline. They follow the MP7 / Glock pattern.

## Full regression

One fresh playtest, all suites, Grenade suites last, run by a background agent. The baseline is
`Roblox/Tests/Truck/README.md` "Full regression".

| Area | Result | vs baseline |
|---|---|---|
| M4 | 770 RPM, 0 rejected; recovery 0.75 / 0.770 s; de-cant −32.575° → 0.066°; ADS 0.333 / 0.334 in, 0.119 / 0.122 out (uncapped frame rate); reloads 3.533 / 3.061 / 3.700 / 3.595 s; extras pass; HUD 13 / 0 | within spread |
| AK | 640 RPM, climb 1.234 / 1.942°, raise 0.128 / lower 0.283–0.287 s, reloads 2.433 / 1.655 / 3.133 / 2.762 s, label 1.069 s | within spread |
| MP7 | 41 / 41 ×3, climb 4.050–4.189°, ADS 0.256 / 0.160, reloads 3.278 / 4.945 / 2.105 / 3.415 s, forged as before | within spread |
| Glock | 16 / 16, reload 3.411 s (swap 2.177, slide 2.654), forged set as its README | same (±1 frame) |
| Sniper | eject 0.705, next shot 1.567 s, tactical 4.180 s, zoom restores 6x, forged set as its README | same |
| Optics (ScopeTest borrows the M4 body) | in 0.147 / 0.141, out 0.164 / 0.167 s, magnification 4.500, tracking 0.894 / 1.110°, 0 remotes scoped | within spread (out about one frame later) |
| Movement | rules 25 / 25, walk 5.600, crouch 2.800 / eye 2.70, jump +7.532, lag 5.954 / 7.391°, roll 1.399 / 2.699°, death / respawn as before | same |
| FirstPerson | all pass; first frames back L+10 (M4, AK, MP7, Sniper) / L+11 (Glock). At L+12: M4 0.80 / 0.73 (baseline 0.93), AK 0.92, MP7 0.64, Glock 0.90, Sniper 0.74 / 0.68 | **M4 L+12 lower: a metric effect, see below.** One Sniper flake (passed twice on rerun) |
| BodyState / Ballistics / Hit reactions / Blood | 42 / 42, 6 / 6, 6 / 6; 10 / 10 per lane, 18 / 18; 6 / 6, 6 / 6, 11 / 11, tamper; 14 / 14, 14 / 14, dead hit, world, security, orphans | same |
| Body interaction | pulse 3.011–3.020 s, drag 9.06 studs, trail 11 (10 placed), "too far" 0.752 s, orphans (known WalkSpeed 5.6) | within spread |
| Death / respawn | interrupted pulse; AK reload cancelled after the swap; respawn 3.276–3.35 s; grenade before death detonates once (4.0015 s) | within spread |
| AI | 14 / 14, 8 / 8, 11 / 11, 10 / 10; player as target 6 / 7, then 7 / 7 on rerun; 5 / 5, 6 / 6, security 10 / 10 | same pattern (known P2 timing flake) |
| M4AnimTest | 481 / 484 plays at 3.529–3.544 s (start hitch 5.479, 3.569, 3.764 during a death) | same pattern |
| GrenadeTest | fuse 4.0004–4.0046 s ×17, release +0.150–0.155 s, wall / lob / steep / room as before, forged refused, server-owned | within spread |
| Grenade among bodies | 41 fragments into bodies | within spread |
| GrenadeFidelity | presentation identical; `heldAtReleaseFrames` 6; label 1.405 / 0.194 s; red edge as before | within spread |
| Truck | all 10 tests pass; 11 forged refused; production-rule refusals as before | within spread |
| Performance | Client frame 4.68 / 4.67 ms on foot with the M4; M4 hip 4.50–4.66, ADS 4.95 / 4.75; AK hip 4.84 / ADS 4.89; heartbeat 4.69 ms | +0.4–0.5 ms vs 4.16 / 4.27, but for every weapon and the server heartbeat alike, late in a long session (Studio memory 2.9 GB). The M4 is not costlier than the AK |

**FirstPerson M4 at L+12.**
- The test scores how much of the weapon is in view by counting the bounding-box corners of the viewmodel's parts
  inside the picture, relative to rest.
- The new model has a different part set: 10 boxes, 43 corners in view at rest.
- In the final playtest at L+12, the lowering amount (WeaponLowering, independent of the model) was 0.08 for the M4 and
  0.08 for the AK, with the first pixels back at L+10 for both.
- The M4 scored 0.75, the AK 0.92 (AK unchanged from the baseline).
- So the weapon moves exactly as before; only the corner count of the new boxes differs. The check (≥ 0.5 by L+12)
  passes.

**Not run:**
- the FirstPerson latency rows (the baseline didn't run them either);
- an M4 death during a reload;
- a real two-player test.

**Console:**
- 0 game-code errors (server log and Studio log file read).
- 166 expected forged-request warnings.
- Studio-internal "Wrap-deformer" warnings at respawns; they predate this slice.

**Known M4 Stressed (unchanged, report-only):** sway roll 2.068°, reload end pose 2.891° tactical / 2.694° empty.
Earlier runs gave 2.924 / 2.505 / 2.268°; the values keep varying.

## Correction pass (2026-11-08, later) — ACCEPTED

**Accepted (2026-11-08)** as the current M4 model-fidelity baseline (checkpoint
`2026-11-08_m4_model_fidelity_correction`). The results below are the accepted test record: M4 tests, security and full
regression passed, with 0 game-code errors.

Record: `ReferenceAnalysis/Weapons/M4/M4_Model_Analysis.md` Part 5.

### Changes in Studio
| Script | What changed | Hash |
|---|---|---|
| `Shared.Assets.Weapons.M4ViewmodelData` | Mesh (+ recessed sight section), calibrated hip rest / ADS / ADS-in keys with LeftArm keys | `216806:4053907683` |
| `Shared.Assets.Weapons.M4ReloadAnimations` | Weapon tracks re-expressed for the new rest | `41111:85608878` |
| `Client.AimController` | Arm keys when every ADS-in key carries one (additive) | `6000:335789808` |

The test module is unchanged (`16009:1484301127`).

### Test import (Edit datamodel, before replacing the live modules)
Both generated modules were pasted into `ServerStorage._M4HDImport` and hash-checked. They were built with fresh clones of
ProceduralMesh, ViewmodelRig and ClipPlayer.

| Check | Result |
|---|---|
| Weapon C0 = the calibrated rest | yes |
| LeftArm / Magazine / ChargingHandle joints, Points, PartOrigins, Camera, ADS LeftArm | unchanged |
| ADS-in keys | 7 (T 0, 163, 165, 166, 167, 168, ADS), each with a LeftArm key |
| Part sizes and centres vs the decoded meshes | 9 / 9 within 0.002 studs |
| Triangle counts | 9 / 9 |
| ADS camera-space shift vs accepted | (0.0062, −0.0037, −0.0001) studs = the fitted 1.75 mm / −1.0 mm |
| Reload clips: camera-space Weapon path inside each clip | identical (≤ 0.00008 studs) for all four |
| Reload clips: start and end at the rest pose | yes |
| Reload clips: lengths, events, every other joint | byte-identical |
| Reload clips: end-blend offset | ≤ 0.053 studs |
| Build time | 64.2 ms |

### M4 model tests (playtest, final scripts)
| Test | Result | Pass |
|---|---|---|
| `model()` | 10 parts, all MeshParts from `"mesh"` recipes, size error 0, colours and materials match, 10,466 triangles | ✔ |
| `fit()` | Hip front post 0.070 below centre (reference 0.067). ADS sight glass (0.504, 0.505), front post (0.502, 0.502). Hood top 0.115 above centre. FOV 62.233 | ✔ |
| `hands()` | Hip 0.121, ADS 0.066 studs. ADS-in transition peak **0.119** (was 0.207) | ✔ |
| `muzzle()` | On the device axis, 0.030 m ahead of the grey device | ✔ |
| `fire()` | 8 shots: server magazine 30 → 22, Accepted +8, Rejected 0. Viewmodel kick 0.146 studs | ✔ |
| `reloads()` | 3.536 / 3.704 / 3.070 / 3.604 s. Magazine moved 1.54–1.79 studs and returned to 0. Charging handle moved 0.214 studs in the empty reloads only. Feed end drift 0. Parts 10 → 10 | ✔ |
| `switching()` | One viewmodel each step, at most one M4 model | ✔ |
| `respawn()` | One M4 viewmodel, 10 parts | ✔ |
| `perf()` | Build 55.5–57.4 ms. Frame 4.69 ms at the hip, 4.58 ms in ADS | ✔ |

Console: 0 errors.

### First-person visibility (grenade-throw lowering)
| | L+10 | L+11 | L+12 | L+13 | First back |
|---|---|---|---|---|---|
| FirstPersonTest corner score, M4 final | 0.05 | 0.43 | **0.79** | 0.98 | L+10 |
| … AK, same run | 0.15 | 0.69 | 0.92 | 1.00 | L+10 |
| … M4 pre-slice (baseline) | — | — | 0.93 | — | L+10 |
| … M4 WIP | 0.05 | 0.42 | 0.75 (0.80 / 0.73 in the regression) | 0.96 | L+10 |
| Pixel fraction (`47_m4_visibility.py`): pre-slice / WIP / final | 0.009 / 0 / 0 | 0.183 / 0.159 / 0.160 | **0.651 / 0.621 / 0.613** | 0.944 / 0.933 / 0.923 | — |

The lowering amount is identical for every weapon (0.37, 0.18, 0.08, 0.02 at L+10 to L+13). The corner score depends on the
part split: the M4 has 10 boxes and 42 corners in view at rest, the AK 26. In pixels, the final M4 is 0.04 below the
pre-slice model at L+12, because the calibrated hip pose sits lower and farther, as the reference hip frames show.

### M4 security (correction pass; forged requests, Accepted / Rejected)

**Legitimate fire (all accepted, 0 rejected):**
- hip taps 5 / 5;
- hip burst 16 / 16;
- ADS taps 5 / 5;
- ADS burst 16 / 16;
- ADS full magazine 31 / 31.

**Forged requests:**

| Request | Accepted / rejected |
|---|---|
| Far / wall origin, behind, NaN, ±inf origin, zero, bad types, wrong weapon, unknown, equipUnknown | 0 / 1 each |
| Fake hit | 1 / 0: a plain shot traced from the server head, 0 damage |
| Origin at the muzzle point | 1 / 0, traced from the server head |
| 12 in one frame | 3 / 9 |
| Sustained (33 shots) | 16 / 17 |
| SetAmmo / ReloadDone / ReloadSwapped | Ignored |
| Instant reload | 0 / 3 ("reloading") |
| Empty shot | 0 / 1 |
| Reload on a full magazine | Ignored |
| Malformed WeaponFire × 12 | 1 / 11 |

**The accepted malformed request.** A 1e9-long direction was normalised by the server and traced from its own head, with
0 damage.

**Pre-existing behaviour, not changed.** An `Equip` command with a malformed argument (42 or `{"M4"}`) cancels the
sender's own running reload ("weapon switched"). The server's weapon stays M4.

The server never reads the viewmodel data. The model and poses are presentation only.

### Full regression (correction pass; one fresh playtest, Grenade suites last, background agent)

| Area | Result | vs baseline |
|---|---|---|
| M4 | 770 RPM, 0 rejected; recoveries 0.74 / 0.759 s; ADS in 0.332 / 0.331, out 0.120 / 0.119 (~230 fps); reloads 3.531 / 3.065 / 3.697 / 3.596 s; HUD 13 / 0; extras pass (second short playtest, see note) | same, except the idle de-cant start **−32.597°** (was −32.575°): the calibrated rest has 0.02° more cant |
| AK | 640 RPM, climb 1.239 / 1.952°, raise 0.127 / 0.290, reloads 2.428 / 1.667 / 3.131 / 2.751 s, label 1.067 s | within spread |
| MP7 | 41 / 41 × 3, climb 4.150–4.174°, ADS 0.266 / 0.150, reloads 3.274 / 4.951 / 2.116 / 3.415 s, forged as before | within spread |
| Glock | 16 / 16, reload 3.407 s (swap 2.175, slide 2.654), forged as its README | same |
| Sniper | eject 0.703, next shot 1.567 s, tactical 4.182 s, zoom 6x, forged as its README | same |
| Optics (ScopeTest borrows the M4 data) | in 0.142 / 0.141, out 0.158 / 0.150 (60 fps), magnification 4.497, tracking 0.894 / 1.110°, 0 remotes scoped | within spread |
| Movement | rules 25 / 25, walk 5.600, crouch 2.800 / eye 2.70, jump +7.529, lag 5.948 / 7.386° (−0.005°), roll 1.399 / 2.699° | lag −0.005° (cause not separated: frame rate or the new rest) |
| FirstPerson | all pass. L+12 / first back: M4 0.75 and 0.80 / L+10, AK 0.92 / L+10, MP7 0.57 / L+11, Glock 0.93 / L+11, Sniper 0.68 / L+10. Security as before | within spread (the M4 corner score is explained above) |
| BodyState / Ballistics / Hit reactions / Blood | 42 / 42, 6 / 6, 6 / 6; 10 / 10 per lane, 18 / 18; 6 / 6, 6 / 6, 11 / 11, tamper; 14 / 14, 14 / 14, dead hit, world, security, orphans | same |
| Body interaction | pulse 3.014–3.018 s, drag 9.11 studs, trail 12 (11 placed), "too far" 0.751 s | within spread |
| Death / respawn | interrupted pulse; AK reload cancelled after the swap; respawn 3.29–3.39 s; a grenade before death detonates once (4.0011 s) | within spread |
| AI | 14 / 14, 8 / 8, 11 / 11, 10 / 10, 7 / 7, 5 / 5, 6 / 6, security 10 / 10 | same |
| M4AnimTest | 440 / 441 at 3.529–3.545 s (start hitch 5.462) | same pattern |
| GrenadeTest | fuse 4.0002–4.0044 s × 18, release 0.148–0.152 s, forged refused, server-owned | within spread |
| Grenade among bodies | 32, rerun 43 | within spread |
| GrenadeFidelity | presentation identical, `heldAtReleaseFrames` 7, label 1.400 / 0.197 s | within spread |
| Truck | 10 / 10; 11 forged refused; production-rule refusals (one "out of range" read 15.9 studs vs 17.5; still refused) | within spread |
| Other weapons' security | MP7, Glock, Sniper, Optics forged sets as their READMEs | same |
| Performance (~230 fps) | M4 hip 4.38 ms, ADS 4.36 ms; AK hip 4.38, ADS 4.31; on foot 4.43 ms; heartbeat 4.42 ms | between the Truck baseline and the last run; the M4 costs no more than the AK |

**Notes.**
- **Frame rate.** Studio drew at 60 fps for the first part of the playtest, then at ~230 fps. The 60 fps readings
  (M4 ADS-out 0.133 s, empty Regular reload 3.685 s) are one-frame quantisation; rerun at ~230 fps they match.
- **M4 reload extras.** They were run in a second short fresh playtest: all pass, console clean.
- **Not run:**
  - the FirstPerson latency rows (as in the baselines);
  - the Truck prompt's per-frame µs cost;
  - an M4 death mid-reload;
  - a real two-player test.

**Console:**
- Server: 1,364 messages, 0 errors, 177 expected forged-request warnings.
- Studio log: 0 game-code errors. The 5 Studio-internal lines at play start are a secrets parse and HTTP 403s from the
  chat / social APIs, plus the known "Wrap-deformer" warnings at spawns.

**Known M4 Stressed (report only):**
- Sway roll: 2.166° at 60 fps, 3.498° at ~230 fps.
- Reload end pose: 1.812 / 2.411° at 60 fps, 3.724 / 4.027° at ~230 fps.
- These values keep varying run to run, as before.