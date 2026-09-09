# Design — `test-count-rerun.sh`/`.jq` (Determinism Phase 6, sub-project B)

**Issue:** #43 (Determinism Phase 6 — `primer` detect, migrate, init, drift)

## Context

`meta/superpowers/specs/2026-09-08-primer-detect-design.md` scoped Phase 6
into five sub-projects and shipped only sub-project A (Step 1's
detect/dispatch logic, PR #52). This spec covers **sub-project B only**:
`commands/primer.md` Step 4 item 3 (lines 285-292 as of `de381a8`) — the
test-count majority-vote rerun that runs during Refresh mode.

This repo's own `.session-continuity/PROJECT_CONTEXT.md` records "No
automated test suite," so this sub-project cannot be dogfooded against a
real run here — same constraint sub-project A had for `git mv`-class
migrations, solved the same way: synthetic fixtures over real scratch
repos, not live dogfooding.

## Problem

Step 4 item 3 today is ~8 lines of prose the model re-executes by hand
every Refresh-mode invocation: decide whether a rerun is even warranted
(via a git-diff skip check), run the recorded test command once, and —
only on disagreement with the recorded count — retry up to 2 more times,
pin to a ≥2-of-3 majority, and report either drift or an unstable-suite
spread. This is the same class of hand-evaluated conditional logic Phases
4-6A already found unreliable when left to per-invocation prose
re-derivation, and it is Phase 6's other highest-frequency piece (every
drift-detected Refresh-mode call, per the original phase table).

## Recorded-count format (existing, unchanged)

`commands/primer.md` Step 2 (Init mode) already seeds
`PROJECT_CONTEXT.md`'s `{{TEST_COMMAND_SUMMARY}}` placeholder as
`` `<TEST_CMD>` — N pass / M fail `` when the init test run had exit 0 and
a parseable count, else the bare command string, else `TBD` — never an
invented count (line 114). Step 4's rerun reads this same line back.

## Architecture

```
test-count-rerun.sh (I/O)               test-count-rerun.jq (pure decision)
  - read PROJECT_CONTEXT.md's            - given {recorded, mode, observed:[...]}
    TEST_COMMAND_SUMMARY line              - mode=="skip" -> RETRIES=0, DRIFT=0
  - parse <TEST_CMD> + recorded N          - mode=="run": majority-vote /
  - git diff <last-primer-commit>..HEAD      drift / spread over observed[]
    --name-only -> skip decision
  - if not skipped: run <TEST_CMD>,
    parse observed count, once
  - if observed[0] != recorded: run
    <TEST_CMD> 2 more times, parse each
  - emit facts to stdout
```

`test-count-rerun.sh` never decides drift/majority itself — it only
decides *whether to run* (the skip check) and *how many times* (stop
after 1 if it matches, else run to 3), because that decision requires an
actual test-run count it doesn't have until it runs. It hands the full
`observed` array to the `.jq` filter for the pure vote/drift/spread
logic, which is fixture-testable with synthetic JSON and needs no git or
subprocess access. This mirrors `token-overlap.sh`/`.jq`'s split (I/O
shim computes once, pure filter decides), not `primer-detect.sh`/`.jq`'s
(which reads only static facts) — here the I/O side is stateful across
up to 3 runs, so the shim itself must implement the "stop early on
match" short-circuit; only the *voting* over whatever it collected moves
to `.jq`.

**Count parsing** duplicates (does not import) Step 2's regex family —
`N pass`, `N passed`, `test result: ok. N passed`, else unparseable. Step
2's version lives inline in `commands/primer.md` prose, not in a script;
sub-project D (Step 2's placeholder derivation) is the one that would
extract it to a shared script, and is explicitly out of scope here. This
sub-project accepts the short-term duplication rather than reaching into
D's scope.

## Output contract

`test-count-rerun.sh <project-dir> <last-primer-commit>` prints, always
to stdout on success:

```
TEST_CMD=<string, may be empty>
RECORDED_COUNT=<int, or empty if PROJECT_CONTEXT.md had no parseable count>
MODE=skip|run|no-command|no-count|run-unparseable
RETRIES=<int, 0-2>
OBSERVED=<comma-separated ints, the runs actually executed, in order>
DRIFT=0|1
PINNED_COUNT=<int, empty if DRIFT=0 or MODE!=run>
SPREAD=<1 if all 3 runs disagree with each other, else 0>
```

`MODE=skip`: the git-diff check found no file outside `.session-continuity/`
changed since the last primer touch — `RETRIES=0`, `OBSERVED=` empty,
`DRIFT=0`.

`MODE=no-command`: `PROJECT_CONTEXT.md`'s `TEST_COMMAND_SUMMARY` line has
no `<TEST_CMD>` (bare `TBD`, or the line is missing/unparseable) — nothing
to rerun. `RETRIES=0`, `DRIFT=0`.

`MODE=no-count`: `TEST_CMD` exists but `RECORDED_COUNT` doesn't (the
seeded line fell back to the bare command string) — there is nothing to
diff against. The command still runs once so the caller can seed a count
going forward, but `DRIFT` is always `0` in this mode — you cannot drift
from a value that was never recorded.

`MODE=run`: the normal path. Runs 1-3 times per the majority-vote rule
already in the current prose (unchanged behavior, now scripted):
first run matching `RECORDED_COUNT` stops at `RETRIES=0`; a mismatch
triggers 2 more runs; `PINNED_COUNT` is whichever value appears in ≥2 of
the 3 `OBSERVED` entries; `DRIFT=1` iff `PINNED_COUNT != RECORDED_COUNT`;
`SPREAD=1` iff all 3 disagree (in which case `PINNED_COUNT` is empty and
the caller reports the raw spread, matching the current prose's
`"saw 1162 / 1161 / 1162 across 3 runs"` phrasing using `OBSERVED`
directly).

A test run that times out or exits nonzero with no parseable count in
its output is treated as an unparseable observation — dropped from the
majority-vote pool (not counted as a vote for any value), but the run
still counts against the 3-run budget. If none of up to 3 runs produce a
parseable count, `MODE=run-unparseable`, `DRIFT=0` (nothing to compare),
and the caller surfaces this as "test command produced no parseable
count after N attempts" rather than silently reporting no drift.

## Error handling

Operational failure (jq missing, `test-count-rerun.jq` missing or
`CONTRACT_VERSION`-mismatched, `PROJECT_CONTEXT.md` unreadable) prints
one diagnostic line to stderr and exits nonzero with no `MODE=` line at
all. Unlike `primer-detect.sh`, a wrong guess here is not destructive
(no `git mv`/`git rm` downstream) — but `commands/primer.md` still must
not fabricate a drift verdict on script failure; it falls back to
`TBD`/manual reporting, same as any other derived-field failure per this
file's "never invent a count" rule (line 371).

## Testing

Fixture-driven, split across both layers:

- `.jq` filter: synthetic JSON fixtures (no git, no subprocess) covering
  the vote/drift/spread matrix — match-on-first-run, drift confirmed by
  majority, spread (3-way disagreement), and the `skip`/`no-command`/
  `no-count` short-circuit modes.
- `.sh` shim: scratch git repos with a fake `TEST_CMD` (a tiny script
  that echoes a controlled count, invocation-counted via a side file so
  the fixture can assert exactly how many times it ran) — covering the
  skip-check's git-diff logic, the stop-after-1-on-match short circuit,
  and the timeout/nonzero/unparseable-output edge case.

Mirrors `meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh`'s
format. New runner:
`meta/superpowers/validation/2026-09-09-test-count-rerun-smoke.zsh`.

## Rollout

`commands/primer.md` Step 4 item 3's prose is replaced with: run
`test-count-rerun.sh`, then report per the `MODE`/`DRIFT`/`SPREAD`
contract above (the reporting sentence itself — "drift with the pinned
count" / "suite is unstable" / etc. — stays prose, since it's the kind of
short user-facing formatting Phase 4/5 already left as prose elsewhere).
Version bump + CHANGELOG entry, following the Phase 4/5/6A precedent.

## Out of scope

Sub-projects C (Step 3c/3d migration mechanics), D (Step 2's placeholder
derivation — including the shared count-parsing regex this sub-project
duplicates), and E (Step 3/3b section-bucketing judgment) are each their
own future spec/plan cycle.
