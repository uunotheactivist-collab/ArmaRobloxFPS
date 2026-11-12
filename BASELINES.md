# BASELINES.md: status register

The register of every system's status (`AGENTS.md` §6). **It is not a source of authority.** A user-authority status
is valid only through the U2 record (`DECISIONS.md` §2 or §4) that the row cites, verified on `origin/master`
(`AGENTS.md` §1.3).

**Rules for this file**
- Read it from `origin/master`. A copy on any other branch is a proposal.
- Agents may set agent statuses (FOR REVIEW, ITERATE, PARTIAL, ACCEPT-RECOMMENDED, SUPERSEDED, NOT ADOPTED) and
  verdicts.
- A change to a user-authority or historical row is a proposal (`Status: PROPOSED <status>`, with a P-ID) until a U2
  record exists. Such commits carry `AUTHORITY-CHANGE` in the message.
- For items awaiting independent QA, this file gives status and a pointer only: no result values, target bands,
  method details or verdict text (`AGENTS.md` §13.2).
- `master` is the integration branch; its content is not a status.
- Checkpoints (`Scripts/Checkpoints/`, PC only) are evidence.
- **In place?** = present in the current `Place1.rbxl`. The 11-09 → 11-11 checkpoint chain is linear by place hash.
- Bootstrap: until the user merges this file to `origin/master`, it is a review draft (`AGENTS.md` §1.5).

Snapshot 2026-11-11; current place `7A3404F8…B0D1`.

**Ratification status:** no row in this file is backed by a ratified user acceptance under the current authority
model. Historical rows wait for RAT-1 (`DECISIONS.md` §4, P-019). Provenance classes (HIST-VERBATIM, HIST-RECORD,
HIST-MEMORY, HIST-AGENT) are defined in `DECISIONS.md` §3; none of them is user authority.

## A. Historically accepted (protected; ratification pending)

Protected exactly like FROZEN until the user ratifies, amends or rejects them (`AGENTS.md` §6).

| ID | Item | Checkpoint | Class | Evidence of acceptance | Protected scope |
|---|---|---|---|---|---|
| B-01 | `ReferenceAnalysis/REFERENCE_LIBRARY.md` | — | HIST-MEMORY | agent memory; `REFERENCE_GUIDE.md` "2026-11-06, accepted" (agent-written); D-003 | never modify |
| B-02 | Minimum ballistic slice | `2026-11-06_ballistics_slice` | HIST-RECORD | `Documentation/README.md` status table; D-004 | placeholder penetration values, damage; deflection not built |
| B-03 | Body hit + body state foundation | `2026-11-06_bodystate_cleanup` | HIST-RECORD | README; D-004 | `Config.BodyState.RuleStatus` labels |
| B-04 | Hit reactions + active ragdoll; fidelity pass | `2026-11-06_hitreactions`; `_hitreactions_fidelity` | HIST-RECORD | README; D-004 | |
| B-05 | Blood + impact effects | `2026-11-06_blood_impacts` | HIST-RECORD | README; D-004 | |
| B-06 | Body interaction | `2026-11-06_body_interaction` | HIST-RECORD | README; D-004 | |
| B-07 | Fragmentation grenade slice | `2026-11-06_grenade_slice` | HIST-RECORD | README; D-004 | |
| B-08 | AI / bot combat slice | `2026-11-06_ai_combat_slice` | HIST-RECORD | README; D-004 | |
| B-09 | AK weapon slice (final) | `2026-11-06_ak_final` | HIST-RECORD | README; D-004 | |
| B-10 | Production M4 steps 1–4 (firing, recoil, reloads, HUD) | chain before `2026-11-06_before_ak` | HIST-RECORD | `2026-11-06_before_ak` MANIFEST ("accepted M4 HUD milestone"); README; D-004 | all M4 behaviour (see B-19) |
| B-11 | Player movement + first-person presentation | `2026-11-07_player_movement_slice` | HIST-RECORD | README; D-004 | movement values; jump 7.2 studs (see protected elements) |
| B-12 | Scoped optics / weapon presentation | `2026-11-07_optics_slice` | HIST-RECORD | README; D-004 | |
| B-13 | MP7 weapon slice | `2026-11-07_mp7_slice` | HIST-RECORD | README; D-004 | |
| B-14 | Glock weapon slice | `2026-11-07_glock_slice` | HIST-RECORD | README; D-004 | accepted ADS weapon and arm poses (see protected elements) |
| B-15 | Sniper slice | `2026-11-08_sniper_slice` | HIST-RECORD | README; D-004. Its MANIFEST label "Awaiting review" is a capture-time label | |
| B-16 | Grenade fidelity slice | `2026-11-08_grenade_fidelity_slice` | HIST-RECORD | README; D-004. MANIFEST label "Awaiting review" | |
| B-17 | Global first-person fidelity pass | `2026-11-08_firstperson_fidelity_slice` | HIST-RECORD | README; D-004 | |
| B-18 | Truck / vehicle slice | `2026-11-08_truck_slice` | HIST-RECORD | README; D-004 | driving UNKNOWN, not built |
| B-19 | M4 model fidelity correction (current M4 baseline) | `2026-11-08_m4_model_fidelity_correction` | HIST-RECORD | README "accepted (2026-11-08)"; D-005. MANIFEST label "WIP" | no M4 geometry, pose, animation, gameplay, recoil, reload or presentation change without an authorization naming it |
| B-20 | M2-v3 structural baseline | `2026-11-11_m2_baseline_accepted` | HIST-VERBATIM | user: "Accept as baseline", recorded in the acceptance-record checkpoint; D-013 | S = 2.5 studs per reference metre; grid, blocks, landmarks, river / bridge / stairs, cover, sightlines, streaming; fingerprint `9602:3837419097:1438334365` |
| B-21 | M2 lighting C9 + viewmodel fill v3 (a pair) | `2026-11-11_m2_lighting_accepted` | HIST-VERBATIM | user: "Accept lighting", recorded in the acceptance-record checkpoint; D-015 | Lighting values; fill v3; `ViewmodelFill.luau` `6F5345B5…EE81`; `apply_lighting.luau` `7480B1D6…EED2` |

**Protected parameters and elements** (HISTORICALLY PROTECTED; ratification pending)

| Element | Class | Source |
|---|---|---|
| Global scale 0.28 m per stud (weapons, viewmodels, physics, vehicles, movement) | HIST-AGENT | `map_m1/DECISIONS.md` D1 (D-012) |
| Map scale S = 2.5 studs per reference metre | HIST-VERBATIM | inside B-20 |
| The avatar | HIST-AGENT | `map_m1/DECISIONS.md` D1 (D-012) |
| Test infrastructure stays in the saved place (SpawnLocation, Targets lane, M4AnimTest, test ranges) | HIST-AGENT | `map_m1/DECISIONS.md` D5 (D-012) |
| Jump 7.2 studs (PLACEHOLDER) | HIST-AGENT | `map_m1/DECISIONS.md` D3 (D-012) |
| Glock accepted ADS weapon and arm poses | HIST-RECORD | B-14; `2026-11-10_glock_ads_pose_restore` MANIFEST |

## B. ACCEPT-RECOMMENDED (awaiting the user)

| ID | Item | Checkpoint | In place? | Acceptance | Results (pointer) | Independent verification |
|---|---|---|---|---|---|---|
| R-01 | M2 FM4-G storefront bays, on top of FM3 (I-02) | `2026-11-11_m2_fm4_storefronts` | yes | `Acceptance: proposed` (P-001) | PC-local `Fidelity Audit 2026-11-10/m2_facade/RESULTS.md` Part II and `FM4_REGRESSION.md`. Values withheld here for blind QA | none; Q-01 is `EXPOSED — NOT BLIND` |

**R-01 notes**
- PC's results include a metric changed post-hoc; the details are in the PC results.
- An earlier version of this file (commit `7a24471`) printed R-01's result values and target band. Anyone who has read
  that commit is exposed (`AGENTS.md` §13.2).
- Not acceptance: the checkpoint title "ACCEPT"; RESULTS §29; the commit "Baseline M2 FM4".

## C. FOR REVIEW (no user decision; in the current place)

| ID | Item | Checkpoint | Independent verification |
|---|---|---|---|
| V-01 | M4 audio fidelity correction | `2026-11-09_m4_audio_fidelity_correction` | none recorded |
| V-02 | AK audio fidelity | `2026-11-09_ak_audio_fidelity` | none recorded |
| V-03 | MP7 audio fidelity | `2026-11-09_mp7_audio_fidelity` | none recorded |
| V-04 | Glock audio fidelity correction | `2026-11-09_glock_audio_fidelity_correction` | none recorded |
| V-05 | MP7 model fidelity correction | `2026-11-09_mp7_model_fidelity_correction` | none recorded |
| V-06 | Glock model fidelity | `2026-11-09_glock_model_fidelity` | none recorded |
| V-07 | Glock ADS-pose restore (restores the protected Glock poses) | `2026-11-10_glock_ads_pose_restore` | none recorded |
| V-08 | Glock reticle alignment | `2026-11-10_glock_reticle_alignment` | none recorded |
| V-09 | Glock aim-hold drift | `2026-11-10_glock_aim_drift` | none recorded |
| V-10 | Glock aimed-shot recoil | `2026-11-10_glock_aimed_recoil` | none recorded |

## D. ITERATE / PARTIAL

| ID | Item | Checkpoint(s) | State |
|---|---|---|---|
| I-01 | MP7 reload animation | `2026-11-10_mp7_reload_animation` → `_r3_600` → `_arm_magazine` → `_gaps` → `_followup` | ITERATE. The R3 swing waits on a rig decision (P-008). In place |
| I-02 | M2 FM3 facade / material pass | `2026-11-11_m2_facade_material_fm3` | ITERATE. Base under R-01. In place |
| I-03 | M2 items outside B-20 / B-21 | — | scarp, far-bank backdrop, identity features #2 / #9 / #10, draw calls |

## E. Superseded, not adopted, retired

**Agent statuses** (unaccepted candidates)

| Item | Checkpoint | Now |
|---|---|---|
| M4 audio slice | `2026-11-08_m4_audio_fidelity` | SUPERSEDED by V-01 |
| Glock audio slice | `2026-11-09_glock_audio_fidelity` | SUPERSEDED by V-04 |
| MP7 model fidelity (lower body) | `2026-11-09_mp7_model_fidelity` | SUPERSEDED by V-05 |
| M4 model fidelity slice | `2026-11-08_m4_model_fidelity_slice` | SUPERSEDED by B-19 |
| Lighting correction 2026-11-09 | `2026-11-09_lighting_correction` | SUPERSEDED (values replaced by A3, then C9) |
| A3 lighting | `2026-11-10_a3_lighting` | SUPERSEDED by B-21 |
| Fill v1 / v2 | `2026-11-10_viewmodel_fill`, `_v2`, `_v2_testfix` | SUPERSEDED by fill v3. The test's fill-off behaviour stays (D-010) |
| M2-v2 | `2026-11-10_m2_nuevo_laredo_v2` | SUPERSEDED by v3 |
| Lighting C8 | `2026-11-11_m2_lighting_c8_iterate` | never applied |
| MP7 two-part arm prototype | — | NOT ADOPTED |

**Historically retired** (RETIRED is a user-authority status; these rows are historical, ratification pending)

| Item | Checkpoint | Class | Now |
|---|---|---|---|
| A1 arena | `2026-11-10_a1_arena` | HIST-AGENT (under the map-target decision D-009) | HISTORICALLY RETIRED (`ServerStorage.PresentationArena_A1`) |
| M1 map | `2026-11-10_map_m1` | HIST-AGENT (replaced by M2) | HISTORICALLY RETIRED (`ServerStorage.PresentationMap_M1`) |

## F. Out of scope

| Item | Status | Source |
|---|---|---|
| Bodycam presentation (overlay, vignette, stamp, REC, camera look) | OUT OF SCOPE | D-018 (user decision; U2 once on `origin/master`); historical D-008 |

## G. UNRESOLVED (not accepted; protected: changes need an authorization naming them, `AGENTS.md` §10)

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
