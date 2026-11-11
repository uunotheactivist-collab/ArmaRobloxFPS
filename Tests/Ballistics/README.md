# Minimum ballistic slice: focused test

**What it proves:** the M4 and the AK fire through **one shared, server-authoritative bullet pipeline**:
muzzle (server eye) → trajectory → surface hit → penetration decision → exit → continued trajectory → target hit.

The footage analysis comes first: `ReferenceAnalysis/Ballistics/Ballistics_Analysis.md` (CONFIRMED / INFERRED /
UNKNOWN; written before any implementation).

## Pieces

| Piece | Where | Role |
|---|---|---|
| Shared tracer | `ServerScriptService.Server.Ballistics` | `trace(origin, direction, {Range, PenetrationStuds}, ignore)`, `classify(part)`. No weapon-specific code |
| Surface classes | `ReplicatedStorage.Shared.Config.Ballistics` | `Penetrable` / `NonPenetrable` / `Target`; attribute `BallisticSurface` on a part or its model |
| Weapon values | `Config.Weapons.M4` / `AK` → `Ballistics` | `PenetrationStuds` (placeholder 2.0 for both); M4 also records 800 m/s and 4 g (measured, unused) |
| Authority | `Server.WeaponServer` | validates the shot, traces from **its own** head position, applies damage to every target the trace reached |
| Range | `Workspace.BallisticTest` (built by `build_range.luau`, saved in the place) | lanes A / B / C at x = −200 / −175 / −150 |
| Server test | `ServerScriptService.BallisticsTest.Run` | `unit`, `arm`, `report`, `draw`, `clearDraw` |
| Client test | `StarterPlayerScripts.BallisticsTest.Run` | stands on each lane's spot, aims at the target's torso and fires real shots through the production controller |

**Method: instant segment tracing.**
1. Raycast from the current point for the remaining range.
2. At a surface, classify it.
   - **Target:** record the hit (once per character per shot).
   - **NonPenetrable:** stop at the entry point.
   - **Penetrable or Target:** find the exit by casting back from 12 studs beyond the entry against that part only.
3. Charge thickness × cost per stud against the weapon's budget.
   - Exit and continue straight from 0.01 stud past the exit if it fits.
   - Otherwise stop inside.

No parts are created per bullet. Nothing travels visibly (footage B10, B11).

### Range layout

All lanes share the same layout, z decreasing downrange:

| Item | Position | Detail |
|---|---|---|
| Shooter spot | z = 150 | |
| Wall (lanes B and C only) | z = 130 | B: Penetrable 10 × 10 × **0.5** WoodPlanks. C: NonPenetrable 10 × 10 × **2** Concrete |
| Target | z = 110 | R6-style anchored dummy, model attribute `Target`, Humanoid 100 HP |
| Backstop | z = 90 | NonPenetrable 12 × 12 × 2; shows where a bullet that passed through the target ends |

## How to run (Studio playtest)

```lua
-- Server data model
local Run = require(game.ServerScriptService.BallisticsTest.Run)
Run.unit({ "M4", "AK" }, 10)   -- direct traces, no client
Run.arm()                      -- clear the server's records, watch target health
-- Client data model
require(game.Players.LocalPlayer.PlayerScripts.BallisticsTest.Run)({ weapons = { "M4" }, lanes = { "A", "B", "C" }, shots = 5 })
-- Server data model
Run.report()                   -- the server's own records of those shots, checked per lane
Run.draw(6)  Run.clearDraw()   -- temporary debug lines (test visual only)
```

**Reading the records.** The server keeps its last 64 traces (Studio only). Test code run from the command bar or
MCP gets its own copy of the module, so the running server's copy also answers through the Studio-only
BindableFunction `Server.Ballistics.RecentResults`, created at run time.

## Expectations

| Lane | Event sequence | Target |
|---|---|---|
| A: shooter → target | Enter Torso → Exit Torso → Enter Backstop → Stop (NonPenetrable) | hit once |
| B: shooter → 0.5-stud Penetrable wall → target | Enter wall → Exit wall (0.5) → Enter Torso → Exit Torso → Enter Backstop → Stop | hit once |
| C: shooter → NonPenetrable wall → target | Enter wall → Stop (NonPenetrable) | **not hit**, health unchanged |

All lanes have two more checks:
- every segment keeps the shot's direction (collinear);
- every continued segment starts at the previous exit.

## Results (2026-11-06, Studio playtest)

### Unit traces (server, both weapons' config values, 10 repeats per lane)

| Lane | M4 | AK | Sequence | Budget left | End z |
|---|---|---|---|---|---|
| A | 10/10 | 10/10 | Enter:Torso > Exit:Torso (t = 1.001) > Enter:Backstop > Stop:Backstop (NonPenetrable) | 1.750 | 91 |
| B | 10/10 | 10/10 | Enter:PenetrableWall > Exit (t = 0.500) > Enter:Torso > Exit (t = 1.001) > Enter:Backstop > Stop | 1.249 | 91 |
| C | 10/10 | 10/10 | Enter:NonPenetrableWall > Stop (NonPenetrable) | 2.000 | 131 |

### End to end: real shots through the production pipeline (Tests A–C, then Test D = A–C with the other weapon)

5 shots per lane per weapon. The table shows the server's own trace records and the target's health watcher.

| Weapon | Lane | Pass | Damage per shot | Target health drops | Sequence (every shot) |
|---|---|---|---|---|---|
| M4 | A | 5/5 | 25 ×5 | 5 | Enter:Torso > Exit:Torso (1.000) > Enter:Backstop > Stop:Backstop |
| M4 | B | 5/5 | 25 ×5 | 5 | Enter:PenetrableWall > Exit (0.500) > Enter:Torso > Exit (1.000) > Enter:Backstop > Stop |
| M4 | C | 5/5 | 0 | **0** | Enter:NonPenetrableWall > Stop:NonPenetrableWall (NonPenetrable) |
| AK | A | 5/5 | 25 ×5 | 5 | as M4 A |
| AK | B | 5/5 | 25 ×5 | 5 | as M4 B |
| AK | C | 5/5 | 0 | **0** | as M4 C |

In every shot the path stayed collinear and each continued segment started at the previous exit. The trace
origins were within 0.09 stud of the lane's eye point (x, z), at the server's head height (y 4.00).

**Server log.** B-lane hits read
`l529s M4 hit Target.Torso for 25 (100 -> 75) after penetrating 1 surface(s)` (the same for the AK).

**Visual.** `Captures/lanes_topdown.png` shows the last shot per lane, top-down, with shooters on the left. Lines are
yellow, entry markers red, exit markers orange and stop markers cyan. Lane A passes through the target to the
backstop, lane B through the wooden wall and the target to the backstop, and lane C ends at the concrete wall.
`Captures/lanes_overview.png` is an oblique view. The lines are thickened for the capture and removed afterwards.

### Server authority (forged client shots, AK, from lane C)

The client fired the `WeaponFire` remote directly:

| Forgery | Server result |
|---|---|
| Honest origin and direction, plus a hit position and a hit part (the target's torso) as extra arguments | extras ignored; the server trace stopped at the NonPenetrable wall; no damage |
| Origin on the far side of the wall (z = 125) | **rejected**: "origin 24 studs from head" |
| Direction pointing behind the shooter | **rejected**: "direction behind the shooter" |
| Origin moved 4 studs forward (allowed offset 8) | accepted, but the trace **started at the server's head** (z 149.95, not the client's 145.95) and stopped at the wall |

The remote's signature is `(weaponId, origin, direction)`: a hit position is never read.

## Regressions (same session, after the change)

| Check | Result |
|---|---|
| AK `equip`, `hipBurst`, `raised`, `fullMag` (+ stressed) | 640 RPM; 31 shots; raise 0.127 s / lower 0.288 s, FOV 70; roll 6.0° → 7.37°; climb 1.23° (hip) / 1.95° (full magazine); 0 rejected |
| AK reloads | 2.430 / 1.663 / 3.134 / 2.764 s (tactical regular / stressed, empty regular / stressed); 0 shots during; 3 accepted after each; label "[TAB] 5.45 MAG" at 1.067 s |
| AK labels, refusals, switch, repeated | as accepted (`Full` / `NoReserve`; AK 23 + 1 kept across a switch; `Busy`; 3 bursts of 6 accepted) |
| M4 firing | 770 RPM; 31 shots ADS / hip / stressed; recovery 0.741–0.745 s; stop and weapon reset as accepted |
| M4 reloads | 3.529 / 3.065 / 3.697 / 3.599 s; correct ammunition; refusals, partial reserve, while aiming, switch during, repeated: as accepted |
| M4 HUD | label at 1.700 / 1.734 / 1.601 s ("[TAB] 5.56 MAG", "+1", "+2"); all states match; client = server |
| Death / respawn | respawn 3.6 s; one AK viewmodel, 30 + 1 with full reserve; 5 AK shots and 1 M4 shot accepted |
| Original reload test (`M4AnimTestRunner`) | 3.530–3.542 s (first play includes loading) |
| Console | no errors, no rejected shots (other than the deliberate forgeries above) |
| Scripts | 37/37 in Studio identical to `Roblox/Scripts/src`. Against `Checkpoints/2026-11-06_before_ballistics`: **changed** `Config.Weapons.M4`, `Config.Weapons.AK` (a `Ballistics` table only), `Server.WeaponServer`; **new** `Config.Ballistics`, `Server.Ballistics`, two `BallisticsTest.Run`; all 30 others byte-identical (every client weapon script, M4/AK data, foundation, test blaster, original reload test) |

## Placeholders and open points (need review)

- **Penetration budget 2.0 studs (both weapons) and Penetrable cost 1.0 / stud: placeholders.** The footage shows no
  wall being penetrated (B13), so they only make the test range behave as the brief describes.
- **Target cost 0.25 / stud: placeholder.** Bodies are passed through in the footage (B1, B2); how much they cost is
  not shown.
- **Deflection at bodies (B4)** is visible in the footage but its rule is UNKNOWN. Not implemented.
- **Two-colour trajectory (B6)** is visible, but its meaning is UNKNOWN. The test draw uses its own colours.
- **AK ballistic values:** UNKNOWN (the AK is not in the footage).
- **800 m/s and 4 g** are recorded for the M4 but unused by the instant trace.
- **Damage** is still the existing placeholder 25 per character per shot (no falloff, no reduction after
  penetration; B9 and B14 are UNKNOWN).
- **The brief was cut off after "Test D Repeat A–C".** Test D was run as A–C repeated with the other weapon (and with
  more shots).
- The foundation's `HitConfirm` → hitmarker presentation is unchanged (it existed before; no new hit markers).
