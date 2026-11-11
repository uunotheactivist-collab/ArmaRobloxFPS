# M4 firing/recoil test (focused, Studio playtest only)

**In Place1:** `StarterPlayer.StarterPlayerScripts.M4FiringTest.Run` (ModuleScript; mirror:
`Roblox/Scripts/src/StarterPlayer/StarterPlayerScripts/M4FiringTest/Run.luau`). It drives
`Client.WeaponController` through a Studio-only debug hook (`ProductionWeaponDebug`, never created in a live game),
samples camera and viewmodel at 30 fps (the reference frame rate) and computes the same statistics as
`ReferenceAnalysis/M4/M4_Firing_Analysis.md`. Remove it by deleting the `M4FiringTest` folder.

Run during a playtest, from the client (command bar / MCP):

```lua
local Run = require(game.Players.LocalPlayer.PlayerScripts.M4FiringTest.Run)
Run("single")      -- one 1-frame trigger press
Run("hipBurst")    -- 1.0 s hip burst: cadence + server ammo
Run("adsMag")      -- full magazine aimed + 0.3 s on empty + 1.4 s recovery
Run("hipMag")      -- full magazine from the hip (firing posture)
Run("stressedHip") -- full magazine from the hip in Stressed
Run("stop")        -- 0.5 s burst, release: no late shots, recovery to zero
Run("weaponReset") -- switch away while firing and back
```

Player reset was checked by killing the character on the server and inspecting state after respawn.

## Results (2026-11-06, final calibration)

| Check | Result | Reference | |
|---|---|---|---|
| Single shot | 1 shot; client 29+1 = server 29+1; 1 accepted, 0 rejected | — | pass |
| Repeated fire | 1.0 s → 13 shots, every interval 0.078 s, 770 RPM; server 17+1, 0 rejected | 770 ±25 RPM | pass |
| Full magazine (ADS) | 31 shots at 770 RPM; 0 more during 0.3 s on empty; client = server 0 + empty chamber; 0 rejected (3 runs) | 31 rounds | pass |
| Camera climb, thirds (ADS, 3 runs) | 1.06/1.44/1.38, 0.99/1.20/1.44, 0.92/1.26/1.22 → mean 0.99 / 1.30 / 1.35° | 0.94 / 1.33 / 1.46° | match (±0.1°) |
| Camera pitch p90 / max | 1.77–1.91 / 2.13–2.87° | 1.66 / 2.18° | slightly high |
| Frame-to-frame pitch jitter (MAD) | 0.35–0.37° | 0.74° | **half** (see note) |
| Recovery to <0.05° after the last shot | 0.74 s | ≈0.65 s | close |
| Sight scale p90 / max / median / min | 1.155–1.168 / 1.19–1.23 / 1.04–1.06 / 0.91–0.92 | 1.17 / 1.20 / 1.03 / 0.89 | match |
| Sight vertical mean / sd / max | 1.70–1.78 / 1.81–1.93 / 5.6–6.4° | 1.91 / 1.82 / 6.35° | match |
| Sight horizontal sd | 1.04–1.45° | 1.09° | match |
| Reticle (barrel) sd dx / dy | 1.41–1.59 / 1.47–1.66° | 1.34 / 1.46° | match |
| Sight tilt sd | 1.62–1.88° | 1.71° | match |
| Hip firing posture (roll vs camera) | idle −32.6°, firing +0.05…−0.3°, 150–400 ms after −31.3° | idle ≈33°, firing ≈0 (−3…+8), back in 1–3 frames | match |
| Hip climb (full magazine) | thirds 0.90–1.24 / 1.14–1.46 / 1.43° | short bursts only (R_hip max 1.48°) | consistent |
| Stressed | same recoil numbers + sway (roll up to 2.8° during the burst) | no recoil difference measurable; sway yes | consistent |
| Stop firing | 0.5 s → 7 shots, 0 after release; climb and posture 0 after 1.4 s | — | pass |
| Weapon reset | switch away mid-burst → weapon put down; back → recoil 0, posture 0, ammo kept (27 = 27) | — | pass |
| Player reset | after respawn: client 30+1 = server 30+1, recoil 0, viewmodel back, FOV 70 | — | pass |
| Real input | left click with M4: 2 server-validated hits (dummy 100 → 50; the click lasted > 1 cycle) | — | pass |
| Test blaster | key 1, click: `[Combat]` hit 50 → 25, crosshair back, M4 hidden | — | pass |
| Console | no errors or warnings; reload test still plays 3.53 s | — | pass |

**Notes.** Per-frame camera jitter is half the reference's: raising the shake further pushes pitch p90/max above
the reference, so part of the reference jitter is probably horizon-measurement noise on flash frames (uncertain).
The reticle's +0.4° vertical mean is a visibility effect (the dot is hidden when the barrel points outside the
window, and the window rides up while firing); its spread matches.
