# Glock audio test (Glock audio fidelity slice + correction)

- **`GlockAudioTest.Run.client-module.luau`** is a copy of `StarterPlayer.StarterPlayerScripts.GlockAudioTest.Run`
  (also `Roblox/Scripts/src/StarterPlayer/StarterPlayerScripts/GlockAudioTest/Run.luau`). It is Studio-only.
- **What it is:** derived from `MP7AudioTest` (same machinery: WeaponController's debug hook, `"audio"` command), with the
  Glock's own rules:
  - semi-automatic, one shot per press, 450 RPM cap;
  - a 32-variant cycle: every shot plays the next variant (32 → 1) whatever the time since the last one; only a
    put-down restarts at 1;
  - **correction:** overlapping shot voices (a fixed pool of 9 per set), aimed shots on the centred variants 33–64, the
    hearing equaliser (inferred model) on every shot voice;
  - 21 sounds: two shot sets × 9 voices (each with a `Hearing` `EqualizerSoundEffect`), three reload clips (the Stressed
    empty reload uses the Regular empty clip).
  Delete the folder to remove it.
- **Before playtesting**, the sounds must be in Studio's content folder: run `Roblox/Assets/Audio/Glock/sync_to_studio.ps1`
  (again after every Studio update).
- Analysis and offline comparison: `ReferenceAnalysis/Weapons/Glock/Glock_Audio_Analysis.md` (Part 5 = the correction).
- `hearing()` (~90 s) and `perf()` outlast a 50 s tool call: run them in a `task.spawn` and poll.

```lua
-- Client datamodel, in a playtest
local Run = require(game.Players.LocalPlayer.PlayerScripts.GlockAudioTest.Run)
Run.assets()  Run.fire("single")  Run.fire("taps")  Run.fire("string")  Run.fire("rapid")  Run.fire("pause")
Run.fire("ads")  Run.fire("stressed")  Run.fire("cycle")  Run.stance()  Run.hearing()
Run.reloads()  Run.interrupt()  Run.switching()  Run.security()  Run.perf()
Run.death("before")  -- then on the Server: game.Players:GetPlayers()[1].Character.Humanoid.Health = 0
Run.death("after")   -- once respawned
Run.timeline("string")  -- raw play log (with aimed / regionStart / gains per shot)
```

## Results — Glock audio fidelity correction (Studio playtests, 2026-11-09)

Every Glock check is in `Run.luau`; "gains error" = the game's `EqualizerSoundEffect` against the test's own
evaluation of the model (independent code), at every shot start (logged gains) and at every frame for every playing
voice (its `eqAt` / `shotAt`), max over the pattern.

| Test | Result | Pass |
|---|---|---|
| assets | 21 sounds in `WeaponAudio_Glock`: `ShotRegular1–9`, `ShotStressed1–9` (64.0 s sprites, regions, one `Hearing` equaliser each), reloads 2.967 / 3.4 / 2.433 s (no equaliser); volume 0.1; `Config.Audio.Glock.Hearing` = the fitted numbers; M4 / AK / MP7: overlap off, no hearing, 8 sounds each | yes |
| fire single | 1 shot, 1 voice, played 0.981 s (its whole region), tail 1.019 s, gains 0 / 0 / 0 dB, server 1 | yes |
| fire taps (4 × 0.25 s) | 4 voices overlapping, every voice ≥ 0.981 s, 0 truncated / 0 recycled, gains error 0.000 | yes |
| fire string (16 × 0.165 s) | 16 / 16, **up to 7 voices at once**, every voice played ≥ 0.981 s, **0 truncated, 0 recycled**, 0 outside the region, tail 1.054 s, Play − shot 0 ms, gains error 0.000 (start) / 0.000 (2,766 frame samples), last shot −0.77 / −3.21 / −7.04 dB, server 16 | yes (after test defect 1) |
| fire rapid (450 RPM cap) | 8 shots, min spacing 0.133 s, **8 voices at once** (pool 9), 0 truncated / 0 recycled | yes |
| fire pause (3 × 1.2 s) | 1 voice at a time, gains 0.000 error | yes |
| fire ads (aimed string) | 16 / 16, every shot `aimed`, regions 32 + position (centred copies), 7 voices, 0 truncated | yes |
| fire stressed | 16 / 16 on `ShotStressed*`, first shot −0.17 / −5.26 / −16.73 dB (the onset muffle 0.6 s after Stressed turned on), 0 truncated | yes |
| fire cycle (34 × 0.2 s, refilled) | positions 1 … 32, **1, 2** (the wrap), consecutive voices always different, 6 voices, 0 truncated | yes |
| stance | hip → aim inside a string: shots 1–3 hip regions, 4–6 aimed; aim → hip: 1–3 aimed, 4–6 hip; the playing voices keep their own region (no re-pan), 0 truncated | yes |
| hearing — isolated | history < 0.001 first, then one shot: 0.000 / −0.000 / −0.000 dB | yes |
| hearing — strings (0.165 s) | High at shots 1 / 2 / 4 / 8 / 16: **0.00 / −2.10 / −4.43 / −6.18 / −7.02 dB** (short, medium and long agree shot for shot); gains error 0.000 | yes |
| hearing — pause then fire | last string shot −7.02 dB; **1.6 s later −4.71 dB**; 4.0 s after that **−0.66 dB** (recovered) | yes (after test defect 2) |
| hearing — stress onset | onset time = the Stressed attribute's arrival (lag 4 ms); first shot **−0.02 / −9.01 / −29.92 dB**, then −26.7, −23.8, −21.2 dB High | yes |
| hearing — stress continuation | Stressed kept on 3 s (set again: no new onset): first shot −0.02 / −0.08 / −0.18 dB; off → on again = a new onset (lag 4 ms) | yes |
| hearing — switch | a switch to the Sniper keeps the history (0.682 → 0.488 = the predicted decay) | yes |
| reloads | TR / ER / TS / ES each start their own sound once (ES = `ReloadEmptyRegular`), sound − clip mean −20 / −11 / −11 / −44 ms (engine start latency, as before), sound ends with the reload, reload → fire plays a shot, **no equaliser on reload sounds** | yes |
| interrupt | switch during a reload: stopped after 9 ms; **during three overlapping shot tails: all 3 stopped after 9 ms**; presses during a reload: 0 shot sounds; cancelled reload: 1 ms | yes |
| death | 2 shot voices + the reload playing at death: all stopped 5 ms after `Died`; after respawn the first shot is variant 1; one Glock folder; sound instance count unchanged (102 → 102 with the then-present probe) | yes |
| switching | Glock → M4 → AK → MP7 → Sniper → Glock: the Glock's voices only while the Glock fires, 0 of any other weapon; re-equip ×3: 1, 2; **rapid switching** (10 switches 0.15 s apart with presses): 0 Glock voices while away; instance count 63 → 63 | yes |
| security | a probe `WeaponAudio`: **1,000 shots in one frame** (both sets, both stances): 21 sounds / 18 equalisers before and after (nothing created), ≤ 18 voices, history capped at 256, 0 regions outside 0–63 s; odd inputs (aim nil / NaN / 1e9 / −5, Stressed "yes") → hip / aimed decided by aim ≥ 0.5 only, regions inside the sprite; **`Destroy()`**: folder gone, 0 connections, inert; global instance count 63 → 63 | yes (after test defect 3) |
| M4 / AK / MP7 audio suites | assets (8 sounds each), fire sustained (31 / 31 / 41 shots, **1 voice**), switching: all pass | yes |

**Performance (`perf()`, final code, uncapped ≈ 200 fps)** — before = the slice's README row below:

| Reading | Before (slice) | After (correction) |
|---|---|---|
| frame mean / p95: idle | 5.018 / 5.736 ms | 4.850 / 5.497 ms |
| Glock rapid presses (7 voices) | 4.978 / 5.558 | 5.016 / 5.746 |
| Glock string at 0.165 s (7 voices) | — | 4.843 / 5.299 |
| Glock empty reload | 5.027 / 6.235 | 4.851 / 5.469 |
| M4 / AK / MP7 sustained fire | 5.430 / 5.421 / 5.277 | 5.085 / 5.112 / 5.237 |
| `WeaponAudio:Shot` | 9.07 µs | 11.84 µs (history + equaliser) |
| reload start + stop | 8.16 µs | 7.43 µs |
| `State()` (test hook) | — | 39.3 µs |
| weapon Sound objects | 31 (8 + 8 + 8 + 7) | 45 (8 + 8 + 8 + 21) + 18 equalisers |
| Sounds memory tag | 10.21 → 10.49 MB | 11.70 → 12.07 MB (64 s sprites) |

Frame-time differences are inside the run-to-run spread (idle itself moved 0.17 ms); the Glock with 7 overlapping,
equalised voices costs no measurable frame time.

**Test defects found and fixed (not implementation failures; no check was loosened):**
1. **Hearing frame check** compared the equaliser with the model at the log's time stamp, taken after `Play()`; the
   module counts each shot from just before `Play()` (0.06–0.1 ms earlier). A frame landing in that window as a shot
   crossed its 0.1 s delay read 0.54 dB. The test now uses the voices' own `shotAt`; rerun 0.000.
2. **`pauseThenFire`**: the 16-shot string empties the 15 + 1, so the two later presses fired nothing; the pattern now
   refills before them (refill touches no sound).
3. **The probe** (`security()` / `perf()`) stayed in `SoundService` as `WeaponAudio_Glock_probe`, which the M4 / AK / MP7
   `assets()` "every audio folder belongs to a weapon" checks rightly flagged; `WeaponAudio:Destroy()` was added (used
   only by test probes) and the probe is destroyed after use; rerun: all pass. Also `perf()` first sampled the voice
   count with `playing()`, which walks the workspace (~0.5 ms a frame of test overhead); it now counts the Glock folder
   only.

**Console:** 0 errors and 0 warnings from game code in every correction playtest (only `[Weapon]` refill / reload lines
and `M4AnimTest`).

## Full regression — correction (one fresh playtest, AI first, Grenade suites last, background agent, 2026-11-09)

Read-only run on the saved place (SHA `9CA400A7…A102`); Studio listing 153 / `10945:105913230` before and after. The
playtest started uncapped (4.93 ms frames); **Studio throttled the play window to 60 fps from 20:22:10Z to 20:35:00Z**
(RenderScheduler push / pop in the Studio log; cause not logged) — the frame-sensitive readings were rerun uncapped.
Baseline: the slice's "Full regression" below (and the MP7 run). Classifications as the brief defines them.

| Area | Result | Classification |
|---|---|---|
| M4 (Firing / Reload / HUD) | 770 RPM, 0 new rejections; recovery 0.738 / 0.740 s; ADS 0.331 / 0.330, 0.120 / 0.123 s; reloads 3.533 / 3.067 / 3.698 / 3.598 s; HUD 13 / 0, labels 1.701 / 1.734 / 1.605 s | PASS |
| M4ModelFidelityTest | all pass; 10,466 tris; reloads 3.537 / 3.703 / 3.069 / 3.601 s | PASS |
| AK | 640 RPM; climb 1.235°; raised 0.125 / 0.289 s; reloads 2.432 / 1.665 / 3.133 / 2.766 s; label 1.069 s | PASS |
| MP7 | 41 / 41 at 950 RPM; climb 4.140°; reloads 3.268 / 4.936 / 2.101 / 3.405 s; forged identical | PASS |
| **Glock (gameplay)** | hold 1 s → 1; 16 / 16 ×2, 0 rejected; end climb 1.538 / 1.542°, dy +19.2 / +19.7 px, ratio 1.342 / 1.322; cap 6 / 6 shots, min gap 133.4 / 133.8 ms; empty 2 shots, slide locked; TR 2.967 / ER 3.403 (release 2.671) / TS 2.436 s; switch cycles; forged reject kinds 0 / 1, fakeHit 1 / 0, rate 3 / 9, rateSustained 10 / 23, ammo ignored | PASS (kick 0.499° then 0.562°: random shake, EXPECTED VARIATION) |
| Sniper (60 fps) | eject 0.701, next shot 1.567, tactical 4.175 s, 6x; forged as its README | PASS |
| Optics | out 0.165–0.167 s at 60 fps; uncapped rerun in 0.142–0.144, out 0.153–0.155 s | ENVIRONMENT/ENGINE ISSUE (throttle), then PASS |
| Movement | 25 / 25; walk 5.600; lag 5.948 / 7.386°; roll 1.399 / 2.699° | PASS |
| FirstPerson | all pass; L+12 uncapped M4 0.73, AK 0.92, MP7 0.57, Glock 0.94, Sniper 0.68 | EXPECTED VARIATION (sample phase) |
| BodyState / Ballistics / Hit reactions / Blood | 42 / 42, 6 / 6, 6 / 6; 10 / 10, 18 / 18; 6 / 6, 6 / 6, 11 / 11; 14 / 14 ×2; world first try | PASS |
| Body interaction | pulse 3.013–3.019 s; drag 9.06 studs; trail 12 (11); "too far" 0.782 s | PASS |
| Death / respawn | respawn 3.268–3.350 s; grenade before death detonates once (4.0022 s) | PASS |
| AI (first) | 14, 8, 11, 10, 7, 5, 6, security 10 / 10, all first try | PASS |
| M4AnimTest | 474 of 475 at 3.528–3.546 s (one 3.587 s) | PASS |
| Truck (60 fps) | 10 / 10 first try; forgedFinish 0.00 studs | PASS |
| Grenade suites (last) | fuse 4.0000–4.0052 s; release 0.149–0.154 s; 41 into bodies; held 7 frames; label 1.403 / 0.197 s; fragmentsHit 0 → 1 pulse on rerun | EXPECTED VARIATION (random directions; fuse +0.1 ms) |
| Performance | server heartbeat 4.59 ms (p95 8.97); 45 weapon Sound objects (Glock 21); Sounds memory 12.10 MB; client frame times throttled (uncapped numbers: `perf()` above) | server PASS; client ENVIRONMENT/ENGINE ISSUE; +14 sounds / +2.0 MB = the intended change |
| Audio suites | Glock: assets, single, taps, string, rapid, pause, ads, stressed, cycle, stance, hearing, reloads (after 1 rerun), interrupt, switching, security, death: all pass, every pattern 0 truncated / 0 recycled / 0 region errors / gains error 0; MP7 / AK / M4: 8 sounds, max 1 shot voice, pass | PASS (see 1) |

**Failures, reruns and classification.**
1. **Glock `reloads()`, Empty Stressed, first run:** the sound ended **101 ms** after the reload (limit 100 ms), start
   offset −93 ms; rerun passed (−27 ms). The same `ReloadEmptyRegular` read −48 / −76 (ER) and −93 / −27 (ES) in this
   one playtest (slice: −10 / −52; the slice's 60 fps run −53 / −55; MP7 ES −76). The reload path is unchanged (no
   equaliser, same file, server-owned timing). **ENVIRONMENT/ENGINE ISSUE** (Roblox audio start latency, ±35 ms per
   play) — the largest offset recorded so far; flagged for review.
2. Optics out at 60 fps: ENVIRONMENT/ENGINE ISSUE, uncapped PASS. 3. GrenadeFidelity fragmentsHit, FirstPerson L+12,
   Glock kick: EXPECTED VARIATION. 4. Grenade `multi` ran with 2 grenades after the tester's own server-command error;
   rerun with 3 passed: TEST HARNESS DEFECT (tester error).

**Console:** 0 game-code errors. Expected rejection lines: Weapon 123 (= the base set), Grenade 36 (+2 from the
tester's rerun), Vehicle 44, Interact 26. 2 tester errors (the agent's own commands). Studio noise only; **0 FMOD
lines** (the slice run's single FMOD NOTREADY did not recur).

## Results — Glock audio fidelity slice (Studio playtests, 2026-11-09, before the correction)

| Test | Result | Pass |
|---|---|---|
| assets | 7 sounds in `SoundService.WeaponAudio_Glock`, loaded from `rbxasset://sounds/GlockReference/`: shot sprites 32.0 s with regions; reloads 2.967 / 3.4 / 2.433 s; not looped; volume 0.1. The other weapon-audio folders: M4, AK, MP7 (weapons with audio configs) | yes |
| fire single | 1 shot → variant 1 (first shot of the session); Play 0 ms after the shot; the voice ends 1.0 s after it (the 1.0 s region); server 1 | yes |
| fire taps (4 presses 0.25 s apart) | variants 2, 3, 4, 5 (the cycle continues: no restart after a pause); spacing 259 ± 2 ms; server 4 | yes |
| fire string (16 presses 0.165 s apart, 15 + 1) | 16 / 16, variants 6 … 21, voices A / B in turn, ≤ 1 shot voice, 607 region samples with 0 outside, spacing 170–176 ms, Play delay 0 ms, tail 1.057 s, server 16 | yes |
| fire rapid (presses every 0.08 s, held 0.07 s) | 8 shots at **0.136–0.144 s** (the 450 RPM cap + one frame), variants 1 … 8, 0 outside, server 8 | yes (after the test fix below) |
| fire pause (3 presses 1.2 s apart) | variants 9, 10, 11 (continuing across 1.2 s gaps), tail 1.044 s, server 3 | yes (after the test fix below) |
| fire ads (aimed string) | 16 / 16, variants 31, 32, **1**, 2 … 14 (the wrap), 0 outside, tail 1.068 s | yes |
| fire stressed | 16 / 16 on ShotStressedA / B, variants 15 … 30, 0 outside, tail 1.064 s | yes |
| reloads | each starts its own sound once (the Stressed empty reload: `ReloadEmptyRegular`, its clip's sound); sound − clip mean / SD: TR −9 / 8, ER −10 / 7, TS −11 / 7, ES −52 / 9 ms (engine start latency, below); the sound ends with the reload (+22 … +70 ms); **reload → fire**: the next press plays a shot sound every time | yes |
| interrupt | switch during a reload: stopped after 7 ms; during a shot tail: 7 ms. Presses during a reload: refused, 0 shot sounds, reload continues. Reload cancelled by a correction: 1 ms | yes |
| death (during a reload + shot tail) | both playing; stopped 7 ms after `Died`; after respawn the first shot is variant 1; one Glock folder | yes |
| switching | Glock → M4 → AK → MP7 → Sniper → Glock, firing each: the Glock voice only while the Glock fires; 0 Glock sounds on the others; 0 sounds of a third weapon; 0 non-weapon sounds. Sniper → Glock ×3: variants 1, 2 every time, one folder. `MP7AudioTest` / `AKAudioTest` / `M4AudioTest` `switching()` pass in the same playtest | yes (after the test fix below) |
| perf | `WeaponAudio:Shot` 9.07 µs, reload start + stop 8.16 µs. Frame time (mean / p95) idle 5.018 / 5.736 ms, Glock rapid presses 4.978 / 5.558, Glock empty reload 5.027 / 6.235; M4 / AK / MP7 sustained fire 5.430 / 5.421 / 5.277 ms. 31 weapon Sound objects (8 + 8 + 8 + 7). Sounds memory tag 10.21 → 10.49 MB | yes |

**Test defects found and fixed (not implementation failures; no check was loosened).**
1. **`fire("pause")`** waited 1.2 s after its last press before the tail measurement began, so it measured the wait
   (1.208 s against the 1.2 s limit). The last wait was removed; rerun 1.044 s.
2. **`fire("rapid")`** pressed for one frame every 0.08 s; a press released inside the fire cycle is dropped by design
   (FireController Semi), so the shots came every 0.17 s and never at the cap. The presses are now held 0.07 s (a held
   press fires at the end of the cycle, as `GlockTest.press` does); rerun 0.136–0.144 s.
3. **`switching()`'s re-equip loop** started with the Glock already equipped, so its first "re-equip" was no put-down
   and the cycle rightly continued (2, 3). The loop now switches to the Sniper first; rerun 1, 2 three times.
`Client.WeaponAudio` and `Config.Audio.Glock` were not changed.

**Console:** 0 errors and 0 warnings from game code; only the normal `[Weapon]` lines and the security tests' expected
rejections ("firing faster than the weapon allows" ×17, "Glock is not equipped" ×3, "bad argument types" ×2, "unknown
weapon" ×2, "non-finite or zero vector" ×1, "shooter is not alive" ×10).

## Security (malicious client, debug-hook audio log on)

| Attempt | Server | Glock audio |
|---|---|---|
| 20 `WeaponFire("Glock", …)` in one frame, no press | 3 accepted / 17 rejected | **0 shot sounds**, nothing playing |
| 3 forged Glock shots with the AK equipped | rejected ("Glock is not equipped") | **0 shot sounds of any weapon** |
| forged `WeaponCommand("Reload")` with a full magazine; malformed `WeaponFire` (missing / wrong types / NaN / tables), forged `ReloadDone` | ignored / rejected | **0 reload, 0 shot sounds** |
| 20 Glock ↔ M4 switches in 0.6 s with presses | — | 0 sounds, nothing left playing after switching away, one Glock folder |
| presses + forged shots for 1 s while dead | rejected ("shooter is not alive" ×10) | **0 shot sounds**, nothing playing |

Audio is client presentation after the client's own fire / reload decisions; `Config.Audio.Glock` is a data module; no
remote was added and no server code changed. The GlockTest forged set is in the full regression below.

## Engine start latency (section 24 of the brief)

A direct probe (`Sound:Play()`, 5 plays each, `TimePosition` − elapsed): Glock reload −38 … −58 ms (mean −48), Glock
shot voice with its region −27 … −76 (−44); M4 −42 / −27, AK −39 / −21, MP7 −46 / −55 ms; the position first advances
8–11 ms after `Play()` everywhere. **Shared engine behaviour, the same for every weapon, varying ±25 ms per play: not
compensated** (not deterministic, not Glock-specific).

## Full regression — slice (one fresh playtest, AI first, Grenade suites last, background agent, 2026-11-09)

Baseline: `Roblox/Tests/Weapons/MP7/MP7AudioTest/README.md`, "Full regression". After the run the agent hashed
WeaponController, FireController, Recoil, ReloadController, WeaponAudio, `Config.Weapons.Glock` and WeaponServer:
byte-identical to `2026-11-09_before_glock_audio_fidelity`.

**Environment of this run:** Studio drew the play window at **60 fps for the whole session** (the baselines ran at
≈ 220 fps), so every timing reading is quantised to 16.7 ms and test loops ran slower; and for ≈ 40 s someone used the
play window (Glock hits on bots, an AK reload, a pulse check and a drag that no test command makes), which spoiled one
Glock switching reading (rerun clean).

| Area | Result | vs baseline |
|---|---|---|
| M4 (Firing / Reload / HUD) | 770 RPM; recovery 0.744 / 0.741 s; reloads 3.530 / 3.064 / 3.700 / 3.598 s; HUD 13 / 0; labels 1.708 / 1.746 / 1.611 s | within spread (labels +7–11 ms, under a frame) |
| M4ModelFidelityTest | all pass; 10,466 tris; reloads 3.541 / 3.706 / 3.070 / 3.615 s | within spread |
| AK | 640 RPM; raised 0.118 / 0.283 s; hip climb 1.212° (rerun 1.224°) | within spread (slightly low at 60 fps) |
| MP7 | 41 / 41 ×3; climb 4.05–4.17°; reloads 3.273 / 4.950 / 2.116 / 3.415 s; forged set identical | within spread |
| **Glock (gameplay)** | rules held: hold 1 s → 1 shot, 16 / 16 accepted, no shot under the 133.3 ms cap, 0 rejections, forged kinds as before. **At 60 fps:** cap test 7 shots (reruns 6, 7; min gap 133.4 ms), rateSustained 11 / 22, end climb 1.37 / 1.33°, dots dy ≈ +21 px / ratio 1.35–1.37, reloads 2.984 / 3.405 (slide 2.672) / 2.445 s | **DIFFERENT readings, investigated below: environment (60 fps) + known run-to-run variance; not a regression** |
| Sniper | eject 0.705, next shot 1.567, tactical 4.167 s, 6x; forged as its README | same |
| Optics | in 0.141 / 0.143, out 0.150 / 0.161 s; magnification 4.500; tracking 0.894 / 1.110° | within spread |
| Movement | 25 / 25; walk 5.600; lag 5.948 / 7.385°; roll 1.399 / 2.699° | same |
| FirstPerson | all pass; L+12: M4 0.77, AK 0.92, MP7 0.57, Glock 0.90, Sniper 0.68 | within spread |
| BodyState / Ballistics / Hit reactions / Blood | 42 / 42, 6 / 6, 6 / 6; 10 / 10, 18 / 18; 6 / 6, 6 / 6, 11 / 11; 14 / 14, 14 / 14; blood world 0/0/12 once, then 1/1/3 | same after 1 rerun (failure 1) |
| Body interaction | pulse 3.016–3.020 s; drag 9.06 studs; trail 12 (11); "too far" 0.788 s | within spread |
| Death / respawn | respawn 3.270–3.335 s; a grenade before death detonates once (4.0028 s) | within spread |
| AI | 14 / 14, 8 / 8, 11 / 11, 10 / 10, 7 / 7, 5 / 5, 6 / 6, security 10 / 10, all first try | same |
| M4AnimTest | 434 of 436 at 3.528–3.547 s (one 3.784 s during the AI suites) | same pattern |
| Truck | 10 / 10 first try; `forgedFinish` 0.00 studs | same |
| Grenade suites (last) | fuse ≤ 4.0051 s; release 0.148–0.162 s; 40 fragments into bodies; held 8 frames; label 1.395 / 0.195 s; fragmentsHit 0 then 1 pulse on rerun | within spread (random fragment directions) |
| Performance | client frame time not comparable (capped at 16.7 ms); server heartbeat 4.19–4.43 ms; Sounds memory +1.05 MB (the Glock's 7 sounds) | server same |
| Audio suites (same playtest) | Glock: assets, single (1), string (2 … 17), rapid (18 … 25), stressed (26 … 32, 1 … 9), 0 region errors, tails 1.04–1.07 s, reloads (sound − clip −41 … −55 ms), interrupt, switching: all pass. MP7 / AK / M4 assets, fire sustained, switching: all pass | pass |

**Failures, reruns and classification.**
1. **Blood world 0/0/12 → 1/1/3 on rerun:** the server rejected lane B's shot ("direction behind the shooter"): the test
   teleports the player client-side and the server copy had not caught up. Timing (known class of flake).
2. **Glock switching spoiled by the outside input → clean on rerun** (one viewmodel per equip, instance count unchanged).
   Environment.
3. **GrenadeFidelity fragmentsHit 0 → 1 pulse on rerun:** random fragment directions. Known variance.
4. **Glock DIFFERENT readings — checked again in a fresh playtest at the normal frame rate (4.9 ms frames), against this
   morning's pre-change baseline:**

   | Reading | 60 fps regression | Uncapped, after the change | Pre-change baseline (same day) | Accepted README |
   |---|---|---|---|---|
   | 16 presses: dy / ratio | ≈ 21 px / 1.35–1.37 | 19.07 / 1.349, 19.36 / 1.326 | 20.14 / 1.325 | 17.1 / 1.324 |
   | 16 presses: kick / end / 22 frames later | — / 1.37, 1.33 / — | 0.575 / 1.517 / 0.206°, 0.549 / 1.528 / 0.212° | 0.523 / 1.559 / 0.24° | 0.588 / 1.533 / 0.218° |
   | cap (10 presses 0.08 s apart) | 7 (reruns 6, 7) | 5 and 6 shots, min gap 134.8 ms, 0 rejected | 6, 136.9 ms | 6, 133.8 ms |
   | rateSustained | 11 / 22 | 10 / 23, 10 / 23 | 10 / 23 | 10 / 23 |

   **Classification:** environment (the 60 fps cap: slower loops let one more shot in, the presses spread out, the
   30-fps resampling picks other frames) plus known run-to-run variance (the ratio moves 1.326–1.349 between two
   identical runs; dy was already 20.1 px this morning before any change). Not a regression: no gameplay code changed,
   and uncapped readings equal the pre-change baseline.

**Console (regression).**
- 0 game-code errors, 0 stack traces. Expected rejection lines: Weapon 145, Grenade 53, Vehicle 44, Interact 26 (the
  extra Weapon / Grenade lines are the reruns and the lane-B flake).
- **One new engine error:** `[FLog::FMOD] FMOD API error, FMOD_RESULT:46 (FMOD_ERR_NOTREADY), System::playSound` at
  18:39:37Z, during FirstPerson `transitions`, after the MP7's refill and 1 s before an MP7 tactical reload, with a
  grenade throw in progress. It is the only FMOD line in the day's Studio log (which covers the M4 / AK / MP7 audio
  regressions too); a rerun of `transitions` did not reproduce it; the test passed both times; the log does not name the
  sound and no Glock sound was playing. **Classification: Roblox audio-engine internal, single, not reproduced, not
  attributable** — reported, not explained away.
- Studio noise otherwise. 0 tester errors (one call ran 53.9 s, over the 50 s guideline, without effect).

**Not run** (as in the baselines): the FirstPerson latency rows, the Truck prompt µs cost, the Sniper `dead` forge, the
M4 forged-request set, a two-player test; client frame times uncapped in this run (measured separately above).
