# AI / bot combat vertical slice: tests

**Scope:** one bot sees, aims, shoots, hits, reacts, dies, through the accepted systems only. Nothing else (no
navigation, cover, squads, grenade AI, vehicles, civilians, other weapons).

**Basis:** `ReferenceAnalysis/AI/AI_Analysis.md`. No bot ever fires in the reference, so every combat number is a
PLACEHOLDER (`Shared/Config/AI.luau`).

## Pieces under test

| Piece | Where | Role |
|---|---|---|
| Shared shot | `Server/WeaponShot.luau` | WeaponServer's post-validation steps, moved unchanged: trace from the shooter's own head → BodyState / placeholder damage → Blood.Impacts → Ballistics.record. Players and bots both call it |
| Bot brain | `Server/AI/AIServer.server.luau` | one Heartbeat loop for all bots; state machine; publishes `AIState` / `AITarget` / `AIMag`; Studio `AIDebug` hook |
| Perception | `Server/AI/Perception.luau` | team, validity (Humanoid + BodyState), range, field of view, line-of-sight raycasts |
| Weapon adapter | `Server/AI/BotWeapon.luau` | the M4 config + shared `Ammo` rules: 770 RPM, 30 + 1, Regular reload timings; calls WeaponShot |
| Rifle | `Server/AI/BotRifle.luau` | black rifle welded to the right hand, outside the bot model; let go 0.3 s after the body goes down |
| Facing | `Server/HitReaction.luau` (additive) | a model with `BodyFacingYaw` stands turned to that yaw; nothing changes without it |
| Muzzle flash | `Client/AI/BotMuzzle.client.luau` | flash + light at the rifle muzzle when the server shot counter rises |
| Template, range | `ServerStorage.AITemplates.AIBOT`, `Workspace.AITest` | built by `build_range.luau` (this folder) |

## Range (`Workspace.AITest`, x −700 … −800)

It is 160+ studs from every other range, and bot range is 120.

| Item | Position (feet) | Use |
|---|---|---|
| BOT1 (demo bot, Red) | (−800, 0, 100), facing +X (toward the spawn side) | live demo; the tests disable it |
| BotPad | (−740, 0, 150) | test bots, facing +Z |
| SpotOpen | (−740, 0, 180) | 30 studs ahead, in the open |
| SpotCover | (−760, 0, 180) | behind WallA (8 × 8 × 1 at (−752, 4, 170)) |
| SpotSide | (−780, 0, 150) | 90° to the bot's side (outside the 120° field of view) |
| SpotFar | (−740, 0, 290) | 140 studs (outside the 120-stud range) |
| SpotFriend | (−735, 0, 170) | friendly target |

## Running

Start a playtest. The tests disable BOT1 and use bots named `T_*`. `Run.cleanup()` removes them and re-enables BOT1.

```lua
-- Server
local Run = require(game.ServerScriptService.AITest.Run)
Run.perception()  Run.aiming()  Run.firing()  Run.integration()   -- each returns { passed, total, checks }
Run.performance(8, 3)

-- player as target: Server
Run.setup()
Run.bot("T_PL", Vector3.new(-740, 3, 150), 180, { HoldFire = true, Seed = 9 })
Run.watchStart("T_PL", 30)
-- Client
local C = require(game.Players.LocalPlayer.PlayerScripts.AITest.Run)
C({ path = { { at = Vector3.new(-780, 0, 150), face = bot, hold = 1.5 }, { at = Vector3.new(-740, 0, 180), face = bot, hold = 1.5 },
  { at = Vector3.new(-780, 0, 150), face = bot, hold = 1.5 }, { at = Vector3.new(-760, 0, 180), face = bot, hold = 2.0 },
  { at = Vector3.new(-740, 0, 180), face = bot, hold = 1.5 } } })        -- returns moments
-- Server
Run.playerChecks("T_PL", moments)
Run.playerShot("T_PL")

-- the player's M4 takes a bot down
-- Server
Run.setup(); Run.bot("T_V", Vector3.new(-740, 3, 150), 0)
-- Client
C({ shootBot = { bot = "T_V", at = Vector3.new(-740, 0, 170) } })
-- Server
Run.shotDown("T_V")

-- security (the player hidden behind WallA at (-760, 3, 180); a firing bot T_SEC on BotPad)
-- Server
local before = Run.securityBefore("T_SEC")
-- Client
C({ security = { bot = "T_SEC" } })
-- Server
Run.securityAfter("T_SEC", before)
```

## Results (final scripts, one fresh playtest)

### Summary

| Suite | Result |
|---|---|
| Perception | **14 / 14** |
| Aiming | **8 / 8** |
| Firing | **11 / 11** |
| Integration | **10 / 10** |
| Player as target | **7 / 7** |
| Bot shoots the player | **5 / 5** |
| Player's M4 takes a bot down | **6 / 6** |
| Security | **10 / 10** |
| Console | 0 errors |

### Perception

- Open target: seen.
- Behind WallA: "blocked". The same spot is visible once the wall is removed on the server.
- Field of view:
  - side (90°): "fov", while the line itself is clear;
  - 55°: seen;
  - 65°: "fov".
- 140 studs: "range".
- Never fought: a friend (Red), a DYING body, itself.
- Enabled with only a friend and a dead body in view: SEARCH, 0 shots.
- A new enemy is acquired 0.203 s after it appears (one scan, 0.2 s).
- A removed target is dropped. One behind the wall is never acquired.

### Aiming

Target 50° off the facing:
- Body turned 50.0° at 244 °/s. The aim converges at 240 °/s and the body follows it.
- Aim error 0.028° (fire tolerance 3°).
- The root's look matches the server yaw (0.0°), so the accepted HitReaction applied `BodyFacingYaw`.
- Aim pitch −1.9° (down to the chest) while the root stays level.
- The rifle turned with the body (0.0°).
- States: SEARCH → ACQUIRE → AIM → FIRE, with fire held.
- Seeded scatter: two bots with the same seed give the same per-shot error (1.205 / 1.222 / 1.113°), inside the 1.5° cone.

### Firing

- Reaction:
  - acquisition → first round 0.709–0.714 s (0.6 s reaction + 0.1 s aim settle + frame).
  - The round is traced from the bot's own head (offset 0).
  - Ballistics record `{ Player = "T_F", Weapon = "M4", Bot = "T_F" }`.
- Rate: 761.7 RPM inside bursts (23 gaps, Heartbeat-quantised; the M4 is 770).
- Bursts: 3–5 rounds, pauses 0.358–0.644 s.
- Reload:
  - 31 rounds (30 + 1), then EmptyRegular for **3.701 s** (the M4 value is 3.70).
  - No round during the reload.
  - After it: 30 loaded, the empty magazine dropped, one spare left.
- Non-body target: the placeholder 25 per round (50 to the head), the same as a player's shot at a player.
- The rifle's shot counter equals the shots fired (the client flash source).
- Empty with no reserve: no reload, no shot.

### Integration

- **Bot vs a body** (the accepted REACT1):
  - BodyState hits (chest → DYING; a second round reached the head).
  - The flinch was seen, then the active ragdoll.
  - Blood through the existing Impacts: stains 4, marks 7–9, drops 5–7, pool 1.
  - The bot stopped firing the moment the body was down (0 rounds after).
- **Hold fire while hit:** a hit on the bot through BodyState's own entry opened `BodyReacting`. The bot held 72 shots'
  worth of frames.
- **Bot vs bot:**
  - Each acquired the other.
  - Red's first two rounds put Blue down (Blue was still in its reaction delay).
  - Blue went DOWN and fired nothing after.
  - Blue's rifle was let go **0.302 s** after it went down (MEASURED range 0.2–0.5).
  - Red returned to SEARCH.
  - Blue's body stays: DYING / DOWN / CHOKE.

### Player as target

The path is side → open → side → behind the wall → open.

- Side (outside the field of view): not acquired.
- Open: acquired 0.15 s after the move.
- Reaction 0.603 s.
- Back to the side: the held target was kept and tracked (body yaw 89.96°, wanted 90°).
- Behind the wall: lost 0.32–0.39 s after the server saw the player there. No round fired while lost.
- Open again: reacquired, then the next shot was allowed after **0.502 s** (reacquire delay 0.5).

### Bot shoots the player

- 4 hits for 25 each.
- Real Humanoid death 0.81 s after the bot was released.
- The bot went back to SEARCH.
- No creator tag.
- The existing respawn worked.

### Player's M4 takes a bot down

- Two real M4 rounds went through BodyState: Lung, then Throat → DYING.
- The AI went DOWN, with its target and reload cleared.
- The rifle was let go 0.302 s later.
- No bot round fired after.
- The accepted active ragdoll took over.

### Security

There is no AI remote at all. The forged inputs were:
- `AIState` / `AITarget` / `AIMag` / `AIReloading` / `BodyFacingYaw` / `AIAim` / `BodyPhase` / `BodyStance` / `BodyLife`
  / `BodyStrength` set locally;
- the root turned locally and Health 0 set locally;
- the commands `BotFire` / `AIFire` / `AITarget` / `AIAim` / `AIDirection` / `AIReload` and BodyInteract `Kill` / `Drag`;
- a WeaponFire from the bot's head (rejected: "origin 35 studs from head");
- WeaponFire with a hit point / part / damage 10000 (rejected: "direction behind the shooter");
- WallA removed locally.

On the server, none of it changed the bot's state, target, yaw, aim, ammunition, reload, body state or line of sight.

## Regressions

One fresh playtest with the final scripts (90 / 90 identical to the mirror). BOT1 was live throughout: it stayed in
SEARCH with 0 shots and was never hit.

| Area | Result |
|---|---|
| BodyState | unit 42 / 42; real shots M4 6 / 6, AK 6 / 6; forged requests rejected (BODY1 only the server's leg hit, INJURED, health 100) |
| Ballistics | unit 10 / 10 per lane for both rifles (sequences, budgets left 1.75 / 1.249 / 2.0, end z unchanged); real shots 18 / 18 (A / B 25 damage, C 0). These go through the new `WeaponShot` path |
| Hit reactions / ragdoll | M4 6 / 6, AK 6 / 6; dying states (synthetic) 11 / 11; tamper pass. Fall stages REACT2 / REACT4: support loss 0.26 / 0.28 s, down 0.76 / 0.74 s, still 1.42 / 1.57 s (REACT2's 1.42 is 0.05 s under the earlier 1.47–1.78 range; ActiveRagdoll is byte-identical, so this is run-to-run physics) |
| Blood | M4 14 / 14, AK 14 / 14; dead hit (DEAD, no bleed); world (4 / 4 / 23); security pass; orphans pass |
| Body interaction | pulse: REACT1–4 and 6 alive → "strong, rapid", REACT5 and REACT6 after bleeding out → "No pulse", 3.014–3.039 s client; far / invalid / interrupt (1.69 s) / forge / local state as before; death during a check → "Interrupted (player dead)"; drags 9.16–9.21 studs, trails 10–14 smears (worst off-path 0.03–0.97), "too far" at 0.75 s, invalid refusals, "already held", tamper (marks unchanged, torso y 0.49); client-owned parts 0; orphans pass |
| Grenade | fuse 4.0013–4.0038 s, release 1.49, launch 55, 600 fragments, server-owned throughout; wall 376 / 219 (5 fragments into the thrower: no player damage), lob 303 / 297, steep 3 floor bounces, room 551 / 39; timing (0.30 s refused, 0.45 s accepted); "NO FRAGS LEFT"; bodies via BodyState, one blood batch of 24 body events; forged: 10 refusals, the real throw detonated at 4.0013 s; 3 in a row: 3 detonations, 3 fx, no leftover grenade parts |
| AK | 640 RPM; climbs 1.236 / 1.951 / 1.949°; raised 0.128 / 0.285 s, FOV 70; reloads 2.431 / 1.665 / 3.129 / 2.765 s, label at 1.067 s; label sequence / repeat; refusals; switch; repeated |
| M4 | 29 + 1; 770 RPM; hip and ADS magazines 31 rounds; recovery 0.739–0.775 s; stop; weapon reset 27 = 27; reloads 3.529 / 3.064 / 3.699 / 3.594 s; refusals, partial reserve, while aiming, switch during, repeated. Random-noise metrics spread run to run as before: ADS thirds 0.80–1.06 / 1.13–1.42 / 1.19–1.59° over 3 runs; Stressed sway roll max 2.75–3.50° over 4 runs (all client weapon scripts byte-identical) |
| M4 HUD | 13 checks, 0 mismatches (label at 1.704 / 1.735 / 1.602 s) |
| Death / respawn | killed during an AK empty reload: reload cancelled ("died", after the magazine change), respawn 3.37 s, AK 30 + 1 with 4 spares and no label, M4 HUD agrees, M4 fires |
| Original reload test | M4AnimTest runner 3.530–3.541 s |
| Console | 0 errors / 0 warnings from game code, server and client. One error in the server log came from a test command of mine (it formatted a returned number) |

**Separate, not changed (as instructed):** the M4 Stressed reload end-pose discrepancy is still there (1.73° tactical,
4.01° empty this run).

## Performance (Studio server, about 240 Heartbeats/s)

| Bots | Search (scans only) | Holding a target (line of sight + aim) | Firing |
|---|---|---|---|
| 1 | 5 scans/s, 28 µs each; loop 0.009 ms/frame | 9.7 line-of-sight checks/s (1 ray each), 31 µs; loop 0.022 ms/frame | 1.6 ms per shot (trace + BodyState + blood) |
| 4 | 20 scans/s, 22 µs; 0.016 ms/frame | 39 checks/s, 31 µs; 0.044 ms/frame | 1.4 ms per shot; worst frame 6.4 ms |
| 8 | 40 scans/s, 26 µs; 0.026 ms/frame | 79 checks/s, 29 µs; 0.073 ms/frame | 1.4 ms per shot; worst frame 10.5 ms |

The bot counts include the disabled BOT1.

- **Per-frame cost:** no per-frame raycasts. Scans are every 0.2 s and line-of-sight checks every 0.1 s, staggered
  across bots.
- **Worst frames:** they come from the test releasing all eight bots on the same frame, so every first round
  (trace + BodyState + blood + ragdoll start) lands at once. In play, acquisitions and reaction delays spread rounds over
  different frames.
- **Network:** one attribute change per shot (`AIShots` on the rifle). The bot body replicates through the accepted
  systems. Impacts and blood use the existing messages.
