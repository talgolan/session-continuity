# Determinism Phase 6, sub-project D — `primer-init-derive.sh`/`.jq` Design

## Context

Phase 6 (`#43`) decomposes into five sub-projects — see
`meta/superpowers/specs/2026-09-08-primer-detect-design.md`'s Context section
for the full breakdown. A (Step 1 detect/dispatch) and B (Step 4 test-count
rerun) are shipped. This spec covers **sub-project D only**: `commands/primer.md`
Step 2 item 6's "Derive from that output" list — the placeholder
gather-and-regex work that runs once per repo, during Init mode.

## Problem

Step 2 item 6 gathers ~9 raw facts in one Bash call (already scripted: `pwd`,
package-manifest greps, `git log --oneline -5`, an `@module` grep, a
discovered-and-run test command), then leaves the model to mentally derive
seven placeholder values from that output. Two of the seven are genuinely
judgment calls the design's parent spec
(`meta/superpowers/specs/2026-09-02-determinism-program-design.md`, "What
stays model work") already names and excludes: `{{WORKFLOW_CONVENTIONS}}`'s
draft (quoting arbitrary `CLAUDE.md` prose under a sub-heading) and
`{{REPO_LAYOUT_SUMMARY}}`'s one inferred sentence (describing a project from
file extensions present). This spec does not touch either.

A third, `{{MODULES_TABLE}}`, looks mechanical (grep already found the
matches) but isn't: "Purpose = the `@module` value plus the docblock's
one-line description **if present**, Notes = the adjacent `Exports:` line
**if present**" depends on a JSDoc convention that varies per project — how
many lines separate the match from a description, whether an `Exports:` line
exists at all, whether the block spans one line or three. Regex-parsing this
generically is the same class of "arbitrary project prose inference" that
already got `REPO_LAYOUT_SUMMARY` and `WORKFLOW_CONVENTIONS` excluded, so it
stays prose here for the same reason, tracked as part of remaining scope (see
"Non-goals" below — it is not folded into sub-project E, which is Step 3/3b's
unrelated section-bucketing work; it simply stays put in Step 2 as-is).

The four that remain are pure, format-fixed regex/parse operations, each
already precedented by a shipped script:

- `{{PROJECT_NAME}}` — first non-empty of `package.json` `name`, `Cargo.toml`
  `name`, `pyproject.toml` `name`, else the directory basename. Pure string
  extraction, no project-specific variance.
- `{{LATEST_COMMIT_HASH_N}}` / `{{LATEST_COMMIT_SUBJECT_N}}` (N = 1..5) —
  `git log --oneline -5`'s fixed `<hash> <subject>` shape.
- `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}` — the `pwd` output, verbatim.
- `{{TEST_COMMAND_SUMMARY}}` — a count-recognition regex over the one
  captured test run's output. `hooks/lib/test-count-rerun.sh` (shipped,
  sub-project B) already treats "`[0-9]+ pass(ed)?` found in arbitrary test
  output" as a mechanical, non-judgment operation for its rerun job, which
  faces the identical arbitrary-test-framework-output problem. This spec
  reuses that exact regex rather than inventing a second one for the same
  concept.

## Architecture

```
commands/primer.md's existing        primer-init-derive.sh (I/O)
Bash block (UNCHANGED)                  - pwd, dirname
  - pwd, dirname                        - package.json/Cargo.toml/
  - manifest name-line greps              pyproject.toml name lines
  - git log --oneline -5                  - git log --oneline -5 (redone
  - @module grep                            locally — cheap, no side
  - discovers + runs TEST_CMD               effects, and this block never
    (this is the ONE place the                captured its own manifest/
    test suite actually runs)                 git-log output into named
  - exports TEST_CMD, TEST_OUTPUT   -->        vars, so the script must
    (already-computed, not re-run)             re-read those two — but
                                                TEST_CMD/TEST_OUTPUT it DOES
                                                read from the environment,
                                                never re-executes them)
                                       - passes raw text as --arg strings
                                         to primer-init-derive.jq
```

```
primer-init-derive.jq (pure decision)
  - pick PROJECT_NAME by priority
  - split git log lines into HASH_N/SUBJECT_N pairs (1..5, fewer if the
    repo has fewer commits — every raw line maps to exactly one pair,
    parseable or not, see "Commit-line parsing" below)
  - regex-match pass/fail counts out of $test_output (supplied, not
    fetched)
  - format TEST_COMMAND_SUMMARY, falling back to the bare command or TBD
    per the rules below — never inventing a count
  - emit KEY=value facts
```

`primer-init-derive.sh` never derives a placeholder value itself — it is a
thin I/O shim, identical in spirit to `primer-detect.sh` and
`test-count-rerun.sh`. All parsing lives in the `.jq` filter, fixture-testable
with synthetic JSON/string args, no git or subprocess required.

**Test command: read, never re-run.** `commands/primer.md`'s existing Bash
block already discovers `TEST_CMD` and runs it exactly once (today's prose,
unchanged in shape). An earlier draft of this spec had
`primer-init-derive.sh` independently re-discover *and re-run* `TEST_CMD` —
caught in review before implementation: Init mode would have executed the
project's real test suite twice per invocation, for no benefit, purely
because the script wasn't wired to the value the surrounding block already
computed in the same shell. The fix: that Bash block adds one line,
`export TEST_CMD TEST_OUTPUT`, right after computing them (both already
exist as plain bash variables at that point — `TEST_CMD` always set,
possibly empty; `TEST_OUTPUT` set only when `TEST_CMD` was non-empty).
`primer-init-derive.sh` reads `"${TEST_CMD:-}"` / `"${TEST_OUTPUT:-}"` from
its inherited environment instead of discovering or executing anything test-
related itself. `TEST_EXIT` is not threaded through: the derivation only
ever looks for a parseable count in `$test_output`, regardless of exit code
— the same "never inspect the exit code, only the parsed output" choice
`test-count-rerun.sh`'s `run_once()` already made, so a timed-out or
nonzero-exit run degrades to the same "no parseable count" outcome as a
zero-exit run that simply printed none, with one code path for both.

**Unchanged from today's prompt:** the raw-fact-gathering Bash block itself
(manifest checks, `git log`, the `@module` grep, test-command discovery and
execution) — this spec only replaces the *derivation* step that reads that
output, not the gathering, and reads (never re-runs) the one test execution
that block already performs. `{{MODULES_TABLE}}`, `{{REPO_LAYOUT_SUMMARY}}`,
and `{{WORKFLOW_CONVENTIONS}}` stay exactly as today's prose describes them.

## Output contract

`primer-init-derive.sh <project-dir>` prints, always to stdout on success:

```
PROJECT_NAME=<string>
WORKING_DIRECTORY_ABSOLUTE_PATH=<string>
COMMIT_COUNT=<0-5>
LATEST_COMMIT_HASH_1=<string, empty if COMMIT_COUNT<1>
LATEST_COMMIT_SUBJECT_1=<string, empty if COMMIT_COUNT<1>
LATEST_COMMIT_HASH_2=...
LATEST_COMMIT_SUBJECT_2=...
LATEST_COMMIT_HASH_3=...
LATEST_COMMIT_SUBJECT_3=...
LATEST_COMMIT_HASH_4=...
LATEST_COMMIT_SUBJECT_4=...
LATEST_COMMIT_HASH_5=...
LATEST_COMMIT_SUBJECT_5=...
TEST_CMD=<string, empty if none discovered>
TEST_COMMAND_SUMMARY=<string, see rules below — never empty>
```

`COMMIT_COUNT` exists because a fresh repo (Init mode's most common case —
Step 2 only runs once per repo, and often on the very first commit) can have
fewer than 5 commits; the placeholder-fill step in `commands/primer.md` uses
it to know how many `LATEST_COMMIT_*_N` placeholders the template actually
has to fill, and to leave the rest untouched rather than writing empty
`{{LATEST_COMMIT_HASH_N}}` pairs the template doesn't have anyway. Verified,
not assumed: `skills/session-continuity/templates/SESSION_PRIMER.md:27-31`
has exactly five `{{LATEST_COMMIT_HASH_N}} {{LATEST_COMMIT_SUBJECT_N}}`
lines, `N` = 1 through 5 — so `COMMIT_COUNT` never exceeds 5 by
construction, since the gathering step only ever ran `git log --oneline -5`.

**`PROJECT_NAME` priority:** `package.json` `name` → `Cargo.toml` `name` →
`pyproject.toml` `name` → directory basename. First match wins; this ports
the existing prose's implicit ordering (the bash block checks manifests in
that order) without behavior change.

**Commit-line parsing — every raw line yields exactly one pair.** Each
non-empty `git log --oneline -5` line is expected to match
`^\S+\s+.*$` (hash, whitespace, subject — subject may be empty). A line
that doesn't match this shape must still produce one `commits[]` entry
(hash-only, empty subject) rather than being silently dropped: jq's
`capture(re)` with no named-capture match produces *zero* outputs, not an
error and not `null` (confirmed: `jq -n '"onetoken" | capture("^(?<hash>\\S+)\\s+(?<subject>.*)$")'`
exits 0 and prints nothing), so a naive `map(capture(...))` drops any
non-matching line from the array — shrinking `COMMIT_COUNT` by one *and*
shifting every following commit's `_N` index to the wrong recency position,
silently. The filter must guard every line with `test(...)` before
`capture(...)` and fall back to a hash-only entry on no match, so
`$commits`'s length always equals the number of non-empty raw lines.

**`TEST_COMMAND_SUMMARY` rules** (never invents a count):

- `TEST_CMD` empty (no test command discovered) → `TBD`.
- `TEST_CMD` non-empty but the run timed out, crashed, or the captured
  output has no `[0-9]+ pass(ed)?` match → the bare `` `<TEST_CMD>` `` string
  (backtick-quoted, no counts).
- A pass count is found **and** a `[0-9]+ fail(ed)?` match is also found →
  `` `<TEST_CMD>` — N pass / M fail ``.
- A pass count is found but no fail count is found → the bare
  `` `<TEST_CMD>` `` string, same as the no-count case. This is the
  conservative reading of "never invent a count": a fail count of `0` is
  still a count this run did not actually report finding, since a framework
  that omits a fail figure entirely (rather than printing "0 failed") gives
  no positive evidence either way.

Both count regexes are lifted verbatim from
`hooks/lib/test-count-rerun.sh`'s `run_once()`: `grep -oE '[0-9]+ pass(ed)?' |
head -1 | grep -oE '^[0-9]+'`, with `fail` substituted for the second.

**`TEST_CMD`/`test_output` are inputs, not discovered here.**
`primer-init-derive.sh` reads `TEST_CMD` and `TEST_OUTPUT` from its
inherited environment — set by `commands/primer.md`'s existing Bash block,
which already ran the discovered command once — rather than re-discovering
or re-running a test command itself. See "Test command: read, never re-run"
above. `TEST_CMD` empty in the environment (no command was discovered or
none exists) is what drives the `TBD` case below; it is never re-derived
from the manifest inside this script.

**Error handling**, matching `primer-detect.sh`'s precedent: jq missing, the
`.jq` filter missing or from a different `CONTRACT_VERSION`, or
`<project-dir>` not a readable directory each print one diagnostic line to
stderr and exit nonzero with no `PROJECT_NAME=` line on stdout at all. Unlike
`primer-detect.sh`'s dispatch (which gates destructive migrations), a wrong
guess here only means a template placeholder — `commands/primer.md` falls
back to asking the user for that field manually rather than inventing one, so
this is a lower-stakes failure mode, but still: no fabricated derivation on
an operational failure.

## Testing

Fixture-driven `.jq` tests against synthetic string args (no real git or
subprocess), mirroring `meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh`'s
format, plus `.sh` integration fixtures against scratch git repos for the
manifest-priority and commit-count-below-5 cases, plus operational-failure
cases. Matrix:

1. `package.json` name present → `PROJECT_NAME` from it, even if `Cargo.toml`
   also present (priority order).
2. Only `Cargo.toml` present → `PROJECT_NAME` from it.
3. Only `pyproject.toml` present → `PROJECT_NAME` from it.
4. No manifest → `PROJECT_NAME` = directory basename.
5. 5 commits in git log → `COMMIT_COUNT=5`, all 5 hash/subject pairs filled.
6. 2 commits (fresh repo) → `COMMIT_COUNT=2`, pairs 3-5 empty.
7. 0 commits (literally empty repo, no commits yet) → `COMMIT_COUNT=0`, all
   pairs empty.
8. `TEST_CMD` empty (unset or empty in the environment) →
   `TEST_COMMAND_SUMMARY=TBD`.
9. `TEST_CMD`/`TEST_OUTPUT` set as environment inputs, `TEST_OUTPUT`
   contains "12 passed, 0 failed" → full `N pass / M fail` summary.
10. `TEST_CMD` set, `TEST_OUTPUT` contains "12 pass" only (no fail count) →
    bare `` `<TEST_CMD>` `` string, no invented `0 fail`.
11. `TEST_CMD` set, `TEST_OUTPUT` empty or has no recognizable count → bare
    `` `<TEST_CMD>` `` string.
12. A git-log line that doesn't match `<hash> <subject>` shape still yields
    one `commits[]` entry (hash-only) — `COMMIT_COUNT` and every following
    index stay correct, nothing silently dropped.
13. Missing `.jq` filter → nonzero exit, no `PROJECT_NAME=` line.
14. Wrong `CONTRACT_VERSION` → nonzero exit, no `PROJECT_NAME=` line.
15. `jq` absent from `PATH` → nonzero exit, no `PROJECT_NAME=` line.

## Non-goals

- `{{MODULES_TABLE}}`'s docblock parsing, `{{REPO_LAYOUT_SUMMARY}}`'s
  inferred sentence, and `{{WORKFLOW_CONVENTIONS}}`'s draft — all three stay
  prose, per the reasoning in "Problem" above and the parent program design's
  "What stays model work" list. Not deferred to a later sub-project; they are
  scoped out of Phase 6 entirely.
- Step 2's file-creation and template-copy steps (items 1-5), the
  interactive-question step (item 7), the GitHub Issues backlog-filing block,
  and the `{{...}}` residual-placeholder check (item 8) — untouched by this
  spec.
- Sub-projects C (Step 3c/3d migration mechanics) and E (Step 3/3b
  section-bucketing) — separate, unstarted scope.
