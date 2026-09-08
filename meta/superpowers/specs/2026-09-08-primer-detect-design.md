# Design — `primer-detect.sh`/`.jq` (Determinism Phase 6, sub-project A)

**Issue:** #43 (Determinism Phase 6 — `primer` detect, migrate, init, drift)

## Context

Phase 6's original scoping (`meta/superpowers/specs/2026-09-02-determinism-program-design.md`)
predates the GitHub Issues migration (2026-09-07), which added a fourth
migration step (`commands/primer.md` Step 3d, BACKLOG.md → GitHub Issues)
never mentioned in that entry. Re-reading `commands/primer.md` (372 lines,
8 steps) end to end found the phase decomposes into five independent
pieces, each mechanical-plus-judgment in different ratios:

| Step | Frequency | Mechanical seam | Judgment that stays prose |
|---|---|---|---|
| 1 Detect state | every invocation | ~9 fact checks → dispatch decision | none |
| 2 Init mode | once per repo | placeholder derivation | ground rules, escalation steps |
| 3/3b Split modes | near-zero (pre-v0.13/v0.22) | section-name lookup, title extraction | overflow routing, unknown sections |
| 3c/3d Migrations | near-zero (pre-v0.29), destructive | `git mv`/`git rm` + rewrites | hex-tag-to-repo mapping |
| 4 Refresh mode | every drift-detected invocation | test-count majority-vote rerun | candidate-close judgment |

This spec covers **only sub-project A: Step 1's detect/dispatch logic** —
the highest-frequency, zero-judgment piece. Sub-projects B (Step 4's
test-count rerun), C (3c+3d migrations), and D (Step 2's placeholder
derivation) are each their own future spec/plan cycle, not in scope here.

## Problem

Step 1 today gathers ~9 raw facts in one bash call (already scripted),
then leaves the model to mentally evaluate a 4-state classification plus
three migration triggers with an explicit sequencing rule ("if the primer
is *also* unsplit, run Step 3 to completion first, then Step 3b"). This
nested nested-conditional is exactly the class of logic Phase 4 and Phase
5 already found models get wrong silently when done by hand per
invocation, and this phase's own issue names it as the program's highest
blast radius (some of the triggered steps run `git mv`/`git rm`).

## Architecture

```
primer-detect.sh (I/O)              primer-detect.jq (pure decision)
  - file-existence checks    -->      - extract primer's recorded
  - git remote get-url                  git-log block from content,
  - git log --oneline -5                diff against actual git log
  - git diff --cached --name-only     - classify staged files against
  - primer file content (if any)        the allowlist
                                       - detect inline-outstanding heading
                                       - detect github.com in origin
                                       - run the 4-state + 3-trigger
                                         sequencing tree
                                     - emit KEY=value facts + STEPS=
```

`primer-detect.sh` never makes a dispatch decision itself — it is a thin
I/O shim, identical in spirit to `token-overlap.sh`/`candidate-extract.sh`.
All decision logic lives in the `.jq` filter, which takes no I/O and is
therefore fixture-testable with synthetic JSON.

## Output contract

`primer-detect.sh <project-dir>` prints, always to stdout on success:

```
PRIMER_EXISTS=0|1
LEARNINGS_EXISTS=0|1
PROJECT_CONTEXT_EXISTS=0|1
OUTSTANDING_ITEMS_EXISTS=0|1
PRIMER_HAS_INLINE_OUTSTANDING=0|1
BACKLOG_EXISTS=0|1
ROADMAP_EXISTS=0|1
GITHUB_ORIGIN=0|1
LOG_DRIFT=0|1
CODE_STAGED=0|1
STEPS=<comma-separated ordered list, possibly empty>
```

`STEPS` values, in the only orders the state machine can produce them:
`split`, `outstanding_split`, `backlog_rename`, `backlog_to_issues`,
`refresh`, `init`. Empty `STEPS` means check mode (Step 5) — primer is
current and no migration triggers fired.

**State machine** (ports the existing prose exactly, no behavior change):

All facts (`PRIMER_EXISTS` through `CODE_STAGED`) are always computed and
emitted regardless of which branch below fires — no fact is conditionally
skipped, so the full `KEY=value` contract holds even for `STEPS=init`.

`PRIMER_EXISTS=0` → `STEPS=init`, unconditionally — nothing else to
migrate or refresh yet. Otherwise, evaluate migration triggers in
dependency order, **threading each trigger's effect forward** into the
fact the next trigger reads — not by re-deriving increasingly complex
disjunctions per trigger, which doesn't compose past one link (see the
"Why threading, not disjunctions" note below):

```
DO_SPLIT      = (PROJECT_CONTEXT_EXISTS == 0)
DO_OSPLIT     = (PRIMER_HAS_INLINE_OUTSTANDING == 1) AND (OUTSTANDING_ITEMS_EXISTS == 0)
PROJ_OI       = DO_OSPLIT ? 1 : OUTSTANDING_ITEMS_EXISTS
DO_BRENAME    = (PROJ_OI == 1) AND (BACKLOG_EXISTS == 0)
PROJ_BL       = DO_BRENAME ? 1 : BACKLOG_EXISTS
DO_B2I        = (PROJ_BL == 1) AND (GITHUB_ORIGIN == 1)
DO_REFRESH    = (LOG_DRIFT == 1) OR (CODE_STAGED == 1)

STEPS = [split if DO_SPLIT] + [outstanding_split if DO_OSPLIT]
      + [backlog_rename if DO_BRENAME] + [backlog_to_issues if DO_B2I]
      + [refresh if DO_REFRESH]
```

`DO_REFRESH` reads the *raw* `LOG_DRIFT`/`CODE_STAGED` facts, not
projected ones — splitting and renaming don't touch the git-log block or
the staged-file set, so no threading is needed on this last link.

**Why threading, not disjunctions.** An earlier draft of this spec wrote
`backlog_to_issues`'s condition as `BACKLOG_EXISTS=1 OR (OUTSTANDING_ITEMS_EXISTS=1
AND BACKLOG_EXISTS=0)` — true now, or about to become true because
`backlog_rename` is queued. That was a real bug fix (caught by
caveman-review) but an incomplete one: `backlog_rename`'s *own* condition
(`OUTSTANDING_ITEMS_EXISTS=1 AND BACKLOG_EXISTS=0`) has the identical
problem one link further up the chain — `outstanding_split`, if also
queued, is what's about to make `OUTSTANDING_ITEMS_EXISTS` true, so a
bare `OUTSTANDING_ITEMS_EXISTS=1` snapshot check silently drops
`backlog_rename` whenever it's chained after `outstanding_split`.
Writing out the "OR about to become true" disjunction a second time
would have worked but doesn't generalize — a fifth chained trigger would
need a three-way disjunction, a sixth a four-way one. Threading a single
projected fact (`PROJ_OI`, `PROJ_BL`) forward through the pipeline scales
to any chain length and is easy to verify by construction: each trigger's
condition reads exactly the fact-state that will actually exist at its
own execution time, given everything queued before it. Verified against
all eleven fixtures below directly in `jq` before this spec was
finalized — see the Testing section.

## Error handling

Operational failure (jq missing, `primer-detect.jq` missing or from a
different `CONTRACT_VERSION`, a required git command failing outright)
prints one diagnostic line to stderr and **exits nonzero with no `STEPS=`
line on stdout at all** — no conservative default dispatch. Unlike
`token-overlap.sh` (where empty output safely degrades to "zero matches"),
there is no safe default here: some `STEPS` values gate destructive
migrations, and guessing wrong is worse than stopping. `commands/primer.md`
must treat a missing `STEPS=` line as a hard stop: surface the stderr
diagnostic, do not execute any step.

## Testing

Fixture-driven jq tests against synthetic JSON facts (no real git
required), mirroring `meta/superpowers/validation/2026-09-08-token-overlap.md`'s
format. The eleven state-machine cases below (plus a docs-allowlist
variant of case 5, and four operational-failure cases instead of the
single combined item 12 describes conceptually) make up the shipped
smoke test's 16 assertions total — see
`meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh`.

1. Fresh install (all existence flags 0) → `STEPS=init`.
2. Existing unsplit primer, otherwise current → `STEPS=split`.
3. Split + current + clean → `STEPS=` (empty).
4. Split + current, but recorded log block differs from actual → `STEPS=refresh`.
5. Split + current, non-allowlisted file staged → `STEPS=refresh`.
6. Inline outstanding heading present, no `OUTSTANDING_ITEMS.md` → `STEPS=outstanding_split`.
7. Both unsplit AND inline-outstanding → `STEPS=split,outstanding_split` (order proves the sequencing rule).
8. `OUTSTANDING_ITEMS.md` exists, no `BACKLOG.md` → `STEPS=backlog_rename`.
9. `BACKLOG.md` exists, github origin → `STEPS=backlog_to_issues`.
10. `BACKLOG.md` exists, non-github origin → `STEPS=` (empty) — proves the fossil-file case never fires the GitHub migration.
11. Full worst-case stack (unsplit + inline-outstanding + no outstanding-items file + no backlog file + github origin) → `STEPS=split,outstanding_split,backlog_rename,backlog_to_issues` in that exact order — neither `OUTSTANDING_ITEMS.md` nor `BACKLOG.md` exists yet; both migrations still fire because they're queued via threading (`PROJ_OI`/`PROJ_BL`), which is the whole point of this case.
12. Missing/wrong-version filter, or jq absent → nonzero exit, no `STEPS=` line.

## Rollout

`commands/primer.md` Step 1's "Interpret the output" prose (currently
~15 lines of manual state/trigger reasoning) is replaced with: run
`primer-detect.sh`, then execute each name in `STEPS` in order, falling
through to Step 5 (check mode) when `STEPS` is empty. The per-step
sections (2, 3, 3b, 3c, 3d, 4, 5) are unchanged by this sub-project —
only the dispatch that routes into them is scripted. Version bump +
CHANGELOG entry, following the Phase 4/5 precedent.

## Out of scope

Sub-projects B (Step 4 test-count rerun), C (Step 3c/3d migration
mechanics themselves — this spec only scripts *whether* they run, not
*what* they do), D (Step 2 placeholder derivation), and E (Step 3/3b
section-bucketing judgment) are each their own future spec/plan cycle.
