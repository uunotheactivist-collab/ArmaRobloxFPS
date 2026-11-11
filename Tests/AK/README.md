# AK slice: focused test and reference comparison (2026-11-06)

Reference: `Reference/Weapons/AK/ak animation.mp4`, analysed in `ReferenceAnalysis/AK/AK_Analysis.md` before
implementation. Test module: `StarterPlayerScripts.AKTest.Run` (copy: `AKTest_Run.luau`). Studio playtest only;
delete the `AKTest` folder to remove it.

## Final cleanup after acceptance (2026-11-06) and verification

**Decisions applied:**
- **AK label:** fixed "[TAB] 5.45 MAG"; no "+N", no count (a 0/1 flag), no inventory effect; meaning UNKNOWN. The M4
  label behaviour is unchanged (shared `MagazineLabel` shows a suffix only when a weapon's config has `CountSuffix`).
- **State `Raised`** (not ADS): config `AK.Raised`, data `Poses.Raised` / `RaisedIn`, no zoom fields, so the FOV stays
  at 70 while aiming.
- **Inferred items** are marked in `Config/Weapons/AK`: 30 + 1, arm placement, magazine path, charging-handle path,
  Stressed empty ending, shake time constant.
- **Post-tactical hold:** exit UNKNOWN; no exit animation added.
- **Shake and recoil values** unchanged.
- **Visual pass, measured** (`AK_Analysis.md` Appendix A4):
  - darker, non-reflective metal/polymer and darker wood: lit-face luminance 0.43 → 0.29, body 0.215 → 0.191;
  - the arm change was tried, measured worse, and reverted;
  - the charging-pose width is a pose/model property, documented.

  Reload clips are byte-identical to the accepted version.

**Final verification (one Studio session, final data):**

| Area | Result |
|---|---|
| AK equip / hip burst / raised | 1 viewmodel, 1 HUD; 640 RPM, roll 6.0° → 5.7° in the burst (no de-cant); raised 0.130 s / 0.287 s, **FOV 70 → 70 → 70** |
| AK full magazine, Regular and Stressed | 31 shots at 640 RPM, 0 on empty, shake 0.514° / 0.482°, muzzle sd 1.69/2.50° and 1.82/2.37°, 0 rejected |
| AK reloads | 2.432 / 1.666 / 3.134 / 2.767 s; 0 shots during; ammunition client = server; fire after accepted |
| AK label | Regular tactical and Regular empty: no label. Stressed tactical: "[TAB] 5.45 MAG" at 1.071 s. Stressed empty: unchanged. **`labelRepeat`: a second Stressed tactical reload leaves "[TAB] 5.45 MAG" and the flag at 1 (client and server)** |
| AK refusals / switching / repeated | `Full`, `NoReserve`; AK 23 + 1 kept across M4 ↔ AK, one viewmodel, reload cancelled by switching with the magazine unchanged; 3 × `Busy`; 18 shots, 0 rejected |
| Death / respawn | kill during an AK empty reload with the label shown: reload cancelled, viewmodel removed, HUD hidden within 0.25 s; after respawn (3.6 s) AK and M4 30 + 1 with 4 spare magazines, label cleared, client = server; 3 shots accepted |
| M4 firing (all 7 tests) | single, hip burst and full magazines at 770 RPM, 0 rejected; ADS climb thirds 0.99/1.32/1.42°, recovery 0.745 s; hip de-cant −32.6° → 0.2°; stop, weapon reset as accepted |
| M4 ADS | FOV 70 → **62.23** → 70 (unchanged) |
| M4 reloads (all 9 cases) | 3.532 / 3.066 / 3.700 / 3.597 s; charging 0.214 studs; refusals, partial reserve, while aiming, switch during, repeated as accepted |
| M4 HUD (sequence, states, check) | 1.703 / 1.737 / 1.601 s, "[TAB] 5.56 MAG", "+1", "+2"; all states match, client = server, 1 HUD |
| Original reload test | 3.529–3.544 s (one 3.707 s during the respawn hitch, as before) |
| Console | no errors, no warnings, no rejected shots |
| Scripts | 33/33 Studio = `Roblox/Scripts/src`; M4 config/data, all M4 tests, foundation and the original reload test byte-identical to `Checkpoints/2026-11-06_before_ak` |

Comparison sheet: `ak_reference_vs_roblox.png` (final captures in `captures/final/`). The accepted-state captures and
sheet are in `captures/accepted/`; the silhouette masks and measurements are in `captures/masks/` and
`captures/final/compare_final.json`.

## How to run

In a Studio playtest, from the client (command bar or `execute_luau` on the Client data model):

```lua
local Run = require(game.Players.LocalPlayer.PlayerScripts.AKTest.Run)
Run("equip")  Run("hipBurst")  Run("raised")  Run("fullMag")  Run("fullMag", { stressed = true })
Run("reload", { kind = "tactical", stressed = false })   -- also "empty", stressed = true
Run("labelSequence")  Run("labelRepeat")  Run("refusals")  Run("switch")  Run("repeated")
```

Death and respawn are driven from the server (the client can't kill itself authoritatively):
`game.Players:GetPlayers()[1].Character.Humanoid.Health = 0` on the Server data model, while a client loop
samples the debug hook (procedure in "Death / respawn" below).

The firing statistics use the footage scripts' own definitions (`27_ak_fire_stats.py`,
`30_ak_recoil_measure.py`): 30 fps samples from the first to the last shot; camera pitch change = median of
|frame-to-frame difference|; muzzle screen position = sd (degrees) and median |frame difference| (pixels of the
432-px footage picture).

## Results at acceptance (Studio playtest)

| Test | Result | Footage / expected | |
|---|---|---|---|
| Equip | AK active, 1 viewmodel in the camera, 1 HUD copy, 30 + 1, reserve 4 × 30, client = server | — | pass |
| Fire rate | 640 RPM in every run (31-round magazine = 2.81 s) | 640 ± 25 RPM | pass |
| Capacity | 31 shots, then 0 shots on an empty rifle; client = server 0 + empty chamber | 30 + 1 (inferred) | pass |
| Hip burst posture | roll 6.0° before, 7.3° during the burst (kick only) | no de-cant (B1, B3) | pass |
| Raised posture (aim) | up 0.128 s, down 0.287 s, FOV 70 throughout | 0.13 s / 0.30 s, zoom 1.000 | pass |
| Camera shake, raised (4 runs) | median \|Δpitch\| 0.43 / 0.56 / 0.49 / 0.60°, mean 0.52° | 0.48–0.59° | pass (calibrated) |
| Camera shake, hip (5-shot bursts) | 0.32–0.89° (few samples, noisy) | 0.48–0.59° | consistent |
| Muzzle jitter, raised (10 runs with the final kick values) | sd 1.4–2.0° h / 2.3–2.9° v; median \|Δ\| 5.4–11 px h / 8.6–17 px v | sd 1.6° / 2.75°; 6 / 12 px | pass (calibrated) |
| Climb | peak 1.94–1.95° (raised), 1.22–1.24° (5-shot hip); below 0.05° 0.80 s after the last shot | B4 peak +2.3° (raised), back to +0.3° 0.6 s after the last shot; B3 +1.5° (hip) | close (model fitted to B3/B4, rms 0.37–0.41°) |
| Server validation | every shot accepted in the tests (0 rejected, cumulative counts up to 267) | — | pass |
| Regular tactical reload | 2.432 s; old magazine (26) back in the reserve; 0 shots during the reload; 3 shots after, all accepted | 2.433 s (frames 46–119) | pass |
| Stressed tactical reload | 1.663 s; label "[TAB] 5.45 MAG" appears at 1.067 s into the clip | 1.667 s; label at frame 437 = 1.067 s | pass |
| Regular empty reload | 3.131 s; 29 + 1 after; charging handle travels 0.120 m; empty magazine not kept | 3.133 s (256–350) | pass |
| Stressed empty reload | 2.765 s; 29 + 1 after | ≥2.53 s visible, 2.767 s with the inferred end | pass |
| Label sequence (footage order) | Regular tactical: no label · Regular empty: no label · Stressed tactical: label appears at 1.07 s · Stressed empty: label unchanged, no suffix | the same in the footage | pass |
| Refusals | full magazine → `Full`; no spare magazine → `NoReserve` | — | pass |
| Switching | AK 23 + 1 kept while the M4 is out (M4 30 + 1, separate); one viewmodel at a time; switching during an AK reload cancels it with the magazine unchanged | — | pass |
| Repeated | 3 reloads in a row: second press during each → `Busy`; partly used magazines kept (27, 26, 25); 3 bursts of 6 all accepted | — | pass |
| Death / respawn | within 0.25 s of the server kill: reload cancelled, viewmodel removed, HUD hidden. After respawn (~3.3 s): one AK viewmodel, AK and M4 both 30 + 1 with full reserve, label cleared, no reload; 3 shots after respawn accepted | — | pass |
| Clip joints | the rifle returns exactly to the rest pose at the end of every clip (0.0000 studs, 0.00°); the magazine leaves and returns | — | pass |
| Console | no errors or warnings except one expected test artefact (below) | — | pass |

**One rejected shot, test artefact.** In a death probe the test pressed the trigger in the same frame as a
Studio-only `DevRefill`. The server's "DevRefill" state message arrived mid-burst and reset the client's
prediction to a full magazine, so the client sent one shot more than the server had. The server rejected it
("empty") and corrected the client. This path is shared with the M4 and existed before this milestone; with a pause
after a refill (as in every test above) it doesn't happen.

## Regressions (M4 and foundation), same session

| Check | Result |
|---|---|
| M4 HUD sequence | label at 1.704 / 1.734 / 1.602 s ("[TAB] 5.56 MAG", "+1", "+2"), client = server |
| M4 HUD states | all 6 states match (partial magazine, ADS, shown, full + refused, switched away / back) |
| M4 reloads | all four: 3.532–3.533 / 3.066 / 3.698 / 3.596–3.599 s, correct ammunition, 0 shots during, fire after accepted; refusals, partial reserve, while aiming, switch during, repeated: all as accepted |
| M4 firing (`adsMag`, 5 runs) | 31 shots at 770 RPM, 0 rejected, recovery 0.740–0.743 s; climb thirds within the earlier run-to-run spread |
| Original reload test (`M4AnimTestRunner`) | 3.529–3.542 s throughout (first play includes loading) |
| Scripts | all 33 in Studio identical to `Roblox/Scripts/src` (length:hash). Foundation scripts, the three M4 tests and the original reload test identical to the pre-AK checkpoint |

## Reference vs Roblox (`ak_reference_vs_roblox.png`)

Twelve states, each as: footage frame | Roblox capture mapped to the footage camera (vertical FOV 70, principal
point (239, 229), so the horizon lines up) | 50/50 blend | 4× insets of the label region (footage above, Roblox
below). Reload poses are held with the debug hook's `freeze` at the clip time of the footage frame; the camera pitch
is set from that frame's horizon. Built by `make_comparison.ps1` from `captures/` (spec: `captures/_spec_all.txt`).

**Measured.** The live Roblox viewmodel projects the AK's landmarks exactly where the fitted Blender pose does
(front post, charging knob, grip, muzzle, ejection port: ≤ 0.1 px), so the conversion is exact and the remaining
differences come from the fits and the scene.

**What matches:**
- the hip idle (frame 10): near-vertical rifle, front post at the same pixel (±3 px), knob on the right;
- the raised posture (145): rifle upright, no zoom, post at the same place;
- the hip burst (22): the flash lights the floor and the arm; brass flies to the right;
- the reload stretches with the arm away (70, 300) and the arm returning (100, 680);
- the HUD label (437, 640, 470): same text, same row and horizontal extent (insets).

**Known differences:**
- **Lighting.** Studio's daylight is far brighter than the dark overcast footage. Since the final visual pass the
  rifle reads as a dark silhouette (no sky reflection), but it is still lighter than the footage's near-black.
  Environment and lighting are a later slice.
- **Charging poses (338, 700).** The rifle silhouette is 22 % / 8 % wider than the footage's (rows 330–425; capture
  silhouette IoU 0.63 / 0.59). That is the fitted pose and the model's proportions, so it was left unchanged rather
  than redesigning the model.
- **Arm.** The arm block is placed from the shoulder (INFERRED; its silhouette couldn't be fitted). Its top edge is
  within −8 to +3 px of the footage in the reload frames 100 / 338 / 700, and 8–10 px lower at idle and raised.
  Near the rifle it reaches further up the handguard. At 680 the footage arm re-enters ~2 frames earlier.
- **Post-tactical hold (470, also 120–131).** After both tactical reloads the footage rests in a lower,
  near-vertical hold with the knob hidden. The game returns to its single rest pose; how the footage gets from
  that hold back to the idle is never shown.
- Captures use the Regular presentation, so they have no Stressed sway.

**Blender previews:** `Blender/Animations/AK/previews/AK_Reload_<Clip>_side_by_side.mp4` show every clip frame
(footage | model at 85 % over it). Clip silhouette IoU against the footage (per frame in `ak_reload_clips.json`):

| Clip | mean | median | p10 | frames below 0.5 |
|---|---|---|---|---|
| TacticalRegular | 0.600 | 0.649 | 0.409 | first 5 and last 4 (blends from/to the rest pose), 23–24 |
| TacticalStressed | 0.577 | 0.658 | 0.298 | first 8, last 4 |
| EmptyRegular | 0.644 | 0.671 | 0.514 | first 3, 53, last 5 |
| EmptyStressed | 0.659 | 0.677 | 0.600 | first 4 |

The low frames are where a clip blends from or to the rest pose while the footage is in another resting variant
(post-burst, Stressed sway, post-tactical hold, end of the charging step). Mid-clip the clips track the fits. M4
for comparison: means 0.63–0.72.
