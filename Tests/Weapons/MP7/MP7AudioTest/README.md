# MP7 audio test (MP7 audio fidelity slice)

- **`MP7AudioTest.Run.client-module.luau`** is a copy of `StarterPlayer.StarterPlayerScripts.MP7AudioTest.Run`
  (also `Roblox/Scripts/src/StarterPlayer/StarterPlayerScripts/MP7AudioTest/Run.luau`). It is Studio-only.
- **What it is:** derived from `AKAudioTest` / `M4AudioTest`, with the same checks but the MP7's own sounds, cadence
  (950 RPM), variant length (1.25 s), magazine (40 + 1) and reload lengths. It uses WeaponController's debug hook
  (`"audio"` command). Delete the folder to remove it.
- **Before playtesting**, the sounds must be in Studio's content folder. Run
  `Roblox/Assets/Audio/MP7/sync_to_studio.ps1`, and run it again after every Studio update.
- Analysis and offline comparison: `ReferenceAnalysis/Weapons/MP7/MP7_Audio_Analysis.md`.

```lua
-- Client datamodel, in a playtest
local Run = require(game.Players.LocalPlayer.PlayerScripts.MP7AudioTest.Run)
Run.assets()  Run.fire("single")  Run.fire("taps")  Run.fire("sustained")  Run.fire("ads") -- "ads" = the aim posture
Run.fire("stressed")  Run.fire("repress")  Run.reloads()  Run.interrupt()  Run.switching()  Run.perf()
Run.death("before")  -- then on the Server: game.Players:GetPlayers()[1].Character.Humanoid.Health = 0
Run.death("after")   -- once respawned
Run.timeline("sustained")  -- raw play log (ReferenceAnalysis/Weapons/MP7/Audio/data/ingame_timeline.json)
```

**Differences from the AK test** (all from the MP7's own data, none loosened to pass): expected lengths (shot sprites
51.25 s, reloads 3.2667 / 2.1 / 4.9333 / 3.4 s); variant 1.25 s; interval 60 / 950 s; positions capped at 41; a full
magazine is ≥ 40 shots; the tail limit is 1.5 s (the MP7 tail is clean for 1.2 s against the AK's 0.95 s, plus one
period, plus Roblox's 21.3 ms `TimePosition` steps); switching starts and ends on the MP7; "switch away" goes to the
Glock; perf compares the MP7 with the AK (both with audio: every automatic weapon now has audio).

## Results (Studio playtest, 2026-11-09)

| Test | Result | Pass |
|---|---|---|
| assets | 8 sounds in `SoundService.WeaponAudio_MP7`, all loaded from `rbxasset://sounds/MP7Reference/`. Shot sprites 51.25 s with regions; reloads 3.267 / 4.933 / 2.1 / 3.4 s; not looped; volume 0.1. The other weapon-audio folders are the M4's and the AK's | yes |
| fire single | 1 → position 1; play 0 ms after the scheduled shot; tail ends 1.249 s after it; server accepted 1 | yes |
| fire taps (4 × one frame, 0.25 s apart) | 4 → positions 1, 1, 1, 1; spacing 258 ± 2 ms; server accepted 4 | yes |
| fire sustained | 41 → positions 1 … 41 (ShotRegularA / B in turn). ≤ 1 shot voice. Play delay 0–6 ms (mean 3). Spacing 63 ± 2 ms (scheduled 63.16). Tail 1.327 s. Server accepted 41. 651 region samples, 0 outside | yes |
| fire ads (aim posture) | 41 / 41, positions 1 … 41, tail 1.318 s, 650 region samples, 0 outside | yes |
| fire stressed | 41 / 41 on ShotStressedA / B, positions 1 … 41, tail 1.326 s, 648 region samples, 0 outside | yes |
| fire repress | 17 shots → positions 1 … 12 (through the one-frame release), then 1 … 5 after the break; server accepted 17 | yes |
| reloads | each of the four starts its own sound once, 0 other sounds. Sound − clip time mean / SD: TR +1 / 8, ER −10 / 7, TS −11 / 7, ES −14 / 7 ms. Sound ends vs reload end: +10 / +10 / +16 / +28 ms | yes |
| interrupt | switch during a reload: stopped after 7 ms; during a shot tail: 7 ms. Firing during a reload: refused, 0 shot sounds, reload continues. Reload cancelled by a correction: stopped after 0 ms | yes |
| death (during a reload + shot tail) | both playing; stopped 5 ms after `Died`; after respawn the first shot is position 1; one MP7 folder | yes |
| death with the trigger held | a shot voice playing; stopped 5 ms after `Died`; after respawn position 1; one folder | yes |
| switching | MP7 → M4 → AK → Glock → Sniper → MP7, firing each: the MP7 shot voice only while the MP7 fires; 0 MP7 sounds on the others; 0 sounds of a third weapon; 0 non-weapon sounds. `AKAudioTest.switching()` and `M4AudioTest.switching()` pass in the same playtest | yes |
| perf | `WeaponAudio:Shot` 8.74 µs per call; reload start + stop 7.71 µs. Sustained-fire frame time MP7 5.093 ms mean / 5.525 p95 vs AK 4.923 / 5.412 (the AK pass measured the MP7 without audio at 5.089 / 5.562). Idle 4.731 / 5.268, empty reload 4.821 / 5.291. 24 Sound objects in SoundService (M4 8 + AK 8 + MP7 8). Sounds memory tag 9.01 MB, unchanged by the probe instance | yes |

**Defect found and fixed during the slice (an implementation fix, not a test change).**
- **Cause:** the first in-game run had `regionBad` 87 in sustained / ads. With a 1.3 s variant length, 8 of the 41
  regions came out up to 3 µs off their variant, because `PlaybackRegion` is a single-precision `NumberRange`
  (verified on the client: `NumberRange.new(10.4, 11.7).Min` ≠ 10.4).
- **Fix:** the variant length became 1.25 s, which is exact in binary. The sprites were rebuilt (same content, shorter
  silent padding after each 1.2 s variant), re-synced, and `Config.Audio.MP7` / this test's `VARIANT` / `EXPECTED`
  updated. The check itself was not changed.
- **Rerun:** 0 outside in every firing test.

**Console:** 0 errors and 0 warnings from game code; only the normal `[Weapon]` lines and the security test's expected
rejections ("firing faster than the weapon allows" ×17, "MP7 is not equipped" ×3).

**Security.**
- Audio is client presentation, called after the client's own fire / reload decisions. `Config.Audio.MP7` is a data
  module. No code changed in `WeaponAudio`, `WeaponController`, `ReloadController` or any server script; no remote was
  added.
- **Forged requests (client datamodel, debug hook logging on):**
  - 20 `WeaponFire("MP7", …)` in one frame, trigger not held: server accepted 3, rejected 17; **0 MP7 shot sounds**.
  - 3 forged MP7 shots with the AK equipped: rejected ("MP7 is not equipped" ×3); **0 shot sounds of any weapon**.
  - A forged `WeaponCommand("Reload")` with a full magazine: **0 reload sounds**.
  - The MP7 suite's own forged set (`Tests/MP7/README.md`) is in the full regression below.
- The server's accepted counts equal the shots fired in every firing test.

**Stale label, not changed:** `AKAudioTest.perf()` still names its MP7 figure `mp7NoAudioSustainedFireFrameMs`. Since this
slice the MP7 has audio, so that figure now includes it. The AK audio test was left as accepted (the brief: do not
reopen AK audio); the label is only a name.

## Full regression (one fresh playtest, AI first, Grenade suites last, background agent, 2026-11-09)

The baseline is `Roblox/Tests/Weapons/AK/AKAudioTest/README.md`, "Full regression". Every suite passed first time; no
rerun was needed (the known flakes did not appear).

| Area | Result | vs baseline |
|---|---|---|
| M4 (Firing / Reload / HUD) | 770 RPM, 0 new rejections; recovery ADS 0.771 (rerun 0.774), hip 0.771 then 0.741 s; de-cant −32.597° → 0.210°; ADS in 0.332 / 0.330, out 0.122 / 0.118 s; reloads 3.529 / 3.063 / 3.696 / 3.596 s; HUD 13 / 0, labels 1.701 / 1.735 / 1.601 s; extras pass | within spread: the recovery metric flips between ≈ 0.74 and ≈ 0.77 run to run (earlier runs 0.739–0.776); the M4 is untouched |
| M4ModelFidelityTest | all pass; 10 parts, 10,466 tris; reloads 3.536 / 3.705 / 3.071 / 3.604 s | same |
| AK | 640 RPM; climb 1.229 / 1.945°; raised 0.126 / 0.288 s, FOV 70; reloads 2.433 / 1.662 / 3.131 / 2.765 s; label 1.067 s; all sub-tests pass | within spread |
| **MP7** | 41 / 41 ×3 at 950 RPM, 0 rejected; climb 4.125–4.131°; ADS 0.251 / 0.149 s, FOV 70; reloads 3.271 / 4.935 / 2.104 / 3.405 s; label "[TAB] 4.6 MAG" at 1.836 / 1.235 s, "+1" at 1.169 s; ammo client = server; forged: 8 kinds 0 / 1, fakeHit 1 / 0 with 0 damage, rate 3 / 9, sustained 19 / 14, ammo ignored | within spread (reloads +3–5 ms, under a frame): no MP7 gameplay value changed |
| Glock | 16 / 16; reload 3.401 s (swap 2.171, slide 2.671); forged as its README | same |
| Sniper | eject 0.702, next shot 1.567 s, tactical 4.171 s, zoom back to 6x; forged as its README | same |
| Optics | in 0.144 / 0.141, out 0.150 / 0.153 s; magnification 4.499; tracking 0.894 / 1.110°; 0 remotes scoped | within spread |
| Movement | 25 / 25; walk 5.600; crouch 2.800 / 2.70; jump +7.532; lag 5.948 / 7.386°; roll 1.399 / 2.699° | same |
| FirstPerson | all pass; L+12: M4 0.77, AK 0.92, MP7 0.57, Glock 0.93, Sniper 0.68 | same |
| BodyState / Ballistics / Hit reactions / Blood | 42 / 42, 6 / 6, 6 / 6; 10 / 10 per lane, 18 / 18; 6 / 6, 6 / 6, 11 / 11; 14 / 14, 14 / 14 | same, no rerun |
| Body interaction | pulse 3.012–3.021 s; drag 9.08 studs; trail 12 (11 placed); "too far" 0.788 s | within spread |
| Death / respawn | pulse interrupted; AK reload cancelled after the swap; respawn 3.271–3.380 s; a grenade before death detonates once (4.0046 s) | within spread |
| AI | 14 / 14, 8 / 8, 11 / 11, 10 / 10, player as target 7 / 7, 5 / 5, 6 / 6, security 10 / 10 (run first, before the 512-line log filled) | same |
| M4AnimTest | 376 of 377 at 3.528–3.543 s (start hitch 5.494 s) | same pattern |
| Truck | 10 / 10; `forgedFinish` 0.00 studs; 11 forged refused | within spread |
| Grenade suites (last) | fuse 4.0005–4.0046 s ×12; release 0.150–0.153 s; 33 into bodies; held 6 frames at release; label 1.403 / 0.195 s; red edge matches | within spread |
| Performance | hip / ADS frame time M4 4.55 / 4.70, AK 4.70 / 4.63, MP7 4.72 / 4.65 ms; server heartbeat 4.53 ms. MP7 sustained fire 5.10–5.24 ms | within spread (MP7 sustained fire was +0.21 ms over the M4 / AK before audio, from its 950 RPM effects; no audio-off run was made in this session) |
| MP7AudioTest + AKAudioTest + M4AudioTest (same playtest) | MP7 assets, fire sustained / stressed / repress, reloads, interrupt, switching; AK assets, fire sustained, switching; M4 assets, fire sustained, switching: all pass | pass |

**Console (regression).**
- 0 game-code errors; no warning or error mentions sound or audio. None of the agent's own commands errored.
- Expected forged-request lines: Weapon rejected 125, Grenade 34, Vehicle 44, Interact 31 (Weapon and Interact differ
  from the AK run's 132 / 28 by each run's own reruns and probes).
- Studio-internal noise only (Wrap-deformer, undefined flags, settingsUrl, HTTP 403 / 400, plugin "Hello World",
  play-start HTTP / secrets errors).

**Not run** (as in the baselines): the FirstPerson latency rows, the Truck prompt µs cost, the Sniper `dead` forge, the
M4 forged-request set, a two-player test, and MP7 suite tests 11–21 (movement, ballistics, body state, death, respawn;
not in the baseline row).

### Reload-sound start latency (found by the regression, investigated)

- **Seen:** in the long regression playtest `MP7.reloads()` passed, but the sound − clip offsets were TR −39, ER −39,
  TS +2, ES **−76** ms (the Empty Stressed sound ended 75 ms after its reload; the check allows 100 ms). In this
  slice's own run they were +1 / −10 / −11 / −14 ms.
- **Fresh playtest, same day:** MP7 −18 / −11 / −6 / −14 ms (sound ends +28 / +22 / +11 / +16 ms); AK, same playtest,
  +3 / −17 / −9 / +2 ms (ends +0 / +27 / +11 / +6 ms). The two weapons are in the same range.
- **Direct probe** (`Sound:Play()` from position 0 on the reload sounds, 7 trials each, `TimePosition` − elapsed):
  MP7 Empty Stressed −40 … −76 ms (mean −55), MP7 Tactical Regular −34 … −85 (mean −49), AK Empty Stressed −34 … −64
  (mean −51), AK Tactical Regular −51 … −81 (mean −59). `TimePosition` first advances 8–9 ms after `Play()` every time.
- **Classification:** Roblox audio-engine start / reporting latency, the same for the MP7 and the AK, with a spread of
  about ±25 ms between plays; not MP7 content, config or timing. The worst reading (76 ms of sound lagging the
  animation) is under the commonly cited detectability threshold for audio lagging picture (≈ 125 ms, ITU-R BT.1359).
- **Not changed:** compensating it would need a shared `Client.WeaponAudio` change (it would alter M4 and AK audio,
  which this brief does not reopen) and a latency that is not constant. Recorded as a remaining mismatch.
