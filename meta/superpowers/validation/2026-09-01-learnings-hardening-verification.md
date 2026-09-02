# Validation log — LEARNINGS-generation hardening, end-to-end (v0.25.0)

**Branch:** `feat/learnings-generation-hardening`
**Spec:** `meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md`
**Plan:** `meta/superpowers/plans/2026-09-01-learnings-generation-hardening.md` (Task 7 / Finding F11)

This is the plan's own required end-to-end check: Tasks 1-6 hardened
`hooks/lib/candidate-extract.sh`, `hooks/lib/candidate-extract.jq`,
`hooks/lib/learnings-index.sh`, the three `learnings-index-*.awk` files, and
the command prose in `commands/end-session.md` / `commands/learning.md`,
but nothing had run them together as the real ritual would. This log
records that run, including a bug it found and fixed along the way.

---

## 0. A bug found and fixed during this verification

Before the results below are trustworthy, one thing had to be fixed:
`hooks/lib/require-script.sh` declared `local path="$1" expected="$2"
found` inside `require_script()`. `path` is a special zsh variable tied to
`$PATH`. Sourcing this file directly into a zsh shell and calling
`require_script` — exactly what `commands/end-session.md` and
`commands/learning.md` do via `source
"${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"` — overwrote `$PATH`
for the remainder of that function call, which broke the function's own
internal `sed` call two lines later. The version-string extraction
silently produced an empty string, the comparison against the expected
contract version never matched, and `require_script` returned 1 for
**every** script, every time, when the calling shell was zsh — reporting a
perfectly healthy, correctly-versioned install as "plugin cache is out of
date," and degrading the whole ritual to its `mode:"error"` fallback.

This was caught while running the scratch-repo mechanical checks in
Section 2 below, because this agent's own Bash tool spawns `/bin/zsh`, not
`/bin/bash`. It was not caught by the existing `require-script` smoke
suite because every one of that suite's assertions wraps the call in
`bash -c '...'` (originally to route around an unrelated DevBar
`grep`-wrapper issue), which happens to also route around this bug — no
test sourced the file directly into zsh without that wrapper.

**Fix:** renamed the local variable `path` → `script_path` throughout
`require_script()` (`hooks/lib/require-script.sh`), no other logic
changed. Added one assertion to
`meta/superpowers/validation/2026-09-01-require-script-smoke.zsh` that
sources the file directly into the smoke test's own zsh process (no
wrapper) and asserts both the correct return value and that `$PATH` is
unchanged afterward — closing the coverage gap so this can't regress
silently again. Committed separately, before this release commit:
`084097c fix: rename require_script's local 'path' var to avoid corrupting zsh's $PATH special`.

**Verification the fix actually closes the gap (not just superficial):**

```
$ zsh meta/superpowers/validation/2026-09-01-require-script-smoke.zsh
✓ matching contract version returns 0
✓ mismatched contract version returns 1
✓ mismatch sets a message
✓ missing script returns 1
✓ missing-script sets a message
✓ script with no version returns 1
✓ no-version sets a message
✓ sourced directly into zsh: matching contract version returns 0
✓ sourced directly into zsh: $PATH unchanged after require_script

Result: 9 passed, 0 failed

$ zsh -f -c '
source hooks/lib/require-script.sh
require_script hooks/lib/candidate-extract.sh 2
echo "ret=$?"
echo "MSG=[$SC_REQUIRE_SCRIPT_MSG]"
'
ret=0
MSG=[]

$ zsh -c '
before="$PATH"
source hooks/lib/require-script.sh
require_script hooks/lib/candidate-extract.sh 2 >/dev/null 2>&1
after="$PATH"
[[ "$before" == "$after" ]] && echo "PATH unchanged: OK" || echo "PATH CHANGED"
'
PATH unchanged: OK
```

Reverting the fix in a throwaway copy and re-running the new assertion
confirmed it fails without the fix (`FAIL ... contract version mismatch
(found 'none', need '1')`), and confirmed the `$PATH`-unchanged check alone
would *not* have caught the original bug (zsh's `local` restores `$PATH`
on function return, so the corruption is only visible from *inside* the
function — which is exactly why the return-value assertion, not the
`$PATH` check, is the one that matters here; the `$PATH` check is kept as
a defense-in-depth signal, not the primary guard).

All results in Sections 1-3 below were produced **after** this fix.

---

## 1. Smoke suites

```
$ for t in require-script candidate-extract learnings-index; do
    echo "=== $t"; zsh meta/superpowers/validation/2026-09-01-$t-smoke.zsh
  done

=== require-script    → 9 passed, 0 failed   (was 7/0 before adding the zsh-direct-source regression test above)
=== candidate-extract  → 30 passed, 0 failed
=== learnings-index    → 27 passed, 0 failed
```

All three: **0 failed.**

---

## 2. Step 2/3 (adapted): scratch-repo mechanical verification

### The adaptation, stated plainly

The plan's Step 2 asks to sync the working tree into
`$HOME/.claude/plugins/cache/talgolan/session-continuity`, start a fresh
interactive Claude Code session in a scratch repo, and run
`/session-continuity:end-session` there. This verification was carried
out by a non-interactive subagent with Bash/Read/Edit/Write and no way to
drive a second, separate interactive Claude Code session through a slash
command.

Inspected (read-only, not modified) the real plugin cache:

```
$ ls "$HOME/.claude/plugins/cache/talgolan/session-continuity"
0.15.1 0.16.0 0.17.0 0.18.0 0.19.0 0.20.0 0.21.0 0.21.1 0.22.0 0.23.0 0.24.0
```

The newest cached version is `0.24.0` — this branch's changes (Tasks 1-6,
and the fix in Section 0) are unreleased and exist in no cache directory
yet. This corroborates Finding F11 itself (the last real `end-session` ran
off a stale 0.22.0 cache) and is exactly why writing a new cache version
mid-verification, which other live sessions on this machine could pick up,
was avoided rather than attempted.

**What was done instead:** a scratch git repo (`/tmp/scn-e2e-scratch*`, not
part of this repo) with a `.session-continuity/` directory seeded from
this repo's own `.session-continuity/LEARNINGS.md`, and the **literal**
bash blocks that `commands/end-session.md` specifies for Step 2 (candidate
extraction) and its index-regeneration block (the same one
`commands/learning.md` Step 6 calls) were executed via Bash, unmodified,
against a real archived transcript from
`~/.claude/projects/-Users-tal-golan-active-development-TG-architect-workbench/`
(a copy with its mtime touched to "now" so it clears the 5-minute
staleness guard, which is correct, intended behavior for a live session
and would otherwise always report `mode:"unavailable"` against a
weeks-old archived file).

**What this proves:** the real mechanical contract — script invocations,
exit codes, `perf-log.sh` writes, contract-version checks — runs exactly
as the command prose specifies, executed directly in a zsh shell (this
agent's own Bash tool spawns `/bin/zsh`), with no `bash -c` workaround.

**What this does not prove:** it does not verify that an LLM reading the
command prose renders the candidates/checklist correctly to a user — no
LLM was in this loop, only the scripts. It does not exercise
`step-4-agent-active` (`hooks/lib/agent-active.sh`), which is explicitly
out of scope per the plan's "Not in this plan" section — Step 4 of the
ritual was never invoked in this verification, at all.

### Actual run (post-fix, directly in zsh, no `bash -c` wrapper)

```
$ echo $0
/bin/zsh

$ export CLAUDE_PLUGIN_ROOT=/Users/tal.golan/active_development/TG/session-continuity-plugin
$ export TRANSCRIPT=/tmp/scn-e2e-scratch2/fresh-transcript.jsonl   # copy of a real transcript, mtime touched to now
$ cd /tmp/scn-e2e-scratch2

$ source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
$ if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-extract.sh" 2; then
    CANDIDATE_JSON="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-extract.sh" "$TRANSCRIPT")"
  else
    echo "WARN $SC_REQUIRE_SCRIPT_MSG"
    CANDIDATE_JSON='{"mode":"error","candidates":[],"overflow":0,"detail":"candidate-extract.sh is missing or outdated."}'
  fi
$ echo "$CANDIDATE_JSON" | jq -c '{mode, count: (.candidates|length), overflow}'
{"mode":"transcript","count":2,"overflow":0}

$ cat .session-continuity/performance.log
{"ts":"2026-09-01T23:12:28Z","source":"command","name":"end-session","duration_s":0.396,"step":"step-2-transcript-extraction"}

$ source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
$ if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" 2; then
    bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" reindex .session-continuity/LEARNINGS.md
  fi
regenerated 15 bullet(s)

$ wc -l .session-continuity/LEARNINGS.md
367 .session-continuity/LEARNINGS.md   # unchanged from the seed copy — idempotent, non-empty, entry count preserved
```

### The four end-to-end invariants (plan Step 3)

```
$ grep -E 'step-2-transcript-extraction|step-4-agent-active|step-4-compute-only' .session-continuity/performance.log
{"ts":"2026-09-01T23:12:28Z","source":"command","name":"end-session","duration_s":0.396,"step":"step-2-transcript-extraction"}
```

| Invariant | Result |
|---|---|
| Exactly one `step-2-transcript-extraction` line, `duration_s` under 1.0 | **Holds.** One line, `duration_s: 0.396`. |
| One `step-4-agent-active` line with a plausible value | **Not exercised.** Step 4 of the ritual (`hooks/lib/agent-active.sh`) was never invoked in this adaptation — explicitly out of scope per the plan's "Not in this plan" section. Stating this as not-run, not as a pass. |
| Zero `step-4-compute-only` lines | **Holds, vacuously** — no Step 4 line of any kind is present, because Step 4 wasn't run. Not the same claim as "Step 4 ran and correctly chose `step-4-agent-active` over `step-4-compute-only`," which this adaptation cannot make. |
| Exactly one Bash call to `candidate-extract.sh`, no follow-up `jq` call against a temp file | **Holds.** One call: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-extract.sh" "$TRANSCRIPT"`, output held in `$CANDIDATE_JSON` and parsed directly. The `jq` invocation shown above is this verification's own display code, not part of the command prose — the actual ritual never re-filters `$CANDIDATE_JSON` per heuristic, which is what Finding 2 of the spec measured as seven round trips. |

---

## 3. Fresh replay against real transcripts (Task 5's harness, re-run now)

```
$ zsh meta/superpowers/validation/2026-09-01-candidate-replay.zsh \
    "$HOME/.claude/projects/-Users-tal-golan-active-development-TG-architect-workbench" 4

== 67fb9ff8-3f6c-4f07-84e9-1187937bdd50.jsonl (14M, 176ms)
  mode=transcript candidates=2 overflow=0
  [retry-burst] timeout 90 bun run --cwd ~/active_development/TG/architect-wo… — re-run 23 times with 123 file edits in between.
  [retry-burst] bun test 2>&1 | tail -15 — re-run 8 times with 152 file edits in between.

== 181c4ffb-8d3f-471e-bf60-7d2226704253.jsonl (11M, 232ms)
  mode=transcript candidates=3 overflow=0
  [retry-burst] bun test 2>&1 | tail -8 — re-run 31 times with 112 file edits in between.
  [error-recurrence] "In staged file docs2026-08-29-pino-transport-unification-design.md: makes a 'provenspike conclusive' claim but does not …" — recurred 4 times over 5 minutes.
  [retry-burst] bun test relay/tests/draftQueue.test.ts 2>&1 | tail -15 — re-run 3 times with 3 file edits in between.

== 0e2be32d-4061-4383-bd84-92d65ae4df9c.jsonl (8.4M, 206ms)
  mode=transcript candidates=5 overflow=2
  [fix-burst] fix(workbench): address caveman-review findings on the build-list/draft split — fix preceded by a 24-action investigation.
  [fix-burst] fix(workbench): move GROUP BY onto its own line in the Results pane — fix preceded by a 22-action investigation.
  [retry-burst] cd ~/active_development/TG/architect-workbench/server && bun … — re-run 9 times with 87 file edits in between.
  [retry-burst] bun test 2>&1 | tail -40 — re-run 8 times with 86 file edits in between.
  [revert] Reverted approach: git checkout -- docs/superpowers/smoke-tests/e2e-full-stack/.history.jsonl.

== 7ead1202-27ca-4a17-9f1b-3ecb3a3e33e8.jsonl (8.0M, 165ms)
  mode=transcript candidates=2 overflow=2
  [retry-burst] bun test 2>&1 | tail -20 — re-run 10 times with 72 file edits in between.
  [retry-burst] timeout 90 bun run --cwd ~/active_development/TG/architect-wo… — re-run 9 times with 66 file edits in between.
```

Identical to Task 5's original replay run (same 4 transcripts, same
candidate/overflow counts, same titles) — no regression from Tasks 5, 6,
or the Section 0 fix on top of Task 4's retuned heuristics.

### Before/after candidate counts

| Transcript | Before (pre-Task-4 heuristics) | After (this replay) |
|---|---|---|
| `0e2be32d` | Finding F4: "5 fix-bursts and `overflow: 8`" — every fix commit in the session fired the heuristic, one candidate title 20 lines long carrying the full commit body and `Co-Authored-By` trailer | **5 candidates, overflow: 2** — 2 fix-bursts (clean commit-subject titles, each requiring a preceding clustered investigation), 2 retry-bursts, 1 revert |
| `67fb9ff8`, `181c4ffb`, `7ead1202` | Findings F3/F5 describe the *mechanism*, not exact pre-fix counts for these specific transcripts: command identity collapsed on first line only (titles like `bun -e ' — investigated for 6 retries`), and error-recurrence could never fire (0 matches for `toolUseResult.stderr`/`^Error:` across 1,155 real tool results, Finding F5) | **2, 3, 2 candidates respectively, overflow 0/0/2** — no heredoc-fragment titles, no bookkeeping-command titles; `181c4ffb` now surfaces a real `error-recurrence` candidate (4 occurrences over 5 minutes) that could not fire before |

No exact pre-fix candidate count was ever captured for `67fb9ff8`,
`181c4ffb`, or `7ead1202` — the replay harness itself didn't exist until
Task 5, which ran after Task 4's retune, so there is no "before" replay
output for those three transcripts, only the qualitative failure modes in
Findings F3 and F5. Stating this gap plainly rather than inventing numbers
that were never measured.

---

## 4. Summary — what held, what didn't, what wasn't run

- **Held:** all three smoke suites, 0 failed each (require-script now 9/9
  after the Section 0 fix and its regression test).
- **Held:** the replay harness reproduces Task 5's original output exactly
  on 4 real transcripts — no regression.
- **Held, after the Section 0 fix:** the real Step 2 candidate-extraction
  block and the reindex block, run verbatim and directly in a zsh shell
  (no `bash -c` workaround), produce the correct `mode:"transcript"`
  result, the correct candidate count, exactly one
  `step-2-transcript-extraction` performance-log line under 1.0s, and a
  correct 15-bullet reindex.
- **Did not hold before the fix:** `require_script` sourced directly into
  zsh reported every correctly-versioned script as mismatched, due to the
  `local path=` / zsh-`$PATH` collision documented in Section 0. Fixed and
  re-verified; see Section 0 for the before/after evidence.
- **Not run at all (explicitly out of scope for this plan):** Step 4 of
  the ritual (`hooks/lib/agent-active.sh`, `step-4-agent-active` /
  `step-4-compute-only`). No claim is made about that mechanism here.
- **Not run at all (structural limit of a non-interactive subagent):** a
  live `/session-continuity:end-session` invocation inside an actual
  interactive Claude Code session reading the command prose and rendering
  output to a user. The mechanical layer underneath that prose is what
  was verified.
