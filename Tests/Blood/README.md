# Blood + impact effects: focused test

**Proves:** for the M4 and the AK, a body hit shows blood exactly where the server's own bullet trace hit, at the
location BodyHit labelled. It leaves persistent evidence:
- stains on the body;
- drops and splats on the floor and walls;
- a growing pool under a body that went down.

Surface hits show a grey puff.

Nothing a client sends can create, move or force any of it.

**Basis:** `ReferenceAnalysis/Blood/Blood_Analysis.md` (O1–O13, decisions tagged CONFIRMED / MEASURED / INFERRED /
PLACEHOLDER / UNKNOWN). Every number is in `ReplicatedStorage.Shared.Config.Blood`, tagged the same way.

**Checkpoint:** `Roblox/Scripts/Checkpoints/2026-11-06_blood_impacts` (before: `2026-11-06_before_blood`, identical to
`2026-11-06_hitreactions_fidelity`).

## Pipeline (no second hit system)

```
client WeaponFire (intent only: weapon, origin, direction)
  → Server.WeaponServer (validation)
  → Server.Ballistics.trace (from the server's own head)
  → damage / BodyHit / BodyState (unchanged)
  → Server.Blood.Impacts.onShot(player, weaponId, trace, damageResults)   ← new, presentation only, under pcall
      ├─ persistent marks: Stains (body parts), SurfaceMarks (floor / wall), on the server, replicated
      └─ Shared.Remotes.ImpactFx:FireAllClients(events)   server → clients only
            → Client.Blood.ImpactEffects → BodyHitEffect / WorldImpactEffect (pooled particles)
Server.Blood.BloodServer: Body* attribute change → DOWN + DYING / DEAD → Pools.start(model)
```

`Impacts` does no hit test, applies no damage and changes no state. Each body entry uses:
- the trace's own part and entry point;
- the trace's exit point on that part, if there is one;
- the entry surface's normal;
- the location label from BodyState's result for that hit.

`ImpactFx.OnServerEvent` only increments a counter, so the test can prove it was ignored.

## Pieces

| Piece | Where | Role |
|---|---|---|
| Data | `ReplicatedStorage.Shared.Config.Blood` | Colours, particle specs, mark / stain / pool sizes and budgets, all tagged; frozen |
| Remote | `ReplicatedStorage.Shared.Remotes.ImpactFx` (saved in the place) | Server → all clients, one call per shot holding all of that shot's entries |
| Events + marks | `ServerScriptService.Server.Blood.Impacts` | Walks the trace. **Body entry:** stains at entry / exit, 2–4 floor drops, and a splat on the next surface within 3 m behind, else on the floor 1–3 m behind. **Surface entry / penetrable exit:** a world entry |
| Pools | `ServerScriptService.Server.Blood.BloodServer` (Script) + `Pools` | When a body's stance is DOWN and its phase DYING or DEAD: one pool under the torso, growing r 0.3 → 2.4 studs over 30 s, then static |
| Surface marks | `Server.Blood.SurfaceMarks` + `Canvas` | Drops (with an optional tail) and splats (3–5 overlapping soft circles) drawn as Frames on a SurfaceGui. They sit on shared invisible 8 × 8-stud "patch" parts laid on the surface (no collision, no queries, no touch, no shadow), lifted 0.02 studs plus 0.002 per layer: no z-fighting. FIFO budgets |
| Body stains | `Server.Blood.Stains` | A Frame on a SurfaceGui on the hit part's own face (no parts, no physics), so it rides the ragdoll. Max 16 per body, oldest first |
| Client listener | `StarterPlayerScripts.Client.Blood.ImpactEffects` (LocalScript) | Checks the payload's types, dispatches; Studio hook `ImpactFxDebug` |
| Particles | `Client.Blood.EmitterPool` | Up to 24 attachment + emitter sets in Terrain, created lazily, reused round-robin, burst only (Rate 0) |
| Body effect | `Client.Blood.BodyHitEffect` | Spot → puff → mist → droplets + large drops away from the body; exit spray if the bullet left the part; bleeding mist on the part (4 s, then removed; max 24) unless DEAD |
| World effect | `Client.Blood.WorldImpactEffect` | Grey dust puff + chips along the normal; exit puff along the bullet |
| Server test | `ServerScriptService.BloodTest.Run` (copy `BloodTest_Server_Run.luau`) | `reset`, `report(weapon)`, `deadHit`, `world`, `snapshot` / `security`, `orphans` |
| Client test | `StarterPlayerScripts.BloodTest.Run` (copy `BloodTest_Client_Run.luau`) | `{ deadHit }`, `{ floor }`, `{ security }` (five fake attempts) |

**Compatibility edits (additive only):**
- `Server.Ballistics`: Enter / Exit events carry the surface `Normal`.
- `Server.WeaponServer`: one `require` and one `pcall(Impacts.onShot, …)` after damage, before `Ballistics.record`.

A failure in the presentation can't break a shot.

## How to run (Studio playtest)

```lua
-- Server
local B = require(game.ServerScriptService.BloodTest.Run)
local H = require(game.ServerScriptService.HitReactionTest.Run)
B.reset(); H.spawn(30)            -- clear all blood, fresh REACT1–6, clear the trace / body records
-- Client: real shots (the hit-reaction plan: arm, abdomen, throat, chest ×3, head, legs)
require(game.Players.LocalPlayer.PlayerScripts.HitReactionTest.Run)({ weapon = "M4" })
-- Server (wait ≈3 s so the downed bodies have pools)
B.report("M4")                    -- 14 checks; then the same with "AK" after B.reset(); H.spawn(30)
-- Client
require(game.Players.LocalPlayer.PlayerScripts.BloodTest.Run)({ deadHit = true })   -- server: B.deadHit()
-- Client: BallisticsTest lanes A / B / C              -- server: B.world()
-- Security: server s = B.snapshot() (after B.reset()); client Run({ security = true }); server B.security(s)
B.orphans()
```

## Results (2026-11-06)

### Body hits: M4 14 / 14, AK 14 / 14

| # | Check | M4 | AK |
|---|---|---|---|
| 1 | Every trace target in the range has a body effect at exactly the trace's own part and point (< 1e-4 studs) | 10 / 10 | 10 / 10 |
| 2–8 | Location → effect on that part with that BodyHit label, and a stain: REACT1 `rightarm` (RightUpperArm), REACT2 `abdomen` (LowerTorso), REACT3 `chest` / throat (UpperTorso), REACT4 `chest`, REACT5 `head`, REACT6 `leftleg` and `rightleg` | 7 / 7 | 7 / 7 |
| 9 | Repeated hits: REACT4 × 3 → 3 effects, 6 stains (entry + exit each) | pass | pass |
| 10 | Dying / dead: a pool under every downed body: REACT2 / 3 / 4 / 6 DYING, REACT5 DEAD | 5 / 5 | 5 / 5 |
| 11 | Hits on living / dying bodies bleed (`bleed = true`) | pass | pass |
| 12 | Blood on the floor: patches 0.032–0.050 studs above the baseplate top | pass | 42 marks |
| 13 | Blood on the wall behind the bodies (HitReactionTest backstop), at y 1.5–4.8 | pass | 7 marks |
| 14 | Ragdoll: stains stay on parts that moved > 1.5 studs since the hit; no parts were added to any body | 8 / 8 carried, 0 extra | 8 / 8, 0 |

### Other checks

| Test | Result |
|---|---|
| DEAD body hit (REACT5's head again) | effect shown, `bleed = false`, phase stays DEAD: **pass** |
| Floor shot (no body) | world NonPenetrable puff at y = 0, normal (0, 1, 0); **no blood placed** |
| Penetrable wall (lane B, 2 shots per rifle) | 4 entry puffs at z 130.2 and 4 exit puffs at z 129.8; the target behind still gets its body effect |
| NonPenetrable wall (lane C, 2 shots per rifle) | 4 puffs at z 131.0 (front face); no exit; nothing behind. With the 8 backstop hits behind lanes A / B: 12 NonPenetrable entries |
| Lane targets (A / B) | body effects, stains, drops. The backstop is ≈19.5 studs behind (beyond 3 m), so the splat goes on the floor behind |
| Death / respawn | no stains left on the player's old body; after respawn, 5 shots, 0 rejected, the listener is still alive |

Captures (`Captures/`):
- `first_look_overview.png`: wall splats, floor drops, pools, stains.
- `body_hit_strip.png` + `hit_burst/`: spot → puff → droplets → stain, about 50 ms apart.
- `bleeding_mist.png`.
- `wall_impact_strip.png` + `wall_burst/`: grey puff on the wood wall, no hole.

### Security: 5 / 5 attempts changed nothing on the server

| Attempt (client) | Server result |
|---|---|
| Fire `ImpactFx` claiming a bleeding hit on REACT1's torso | counted (`ClientCalls` 0 → 1), not acted on: 0 marks, 0 stains, 0 pools |
| `WeaponCommand` "SpawnBlood" / "Blood" with a part and a position | unknown commands: no effect |
| A real `WeaponFire` aimed at the floor, with extra arguments claiming a hit position, part and name on REACT1 | the server traced its own shot: one world NonPenetrable entry at y = 0; **no body entry**; REACT1 still ALIVE |
| Set `BodyPhase = DEAD`, `BodyStance = DOWN` on REACT1 locally | local only: no pool; the server's phase unchanged |
| Draw a `BloodStain_Front` SurfaceGui on REACT1's torso locally | the server sees 0 GUIs on that torso |

"Make another player bleed" and "choose the hit position" are the same case as rows 1 and 3. Body entries exist only
for parts the server's own trace entered. No remote takes a part, a position or a state.

## Performance

- **Client:**
  - Particles come from a pool of ≤ 24 emitter sets (11 created in the full run) and are emitted in bursts only.
  - Nothing is created per shot except one bleed attachment, which removes itself after ≈6.6 s (≤ 24 alive).
  - There is no per-frame code: everything is event-driven.
  - After the run: 0 bleed attachments left, 0 active.
- **Server:**
  - Marks are Frames on shared patches. One M4 run (10 shots) made 48 marks (36 drops, 12 splats) on 15 patches, plus
    5 pools: 20 parts in all, and 24 stains, which add no parts.
  - Budgets: 600 marks, 150 patches, 32 pools, 16 stains per body. Oldest first.
  - The pool growth loop runs only while a pool grows (4 Hz, 30 s), then stops. There is no loop per mark.
  - A destroyed surface takes its patches with it; a destroyed body takes its stains.
- **Network:** one `FireAllClients` per shot that hit anything. Marks replicate as ordinary instances.
- **Orphans (`B.orphans()`):** blood parts = patches + pools; 0 empty patches; 0 after a clear.

## Regressions (fresh playtest, final scripts)

| Area | Result |
|---|---|
| BodyState | unit 42 / 42; real shots M4 6 / 6, AK 6 / 6; forged requests rejected |
| Ballistics | unit 10 / 10 per lane (event sequences unchanged); real shots 18 / 18 (A / B 25 damage, C 0) |
| Hit reactions | M4 6 / 6, AK 6 / 6 (fall stages in their accepted ranges); synthetic 11 / 11; tamper pass (no ragdoll, no pool) |
| AK | equip; hip burst 640 RPM; raised; full mag 640 RPM, 31 shots; reloads 2.429 / 1.664 / 3.130 / 2.765 s; label; refusals; switch; repeated |
| M4 firing | 29 + 1; 770 RPM; ADS mag thirds 1.26 / 1.16 / 1.27, recovery 0.744 s; hip / stressed mags; weapon reset |
| M4 reloads | 3.530 / 3.066 / 3.697 / 3.599 s; partial reserve, while aiming, switch during, repeated |
| M4 HUD | 1.702 / 1.735 / 1.601 s; 0 mismatches |
| Death / respawn | respawn 3.65 s; equip and fire after respawn |
| Console | no errors, no `[Weapon] impact presentation failed` |

**Separate, not fixed (as instructed):** the M4 Stressed reload end-pose discrepancy is still there (pose rotation
2.93° on the tactical Stressed clip this run).

## Placeholders and remaining mismatches

- **PLACEHOLDER:**
  - every particle count, size, speed and lifetime;
  - the bleeding mist's duration and rate;
  - drops per hit and their spread;
  - splat and stain sizes;
  - pool size and growth;
  - all budgets;
  - the colour values (only their darkness relative to the floor is measured).
- **INFERRED:**
  - droplets thrown along the entry normal;
  - the exit spray;
  - spatter on the next surface within 3 m;
  - the penetrable-exit puff.
- **UNKNOWN, so not built:**
  - screen blood (seen in one clip only, trigger unknown);
  - bullet holes and ricochets;
  - an exit-wound look;
  - per-weapon or per-location differences;
  - Penetrable vs NonPenetrable look differences.
- **Out of scope:** drag trails. `SurfaceMarks.trail(from, to)` exists, but nothing calls it.
- **Mismatches:**
  - Pools start when the body is down, not from a measured bleed rate.
  - The pool shape is a static five-lobe blob, so it does not follow the body's outline.
  - Splats are overlapping hard-edged circles; the footage's are soft-edged and irregular.
- **Players:** a player character the server's trace hits gets the same body effect and stains (any humanoid). Pools
  only follow BodyState bodies, because players are not integrated with BodyState.
