# Handoffs between PC and Mac

A handoff is a request, report or proposal. **It is never authorization.** Only the user authorizes production work
(`AGENTS.md` §0, §6).

## Files and branches

- **File:** `HANDOFFS/<yyyy-mm-dd>_<HID>_<from>-to-<to>_<slug>.md`, where HID = `H-PC-nnn` or `H-MAC-nnn`.
- **Where:** the sender commits it on its own branch (`pc/*` or `mac/*`) and pushes. The receiver reads it with
  `git fetch origin` and `git show origin/<branch>:HANDOFFS/<file>`.
- **Replies:** a new file on the receiver's own branch. Never edit the other agent's files. There is no shared index
  file.

## Types

| Type | Use |
|---|---|
| `REQUEST-QA` | verify a candidate or claim |
| `REQUEST-RESEARCH` | find or measure evidence |
| `RESULT` | answer to a request |
| `PROPOSAL` | Mac → PC: a proposed `BACKLOG`, `DECISIONS` (pending), `PROJECT_STATE` or `BASELINES` candidate entry |
| `BLOCKER` | cannot proceed |
| `ESCALATION` | needs the user, including material PC / Mac disagreements |
| `PLACE-LOCK` | RELEASE or RETURN of the single-writer lock. Exceptional; needs `Authorized-by: user` (`AGENTS.md` §12) |
| `INFO` | anything else, including Mac's first capability report |

## Header

```
HID: H-PC-007     Type: REQUEST-QA     Status: OPEN | ACK | DONE | REJECTED | SUPERSEDED
From: PC   To: Mac     Date: yyyy-mm-dd     Replies-to: <HID or none>
Branch/commit: pc/yyyy-mm-dd-slug @ <sha>
Authorized-by: user "<quoted words>" (date) | none
Baseline refs: <BASELINES IDs>
Validation: FIDELITY | REGRESSION | BOTH
```

## Body

1. **Ask:** what "done" looks like.
2. **Claims:** numbered. Each gives:
   - the value;
   - the method, with tool path and hash;
   - when the method was defined: before results, or `METRIC CHANGED POST-HOC`;
   - the evidence path and SHA-256;
   - tuning or held-out.
3. **Constraints:** FROZEN, PROTECTED or ACCEPT-RECOMMENDED items in reach; what not to touch.
4. **Evidence attached:** small JSON, label maps, summary sheets. PC-only artifacts are listed by path and hash.
5. **Reply:** each claim is marked one of:
   - `VERIFIED` (own method, own numbers);
   - `NOT REPRODUCED` (own numbers);
   - `NOT VERIFIABLE` (why: missing evidence or tooling);
   - `DISAGREE-MATERIAL` (the verdict changes; both methods and results attached, plus an `ESCALATION`).
   Fidelity and regression are answered separately.

## Lifecycle

- `OPEN` → the receiver writes `ACK` → `DONE` or `REJECTED` (with reason).
- `SUPERSEDED` when the sender replaces a handoff.
- Each agent checks for open handoffs addressed to its role at the start of every session.
- Neither agent settles a material disagreement; the user does.
