# M4 audio test (M4 audio fidelity slice + correction pass)

- **`M4AudioTest.Run.client-module.luau`** is a copy of `StarterPlayer.StarterPlayerScripts.M4AudioTest.Run`
  (also `Roblox/Scripts/src/StarterPlayer/StarterPlayerScripts/M4AudioTest/Run.luau`). It is Studio-only: it uses
  WeaponController's debug hook (`"audio"` command: play / stop log, with each shot's burst position, and every weapon's
  sound state). Delete the folder to remove it.
- **Before playtesting**, the sounds must be in Studio's content folder. Run
  `Roblox/Assets/Audio/M4/sync_to_studio.ps1`, and run it again after every Studio update.
- Analysis and offline comparison: `ReferenceAnalysis/Weapons/M4/M4_Audio_Analysis.md`.

```lua
-- Client datamodel, in a playtest
local Run = require(game.Players.LocalPlayer.PlayerScripts.M4AudioTest.Run)
Run.assets()  Run.fire("single")  Run.fire("taps")  Run.fire("sustained")  Run.fire("ads")
Run.fire("stressed")  Run.fire("repress")  Run.reloads()  Run.interrupt()  Run.switching()  Run.perf()
Run.death("before")  -- then on the Server: game.Players:GetPlayers()[1].Character.Humanoid.Health = 0
Run.death("after")   -- once respawned
Run.timeline("ads")  -- raw play log (ReferenceAnalysis/Weapons/M4/Audio/data/ingame_timeline_v2.json)
```

## What the correction pass changed in this test

- **`assets`:** 8 sounds instead of 7: ShotRegularA / B and ShotStressedA / B (77.5 s sprites with `PlaybackRegion`),
  plus the 4 reloads.
- **`fire`:**
  - Checks every shot's burst position against the shot schedule: a shot one fire interval after the previous one
    continues the burst, anything else is position 1.
  - Checks the set for the state (Regular / Stressed), alternating voices, and that a playing shot voice stays inside
    its 2.5 s region.
  - New kinds: `"stressed"` and `"repress"` (a one-frame release inside the fire cycle continues the burst; a 0.3 s
    break starts a new one).
- **`death("after")` / `perf`:** check position 1 instead of the old ShotFirst name. `perf` now runs 200 continuous shots
  through the plateau wrap and both sets.

These follow the implementation's new contract (Config.Audio.M4). No check was loosened: the old "first / sustained"
checks are now stricter per-position checks.

**AK audio slice (2026-11-09).** The AK now has its own audio (`Config.Audio.AK`). This test's "every other weapon is
silent" checks were narrowed to what they guard, and the narrowed checks pass in a playtest with both weapons' audio.
- `assets`: weapons *without* an audio config must have 0 sounds. The only other weapon-audio folders allowed are those
  of weapons that have a config (the AK).
- `playing()`: no longer counts sounds inside other weapons' own audio folders as stray sounds.
- `switching`: still requires 0 M4 sounds on every other weapon, and now also 0 sounds from a third weapon's folder.
- No M4 check changed.

## Results (Studio playtest, 2026-11-09, correction pass)

| Test | Result | Pass |
|---|---|---|
| assets | 8 sounds in `SoundService.WeaponAudio_M4`, all loaded from `rbxasset://sounds/M4Reference/`. Shot sprites 77.5 s with regions; reloads 3.533 / 3.067 / 3.700 / 3.600 s; not looped; volume 0.1. AK / MP7 / Glock / Sniper / ScopeTest: no audio, 0 sounds, no folder | yes |
| fire single | 1 shot → 1 sound, position 1; play 0 ms after the scheduled shot; tail ends 2.518 s after it; server accepted 1 | yes |
| fire taps (4 × one frame, 0.25 s apart) | 4 shots → positions 1, 1, 1, 1; server accepted 4 | yes |
| fire sustained | 31 shots → positions 1 … 31, ShotRegularA / B in turn. ≤ 1 shot voice. Play delay 0–6 ms (mean 3). Spacing 78 ± 2 ms. Tail 2.538 s. Server accepted 31. 818 region samples, 0 outside | yes |
| fire ads | as sustained: 31 / 31, positions 1 … 31, tail 2.529 s, 839 region samples, 0 outside | yes |
| fire stressed | 31 / 31 on ShotStressedA / B, positions 1 … 31, tail 2.534 s, 801 region samples, 0 outside | yes |
| fire repress | 14 shots → positions 1 … 10 (through the one-frame release), then 1 … 4 after the 0.3 s break (1 restart). Server accepted 14 | yes |
| reloads | each of the four starts its own sound once. Sound − clip time mean / SD: TR −6 / 7, ER 0 / 8, TS −5 / 8, ES −17 / 8 ms. Sound ends vs reload end: +16 / +11 / −6 / +5 ms | yes |
| interrupt | switch during a reload: stopped after 6 ms; during a shot tail: 7 ms. Firing during a reload: refused, 0 shot sounds, reload continues. Reload cancelled by a correction: stopped in the same frame | yes |
| death (during a reload + shot tail) | both playing before; stopped 5 ms after `Died`; after respawn the first shot is position 1; one M4 folder | yes |
| death with the trigger held (inline, same playtest) | a shot voice playing; stopped 4 ms after `Died`; after respawn position 1; one folder | yes |
| switching | M4 → AK → MP7 → Glock → Sniper → M4, firing each: M4 shot voice only while the M4 fires; 0 M4 sounds on the others; 0 other weapon sounds | yes |
| perf | `WeaponAudio:Shot` 8.4 µs per call (v1: 13.9–16.2); reload start + stop 7.3 µs. Sustained-fire frame time M4 4.945 ms mean / 5.509 p95 vs AK (no audio) 4.966 / 5.489. 8 Sound objects. Sounds memory tag 6.42 MB, unchanged by the probe instance | yes |

**Console:** 0 errors and 0 warnings from game code; only the normal `[Weapon]`, `[AI]`, `[Vehicle]` and `[M4AnimTest]`
lines.

**Security (unchanged design).**
- Audio is client presentation, called after the client's own fire / reload decisions.
- `WeaponAudio` and `Config.Audio.M4` reference no remote.
- Source diff against `2026-11-09_before_m4_audio_fidelity_correction`:
  - changed: `Client.WeaponAudio`, `Shared.Config.Audio.M4`, `Client.WeaponController` (2 call lines + 1 comment line),
    this test module;
  - unchanged: everything in `ServerScriptService`, every weapon config, and the remotes.
- Server accepted / rejected counts match the shots fired in every firing test.

## Full regression (correction pass; one fresh playtest, Grenade suites last, background agent, 2026-11-09)

The baseline is the slice's regression (in the pre-change copy's `_analysis/M4AudioTest/README.md`).

| Area | Result | vs baseline |
|---|---|---|
| M4 (Firing / Reload / HUD) | 770 RPM, 0 rejected. Recoveries ADS 0.740 / hip 0.741 s. De-cant −32.597° → 0.097°. ADS in 0.332 / 0.331, out 0.120 / 0.120 s. Reloads 3.528 / 3.063 / 3.697 / 3.599 s. HUD 13 / 0, labels 1.701 / 1.734 / 1.604 s. Extras pass | same |
| M4ModelFidelityTest | all pass. 10 parts, 10,466 tris. Post 0.070, glass (0.504, 0.505), hood 0.115, FOV 62.233. Hands 0.121 / 0.066. Reloads 3.537 / 3.705 / 3.070 / 3.604 s. Respawn pass | same |
| AK | 640 RPM. Climb 1.229 / 1.941°. Raised 0.129 / 0.288 s. Reloads 2.430 / 1.664 / 3.129 / 2.764 s, label 1.070 s | within spread |
| MP7 | 41 / 41 ×3. Climb 4.135–4.139°. ADS 0.250 / 0.149 s. Reloads 3.272 / 4.936 / 2.101 / 3.403 s. Forged as its README | within spread |
| Glock | 16 / 16, reload 3.404 s (swap 2.168, slide 2.667). Forged as its README | same |
| Sniper | eject 0.703, next shot 1.567, tactical 4.168 s, zoom 6x. Forged as its README | same |
| Optics | in 0.145 / 0.141, out 0.151 / 0.150 s. Magnification 4.501, tracking 0.894 / 1.110°, 0 remotes scoped | within spread |
| Movement | rules 25 / 25. Walk 5.600, crouch 2.800 / 2.70, jump +7.532, lag 5.948 / 7.385°, roll 1.399 / 2.699° | same |
| FirstPerson | all pass. L+12: M4 0.73 then 0.75 / L+10, AK 0.92, MP7 0.57, Glock 0.93, Sniper 0.68. Security as before | same |
| BodyState / Ballistics / Hit reactions / Blood | 42/42, 6/6, 6/6; 10/10 per lane, 18/18; 6/6, 6/6, 11/11, tamper; 14/14, 14/14, dead hit, world, security, orphans | same |
| Body interaction | pulse 3.016–3.020 s, drag 9.06 studs, trail 12 (11 placed), "too far" 0.802 s | within spread |
| Death / respawn | pulse interrupted, AK reload cancelled after the swap, respawn 3.273–3.368 s, a grenade before death detonates once (4.0011 s) | within spread |
| AI | 14/14, 8/8, 11/11, 10/10. Player as target 6/7, then 7/7 on the rerun (the bot acquired the player 29 ms before the client's own "moved" stamp: the timing race recorded in the Optics README). 5/5, 6/6, security 10/10 | same pattern (known flake) |
| M4AnimTest | 337 of 339 at 3.529–3.543 s (start hitch 5.278 s; one 3.708 s right after a scripted death) | same pattern |
| Truck | 10 / 10 after one rerun; 11 forged refused; production-rule refusals as before | within spread (flake, below) |
| GrenadeTest / among bodies / GrenadeFidelity | fuse 4.0003–4.005 s ×16, release 0.150–0.154 s, 36 into bodies, presentation identical, `heldAtReleaseFrames` 8, label 1.402 / 0.198 s | within spread |
| Performance | client M4 hip 4.64 / ADS 4.71 ms, AK 4.58 / 4.59; rerun M4 4.41 / 4.62, AK 4.68 / 4.68; on foot 4.71; server heartbeat 4.67 ms | within spread; the M4 costs no more than the AK |
| M4AudioTest (in the same playtest) | assets, fire sustained / stressed / repress, switching: all pass; ≤ 1 voice; play delay 3 ms; tails 2.520 / 2.531 / 2.544 s | pass |

**Failures, both passed on the rerun.**
1. **AI player-as-target 6/7:** the known timing race described above.
2. **Truck `forgedFinish`:** after a forged exit flight the body ended 3.93 studs from the exit point (the test allows
   1). Movement had refused the flight ("too high: 25.77 studs above the last floor") but placed the body back on the
   truck bed. The rerun gave 0.00 studs and speed 0.
   - It depends on how far the forged velocity carries the body before the 10 Hz movement check.
   - No server, vehicle or movement code changed in this pass, and the M4 isn't fired in that test, so this is not an
     audio regression.
   - Noted as a possible flake in the Truck suite, not investigated further.

**Console (regression).**
- 0 game-code errors.
- Expected forged-request lines: Weapon rejected 123, Grenade 34, Interact 26, Vehicle 77. The extra Vehicle lines are
  the Truck rerun (32) plus one leave request the agent sent with the wrong target.
- Studio-internal: Wrap-deformer ×16, undefined flags ×4, settingsUrl ×4, HTTP 403 ×36 / 400 ×1, 3 social-API errors at
  play start.

**Not run** (as in the baselines): the FirstPerson latency rows, the Truck prompt µs cost, the Sniper `dead` forge, the
M4 forged-request set, a two-player test.

**Observations outside the baseline:** GrenadeFidelity's label box reads −32 px from the left (as in the slice's run),
and its launch angle read 17.1° above the aim against 18.9° in its README. Neither is a regression baseline; neither was
investigated, and no grenade code was touched.

## Earlier results (slice, 2026-11-08, v1 sounds)

Kept in `Roblox/Scripts/Checkpoints/2026-11-09_before_m4_audio_fidelity_correction/_analysis/M4AudioTest/README.md`:
all pass, including the full regression and the test-bug note (A / B voice phase).
