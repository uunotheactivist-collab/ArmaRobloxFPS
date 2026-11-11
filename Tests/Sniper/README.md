# Sniper test (bolt-action Sniper vertical slice, 2026-11-08)

Tests for the Sniper (`Config.Weapons.Sniper`, key 7) on the shared weapon path and the accepted optics framework
(`Config.Optics.SniperScope`). Reference and decisions: `ReferenceAnalysis/Sniper/Sniper_Analysis.md` (sniper2.mp4).
Checkpoints: before `Roblox/Scripts/Checkpoints/2026-11-08_before_sniper`, after `Roblox/Scripts/Checkpoints/2026-11-08_sniper_slice`.

## Pieces

| Piece | Where | Purpose |
|---|---|---|
| Range | `Workspace.MP7Test` (**reused**, `Roblox/Tests/MP7/build_range.luau`) | the MP7 firing lane, bots behind `PenWall` / `SolidWall`, `WallTarget`. No new range |
| Server test | `ServerScriptService.SniperTest.Run` (copy `SniperTest_Server_Run.luau`) | everything from `MP7Test.Run` (placement, bots, server traces, Body* attributes, blood, kill, traffic) + the Sniper shot cost |
| Client test | `StarterPlayerScripts.SniperTest.Run` (copy `SniperTest_Client_Run.luau`) | shots with the footage's per-shot measures, held trigger, bolt cycle (hip / scoped), empty, scope in / out, zoom, rounds check, switching (also mid-cycle), forged remotes, instant reload; MP7 helpers (equip, reload, track, perf) |
| Captures | `captures/` | `cmp_*.png`: footage frame, game, 50 % mix for the 16 moments of the visual validation |
| Tools | `compare.ps1`, `frames/` | side-by-side / overlay builder for the 1280 x 720 footage; the footage frames used |

## Running

```lua
-- Server
local S = require(game.ServerScriptService.SniperTest.Run)
S.place("fire")  S.spawnBots()  S.clearShots()  S.shots()  S.botState("MP7_MEDIUM")  S.blood()  S.kill()  S.shotCost(100)
-- Client
local C = require(game.Players.LocalPlayer.PlayerScripts.SniperTest.Run)
C.equip("Sniper")  C.hold(1.0)  C.shots(2, 1.7)  C.shots(6, 1.7, { aim = true })  C.cycle(false)  C.cycle(true)
C.empty()  C.ads()  C.zoom()  C.check()  C.reload({ Mag = 3, Chambered = true, Reserve = { 5, 5 } })
C.switchCycle({ "M4", "Sniper", "AK", "Sniper", "MP7", "Sniper", "Glock", "Sniper" }, 3)  C.switchDuringCycle("M4")
C.forge(kind)  C.instantReload()  C.track({ aim = true, ... })  C.perf(3, false)
```
Old suites teleport the player client-side: run `MovementTest.Run.dbg("allowClientTeleports", nil, true)` on the server first.
Poses: `ProductionWeaponDebug("freezeBolt", t)` holds the bolt cycle (hip or scoped, by the aim) at t s;
`("freeze", { clip = "TacticalRegular", t = 2.9 })` holds a reload / check clip (`panel = 1` shows the rounds panel); then
`Roblox/Tests/M4_Reload/capture_viewport.ps1` and `compare.ps1`. Shot moments (flash, kick, recovery) are live:
`capture_burst.ps1` grabs the viewport back to back during a real shot and scores the flash pixels per grab.

## Results (playtests of 2026-11-08)

Footage numbers are from `ReferenceAnalysis/Sniper/Sniper_Analysis.md` (30 fps frame offsets from the flash frame).
Game numbers are sampled from the client log at the footage's 30 fps phase (`at30`) unless stated.

The fire / ammunition / reload / switching / security / ballistics / scope / performance rows were measured before the
last presentation calibration (recoil values and clip poses: `Sniper_Analysis.md` §10b), which doesn't touch them. After
it, in the final playtest:
- the bolt cycle was re-measured (casing 0.70 s, chamber 0.934 / 0.938 s client, 0.964 / 0.978 s server, next shot
  1.567 s, hand +10..+37);
- the tactical reload was re-measured (4.170 s, swap 3.137 s, end pose 0 / 0);
- the recoil, the visual validation and the full regression come from the final scripts.

### Equip, fire mode, ammunition

| Test | Result | Footage / rule | Verdict |
|---|---|---|---|
| Equip (key 7) | 1 viewmodel (10 parts), 5 + 1, spares 4 × 5, main FOV 70 | 5 + 1 (INFERRED), FOV unchanged | pass |
| Trigger held 1 s | 1 shot | one shot per activation | pass |
| Two hip presses 1.7 s apart | 2 accepted, server ammo agrees | min. interval 1.567 s | pass |
| Six scoped presses 1.7 s apart | 6 accepted; magazine 0 + 0 after; server agrees | | pass |
| Dry presses on empty | nothing sent; server 0 + 0 | | pass |
| Bolt cycle timing (client) | casing at 0.704 s (+21.1 fr), chamber predicted 0.937 s (+28.1), next shot 1.567 s (+47) | +21 / +28 / +47 | MEASURED MATCH |
| Bolt cycle timing (server) | chambered (`BoltChambered`) 0.967 / 0.982 s after the shot (the client clock: delay + replication) | +28 = 0.933 s | match (+1 frame of latency) |
| Right hand on screen (bolt) | frames +10..+37, hip and scoped (final clips) | right arm +10..+37 (gone at +38) | MEASURED MATCH |
| Fire during the cycle | presses before ReadyAt send but are rejected (`bolt cycling`); the client blocks them first | never seen | pass |
| Reload during the cycle | refused on the client and the server (`ReloadRefused:Cycling`) | not seen (INFERRED) | pass |
| Rounds check (V) | panel from 1.002 s, full 1.174, fade 2.536, gone 2.705; "5" / "/5 RDS"; 94 × 36 px at 753 px; no shots while checking; refused while cycling | panel 30 → 76, fade to 81 (frames 296 → 347) | MEASURED MATCH (centre 2 px left / 16 px high of the footage) |

### Reloads

| Test | Result | Footage | Verdict |
|---|---|---|---|
| Tactical (3 + 1 left) | done 4.168 s, swap 3.137 s; 5 + 1, the old 3-round magazine kept in the spares; end pose 0 / 0 | 125 fr = 4.167 s, seated 94 = 3.133 s | MEASURED MATCH |
| Empty (0 + 0) | done 5.936 s, swap 4.134 s, chamber 5.503 s; 4 + 1; bolt stroke 0.314 studs | 178 fr = 5.933 s, seated 124 = 4.133, chambered 165 = 5.5 | MEASURED MATCH |
| Switch away at 1 s into a tactical | cancelled, 2 + 1 kept, the next tap fires | | pass |
| Switch away after the empty swap (before the chamber) | 5 + 0: blocked (nothing chambered); a new empty reload gives 4 + 1 and fires | | pass |
| Death 1.98 s into an empty reload | cancelled, no swap; respawn after 3.7 s: 5 + 1, 4 × 5, server agrees | | pass |
| Instant reload forged (reload then 3 shots at once) | 3 shots rejected (`reloading`), magazine unchanged at 0.5 s, completes on the clip time | | pass |

### Switching

| Test | Result | Verdict |
|---|---|---|
| `switchCycle` M4 / AK / MP7 / Glock / ScopeTest ↔ Sniper, 3 rounds | one viewmodel and one effects folder each time; only the equipped optic's lens gui enabled; FOV 70; climb 0; no reload / bolt clip; ammo kept; zoom level kept; instances 57244 → 57244 | pass |
| `switchDuringCycle` M4 and Glock | presentation reset (hip, lens not live, no bolt clip); zoom kept; the server still chambered; the next Sniper shot still 0.61 s away (the cycle runs on: switching doesn't skip it); an early press fired nothing; the shot after the cycle accepted | pass |

### Security (forged remotes; server ammo unchanged unless a shot was accepted)

| Forge | Result |
|---|---|
| farOrigin, wallOrigin, behind, nan, inf, zero direction, badTypes | rejected |
| wrongWeapon, unknownWeapon, equipUnknown | rejected |
| ammo (client claims a full magazine) | ignored (server count) |
| switchFire (fire the Sniper while the M4 is equipped) | rejected (`Sniper is not equipped`) |
| fakeHit (client-chosen hit part / damage) | accepted as a plain shot traced by the server from the server head; 0 damage to the claimed part |
| rate: 12 shots in one frame | 1 accepted / 11 rejected |
| cycleFire: 4 shots inside one cycle | 1 / 3 |
| bolt: forged BoltReady / Chamber / CycleDone / BoltChambered commands then fire | 1 / 2, the commands ignored |
| reloadDuringCycle | refused; no reload running |
| rateSustained: a shot every 0.5 s for 4 s | 3 accepted (0, 1.5, 3.0 s) / 6 rejected (the 0.1 s grace allows 1.467 s) |
| dead: the server kills the player, then 3 shots | 0 / 3, server log "shooter is not alive" (checked before ammunition) |

### Ballistics, damage, blood (shared pipeline; Sniper values PLACEHOLDER)

| Test | Result |
|---|---|
| PEN lane | budget 2.00 → 0.94 → 0.67; chest INJURED (standing); stops at `WallTarget` |
| SOLID lane | stops at the wall entry; the bot untouched |
| CLOSE chest | through, into the floor |
| MEDIUM head | through the CLOSE and MEDIUM heads → DYING → DEAD, active ragdoll down |
| Blood | marks / drops / splats / stains all rose |

### Scope

| Test | Result | Footage | Verdict |
|---|---|---|---|
| ADS in / out | 0.201 s / 0.167 s | 6 fr (0.20 s) / 5 fr (0.17 s) | MEASURED MATCH |
| Main FOV while scoped | 70 | unchanged | CONFIRMED MATCH |
| Hip eyepiece | (695.7, 611.4), 96.8 px | (696.5, 615), 98 px | MEASURED MATCH |
| Scoped ring | centre (640, 360), 194.8 px | ≈(648, 340 ± 15), 200 px | ring size MEASURED MATCH; centre 8 px left / 20 px low (inside the footage's ±15 px drift for x only) |
| Magnification | 6x default; scope FOV 2.46°; axis 0° | 6x INFERRED | INFERRED |
| Zoom | 6 → 9 → 12 → 3 → 6 (wrap); magnification = level; reticle scale = level / 6; label "9x" etc. ~1.2–1.4 s; no zoom at the hip | labels 9x / 12x / 3x, wrap, ~3-frame resize | CONFIRMED / INFERRED |
| Zoom across ADS | 9x → scope out → scope in: 9x; the wrap test re-scoped at 3x; kept through weapon switches | the 3x reticle after re-scoping (828–832) | CONFIRMED MATCH |
| Moving scoped | walk 5.70 studs/s; crouch eye 2.7; jump OK; turn roll 2.69°, lag 7.4°, viewmodel 1.1°; always scoped, lens live (139 px) | | pass |

### Recoil (final calibration; 2 hip + 6 scoped shots, 1.7 s apart)

Camera pitch vs the two frames before the shot, deg (shake + climb). Footage: `ReferenceAnalysis/Sniper/Sniper_Analysis.md` §5.

| Frame | Game hip (2) | Game scoped (6, median) | Footage hip / scoped | Verdict |
|---|---|---|---|---|
| +0 (flash) | 1.51 / 1.26 | 1.32 (0.33–1.50, phase) | 1.07 / 1.15 ; 0.0–1.33 | high by ~0.2–0.3 (hip) |
| +1 | 1.14 / 1.04 | 1.23 (1.12–1.49) | 1.27 / 1.21 ; median 1.08 | all 8: median **1.18** vs 1.16 — MEASURED MATCH |
| +2 | 0.74 / 0.69 | 0.84 | 0.73 ; 0.73 | match ±0.1 |
| +3 | 0.52 / 0.49 | 0.57 | 0.52 ; 0.51 | match |
| +4 / +5 | 0.40 / 0.36 | 0.43 / 0.36 | 0.30 / 0.22 ; 0.36 / 0.30 | high by ≤ 0.1 (no undershoot in the model) |
| +6 / +30 (residual) | 0.34 / 0.32 | 0.33 / 0.28 | 0.28 / 0.31 ; 0.32 / 0.35 | MEASURED MATCH |
| String of 6 | — | climb 2.0° | 1.9° | MEASURED MATCH |

Weapon (engine projection, 1280 × 720 picture):

| Frame | Hip muzzle (2 shots) | Footage muzzle top (9 / 56) | Scoped ring centre (6 shots) | Footage ring |
|---|---|---|---|---|
| +0 | −20 / −13 | (flash) | −133..−261, ×1.32–1.66 | −257 ×1.8 (427 / 567), −147 (477) |
| +1 | −59 / −56 | −39 / −60 | −132..−167 (median ≈ −148), ×1.0–1.1 | −150..−158, normal size |
| +2 | −65 / −68 | −81 / −62 | −79..−113 (≈ −91) | −97 |
| +3 | −48 / −50 | −65 / −44 | −52..−65 | −55 |
| +4 / +5 | −34 / −31 | −41..−30 / −34..−25 | −50 / −38..−50 | −49 / −49 |
| +6..+9 | −33..−35 (raised hold) | ≈ −34 | −25 / −19 / −13 / −7 | −27 / −23 / −18 / −7 |

Calibration history (why the numbers moved): `ReferenceAnalysis/Sniper/Sniper_Analysis.md` §10b.

### Visual validation (16 moments; `captures/cmp_*.png` = footage | game | 50 % mix, 100-px grid of the 1280 × 720 picture)

Game key points are engine projections at the capture (1280 × 720 picture, camera pitched 5.1° down like the footage).
Shot moments are live captures (`capture_burst.ps1`, ~33 ms apart, so the frame offset is ±1); the others are frozen
poses (`freezeBolt` at (k + 0.7) / 30 s, the game's measured sampling phase; reload clip at k / 30 s).

| # | Moment | Footage | Game | Difference |
|---|---|---|---|---|
| M01 | Hip idle | f0005: muzzle ≈(645, 410), eyepiece (696.5, 615) 98 px | muzzle (648, 416), eyepiece (695.7, 611.4) 96.8 px | ≤ 6 px — MEASURED MATCH |
| M02 | First shot (flash) | f0009: rifle not moved; flash glow at the muzzle; tan light on +1 (f0010) | rifle not moved; flash + orange light on the same capture | light 1 frame early, more saturated on the bright floor — VISUAL MISMATCH |
| M03 | Recoil peak | f0011 (+2): muzzle −81 / −62 (shot 56) | engine peak −67 px at 76–93 ms; capture (~60 ms) −50 | within the footage's two shots |
| M04 | Recovery | f0014 (+5): muzzle −34 | −33 | MEASURED MATCH |
| M05 | Bolt start | f0021 (+12): eyepiece (625, 580), muzzle (560, 400) | (625, 578), (562, 408) | ≤ 8 px |
| M06 | Bolt mid | f0028 (+19): (615, 625), (550, 420) | (617, 627), (553, 428) | ≤ 8 px |
| M07 | Bolt completion | f0038 (+29): (595, 570), (530, 405) | (605, 571), (541, 414) | ~10 px |
| M08 | Scope entering | f0402 (4 of 6 frames): ring 175 px at (661, ≈421), reticle visible | ring 174 px at (649, 416); lens dark | 12 px left; lens dark (eye-box model) vs reticle already visible — VISUAL MISMATCH |
| M09 | Fully scoped (6x) | f0420: ring (644, 355) 200 px, lens 116 px | ring (640, 360) 194.8 px | ≤ 5 px; our bolt handle shows right under the scope — VISUAL MISMATCH (placeholder model) |
| M10 | Scoped shot | f0427: ring ×1.8, centre −284 | engine +18 ms ×1.71, −268; capture (~+33 ms) ×1.33, −200 | peak MEASURED MATCH; captures land after it |
| M11 | Scope kick | f0428 (+1): ring centre −147, lit tan | capture ≈ −164, ×1.03, orange light | ≈ 17 px |
| M12 | Scope recovery | f0435 (+8): ring −34 (shot 427; the 6-shot median at +8 is −18); right arm entering | +8: −10..−17; right arm entering | ≤ 8 px vs the median |
| M13 | Reload start | f0118 (+5): eyepiece (790, 505), muzzle ≈(700, 418) | (790, 518), (681, 426) | ≤ 20 px |
| M14 | Magazine removal | f0144 (+31): eyepiece (890, 660), muzzle (710, 400); silhouette 44.9k px² | (871, 651), (708, 404) | ≤ 20 px; the footage rifle covers ~2× the area (closer / seen from the side; depth not solvable from two points) — VISUAL MISMATCH |
| M15 | Magazine insertion | f0200 (+87): eyepiece ≈(1020, 650), muzzle (720, 375); 62.0k px² | (987, 633), (713, 379) | ≤ 35 px; same area difference — VISUAL MISMATCH |
| M16 | Reload complete | f0238: rest (muzzle top 411) | rest exactly (0.000 studs / 0.000°) | match; the footage then sinks ≈30 px (P5, UNKNOWN, not built) |

Everywhere: the footage is a dark bodycam grade (night sky, grey floor); the Roblox scene is bright, so the block arms
read white and the rifle black. Not a mismatch of the slice.

### Full regression (same playtest as the visual validation, final scripts; `allowClientTeleports` on)

| Area | Result (baseline: `Roblox/Tests/Glock/README.md`) |
|---|---|
| BodyState | unit 42 / 42; real shots M4 6 / 6, AK 6 / 6; forged: INJURED, health 100, the server's own leg hit — match |
| Ballistics | unit 10 / 10 per lane for both rifles (budgets 1.75 / 1.249 / 2.0, end z 91 / 91 / 131); real shots 18 / 18 (drops A 6, B 6, C 0) — match |
| Hit reactions / ragdoll | M4 6 / 6, AK 6 / 6; dying states 11 / 11; tamper pass — match |
| Blood | M4 14 / 14, AK 14 / 14; dead hit pass; world pass (fewer lane shots this run: 1 / 1 / 14); security pass; orphans 0 — match |
| Body interaction | pulse 3.013–3.019 s client (REACT1–4 "strong, rapid", REACT5 / bled-out REACT6 "No pulse"); far / 8 invalid / interrupt 1.68 s / forged / local state; death → "Interrupted (player dead)"; drag 9.06 studs, 5.6 restored, trail 11 points; "too far" 0.718 s; already held; tamper; orphans 0 — match (**known exception:** `WalkSpeed == 16` reads 5.6) |
| AK | 640 RPM; hip climb 1.236°; raised 0.129 / 0.288 s; magazine 31, climb 1.947°; reloads 2.432 / 1.663 / 3.133 / 2.767 s; label 1.068 s; sequence, repeat, refusals, switch, repeated — match |
| M4 | 770 RPM (13 in 1 s, server 17 + 1); ADS in 0.333 / 0.331 s, out 0.119 / 0.123 s; ADS recovery 0.74 s; hip recovery 0.742 s; de-cant −32.575° → 0.053°; 0 late shots; reloads 3.532 / 3.065 / 3.699 / 3.599 s; Stressed sway roll 3.448° (known to vary) |
| M4 HUD | 13 checks, 0 mismatches; label 1.703 / 1.734 / 1.604 s; "+1", "+2" — match |
| Death / respawn | killed 2.0 s into an AK empty reload → "cancelled (died) after the magazine change"; respawn 3.273 s; M4 HUD agrees (30 + 1), M4 fires — match |
| Original reload test | M4AnimTest plays 3.531–3.542 s (play 1: 5.10 s at the session start hitch) — match |
| AI | perception 14 / 14, aiming 8 / 8, firing **11 / 11** (763 RPM; **first reading 10 / 11**, the failing check not captured, 3 reruns 11 / 11), integration 10 / 10; player as target **7 / 7** (**first reading 6 / 7**: P2 acquired 0.79 s after entering view), bot shoots player 5 / 5; M4 takedown 6 / 6; security 10 / 10 |
| Movement | rules 25 / 25; walk 5.600; crouch eye 2.700, 2.80 studs/s; jump +7.532; roll 1.399° / 2.699°; weapon lag 5.953° / 7.391° hip, 0.894° / 1.111° aiming — match |
| Optics | in 0.140 / 0.142 s, out 0.152 / 0.154 s; lens 162.4 px, ring 266.4 px, magnification 4.500; tracking 0.894° / 1.110°; shots 3 / 3; forged far / behind / NaN / wrong weapon rejected, fake hit and optic arguments plain shots; 0 client → server events while scoped — match; flags unchanged: roll while scoped 1.352° / 2.607°, up-vector 0.028° / 0.020° |
| MP7 | equip 40 + 1, FOV 70; idle p-p 0.000; 41 / 41 at 950 RPM (3 runs), climb 4.135–4.146°, 1.63° after 26 frames; shake 0.47–0.61°, roll sd 0.44–0.55°, muzzle Δx 8.1–15.3 px (random; the baseline ranges overlap); tap 1; ADS 0.251 / 0.148 s; reloads 3.270 / 4.936 / 2.107 / 3.407 s, end pose 0 / 0; PenWall 2.00 → 0.94 → 0.67 at a 20° angle (baseline 1.0 / 0.75 straight on), SolidWall stops at entry; forged: rejections as before, rate 3 / 9, 2000 RPM 20 / 13 (baseline 19 / 14) |
| Glock smoke | hold 1 s → 1 shot; 16 presses → 16 / 16, 0 + 0; empty → 2 shots, locked; empty reload 3.404 s, swap 2.170, slide released 2.669 s; switch cycles: one viewmodel per equip — match |
| Grenade (last) | fuse 4.0003–4.0039 s over 9; release ≈ 0.15 s; "already throwing", "NO FRAGS LEFT"; forged actions refused (8 unknown actions); consecutive throws clean; player health 100 — match |
| Console | 0 errors from game code (server and client); 1 test-tool error from my own wrong argument to `AITest.Run.playerChecks`; warnings only the expected security rejections |

**Separate, not changed (as instructed):** the M4 Stressed reload end-pose discrepancy (3.746° tactical, 4.034° empty
this run).

### Performance

| Measure | Result |
|---|---|
| Client frame, Sniper idle at the hip | 4.39 ms (p95 4.89) |
| Client frame, scoped | 4.79 ms (p95 5.30) |
| Instances over the tests | flat |
| Server shot cost (100 shots) | mean 0.77 ms, max 1.79 |
