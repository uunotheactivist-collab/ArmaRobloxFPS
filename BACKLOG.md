# BACKLOG.md: work queue

Maintained by PC; Mac proposes items by handoff.

**Item fields**

| Field | Values |
|---|---|
| ID | |
| P | priority from the item's source; `P?` = unranked, for the user to rank |
| Type | IMPL / QA / RESEARCH / INFRA / DECISION |
| Validation | FIDELITY / REGRESSION / BOTH / — |
| Owner | PC / Mac / either / user |
| State | UNTRIAGED / READY / BLOCKED-USER / BLOCKED-DEP / IN-PROGRESS (`<role>`, `<branch>`) / DONE (with evidence) |
| Authorized | user `<date>` / standing / pending |
| Source | |
| Next | |

**Who may pick what**
- IMPL and INFRA items need `Authorized: user <date>`. They are never self-selected.
- QA and RESEARCH items marked `standing` may be self-selected.
- Recommendations in reports do not create authorization.

## Infrastructure (not solved during the control-document installation)

| ID | P | Owner | State | Authorized | Item | Decision |
|---|---|---|---|---|---|---|
| INF-01 | P? | user → PC | BLOCKED-USER | pending | Docs and evidence outside `Roblox/`: mirroring, restructuring | P-010 |
| INF-02 | P? | user → PC | BLOCKED-USER | pending | Checkpoint access for Mac; checkpoint migration | P-011 |
| INF-03 | P? | user → PC | BLOCKED-USER | pending | Git LFS and capture storage policy | P-012 |
| INF-04 | P? | user → PC | BLOCKED-USER | pending | Line-ending policy (`.gitattributes`) | P-013 |
| INF-05 | P? | PC | BLOCKED-USER | pending | Make historical checkpoints read-only. **No bulk attribute change without this authorization** | P-017 |
| INF-06 | P? | user | BLOCKED-USER | pending | GitHub visibility; branch protection on `master` | P-014 |
| INF-07 | P? | either | UNTRIAGED | — | Windows-only tools and absolute paths: Mac equivalents | after P-015 |
| INF-08 | P? | PC | UNTRIAGED | pending | `Documentation/README.md` status table: point it at `BASELINES.md` | after P-010 |
| INF-09 | — | user | BLOCKED-USER | pending | Long-term `master` policy (does not block installation) | P-003 |
| INF-10 | P? | PC | BLOCKED-USER | pending | Correct non-checkpoint FM4 "ACCEPT" records and agent memory to ACCEPT-RECOMMENDED | P-018 |

## QA and research (standing authorization)

| ID | Validation | Owner | State | Item |
|---|---|---|---|---|
| Q-01 | BOTH | Mac | READY (when evidence is accessible) | Verify R-01 FM4-G independently, including re-deriving an opening-share metric defined before looking at FM4 results |
| Q-02 | BOTH | Mac | READY (when evidence is accessible) | Verify V-01 … V-10 |
| Q-03 | FIDELITY | Mac | READY | Verify I-01 held-out numbers |
| R-A8 | FIDELITY | Mac | READY | Death fall toward the shooter: measure ≥ 5 more kills (FA 11-10 A8) |
| R-FM4a | FIDELITY | Mac | READY | Modern frontal Nuevo Laredo centro shop-row evidence: public-web research only, no downloads without permission (resolves SF-C3) |
| R-M2c | FIDELITY | Mac | READY | Identity features #2 / #9 / #10 evidence (map_m2 VALIDATION §7.4) |

## Fidelity implementation (not authorized)

| ID | P | Owner | State | Item | Source |
|---|---|---|---|---|---|
| F-A4 | P1 | PC | BLOCKED-USER (P-004) | Test content in presentation views | FA 11-10 A4 |
| F-A5 | P1 | user | BLOCKED-USER (P-005) | Weapon look: `recorded` vs reels | FA 11-10 A5 |
| F-A9 | P2 | Mac → PC | BLOCKED-USER (P-006) | Arm representation | FA 11-10 A9 |
| F-U1-4 | — | user | BLOCKED-USER (P-007) | Menu direction | FA 11-09 |
| F-MP7R3 | — | PC | BLOCKED-USER (P-008) | MP7 reload R3 rig | I-01 |
| F-A6 | P2 | PC | UNTRIAGED | World audio (capture path first) | FA 11-10 A6 |
| F-A7 | P2 | PC | UNTRIAGED | Weapon toast + draw time | FA 11-10 A7 |
| F-FM4b | P2 | PC | UNTRIAGED | Second bay family; painted-lettering signs | m2_facade RESULTS §26 |
| F-M2a | P2 | PC | UNTRIAGED | Upper-floor opening share | m2_facade RESULTS §26 |
| F-M2b | P2 | PC | UNTRIAGED | Scarp surface, far-bank backdrop | map_m2 VALIDATION §7.4 |
| F-L1 | — | PC | UNTRIAGED | Lighting residuals: M4 blacks slightly purple, dark interiors, sky about 10 dark, white props clip, other presets. B-21 is FROZEN, so this needs a brief | lighting acceptance record |
| F-A10–15 | P3 | — | UNTRIAGED | Blood look; flash glow; stop fade; fast-turn mosaic; arm blood stain; shotgun | FA 11-10 P3 |
