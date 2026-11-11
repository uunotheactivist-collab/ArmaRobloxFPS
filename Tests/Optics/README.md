# Optics test (scoped-optics slice, 2026-11-07)

Tests for the optics framework and its first optic, the scope of `scope.mp4`, on the scoped test rifle
(`Config.Weapons.ScopeTest`, key 4). Reference and decisions: `ReferenceAnalysis/Optics/Optics_Analysis.md`.

## Pieces

| Piece | Where | Purpose |
|---|---|---|
| Range | `Workspace.OpticsTest` (built by `build_range.luau`) | firing point F = (0, 0, 400) facing +Z; bots OPT_NEAR (25 studs), OPT_MEDIUM (100), OPT_COVER (160, behind a 4.2-stud wall), OPT_DISTANT (300); scale boards at 50 / 150 / 400 studs whose red and blue markers subtend the same 0.04 rad from F; black AlignWall with a sharp corner at (20, 14, 650); low reference posts on a 30-stud arc (±10–30°); far checker board at 550 studs |
| Server test | `ServerScriptService.OpticsTest.Run` (copy `OpticsTest_Server_Run.luau`) | placement at F, fresh bots, the server's own traces (`Ballistics.RecentResults`), Body* attributes, blood counts, client → server traffic counter, remote inventory |
| Client test | `StarterPlayerScripts.OpticsTest.Run` (copy `OpticsTest_Client_Run.luau`) | equip, lens geometry, transitions, scoped tracking (turn / walk / crouch / jump / fall), arm attachment, firing, forged shots, cost |
| Marker tool | `markers.py` (Blender, headless) | red / blue marker blobs in viewport captures: rendered magnification |
| Captures | `captures/` | hip pose, scoped boards at 50 / 150 / 400 studs, scoped bot (arm before the grip-point fix), reticle alignment (`align_corner_zoom4.png`), outside-the-scope diff pair |

Debug hook used: `ProductionWeaponDebug("optic", "ScopeTest")` (read-only optic state) plus the existing `record` log, which now
also carries `opticState`, `opticLive`, `lensCF`, `scopeCF`, `scopeFov`, `shadow`, `opticMs`, `mirrorMs`.

## Running

```lua
-- Server
local S = require(game.ServerScriptService.OpticsTest.Run)
S.place()  S.spawnBots()  S.clearShots()  S.shots()  S.botState("OPT_COVER")  S.blood()
S.netStart()  S.netStop()  S.remotes()
-- Client
local C = require(game.Players.LocalPlayer.PlayerScripts.OpticsTest.Run)
C.equip("ScopeTest")  C.look(point)  C.lens()  C.transition(0.8, 0.5)  C.attach()
C.track({ rate = 20, seconds = 1.5 })  C.track({ move = Vector3.new(0, 0, 1), seconds = 2 })  C.track({ crouch = true })
C.track({ jump = true })  C.fire(3, 1.0, true)  C.forge("farOrigin" | "fakeHit" | "behind" | "nan" | "rate" | "wrongWeapon" | "opticArgs")
C.perf(4, true)
```
Rendered magnification: aim the scope at a scale board, capture the viewport (`Roblox/Tests/M4_Reload/capture_viewport.ps1`),
run `markers.py` on the capture, divide the lens marker spacing by the unscoped spacing (`camera:WorldToViewportPoint` of the
two markers: the hip view's Neon bloom shrinks the red marker's blob, so the engine projection is the hip reference).

## Results (fresh playtests, final scripts, viewport 1452 × 753 → sizes also given at the reference's 720 p)

### Optics (20 required tests)

| # | Test | Result |
|---|---|---|
| 1 | Optic equips | key 4 / `EquippedWeapon = "ScopeTest"`: one viewmodel with `Optic_Body`, `Optic_Mount`, `Optic_Lens`; optic active, HIP, lens layer enabled with the dark glass shown and no picture; server: equipped `ScopeTest`, 20 + 1; FOV 70; HUD enabled ("[TAB] 7.62 MAG", hidden until a magazine is discarded, as the M4 rule) |
| 2 | Optic unequips | to M4 / AK: optic inactive, lens layer disabled, picture hidden, mirror not synced; M4 ADS FOV still 62.233 and 70 after; AK 70; back to the scope: active again |
| 3 | Hip → aim | HIP → AIMING (first frame) → **SCOPED at 0.143 s** (reference 0.13 s ± 1 frame); per 30 fps frame the lens rises 320 → 278 → 186 → 79 → 9 → 5 px (720 p) with the ring 250 → 266 px; settle 0.007 H → 0 over 0.33 s; FOV 70 throughout |
| 4 | Aim → hip | SCOPED → AIMING → **HIP at 0.152 s** (reference 0.12–0.19 s); drop per frame +16 / +60 / +144 / +247 / +320 px at near-constant ring size (reference exit 1: +10 / +42 / +99 px …, exit 2: +7 / +68 / +133 px …) |
| 5 | Lens appears correctly | scoped: lens 162.4 px and ring 266.4 px at 720 p (reference 162 / 267.7), centred (0.0 px), picture + reticle visible, glass hidden, ScopeCamera ≠ the player's camera, Adornee = the lens part; captures `scoped_board*.png` |
| 6 | Magnification | **rendered**: marker spacing in the lens / unscoped spacing = **4.509 (50 studs), 4.513 (150), 4.515 (400)**; geometric 4.500; reference 4.29–4.63 (mean 4.49). **Outside the lens** the hip and scoped captures (same camera) are identical: mean |Δ| 0.002, max 3.7 levels, 0 pixels > 10 over 608 531 pixels |
| 7 | Reticle alignment | the reticle dot sits at the lens centre and on the camera axis (axis and lens centre on screen within 0.3 px). Aimed 0.6 studs off the AlignWall corner at 250 studs: the corner appears at (−4.64, +6.49) lens px from the dot against (−5.76, +5.79) predicted (engine projection × 4.5): within 1.3 lens px = 0.03°. Board midpoints fall 0.25 px from the dot |
| 8 | Scope camera tracks the main camera | scoped turns: scope axis vs camera max **0.894° at 20 °/s, 1.110° at 60 °/s** (= the accepted ADS weapon lag, 7.4° × 0.15), back to 0.00–0.02°; scope camera on the eye (offset < 0.001 stud); its up vector within 0.02° of the camera's; lens centre within 0.011–0.014 H of the screen centre during the turn, 0 after; FOV 70; the player's camera never becomes the ScopeCamera |
| 9 | Movement compatibility | walking scoped: 5.72 studs/s over 0.25 s windows (walk 5.6, movement authoritative), scope vs camera ≤ 0.152° (walk bob), lens ≤ 0.002 H; jump scoped: eye 4.05 → 11.58 (apex +7.53, unchanged), lens live and centred; fall off the 6-stud ledge scoped: eye 10.05 → 4.05 at 5.73 studs/s, lens live and centred |
| 10 | Crouch compatibility | crouch scoped: eye 2.70 (crouch eye), lens centred, scope on the axis; stand again: IDLE, WalkSpeed 5.6, eye 4.05 |
| 11 | Camera roll compatibility | roll 1.399° at 20 °/s and 2.682° at 60 °/s (movement slice: 1.394 / 2.689); the scope image rolls with the camera (up vectors within 0.02°) |
| 12 | Weapon recoil compatibility | 3 scoped shots: climb 0.7° per first shot (the accepted M4 values: 0.30 + 0.40), recovered between shots; lens kick on the shot frame: ring ×1.31–1.40 (reference ×1.3–1.4), lens up 32–53 px (reference ≈110), back at rest after 0.196–0.198 s (reference 0.17–0.23 s); eye-box shadow on the shot frame: clear disc shifted (0.73, 0.23) lens radii and shrunk to 0.84 (crescent), clear again by 0.3 s. **Mismatch:** the borrowed M4 spring overshoots (×1.34 → 0.92 → 1.08) |
| 13 | Firing through the optic | semi-automatic: 3 presses → 3 shots, 3 accepted, 0 rejected; magazine 20 → 17 |
| 14 | Ballistic validation | the server traced each shot from **its own head** (−0.056, 4.203, 400.05) along the camera-centre direction (−0.15829, 0.01150, 0.98733) = the camera look through the reticle; impact on the 150-stud board 0.08 studs from the aim point (0.03°, head-to-eye offset) |
| 15 | Hit location | scoped head shot over the cover wall: `head` / Brain on OPT_COVER (the bullet first went through OPT_NEAR's head in the line of fire, as the accepted penetration does); scoped chest shot on OPT_MEDIUM: `chest` / Lung |
| 16 | BodyState | OPT_COVER ALIVE → DYING → DEAD (life 0, LIMP); OPT_MEDIUM ALIVE → INJURED (Lung, standing) — all from the server's BodyState |
| 17 | Blood | after the two shots: marks 8 → 11, drops 6 → 8, splats 2 → 3, pools 2, stains 4 → 6 (server blood) |
| 18 | Death | killed while scoped: last logged frame SCOPED 0.013 s after the kill; while dead the optic is inactive, lens layer disabled, picture hidden, no viewmodel, FOV 70 |
| 19 | Respawn | 3.31 s later: HIP, lens off, FOV 70, 20 + 1; scoping works at once (162.4 px, centred, 4.5×); the new local character is not copied into the lens (0 copies) |
| 20 | Security | see below |

**Arm attachment:** the left arm's hand end stays on the handguard grip in HIP, AIMING and SCOPED frames: max 0.00003 studs
(243 frames). **Framework (reflex kind):** a throw-away "Reflex" definition on a test rig puts the dot along the optic axis
at infinity (0.0000°) for a centred eye, an offset eye and a weapon kicked 2°, and hides it when the eye is outside the window.

### Security

| Attempt (scoped test rifle equipped) | Server result |
|---|---|
| Shot origin 40 studs from the head ("from the scope's view") | rejected |
| Extra arguments: a hit position, a target part, "Head", with a downward direction | accepted as a plain shot only: traced from the server head straight down into the firing pad; the named target was not hit |
| Extra table `{ scopeCamera, magnification = 99 }` | ignored: an ordinary shot along the camera direction |
| Direction behind the shooter | rejected |
| NaN direction | rejected |
| `AK` while the scope rifle is equipped | rejected (not equipped) |
| 6 shots in one frame | 3 accepted (burst allowance), 3 rejected (cap 600 RPM) |
| Remotes | 12 before and after: the optic adds no remote; the optic state, scope camera and magnification exist only on the client |
| Lens copies | anchored, CanCollide / CanQuery / CanTouch false, outside the Workspace (inside a ViewportFrame): invisible to the server, raycasts and physics |
| Network while scoped | 0 client → server remote events during 6.3 s of scoping in / out and a 2 s scoped sweep (client send 0.57 kbps, character replication) |

### Full regressions (one fresh playtest, final scripts, client-teleport allowance on; recipes in each suite's README)

| Area | Result |
|---|---|
| BodyState | unit 42 / 42; real shots M4 6 / 6, AK 6 / 6; forged requests rejected (INJURED, health 100, the server's own leg hit) |
| Ballistics | unit 10 / 10 per lane for both rifles (budgets 1.75 / 1.249 / 2.0, end z 91 / 91 / 131); real shots 18 / 18 (drops A 6, B 6, C 0) |
| Hit reactions / ragdoll | M4 6 / 6, AK 6 / 6; dying states (synthetic) 11 / 11 (crawl 0.60 studs/s); tamper pass |
| Blood | M4 14 / 14, AK 14 / 14; dead hit (DEAD, effect, no bleed); world (4 entries / 4 exits / 24 non-penetrable); security pass; orphans pass |
| Body interaction | pulse 3.010–3.017 s ("strong, rapid" alive; "No pulse" REACT5, REACT4 after bleeding out, REACT6 on the second check); too far / invalid / interrupt 1.756 s / forged / local state as before; death during a check → "Interrupted (player dead)"; drags 9.05–9.10 studs at WalkSpeed 9, 5.6 restored; trails 10–14 smears; "too far" 0.758 s; refusals; "already held"; tamper (marks 49 → 49, 0 client-owned parts); orphans 0 of each, **but the check's hard-coded `WalkSpeed == 16` reads 5.6** (known since the movement slice) |
| AK | equip; hip burst 640 RPM, climb 1.228°; raised 0.127 / 0.286 s, FOV 70; magazine 31 at 640 RPM, climb 1.943 / 1.945°; reloads 2.429 / 1.664 / 3.133 / 2.761 s, label 1.067 s; label sequence, refusals, switch, repeated pass |
| M4 | 29 + 1; hip burst 770 RPM; ADS magazine 31 at 770 RPM; recovery **0.77 s on the first run, 0.742 s on the rerun** (baseline 0.739–0.743; earlier READMEs 0.739–0.775: run-to-run noise); hip recovery 0.74 s; de-cant −32.575° → −0.057°; stop 0 late shots; reset 27 = 27; reloads 3.528 / 3.063 / 3.700 / 3.595 s; Stressed sway roll 3.105 / 3.408 / 3.500 / 3.209° (known to vary) |
| M4 HUD | 13 checks, 0 mismatches; label at 1.704 / 1.736 / 1.600 s; "+1", "+2" |
| Death / respawn | killed 2.0007 s into an AK empty reload: "cancelled (died) after the magazine change"; respawn 3.385 s (server) / 3.43 s (client); M4 HUD agrees (30, chambered); M4 fires |
| Original reload test | M4AnimTest runner 3.529–3.542 s (the first play of a session includes loading: 5.12 s, as recorded before) |
| AI | perception 14 / 14, aiming 8 / 8, firing 11 / 11, integration 10 / 10; player as target 7 / 7 (first attempt 6 / 7: P1 timing race, the bot acquired 12 ms before the client's own move timestamp; one rerun with a setup error by the tester; correct rerun 7 / 7: acquired 0.104 s after the move, reaction 0.603 s, lost after 0.31 s, reacquire 0.503 s); bot shoots player 5 / 5; M4 takedown 6 / 6; security 10 / 10 |
| Movement | rules 25 / 25; spawn STAND / IDLE, 5.6 / 7.2, eye 4.050, FOV 70; walk 5.600 studs/s (63 % at 0.105 s, 90 % 0.233 s); crouch confirmed 0.022 s, eye 2.700 at 0.25 s, 2.80 studs/s, toast 0.017 / 1.551 / 1.814 s; jump +7.532 at 0.276 s; roll 1.399° (20 °/s), −2.699° (60 °/s); weapon lag 5.953° / 7.392° hip, 0.894° / **1.111°** aiming; arm ≤ 0.0001 studs; death DEAD / 0 / 0, crouch refused; respawn 3.290 s, walk 5.600 |
| Grenade (last) | fuse 4.0001–4.0044 s over 11 (Grenade README accepts 4.0000–4.0047); release 0.149–0.153 s, 55 studs/s; wall 374 / 221, lob 302 / 298, steep 307 / 292, room 553 / 38; timing 0.317 s refused / 0.471 s accepted; "NO FRAGS LEFT"; body REACT3 DEAD (Brain, 8 hits, 10 stains — fragment directions are random); forged 10 refusals; 3 in a row, no leftover parts; player health 100 |
| Console | 0 errors from game code (server and client); warnings only the AI security test's expected rejections. Studio caps the log, so the first third of the long session was not retained; a final short fresh playtest (scope, shots, M4 ADS) printed no error or warning |

**Separate, not changed (as instructed):** the M4 Stressed reload end-pose discrepancy is still there (1.585° tactical,
4.017° empty this run).

## Performance (Studio, uncapped ≈220 fps)

| Case | Mean frame | p95 | Optic update (mean / max) | Mirror sync (mean / max) |
|---|---|---|---|---|
| Scope rifle, hip | 4.469 ms | 4.949 ms | 0.001 / 0.016 ms | – (not live) |
| Scope rifle, scoped | 4.888 ms | 5.377 ms | 0.276 / 0.646 ms | 0.257 / 0.625 ms |
| M4, hip | 4.519 ms | 4.977 ms | – | – |
| M4, ADS | 4.536 ms | 4.993 ms | – | – |

- **Scoped cost:** +0.42 ms per frame (+9 %): ≈0.28 ms CPU (mirror sync of 281 moving parts) + ≈0.14 ms render
  (ViewportFrame). Nothing renders or syncs at the hip.
- **Memory / objects:** 394 part copies in the lens WorldModel (281 moving, 113 anchored), built in 3 frames
  (150 per frame) on first equip. The lens SurfaceGui holds 12 GUI objects. There are 4 EditableImages (≈2.4 MB of
  pixels) and 2 EditableMeshes for the scope. Client memory 2083 MB (Studio) at hip vs 2084 MB scoped; graphics 59.7 MB
  either way.
- **No server work:** no per-frame server work and no new server loop. The server only gained `ScopeTest` in its weapon list.
- **Network:** 0 messages from the optic.
