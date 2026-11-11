# Body hit + body state foundation: focused test

**Proves** that the server, from its own ballistic trace, decides a body's hit location, wound and state
(ALIVE → INJURED → DYING → DEAD), for the M4 and the AK, with nothing taken from the client.

**Basis:** `ReferenceAnalysis/BodyState/BodyState_Analysis.md`, which records every rule with its tag
(CONFIRMED / INFERRED / PLACEHOLDER).

## Pieces

| Piece | Where | Role |
|---|---|---|
| Data | `ReplicatedStorage.Shared.Config.BodyState` | Location labels, the part → location map, throat band, wounds, severity, per-hit losses, fall times, the dying behaviour per wound, life drain, tags |
| Location | `ServerScriptService.Server.BodyHit` | `locate(part, point)` → location (`head` / `chest` / `abdomen` / `leftarm` / `rightarm` / `leftleg` / `rightleg`), zone (`throat`), wound |
| State | `ServerScriptService.Server.BodyState` | `isBody`, `applyHit` (the only entry), Heartbeat (recovery, falls, drain, death), published attributes, Humanoid health mirror, temporary debug tag and pose for test bots, Studio-only hook `BodyStateDebug` |
| Hook | `Server.WeaponServer` | For each `trace.Targets` entry whose model has `BodyModel`, call `BodyState.applyHit(humanoid, part, point, weapon)` instead of the placeholder damage |
| Range | `Workspace.BodyStateTest` (`build_range.luau`, saved in the place) | Six anchored R6 test bots BODY1–6 (`BodyModel`, `BodyDebugView`) at x = −270 … −320, z = 110, spots at z = 125, backstop z = 100 |
| Server test | `ServerScriptService.BodyStateTest.Run` | `unit()`, `arm()`, `report(weapon)`, `reportForged()` |
| Client test | `StarterPlayerScripts.BodyStateTest.Run` | Real shots through the production controller (`{ weapon = "M4" }`), forged requests (`{ forged = true }`) |

**How a location is determined:**
- the server's trace gives the part and the entry point;
- Head → `head`; arms / legs by part name;
- the R6 Torso by the entry point's height in the torso's own frame: upper half `chest`, lower half `abdomen`;
- the top 0.3 studs of the chest is the `throat` zone (label still `chest`, as in the reference);
- R15 part names map the same way.

## How to run (Studio playtest)

```lua
-- Server
local R = require(game.ServerScriptService.BodyStateTest.Run)
R.unit()        -- 42 checks with simulated time
R.arm()         -- reset BODY1–6, clear records
-- Client
require(game.Players.LocalPlayer.PlayerScripts.BodyStateTest.Run)({ weapon = "M4" })   -- then "AK"
-- Server
R.report("M4")
-- forged: R.arm(); client Run({ forged = true }); server R.reportForged()
```

## Results (2026-11-06)

### Server unit suite: 42 / 42
- **Locations, all 8 points:** head → head / Brain; throat → chest / throat / Throat; chest → chest / Lung;
  abdomen → abdomen / Gut; each arm and leg → its own label / Limb.
- **Boundaries:**
  - torso local Y 0.69 → chest; 0.71 → throat;
  - 0.01 → chest; −0.01 → abdomen;
  - all 8 results distinct.
- **Arm:** INJURED, strength 97 %, flinch on; after 1 s strength 100 %, flinch off.
- **Gut:** DYING at once (no flinch) → down after 0.53 s → CRYING; ≈3.6 %/s (life 60–70 % after 10 s) → AGONAL
  below 20 % → DEAD, health 0.
- **Throat:** DYING; still falling at 1.0 s, down at 1.07 s → CHOKE → DEAD.
- **Lung:** chest hits 1–2 stay up (66 %, then recovered and hit again); the 3rd collapses (strength ≤ 15 %) → CRYING,
  Lung wound.
- **Brain:** DYING with LIMP at the hit, strength 0 → down by 0.5 s → DEAD within 2.3 s, health 0.
- **Legs:** legs 20 → 0, unstable; standing at 0.8 s, falling at 0.9 s → down → SHOCK, Limb; no drain (life 100 %
  after 10 s).
- **Repeated hits:**
  - a hit on a DYING body is recorded only (behaviour unchanged, hit count +1);
  - a hit on a DEAD body is ignored;
  - limb then brain → Brain / DYING; limb then throat → Throat (most severe kept);
  - a 7-hit sequence plus 6 s of time: no invariant broken (phase never goes back; DEAD ⇒ life 0 and health 0;
    life drains only when down; behaviour only when down (LIMP excepted); no flinch outside INJURED);
  - exactly one tag per body.
- **Authority:** the published attributes equal the server's own state.

### Real shots through the production pipeline: M4 6 / 6, AK 6 / 6

| Bot | Shots | Server's records (both weapons) | State afterwards |
|---|---|---|---|
| BODY1 | right arm | rightarm : Limb : ALIVE → INJURED | standing, INJURED |
| BODY2 | abdomen | abdomen : Gut : ALIVE → DYING | down, CRYING, draining |
| BODY3 | throat point | chest / throat : Throat : ALIVE → DYING | down, CHOKE |
| BODY4 | chest, one 3-round burst | chest : Lung : ALIVE → INJURED, INJURED → INJURED, INJURED → DYING | down, CRYING, Lung |
| BODY5 | head | head : Brain : ALIVE → DYING (LIMP) | DEAD, health 0 |
| BODY6 | left leg, right leg, then the body while down | leftleg → INJURED, rightleg → INJURED (unstable), third hit recorded only | down, SHOCK, Limb, legs 0 |

- Server log lines read, for example, "M4 hit body BODY3.chest/throat → Throat wound, ALIVE → DYING".
- `Captures/bots_after_AK_run.png` shows the temporary debug tags and poses about a minute after the AK run: BODY1
  INJURED standing; BODY2, BODY3 and BODY5 DEAD; BODY4 AGONAL 10 %; BODY6 SHOCK 100 %.

### Invalid client requests (M4): pass
- **Client-side attribute write** (`BodyPhase = DEAD`, `BodyLife = 0`): stays local. The server has INJURED / 100,
  Humanoid health 100.
- **`WeaponCommand("SetBodyState", …)`:** no such command; ignored.
- **A real shot at BODY1's left leg** with forged extra arguments (hit table "head / Brain / DEAD", the head part,
  "head"): the server recorded `leftleg / Limb`, its own trace's result.
- **Remotes:** none accepts body state (FireWeapon, HitConfirm, WeaponFire, WeaponCommand, WeaponState).

## Regressions (same day, fresh playtest)

| Check | Result |
|---|---|
| Ballistic unit traces | M4 and AK lanes A / B / C 10 / 10, sequences identical to the accepted ones |
| Ballistic real shots | M4 and AK, 3 per lane: A and B 25 damage per shot, C none; 18 / 18 pass (lane targets are not body bots, so the old damage path stays) |
| AK | equip; raised 0.126 / 0.288 s, FOV 70; full magazine 640 RPM, 31 shots, 0 rejected, climb 1.95°; hip burst 640 RPM, climb 1.23°; reloads 2.430 / 1.663 / 3.132 / 2.766 s, label at 1.071 s; label sequence and repeat; refusals; switch; repeated (Busy ×3, 3 bursts accepted) |
| AK hip-burst "rollDuring" | 0.7–2.9° this session vs 7.37° at acceptance. This value is **one frame** of random per-shot kicks (unseeded `Random.new()`). A full trace shows the weapon held canted (3.8–8.8° around the 6° rest), i.e. no de-cant. All client weapon code is byte-identical to the baseline. Not a regression |
| M4 firing | single; hip burst 770 RPM; ADS / hip / stressed magazines 770 RPM, 31 shots, recovery 0.740–0.742 s; stop; weapon reset |
| M4 reloads | 3.532 / 3.065 / 3.700 / 3.599 s; refusals; partial reserve; while aiming; switch during; repeated |
| M4 HUD | sequence 1.704 / 1.736 / 1.603 s, client = server; all states; check |
| Death / respawn | respawn 3.37 s; one AK viewmodel, 30 + 1, 4 spare magazines; shots accepted after |
| Original reload test | 3.533–3.544 s, with one 3.712 s outlier during the heavy test batches (first play includes loading) |
| Console | no errors, no rejected shots (besides the deliberate forgeries) |
| Scripts | 42 / 42 in Studio = `Roblox/Scripts/src`. Against `Checkpoints/2026-11-06_before_bodystate`: **new** Config.BodyState, Server.BodyHit, Server.BodyState, two BodyStateTest.Run; **changed** Server.WeaponServer only; 36 byte-identical |

## Correction pass (2026-11-06, after review): rerun
- **Status labels only; behaviour unchanged.** Changed: `Config.BodyState` (statuses + `RuleStatus` /
  `DownBehaviourStatus`) and `Server.BodyState` (comments, `BehaviourStatus` in records, the debug-tag placeholder
  marker). Checkpoint `Checkpoints/2026-11-06_bodystate_cleanup`.
- **Body state:**
  - unit 42 / 42;
  - Gut CRYING and Limb SHOCK report `BehaviourStatus = PLACEHOLDER` and the tag shows "· behaviour PLACEHOLDER";
  - Throat CHOKE and Brain LIMP report CONFIRMED.
- **Real body hits:** M4 6 / 6, AK 6 / 6; forged requests pass.
- **Ballistics:** unit 10 / 10 per lane for both weapons; real shots 18 / 18 (A / B 25 damage, C none).
- **AK:**
  - equip; raised 0.126 / 0.287 s;
  - firing: full magazine 640 RPM 31 shots, 0 rejected; hip burst 640 RPM;
  - reloads 2.433 / 1.668 / 3.132 / 2.767 s, label at 1.07 s; label sequence / repeat; refusals; switch; repeated.
- **M4:**
  - firing: single, hip burst, ADS / hip / stressed magazines 770 RPM, recovery 0.742–0.745 s, stop, weapon reset;
  - reloads 3.532 / 3.068 / 3.700 / 3.597 s plus refusals, partial reserve, while aiming, switch during, repeated;
  - HUD sequence 1.701 / 1.736 / 1.603 s; HUD states; check.
- **Other:** death / respawn 3.36 s; the original reload test 3.532–3.546 s (one 3.721 s outlier during a heavy batch);
  no console errors.

## Placeholders and open points
See `BodyState_Analysis.md` §3–5 and `Config.BodyState.RuleStatus`. **None of these is accepted reference
behaviour:**
- throat band 0.3 studs: INFERRED / PLACEHOLDER;
- collapse at strength ≤ 15 %: PLACEHOLDER (configurable for tests);
- immediate DYING for Brain / Throat / Gut: PLACEHOLDER rule;
- Gut CRYING and Limb SHOCK once down: PLACEHOLDER / INCOMPLETE (temporary test behaviour; no selection formula);
- hits on a DYING body recorded only: UNKNOWN; a temporary implementation choice, not a rule;
- DEAD at life ≤ 0: IMPLEMENTATION RULE / NOT DIRECTLY PROVEN BY FOOTAGE;
- fall times other than brain / throat / gut, and the flinch duration: PLACEHOLDER;
- player characters (R15): not integrated. The design covers R6 / R15 bots and R15 players through the same
  server-authoritative system.

The tests check the implementation as it stands. A check that relies on one of these labels (e.g. E2 "→ CRYING",
E6 "→ SHOCK", the "recorded only" result) tests the temporary behaviour, not a reference rule.
