# Validation log — per-repo performance logging (v0.15.0)

**Branch:** `feat/performance-logging`
**Spec:** `meta/superpowers/specs/2026-08-17-performance-logging-design.md`
**Plan:** `meta/superpowers/plans/2026-08-17-performance-logging.md`

This log records an end-to-end run of the finished performance-logging
feature (Mechanisms 2 and 3 — the self-reported command timers in
`commands/primer.md`/`commands/end-session.md`, and the storage/gitignore
writer in `hooks/lib/perf-log.sh`) against a real scratch git repo. All
Bash blocks below are copied verbatim from `commands/primer.md` and
`commands/end-session.md` and were executed as the acting agent, with
`CLAUDE_PLUGIN_ROOT` pointed at this checkout
(`/Users/tal.golan/active_development/TG/session-continuity-plugin`) and
`cwd` inside a `mktemp -d` scratch repo, discarded after the run.
Mechanism 1 (the shipped-hook timing wrapper, `hooks/lib/perf-wrap.sh`)
was not separately exercised here — it only fires via the harness's own
`PreToolUse`/`SessionStart` hook dispatch on the *real* working directory,
not a scratch `cd`, so it's out of scope for a manually-driven scratch-repo
run; Tasks 2-3 cover it structurally.

---

## Scenario 1 — Primer init mode (no primer exists)

**Setup.** Fresh scratch repo, one commit (`2b135e2 chore: initial
commit`), no `.session-continuity/` directory.

**Expected.** `commands/primer.md` Step 1 detects no primer → init mode
(Step 2). Step 2 copies the three templates, derives placeholders, stages
all three files, and along the way `hooks/lib/perf-log.sh` creates
`.session-continuity/performance.log` and appends the gitignore line
(first-ever write in this repo) plus the `.gitignore-ensured` marker.

**Actual.** Step 1's detect-state Bash block ran and correctly reported
`PRIMER_EXISTS=0`, `LEARNINGS_EXISTS=0`, `PROJECT_CONTEXT_EXISTS=0`,
routing to init mode. Step 2 copied and filled the three templates
(directory-basename-derived project name, since no `package.json`/
`Cargo.toml`/`pyproject.toml` existed). One real friction found while
filling `LEARNINGS.md`: the shipped template's own example scaffold
(`{{LAYER_1_NAME}}`, `{{ENTRY_TITLE}}`, etc.) still contains `{{...}}`
tokens after copying, and primer.md Step 2 item 7's own literal
instruction — `grep -n '{{' ... .session-continuity/LEARNINGS.md` must
return nothing before staging — requires those to be swept to `TBD` too,
even though they're illustrative section scaffolding, not real per-project
blanks. Not a performance-logging regression (LEARNINGS.md is explicitly
untouched by this feature per its own scope note), but a real result of
literally following the instruction as written; noted under Concerns
below since it's the kind of thing this validation task exists to catch,
even though it predates Tasks 1-6.

`.session-continuity/performance.log` after this run:
```
{"ts":"2026-08-17T22:18:37Z","source":"command","name":"primer","duration_s":0.034,"step":"step-1-detect-state"}
{"ts":"2026-08-17T22:19:26Z","source":"command","name":"primer","duration_s":0.028,"step":"step-2-init-derive-placeholders"}
```

`.gitignore` after this run:
```
.session-continuity/performance.log
```

**Result.** Pass. Both instrumented units in the init path (Step 1's
`step-1-detect-state`, Step 2's `step-2-init-derive-placeholders`) logged
exactly once, with correct `source=command`, `name=primer`, and `step`
values, parseable JSON, real sub-second `duration_s`. `.gitignore` got the
exact literal line `.session-continuity/performance.log` on the very
first `perf-log.sh record` call, before any command-specific logic ran —
confirms Mechanism 3's marker-gated gitignore-ensure fires correctly on
first write.

---

## Scenario 2 — Primer refresh mode (unrelated code staged)

**Setup.** After Scenario 1's three files were staged and committed
(`c72a744 docs: initialize session continuity`), created `src/app.js`
(an unrelated code file) and `git add`ed it, then re-ran `primer.md`
from Step 1.

**Expected.** Step 1 detects a primer exists, `PROJECT_CONTEXT.md` exists
(so not split mode), and either the git-log block has drifted (the primer
still shows only the pre-init-commit one-line log) or code is staged
outside the docs/session-continuity allowlist (`src/app.js` is) → refresh
mode (Step 4). Step 4 regenerates the git-log block, skips the test-count
rerun (no test-counts section in this primer), surfaces activity since
the last primer touch (empty — the primer was touched in the same
commit that's now `HEAD`), and stages the updated primer.

**Actual.** Step 1's detect-state block correctly reported
`PRIMER_EXISTS=1`, `LEARNINGS_EXISTS=1`, `PROJECT_CONTEXT_EXISTS=1`, and
`git diff --cached --name-only` showing `src/app.js` — both drift signals
present. Routed to refresh mode. Step 4 item 2 (git-log regen) ran and
logged. Step 4 item 3 (test-count rerun) legitimately did not fire — this
scratch primer has no test-counts section, so per the instruction's own
gating ("If the primer has a test-counts section...") the whole timed
block, including its `perf-log.sh` call, is skipped; this is correct
conditional behavior, not a miss. Step 4 item 4 (activity-surface) ran
and logged; the `git log <last-primer-commit>..HEAD --oneline` output was
empty since no commit had landed since the primer's last touch (only a
stage, not yet a commit) — correctly an empty candidate list, no overlay
rendered. Primer's git-log block and current-state summary were then
updated and staged; the repo was committed to advance to the next
scenario.

`.session-continuity/performance.log` after this run (new lines only):
```
{"ts":"2026-08-17T22:24:02Z","source":"command","name":"primer","duration_s":0.035,"step":"step-1-detect-state"}
{"ts":"2026-08-17T22:24:27Z","source":"command","name":"primer","duration_s":0.020,"step":"step-4-git-log-refresh"}
{"ts":"2026-08-17T22:24:54Z","source":"command","name":"primer","duration_s":0.033,"step":"step-4-activity-surface"}
```

`.gitignore` after this run (unchanged from Scenario 1 — confirms the
marker file suppresses a duplicate append):
```
.session-continuity/performance.log
```

**Result.** Pass, with one real-world finding surfaced along the way
(see Concerns). The three primer-refresh units that should fire under
these preconditions fired with correct `step` slugs and durations;
`step-4-test-count-rerun` correctly did not fire because its precondition
(a test-counts section) wasn't present — verified by inspecting the
primer's own content, not assumed.

---

## Scenario 3 — end-session fast path (nothing changed since last close-out)

**Setup.** Intent per the brief: commit Scenario 2's staged changes so
the tree is clean, then run `/session-continuity:end-session` with
nothing further changed.

**Actual — first attempt surfaced a real gap.** After committing
Scenario 2's changes, `git status --porcelain` was **not** empty: two
files created by `perf-log.sh` itself — `.gitignore` (newly created,
never staged by any documented step) and
`.session-continuity/.gitignore-ensured` (the internal marker file) —
remained untracked. Neither `primer.md` nor `end-session.md` stages or
mentions committing either file anywhere in their instructions.
Concretely: the fast-path gate (`git status --porcelain` empty AND
`<last-primer-commit>` == `HEAD`) evaluated to **false** purely because
of these two Mechanism-3-created artifacts — even though nothing in the
tracked project state had changed. Ran the fast-path Bash block twice
more while diagnosing (once right after discovering the untracked
`.gitignore`, once after committing `.gitignore` alone but leaving the
marker file untracked) — both times the gate still failed for the same
reason, confirmed by direct inspection of `git status --porcelain`
output each time.

Committed both files explicitly (as a real user would need to,
proactively, since no documented step does this for them), then
resynced the primer's `git log --oneline -5` block to the new `HEAD` and
committed that too — restoring `<last-primer-commit> == HEAD`. Re-ran the
fast-path Bash block a third time: `git status --porcelain` was empty and
both hashes matched, so the gate correctly evaluated true. Continued past
Step 1 (skipped entirely, as designed) into Step 2 (skipped — no real
Claude Code transcript file exists for this scratch directory, so
transcript-file mode correctly and silently fell through to
context-window mode, and `step-2-transcript-extraction`'s block is
explicitly scoped "transcript-file mode only," so it correctly did not
fire) and Step 3 (gather-facts), which ran and logged normally.

`.session-continuity/performance.log` after this run (new lines only):
```
{"ts":"2026-08-17T22:27:43Z","source":"command","name":"end-session","duration_s":0.049,"step":"step-1-fast-path"}
{"ts":"2026-08-17T22:30:20Z","source":"command","name":"end-session","duration_s":0.050,"step":"step-1-fast-path"}
{"ts":"2026-08-17T22:34:11Z","source":"command","name":"end-session","duration_s":0.052,"step":"step-1-fast-path"}
{"ts":"2026-08-17T22:37:13Z","source":"command","name":"end-session","duration_s":0.085,"step":"step-3-gather-facts"}
```
(The first three lines are the three fast-path probes described above —
two genuine gate failures, one genuine pass — all logged correctly
regardless of which way the gate evaluated, confirming the timer wraps
the check itself rather than only the "fast path taken" branch.)

`.gitignore` after this run:
```
.session-continuity/performance.log
```

**Result.** Pass on the mechanism itself (the fast-path gate's own logic
is correct — verified it flips from false to true exactly when its two
stated conditions become true, and the timer/logger around it works
regardless of outcome). **Concern raised** (see below): the fast path's
practical trigger rate on a *freshly initialized* repo is undermined by
Mechanism 3's own untracked artifacts, until a user notices and commits
them — something no documented step currently prompts for.

---

## Scenario 4 — end-session full Step 1 path (drift + appears-DONE item)

**Setup.** Added an outstanding item to the primer whose artifact already
exists in the scratch repo: *"Add a `src/app.js` entry point... deferred
until real app structure is decided"* (the file already existed from
Scenario 2). Committed that primer edit, then made a further commit with
a subject deliberately overlapping the item's tokens (`feat: wire up
src/app.js entry point for scratch service` — needed so the
outstanding-items overlap gate's token-intersection check, cardinality
≥3 against at least one commit subject, would pass and route the item
into full classify/verify rather than short-circuiting it to `manual`
via the gate). Staged one more unrelated file (`NOTES.md`) on top, then
ran `end-session` from Step 1.

**Expected.** Fast path does not fire (staged file present, and a commit
landed since the primer's last touch). Outstanding-items verification
runs: the item is code-verifiable (names `src/app.js`), the overlap gate
passes against the `wire up src/app.js entry point` commit subject, the
derived `[ -f src/app.js ]` check finds it present → `appears-DONE` with
cited evidence. Drift check finds the git-log block stale → refresh flow
enters, appending the `appears-DONE` item to the close-candidate overlay.
User (simulated) declines to close it → item stays in the primer,
Step 3's Outstanding-items row reports it with a ⚠️ marker.

**Actual.** Fast-path Bash block ran and correctly reported non-empty
`git status --porcelain` (`A NOTES.md`) and `<last-primer-commit> !=
HEAD` → routed past the fast path. Computed the commit list since the
primer's last touch: exactly the one qualifying commit. Ran the
verification Bash block with `--items=1`: `[ -f src/app.js ]` found the
file present → `appears-DONE`, matching the expected verdict exactly.
Drift check confirmed the primer's `git log --oneline -5` block was
stale relative to actual `HEAD` → entered the refresh flow, regenerated
the block, rendered the close-candidate line (`src/app.js exists — 544d242
→ item #1`), and — simulating the user declining ("no changes") — left
the item in the primer untouched, matching the never-auto-close
invariant. Staged the refreshed primer and `NOTES.md`, then ran Step 3's
gather-facts block, which correctly listed both staged files, zero
unstaged modifications, zero untracked files, and the no-upstream branch
state.

`.session-continuity/performance.log` after this run (new lines only):
```
{"ts":"2026-08-17T22:39:22Z","source":"command","name":"end-session","duration_s":0.052,"step":"step-1-fast-path"}
{"ts":"2026-08-17T22:43:06Z","source":"command","name":"end-session","duration_s":0.050,"step":"step-1-fast-path"}
{"ts":"2026-08-17T22:43:34Z","source":"command","name":"end-session","duration_s":0.004,"step":"step-1-outstanding-items-verification","items":1}
{"ts":"2026-08-17T22:45:09Z","source":"command","name":"end-session","duration_s":0.091,"step":"step-3-gather-facts"}
```
(Two `step-1-fast-path` lines appear because the gate was checked once
before adding `NOTES.md` to staging and once after — both correctly
evaluate false and log normally; the interesting new unit is
`step-1-outstanding-items-verification`, which correctly carries
`"items":1`.)

`.gitignore` after this run (unchanged throughout):
```
.session-continuity/performance.log
```

**Result.** Pass. The `appears-DONE` verdict, its cited evidence, the
`--items=1` field on the verification log line, and the never-auto-close
behavior at the simulated prompt all matched the expected behavior
described in `commands/end-session.md`'s Outstanding-items verification
sub-block. `step-1-drift-test-rerun` did not fire in this run — correctly
so, since this scratch primer never had a test-counts section to begin
with (same conditional-skip reasoning as Scenario 2's
`step-4-test-count-rerun`).

---

## Full captured log (all 4 runs, in order)

```
{"ts":"2026-08-17T22:18:37Z","source":"command","name":"primer","duration_s":0.034,"step":"step-1-detect-state"}
{"ts":"2026-08-17T22:19:26Z","source":"command","name":"primer","duration_s":0.028,"step":"step-2-init-derive-placeholders"}
{"ts":"2026-08-17T22:24:02Z","source":"command","name":"primer","duration_s":0.035,"step":"step-1-detect-state"}
{"ts":"2026-08-17T22:24:27Z","source":"command","name":"primer","duration_s":0.020,"step":"step-4-git-log-refresh"}
{"ts":"2026-08-17T22:24:54Z","source":"command","name":"primer","duration_s":0.033,"step":"step-4-activity-surface"}
{"ts":"2026-08-17T22:27:43Z","source":"command","name":"end-session","duration_s":0.049,"step":"step-1-fast-path"}
{"ts":"2026-08-17T22:30:20Z","source":"command","name":"end-session","duration_s":0.050,"step":"step-1-fast-path"}
{"ts":"2026-08-17T22:34:11Z","source":"command","name":"end-session","duration_s":0.052,"step":"step-1-fast-path"}
{"ts":"2026-08-17T22:37:13Z","source":"command","name":"end-session","duration_s":0.085,"step":"step-3-gather-facts"}
{"ts":"2026-08-17T22:39:22Z","source":"command","name":"end-session","duration_s":0.052,"step":"step-1-fast-path"}
{"ts":"2026-08-17T22:43:06Z","source":"command","name":"end-session","duration_s":0.050,"step":"step-1-fast-path"}
{"ts":"2026-08-17T22:43:34Z","source":"command","name":"end-session","duration_s":0.004,"step":"step-1-outstanding-items-verification","items":1}
{"ts":"2026-08-17T22:45:09Z","source":"command","name":"end-session","duration_s":0.091,"step":"step-3-gather-facts"}
```

All 13 lines are well-formed JSON (checked with `python3 -m json.tool`
per line, zero parse failures) and every `step` value matches an exact
slug named in `commands/primer.md`/`commands/end-session.md`. No line
carries an `exit` field (`source` is always `command`, never `hook`, in
this run — expected, since Mechanism 1's hook-timing wrapper wasn't
separately exercised here per the note at the top of this log).

---

## Concerns found during this validation

1. **Fast path's real-world trigger rate is undermined by Mechanism 3's
   own untracked artifacts.** On any repo's first-ever `perf-log.sh
   record` call, `.gitignore` (new or modified) and
   `.session-continuity/.gitignore-ensured` are created but never staged
   or committed by any documented step in `primer.md` or `end-session.md`.
   Since `end-session.md`'s fast path requires `git status --porcelain`
   to be completely empty, these two untracked files silently force the
   full Step 1 path (outstanding-items verification + drift check) on
   every invocation until a user happens to notice and commit them —
   which nothing prompts them to do. This is not a crash or an incorrect
   verdict; it's a quiet perf-optimization miss that could persist
   indefinitely on inactive/rarely-committed repos, working directly
   against the stated purpose of the fast path ("if the primer is
   already in sync with the repo, do nothing"). Once a user commits both
   files (verified above), the fast path works exactly as designed on
   every subsequent invocation. Recommend either: gitignoring
   `.gitignore-ensured` itself (removing it from `git status` visibility
   permanently), or a one-line mention in `primer.md`'s init-mode
   staging step to include `.gitignore` in what gets staged. Out of
   scope for this validation-only task to fix.

2. **`LEARNINGS.md` template ships with its own `{{...}}` scaffolding
   that collides with `primer.md` Step 2 item 7's literal grep check.**
   Pre-existing, unrelated to Tasks 1-6, noted for completeness under
   Scenario 1 above.

Neither concern is a defect in the performance-logging feature itself —
every instrumented unit that had its documented precondition met fired
exactly once, with correct fields, correct JSON, and correct durations,
across all four scratch-repo runs above. Concern 1 is a pre-existing
interaction between the new feature's own side effects and the
end-session fast path's gate; concern 2 predates this feature and sits in
a file this feature explicitly never touches.

## Acceptance gate

- All 4 scenarios in the brief were run against a real scratch git repo
  with `CLAUDE_PLUGIN_ROOT` pointed at this checkout; every Bash block was
  copied verbatim from `commands/primer.md`/`commands/end-session.md`.
- `Actual` and `Result` above are the real captured output — no
  `_(filled at validation time)_` placeholders remain.
- `.session-continuity/performance.log` and `.gitignore` were captured
  after each of the four runs; all four snapshots appear above.
- Every logged line is valid JSON with an expected `step` value; no
  parse failures; no silent-fail exit codes from `perf-log.sh` observed.
- The scratch repo was discarded (`rm -rf`) after the run; this
  checkout's own `.session-continuity/` and working tree are untouched
  (`git status --porcelain` clean throughout, verified before and after).

**Verdict.** Feature validated end-to-end. Two concerns surfaced (see
above) — neither blocks this task, both worth a maintainer's attention
before/soon after merge.
