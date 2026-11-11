# M4 HUD test

A focused test of the M4 HUD, which is a single label: "[TAB] 5.56 MAG", then "… +1", "… +2", as analysed in `ReferenceAnalysis/M4/M4_HUD_Analysis.md`.
- **Where it lives:** `StarterPlayer.StarterPlayerScripts.M4HudTest.Run`, Studio playtest only. A copy is in this folder as `M4HudTest_Run.luau`.
- **How it drives the game:** through the Studio-only debug hook `Client.WeaponController.ProductionWeaponDebug`, the real reload and server path.
- **Removing it:** delete the `M4HudTest` folder.
- **What every check compares:** the label on screen (`PlayerGui.M4Hud.MagazineLabel`) against the text expected from the client's dropped-magazine count, and that count against the server's. It also counts `M4Hud` ScreenGuis and labels.

## How to run

In Play mode, from the client:

```lua
local Run = require(game.Players.LocalPlayer.PlayerScripts.M4HudTest.Run)
Run("sequence")  -- the footage's reload order: Regular tactical, Regular empty, Stressed tactical, Stressed empty
Run("states")    -- firing, partial magazine, ADS, full magazine (refused), weapon switch away / back
Run("check")     -- one agreement check
```

**Death / respawn:** kill the character from the server (`Humanoid.Health = 0`), then call `Run("check")` after respawning.

**Viewport captures:** `Roblox/Tests/M4_Reload/capture_viewport.ps1` (PrintWindow) with the hook's `freeze` and `setAmmo` commands.

## Results (playtest 2026-11-06, Place1, 1452 × 753 viewport)

### Content and timing: the footage's reload order
| Step | Label (game) | Label changed at (clip time) | Footage | Dropped (client = server) |
|---|---|---|---|---|
| Idle after refill | hidden | — | hidden (frames 1–33) | 0 |
| Regular tactical (4 shots) | hidden | no change | no change (34–140) | 0; reserve [30,30,30,26]: magazine kept |
| Empty magazine (31 shots) | hidden | — | hidden (≈290) | 0 |
| Regular empty | **"[TAB] 5.56 MAG"** | **1.704 s** | 1.700 s (frame 344) | 1 |
| Stressed tactical (4 shots) | **"[TAB] 5.56 MAG +1"** | **1.736 s** | 1.733 s (frame 486) | 2; the partial magazine (25) is dumped |
| Stressed empty | **"[TAB] 5.56 MAG +2"** | **1.600 s** | 1.600 s (frame 672) | 3 |

The first run measured 1.623 / 1.654 / 1.516 s: the server swapped the magazine 0.1 s early, because the reload-end allowance was also applied to the swap. That was fixed (the swap and chamber now run at the clip times exactly), then re-run with the results above. All changes match the footage within one 60 fps frame.

### States
| Case | Label | Agreement |
|---|---|---|
| Firing with the label shown (6 shots, magazine 23) | unchanged "+2" | HUD = client = server |
| ADS | shown, unchanged (design choice; the footage has no ADS after frame 344) | ✓ |
| Full magazine: reload refused (`Full`) | unchanged | ✓ |
| Weapon switch to the test blaster | **hidden** | ✓ |
| Switch back to the M4 | shown again, same text | ✓ |
| Dead (killed by the server) | **hidden**, still one GUI | ✓ |
| After respawn | hidden (new loadout: dropped 0 on client and server) | ✓ |
| Empty reload interrupted by a switch after the swap (2.1 s) | "[TAB] 5.56 MAG": the empty magazine is dropped and the new one is in but not chambered. The next reload returns the loaded magazine to the reserve: 29 + 1, reserve [30,30], dropped still 1 | ✓ no rounds lost |

**Duplicates and leftovers:**
- every check found exactly 1 `M4Hud` ScreenGui with exactly 1 label;
- `PlayerGui` holds `M4Hud`, the foundation's `CombatHUD`, and Studio's `Freecam`;
- the foundation crosshair stays hidden with the M4 (unchanged behaviour).

### Geometry: game vs footage (`captures/label_EmptyRegular_3.40.png`)
| | Footage | Game | |
|---|---|---|---|
| Centre x (of screen width) | 0.499 | **0.500** | ✓ |
| Centre y (of screen height) | 0.772 | **0.773** | ✓ |
| "[TAB] 5.56 MAG" ink width (of height) | 0.0787 (34 px ±1) | **0.0770** (58 px; TextSize 11) | −2 %, within ±3 % |
| Text height (of height) | ≈0.0139 (6 px after blur; 8 px with blur) | **0.0120** (9 px) | ≈14 % lower: the footage font is a bit more condensed than SourceSans |
| Colour | opaque grey, peak luminance 0.55–0.60 | (150,150,150), opaque | ✓ |
| Behaviour | screen-fixed, instant changes | screen-fixed, instant | ✓ |

`hud_reference_vs_roblox.png` shows five footage frames next to Roblox in the same state: 150 (no label), 395 and 440 ("[TAB] 5.56 MAG"), 530 ("+1") and 705 ("+2"). A sixth row shows ADS, which has no footage. Each row has a 4× inset of the label region from both. In the insets the label spans the same horizontal range (within 1–2 footage pixels) on the same row.

### Regression (same session)
| Check | Result |
|---|---|
| Reload test, all four reloads | 3.533 / 3.064 / 3.701 / 3.596 s. No shots during reloads; 3/3 shots accepted after; 0 rejected |
| Refusals, partial reserve, reload while aiming, weapon switch before/after the magazine change, repeated reloads | all as before |
| Changed by this milestone (intended) | the Stressed tactical reload dumps its partial magazine (reserve [30,30,30] instead of [30,30,30,26]). The ammunition change now happens at the measured `SwapAt` |
| Firing test (`adsMag`) | 31 shots at 770 RPM, 0 rejected; recoil statistics unchanged |
| Original M4 reload test | playing at 3.530–3.542 s; 107 keyframes |
| Console | no errors |
| Scripts | all 29 identical in Studio and `Roblox/Scripts/src`; foundation and original reload test identical to the checkpoint |
