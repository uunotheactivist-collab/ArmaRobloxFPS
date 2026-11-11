# Body interaction (pulse check, drag, drag trail): focused test

**Proves:** a player can interact with an existing authoritative bot body, through the accepted systems:
- check its pulse (3.00 s, result from BodyState);
- drag it while it stays the accepted active ragdoll;
- leave a persistent blood trail in the accepted blood mark layer.

Every decision is the server's. A client only asks.

**Basis:** `ReferenceAnalysis/BodyInteraction/BodyInteraction_Analysis.md` (O1–O17, decisions tagged CONFIRMED / MEASURED /
INFERRED / PLACEHOLDER / UNKNOWN). Values: `ReplicatedStorage.Shared.Config.BodyInteraction` and
`Config.Blood.Trail`, tagged the same way.

**Checkpoint:** `Roblox/Scripts/Checkpoints/2026-11-06_body_interaction`. Before: `2026-11-06_before_body_interaction`,
identical to the accepted `2026-11-06_blood_impacts`.

## Pipeline (no second body-state, ragdoll or blood system)

```
F menu (client)  ──BodyInteract("PulseCheck" | "Drag", body) / ("LetGo") / ("Cancel")──►  Server.Interaction.BodyInteraction
                                                                                            │ checks: player alive · BodyState body in the world ·
                                                                                            │ range (server copies) · line of sight · one at a time ·
                                                                                            │ request rate · who holds the body
   ◄──BodyInteractState (that player only: Started / Result / Interrupted / Released / Rejected)──┤
                                                                                            ├─ PulseCheck: 3.00 s timer → PulseCheck.result(BodyState.get)
                                                                                            └─ Drag: Drag.grab (snap + AlignPosition on the ragdoll)
                                                                                                    → every frame: Drag.update (rope target) + Blood.Trails.step
                                                                                                    → Blood.SurfaceMarks.trail (shared patches, shared budget)
```

## Pieces

| Piece | Where | Role |
|---|---|---|
| Data | `ReplicatedStorage.Shared.Config.BodyInteraction` | Key, menu texts, ranges, pulse duration and results, drag values (tagged) |
| Remotes | `Shared.Remotes.BodyInteract` (client → server), `BodyInteractState` (server → that client); saved in the place | Requests only / results only |
| Server | `ServerScriptService.Server.Interaction.BodyInteraction` (Script) | Validation, per-player state, the 3.00 s timer, drag lifecycle. One Heartbeat that exists only while an interaction is active. Studio hook `InteractionDebug` |
| Checks | `Server.Interaction.Eligibility` | Live player; BodyState body in the world (not a player); closest-point distance; line of sight (other bodies don't block) |
| Pulse | `Server.Interaction.PulseCheck` | `BodyState.get(model).Phase` → result (ALIVE / INJURED / DYING → Pulse, DEAD → No pulse) |
| Drag | `Server.Interaction.Drag` | Grab: a one-time rigid turn so the head end points at the player, then `DragGrip` (Attachment) + `DragAlign` (AlignPosition, one attachment) on the upper torso. Update: rope target from the player's hand point. Release: both destroyed, walk speed restored |
| Trail | `Server.Blood.Trails` (new) + `Server.Blood.SurfaceMarks.trail` / `place("trail")` (extended) | A smear each time the pelvis has moved 0.6 studs, only for wounded bodies; persistent, shared budget |
| Client | `StarterPlayerScripts.Client.Interaction.BodyInteraction` (LocalScript) + `InteractionMenu` | Temporary menu: "[F] Check pulse / ○ Drag", "Checking pulse..." with a linear underline, the result line, "[F] Let go". Candidate found at 10 Hz (nearest body ≤ 7 studs, in front). Studio hook `BodyInteractionDebug` |
| Server test | `ServerScriptService.InteractionTest.Run` (copy `InteractionTest_Server_Run.luau`) | `setup`, `state`, `watch` / `path`, `trail`, `recent`, `status`, `blood`, `orphans`, `kill`, `reserve` |
| Client test | `StarterPlayerScripts.InteractionTest.Run` (copy `InteractionTest_Client_Run.luau`) | Real menu requests and fake ones: `pulse`, `far`, `invalid`, `interrupt`, `forge`, `localState`, `drag`, `dragAway`, `dragInvalid`, `tamper` |

**Changes to accepted files:** the blood layer only, additive.
- `Config.Blood.Trail` gains WidthStuds, Pieces, Color, Transparency, SourceParts and WhenDead. The unused DropSize is removed.
- `SurfaceMarks.place` gets the kind "trail"; drops and splats are unchanged, with the same random draws.
- `SurfaceMarks.trail` is rewritten. It was the unused entry the blood milestone left for this.
- `SurfaceMarks.stats` counts trail marks separately.

BodyState, ActiveRagdoll, HitReaction, BodyPresentation, Pools, Stains, Impacts, BloodServer and every weapon script are
byte-identical.

## How to run (Studio playtest)

```lua
-- Server
local R = require(game.ServerScriptService.InteractionTest.Run)
R.setup()      -- REACT1 ALIVE · REACT2 INJURED · REACT3 DYING/SHOCK · REACT4 DYING/CRYING · REACT5 DEAD · REACT6 DYING/CHOKE (dies ≈15 s later) · BODY3 (R6) down
-- Client
local Run = require(game.Players.LocalPlayer.PlayerScripts.InteractionTest.Run)
Run({ pulse = 6 })  Run({ pulse = 1 })  … Run({ pulse = 6 })   -- REACT6 again once it has bled out
Run({ far = 3 })  Run({ invalid = true })  Run({ interrupt = 3 })  Run({ forge = 1 })  Run({ localState = 1 })
-- death during a check: client starts a check (hook select 1 + press), server R.kill()
-- Server: R.watch(i, 30) on the bodies to drag; Client: Run({ drag = i, back = 10, hold = 0.8 }); Server: R.state(i), R.path(i), R.trail(i), R.orphans()
Run({ dragAway = 4 })  Run({ dragInvalid = true })
-- held by someone else: Server R.reserve(3, true); Client Run({ drag = 3 }); Server R.reserve(3, false)
-- tamper: Server note R.state(3) / R.blood(); Client Run({ tamper = 3 }); Server compare
```

## Results (2026-11-06, final scripts)

### Pulse check: 9 / 9

| # | Test | Result |
|---|---|---|
| 1 | Living body (REACT1, ALIVE) | "Pulse: strong, rapid · ~100/min" after **3.0034 s** on the server (3.018 s press → result on the client) |
| 2 | Injured (REACT2, INJURED, standing) | Pulse, 3.0025 s |
| 3 | Dying (REACT3 SHOCK; REACT4 CRYING and REACT6 CHOKE before they bled out) | Pulse, 3.0014 / 3.0028 / 3.0009 s |
| 4 | Dead (REACT5) | **"No pulse"**, 3.0044 s. REACT6 gave "strong, rapid" first, then "No pulse" after it bled out: the footage's sequence |
| 5 | Too far (16.8 studs) | Rejected "out of range" (pulse and drag) |
| 6 | Invalid targets (8): the Baseplate, a string, a number, a lane target dummy, the player's own character, ReplicatedStorage, nothing, dragging the own character | All rejected ("not a body" / "no target") |
| 7 | Interrupted | Walking away: "Interrupted (out of range)" at 1.74 s, no result. Player killed mid-check: "Interrupted (player dead)", loop stopped |
| 8 | Forged result | "PulseResult" / "Complete" / "SetPulse": unknown action. A fake result fired on `BodyInteractState`: counted, ignored. A second PulseCheck and a Drag during the check: "busy". The real result still came 3.015 s after the start |
| 9 | Client BodyState write | `BodyPhase = DEAD`, `BodyStance = DOWN`, `BodyLife = 0` set locally on REACT1, then a real check: **"Pulse"** (the server's ALIVE) |

Over all 9 results the server measured 3.0009–3.0044 s and the client 3.014–3.020 s; the footage measures 3.00 s. The menu
showed "Checking pulse..." with the underline half full at 1.5 s, and the highlight moved to "Drag" after each result.

### Drag: 10 / 10

| # | Test | Result |
|---|---|---|
| 1 | Downed (DYING) body | REACT3 grabbed from the menu. Lying head-away, it was turned 177° at the grab, then the player walked back 9 studs at 9 studs/s and it moved 9.20 studs. In the final regression run: turned −177°, moved 11.18 studs |
| 2 | Dead body | REACT4, REACT5 and REACT6 dragged 9.15–9.21 studs. REACT5 (LIMP, head-away, the case that jammed before the snap was added) turned 166° and −174° |
| 3 | Stays ragdolled | Root motor only, 14 joints, muscles 14 (dying) / 0 (dead) as before. Root unanchored, 0 client-owned parts, 16 parts (none added); ragdoll in every 30 Hz sample |
| 4 | Follows physically | Torso path at 30 Hz: no step over 0.47 studs except the single snap frame (≈2 studs as the torso swings about the pelvis). Torso height 0.49–1.5 studs; the body stays 2–3 studs in front of the hand; the player walks at 9 studs/s |
| 5 | Let go releases cleanly | No `DragGrip` / `DragAlign` left, `BodyDraggedBy` cleared, loop disconnected, nobody held, walk speed back to 16, menu back to "Check pulse / Drag" without the result line |
| 6 | Moving away / dying | Jumping 30 studs away: "Released (too far)" within 0.67–0.81 s. Killed while dragging: "Released (player dead)", nothing left over; the new character walks at 16 |
| 7 | Invalid / far targets | Standing ALIVE and standing INJURED: "not down". R6 debug-pose BODY3 (down, anchored): "not a physical body". 22–23.5 studs away: "out of range". Held by another (test reservation): "already held". Non-bodies: "not a body" |
| 8 | Client can't move the body | The client set the torso +10 studs up and 80 studs/s locally: the server's body stayed (y 0.50; it moved 0.15 studs, from the real 0.4 s drag in the same test). Extra drag arguments (a position, "OtherPlayer", a speed) were ignored; "MoveBody" / "Trail" were unknown actions |
| 9 | No orphans | `R.orphans()` passed after every drag test: 0 grips, 0 aligns, 0 dragged attributes, no loop, 0 held, 0 active trails, walk speed 16 |
| 10 | BodyState stays authoritative | After every release: phase, stance, behaviour and life unchanged (DYING DOWN SHOCK 100 / DEAD DOWN 0). BodyState still drains dying bodies (REACT4 / REACT6 died on schedule) |

### Blood trail: 7 / 7

| # | Test | Result |
|---|---|---|
| 1 | Dragging a wounded body makes a trail | 10–18 smears per 9–11 studs dragged |
| 2 | It follows the actual movement | Smear points spaced 0.60–0.74 studs, every one within 0.03–0.98 studs of the body's sampled torso path. The pelvis lies a little off the torso line when the body slides at an angle |
| 3 | It stops when the drag stops | A drag released after 0.7 s with almost no movement: 0 smears. The mark count doesn't change after a release |
| 4 | No trail from forged events | "Trail" request, state-remote message, local writes: marks 49 → 49 |
| 5 | No part per drop | 49 marks on 10 patch parts, 18 on 3. Each smear is Frames on a shared patch's SurfaceGui; 0 empty patches |
| 6 | Existing blood persistence intact | Pools (5) unchanged through every drag. The trail shares the existing budget (600 marks, oldest first) and nothing fades |
| 7 | Blood impact tests | M4 14 / 14, AK 14 / 14, dead hit, world, security, orphans: all pass |

**Look:**
- The band is continuous and mottled, from where the body lay (its pool) to the released body's legs end.
- Colour, rendered against the floor:
  - green and blue are 0.31–0.36 × the floor's (footage 0.27–0.47);
  - red is 0.89–1.20 × the floor's (footage 0.85–0.95).

  The floor's own brightness changes a lot with the view (92–167 on red), so the red ratio is view-dependent.
- Captures (`Captures/`):
  - `smoke_trail.png`: the first version (separate dots);
  - `trail_after_drag.png` + `_zoom`: an intermediate colour (smears joined);
  - `drag_trail_side.png`, `drag_trail_dragger_view.png`: an intermediate colour;
  - `drag_trail_final.png`, `drag_trail_final_dragger_view.png`: final values. The second one also shows the drag pose: torso and arms at the player, legs away.

## Security: every attempt failed

| Client attempt | Server result |
|---|---|
| Declare a body dead (local `BodyPhase = DEAD`) | Nothing changes on the server; the pulse result stays "Pulse" |
| Declare a pulse result (`PulseResult`, `SetPulse`, fake `BodyInteractState` message) | Unknown action / counted and ignored |
| Skip the duration (`Complete`, repeated `PulseCheck`) | Unknown action / "busy"; the result still comes at 3.00 s |
| A body outside range | "out of range" (16.8 and 22–23.5 studs) |
| Teleport / fling a body | Local writes only; the server-owned body doesn't move. No remote takes a position |
| Create a blood trail (`Trail`, fake messages) | Unknown action; 0 marks |
| Force another player / body into drag state | No remote names a player; a held body is "already held"; player characters are "not a body" |
| Spam | Requests closer than 0.2 s apart are refused ("too fast"). Implemented; the tests space their requests 0.25 s apart, so it was not triggered |

## Regressions (fresh playtest, final scripts)

| Area | Result |
|---|---|
| BodyState | unit 42 / 42; real shots M4 6 / 6, AK 6 / 6; forged requests rejected |
| Ballistics | unit 10 / 10 on every lane for both rifles (event sequences unchanged); real shots 18 / 18 (lanes A / B 25 damage, C 0) |
| Hit reactions / ragdoll | M4 6 / 6, AK 6 / 6; synthetic (dying states) 11 / 11; tamper pass |
| Blood | M4 14 / 14, AK 14 / 14; dead hit pass; world pass; security 5 / 5; orphans pass |
| AK | equip; hip burst 640 RPM, climb 1.233; raised 0.129 / 0.288 s, FOV 70; full magazine 640 RPM, 31 shots, climb 1.946 / 1.943 (Stressed); reloads 2.431 / 1.661 / 3.130 / 2.765 s, label at 1.067 s; label sequence / repeat; refusals NoReserve / Full; switch 23; repeated Busy |
| M4 firing | single 29 + 1; 770 RPM in every test; ADS magazine thirds 0.81 / 1.30 / 1.51 (reruns 1.00 / 1.07 / 1.44 and 0.89 / 1.03 / 1.38; README run spread 0.92–1.06 / 1.20–1.44 / 1.22–1.44), recovery 0.740–0.772 s; hip magazine recovery 0.776, Stressed 0.771; stop; weapon reset 27 = 27 |
| M4 reloads | 3.532 / 3.062 / 3.696 / 3.597 s; refusals; partial reserve 11 [7]; while aiming; switch during; repeated Busy |
| M4 HUD | sequence, states, check: label matches and client = server everywhere |
| Death / respawn | 3.63 s; M4 equipped, 1 viewmodel, 5 shots; impact and interaction listeners alive; a pulse check after respawn 3.017 s |
| Console | 0 errors, 0 warnings in the retained log (server and client) |

**Separate, not changed (as instructed):** the M4 Stressed reload end-pose discrepancy is still there (2.43° tactical
Stressed, 1.78° empty Stressed this run).

## Performance

- **Server:**
  - One Heartbeat connection, created by the first interaction and disconnected when the last ends. No interaction: no
    loop.
  - Per active interaction per frame: a distance check (pulse), or one AlignPosition target write and one distance
    compare (drag).
  - Raycasts happen only when a smear is placed: about 15 per second while dragging at walking speed.
- **Instances:** each active drag adds one Attachment and one AlignPosition, both destroyed on release. Trail smears are
  Frames on the shared 8 × 8-stud patches, so no part per drop.
- **Network:** messages go out only on started / result / interrupted / released / rejected. There is nothing per frame;
  the body replicates as ordinary server physics.
- **Client:** the candidate scan runs at 10 Hz over the known bodies; the underline is one Tween. There is no per-frame
  code.

## Placeholders, unknowns and remaining mismatches

- **PLACEHOLDER:**
  - the ranges (7 / 9 studs);
  - the selection input (mouse wheel);
  - the grip height, rope, force, speed and break distance;
  - the snap threshold (30°);
  - trail spacing, specks and the DEAD-body trail rule;
  - colour values (only their ratio to the floor is measured).
- **INFERRED:**
  - the pulse mapping (living → "strong, rapid", dead → "No pulse");
  - the drag walk speed (from the step cadence);
  - the trail source (under the pelvis);
  - the width in studs.
- **UNKNOWN, so not built:**
  - "Search body";
  - how the selection moves;
  - cancelling a check from the menu (the server supports "Cancel"; the menu doesn't send it);
  - other pulse wordings;
  - revive;
  - firing while dragging or checking (nothing blocks it);
  - the red tether line (O16).
- **Mismatches:**
  - The footage's dragged body keeps a fixed, straight pose. Here the snap only turns the body; its limbs stay as they
    fell and trail physically.
  - The trail's red is somewhat stronger than the footage in some views (above).
  - The trail reads as overlapping round specks, not the footage's fine speckle.
  - A pool keeps its place, and growth, after its body is dragged away (accepted Pools behaviour, not changed).
  - No arm-reach or backward-walk animation for the player (W3).
  - Turning a body inside a pile could push into its neighbours (not tested).
- **Players:** not BodyState bodies, so not interactable. The same server checks apply once they are.
