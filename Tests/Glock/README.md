# Glock test (Glock weapon vertical slice, 2026-11-07)

Tests for the Glock (`Config.Weapons.Glock`, key 6) on the shared weapon path. Reference and decisions:
`ReferenceAnalysis/Glock/Glock_Analysis.md`. Checkpoints: before `Roblox/Scripts/Checkpoints/2026-11-07_before_glock`,
after `Roblox/Scripts/Checkpoints/2026-11-07_glock_slice`.

## Pieces

| Piece | Where | Purpose |
|---|---|---|
| Range | `Workspace.MP7Test` (**reused**, `Roblox/Tests/MP7/build_range.luau`) | the MP7 firing lane, bots behind `PenWall` / `SolidWall`, `WallTarget`. No new range was built |
| Server test | `ServerScriptService.GlockTest.Run` (copy `GlockTest_Server_Run.luau`) | everything from `MP7Test.Run` (placement, bots, server traces, Body* attributes, blood, kill, traffic) + the Glock shot cost |
| Client test | `StarterPlayerScripts.GlockTest.Run` (copy `GlockTest_Client_Run.luau`) | everything from the MP7 client test (equip, idle, tap, reload, track, perf) + presses with recoil / rear-dot / slide statistics measured **the footage's way**, held trigger, slide cycle, empty / lock, red-dot ADS, reload with slide and camera, switching, switch during a reload, forged remotes, instant reload |
| Captures | `captures/` | `cmp_m01…m10_*.png`: footage frame, game, 50 % overlay for the ten moments of §Visual validation; `*_raw.png`: the game captures |
| Tools | `compare.ps1`, `capture_burst.ps1` | side-by-side / overlay builder; rapid viewport capture with rear-dot and flash scoring (picks the flash / peak / recovery frames) |

## Running

```lua
-- Server
local S = require(game.ServerScriptService.GlockTest.Run)
S.place("fire")  S.spawnBots()  S.clearShots()  S.shots()  S.botState("MP7_MEDIUM")  S.blood()  S.kill()  S.shotCost(200)
-- Client
local C = require(game.Players.LocalPlayer.PlayerScripts.GlockTest.Run)
C.equip("Glock")  C.hold(1.0)  C.press(16, 0.165)  C.press(8, 0.7)  C.press(10, 0.165, { aim = true })
C.slideCycle()  C.empty()  C.ads(0.8, 0.6)  C.reload({ Mag = 0, Chambered = false, Reserve = { 15, 15 } }, stressed)
C.switchCycle({ "M4", "Glock", "AK", "Glock", "MP7", "Glock" }, 4)  C.switchDuringReload(ammo, "M4", 1.0)
C.forge(kind)  C.instantReload()  C.rawShot(id, origin, dir)  C.perf(3, false)
```
Death mid-reload: schedule the kill on the server against `workspace:GetServerTimeNow()` (tool calls take seconds to
start) and start the client reload 1.2 s before it. Poses: `ProductionWeaponDebug("freeze", { clip, t })`, then
`Roblox/Tests/M4_Reload/capture_viewport.ps1`; shots: start a firing loop in the client, then `capture_burst.ps1`.

## Results (Studio playtests with the final scripts; viewport 1452 × 753; pixels converted to the footage's 405-px picture)

### Fire
| Test | Result |
|---|---|
| Equip | key 6 / `EquippedWeapon = "Glock"`: one `GlockViewmodel` (12 parts incl. `RightArm`), client and server **15 + 1**, spares 4 × 15, FOV 70, Glock HUD present and hidden (nothing discarded) |
| One press = one shot | trigger **held 1.0 s → 1 shot**, 1 accepted |
| Cadence cap | 10 presses 0.08 s apart → **6 shots**, minimum gap **133.8 ms** (cap 450 RPM = 133.3 ms), 0 rejected |
| Footage cadence | 16 presses 0.165 s apart → 16 shots, median gap 169 ms, all accepted |
| Decrement / empty | 16 shots from 15 + 1 → mag 0, not chambered, server agrees; **5 presses from 1 + 1 → 2 shots**, then blocked; the client sends nothing when empty; a forged shot when empty → rejected ("empty") |
| Server validation | every shot traced by the server from its own head; 0 rejections of legitimate shots in every run |

### Recoil (the footage's per-shot definitions, `glock_recoil.py`)
| Measure | Game | Footage |
|---|---|---|
| Hip string kick (median) | 0.588° | 0.562° |
| End of string / 22 frames later | 1.533° / 0.218° | 1.58° / 0.17° |
| Roll s.d. while firing | 0.583° | 0.444° |
| Hip string dots dy / \|dx\| / spacing ratio / back | +17.1 / 22.7 px / 1.324 / 4 frames | +13.4 / 19.5 px / 1.328 / 4 frames |
| Single hip shots kick / dy / ratio / back | 0.652° / +21.3 px / 1.381 / 4 | 0.82° / +25 px / 1.348 / 5.5 |
| Aimed string kick / dy / ratio | 0.573° / −0.5 px / 1.203 | 0.70° / −5.5 px / 1.205 |
| Stressed hip burst kick / dy / \|dx\| / ratio | 0.605° / +30.4 / 61.7 px / 1.526 | 0.76° / +39.3 / 25.2 px / 1.53 |
| Idle | camera p-p 0.000°, weapon p-p 0.000 | ≤ 0.6 px horizon, ≤ 1.7 px dots (no sway) |
| No drift | climb returns to 0 after every string; aim is not moved by the shake (shots use climb only) | — |

### Slide
| Test | Result |
|---|---|
| Cycle | slide fraction per 30-fps frame around a shot: **0, 0, 0 (flash), 1, 0.51, 0, 0** (footage: back on the frame after the flash, home by the third); peak travel 0.084 studs = the lock travel |
| Lock on empty | locked (1.0) on the frame of the last shot, stays locked while pressing; client and server: mag 0, not chambered |
| Locked state on screen | rear-dot spacing ratio **1.20** at idle (footage 18.3 / 15.1 = 1.21) |
| Release | empty reload: locked at the start, **released at 2.666 s** (ChamberAt 2.6667; footage frame 363); tactical reloads: never moves |
| Forcing | `SlideRelease` / `Chamber` / `SetSlide` / `ReloadChambered` commands → ignored (the slide is derived from the server's `Chambered`) |

### Reloads
| Reload | Done | Swap | Chamber / slide | Ammunition after | Other |
|---|---|---|---|---|---|
| TacticalRegular (5 + 1) | **2.968 s** (2.9667) | 2.236 s (2.2333) | — | 15 + 1, old 5-round magazine back in the reserve | no label; camera pitch −6.08° (footage ≈ −5.5…−6°) |
| EmptyRegular (0) | **3.404 s** (3.4) | 2.169 s (2.1667) | **2.67 s** (2.6667) | 14 + 1 | slide locked → released at 2.666 s |
| TacticalStressed (5 + 1) | **2.434 s** (2.4333) | 1.536 s (1.5333) | — | 15 + 1, the 5 dumped | label "[TAB] 9MM MAG" at **1.536 s** (footage 450 = 1.533 s) |
| EmptyStressed (PLACEHOLDER) | 3.402 s | 2.170 s | 2.67 s | 14 + 1 | plays the Regular empty clip (no footage) |
| Refusals | "Full" (15 + 1), "NoReserve" | | | | |
| End pose | every clip ends on the rest pose (0.000 studs, 0.000°) | | | | |

Interruptions: switch to the M4 1.0 s into a tactical reload → cancelled, 5 + 1 kept (client = server), next press fires;
switch to the AK 2.4 s into an empty reload (after the swap, before the release) → 15 + 0, slide still locked, presses
blocked — a new empty reload chambers (released at 2.669 s) and fires; switch 0.8 s into an empty reload → 0 + 0, locked.
**Death** 1.26 s into an empty reload → cancelled at once, no swap; respawn → 15 + 1, slide forward, server agrees.
Firing during a reload: client fires nothing; 3 forged shots → rejected ("reloading").

### HUD
Label hidden until a magazine is discarded; "[TAB] 9MM MAG" at the Stressed tactical swap; per weapon, hidden while another
weapon is out. Geometry is the shared MagazineLabel with the Glock's measured values (centred, 0.287 below the middle).

### ADS / red dot
In **0.150 s**, out **0.130 s** (config 0.15 / 0.13); FOV 70 → **62.233** (zoom 1.16); red dot shown on **154 / 154** aimed frames
and **0** hip frames, **3.5 px above** the screen centre (footage 2.5 px below — placeholder optic geometry).

### Ballistics / body (shared pipeline)
| Shot | Server result |
|---|---|
| Direct, MP7_MEDIUM chest | `UpperTorso` / chest / **Lung**, ALIVE → INJURED, BodyHits 1, blood marks / drops / splats up |
| Through `PenWall` (WoodPlanks) | budget 2.00 → 0.94 in the wall, MP7_BEHIND_PEN chest / Lung → INJURED, 0.67 left, stops on `WallTarget` |
| Behind `SolidWall` (Concrete) | stops at the entry (NonPenetrable), the bot untouched |
| Head shots | Brain → DYING |
| Hit reaction | shared HitReaction / ActiveRagdoll presentation (BodyPresentation ActiveRagdoll, stance STANDING after a chest hit) |

### Switching
`switchCycle({M4, Glock, AK, Glock, MP7, Glock}, 4)`: every equip shows **exactly one viewmodel** (the equipped one) and
one effects folder; FOV 70, climb 0, no reload, slide 0, HUD hidden; Glock 15 + 1 kept; **instance count unchanged**
across 3 extra cycles (56 710 → 56 710: no duplicated rigs / connections).

### Security (malicious client, Glock equipped)
| Attempt | Server result |
|---|---|
| Origin 40 studs ahead / behind `SolidWall` | rejected / rejected |
| Direction behind the shooter, NaN, ±Inf origin, zero vector | rejected |
| Wrong argument types | rejected |
| MP7 shot while the Glock is out; unknown `Glock_GOLD`; `Equip "Glock_GOLD"` then fire it | rejected; rejected; equip ignored, shot rejected |
| Forged hit (position, part, "Head", damage 999, direction down) | accepted only as a plain shot: traced from the server head into the floor, **0 damage** |
| 12 shots in one frame | **3 accepted / 9 rejected** |
| ≈2000 RPM for 1 s (33 shots) | **10 accepted / 23 rejected** (450 RPM + allowance) |
| Forged ammunition / reload results (`SetAmmo`, `ReloadDone`, `ReloadSwapped`) | ignored, server ammunition unchanged |
| Forced slide / chamber commands | ignored |
| Instant reload (`Reload` + `ReloadDone` + a second `Reload`, then 3 shots) | 3 shots rejected ("reloading"), magazine unchanged at 0.4 s, reload completes on the clip's time |
| Fire when empty (forged) | rejected ("empty") |

### Performance (Studio, uncapped)
Idle 4.19 ms mean / 4.82 ms p95; firing (presses at the footage cadence) 4.71 / 5.15 ms; 21 pooled effect parts, at most 3
visible; instance count unchanged by firing; server `WeaponShot.resolve` 0.74 ms mean (max 1.73) over 200 shots.

## Visual validation (`captures/cmp_m*.png`: footage | game | 50 % overlay)

| # | Moment | Footage frame | Measured / seen difference |
|---|---|---|---|
| 1 | Idle (hip) | 5 | rear dots (394.95, 259.7) px, spacing 15.45 vs footage (394.97, 262.4), 15.59: **x 0.02 px, y 2.7 px, spacing −0.9 %**. Placeholder slide / optic read slightly larger |
| 2 | First shot (flash) | 12 | flash at the muzzle, slide back; our starburst + light are the shared effect style |
| 3 | Repeated shots (string) | 255 | flash + slide back mid-string; weapon kick within the measured range |
| 4 | Recoil peak (frame after the flash) | 13 | spacing ratio 1.34 (footage 1.33–1.35), dots +12.7 px (footage +13…+25) |
| 5 | Recovery | 16 | ratio 1.07 at +3.5 frames, at rest by +6 (footage back by 4–5.5 frames) |
| 6 | Magazine out | 55 | pistol tilted the same way; our right arm block reads bigger than the footage's |
| 7 | Magazine insertion | 106 | pistol rolled ≈40° as in the footage; **our left hand and new magazine are hidden behind the right arm** (footage: lower-left of the pistol) |
| 8 | Slide interaction | 360 | left forearm comes up from the lower left to the slide's left (footage: upright column on the left); ours is less upright |
| 9 | Empty: slide locked | 270 | locked spacing ratio 1.20 (footage 1.21) |
| 10 | Reload completing | 133 | back at the hip rest (end pose 0.000 studs / 0°) |

## Full regressions (one fresh playtest, final scripts, client-teleport allowance on; recipes in each suite's README)

| Area | Result (baseline: `Roblox/Tests/MP7/README.md`) |
|---|---|
| BodyState | unit 42 / 42; real shots M4 6 / 6, AK 6 / 6; forged requests rejected (INJURED, health 100, the server's own leg hit) — match |
| Ballistics | unit 10 / 10 per lane for both rifles (budgets 1.75 / 1.249 / 2.0, end z 91 / 91 / 131); real shots 18 / 18 (drops A 6, B 6, C 0) — match |
| Hit reactions / ragdoll | M4 6 / 6, AK 6 / 6; dying states 11 / 11 (crawl 0.61 studs/s); tamper pass — match |
| Blood | M4 14 / 14, AK 14 / 14; dead hit; world 4 / 4 / 23; security pass; orphans 0 — match |
| Body interaction | pulse 3.0004–3.0042 s server / 3.013–3.018 s client; no pulse REACT5 / 4 / 6; far / invalid / interrupt 1.700 s / forged / local state; death → "Interrupted (player dead)"; drags 9.05 / 9.08 studs, 5.6 restored; trails 11 / 11; "too far" 0.764 s; tamper, orphans 0 — match (**known exception:** `WalkSpeed == 16` reads 5.6) |
| AK | 640 RPM; hip climb 1.229°; raised 0.129 / 0.289 s, FOV 70; magazine 31, climb 1.945°; reloads 2.433 / 1.665 / 3.130 / 2.762 s; label 1.069 s; sequence, refusals, switch, repeated — match |
| M4 | 29 + 1; 770 RPM; ADS in 0.333 / 0.333 s, out 0.119 / 0.121 s, FOV 62.233; ADS recovery 0.743 s; hip recovery **0.768 s (rerun 0.770)**, baseline 0.743, earlier READMEs 0.739–0.776; de-cant −32.575° → −0.222° (rerun +0.037°); 0 late shots; reloads 3.533 / 3.062 / 3.697 / 3.600 s; Stressed sway roll 3.492° (known to vary) |
| M4 HUD | 13 checks, 0 mismatches; label 1.703 / 1.735 / 1.601 s; "+1", "+2" — match |
| Death / respawn | killed 2.0004 s into an AK empty reload → "cancelled (died) after the magazine change"; respawn 3.335 s / 3.345 s; M4 HUD agrees, M4 fires — match |
| Original reload test | M4AnimTest 379 / 380 plays 3.528–3.542 s (one 3.707 s during a death / respawn hitch) — match |
| AI | perception 14 / 14, aiming 8 / 8, firing 11 / 11 (759.1 RPM, empty reload 3.701 s), integration 10 / 10; player as target 7 / 7; bot shoots player 5 / 5; M4 takedown 6 / 6; security 10 / 10 — match |
| Movement | rules 25 / 25; walk 5.600; crouch eye 2.700, 2.80 studs/s; jump +7.532; roll 1.399° / −2.699°; weapon lag 5.953° / 7.396° hip, 0.894° / 1.112° aiming; death / respawn checks — match |
| Optics | in 0.144 / 0.141 s, out 0.154 / 0.152 s; lens 162.4 px, ring 266.4 px, magnification 4.500; tracking 0.894° / 1.110°; shots, traces, body states, respawn, security, 0 client → server events while scoped — match; flags: roll while scoped 1.352° / 2.606°, up-vector 0.020°, lens kick ×1.36–1.42 (the known optics flags) |
| MP7 (its own 25 tests) | all pass with the README numbers (41 / 41 at 950 RPM; climb 4.139–4.143°, 1.63° after 26 frames; ADS 0.254 / 0.150 s; reloads 3.271 / 4.934 / 2.105 / 3.401 s; penetration 2.0 → 1.0 → 0.75; forged rate 3 / 9 and 19 / 14) — aim-dependent first readings rerun and matched |
| Grenade (last) | fuse 4.0002–4.0039 s over 11; release 0.148–0.153 s, 55 studs/s; wall / lob / steep / room counts within earlier runs; refusals; "NO FRAGS LEFT"; forged 10 refusals; 3 in a row clean; player health 100 — match |
| Glock smoke (same session) | hold 1 s → 1 shot; 16 presses → 16 / 16 accepted, 0 + 0; empty → 2 shots then locked, server agrees; empty reload 3.401 s, swap 2.171, slide released 2.662 s; switch cycles: one viewmodel per equip |
| Console | 0 errors from game code (server and client, whole session); warnings only the expected security rejections |

**Separate, not changed (as instructed):** the M4 Stressed reload end-pose discrepancy (3.227° tactical, 2.465° empty this run).
