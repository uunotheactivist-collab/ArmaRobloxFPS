# PROJECT_STATE.md: current working state

Maintained by PC; Mac proposes changes by handoff. This file is evidence, not authority: statuses are in
`BASELINES.md` and authority is in `DECISIONS.md` §2 and §4 (`AGENTS.md` §1). Snapshot 2026-11-11.

## Control layer

| Item | State |
|---|---|
| Control documents | on the review branch `pc/2026-11-11-agent-control-layer` (local; not pushed when this snapshot was written). Not on `origin/master` |
| Authoritative control plane | none yet: `origin/master` (`22cbe21`) contains no control documents (`AGENTS.md` §1.5) |
| User-authority records on `origin/master` | none |
| Historical ratification (RAT-1) | not performed (P-019) |
| Role markers | no `AGENT_ROLE` in the PC user or machine environment (checked 2026-11-11); Mac UNKNOWN (INF-12) |
| Autonomous operation | not permitted: bootstrap merge, INF-06, INF-11, INF-12 and P-020 outstanding (`AGENTS.md` §22) |

## Repository and machines

| Item | State |
|---|---|
| Shared root | `Roblox/` (Git) |
| Remote | `github.com/uunotheactivist-collab/ArmaRobloxFPS`. Visibility UNKNOWN |
| `master` | **controlled integration / current-project branch.** One commit, `22cbe21` "Baseline M2 FM4" (the user, 2026-11-11). It holds the current place, so it mixes historically accepted, recommended and unaccepted work. Its content is not a status. Long-term policy: P-003 |
| Agent branches | `pc/2026-11-11-agent-control-layer` (control-layer review branch; see above) |
| Tracked size | ≈ 1.3 GB, mostly PNG; Git LFS installed but unused; no `.gitattributes`. Not to be changed during the control-layer work (INF-03, INF-04) |
| Line endings | PC `core.autocrlf=true`. 47 files CRLF + 2 mixed in the working tree. All 157 `Scripts/src` files are LF. Integrity checks compare Git objects, not file bytes (`AGENTS.md` §3) |
| Outside Git (PC only) | in the PC project folder next to `Roblox/`: `Documentation/`, `Fidelity Audit 2026-11-09/` (44 MB), `Fidelity Audit 2026-11-10/` (3.4 GB), `Lighting Correction 2026-11-09/` (961 MB), `ReferenceAnalysis/` (1.4 GB), `ReferenceLibrary/`, `Reference/`, `Blender/`; plus `Scripts/Checkpoints/` (103 checkpoints, 797 MB; about 85 still writable). Not to be changed during the control-layer work (INF-01, INF-02, INF-05) |
| PC | Windows 11, Roblox Studio + MCP. Studio version UNKNOWN (auto-updates) |
| Mac | UNKNOWN: OS version, agent runtime, Studio / MCP, evidence and footage access (P-015, P-016) |

## Place contents

**In the place**
- Historically accepted B-02 … B-19.
- FOR REVIEW V-01 … V-10.
- I-01; B-20 + B-21; I-02 + R-01.
- `Workspace` test folders and SpawnLocation.

**In ServerStorage:** `FM4_Holder` (797 stashed parts, used by rollback), the retired A1 and M1.

**Scripts:** 157; remotes 14. Not published; no uploaded assets.

## Verification queue

The QA items are in `BACKLOG.md` (Q-01 … Q-03), with owners and states there.
- Q-01 is permanently labelled `EXPOSED — NOT BLIND`.
- Mac's access to the PC-local evidence is UNKNOWN (P-010, P-011).

## Engine and tool facts (implementation facts; MEASURED unless marked)

**Rendering under C9**
- Asphalt renders about 2× Plaster at the same Color.
- CorrodedMetal ignores Color.
- Vivid paint needs base saturation ≥ 0.70.

**Lighting**
- Roblox sun z = sin(latitude − 23.44°).
- ClockTime is stored to whole seconds.

**Optics**
- The scope mirror skips parts with `OpticMirrorIgnore`.
- The residual scoped cost comes from the lens view itself, not from copy count.

**Gameplay geometry**
- Wall blood splats sit about 0.05 off the hit surface.
- Thin solid panels let grenades tunnel; hollow covers trap them. Use full-depth solid blocks.

**Studio MCP and logging**
- Long `execute_luau` calls drop their reply.
- `execute_luau` has its own require cache.
- Studio log lines truncate near 1,000 characters.
- No HTTP to localhost from `execute_luau`.

**Studio upkeep and tools**
- Studio updates remove the local reference sounds.
- `save_place.ps1` prints a wrong "before" time and size; its hash is correct.
- PowerShell gotchas: the `R` alias, case-insensitive variables, a backtick-a in a string is BEL.
- Old suites need `allowClientTeleports`.

## Records that are evidence only (never status or authority)

- `Documentation/README.md` status table (stops at 2026-11-09).
- MANIFEST titles of B-15, B-16, B-19.
- Acceptance-record checkpoints (`*_accepted`).
- FM4 "ACCEPT" wording in:
  - the checkpoint MANIFEST;
  - `m2_facade/RESULTS.md` §29;
  - `ReferenceLibrary/REQUIREMENTS_MATRIX.md`;
  - session notes;
  - agent memory.
  Correcting these is INF-10.

## UNKNOWN

- Studio version.
- The Mac environment.
- GitHub visibility and branch protection.
- The user's wording for B-01 … B-19.
- Mac access to evidence and footage.
