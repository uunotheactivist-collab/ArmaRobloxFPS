# First-person fidelity tests (2026-11-08)

The suite for the first global first-person pass: weapon lowering during the grenade throw, and the thrower's
client-side view of its grenade in flight. Analysis: `ReferenceAnalysis/FirstPerson/FirstPerson_Analysis.md`.

## Files and hooks
- `StarterPlayer/StarterPlayerScripts/FirstPersonTest/Run.luau`: the client half.
  - It samples every rendered frame at render priority Last:
    - the viewmodel's presence in the 1280 × 720 picture, as part corners inside the picture;
    - the visible grenade (in hand / proxy / replicated body), with its prediction phase;
    - WeaponLowering's amount.
- `ServerScriptService/FirstPersonTest/Run.luau`: the server half.
  - `prepare` (client teleports allowed, grenade records cleared), `killDuringThrow(delay)`;
  - `watchLaunch` / `launchResult(aim)`, `grenades`, `serverView`, `netStart` / `netStop`.
- Studio-only hooks added to `GrenadeClientDebug`: `prediction`, `predictionClear`, `predictReleased(msg)`, `lowering`,
  `lowerPlay(profile)`.
- Copies of both modules here: `FirstPersonTest_Client_Run.luau`, `FirstPersonTest_Server_Run.luau`.

## How to run (execute_luau)
1. **Server:** `require(game.ServerScriptService.FirstPersonTest.Run).prepare()`.
2. **Client:** `local FP = require(game.Players.LocalPlayer.PlayerScripts.FirstPersonTest.Run)`, then in separate calls
   (each under 60 s):
   - `FP.timing(weapon)` for M4, AK, MP7, Glock, Sniper;
   - `FP.release(-4.5)`, `FP.release(20)`, `FP.release(-70)`;
   - `FP.rapid()`, `FP.switching()`, `FP.transitions()`, `FP.movement()`;
   - `FP.idle(weapon)` for all five, `FP.forged()`.
3. **Death:**
   - on the server, `killDuringThrow(0.05)`, then on the client `FP.death("before")`;
   - on the server, `killDuringThrow(0.3)`, then on the client `FP.death("after")`.
4. **Security:**
   - on the server, `netStart()` and `watchLaunch()`;
   - on the client, `FP.forgeThrowArgs()`, plus a forged `predictReleased` and the server-only remotes fired;
   - on the server, `launchResult(aim)`, `netStop()`, `grenades()`, `serverView()`.
5. **Latency:** on the client, set `settings().Network.IncomingReplicationLag` to 0.15 / 0.3 around `FP.release(...)`,
   then set it back to 0.

## Results (final scripts, fresh playtest)

| Test | Checks | Result |
|---|---|---|
| timing M4 / AK / MP7 / Glock / Sniper | rest at L−4; ≤ 30 % at L−1; none L … L+9; ≥ 50 % by L+12; ≥ 90 % by L+15; identity after | **pass ×5**. First pixels L+10 (M4, AK, Sniper) / L+11 (MP7, Glock); at L+12: 0.93 / 0.92 / 0.57 / 0.93 / 0.74 |
| release −4.5° (contact 0.35 s) | no hold, rest at contact ≤ 1 frame, no reversal, smooth hand → proxy → body, handed over, body shown | **pass**: hold 0, rest 0.01 s; hand → proxy 0.20 studs (neighbour 0.18); proxy → body 0.07 (0.09); lag 0.16 s, speed 0.68 × |
| release 20° (long lob, contact 2.17 s) | same | **pass**: handed over mid-air at 1.0 s; hand → proxy 0.27 (0.23); proxy → body 0.17 (0.38); lag 0.14 s, speed 0.86 × |
| release −70° (into the ground, contact 0.08 s) | same; rest ≤ 5 frames (contact before the body moves) | **pass**: rest 0.11 s; proxy → body 0.19 (0.20) |
| rapid | 8 presses in one throw → 1 throw; 4 back-to-back → 4 released, 0 refused; all handed over; ≤ 3 proxies built; nothing left | **pass**: 1; 4 / 0; 5 / 5; 1 built; clean |
| switching | M4 → AK → Glock → Sniper during the throw: none in view L … L+9, back after, 1 viewmodel | **pass** |
| transitions | reload during the throw (keeps going, finishes: mag 30); ADS held (hidden L+5, aim 1.0 after); Sniper scoped (state SCOPED before = after); MP7 trigger held (9 shots at 0.06 s, not blocked); switch mid-reload; nothing left | **pass** |
| movement | walk, crouch, jump, fall: handed over, no hold, no reversal, hidden at L+5, identity after | **pass**. Server vs local release point: 0.42 / 0 / 5.4 / 15.9 studs (faded along the flight) |
| idle ×5 | every frame of fire / ADS / reload with lowering 0 | **pass**: 0 / 536–570 frames lowered |
| death before release | server refuses "died before the release"; no arm and no proxy after death; clean after respawn | **pass** (died 0.07 s after the press) |
| death after release | the flight finishes; no arm after death; clean after respawn | **pass** |
| forged Released | 5 / 5 malformed rejected; a well-formed fake shows locally and ends | **pass** |

### Security (server half)
- **Throw with forged extra arguments** (`Vector3(0, 500, 0)`, `Vector3(9999, 0, 0)`, `1e9`):
  - the grenade starts on the server's own rule: 0.001 studs from it, 1.20 studs from the head;
  - its velocity is exactly the server's (error 0, 55 studs/s).
- **A velocity sent in place of a direction:** refused, "not a direction (|v| = 55)".
- **A forged local "Released"** (id 9999, from 300 studs up): no such grenade on the server (highest id 25); counters
  unchanged.
- **GrenadeState / GrenadeFx fired from the client:** counted (StateClientCalls 1, FxClientCalls 1) and ignored.
- **Client → server traffic** during the security run:
  - GrenadeCommand 4 (2 refills, 2 throws), WeaponCommand 1 (refill), plus the 2 forged calls;
  - prediction and lowering send nothing.
- **What the server sees:** no proxy anywhere; grenade bodies opaque (`LocalTransparencyModifier` is client-only).

### Latency (`IncomingReplicationLag`)

| Extra lag | Long lob (20°) | Contact at 0.35 s (−4.5°) |
|---|---|---|
| 0 | pass; lag 0.12 s, planned 0.19; speed 0.88 ×; match 0.08 studs | pass; rest 0.01 s |
| 0.15 s | pass; lag 0.31, planned 0.30; speed 0.69 ×; match 0.10 | rest 0.08 s (fails the 1-frame check) |
| 0.30 s | handed over with a 0.70-stud offset, blended out over 0.1 s (fails the strict step check); lag 0.47, planned 0.45; speed 0.53 × | rest 0.21 s |

There is never a hold at the release. A first contact that the server body reaches before the proxy can (close
geometry, high latency) rests for part of the lag: the server's bounce is never predicted.

### Full regression (one fresh playtest, final scripts; Grenade suites last)

Same calls as the grenade fidelity slice's final regression (`Roblox/Tests/Grenade/README.md`), plus the M4 reload
extras and the Glock / Sniper forged sets.

| Area | Result | vs baseline |
|---|---|---|
| M4 | 770 RPM, recovery 0.74 / 0.739 s, de-cant −32.575° → −0.180°, ADS 0.332 / 0.120 s, reloads 3.530 / 3.066 / 3.696 / 3.598 s, reload extras pass; HUD 13 / 0 | same |
| AK | 640 RPM, climb 1.235° / 1.943°, raised 0.130 / 0.288 s, reloads 2.429 / 1.662 / 3.132 / 2.764 s, label 1.067 s | same |
| MP7 | 41 / 41 at 950 RPM ×3, climb 4.128–4.135°, ADS 0.251 / 0.149 s, reloads 3.271 / 4.935 / 2.101 / 3.404 s, forged as before | same (ADS back at its baseline) |
| Glock | 16 / 16, reload 3.403 s (swap 2.169, slide 2.670), forged set as its README | same |
| Sniper | eject 0.704, next 1.567 s, tactical 4.170 s, zoom restores 6x, forged set as its README | same |
| Optics | in 0.142 / 0.141, out 0.151 / 0.154 s, magnification 4.500, tracking 0.894 / 1.110°, 0 remotes scoped | same |
| BodyState / Ballistics / Hit reactions / Blood | 42 / 42, 6 / 6, 6 / 6; 10 / 10 per lane, 18 / 18; 6 / 6, 6 / 6, 11 / 11, tamper; 14 / 14, 14 / 14, dead hit, world, security, orphans | same |
| Body interaction | pulse 3.014–3.016 s, drag 9.08 studs, trail 11, "too far" 0.763 s, tamper, orphans (known WalkSpeed 5.6) | within spread |
| Death / respawn | interrupted pulse; AK reload cancelled after the swap; respawn 3.28–3.35 s; a grenade thrown before death detonates once (4.0004 s) | same |
| AI | perception 14 / 14, aiming 8 / 8, firing 11 / 11, integration 10 / 10, player as target 7 / 7 ×3, bot shoots player 5 / 5, takedown 6 / 6; security **9 / 10** in the long playtest → **10 / 10** in a fresh one | the S4 check counts rejection lines in a log capped at 512 lines, which the earlier weapon suites had filled; the server did reject the shot ("origin 19 studs from head") |
| Movement | rules 25 / 25, walk 5.600, crouch 2.800 / eye 2.70, jump +7.532, lag 5.953 / 7.391°, roll 1.399 / 2.699° | same |
| M4AnimTest | 3.530–3.542 s (one play at 3.709 s right after a scripted death) | within spread |
| GrenadeTest | fuse 4.0001–4.0034 s ×20, release 0.148–0.153 s, wall / lob / steep / room as before, forged refused, server-owned throughout | same |
| Grenade among bodies | 35 / 38 / 34 fragments into bodies; one more throw released at a stale server head position right after a client teleport (0 into bodies), reruns normal | within spread |
| GrenadeFidelity | presentation identical (L+1 grenade at (500, 125)); label 1.402 / 0.195 s; red edge envelope identical; fragmentsHit / security as before; `heldAtReleaseFrames` of the replicated body **8 / 7 / 8**, then 7 / 7 / 8 / 7 / 7 | was 6–7. This counts the replicated body, which the thrower no longer sees (it is hidden while the proxy flies); the body is created and launched as before. The extra frame is replication timing (motion reaching the client at ≈ 0.23–0.27 s) |

- **M4 Stressed reload end-pose discrepancy:** known, not changed: 0.710° tactical, 2.343° empty.
- **Console:** 0 game-code errors. The warnings are the expected rejections of forged shots / commands.

### Performance (same method as the baseline: M4, grenade range, Studio)

| | Before | After |
|---|---|---|
| Client frame, idle (mean / p95) | 4.23 / 4.69 ms | 4.17 / 5.06 ms |
| Client frame, throw + detonation 5.5 s (mean / p95 / max) | 4.25 / 4.78 / 6.43 ms | 4.26 / 4.65 / 5.80 ms |
| Server heartbeat (mean / p95) | 4.19 / 5.98 ms | 4.17 / 5.98 ms |
| Client instances after a further throw | — | +0 (one pooled proxy: 2 parts, made once) |

- **Per-frame work:**
  - WeaponLowering is one table check per frame when idle (a CFrame only while a throw plays).
  - GrenadePrediction binds its render step only while a proxy exists:
    - one closest-point search of ≈ 40–140 path samples;
    - two part CFrames;
    - one ballistic sweep (≤ 180 short raycasts) per path, at the release and at the server's message.
- **ViewportFrames:** none added.
- **Memory:** Studio's process figure (2 679 MB on both sides) grew over a long session of edits and playtests; it is
  not comparable with the baseline.
