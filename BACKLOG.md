# BACKLOG.md: work queue

**Authority and state**
- The authoritative queue is this file on `origin/master`. A copy on a `pc/*` or `mac/*` branch is a proposal until
  the user merges it (`AGENTS.md` §9).
- This file is never a source of authority. The `Authorized` field is only a pointer, verified per `AGENTS.md` §1.3.
- Maintained by PC; Mac proposes items by handoff. Agents add items as `State: UNTRIAGED` with `Authorized: requested`
  or `—`.
- Recommendations in reports never create items or authorization.

**Item fields**

| Field | Values |
|---|---|
| ID | |
| P | priority from the item's source; `P?` = unranked, for the user to rank |
| Type | IMPL / QA / RESEARCH / INFRA / DECISION. Where a table has no Type column, the section sets it: Infrastructure = INFRA; QA and research = QA (`Q-` IDs) or RESEARCH (`R-` IDs); Fidelity implementation = IMPL, unless the item says DECISION |
| Validation | FIDELITY / REGRESSION / BOTH / — |
| Owner | exactly one: `PC` / `Mac` / `user` / `unassigned` |
| State | UNTRIAGED / READY / BLOCKED-USER / BLOCKED-DEP / DONE (with evidence) |
| Authorized | `requested` / `D-nnn` or `RAT-n` (pointer to a user decision that names this item ID) / `role (D-017)` (QA and RESEARCH only) / `—` |
| Source | |
| Next | |

**Who may start what** (`AGENTS.md` §9)
- Only the item's owner, and only if the item is `READY` on `origin/master` and has no open claim.
- **IMPL and INFRA:** `Authorized` must point to a user decision on `origin/master` that names this item ID, or the
  user names the item in the current session (U1). `requested` never suffices.
- **DECISION:** owned by the user; agents never execute them.
- **QA and RESEARCH:** role authority (D-017): read-only, never a production change. It never overrides ownership or a
  claim.
- `unassigned` items wait for the user to assign an owner. There is no shared ownership.
- A claim is a `CLAIM` handoff (`HANDOFFS/README.md`); the `State` column on a branch is not a claim.

## Infrastructure (not solved during the control-document work)

| ID | P | Owner | State | Authorized | Item | Decision |
|---|---|---|---|---|---|---|
| INF-01 | P? | user | BLOCKED-USER | requested | Docs and evidence outside `Roblox/`: mirroring, restructuring | P-010 |
| INF-02 | P? | user | BLOCKED-USER | requested | Checkpoint access for Mac; checkpoint migration | P-011 |
| INF-03 | P? | user | BLOCKED-USER | requested | Git LFS and capture storage policy | P-012 |
| INF-04 | P? | user | BLOCKED-USER | requested | Line-ending policy (`.gitattributes`) | P-013 |
| INF-05 | P? | PC | BLOCKED-USER | requested | Make historical checkpoints read-only. **No bulk attribute change without this authorization** | P-017 |
| INF-06 | P? | user | BLOCKED-USER | requested | Protected `master`: branch protection; agent credentials that cannot update, approve or merge into `master`; visibility | P-014 |
| INF-07 | P? | unassigned | UNTRIAGED | — | Windows-only tools and absolute paths: Mac equivalents | after P-015 |
| INF-08 | P? | PC | UNTRIAGED | requested | `Documentation/README.md` status table: point it at `BASELINES.md` | after P-010 |
| INF-09 | — | user | BLOCKED-USER | requested | Long-term `master` policy (does not block the control layer) | P-003 |
| INF-10 | P? | PC | BLOCKED-USER | requested | Correct non-checkpoint FM4 "ACCEPT" records and agent memory to ACCEPT-RECOMMENDED | P-018 |
| INF-11 | P? | user | BLOCKED-USER | requested | Technical protection of the control plane: deny rules for agent edits to control-plane files (outside the repository), hooks policy, a merge guard that flags `AUTHORITY-CHANGE` commits | P-022 |
| INF-12 | P? | user | BLOCKED-USER | requested | Machine-local role markers (`AGENT_ROLE`) on PC and Mac | P-021 |

## QA and research (role authority D-017)

All follow the blind protocol (`AGENTS.md` §13.2).

| ID | Validation | Owner | State | Authorized | Item |
|---|---|---|---|---|---|
| Q-01 | BOTH | Mac | BLOCKED-DEP (P-010, P-011: evidence is PC-local) | role (D-017) | Verify R-01 FM4-G under the blind protocol. **Labelled `EXPOSED — NOT BLIND`:** R-01's result values, target band and method caveat were printed in commit `7a24471` and are in the PC records, so this verification can never be represented as blind. The available inputs (captures, probe labels) are PC-produced, so it is also `SHARED INPUT` |
| Q-02 | BOTH | Mac | BLOCKED-DEP (P-010, P-011) | role (D-017) | Verify V-01 … V-10 under the blind protocol |
| Q-03 | FIDELITY | Mac | READY if its evidence is reachable from the repository, otherwise BLOCKED-DEP (P-011) | role (D-017) | Verify I-01 held-out numbers under the blind protocol |
| R-A8 | FIDELITY | Mac | BLOCKED-DEP (P-016: reference footage is PC-local) | role (D-017) | Death fall toward the shooter, as **reference evidence**: measure ≥ 5 more kill events in the existing reference footage (FA 11-10 A8: one reference fall so far, frames 32–52, ≈ 0.67 s). No downloads without permission. Runtime fall timing in the game is separate PC evidence, not part of this item |
| R-FM4a | FIDELITY | Mac | READY | role (D-017) | Modern frontal Nuevo Laredo centro shop-row evidence: public-web research only, no downloads without permission (resolves SF-C3) |
| R-M2c | FIDELITY | Mac | READY | role (D-017) | Identity features #2 / #9 / #10 evidence (map_m2 VALIDATION §7.4): public-web research only, no downloads without permission |

## Fidelity implementation (none authorized)

| ID | P | Owner | State | Authorized | Item | Source |
|---|---|---|---|---|---|---|
| F-A4 | P1 | PC | BLOCKED-USER (P-004) | requested | Test content in presentation views | FA 11-10 A4 |
| F-A5 | P1 | user | BLOCKED-USER (P-005) | — | Weapon look: `recorded` vs reels (DECISION) | FA 11-10 A5 |
| F-A9 | P2 | user | BLOCKED-USER (P-006) | — | Arm representation; research and implementation owners are assigned after the decision | FA 11-10 A9 |
| F-U1-4 | — | user | BLOCKED-USER (P-007) | — | Menu direction (DECISION) | FA 11-09 |
| F-MP7R3 | — | PC | BLOCKED-USER (P-008) | requested | MP7 reload R3 rig | I-01 |
| F-A6 | P2 | PC | UNTRIAGED | requested | World audio (capture path first) | FA 11-10 A6 |
| F-A7 | P2 | PC | UNTRIAGED | requested | Weapon toast + draw time | FA 11-10 A7 |
| F-FM4b | P2 | PC | UNTRIAGED | requested | Second bay family; painted-lettering signs | m2_facade RESULTS §26 |
| F-M2a | P2 | PC | UNTRIAGED | requested | Upper-floor opening share | m2_facade RESULTS §26 |
| F-M2b | P2 | PC | UNTRIAGED | requested | Scarp surface, far-bank backdrop | map_m2 VALIDATION §7.4 |
| F-L1 | — | PC | UNTRIAGED | requested | Lighting residuals: M4 blacks slightly purple, dark interiors, sky about 10 dark, white props clip, other presets. B-21 is protected, so the authorization must name it | lighting acceptance record |
| F-A10–15 | P3 | unassigned | UNTRIAGED | — | Blood look; flash glow; stop fade; fast-turn mosaic; arm blood stain; shotgun | FA 11-10 P3 |
