# Hit reactions + death / active ragdoll: focused test

**Proves** the chain bullet → body hit → BodyState → visible reaction, for the M4 and the AK:
- a flinch while standing;
- a weakened pose and a stumble step;
- a visible fall (not a teleport);
- an active ragdoll whose muscles follow the dying behaviour and fade with life;
- DEAD (limp), with the body staying in the world.

Everything is decided on the server, from BodyState's own state. Nothing is taken from the client.

> **Fidelity pass (later the same day):** the fall is now staged, knees first with the upper body held, and the joints
> have anatomical limits. See "Fidelity pass" at the end. The sections before it describe the accepted slice
> (checkpoint `2026-11-06_hitreactions`).

**Basis:** `ReferenceAnalysis/HitReactions/HitReactions_Analysis.md`. Every rule there is tagged CONFIRMED / MEASURED /
INFERRED / PLACEHOLDER / UNKNOWN. The accepted BodyState rules are not changed (§ Compatibility).

## Pieces

| Piece | Where | Role |
|---|---|---|
| Data | `ReplicatedStorage.Shared.Config.BodyPresentation` | Joint map, gain, the measured per-behaviour muscle profiles, life fading, crawl speed, go-over rate, ragdoll gravity, flinch / posture / stumble values, all tagged |
| Presenter | `ServerScriptService.Server.BodyPresentation` (Script) | Binds models with `BodyPresentation = "ActiveRagdoll"`. Reads BodyState's published attributes only. **Standing:** flinch / posture / stumble (HitReaction). **Going down** (DYING, or stance not STANDING): ActiveRagdoll. Studio-only hook `BodyPresentationDebug` |
| Standing reactions | `ServerScriptService.Server.HitReaction` | Procedural offsets on the Motor6D C0s of the anchored standing rig |
| Ragdoll | `ServerScriptService.Server.ActiveRagdoll` | Ball sockets at the joints. One AlignOrientation "muscle" per joint, with torque = limb mass × reach × g × gain × k. Humanoid → Physics. Server network ownership. Ragdoll gravity, crawl push |
| Compatibility | `ServerScriptService.Server.BodyState`, `pose()` | One guard line: bodies with a `BodyPresentation` attribute are not given BodyState's temporary debug pose |
| Range | `Workspace.HitReactionTest` (`build_range.luau`, saved in the place) | R15-joint blocky bots REACT1–6 at x = −350 … −400, z = 110 (spots at z = 125; backstop at z = 100). PRES1 at x = −420 for presentation-only tests. Templates in `ServerStorage.HitReactionTemplates` |
| Server test | `ServerScriptService.HitReactionTest.Run` (copy `HitReactionTest_Server_Run.luau`) | `spawn(seconds)`, `report(weapon)`, `synthetic()`, `tamperCheck()` |
| Client test | `StarterPlayerScripts.HitReactionTest.Run` (copy `HitReactionTest_Client_Run.luau`) | Real shots through the production controller (`{ weapon = "M4" }`), client tampering (`{ tamper = true }`) |

## How to run (Studio playtest)

```lua
-- Server
local R = require(game.ServerScriptService.HitReactionTest.Run)
R.spawn(45)          -- fresh REACT1–6 + PRES1, clear BodyState records, sample each bot at 30 Hz
-- Client
require(game.Players.LocalPlayer.PlayerScripts.HitReactionTest.Run)({ weapon = "M4" })   -- then "AK" after R.spawn(45)
-- Server
R.report("M4")       -- H1–H6
R.synthetic()        -- PRES1 through every behaviour (synthetic attributes, presentation only)
-- tamper: R.spawn(10); client Run({ tamper = true }); server R.tamperCheck()
```

**The plan:**

| Bot | Shots |
|---|---|
| REACT1 | right arm |
| REACT2 | abdomen |
| REACT3 | throat point |
| REACT4 | chest, 3-round burst |
| REACT5 | head |
| REACT6 | left leg, then right leg; after 2.5 s, the centre while down |

## Results (2026-11-06, final version)

### Real shots: M4 6 / 6, AK 6 / 6

| Check | M4 | AK |
|---|---|---|
| **H1** REACT1 arm: `rightarm : Limb : ALIVE → INJURED`. Flinch seen, then back to 0, no ragdoll, root still anchored | swing peak 21.7° | 19.0° |
| **H2** REACT2 abdomen: `Gut : ALIVE → DYING`. Ragdoll, CRYING profile (k error 0). Down (chest −1.2 studs) after ragdoll start, with ≥ 5 samples in between | 0.40 s, 5 samples | 0.42 s, 5 |
| **H3** REACT3 throat: `chest / throat : Throat`. CHOKE profile (k error 0) | 0.41 s, 5 | 0.41 s, 5 |
| **H4** REACT4 chest ×3: `ALIVE → INJURED`, `INJURED → INJURED`, `INJURED → DYING`. Flinches on hits 1–2, ragdoll on the 3rd, CRYING (Lung) | flinch 18.9°, 0.39 s | 22.0°, 0.39 s |
| **H5** REACT5 head: `Brain`. LIMP (every k 0), sinks, DEAD, body stays | 0.63 s, 6 | 0.64 s, 6 |
| **H6** REACT6 legs: INJURED, then unstable. Stumble step 0.5 studs, then ragdoll SHOCK (k error 0). The later hit is "recorded only" | step 0.5, 0.32 s | 0.5, 0.31 s |

For every ragdoll: motors off (Root kept), ball sockets and muscles on, network owner the server (0 client-owned
parts).

**Torso height after the ragdoll starts, M4 run (studs; standing ≈ 3.5, lying ≈ 0.5):**

| Bot | 0.1 s | 0.2 s | 0.3 s | 0.4 s | 0.5 s | 0.6 s | 1.0 s | 1.5 s |
|---|---|---|---|---|---|---|---|---|
| REACT2 gut | 3.42 | 3.19 | 2.71 | 1.92 | 0.59 | 0.97 (bounce) | 0.51 | 0.50 |
| REACT3 throat | 3.44 | 3.25 | 2.88 | 2.19 | 1.12 | 0.74 | 0.50 | 0.50 |
| REACT5 head (LIMP) | 3.50 | 3.50 | 3.47 | 3.20 | 2.68 | 2.09 | 0.98 | 0.50 |
| REACT6 legs | 3.13 | 2.79 | 2.25 | 1.55 | 0.76 | 0.57 | 0.50 | 0.50 |

**Footage:**
- F1: kneeling ≈0.6 s, settled ≈1.1 s;
- F2: throat, ≈0.6 s of visible fall;
- F3: LIMP stays up ≈5 frames, then sinks straight down.

### Presentation-only (PRES1, synthetic attributes): 11 / 11
- SHOCK @100, WRITHE @92, CHOKE @97, PANIC @94, AGONAL @19, LIMP @60, CRAWL @99: each matches its measured profile × life
  fading (k error 0).
- CHOKE @81: fades with life (k error 0).
- CRAWL moves 1.8 studs in 3 s = **0.60 studs/s** (measured 0.6).
- DEAD: every k 0, crawl off, body stays.
- All behaviour profiles are distinct.

WRITHE, CRAWL, PANIC and FADING can only be reached this way. BodyState never selects them (its accepted
`DownBehaviour` gives LIMP / CHOKE / CRYING / SHOCK, and AGONAL below 20 %).

### Client tampering: pass
The client:
- wrote `BodyStance = DOWN`, `BodyPhase = DEAD`, `BodyBehaviour = LIMP` on REACT1;
- set its UpperTorso velocity;
- sent `WeaponCommand("Ragdoll", …)` and `WeaponCommand("SetBodyState", …)`.

The server saw no change: no ragdoll, root still anchored, torso at 3.5 with velocity 0, server attributes unset,
and BodyState's `get` returned no state for REACT1.
The client's writes stayed local. No remote accepts a body state or a ragdoll request.

### Captures
- `Captures/fall_gut_strip.png` (frames in `Captures/fall_gut/`, ≈100 ms apart): REACT2 shot in the abdomen.
  - It topples forward over ≈0.6–0.7 s.
  - It lies with the tag "REACT2 CRYING life 99 % · Gut wound · behaviour PLACEHOLDER".
  - The tag is BodyState's temporary debug view, unchanged.
- `Captures/fall_gut_sheet_all.png`: contact sheet of the whole burst (the first 46 frames are before the client
  moved).
- `Captures/bots_after_M4_run.png`: after the M4 plan.
  - REACT1 still standing, INJURED.
  - REACT2 CRYING 44 %, REACT3 CHOKE 17 %, REACT4 CRYING 54 %, REACT6 SHOCK 100 %: lying.
  - REACT5 DEAD, sprawled (LIMP).
  - All bodies stay in the world.

### Before the final version (honest record)
- **First run (M4): 5 / 6.**
  - H2 failed: gut-shot (CRYING) bodies **stood balanced as a statue for 1.4–2.9 s** before falling.
  - Cause: straight legs held by muscles need no torque, so the 0.6 rad/s tip on the lower torso was not enough.
- **Fix 1:** the whole body starts toppling about its feet at the measured **1.5 rad/s** ("GOES OVER … 1.5 rad/s
  about the feet").
  - Bodies now went over at once.
  - But they fell ≈2.4× faster than the footage (down 0.14–0.28 s, settled ≈0.55 s).
  - H2 still failed (2 samples).
- **Fix 2:** ragdolls fall under the project's own gravity, **35 studs/s² = 9.8 m/s²**. That is the value the accepted
  ballistics already use, instead of Roblox's 196.2. Final results above.
- **The test thresholds were never changed.**

## Regressions (fresh playtest, same day)

| Check | Result |
|---|---|
| BodyState unit | 42 / 42 |
| BodyState real shots | M4 6 / 6, AK 6 / 6 (same records as accepted). The BodyState bots BODY1–6 have no `BodyPresentation` attribute and keep BodyState's own debug pose |
| BodyState forged requests | pass (INJURED / 100, health 100, the server's own `leftleg / Limb`) |
| Ballistic unit traces | M4 and AK lanes A / B / C 10 / 10, sequences identical to the accepted ones |
| Ballistic real shots | 18 / 18: A and B 25 damage per shot, C none |
| AK | equip (client = server); raise 0.128 / lower 0.288 s, FOV 70; hip burst 640 RPM, climb 1.24°; full magazine (normal and stressed) 640 RPM, 31 shots, 0 rejected, climb 1.94–1.95°; reloads 2.430 / 1.666 / 3.133 / 2.765 s, label "[TAB] 5.45 MAG" at 1.07 s; label sequence and repeat; refusals `Full` / `NoReserve`; switch (23 + 1 kept); repeated (`Busy` ×3, 3 bursts of 6 accepted) |
| M4 firing | single; hip burst 770 RPM; ADS / hip / stressed magazines 770 RPM, 31 shots, recovery 0.740–0.745 s; stop; weapon reset |
| M4 reloads | 3.532 / 3.065 / 3.699 / 3.596 s; refusals; partial reserve; while aiming; switch during (before / after the commit); repeated |
| M4 reload final pose | Regular within 0.003 studs / 0.35°, as accepted. **Stressed:** 1.4–5.1° rotation error over 6 runs (tactical 1.40 / 2.65°; empty 5.12 / 3.83 / 2.09 / 3.69°), against "within 2.5°" in the M4_Reload README. This is the Stressed sway still running at the sample moment, and it varies run to run. All client weapon code is byte-identical to the accepted checkpoints, so this slice did not change it. The README figure came from fewer runs |
| M4 HUD | sequence 1.702 / 1.737 / 1.603 s, client = server; all states; check |
| Death / respawn | respawn 3.35 s; one viewmodel; 5 shots fired, 0 rejected. The player character has no `BodyPresentation` attribute (not ragdolled) |
| Original reload test | 3.530–3.542 s; one 3.701 s outlier during the heavy batches (the first play includes loading) |
| Console | no errors, no rejected shots |
| Scripts | 48 / 48 in Studio = `Roblox/Scripts/src`. Against `Checkpoints/2026-11-06_bodystate_cleanup`: 6 **new** (Config.BodyPresentation, Server.BodyPresentation, Server.HitReaction, Server.ActiveRagdoll, two HitReactionTest.Run); **changed** `Server.BodyState` only (one guard line); 41 byte-identical |

## Placeholders, unknowns and limits (none of the placeholders is reference behaviour)

**Flinch:**
- Timing: MEASURED (peak within 2 frames, gone within BodyState's 0.3 s `Reacting` window).
- Amplitude (12° waist back, 8° twist, 22° arm swing): PLACEHOLDER.
- Direction: UNKNOWN, so it is the same for every hit.

**Weakened pose and stumble:**
- A broken pose exists: CONFIRMED.
- The scales: PLACEHOLDER.
- Stumble step 0.5 studs over 0.3 s and sway: PLACEHOLDER values inside the measured ranges.

**Fall:**
- Go-over rate 1.5 rad/s: MEASURED.
- Starting with it: INFERRED.
- Forward direction: PLACEHOLDER (F7 UNKNOWN).
- The fall is a mostly stiff topple, not F1's knees-first crumple with the upper body still aiming.

**Muscles:**
- The formula: CONFIRMED.
- Gain 1: INFERRED.
- One panel reading per behaviour: MEASURED; the choice of reading is PLACEHOLDER.
- Wrists use the elbow k and ankles the knee k: PLACEHOLDER.
- Responsiveness 15, joint limits: PLACEHOLDER.

**Life fading:** k × life / life at the reading. INFERRED from CHOKE; assumed for every behaviour.

**POSTURE profile:** a uniform 0.5, PLACEHOLDER. Never read in the footage, and BodyState never produces it.

**Unknown or not built:**
- "Doing" actions (Kick, Arch, Reach, Scoot, Tense, Convulse, Sway): UNKNOWN visuals; not built.
- Hits on lying bodies: no presentation response (BodyState records only; R12 UNKNOWN).
- Get-up: never seen (UNKNOWN).
- Despawn: none (bodies stay; UNKNOWN beyond ≈22 s).

**Not in this slice:** blood, gore, drag, pulse check, grenades, AI, vehicles, gun drop (the bots carry no guns),
bullet impulse (too small in the footage).

**Players:** player characters (R15) are not integrated.
- The design applies to them through the same attribute: the server would set `BodyPresentation` on a player's
  character.
- That needs network ownership and the client camera / controls to be handled first.

## Fidelity pass (2026-11-06, after acceptance)

**Goal:** replace the stiff forward topple with the footage's fall: legs give way first → the body drops → the upper
body keeps its orientation for part of the fall → active ragdoll. Same architecture (BodyPresentation → HitReaction /
ActiveRagdoll); BodyState unchanged. Evidence and decisions: `HitReactions_Analysis.md` §7.

### What changed (presentation only)
- **Staged fall** (`Config.BodyPresentation.Fall`, `ActiveRagdoll.step`):
  - A. the body stands on its held muscles for 0.15 s (LIMP 0.17 s);
  - B. the hip / knee / ankle muscles go slack and the knees are started forward (thighs about the hips, shins about
    the ankles), the upper body drifting forward with them;
  - C. a temporary world-orientation hold keeps the upper torso's orientation for 0.4 s (not for LIMP or DEAD);
  - D. the hold fades over 0.17 s while folding the upper body 35° forward and is destroyed; the leg muscles take
    hold again of the pose the legs went down in; the measured go-over (2.2 rad/s about the feet, forward) is applied.
    LIMP gets A and B only, so it sinks.
- **Joint limits** (`Limits`): knees and elbows are one-way hinges (no hyperextension); waist, neck, shoulders, wrists,
  hips and ankles are limited cones tilted toward flexion. Before: ball sockets with a symmetric 75° / 120° cone, so a
  knee could bend backwards.
- **Surfaces** (`Surface`): ragdoll parts get friction 0.8 and no bounce (same density). The SmoothPlastic default
  (friction 0.2) let the feet slide out about 1 stud during the fold. The cube thighs pass through their own feet
  (`NoCollidePairs`), as they would jam where a real thigh and calf compress.
- **Stumble** (`HitReaction`): while unstable, the knees sag 30° more over BodyState's own 0.9 s legs-gone delay, so the
  body has begun to descend when the fall starts. The pelvis drop now follows the bent legs and the ankles keep the
  feet flat (the old fixed 0.45-stud drop pushed the feet ≈0.17 studs into the ground).
- **Crawl force cap** = 2 × body weight × surface friction (the measured 0.6 studs/s is unchanged; with the new friction
  the old cap stalled the crawl at 0.11 studs/s).
- **Muscles:** the measured profiles, life fading, CRAWL, DEAD → limp are unchanged. Dead bodies' muscles are switched
  off (nothing left to solve).
- **Flinch:** unchanged. The footage's per-location readings overlap (§7.2), so no differentiation is justified.

### Before vs after (real shots; seconds from the start of the fall = the DYING hit, or BodyState's fall after the legs)

Metrics: support loss = pelvis 0.1 studs down; half drop = pelvis halfway to its lowest (torso tilt and knee bend
there show what led); ground contact = a knee (shin lying) or the torso / head / arms / thighs touching; down = chest
1.2 studs down; still = every part slower than 0.3 studs/s for 0.5 s.

| Case | | Support loss | At half drop: torso tilt / knee | Ground contact | Down | Still |
|---|---|---|---|---|---|---|
| Gut / throat / chest (REACT2–4) | before | 0.14–0.18 | **62–71° / 20–29°** (whole body tipping) | 0.50–0.57 (the torso hits) | 0.39–0.43 | ≈1.0–1.2 * |
| | **after** (3 runs) | 0.24–0.28 | **3–17° / 132–141°** (knees lead, torso upright) | 0.61–0.70 (knees) | 0.72–0.98 | 1.47–1.78 |
| Head, LIMP (REACT5) | before | 0.39 | 38° / 112° | 0.73 | 0.62 | ≈1.8 * |
| | **after** | 0.22–0.28 | 31–34° / 138–140° | 0.83–0.85 | 0.61–0.65 | 1.33–1.36 |
| Legs (REACT6) | before | 0.32 | 125° (head-first dive) | 0.47 | 0.43 | ≈1.4 * |
| | **after** | 0.07–0.08 (already sagging) | 24–26° / 139–140° | 0.64–0.71 | 0.56–0.67 | 1.24–1.28 |
| Footage | | 0.0–0.4 (F1 ≤ 0.13, F2 0.33–0.4, F3 0.17) | F1: aim pose held while sinking | F1 kneeling ≈0.6; F3 ≈0.5 | F2 flat ≈0.6 | F1 ≈1.1 |

\* The "still" metric was added in this pass; the before figures are its "settle" (from then on slower than
0.3 studs/s) from the same samples. The straight lying bodies did not sag afterwards, so the two agree.

**Side views** (`Captures/fidelity_side_view.png`, from the server's own samples; `draw_falls.ps1`):
- gut, before: one rigid plank tipping forward;
- gut, after: knees fold, the body sinks with the torso upright (0.2–0.4 s), folds forward onto the knees (0.5–0.8 s)
  and face (≈1.1 s);
- legs, after: sinks from the stumble crouch and rolls onto its back;
- LIMP, after: sinks almost straight down from ≈0.2 s and lies on its back (before: stood ≈0.4 s).

**Viewport:** `Captures/fidelity_fall_gut_strip.png` (frames in `Captures/fidelity_fall_gut/`) against the accepted
`Captures/fall_gut_strip.png`.

### Tests (fidelity pass)

| Test | Result |
|---|---|
| Real shots, H1–H6 (arm, gut, throat, chest ×3, head, legs ×2 + a hit while down) | M4 6 / 6 (three runs, including the final code), AK 6 / 6. Visible-fall samples between standing and down: 8–19 per fall (before 5–7; threshold 5, unchanged) |
| Dying states (PRES1: SHOCK, WRITHE, CHOKE + fading, PANIC, AGONAL, LIMP, CRAWL, DEAD, distinct) | 11 / 11 (10 / 11 before the crawl-force fix: CRAWL 0.11 studs/s; after: 0.60 studs/s) |
| Client tampering | pass: no ragdoll, root anchored, velocity 0 |
| After every fall | no upper-body hold left, the staged fall over, 4 hinges + 10 cones, server-owned (0 client parts); DEAD bodies 0 active muscles |
| Reset / respawn | fresh bots from the templates before every run; player death → respawn 3.35 s, not ragdolled |

### Regressions (fresh playtest)

| Check | Result |
|---|---|
| BodyState | unit 42 / 42; real shots M4 6 / 6, AK 6 / 6; forged requests rejected (INJURED / 100, the server's own `leftleg / Limb`); BODY1–6 have no `BodyPresentation` |
| Ballistics | unit 10 / 10 for every lane and weapon (sequences as accepted); real shots 18 / 18: A / B 25 damage, C none |
| AK | equip; raise 0.129 / lower 0.288 s, FOV 70; hip burst 640 RPM, climb 1.235°; full magazine (normal / stressed) 640 RPM, 31 shots, 0 rejected, climb 1.95°; reloads 2.431 / 1.667 / 3.131 / 2.766 s, label 1.067 s; label sequence / repeat; refusals; switch (23 + 1 kept); repeated |
| M4 firing | single; hip burst 770 RPM; ADS magazine 770 RPM, thirds 0.94 / 1.23 / 1.24°, recovery 0.742 s; hip / stressed magazines 770 RPM, recovery 0.741–0.742 s; stop; weapon reset |
| M4 reloads | 3.531 / 3.064 / 3.696 / 3.599 s; refusals; partial reserve; while aiming; switch during; repeated |
| M4 HUD | 1.702 / 1.734 / 1.603 s, labels as accepted; states and check: 0 mismatches |
| Death / respawn | 3.35 s; one viewmodel; 5 shots, 0 rejected |
| Original reload test | 3.530–3.542 s (one 3.711 s outlier during the heavy batches) |
| Console | no errors |
| Scripts | 48 / 48 in Studio = `Roblox/Scripts/src`. Against `Checkpoints/2026-11-06_hitreactions`: changed `Config.BodyPresentation`, `Server.ActiveRagdoll`, `Server.HitReaction`, `Server.BodyPresentation`, `HitReactionTest.Run` (server); 43 byte-identical (BodyState, BodyHit, WeaponServer, Ballistics and every weapon script included) |

**M4 Stressed reload end pose (separate, not fixed here):** still outside the README's 2.5° in some runs: 3.00°
(tactical) and 1.28° (empty) this time; 1.40–5.12° earlier. The M4 client code is byte-identical to the accepted
baseline.

### Remaining visual mismatches
- **F1 ends seated** (legs folded, torso upright). Here non-LIMP bodies fold forward onto their knees and front. The
  reference's muscle strengths (k ≈ 0.2–0.4 of a limb's weight) can't hold a seated trunk up, and no balance
  controller is modelled.
- **Leg-hit and LIMP bodies roll onto their backs** after sinking; the direction rule is UNKNOWN (F7).
- **Still at 1.25–1.78 s** against F1's ≈1.1 s; the chest is down at 0.72–0.98 s for vital hits (F2 flat ≈0.6 s).
- **No weapon or aim pose on the bots**, so "upper body keeps aiming" is the torso / head orientation only; the arms
  hang.
- **The fold is the same every time** (forward, same angles); the footage varies.
- **Settled bodies with folded legs keep sagging slowly** as life drains (the muscles fade); intended, but it makes
  "settle" long for CRYING / CHOKE bodies.
- **Blocky rig artefacts:** cube thighs need the thigh–foot no-collide; the fold angles are those of this rig.