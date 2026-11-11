# Truck / vehicle tests (2026-11-08)

The suite for the truck slice: a static cargo truck that players get into (bed and driver seat), move between seats in,
and leave, with the cab's door, key, parking brake and lights controls. The truck never moves in the reference footage,
so nothing about driving is tested (not built). Analysis: `ReferenceAnalysis/Truck/Truck_Analysis.md`.

## Files and hooks
- `StarterPlayer/StarterPlayerScripts/TruckTest/Run.luau`: the client half.
  - It stands the player at one of the truck's `TestSpot_*` attachments (a client teleport, the old suites' way).
  - It turns the camera to a target part, presses F through `VehicleClientDebug` and reads the server's answer.
- `ServerScriptService/TruckTest/Run.luau`: the server half.
  - `prepare` (Studio switch on, vehicles reset, log cleared, player placed server-side behind the tailgate);
  - `placeAt(spot)` (a server placement: production rules), `switch(on)`;
  - `view` (the server's copy: seat attributes, weld, root against its Hip, Movement's view, the truck's pivot);
  - `occupy(seat, userId)` (a stand-in occupant), `kill`, `status`, `log`, `weaponRejects`, `netStart` / `netStop`.
- Studio-only hooks:
  - `VehicleDebug` (server): `status`, `log`, `clearlog`, `occupy`, `reset`.
  - `VehicleClientDebug` (client): `view`, `press`, `switch`, `send` (raw request), `raise`, `messages`, `sent`,
    `clear`.
- The truck carries four test spots: `Tailgate`, `DriverDoor`, `Far` (out of reach) and `PassengerSide` (the cab
  between it and the driver door).
- Copies of both modules here: `TruckTest_Client_Run.luau`, `TruckTest_Server_Run.luau`.

## How to run (execute_luau, one fresh playtest)
`S` = `require(game.ServerScriptService.TruckTest.Run)` on the Server.
`C` = `require(game.Players.LocalPlayer.PlayerScripts.TruckTest.Run)` on the Client.
Call `S.prepare()` before each line below; keep each call under 60 s.

1. **Client:** `C.spawn()`, `C.back()`, `C.screen()`.
2. **Client:** `C.driver()`.
3. **Client:** `C.weapons()`, then `C.repeated(3)`. Check `S.status()` / `S.view()`: no occupied or reserved seat, no
   weld, walk 5.6 / jump 7.2 back.
4. **Contention:** `S.occupy("Back2")` and `S.occupy("Driver")`, then on the client `C.contention()`.
5. **Forged (Studio rules):**
   - on the client, `C.forged()`; it ends seated after a client-side teleport attempt;
   - on the server, `S.view()`: still on its seat, root on the Hip, truck unmoved;
   - on the server, `S.switch(false)`;
   - on the client, `C.forgedFinish()`: rate limit and the exit under production rules;
   - on the server, `S.view()` and the MovementDebug events.
6. **Security under production rules** (`S.switch(false)`):
   - `S.placeAt("PassengerSide")` → on the client:
     - `C.raw("OpenDoor", "DriverDoorPanel")` and the same with `aim = true`;
     - a client-side teleport into the cab, then a raw `OpenDoor`.
   - `S.placeAt("Far")` → on the client:
     - `C.raw("EnterBack", "Tailgate")`;
     - a client-side teleport to the tailgate, then a raw `EnterBack`.
   - `S.placeAt("Tailgate")` → on the client: a raw `EnterBack` (control), then leave.
7. **Death:**
   - on the client, `C.deathInSeat("enter")`, and hook `Humanoid.Died` to send raw `Leave` / `MoveSeat` / `EnterBack`;
   - on the server, `S.kill()`;
   - on the client, read the messages, then `C.deathInSeat("after")`.
8. Read both consoles before stopping play.

## Results (final scripts, fresh playtest)

| Test | Checks | Result |
|---|---|---|
| spawn | start state (door closed, key STOP, parking brake set, lights off), 6 seats (Back1–5, Driver), target parts | **pass** |
| back | "Get in (back)" at the tailgate; cut to Back1; eye on the seat's Eye; yaw = seat facing, pitch kept; CONTROLS panel (8 lines); rifle down; legs + lap arms; "Move to back seat" → Back4; "Leave vehicle" over the left rail → left side; exit pitch −53°; panel gone; rifle back on foot | **pass**: cuts 3 / 5 / 5 frames from the press (reference 2 / 4–5 / 5); eye 7.62 studs; pitch kept to 0.00°; panel gone 0.27 s after the answer (+≈ 0.1 s before it) |
| screen | prompt and panel pixels against the reference (1280 × 720 scale) | **pass**: box (577.9, 350.0), 19.1 px (ref 578.6, 350.6, 19.4); text from 607.5 (608); line 2 +25.8 / +25.8 (+25.4 / +26.0), text 0.82× (0.8×), "○" on line 2; panel right edge 1261.8 (1262), centre y 360.0 (360.5) |
| driver | door from outside; "Get in (driver) │ Close door"; cut; eye; panel (9 lines); weapon stowed; legs, no lap arms; close door from inside (left arm with the door); "Turn key to RUN"; right arm out on hover (1.0) and back after the press (0.0); "Hold START  (WAIT lamp's still on)" → NotBuilt; key back to STOP; parking brake release / set; "Lights on" → NotBuilt; W / A / S / D move nothing; open door from inside; leave; exit on the left, facing forward, looking 53° down; the truck never moves | **pass**: swings 0.61 / 0.27 / 0.55 s (configured 0.60 / 0.35 / 0.63 including the 2-frame send); open angle −82.0°; cuts 3 / 6 frames (reference 3 / 6); eye 6.53 studs; moved 0; truck moved 0 |
| weapons | bench: rifle down at idle (0 viewmodels), raised by FIRE (1), shots accepted by the existing weapon server; driver: no viewmodel, no shot, reload refused, a forged shot and a forged grenade refused | **pass**: 7 bench shots, 0 rejected; driver 0 shots, reload "NotReady"; "[Weapon] rejected shot …: in the driver seat", "[Grenade] … Throw rejected: in a vehicle seat" |
| repeated(3) | 3 bed + 3 driver round trips; nothing left over | **pass** 6 / 6; no occupant / reservation, no weld, walk 5.6, jump 7.2 |
| contention | stand-in occupants on Back2 and Driver: Back2 not offered; a forged MoveSeat to it refused; "Get in (driver)" refused | **pass**: "not offered"; "seat taken" |
| forged (Studio rules) | 11 malformed / impossible requests refused, seat unchanged; junk position / direction arguments ignored on a valid enter; two enters in one frame → one seat; a client-side teleport / velocity while seated | **pass**: not a vehicle; not a target of this vehicle (other model, NaN in the part slot); not offered (unknown action, tailgate → driver); bad request (200-char action); bad seat (number, unknown id); blocked by the closed driver door; out of range 17.5 studs; blocked by the passenger door; duplicate 1 entered / 1 refused; the client's copy moved 40 studs, the server's did not (root on the Hip, welded, truck at its pivot) |
| forgedFinish (production rules) | rate limit; a forged VehicleState from the client ignored; the exit with the forged velocity still on the client's copy | **pass**: 12 of 20 refused "rate"; exit 0.00 studs from the exit point, speed 0. Movement logged one rejection ("too high") and pulled the body back |
| security, production rules | passenger side → driver door (no aim / aimed); client teleport into the cab + OpenDoor; far → EnterBack; client teleport to the tailgate + EnterBack; control enter / leave | **pass**: blocked by the passenger door ×3 (the server judges from the last validated place and puts the body back); out of range 17.5 ×2; control entered / left |
| death in a seat | released through the existing death path; Leave / MoveSeat / EnterBack from the dead player; after respawn | **pass**: "release died"; all three refused "dead"; no seat, no panel, no seat eye, rifle back |

Console: 0 game-code errors. The only warning is the expected `[Weapon] rejected shot from …: in the driver seat` from
the forged driver-seat shot.

### Security notes
- **What the server owns:** position, seating, occupancy, doors, key, parking brake and lights. A client only names an
  action, a target part, a seat id and its aim direction. A direction is accepted only if finite and unit length, and
  only steers the server's own visibility ray from its own eye point.
- **Seated:** the body is welded to the anchored truck. A client moving or pushing its own copy changes nothing on the
  server. The client's own view goes with its copy.
- **Exit:**
  - The server holds the body anchored for 0.15 s while it places it at the exit point.
  - Movement resumes validating at once; there is no grace window after a vehicle exit.
  - A client that forged a velocity while seated is corrected by the validator after the exit (one rejection).
- **On foot:** requests are judged from the place Movement last validated. A body more than 4 studs from it is refused
  ("position not validated yet").
- **Under the Studio switch:** the validator follows client teleports even through the truck, so the "blocked" case can
  pass if a request arrives while the server's copy is crossing the cab. The client test waits 0.6 s after each
  placement, and the decisive check is the production-rule run (step 6).
- **Two players:** only stand-in occupants were tested; a real two-client test was not run (the Studio MCP drives one
  client). The server reserves a seat at the request, so two requests for one seat can't both get it.

### Full regression (one fresh playtest, final scripts; Grenade suites last; background agent)

Same calls as the first-person pass's final regression (`Roblox/Tests/FirstPerson/README.md`), plus the FirstPerson
suite. The client stayed on foot throughout (`VehicleSeat` nil), `IncomingReplicationLag` 0.

| Area | Result | vs baseline |
|---|---|---|
| M4 | 770 RPM, recovery 0.74 / 0.772 s, de-cant −32.575° → 0.173°, ADS 0.333 / 0.119 s, reloads 3.533 / 3.064 / 3.697 / 3.599 s, extras pass, HUD 13 / 0 | within spread |
| AK | 640 RPM, climb 1.230° / 1.942°, raised 0.125 / 0.287 s, reloads 2.431 / 1.665 / 3.132 / 2.765 s, label 1.068 s | within spread |
| MP7 | 41 / 41 at 950 RPM ×3, climb 4.125–4.126°, ADS 0.252 / 0.151 s, reloads 3.270 / 4.935 / 2.102 / 3.403 s, forged as before | same |
| Glock | 16 / 16, reload 3.401 s (swap 2.169, slide 2.665), forged set as its README | same |
| Sniper | eject 0.702, next 1.567 s, tactical 4.172 s, zoom restores 6x, forged set as its README | same |
| Optics | in 0.141 / 0.141, out 0.153 / 0.151 s, magnification 4.500, tracking 0.894 / 1.110°, 0 remotes scoped | same |
| Movement | rules 25 / 25, walk 5.600, crouch 2.800 / eye 2.70, jump +7.532, lag 5.953 / 7.391°, roll 1.399 / 2.699°, death / respawn as before | same |
| FirstPerson | all pass; first frames back L+10 / L+11; at L+12 0.90 / 0.92 / 0.57 / 0.93 / 0.68; security as before (latency rows not run: lag kept at 0) | within spread |
| BodyState / Ballistics / Hit reactions / Blood | 42 / 42, 6 / 6, 6 / 6; 10 / 10 per lane, 18 / 18; 6 / 6, 6 / 6, 11 / 11, tamper; 14 / 14, 14 / 14, dead hit, world, security, orphans | same |
| Body interaction | pulse 3.012–3.018 s, drag 9.06 studs, trail 12 (11 placed), "too far" 0.801 s, orphans (known WalkSpeed 5.6) | within spread |
| Death / respawn | interrupted pulse; AK reload cancelled after the swap; respawn 3.28–3.40 s; a grenade thrown before death detonates once (4.0043 s) | within spread |
| AI | perception 14 / 14, aiming 8 / 8, firing 11 / 11, integration 10 / 10, player as target 7 / 7, 7 / 7, **5 / 7**, 7 / 7, bot shoots player 5 / 5, takedown 6 / 6, security 10 / 10 | the 5 / 7 is the known P2 timing flake (no "acquired" stamp, P3 measured from it); 7 / 7 before and after |
| M4AnimTest | 3.531–3.542 s (one 3.719 s during a death, one 5.117 s start hitch) | same pattern |
| GrenadeTest | fuse 4.0003–4.0043 s ×18, release 0.149–0.153 s, wall / lob / steep / room as before, forged refused, server-owned | within spread |
| Grenade among bodies | 39 / 40 fragments into bodies | within spread |
| GrenadeFidelity | presentation identical; `heldAtReleaseFrames` 7; label 1.402 / 0.195 s; red edge as before; security as before | same |

- **M4 Stressed:** known, unchanged; sway roll 2.924°, reload end pose 2.505° tactical / 2.268° empty.
- **Console:** 0 game-code errors. The warnings are the expected forged-request rejections. One server error,
  `AssistantCommand:7`, came from the agent's own call: a recorded recipe iterated `p.Samples`, which is now a count.

### Performance (Studio, same method as the first-person baseline)

| | Value |
|---|---|
| Client frame, on foot away / prompt shown / bench seat / driver seat | 4.16 / 4.18 / 4.28 / 4.23 ms (max 5.4 / 5.1 / 5.9 / 5.6) |
| The prompt's per-frame work (one ray + the offer rules) | 3.5 µs |
| Server heartbeat | 4.27 ms (max 7.0); physics 60 Hz |
| Truck | 232 instances, all anchored; no per-frame server work (events only) |
| Seated, client only | +8 camera parts (6 legs / lap arms, 2 driver arms), 2 ScreenGuis |
