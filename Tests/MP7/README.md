# MP7 test (MP7 weapon vertical slice, 2026-11-07)

Tests for the MP7 (`Config.Weapons.MP7`, key 5) on the shared weapon path. Reference and decisions:
`ReferenceAnalysis/MP7/MP7_Analysis.md`. Checkpoint: `Roblox/Scripts/Checkpoints/2026-11-07_mp7_slice`.

## Pieces

| Piece | Where | Purpose |
|---|---|---|
| Range | `Workspace.MP7Test` (built by `build_range.luau`, Edit mode) | isolated at x 400–540, z −350…−150. Firing lane: F = (450, 0, −330) facing +Z; REACT1 bots MP7_CLOSE (10 studs), MP7_MEDIUM (50), MP7_DISTANT (150), MP7_BEHIND_PEN (behind `PenWall`, 1 stud, `BallisticSurface = Penetrable`), MP7_BEHIND_SOLID (behind `SolidWall`, unmarked = NonPenetrable); `WallTarget` board. Reload lane (480, 0, −330), clear for 200 studs. Movement lane x 505–535 with 10-stud markers and a 6-stud ledge |
| Server test | `ServerScriptService.MP7Test.Run` (copy `MP7Test_Server_Run.luau`) | lane placement (server teleport), fresh bots, the server's own traces (`Ballistics.RecentResults`), Body* attributes, blood counts, client → server traffic counter, kill, server shot cost, remote inventory |
| Client test | `StarterPlayerScripts.MP7Test.Run` (copy `MP7Test_Client_Run.luau`) | equip, idle, bursts with recoil statistics resampled at 30 fps (the footage's rate), taps, ADS, reloads, movement, forged remotes, cost |
| Captures | `captures/` | hip idle vs footage frame 180, reload poses vs footage (95, 125, 305, 410, 612, 856) |

## Running

```lua
-- Server
local S = require(game.ServerScriptService.MP7Test.Run)
S.place("fire" | "reload" | "move", offset?)  S.spawnBots()  S.clearShots()  S.shots()  S.botState("MP7_CLOSE")
S.blood()  S.netStart()  S.netStop()  S.kill()  S.shotCost(60)  S.remotes()
-- Client
local C = require(game.Players.LocalPlayer.PlayerScripts.MP7Test.Run)
C.equip("MP7")  C.look(point)  C.idle(3)  C.burst(3.0, { after = 1.2 })  C.tap()  C.ads(0.8, 0.6)
C.reload({ Mag = 0, Chambered = false, Reserve = { 40, 40 }, Dropped = {} }, stressed)
C.track({ move = Vector3.new(0, 0, -1), seconds = 2 })  C.track({ crouch = true, ... })  C.track({ jump = true })
C.track({ rate = 20 | 60, seconds = 1.5 })  C.forge(kind)  C.rawShot(id, origin, dir)  C.perf(seconds, firing)
```
Death mid-reload: schedule the kill on the server ≥ 20 s ahead (`task.delay`) and start the client call that waits for it
(calls take several seconds to start). Reload poses: `ProductionWeaponDebug("freeze", { clip, t })` then
`Roblox/Tests/M4_Reload/capture_viewport.ps1`.

## Results (fresh playtests, final scripts and data; viewport 1452 × 753, values also given at the footage's 720 p)

### MP7 tests (25 required)

| # | Test | Result |
|---|---|---|
| 1 | Equip | key 5 / `EquippedWeapon = "MP7"`: one viewmodel `MP7Viewmodel` (Weapon_Polymer, Weapon_Metal, Magazine_Polymer, ChargingHandle_Metal, LeftArm); client and server 40 + 1, spares 4 × 40; server equipped MP7; FOV 70; MP7 HUD present, label hidden (nothing discarded yet) |
| 2 | Unequip | MP7 → M4: only `M4Viewmodel`, MP7 label hidden, server M4, FOV 70; → AK: only `AKViewmodel`, server AK; back to MP7: one MP7 viewmodel, 40 + 1, server MP7 |
| 3 | Idle | Regular and Stressed (3 s each): camera pitch / roll p-p **0.000°**, muzzle relative to the camera p-p 0.000 studs (footage: ≤ 1 px / 0.03–0.07° in every idle window of both halves); muzzle on screen at (673, 496) 720 p, weapon top within ≈12 px of footage frame 180 (`captures/hip_idle_level.png`) |
| 4 | Hip fire | full magazine (3 runs): **41 shots, 41 accepted, 0 rejected**, magazine 0, not chambered (client and server) |
| 5 | ADS (PLACEHOLDER) | in **0.25 s**, out **0.15 s**, FOV 70 throughout (no zoom), iron-sight line **0.000°** from the camera axis, front post at the screen centre (0, −0.001 px) |
| 6 | Firing rate | **950 RPM** from the shot span, median / max gap 63.158 ms (3 runs); single press (tap) = 1 shot (×2); 0.25 s hold = 4 shots, all accepted |
| 7 | Recoil | camera climb at the end of a 41-shot burst **4.12–4.14°** (footage D 4.25°, model fit 4.11°); 26 frames after the last shot 1.63° (footage ≈2.1°, model 1.55°); pitch shake |Δ| median at 30 fps **0.52–0.62°** (target 0.52°); roll sd **0.39–0.49°** (target 0.40–0.53°); weapon top |Δx| median **9.8–16.2 px** at 720 p (target 13 px); hip-fire envelope 1 (de-cant) |
| 8 | Reload | TacticalRegular **3.271 s** (swap 2.335), EmptyRegular **4.934 s** (swap 1.834, chamber 4.235), TacticalStressed **2.104 s** (swap 1.237), EmptyStressed **3.402 s** (swap 1.169, chamber 2.802) — config 3.2667 / 4.9333 / 2.1 / 3.4 s; each clip ends exactly on the rest pose (0.000 studs, 0.000°). Poses vs footage: `captures/reload_compare.png` |
| 9 | Ammo accounting | tactical Regular from 10 + 1: 40 + 1, the 10-round magazine back in the reserve, nothing dropped; empty Regular from 0: 39 + 1, empty magazine dropped; Stressed tactical from 35 + 1: 40 + 1, the 35 dropped; Stressed empty: 39 + 1, dropped {35, 0}; client = server every time; refusals "Full" and "NoReserve" |
| 10 | HUD | label hidden until the first discarded magazine; **"[TAB] 4.6 MAG"** at the swap (1.834 s empty Regular, 1.237 s Stressed tactical), **"+1"** at 1.169 s (Stressed empty); centre x 0.500, **0.290** of the screen height below the middle (footage 0.29), ink 55.6 px at 720 p (footage 54), colour 165 / 165 / 167, SourceSans, one GUI copy; hidden while another weapon is out or dead |
| 11 | Movement | walk **5.72 studs/s** over 0.25 s windows (the accepted 5.6 walk), eye 4.05, bob to +0.20; turns: weapon lag **5.96° / 7.40°** at 20 / 60 °/s, camera roll **1.40° / 2.70°** (accepted 5.953 / 7.392°, 1.399 / 2.689–2.699°) |
| 12 | Crouch | eye **2.70**, 2.85 studs/s; stands again |
| 13 | Jump | camera 4.05 → **11.58** (+7.53, the accepted apex) |
| 14 | Ballistics | every shot traced by the server from **its own head** (origin 0.03 studs from the head); wall shot stops on `WallTarget` 0.05 studs from the aim point (NonPenetrable), no blood on a wall |
| 15 | Penetration | `PenWall`: entered with budget 2.0, exited with 1.0, the bot behind hit (`chest` / Lung), exits with 0.75, stops in the baseplate; `SolidWall`: stops at the entry ("NonPenetrable"), the bot behind untouched |
| 16 | Hit location | chest shot at 10 studs → `chest` / UpperTorso / Lung; head shot at 50 studs → `head` / Brain |
| 17 | BodyState | MP7_CLOSE ALIVE → INJURED (Lung, standing); MP7_MEDIUM ALIVE → DYING → DEAD (Brain, life 0); 6-shot burst on MP7_CLOSE INJURED → DYING (7 hits) |
| 18 | Hit reaction / ragdoll | from the server's Body* attributes: chest-hit bot stays STANDING (presentation ActiveRagdoll); head-shot bot DOWN / LIMP (ragdoll, head at y 0.49); burst bot DOWN / CRYING (dying) |
| 19 | Blood | chest hit: marks 26 → 30, drops 20 → 23, splats 6 → 7, stains 0 → 2; head shot: pools 2 → 3 (growing); 6-shot burst: marks 36 → 61, drops 27 → 46, stains 6 → 18, pools 3 → 4; wall hit: no change |
| 20 | Death | killed with the MP7 out: no viewmodel, HUD hidden, FOV 70; the client fires **0** shots with the trigger held; a forged shot is rejected ("shooter is not alive"); an MP7 empty reload in progress → "cancelled (died) after the magazine change" |
| 21 | Respawn | **3.33 s** later: MP7 still equipped, one viewmodel, 40 + 1, spares 4 × 40 (server and client) |
| 22 | Forged origin | 40 studs ahead → rejected ("origin 39 studs from head"); 4 studs ahead on the far side of `SolidWall` (inside the 8-stud limit) → rejected |
| 23 | Forged direction | behind the shooter → rejected; NaN → rejected; zero vector → rejected |
| 24 | Forged hit | extra hit position, target part, "Head", `{ damage = 999 }` with a downward direction → accepted only as a plain shot: traced from the server head straight down into the firing pad, **no damage**, the named target untouched |
| 25 | Fire-rate abuse | 12 shots in one frame → **3 accepted / 9 rejected** (burst allowance 3); 2000 RPM for ≈1.1 s → **19 / 14** (≈ 950 RPM + allowance, "firing faster than the weapon allows") |

### Security (malicious client)

| Attempt (MP7 equipped unless stated) | Server result |
|---|---|
| Forged fire rate | capped (25) |
| Forged ammunition / reload completion: `SetAmmo {Mag 999}`, `ReloadDone`, `ReloadSwapped` commands | ignored: server magazine and spares unchanged (`DevSetAmmo` / `DevRefill` exist only in Studio) |
| Forged weapon: `AK` while the MP7 is equipped | rejected ("AK is not equipped") |
| Unknown weapon `MP7_GOLD`; wrong argument types | rejected |
| Forged origin / direction / hit point / target | rejected or traced from the server head only (22–24) |
| Firing while dead | rejected (20) |
| Firing while unequipped: an MP7 shot while the M4 / the test blaster is out | rejected |
| Firing during a reload | rejected; the client itself fires 0 shots during a reload |
| Remotes | 12 before and after: the MP7 adds no remote |

### Performance (Studio, uncapped)

| Case | Mean frame | p95 |
|---|---|---|
| MP7 idle | 4.67–4.94 ms | 5.22–5.52 ms |
| MP7 sustained fire (2.6 s, 41 shots) | 4.96 ms | 5.57 ms |
| M4 idle / fire (baseline, same session) | 4.61 / 5.33 ms | 5.10 / 5.89 ms |

- **Effects:** 46 pooled parts for the MP7 (flash 4 + streak, 12 sparks, 12 smoke puffs, light, 16 casings), created
  once at start; at most 26 visible during sustained fire. **Instance count unchanged by firing** (56 159 before and after):
  no per-shot objects.
- **Server:** one `WeaponShot.resolve` (trace + impact presentation + record) mean **0.85 ms** (median 0.96, max 1.56 ms,
  60 shots at the wall) — ≈13 ms per second of sustained 950 RPM fire; no per-frame server loop was added (the server
  change is one table entry).
- **Network:** exactly one `WeaponFire` per shot (72 = 41 MP7 + 31 M4 shots), client send 0.48–0.71 kbps.

### Full regressions (one fresh playtest, final scripts, client-teleport allowance on; recipes in each suite's README)

| Area | Result (baseline: `Roblox/Tests/Optics/README.md`) |
|---|---|
| BodyState | unit 42 / 42; real shots M4 6 / 6, AK 6 / 6; forged requests rejected (INJURED, health 100, the server's own leg hit) |
| Ballistics | unit 10 / 10 per lane for both rifles (budgets 1.75 / 1.249 / 2.0, end z 91 / 91 / 131); real shots 18 / 18 (drops A 6, B 6, C 0) |
| Hit reactions / ragdoll | M4 6 / 6, AK 6 / 6; dying states 11 / 11 (crawl 0.60 studs/s); tamper pass |
| Blood | M4 14 / 14, AK 14 / 14; dead hit (DEAD, effect, no bleed); world 4 entries / 4 exits / 23 non-penetrable (24 in the baseline: the count includes the session's earlier shots); security pass; orphans 0 |
| Body interaction | pulse 3.0007–3.0039 s server / 3.013–3.018 s client; no pulse REACT5 / REACT4 / REACT6 (2nd check); far / invalid / interrupt 1.698 s / forged / local state; death → "Interrupted (player dead)"; drags 9.05–9.06 studs at WalkSpeed 9, 5.6 restored; trails 10–14 smears; "too far" 0.784 s; tamper and orphans 0 — **known exception only:** the orphan check's hard-coded `WalkSpeed == 16` reads 5.6 |
| AK | 640 RPM; hip climb 1.236°; raised 0.126 / 0.285 s, FOV 70; magazine 31 at 640 RPM, climb 1.945°; reloads 2.431 / 1.663 / 3.130 / 2.763 s; label 1.068 s; sequence, refusals, switch, repeated pass |
| M4 | 29 + 1; hip burst 770 RPM; ADS magazine 31 at 770 RPM; ADS in 0.332 / 0.330 s, out 0.118 / 0.122 s, FOV **62.233**; recovery 0.769 s (rerun 0.741 s; baseline 0.77 / 0.742); hip recovery 0.743 s; de-cant −32.575° → −0.021°; 0 late shots; reloads 3.531 / 3.065 / 3.700 / 3.596 s; Stressed sway roll 1.577–3.500° (known to vary) |
| M4 HUD | 13 checks, 0 mismatches; label at 1.700 / 1.738 / 1.602 s; "+1", "+2" |
| Death / respawn | killed 2.0033 s into an AK empty reload: "cancelled (died) after the magazine change"; respawn 3.355 s (server) / 3.371 s (client); M4 HUD agrees (30, chambered); M4 fires |
| Original reload test | M4AnimTest plays 3.525–3.544 s |
| AI | perception 14 / 14, aiming 8 / 8, firing 11 / 11 (761.9 RPM, empty reload 3.704 s), integration 10 / 10; player as target 7 / 7; bot shoots player 5 / 5; M4 takedown 6 / 6; security 10 / 10 |
| Movement | rules 25 / 25; walk 5.600 studs/s; crouch eye 2.700, 2.80 studs/s; jump +7.532; roll 1.399° / −2.699° (movement value); weapon lag 5.955° / 7.391° hip, 0.894° / 1.111° aiming; death / respawn checks pass |
| Optics | equip / unequip; in 0.150 / 0.148 s, out 0.155 / 0.150 s (baseline 0.143 / 0.152); lens 162.4 px, ring 266.4 px, centred, magnification 4.500; tracking 0.894° / 1.110°; walk 5.715, jump, crouch; 3 shots accepted, server-head traces; hits head / Brain → DEAD, chest / Lung → INJURED; death / respawn 3.348 s; security as the baseline; 0 client → server events while scoped — **three flags below** |
| Grenade (last) | fuse 4.0005–4.0042 s over 11; release 0.148–0.154 s, 55 studs/s; wall 374 / 221, lob 303 / 297, steep 307 / 292, room 554 / 37; timing refused / accepted; "NO FRAGS LEFT"; bodies; forged 10 refusals; 3 in a row clean; player health 100 |
| Console | 0 errors from game code (server and client); warnings only the expected security rejections; two errors came from the tester's own mis-typed calls (retried correctly). The log is capped at 512 lines, so the first third of the session was not retained |

**Flags (not resolved; reported as found):**
1. **Optics camera roll while scoped:** 1.243–1.352° at 20 °/s and 2.397–2.53° at 60 °/s against 1.399 / 2.682° in the baseline. The movement code's own roll value is exact (1.399 / −2.699) and the horizon matched it earlier in the same session at ≈60 fps; later, at ≈215 fps, the horizon read a constant 0.888 of it. The movement and optics scripts are byte-identical to the accepted checkpoint, and none of the three changed scripts touches the camera roll, so this looks like a frame-rate effect of the measurement — **not confirmed**.
2. **Optics scope tracking:** the first 60 °/s run read 1.43° (one frame hitch); three reruns 1.110°. The scope-vs-camera up-vector difference read 0.028° against "within 0.02°".
3. **Optics lens kick:** over 7 shots the ring grew ×1.20–1.394 (baseline ×1.31–1.40) and the lens rose −11 to 101 px (baseline 32–53 px); the eye-box shadow shift appeared on the frames after the shot instead of the shot frame. The kick is random per shot and uses the accepted M4 recoil (unchanged).

**Separate, not changed (as instructed):** the M4 Stressed reload end-pose discrepancy is still there (4.118° tactical,
3.194° empty this run).
