# BASELINES.md: status registry

The single place to look up whether something is accepted, frozen, under review or unresolved (`AGENTS.md` §3).

**Rules for this file**
- User-only statuses (ACCEPTED, FROZEN, DEFER, OUT OF SCOPE) change only on a user decision recorded in
  `DECISIONS.md`.
- Agent verdicts are recorded as evidence.
- `master` is the integration branch; its content is not a status.
- Checkpoints live under `Scripts/Checkpoints/` (PC only).
- **In place?** = present in the current `Place1.rbxl`. The 11-09 → 11-11 checkpoint chain is linear by place hash.

Snapshot 2026-11-11; current place `7A3404F8…B0D1`.

## A. ACCEPTED (user) → FROZEN

| ID | Item | Accepted-state checkpoint | Acceptance source | Frozen / protected scope |
|---|---|---|---|---|
| B-01 | `ReferenceAnalysis/REFERENCE_LIBRARY.md` | — | user, 2026-11-06 (wording not recorded) | never modify |
| B-02 | Minimum ballistic slice | `2026-11-06_ballistics_slice` | README status table (wording not recorded) | placeholder penetration values, damage; deflection not built |
| B-03 | Body hit + body state foundation | `2026-11-06_bodystate_cleanup` | README | `Config.BodyState.RuleStatus` labels |
| B-04 | Hit reactions + active ragdoll; fidelity pass | `2026-11-06_hitreactions`; `_hitreactions_fidelity` | README | |
| B-05 | Blood + impact effects | `2026-11-06_blood_impacts` | README | |
| B-06 | Body interaction | `2026-11-06_body_interaction` | README | |
| B-07 | Fragmentation grenade slice | `2026-11-06_grenade_slice` | README | |
| B-08 | AI / bot combat slice | `2026-11-06_ai_combat_slice` | README | |
| B-09 | AK weapon slice (final) | `2026-11-06_ak_final` | README | |
| B-10 | Production M4 steps 1–4 (firing, recoil, reloads, HUD) | chain before `2026-11-06_before_ak` | `2026-11-06_before_ak` MANIFEST ("accepted M4 HUD milestone"), README | all M4 behaviour (see B-19) |
| B-11 | Player movement + first-person presentation | `2026-11-07_player_movement_slice` | README | jump 7.2 studs (PLACEHOLDER, protected: `map_m1/DECISIONS.md` D3) |
| B-12 | Scoped optics / weapon presentation | `2026-11-07_optics_slice` | README | |
| B-13 | MP7 weapon slice | `2026-11-07_mp7_slice` | README | |
| B-14 | Glock weapon slice | `2026-11-07_glock_slice` | README | **PROTECTED:** accepted ADS weapon and arm poses |
| B-15 | Sniper slice | `2026-11-08_sniper_slice` | README; its MANIFEST label "Awaiting review" is a capture-time label | |
| B-16 | Grenade fidelity slice | `2026-11-08_grenade_fidelity_slice` | README; MANIFEST label "Awaiting review" | |
| B-17 | Global first-person fidelity pass | `2026-11-08_firstperson_fidelity_slice` | README | |
| B-18 | Truck / vehicle slice | `2026-11-08_truck_slice` | README | driving UNKNOWN, not built |
| B-19 | M4 model fidelity correction (current M4 baseline) | `2026-11-08_m4_model_fidelity_correction` | README "accepted (2026-11-08)"; MANIFEST label "WIP" | no M4 geometry, pose, animation, gameplay, recoil, reload or presentation change without a new brief |
| B-20 | M2-v3 structural baseline | `2026-11-11_m2_baseline_accepted` | user: "Accept as baseline" | S = 2.5 studs per reference metre; grid, blocks, landmarks, river / bridge / stairs, cover, sightlines, streaming; fingerprint `9602:3837419097:1438334365` |
| B-21 | M2 lighting C9 + viewmodel fill v3 (a pair) | `2026-11-11_m2_lighting_accepted` | user: "Accept lighting" | Lighting values; fill v3; `ViewmodelFill.luau` `6F5345B5…EE81`; `apply_lighting.luau` `7480B1D6…EED2` |

**Project-wide protected parameters** (`map_m1/DECISIONS.md` D1, D5):
- global scale 0.28 m per stud;
- the avatar;
- test infrastructure stays in the saved place.

## B. ACCEPT-RECOMMENDED (awaiting the user)

| ID | Item | Checkpoint | In place? | Agent verdicts (evidence only) | Independent verification |
|---|---|---|---|---|---|
| R-01 | M2 FM4-G storefront bays, on top of FM3 (I-02) | `2026-11-11_m2_fm4_storefronts` | yes | **Fidelity:** CLOSER. Geometric opening share 0.253 → 0.588; image share, tuning 0.195 → 0.627, held-out 0.063 → 0.599. **Regression:** PASS (`FM4_REGRESSION.md` §G). Performance: scoped GPU +0.24–0.33 ms. Method caveats below | none (Q-01) |

**R-01 caveats**
- The SF2 image-share metric was introduced after the FM4-A / B results, because SF v1 counted side walls. It is
  `METRIC CHANGED POST-HOC` and is **not** independent validation.
- The target was revised during the task (0.60–0.68 → 0.40–0.70) from documented reference evidence.
- Held-out views are independent of view-level tuning but not of the global-share target.
- Not acceptance:
  - the checkpoint title "ACCEPT";
  - RESULTS §29;
  - the commit "Baseline M2 FM4".

## C. FOR REVIEW (no user decision; in the current place)

| ID | Item | Checkpoint | Independent verification |
|---|---|---|---|
| V-01 | M4 audio fidelity correction | `2026-11-09_m4_audio_fidelity_correction` | none recorded |
| V-02 | AK audio fidelity | `2026-11-09_ak_audio_fidelity` | none recorded |
| V-03 | MP7 audio fidelity | `2026-11-09_mp7_audio_fidelity` | none recorded |
| V-04 | Glock audio fidelity correction | `2026-11-09_glock_audio_fidelity_correction` | none recorded |
| V-05 | MP7 model fidelity correction | `2026-11-09_mp7_model_fidelity_correction` | none recorded |
| V-06 | Glock model fidelity | `2026-11-09_glock_model_fidelity` | none recorded |
| V-07 | Glock ADS-pose restore (restores B-14's protected poses) | `2026-11-10_glock_ads_pose_restore` | none recorded |
| V-08 | Glock reticle alignment | `2026-11-10_glock_reticle_alignment` | none recorded |
| V-09 | Glock aim-hold drift | `2026-11-10_glock_aim_drift` | none recorded |
| V-10 | Glock aimed-shot recoil | `2026-11-10_glock_aimed_recoil` | none recorded |

## D. ITERATE / PARTIAL

| ID | Item | Checkpoint(s) | State |
|---|---|---|---|
| I-01 | MP7 reload animation | `2026-11-10_mp7_reload_animation` → `_r3_600` → `_arm_magazine` → `_gaps` → `_followup` | ITERATE. The R3 swing waits on a rig decision (P-008). In place |
| I-02 | M2 FM3 facade / material pass | `2026-11-11_m2_facade_material_fm3` | ITERATE. Base under R-01. In place |
| I-03 | M2 items outside B-20 / B-21 | — | scarp, far-bank backdrop, identity features #2 / #9 / #10, draw calls |

## E. SUPERSEDED / RETIRED / NOT ADOPTED

| Item | Checkpoint | Now |
|---|---|---|
| M4 audio slice | `2026-11-08_m4_audio_fidelity` | superseded by V-01 |
| Glock audio slice | `2026-11-09_glock_audio_fidelity` | superseded by V-04 |
| MP7 model fidelity (lower body) | `2026-11-09_mp7_model_fidelity` | superseded by V-05 |
| M4 model fidelity slice | `2026-11-08_m4_model_fidelity_slice` | superseded by B-19 |
| Lighting correction 2026-11-09 | `2026-11-09_lighting_correction` | values replaced (A3, then C9) |
| A1 arena | `2026-11-10_a1_arena` | RETIRED (`ServerStorage.PresentationArena_A1`) |
| M1 map | `2026-11-10_map_m1` | RETIRED (`ServerStorage.PresentationMap_M1`) |
| A3 lighting | `2026-11-10_a3_lighting` | superseded by B-21 |
| Fill v1 / v2 | `2026-11-10_viewmodel_fill`, `_v2`, `_v2_testfix` | superseded by fill v3. The test's fill-off behaviour stays (D-010) |
| M2-v2 | `2026-11-10_m2_nuevo_laredo_v2` | superseded by v3 |
| Lighting C8 | `2026-11-11_m2_lighting_c8_iterate` | never applied |
| MP7 two-part arm prototype | — | NOT ADOPTED |

## F. OUT OF SCOPE (permanent)

| Item | Source |
|---|---|
| Bodycam presentation (overlay, vignette, stamp, REC, camera look) | user, D-008 |

## G. UNRESOLVED

| Item | Note |
|---|---|
| Foundation test (test blaster etc.) | README: "working, preserved" |
| `ReferenceLibrary/` (Arma + Nuevo Laredo layer) | in use since 2026-11-10; acceptance not recorded |
| Blender → FBX → Roblox pipeline | proven locally; Roblox importer untested |
| Menu / UI direction | P-007 |

## Current-state hashes

| Check | Value |
|---|---|
| Place | `7A3404F81DBFD886004A435503742176B08BCE2D4950F27FF9845869D8B0B0D1` (989,173 B) |
| Scripts manifest (157 files) | `B61FAF74…1D61` |
| FM4 geometry | `3290:2122412297` |
| M2 structure after FM4 rollback | `9602:3837419097:1438334365` |
| Remotes | 14 |
