# AK audio test (AK audio fidelity slice)

- **`AKAudioTest.Run.client-module.luau`** is a copy of `StarterPlayer.StarterPlayerScripts.AKAudioTest.Run`
  (also `Roblox/Scripts/src/StarterPlayer/StarterPlayerScripts/AKAudioTest/Run.luau`). It is Studio-only.
- **What it is:** derived from `M4AudioTest`, with the same checks but the AK's own sounds, cadence (640 RPM), variant
  length (1.0 s) and reload lengths. It uses WeaponController's debug hook (`"audio"` command). Delete the folder to
  remove it.
- **Before playtesting**, the sounds must be in Studio's content folder. Run
  `Roblox/Assets/Audio/AK/sync_to_studio.ps1`, and run it again after every Studio update.
- Analysis and offline comparison: `ReferenceAnalysis/Weapons/AK/AK_Audio_Analysis.md`.

```lua
-- Client datamodel, in a playtest
local Run = require(game.Players.LocalPlayer.PlayerScripts.AKAudioTest.Run)
Run.assets()  Run.fire("single")  Run.fire("taps")  Run.fire("sustained")  Run.fire("ads") -- "ads" = the raised posture
Run.fire("stressed")  Run.fire("repress")  Run.reloads()  Run.interrupt()  Run.switching()  Run.perf()
Run.death("before")  -- then on the Server: game.Players:GetPlayers()[1].Character.Humanoid.Health = 0
Run.death("after")   -- once respawned
Run.timeline("sustained")  -- raw play log (ReferenceAnalysis/Weapons/AK/Audio/data/ingame_timeline.json)
```

## Results (Studio playtest, 2026-11-09)

| Test | Result | Pass |
|---|---|---|
| assets | 8 sounds in `SoundService.WeaponAudio_AK`, all loaded from `rbxasset://sounds/AKReference/`. Shot sprites 31.0 s with regions; reloads 2.433 / 3.133 / 1.667 / 2.767 s; not looped; volume 0.1. Weapons without an audio config (MP7, Glock, Sniper, ScopeTest): 0 sounds. The only other weapon-audio folder is the M4's | yes |
| fire single | 1 → position 1; play 0 ms after the scheduled shot; tail ends 1.014 s after it; server accepted 1 | yes |
| fire taps (4 × one frame, 0.25 s apart) | 4 → positions 1, 1, 1, 1; server accepted 4 | yes |
| fire sustained | 31 → positions 1 … 31 (ShotRegularA / B in turn). ≤ 1 shot voice. Play delay 0–6 ms (mean 3). Spacing 94 ± 2 ms (scheduled 93.75). Tail 1.027 s. Server accepted 31. 673 region samples, 0 outside | yes |
| fire ads (raised posture) | 31 / 31, positions 1 … 31, tail 1.015 s, 671 region samples, 0 outside | yes |
| fire stressed | 31 / 31 on ShotStressedA / B, positions 1 … 31, tail 1.045 s, 666 region samples, 0 outside | yes |
| fire repress | 12 shots → positions 1 … 8 (through the one-frame release), then 1 … 4 after the 0.36 s break; server accepted 12 | yes |
| reloads | each of the four starts its own sound once. Sound − clip time mean / SD: TR +3 / 7, ER −20 / 7, TS +3 / 7, ES −15 / 8 ms. Sound ends vs reload end: +5 / +27 / +6 / +11 ms | yes |
| interrupt | switch during a reload: stopped after 7 ms; during a shot tail: 7 ms. Firing during a reload: refused, 0 shot sounds, reload continues. Reload cancelled by a correction: stopped after 1 ms | yes (after the test fix below) |
| death (during a reload + shot tail) | both playing; stopped 5 ms after `Died`; after respawn the first shot is position 1; one AK folder | yes |
| death with the trigger held (inline, same playtest) | a shot voice playing; stopped 9 ms after `Died`; after respawn position 1; one folder | yes |
| switching | AK → M4 → MP7 → Glock → Sniper → AK, firing each: the AK shot voice only while the AK fires; 0 AK sounds on the others; 0 sounds of a third weapon; 0 non-weapon sounds | yes |
| perf | `WeaponAudio:Shot` 8.3 µs per call; reload start + stop 7.2 µs. Sustained-fire frame time AK 4.880 ms mean / 5.393 p95 vs MP7 (no audio) 5.089 / 5.562. 16 Sound objects in SoundService (M4 8 + AK 8). Sounds memory tag 7.43 MB, unchanged by the probe instance | yes |

**Test defect found and fixed (not an implementation failure).**
- **Cause:** the first run of `interrupt` failed. The test was derived from the M4 test, and its "switch away" lines
  still set `EquippedWeapon` to `"AK"`, so the AK was never put down and its sound rightly kept playing.
- **Fix:** both lines now switch to the MP7.
- **Rerun:** a patched runtime copy in the same playtest passed (stopped after 7 / 7 / 1 ms).
- `Client.WeaponAudio` and `Config.Audio.AK` were not changed.

**Console:** 0 errors and 0 warnings from game code; only the normal `[Weapon]`, `[AI]`, `[Vehicle]` and
`[M4AnimTest]` lines.

**Security.**
- Audio is client presentation, called after the client's own fire / reload decisions. `Config.Audio.AK` is a data
  module. No code changed in `WeaponAudio`, `WeaponController`, `ReloadController` or any server script.
- No remote was added; the remotes are the same 14 RemoteEvents.
- The server's accepted counts equal the shots fired in every firing test.

## Full regression (one fresh playtest, Grenade suites last, background agent, 2026-11-09)

The baseline is `Roblox/Tests/Weapons/M4/M4AudioTest/README.md`, "Full regression (correction pass)".

| Area | Result | vs baseline |
|---|---|---|
| M4 (Firing / Reload / HUD) | 770 RPM, 0 rejected; recovery 0.739 / 0.740 s; de-cant −32.597° → 0.179°; ADS in 0.333 / 0.334, out 0.118 / 0.120 s; reloads 3.531 / 3.063 / 3.697 / 3.599 s; HUD 13 / 0, labels 1.701 / 1.737 / 1.602 s; extras pass | same |
| M4ModelFidelityTest | all pass; 10 parts, 10,466 tris; reloads 3.534 / 3.702 / 3.070 / 3.604 s | same |
| **AK** | 640 RPM; climb 1.232 / 1.943°; raised 0.126 / 0.288 s, FOV 70; reloads 2.429 / 1.664 / 3.134 / 2.763 s; label at 1.068 s; sequence, repeat, refusals, switch, repeated pass, client = server | within spread: no AK gameplay value changed |
| MP7 | 41 / 41 ×3; climb 4.126–4.136°; ADS 0.250 / 0.149 s; reloads 3.267 / 4.935 / 2.101 / 3.400 s; forged as its README | within spread |
| Glock | 16 / 16; reload 3.404 s (swap 2.170, slide 2.667); forged as its README | same |
| Sniper | eject 0.701, next shot 1.567 s, tactical 4.168 s, zoom back to 6x; forged as its README | same |
| Optics | in 0.144 / 0.143, out 0.150 / 0.154 s; magnification 4.500; tracking 0.894 / 1.110°; 0 remotes scoped | within spread |
| Movement | 25 / 25; walk 5.600; crouch 2.800 / 2.70; jump +7.532; lag 5.948 / 7.386°; roll 1.399 / 2.699° | same |
| FirstPerson | all pass; L+12: M4 0.77 then 0.73, AK 0.92, MP7 0.57, Glock 0.93, Sniper 0.68 | same |
| BodyState / Ballistics / Hit reactions / Blood | 42 / 42, 6 / 6, 6 / 6; 10 / 10 per lane, 18 / 18; hit reactions M4 5 / 6 then 6 / 6 on the rerun, AK 6 / 6, 11 / 11; blood 14 / 14, 14 / 14 | same after rerun (flake below) |
| Body interaction | pulse 3.015–3.019 s; drag 9.08 studs; trail 11 (10 placed); "too far" 0.722 s | within spread |
| Death / respawn | pulse interrupted; AK reload cancelled after the swap; respawn 3.256–3.351 s; a grenade before death detonates once (4.0003 s) | within spread |
| AI | 14 / 14, 8 / 8, 11 / 11, 10 / 10; player as target 7 / 7; 5 / 5, 6 / 6; security 9 / 10 twice in the long playtest, **10 / 10 in a fresh playtest** | same (known test defect, below) |
| M4AnimTest | 369 of 370 at 3.528–3.548 s (start hitch 5.185 s) | same pattern |
| Truck | 10 / 10; `forgedFinish` 0.00 studs; 11 forged refused | within spread |
| Grenade suites | fuse 4.0000–4.0047 s ×16; release 0.150–0.154 s; 32 into bodies; held 8 frames at release; label 1.404 / 0.194 s; red edge identical | within spread |
| Performance | M4 4.91 / 4.88 ms, AK 4.84 / 4.93 ms; server heartbeat 4.95 ms | within spread. All about +0.2–0.3 ms, the server heartbeat too (no audio there): session load (Studio 2.55 GB vs 2.24 GB). The AK with audio costs no more than the M4 |
| AKAudioTest + M4AudioTest (same playtest) | AK assets, fire sustained / stressed / repress, reloads, interrupt, switching; M4 assets, fire sustained, switching: all pass | pass |

**Failures, investigated.**
1. **Hit reactions M4 5 / 6, then 6 / 6:** a timing flake.
   - On the first run the server rejected the 3-round burst at REACT4 ("origin 10 studs from head" ×3).
   - The test had teleported the player on the client, and the server's copy had not caught up.
   - This is server validation of an M4 shot; audio cannot affect it.
2. **AI security 9 / 10 (check S4):** a known test defect (FirstPerson README). S4 counts rejection lines in Studio's
   512-line log, which was full late in the long playtest. The agent's full server log showed the forged shot rejected
   both times. **A fresh playtest gave 10 / 10.**

**Console (regression).**
- 0 game-code errors. The one error and stack trace came from a read-back command of the agent, which it redid.
- Expected forged-request lines: Weapon rejected 132, Grenade 34, Vehicle 44, Interact 28.
- Studio-internal noise.

The fresh AI security playtest's only error was my own first call (`securityBefore` before its bot existed).

**Not run** (as in the baselines): the FirstPerson latency rows, the Truck prompt µs cost, the Sniper `dead` forge, the
M4 forged-request set, a two-player test.
