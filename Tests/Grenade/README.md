# Fragmentation grenade vertical slice: focused test

**Proves the loop, for one grenade type (the footage's frag):**
1. G throws (0.133 s release, 0.40 s throw).
2. The grenade flies, bounces and rolls as a real physics body.
3. The fuse runs 4.0 s on the server.
4. One detonation: sparks → flash + ground glare + light → tan dust on every client.
5. 600 fragment traces on the server.
6. Hits go into the accepted BodyState → HitReaction / ActiveRagdoll → Blood pipeline.

Everything that matters is the server's. A client only asks to throw, with an aim direction.

**Basis:** `ReferenceAnalysis/Grenade/Grenade_Analysis.md` (every item tagged CONFIRMED / MEASURED / INFERRED / PLACEHOLDER
/ UNKNOWN). Values: `ReplicatedStorage.Shared.Config.Grenade`, tagged the same way.

**Checkpoint:** `Roblox/Scripts/Checkpoints/2026-11-06_grenade_slice`. Before: `2026-11-06_before_grenade`, identical to
the accepted `2026-11-06_body_interaction`.

## Lifecycle (server)

```
READY ─G (client: "Throw", aim direction)─► checks: alive · grenades left · not already throwing · aim is a direction
  │                                          (|v| ≈ 1) and not behind the character
  ▼
THROWING  0.133 s wind-up [measured]  (the throw is over at 0.40 s [measured]; one at a time)
  ▼ release: point = the SERVER's head + a left-hand offset; velocity = aim × 55 studs/s; "FRAG OUT  xN" to the thrower
FLYING / BOUNCING / ROLLING   Roblox physics, server-owned, project gravity 35 studs/s²; the fuse runs on the server clock
  ▼ 4.0 s after release [measured 4.00–4.13 s]
DETONATED (once)  body removed → 600 traces (Server.Ballistics.trace, budget 0) → hits grouped per body part
                  → BodyState.applyHit per part (most severe wound first) → blood: Impacts.onBurst (one message)
                  → GrenadeFx to every client (one message)
CLEANUP           nothing left: no grenade parts, no loop (the Heartbeat exists only while a grenade is live)
```

## Pieces

| Piece | Where | Role |
|---|---|---|
| Data | `ReplicatedStorage.Shared.Config.Grenade` | Key, count, throw / body / fuse / fragment / effect / label values (tagged) |
| Remotes | `Shared.Remotes.GrenadeCommand` (client → server), `GrenadeState` (server → the thrower), `GrenadeFx` (server → all); saved in the place | Intent / count and label / one effect message per detonation |
| Server | `ServerScriptService.Server.Grenade.GrenadeServer` (Script) | State per player, timed throw, lifecycle loop, detonation, damage, blood hand-off. Studio hook `GrenadeDebug` |
| Throw | `Server.Grenade.Throw` | Aim check, launch from the server head, the grenade body (ball + yellow band, no collision with the thrower, gravity force, roll brake, server owner) |
| Fragments | `Server.Grenade.Fragments` | 600 directions (Fibonacci sphere, random turn), each traced with the accepted `Server.Ballistics.trace` (range 250, penetration 0); categories; hits grouped per part |
| Blood (additive) | `Server.Blood.Impacts.onBurst` | The same events and marks as `onShot`, for several traces, in one message. `onShot` behaves identically: its loop moved into a shared local function |
| Client | `StarterPlayerScripts.Client.Grenade.GrenadeClient` (LocalScript) + `FragOutLabel`, `ExplosionEffect`, `ThrowPresentation` | G input, label, pooled effect (4 rigs), first-person throw swing. Studio hook `GrenadeClientDebug` |
| Range | `Workspace.GrenadeTest` (`build_range.luau`, saved in the place) | PadOpen (−500, 0, 160) with open ground to +Z; WallA at z 140; a 10 × 10 roofless room centred (−540, 0, 150). Bodies: HitReactionTest REACT1–6, BodyStateTest BODY1–6 |
| Server test | `ServerScriptService.GrenadeTest.Run` (copy `GrenadeTest_Server_Run.luau`) | `reset`, `bodies`, `kill`, `left`, `detonations`, `path`, `body`, `blood`, `status`, `rejections`, `parts` |
| Client test | `StarterPlayerScripts.GrenadeTest.Run` (copy `GrenadeTest_Client_Run.luau`) | `throw`, `timing`, `noFrags`, `forged`, `multi` (real presses through the production client; fakes straight at the remotes) |

## How to run (Studio playtest)

```lua
-- Server
local R = require(game.ServerScriptService.GrenadeTest.Run)
R.reset()
-- Client (one throw each; wait ≥ 4.2 s before reading the server)
local Run = require(game.Players.LocalPlayer.PlayerScripts.GrenadeTest.Run)
Run({ throw = { at = Vector3.new(-500, 0, 160), dir = Vector3.new(0, -0.05, -1).Unit } })   -- wall
Run({ throw = { at = Vector3.new(-500, 0, 160), dir = Vector3.new(0, 0.45, 1).Unit } })     -- open lob
Run({ throw = { at = Vector3.new(-500, 0, 160), dir = Vector3.new(0.3, -0.6, 1).Unit } })   -- steep: floor bounces
Run({ throw = { at = Vector3.new(-540, 0, 152.5), dir = Vector3.new(0.25, -0.1, -1).Unit } }) -- confined room
-- Server
for _, d in R.detonations() do print(d.Id, d.Fuse, d.Summary, R.path(d.Id).FloorBounces, R.path(d.Id).WallBounces) end
-- timing: Run({ timing = { at, dir } });  no grenades: R.left(0) then Run({ noFrags = true })
-- bodies: R.bodies(); Run({ throw = { at = Vector3.new(-370, 0, 127), dir = Vector3.new(0, -0.55, -1).Unit } }); R.body(3)
-- forged: Run({ forged = { at, dir } }) then R.rejections();  several: Run({ multi = { at, dir, n = 3 } })
```

## Results (2026-11-06, final scripts, fresh playtest)

### Throw: 7 / 7

| Test | Result |
|---|---|
| Valid throw | Accepted. "Throwing" at +0.013–0.019 s, "Released" at +0.148–0.157 s from the press (0.133 s after acceptance), and "FRAG OUT  x4 … x1" shown at release |
| Preparation timing | Release 0.133 s after acceptance; the throw is over at 0.40 s. A second throw at 0.30 s is refused ("already throwing"); one at 0.45 s is accepted |
| Server-derived origin | Every release point is 1.49 studs from the server's own head (the left-hand offset), whatever the client sends |
| Server-derived direction / speed | Launch speed 55.00 studs/s every time, along the client's aim |
| Impossible origin | No remote takes one. A position sent instead of a direction (\|v\| = 50) is refused ("not a direction"); a position as an extra argument is ignored |
| Impossible velocity | A velocity sent instead of a direction (\|v\| = 900) is refused; as an extra argument it is ignored (launch still 55 studs/s) |
| Duplicate throw | Refused while throwing. With none left, the press is refused: "NO FRAGS LEFT", no throw animation |

### Fuse: 4 / 4

| Test | Result |
|---|---|
| ≈ 4.0 s | Every detonation: release → detonation **4.0000–4.0047 s** (server clock); footage 4.00–4.13 s |
| Client can't skip | "Detonate" / "SetFuse": unknown actions. A 0.1 s fuse sent with a real throw is ignored (that grenade: 4.0002 s) |
| Client can't extend | No remote carries a fuse; the timer is server-only |
| Authoritative after bounce | The server owned the grenade in every 30 Hz sample of every path. A client moving / flinging a live grenade locally (+40 studs, 200 studs/s): the server's path had no jump (largest step 2.74 studs) |

### Physics: 5 / 5

| Test | Result (final run) |
|---|---|
| Open ground | Lob 24° up: 3 floor bounces, rolls on, detonates ≈ 99 studs out (302 into the floor and walls, 298 clear) |
| Wall bounce | Straight at WallA (20 studs): 1 wall bounce, back 16 studs/s, 2 floor bounces, stops ≈ 8 studs from the wall |
| Floor / multiple bounce | Steep throw: 3 floor bounces; every throw bounced at least twice |
| Confined space | Inside the roofless room at a wall 5 studs away: 1–2 wall + 1–2 floor bounces, stays inside; 549–551 fragments into walls, 39–41 clear (up through the open top), the rest into the thrower (no damage) |
| Near a body | Thrown among REACT1–6: lands 7 studs in front of REACT3 (below) |

No teleports: the largest step between 30 Hz samples is 2.0–2.85 studs, which is the grenade's own speed × the sample interval.

### Detonation: 5 / 5

| Test | Result |
|---|---|
| Once | One detonation per grenade (`Detonated` flag; the body is removed first). Three grenades in a row: 3 detonations for 3 throws |
| Effects once | One `GrenadeFx` per detonation, one effect each on the client (12 → 15 plays for 3 grenades; no grenade id twice) |
| No duplicate explosions | As above; the forged "Detonate" is refused |
| No orphaned objects | After every test: `Workspace.Grenades` empty, no grenade loop, client effect rigs ≤ 4 (pooled) |
| No permanent parts | 273 parts before three grenades and 273 after, plus only the blood marks of body hits (3 patches + 1 pool for one far body hit) |

### Fragments: 6 / 6

| Test | Result |
|---|---|
| 600 | Exactly 600 traces per detonation |
| Spread | Per direction octant 71–80 (an even spread is 75), mean direction length 0.00001 |
| Environment collision | Every "into walls" fragment ends at its surface entry point (`WallStops` = into walls, e.g. 373 / 373). Categories: open ground ≈ 300 / 300 (floor vs sky); by the wall 373 walls / 226 clear; in the room 551 / 39; beside the bots and backstop 43 bodies / 420 walls / 137 clear (footage 5 / 457 / 138) |
| Valid body hit reaches BodyState | Every part reached → `BodyState.applyHit(…, "Grenade")` (below) |
| Fake hit rejected | "Fragment", "Fragments", "Hit", "Target", "Damage", "Result": unknown actions; BodyState and blood unchanged |
| No client damage | No remote accepts a hit, a target or damage |

### Body integration: 6 / 6

Grenade among fresh REACT1–6: lands at (−370.6, 0.11, 116.8); 600 FRAGMENTS / 24 INTO BODIES / 333 INTO WALLS / 243
CLEAR.

| Test | Result |
|---|---|
| Hit location | Each part reached is one BodyState hit with BodyHit's own label: head → Brain, chest → Lung, abdomen → Gut, arms / legs → Limb (R6 BODY bots too: "Right Arm" → rightarm) |
| BodyState changes | REACT3 and REACT4: a head fragment first → Brain, DYING, LIMP (they collapse in place, as the footage's debug clip shows). REACT2: four limb hits → legs gone → DYING / SHOCK. REACT1, REACT5: INJURED, standing. Later hits on dying bodies: "recorded only" (BodyState's rule) |
| Hit reaction | REACT1 / REACT5 flinch and stay standing (HitReaction); the "flinch" tag is seen in the captures |
| Blood | One blood batch per detonation (one message): 24 body effects, 24 stains, 70 floor drops; pools under the 3 downed bodies; at most 3 entries per part, 24 per grenade |
| Ragdoll | REACT2 / 3 / 4: root motor only, 14 joints, root unanchored, 0 client-owned parts |
| Dead body unchanged | A grenade by the DEAD REACT3: 37 fragments into it, every hit ignored ("dead", hit count 11 → 11), its 7 blood effects bleed = false, stains to the cap |

### Security: every forged input refused or ignored

| # | Forged input | Server result |
|---|---|---|
| 1 | Grenade position | No remote takes one; as a "direction": refused (\|v\| = 50); as an extra argument: ignored (release 1.49 studs from the server head) |
| 2 | Velocity | As a "direction": refused (\|v\| = 900); as an extra argument: ignored (55 studs/s) |
| 3 | Fuse | "SetFuse": unknown action; 0.1 s as an extra argument: ignored (4.0002 s) |
| 4 | Detonation | "Detonate": unknown action; a `GrenadeFx` fired by the client: counted, ignored |
| 5 | Fragment origin | "Fragment" with an origin: unknown action |
| 6 | Fragment direction | "Fragments" with directions: unknown action |
| 7 | Fragment hit position | "Hit" with a body and a point: unknown action |
| 8 | Fragment target | "Target" with a body: unknown action |
| 9 | Fragment damage | "Damage" 999: unknown action; REACT bodies unchanged |
| 10 | Explosion result | "Result" { IntoBodies = 600 }: unknown action; a `GrenadeState` "Detonated" fired by the client: counted, ignored |
| + | Live grenade moved locally | Server-owned: no change on the server |
| + | Aim behind the character | Refused ("behind the thrower") |

Before and after the forged set: REACT1–6 states, hit counts and blood marks are identical, apart from the one
legitimate grenade's single far hit on BODY6.

## Regressions (fresh playtest, final scripts)

| Area | Result |
|---|---|
| BodyState | unit 42 / 42; real shots M4 6 / 6, AK 6 / 6; forged requests rejected |
| Ballistics | unit 10 / 10 per lane for both rifles (event sequences unchanged); real shots 18 / 18 (A / B 25 damage, C 0) |
| Hit reactions / ragdoll | M4 6 / 6, AK 6 / 6; dying states (synthetic) 11 / 11; tamper pass |
| Blood | M4 14 / 14, AK 14 / 14 (the `Impacts` refactor changes nothing for rifles); dead hit; world (6 / 6 / 29); security 5 / 5; orphans |
| Body interaction | pulse 9 results, 3.0002–3.0040 s, mapping unchanged; far / invalid / interrupt / forged / local state; drag (head-away bodies turned 176° / −174°, dragged 9.2 studs), let go, too far, invalid, held, tamper; trails 10–11 smears along the path; no orphans |
| AK | 640 RPM; climbs 1.224 / 1.956 / 1.952; raised 0.116 / 0.283 s (the AimController is byte-identical; the earlier 0.127 is render-frame timing), FOV 70; reloads 2.420 / 1.651 / 3.124 / 2.766 s, label at 1.068 s; label sequence / repeat; refusals; switch; repeated |
| M4 | 29 + 1; 770 RPM; ADS thirds 0.88 / 1.30 / 1.46 and 1.20 / 1.15 / 1.50 (run-to-run spread as before), recovery 0.741–0.766 s; stop; weapon reset 27 = 27; reloads 3.527 / 3.054 / 3.698 / 3.587 s; refusals, partial reserve, while aiming, switch during, repeated |
| M4 HUD | 13 checks, 0 mismatches |
| Death / respawn | 3.31–3.42 s; a grenade thrown just before death still detonates once (4.0002 s); grenades back to 5; M4 fires; pulse check 3.015 s; all listeners alive |
| Console | 0 errors, 0 warnings in the retained log (server and client) |

**Separate, not changed (as instructed):** the M4 Stressed reload end-pose discrepancy is still there (2.31° tactical,
4.40° empty this run).

## Performance

- **Fragments:** 600 straight server raycasts (two where a body or penetrable part needs an exit probe), with no
  physics objects, no parts and nothing replicated per fragment. **2.4–4.2 ms** of tracing per detonation; **2.7–6.1 ms**
  in all, with hits, BodyState and blood. Three grenades 0.45 s apart: three separate frames of ≈ 3–5 ms each.
- **Live grenade:** 2 parts (body + band) plus constraints (≈ 16 no-collides with the thrower, a gravity force, a roll
  brake). All are removed at detonation, so a grenade adds nothing permanent.
- **Server loop:** one Heartbeat while any grenade is live (fuse and Studio sampling); it disconnects after the last
  detonation.
- **Network:**
  - "Throwing" + "Released" to the thrower, then one `GrenadeFx` to all per detonation;
  - at most one blood message per detonation (fragment blood batched, ≤ 24 entries, ≤ 3 per part);
  - the flying body replicates as ordinary server physics;
  - no per-frame and no per-fragment messages.
- **Client:**
  - up to 4 pooled effect rigs (an attachment with 3 emitters, a light and a billboard; no parts);
  - the throw swing's 2 camera parts are made once, and its render callback runs only during the 0.40 s throw;
  - the label is one TextLabel.

## Captures (`Captures/`)

- `explosion_sequence_strip.png`: 40 ms frames of three blasts. Flash (white-yellow, warm light on the wall), tan dust
  billowing and building into a haze; no camera movement.
- `dust_2_5s.png` / `dust_3_5s.png`: the dust is still clearly visible ≈ 2.5–3 s after a blast and gone by ≈ 4 s.

The frame-0 spark streaks last 2–4 game frames, so they fall between the 40 ms captures: they are in the effect but not
visually confirmed in a capture.

## Placeholders, unknowns, mismatches

- **PLACEHOLDER:**
  - G key; 5 grenades per life;
  - throw speed 55 studs/s and the hand offset;
  - body size, density, elasticity 0.35, friction 0.6, roll brake;
  - fragment range 250 studs;
  - penetration 0;
  - 10 damage per fragment for non-BodyState characters;
  - effect sizes and colours;
  - label offsets.
- **INFERRED:**
  - the fuse starts at release;
  - an even fragment spread over the sphere;
  - fragment hits grouped per part ("× 3") and applied most severe wound first;
  - fragment mass and speed meaning (recorded only).
- **UNKNOWN, so not built:**
  - hold / cooking (and its input);
  - bounce and roll behaviour (placeholder physics instead);
  - blast radius and falloff;
  - whether grenades hurt players (off);
  - blast push / flinging (the debug clip shows collapse in place, the normal clip a fling: no rule);
  - lever (spoon), fuse smoke, sound, the red edge tint, debug rays / sphere, fragment drag / lethality loss with
    distance.
- **Mismatches:**
  - The rifle isn't lowered during the throw, and firing isn't blocked during the 0.40 s throw. Either would change the
    accepted weapon controller / server.
  - The throw swing is a simplified hand + grenade, not the footage's arm model.
  - **Fragments are lethal out to the full 250 studs.** During the tests, fragments from the grenade range hit REACT
    and BODY bots 140–200 studs away. The footage shows rays crossing the whole map, but says nothing about lethality at
    range.
  - The lob rolls far after landing (≈ 35 studs at 50 studs/s); the roll is a placeholder.
  - Body hits from one grenade are one BodyState hit per part, so later parts on an already dying body are "recorded
    only" (BodyState's existing rule).

## Grenade fidelity slice (2026-11-08)

Reference and comparison: `ReferenceAnalysis/GrenadeFidelity/GrenadeFidelity_Analysis.md` (sections A–C; D = the results
below). New test module: `StarterPlayer.StarterPlayerScripts.GrenadeFidelityTest.Run` (copy `GrenadeFidelityTest_Client_Run.luau`):
`launch(pitch)`, `presentation()`, `label()`, `redEdge()`, `fragmentsHit()`, `security()`. Captures: `captures/`
(`cmp_throw_L0..L3.png` + `sheet_throw.png`, `cmp_label.png`, `cmp_red_edge.png`, `cmp_detonation.png`); footage frames:
`frames/`; edge redness metric: `edge_redness.ps1`. Studio hooks (GrenadeClientDebug): `freezeThrow` (t), `redEdge`,
`redEdgeHold` (strength).

### Fidelity (IMPLEMENTATION MEASUREMENT vs REFERENCE MEASUREMENT; 1280 x 720 picture, FOV 70, 30 fps)

| Behaviour | Implementation (final) | Reference | Difference |
|---|---|---|---|
| Release point (grenade at release) | (501, 127) at 1.5 studs | (490–507, 120–130) (M9) | ≤ 11 px |
| Launch direction vs the aim | 21° up / 11° left by construction; measured from the server path 18.9° / 11.0° (first 0.05 s of motion, gravity included) | ≈ 21° / 11° (M8) | ≈ 2° low (gravity in the measurement) |
| Line of sight after release (+6..+12 frames) | (524–537, 154–196): 11.3–11.9° left, 17.7–20.6° up | 10.1–11.8° left, 19.6–21.7° up | ≤ 2–3° |
| Grenade on screen right after release | **held still at the release point for 6–7 frames**, then recedes | recedes at once (29 → 8 px in 4 frames) | MISMATCH (server-owned body: its motion reaches the client ≈ 0.2 s late) |
| Throw arm, hand end | L-1 (370, -58), L (450, -51), L+1 (519, 169), L+2 (600, 471), L+3 (598, 561), L+4 (560, 703), L+5 off | L-1 top, L top left, L+1 tip ≈ (560, 140), L+2 ≈ (600, 470–485), L+3 ≈ (600–610, 560–600), L+4 bottom centre, L+5 gone (C3) | ≤ 20–50 px; lit white here, dark in the footage's overcast scene |
| Grenade in hand at release (L+1) | (500, 125) | (490–507, 120–130) | ≤ 10 px |
| Lever | 1 per throw, up-right from the hand, falls | C4 | present |
| Rifle during the throw | stays on screen | leaves the view (C5) | MISMATCH, left (accepted weapon controller) |
| Label solid / fade | 1.403–1.406 s / 0.189–0.196 s | 1.40 s / 0.2 s (M6) | ≤ 1 frame |
| Label text box | left 23 px (22 at 720 p), caps ≈ 689, baseline ≈ 696, 71 px wide, 12 px Code | ink x 24, caps 688, baseline 695, 70 px wide (M7) | ≤ 3 px (the crop overlay shows ours ≈ 2–3 px lower) |
| Red edge envelope (hook samples) | 1.00 / 0.88 / 0.70 / 0.56 / 0.46 / 0.31 / 0.24 / 0.16 / 0.05 / 0.01 / 0 at +0/3/6/9/12/19/24/34/54/62/70 fr | 1.00 / 0.90 / 0.74 / 0.59 / 0.42 / 0.28 / 0.23 / 0.17 / 0.12 / ≈0.05 / 0 (M12) | ≤ 0.04 to +34; the tail ends ≈ 0.3 s earlier |
| Red edge look | dark red (120, 10, 10) at 45 % at the edge; top profile 1.0 / 0.87 (30 px) / 0.55 (70) / 0.41 (90) / 0.17 (130) / 0 (160) | top edge 1.0 / 0.87 / 0.51 / 0.47 / 0.35 / ≈ 0.26 (160); bottom fades by ≈ 120 px | fades faster beyond 90 px at the top |
| Red edge trigger | `FragmentsHit` exactly when fragments reach the player: 6 of 14 detonations in the test run → 6 pulses; none otherwise; health stays 100 | 2 of 7 detonations (I4, INFERRED) | trigger INFERRED |
| Detonation sequence | flash at the first capture, dust dome at once (DustAt 1/30), flash gone within ≈ 4 captures (≈ 0.15 s) | sparks 0, flash + dust +1, flash gone by +7–8 (C7, M4) | sparks not caught between captures; dust denser and longer here (placeholder) |
| Fuse | 4.0008–4.0043 s (19 detonations over the sessions) | 4.00–4.17 s (M1) | MATCH |
| Camera shake | none | none (C8) | MATCH |

### Security (fidelity test + GrenadeTest forged recipe; every result from the server)

| Attempt | Result |
|---|---|
| Throw with a NaN / inf aim | refused "not finite" |
| Zero vector; a velocity (\|v\| 55 / 50 / 900) instead of a direction | refused "not a direction" |
| String / table / nil aim | refused "no direction" |
| 10 throws in one frame (spam) | 1 thrown, 9 "already throwing" |
| A throw while the previous one runs (0.30 s) | "already throwing"; the next at 0.45 s is accepted |
| Zero grenades | "NoFrags", label "NO FRAGS LEFT", no throw presentation |
| Position / velocity / fuse as extra arguments of a real throw | ignored (the throw is the server's own) |
| SetFuse / Detonate / Fragment / Fragments / Hit / Target / Damage / Result / FragmentsHit / Explode as commands | "unknown action" |
| Forged GrenadeFx / GrenadeState (incl. a forged FragmentsHit) sent to the server | counted, ignored; no pulse |
| A live grenade moved / flung locally | server-owned throughout, largest path step 2.71 studs (no jump) |
| Throw in progress when the player dies | refused at release: "died before the release" |
| Throw while dead | "dead"; the client's own G sends nothing while dead |

### Existing grenade suite (with the new launch)

- Fuse 4.0024–4.0043 s.
- Release 0.149–0.155 s after the request.
- The throw lock still refuses at 0.30 s and accepts at 0.45 s.
- "NO FRAGS LEFT" shows; player health stays 100.
- BodyState / ragdoll / blood integration: one grenade among REACT1–6 gives 38 fragments into bodies.
  - REACT4: head first (Brain, ALIVE → DYING), then 12 more parts recorded.
  - REACT2 / 3 / 5: INJURED.
  - Grenade blood batches: 71 marks, 24 stains.
- **Changed by design**: the four scenario throws now leave 21° higher and 11° left, so the scenario numbers above
  (2026-11-06) no longer apply:
  - Open lob: 3 floor bounces, ≈ 115 studs of travel.
  - Wall throw: 1 wall + 2 floor bounces.
  - Steep: 3 floor bounces.
  - Confined room: stays inside, 489 into walls / 38 clear / 73 into the thrower.

### Full regression (fresh playtest, final grenade scripts; Grenade last)

| Area | Result |
|---|---|
| BodyState | unit 42 / 42; M4 6 / 6, AK 6 / 6; forged pass (INJURED, health 100) |
| Ballistics | unit 10 / 10 per lane (1.75 / 1.249 / 2.0, z 91 / 91 / 131); real shots 18 / 18 (drops A 6, B 6, C 0) |
| Hit reactions | M4 6 / 6, AK 6 / 6; dying states 11 / 11; tamper pass |
| Blood | M4 14 / 14, AK 14 / 14; dead hit; world; security; orphans 0 |
| Body interaction | pulse 3.014–3.020 s (REACT1–4 pulse, REACT5 / bled-out REACT6 "No pulse"); far / invalid / interrupt 1.744 s / forged / local state; death → "Interrupted (player dead)"; drag 9.06 studs, 5.6 restored, trail 12 points; "too far" 0.777 s; already held; tamper — match (known: orphan check `WalkSpeed == 16` reads 5.6) |
| Death / respawn | AK empty reload "cancelled (died) after the magazine change"; respawn 3.278 s; M4 HUD agrees (30 + 1), M4 fires |
| AK | 640 RPM, climb 1.231°; raised 0.129 / 0.288 s; 31 shots, 1.943°; reloads 2.432 / 1.663 / 3.133 / 2.763 s; label 1.067 s; sequence / repeat / refusals / switch / repeated client = server |
| M4 | 770 RPM (13 / 1 s, server 17 + 1, 0 rejected); 31 aimed, recovery 0.74 s; hip recovery 0.740 s; de-cant −32.575° → 0.138°; 0 late shots; ADS 0.331 / 0.330 in, 0.118 / 0.120 out; reloads 3.532 / 3.066 / 3.699 / 3.596 s; Stressed sway roll 2.502° (known to vary) |
| M4 HUD | 13 checks, 0 mismatches; labels 1.702 / 1.736 / 1.602 s |
| Original reload test | M4AnimTest plays 3.529–3.543 s (play 1 at the start hitch) |
| AI | perception 14 / 14, aiming 8 / 8, firing 11 / 11, integration 10 / 10; player as target **6 / 7, 6 / 7, then 7 / 7** (P2 is timing-sensitive: in the second reading the bot acquired the player 31 ms *before* the test's "moved" stamp); bot shoots player 5 / 5; M4 takedown 6 / 6; security 10 / 10 |
| Movement | rules 25 / 25; walk 5.600; crouch 2.80 studs/s, eye 2.70; jump +7.529; lag 5.953 / 7.391° hip, 0.895 / 1.111° aiming; roll 1.399 / 2.699° |
| Optics | in 0.148 / 0.150, out 0.163 / 0.152 s; lens 162.4, ring 266.4, magnification 4.499; tracking 0.894 / 1.110°; 0 client → server events scoped; forged as before; flags roll 1.399 / 2.698°, up 0.020° |
| MP7 | 40 + 1, idle 0.000; 41 / 41 at 950 RPM, climb at the end 4.04–4.18° over 3 runs (baseline 4.12–4.14°); ADS 0.266–0.272 / 0.151–0.160 s (≈ 1 frame over the baseline late in a long playtest); reloads 3.273 / 4.949 / 2.116 / 3.411 s, end pose 0 / 0; forged rate 3 / 9, 20 / 13 |
| Glock | hold 1 → 1; 16 / 16; empty → 2; empty reload 3.401 s (swap 2.179, slide 2.679); one viewmodel per equip incl. the Sniper |
| Sniper | hold 1 → 1; cycle eject 0.700, chamber 0.933 / 0.967, next 1.567 s, hand +10..+38; tactical 4.177 s; zoom wrap restores 6x |
| Console | final capture session and a cross-system smoke session (BodyState unit 42 / 42, Ballistics 6 / 6 lanes, AI firing 11 / 11, a grenade among bodies, MP7 16 / 16, Sniper cycle): **0 errors**. The long regression session's log was not read before it was stopped (Studio keeps only the latest session); no game-code error surfaced in any tool result there — three test calls errored because I overlapped them with a still-running AK batch (the batch exceeded the call limit), and were rerun cleanly |

**Separate, not changed (as instructed):** the M4 Stressed reload end-pose discrepancy (3.153° tactical, 1.218° empty this run).
