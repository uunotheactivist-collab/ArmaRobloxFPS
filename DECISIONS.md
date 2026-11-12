# DECISIONS.md: decision log

**Rules**
- Resolved entries carry the user's words where recorded, or name the brief that set them.
- PC appends pending entries, including Mac's proposals. Only the user resolves them.
- Entries are never rewritten; a new entry supersedes an old one.

## Resolved

| ID | Date | Decision | By | Source |
|---|---|---|---|---|
| D-001 | 2026-11-05 → | No uploading or publishing; local-only content | user (every brief) | memory, README |
| D-002 | 2026-11-06 | Footage first: measure before building; mark what can't be measured; inferences stay marked | user | memory, analyses |
| D-003 | 2026-11-06 | `REFERENCE_LIBRARY.md` accepted; do not modify | user | memory, `REFERENCE_GUIDE.md` |
| D-004 | 2026-11-06 → 08 | Slices B-02 … B-18 accepted | user (wording not recorded) | README |
| D-005 | 2026-11-08 | M4 model fidelity correction accepted; no M4 change without a new brief | user | README |
| D-006 | 2026-11-08 → 09 | Weapon audio as local Studio content | user | memory |
| D-007 | 2026-11-09 | Audio Volume stays 0.1 | user | memory |
| D-008 | 2026-11-10 | Bodycam permanently out of scope | user | FA 11-10 backlog |
| D-009 | 2026-11-10 | Map target: YouTube `cM2D-CniPXI`; A1 provisional | user | FA 11-10 backlog |
| D-010 | 2026-11-10 | `M4ModelFidelityTest` switches the fill off for its colour check | user | FA 11-10 backlog |
| D-011 | 2026-11-10 | Arma = presentation, Nuevo Laredo = geography / architecture; accepted systems keep clip truth; ARMA-DIVERGENCE | brief | `ReferenceLibrary/README.md` |
| D-012 | 2026-11-10 | M1 decisions D1–D5. D1 (S = 2.5) was later accepted inside B-20; D2–D5 ratification UNKNOWN | agent under brief | `map_m1/DECISIONS.md` |
| D-013 | 2026-11-11 | M2-v3 is the structural baseline | user: "Accept as baseline" | `2026-11-11_m2_baseline_accepted` |
| D-014 | 2026-11-11 | Re-fit the fill | user: "Re-fit the fill" | m2_lighting RESULTS |
| D-015 | 2026-11-11 | C9 + fill v3 accepted as a pair | user: "Accept lighting" | `2026-11-11_m2_lighting_accepted` |
| D-016 | 2026-11-11 | Standing brief rules (see below) | user briefs | FM / FM4 briefs |
| D-017 | 2026-11-11 | Agent structure and authority (see below) | user | agent-infrastructure decisions |
| D-018 | 2026-11-11 | Validation and evidence rules (see below) | user | revision decisions |

**D-016: standing brief rules**
- Never edit checkpoints.
- Keep reference facts apart from implementation facts.
- No lighting changes to compensate.
- Downloads need permission.
- Privacy-preserving cookie choices.
- No personal details in external requests.
- Read the console before stopping Play; leave Studio in Edit, saved.

**D-017: agent structure and authority**
- `Roblox/` is the shared root; `AGENTS.md` is the contract and `CLAUDE.md` imports it.
- PC is the Production / Build / Integration machine and the default single writer of `Place1.rbxl`.
- Mac is the QA / Research / Audit machine: read-only on production; writes QA, research and handoffs. A place-lock
  transfer to Mac is exceptional and needs explicit authorization.
- Only the user declares ACCEPTED, FROZEN, DEFER or OUT OF SCOPE. FM4-G stays ACCEPT-RECOMMENDED.
- Git: PC pushes `pc/*`, Mac pushes `mac/*`. No merges to `master`, no force-push, no history rewrite. The user
  controls integration.
- `master` is the controlled integration / current-project branch. It is not acceptance and is not rebuilt.
- Checkpoints are immutable. No bulk attribute changes to historical checkpoints without an authorized task.
- Infrastructure (LFS, capture storage, checkpoint migration, restructuring, evidence mirroring) is deferred to
  explicit INF tasks.

**D-018: validation and evidence rules**
- The source-of-truth hierarchy as written in `AGENTS.md` §2.
- The mandatory workflow, with pre- and post-change checkpoints and performance / security validation.
- Anti-self-validation: methods and bands are defined before comparison; post-hoc metric changes are labelled and
  don't count as independent; tuning and held-out stay separate.
- Fidelity validation and regression validation are separate questions.
- Independent cross-machine verification; material disagreements go to the user.
- Public-web research is allowed; downloads need permission; never upload or publish; never send personal information.
- Recommendations are not authorization.
- Bodycam permanently out of scope.

## Pending (user decision required)

**Status decisions**

| ID | Question | Blocks |
|---|---|---|
| P-001 | Accept FM4-G (R-01)? Does that include FM3 (I-02)? | R-01, I-02 |
| P-002 | V-01 … V-10: accept, iterate or revert each | work on those weapons |
| P-003 | Long-term `master` policy (for example, merge only accepted work). **Does not block installation** | INF-09 |

**Product decisions**

| ID | Question | Blocks |
|---|---|---|
| P-004 | Test content: a presentation toggle or a separate test place | F-A4 |
| P-005 | Weapon look: `recorded` or the reels | F-A5 |
| P-006 | Arm representation / rig change | F-A9 |
| P-007 | Menu direction (U1–U4) | F-U1-4 |
| P-008 | MP7 reload R3 rig decision | F-MP7R3 |
| P-009 | Are A3's pending items (scope-lens lighting, flash contrast) still relevant under C9? | — |

**Infrastructure decisions**

| ID | Question | Blocks |
|---|---|---|
| P-010 | Docs and evidence outside `Roblox/`: mirror or restructure? | INF-01 |
| P-011 | Checkpoint access for Mac; migration | INF-02 |
| P-012 | Git LFS and capture storage | INF-03 |
| P-013 | Line-ending policy | INF-04 |
| P-014 | GitHub visibility; branch protection | INF-06 |
| P-015 | Mac capabilities: Studio / MCP; may it run Play tests on a copy? | Mac QA scope |
| P-016 | How the Mac gets reference footage | Mac research |
| P-017 | Authorize the historical-checkpoint immutability task | INF-05 |
| P-018 | Correct the FM4 "ACCEPT" records outside checkpoints, and agent memory | INF-10 |
