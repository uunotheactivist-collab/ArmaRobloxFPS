# Player movement + first-person presentation: tests

Evidence and decisions: `ReferenceAnalysis/Movement/Movement_Analysis.md`. Values: `Shared.Config.Movement`.

## Pieces

| Piece | Script | Role |
|---|---|---|
| Config | `ReplicatedStorage/Shared/Config/Movement.luau` | every value tagged MEASURED / CONFIRMED / INFERRED / PLACEHOLDER / UNKNOWN |
| Rules | `Server/Movement/MovementRules.luau` | pure: speeds per stance, travel budget, rise limit, state transitions, intent validation |
| Authority | `Server/Movement/MovementServer.server.luau` | stance and state attributes, WalkSpeed / JumpHeight / HipHeight, 10 Hz validation, intent remote, Studio `MovementDebug` |
| Client | `Client/Movement/MovementController.client.luau` | input easing, crouch key (C) with prediction, eye height, camera roll, steps the presentation, Studio `MovementClientDebug` |
| Presentation | `Client/Movement/MovementPresentation.luau` | look lag, walk bob, roll (shared state); the weapon controller applies its viewmodel offset |
| Toast | `Client/Movement/CrouchToast.luau` | "CROUCHED", bottom left |
| Weapon (changed) | `Client/WeaponController.client.luau` | one `require`, one multiplication in front of the rig's base CFrame |
| Remote | `Shared.Remotes.MovementIntent` | client → server intents only ("Crouch", boolean) |
| Range | `Workspace.MovementTest` (`build_range.luau`) | x 200–301, z −140…−48, away from every other range |
| Tests | `ServerScriptService/MovementTest/Run.luau`, `StarterPlayerScripts/MovementTest/Run.luau` (copies here) | Studio only |

## Range

| Lane (z) | Content |
|---|---|
| −130 | SpeedLane, markers every 10 studs (x 210–290) |
| −115 | Slope (4 high over 7 studs, 29.7°) to SlopeTop (4 high) |
| −100 | Stairs (8 × 0.75 high, 1.5 deep) to the Ledge (6 high), LandingPad below |
| −85 | Curb 0.6 high, LowBlock 2.0 high |
| −70 | Wall at x 240 with a 4 × 7 doorway |
| −55 | CrouchTunnel: 4 wide, ceiling underside 3.2 (x 230–242) |
| x 300 | End wall across all lanes |

## Running

```lua
-- Server
local M = require(game.ServerScriptService.MovementTest.Run)
M.unit()                 -- 25 rule checks
M.place("lane")          -- server placement (resets the validator's baseline): lane, slope, stairs, ledge, obstacles, door, tunnel, inTunnel, wall, start
M.watchStart(30)  M.watchStop()  M.status()  M.events(since)
-- Client
local C = require(game.Players.LocalPlayer.PlayerScripts.MovementTest.Run)
C({ move = { dir = Vector3.new(1, 0, 0), seconds = 4, after = 1.5 } })     -- a held stick, then release
C({ turn = { rate = 20, seconds = 1.5, after = 2.5, aim = false, move = nil } }) -- constant camera turn + weapon log
C({ crouch = true })  C({ jump = true })  C({ record = 0.5 })  C({ state = true })
C({ forge = "speed" | "teleport" | "fly" | "noclip" | "hover" | "nan" | "attributes" | "intents" | "deadMove" })
```

**Running the older suites with this slice in:** they place the player by client-side teleports, which the movement
validator now (correctly) moves back. For those runs, switch on the Studio-only allowance from the server:
`require(game.ServerScriptService.MovementTest.Run).dbg("allowClientTeleports", nil, true)`. Clients can't reach it.
It only exists in Studio.

## Results (final scripts, fresh playtests 2026-11-07)

### Movement (18 required tests)

| # | Test | Result |
|---|---|---|
| 1 | Spawn state | STAND / IDLE, WalkSpeed 5.6, JumpHeight 7.2, 0 rejections; eye 4.050 studs, FOV 70, roll 0, one viewmodel (4 / 4 + camera) |
| 2 | Walking speed | steady **5.605 studs/s** (target 5.6, MEASURED); the server saw 5.75 (30 Hz sampling of replicated positions); never above 5.600 |
| 3 | Acceleration / deceleration | 63 % at 0.109 s, 90 % at 0.237 s; stop: below 10 % at 0.237 s, at rest 0.481 s. Real keyboard (W) through the default controls: 63 % at 0.104 s, top 5.600, eases back to 0 |
| 4 | Direction changes | reverse: through zero at 0.078 s, 90 % the other way at 0.307 s; 90° change: 90 % at 0.240 s |
| 5 | Sprint | **not built** (UNKNOWN in the footage). A "Sprint" request is refused; no state or speed changes |
| 6 | Crouch | server confirms in 0.016 s; eye 4.05 → 3.78 (0.05 s) → 3.37 (0.125 s) → **2.70 at 0.25 s**; WalkSpeed 2.80 (crouch walk measured 2.807); hip 1.80 → 0.45, body lowered 1.35 (upper torso 2.81 → 1.46, head 4.00 → 2.65, the same on the server). Toast "CROUCHED": shown at 0.017 s, fade from 1.552 s, gone at 1.814 s (config 1.533 + 0.267); none on standing. Tunnel: standing stops at x 229.3 (mouth 230); crouched passes (x 241.9); standing up inside is refused ("no room to stand") and the client reverts within 0.4 s; outside it stands (eye back to 4.05 at 0.25 s) |
| 7 | Jump (engine default, PLACEHOLDER) | apex +7.53 studs at 0.276 s, back down 0.555 s; server JUMP → FALL → LAND (0.2 s) → IDLE; 0 rejections |
| 8 | Fall | off the 6-stud ledge: dropped 6.20 studs in 0.20 s; server WALK → FALL → LAND → WALK → IDLE; 0 rejections |
| 9 | Landing | eye 4.050 within 0.1–0.7 s after touching down (no dip: none is shown in the footage); LAND lasts 0.2 s |
| 10 | Camera state | eye 4.050 standing on flat floor, while walking and after landing; on the slope within 0.141 of floor + 4.05 (eased floor); stairs: largest one-frame camera rise 0.062 studs (0.750 before easing); camera pitch constant while walking (no bob); FOV 70 hip / 62.23 ADS unchanged; roll 1.394° at 20 °/s right (expected 1.400), −2.689° at 60 °/s left (clamp 2.7), back to 0 after; the final camera's horizon dips to the right in right turns, as in the footage |
| 11 | Weapon stays attached | left arm relative to the weapon ≤ 0.00006 studs, 0.000°; magazine ≤ 0.00005 studs (turns, walking + turning, ADS). Weapon vs camera: 5.95° (20 °/s), 7.39° (60 °/s, clamp 7.4), 8.39° (walk + 25 °/s), **1.11° aiming** (x0.15); back to the stationary pose after |
| 12 | M4 regression | pass (below) |
| 13 | AK regression | pass (below) |
| 14 | BodyState regression | pass (below) |
| 15 | AI targeting regression | pass (below); a crouched player is acquired and hit at the lowered body (4 hits, 3 on the UpperTorso) |
| 16 | Death disables movement | MoveState DEAD, WalkSpeed 0, JumpHeight 0; a held input moves 0.000 studs; crouch request refused ("dead") |
| 17 | Respawn restores movement | bound 3.36–3.42 s after death; STAND / IDLE / 5.6 / 7.2; walk 5.603 studs/s, crouch and stand work, eye 4.05, one viewmodel |
| 18 | Teleport / security | see Security |

Terrain: slope climbed at 5.60 studs/s along the surface to its top (4.0); stairs climbed to the ledge (6.0); the 0.6
curb is stepped over; the 2.0 block stops the player at x 244.31; the doorway is passed (x 232 → 248.8); the end wall
stops the player at x 299.29. 0 rejections in every legitimate run.

State transitions are deterministic: rules 25 / 25 (speeds, budget, rise limit, every state transition including LAND
timing, settling into / out of a crouch without a FALL, walk hysteresis, every intent case). Pressing against the
tunnel's ceiling edge gives WALK → IDLE with no flicker (walk starts above 1.5 studs/s, ends below 0.5).

### Security (all with the Studio allowance off)

| Forgery | Server result |
|---|---|
| Client WalkSpeed 40 for 1.5 s | 4 rejections ("too fast"); server WalkSpeed stays 5.6. The client gained 10.48 studs in 1.5 s against 8.4 legally: at most the 0.5 s jitter allowance, once. After a correction the allowance restarts at 0 |
| Teleport +40 studs | rejected, moved back (0.68 studs from the start) |
| Teleport +30 studs up | rejected ("too high") |
| Flying (40 studs/s up for 1.2 s) | 4 rejections ("too high"), back on the floor |
| Through the end wall (+6 studs) | rejected ("through a wall: Workspace.MovementTest.Wall"), stays at x 298.8 |
| Hovering (local HipHeight +3) | rejected ("hovering") |
| NaN position | no effect |
| Local `Stance` / `MoveState` / `MoveRejections` / `MoveLocked` | never reach the server (server still STAND / IDLE) |
| "Sprint", "Crouch" with "yes" / NaN, a table verb, extra arguments | refused (sprint not built / bad value / unknown request); extra arguments ignored |
| 30 requests in one burst | 6 accepted per second, the rest "refused: rate" |
| Requests while dead | refused ("dead"); no movement |
| Crouch while dragging a body | refused ("locked: Interaction"); the drag's own WalkSpeed 9 untouched, 5.6 handed back after |

### Full regressions (one fresh playtest, final scripts, client-teleport allowance on)

| Area | Result |
|---|---|
| BodyState | unit 42 / 42; real shots M4 6 / 6, AK 6 / 6; forged requests rejected (INJURED, health 100, the server's leg hit only) |
| Ballistics | unit 10 / 10 per lane for both rifles (budgets 1.75 / 1.249 / 2.0, end z 91 / 91 / 131); real shots 18 / 18 (target drops A 6, B 6, C 0) |
| Hit reactions / ragdoll | M4 6 / 6, AK 6 / 6; dying states (synthetic) 11 / 11; tamper pass |
| Blood | M4 14 / 14, AK 14 / 14; dead hit (DEAD, effect, no bleed); world pass; security pass; orphans pass |
| Body interaction | pulse 3.013–3.018 s client ("strong, rapid" alive; "No pulse" for REACT5 and for REACT4 / REACT6 after they bled out); far / invalid / interrupt (1.73 s) / forge / local state as before; death during a check → "Interrupted (player dead)"; drags 9.05–9.09 studs at the drag's WalkSpeed 9, walk speed restored; trails 11–14 smears (worst off-path 0.14–0.96); "too far" 0.72 s; invalid refusals; "already held"; tamper (blood marks unchanged, 0 client-owned parts); orphans: 0 grips / aligns / holds / trails / dragged attributes, **but the check's hard-coded `WalkSpeed == 16` reads 5.6** (the measured walk; the drag hands back whatever it found) |
| AK | equip; hip burst 640 RPM, climb 1.230°; raised 0.130 / 0.286 s, FOV 70; full magazine 31 at 640 RPM, climb 1.946 / 1.945°; reloads 2.431 / 1.664 / 3.130 / 2.765 s, label at 1.071 s; label sequence / repeat; refusals; switch; repeated |
| M4 | 29 + 1; hip burst 770 RPM; ADS and hip magazines 31 at 770 RPM; recovery 0.739–0.743 s; hip de-cant (idle −32.6° → firing 0.23°); stop (0 late shots); weapon reset 27 = 27; reloads 3.530 / 3.063 / 3.699 / 3.600 s; refusals, partial reserve, while aiming, switch during, repeated. Stressed sway roll max 2.25 / 2.07 / 1.85 / 3.33° over 4 runs (it reads the unchanged `Sway` output directly; random noise window) |
| M4 HUD | 0 mismatches; label at 1.701 / 1.734 / 1.604 s; "+1", "+2" |
| Death / respawn | killed 2.0 s into an AK empty reload: "cancelled (died) after the magazine change"; respawn 3.29–3.42 s; M4 HUD agrees (30, chambered); M4 fires |
| Original reload test | M4AnimTest runner 3.529–3.542 s over 178 plays (one 3.711 s play during a death / respawn hitch) |
| AI | perception 14 / 14, aiming 8 / 8, firing 11 / 11, integration 10 / 10; player as target 7 / 7 (first attempt 6 / 7: the opening teleport jumped ≈800 studs from the HUD test spot and reached the server late, so P2's "within one scan" timing missed; rerun from the range: acquired 0.19 s after the move, reaction 0.604 s, lost after 0.336 s, reacquire 0.501 s); bot shoots the player 5 / 5 (4 × 25, death 0.81 s, respawn); M4 takes a bot down 6 / 6; security 10 / 10 |
| Grenade | fuse 4.0017–4.0035 s; release 0.149–0.152 s; wall 371 / 224 (5 into the thrower: no damage), lob 303 / 297, steep 3 floor bounces, room 551 / 40; timing (0.31 s refused, 0.465 s accepted); "NO FRAGS LEFT"; bodies via BodyState (body 3 DEAD, Brain, 13 hits, 16 stains); forged: 10 refusals, the real throw detonated at 4.0023 s; 3 in a row: 3 detonations, no leftover parts; player health 100 |
| Console | 0 errors from game code (server and client). Logged errors came from my test commands (one arithmetic slip; two AI security calls before their bot existed). Warnings: the forged-shot rejections the AI security test expects; one "origin 8 studs from head" when a mistimed kill landed during an AK burst; infinite-yield warnings from my mistaken test calls |

**Separate, not changed (as instructed):** the M4 Stressed reload end-pose discrepancy is still there (0.95° tactical,
1.38° empty this run; earlier runs 1.4–5.1°).

## Performance

| Side | Cost |
|---|---|
| Client (MovementController camera / presentation step, per frame) | 0.044 ms mean standing, 0.054 ms walking; max 0.29–0.42 ms |
| Client input easing | only calls `Humanoid:Move` while easing (nothing when the input is steady) |
| Server (one 10 Hz timer for all players; sleeps when nobody is alive) | 0.041–0.045 ms per check per player; 1.0 ray per check standing, 1.6 walking (ground + path); ≈0.44 ms of server time per second per player |
| Network | no per-frame remotes; one intent per crouch press; character attributes change only on state changes |
