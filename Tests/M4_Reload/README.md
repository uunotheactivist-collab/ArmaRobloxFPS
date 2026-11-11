# M4 reload test

**What it is.**
- A focused test of the production M4 reloads.
- Studio playtest only: `StarterPlayer.StarterPlayerScripts.M4ReloadTest.Run`; a copy is in this folder as `M4ReloadTest_Run.luau`.
- It drives the real reload path (client clip + server command) through the Studio-only debug hook `Client.WeaponController.ProductionWeaponDebug`.
- It records every rendered frame and reports timing, joint behaviour and ammunition on both sides.
- Delete the `M4ReloadTest` folder to remove it.

**What it leaves alone.** The original M4 reload test is untouched and kept running alongside this one:
- `Workspace.M4AnimTest`;
- `ServerStorage.M4AnimTest.M4_Reload_Test`;
- `Roblox/Tests/M4_AnimTest`.

## How to run

In Play mode, from the client (command bar set to Client, or the MCP `execute_luau` Client):

```lua
local Run = require(game.Players.LocalPlayer.PlayerScripts.M4ReloadTest.Run)
Run("tactical", { stressed = false })   Run("tactical", { stressed = true })
Run("empty", { stressed = false })      Run("empty", { stressed = true })
Run("refusals")   Run("partialReserve")   Run("whileAiming")   Run("switchDuring")   Run("repeated")
```

**Death during a reload.** Arm a server listener that kills the character 1.0 s after the next `Reload` command, then reload from the client. The exact snippets used are in the session record.

**Visual capture.** `capture_viewport.ps1` grabs the Studio play viewport with `PrintWindow`, which works while Studio is behind other windows. Use it with the hook's `freeze` command (`{ clip = "...", t = seconds }`) to hold a pose.

## Results (playtest 2026-11-06, Place1, FOV 70, 60 fps render)

### Timing and joints
| Reload | Started | Client clip length | Target (footage) | Magazine leaves rifle* | Magazine seated again* | Charging handle travel |
|---|---|---|---|---|---|---|
| Tactical Regular | TacticalRegular | **3.530–3.532 s** | 3.533 s (34–140) | 0.81 s | 2.28 s (event 2.30) | 0 |
| Tactical Stressed | TacticalStressed | **3.063 s** | 3.067 s (434–526) | 0.44 s | 1.91 s (1.93) | 0 |
| Empty Regular | EmptyRegular | **3.700 s** | 3.700 s (293–404) | 0.44 s | 1.79 s (1.80) | 0.214 studs = 6.0 cm |
| Empty Stressed | EmptyStressed | **3.599 s** | 3.600 s (624–732, end inferred) | 0.24 s | 1.69 s (1.73) | 0.214 studs |

\* The magazine "leaves" when it is more than 0.3 studs from its seat, and is "seated" when it is within 0.02 studs. Both thresholds make the measured times a frame or two from the clip events.

**Final pose:**
- **Regular reloads:** the weapon and arm end within 0.003 studs and 0.4° of the idle.
- **Stressed reloads:** they end within 2.5° (the Stressed sway keeps running).

**Server timing.** The server commits at `CommitAt − 0.1 s` and finishes at `Duration − 0.1 s`. The first shot after a reload was never rejected.

### Ammunition (client prediction = server, every case)

> **Since the HUD milestone:**
> - The Stressed tactical reload dumps its partial magazine, leaving reserve [30,30,30]. The magazine goes to the server's dropped list shown by the HUD label.
> - Ammunition changes in two steps: the swap at `SwapAt`, then the chamber at `ChamberAt`.
> - Re-run results are in `Roblox/Tests/M4_Hud/README.md` → Regression.
>
> The table below is the original reload-milestone run.
| Case | Before | After |
|---|---|---|
| Tactical (4 shots fired) | 26 + 1, reserve 30×4 | **30 + 1**, reserve [30,30,30,26] (partial magazine stowed) |
| Empty (31 shots fired) | 0 + 0, reserve 30×4 | **29 + 1**, reserve [30,30,30] (empty magazine dropped, round chambered) |
| Partial reserve | 0 + 0, reserve [12, 7] | **11 + 1**, reserve [7] (fullest spare used) |
| Full magazine | 30 + 1 | refused: `Full` |
| Empty reserve | 12 + 1, reserve [] | refused: `NoReserve` |
| Real **R** key | 17 + 1, reserve [30,30] | 30 + 1, reserve [30,17] (TacticalRegular) |

### Rules
| Check | Result |
|---|---|
| Fire during a reload (trigger held 0.4 s at +1.0 s) | 0 shots on every reload |
| Fire after a reload | 3/3 shots, all accepted by the server; 0 rejected in total |
| Reload while aiming | reload starts; ADS drops (aim 0, FOV 70 after 0.6 s) |
| R pressed again mid-reload | `Busy`, ignored (3 repeated reloads, ammunition correct each time) |
| Weapon switch before the magazine change (at 1.0 s) | cancelled on both sides; magazine unchanged (25) |
| Weapon switch after the magazine change (at 2.6 s) | cancelled; new magazine kept (30, reserve [30,30,30,25]) |
| Death during a reload (killed at 1.02 s) | server `ReloadCancelled (died)` at once; no magazine change at 2.3 s; after respawn 30 + 1, reserve 30×4, not reloading |

The server log shows each of these: `reload <clip> (... magazine change at ... s)`, `cancelled (weapon switched)`, `cancelled (weapon switched) after the magazine change`, and `cancelled (died)`.

### Regression
| Check | Result |
|---|---|
| Firing test (`M4FiringTest` `adsMag`) | 31 shots at 770 RPM (0.078 s each), server accepted, 0 rejected. Sight scale max 1.19, recovery below 0.05° after 0.74 s (as in the firing milestone) |
| Original M4 reload test (`M4AnimTestRunner`) | played throughout at 3.531–3.542 s. The outliers are the first play (5.05 s, includes loading) and one play during the death/respawn hitch (3.70 s) |
| Console | no errors |
| Scripts | all 26 identical in Studio and `Roblox/Scripts/src` (length:hash). The foundation scripts and the original reload test are identical to the checkpoint copies |

### Reference vs Roblox (`reload_reference_vs_roblox.png`)

Nine poses held with `freeze` and captured from the play viewport: the footage frame on the left, Roblox at the same clip time on the right, same vertical FOV, centre crop.

**What matches:**
- the canted hold (rifle up by the face, sight box large at the right);
- the Regular steep insert (muzzle up at the top centre, hand bringing the tan magazine to the well from the lower left);
- the Stressed canted insert from below;
- the empty reloads' roll-left charging hold (sight box at the lower left, muzzle at the top centre);
- the Stressed empty insert (hand and magazine at the well);
- the return to the canted hip idle.

**Known differences** (see `ReferenceAnalysis/M4/M4_Reload_Analysis.md` §10):
- In the roll-left hold, the front sight post leans ≈40° in Roblox but stands upright in the footage, and the seated magazine shows at the lower right.
- The Roblox scene is daylit while the footage is a dark overcast scene. The environment is a later slice.
- Captures use the Regular presentation, so they have no Stressed camera sway.

The Blender previews `Blender/Animations/M4/previews/M4_Reload_<Clip>_side_by_side.mp4` show every frame: the footage on the left, the production model composited at 85 % over it on the right. Because the overlay is partly transparent, the footage's own white arm can show through where the model's arm is off-screen.
