# Determinism Phase 7 — Derived-Value Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a seventh commit-time content gate, `hooks/derived-value-gate.sh`,
that blocks new prompt text in `commands/*.md` instructing a model to compute a
duration, tally/vote on a count, eyeball-compare a claimed value against an
actual one, or print fixed reference text as if it were an instruction — the
reconciler-level enforcement of the determinism program's invariant. Closes
GitHub issue `#44`. Along the way, fixes `#54` (an un-migrated duplicate of
already-scripted majority-vote logic that the gate's own count pattern would
otherwise immediately flag) and corrects a stale `SECURITY.md` claim about
which gates are wired to which hook matcher.

**Architecture:** `derived-value-gate.sh` follows the exact idiom of the six
existing gates in `hooks/*.sh` (`occurrence-gate.sh`, `proven-gate.sh`, etc.):
source `hooks/lib/gate-common.sh`, define `gate_in_scope` (staged path matches
`commands/*.md`) and `gate_check` (content + path -> `deny` on a match), then
`gate_load; gate_is_commit || exit 0; gate_scan_staged gate_in_scope
gate_check; exit 0`. `gate_check` masks this gate's own escape-hatch line
(`gate_mask_escape`, so a doc that legitimately cites the escape label doesn't
self-condemn), then runs four independent phrase-pattern checks in sequence,
each denying with a category-specific reason on first hit. Escape hatch:
`Derived-value-gate: N/A — <reason>`.

**Pattern grounding (per the design doc's requirement that Phase 7's patterns
come from what earlier phases actually removed, not guesswork):** git history
was mined for the literal instruction phrasing Phases 0–6 deleted from
`commands/*.md`. Four categories have solid grounded hits and ship in v1:

1. **Duration** — the four near-identical epoch-subtraction blocks Phase 3
   replaced with `perf-log.sh`: `date -u -j -f`, `date -u -d "`, and the
   `$(( ..._epoch - ..._epoch` arithmetic idiom.
2. **Count/tally** — Phase 6-B's majority-vote prose: `cardinality`, `Pin to
   the count seen in`, `RETRIES count`, `across <N> runs` (from the spread
   report "saw 1162 / 1161 / 1162 across 3 runs").
3. **Compare claimed-vs-actual** — Phase 6-A's eyeball-diff prose: `match(es)
   the ... output above`, `disagrees with the recorded`, `does ... match ...
   above`.
4. **Print-verbatim / reference-as-instruction** — Phase 2/4's fixed-text
   leakage: `not instructions to you`, `Illustrative only`, `List every
   file...do not summarize`, `Never omit it. Never replace it with
   paraphrased prose`, `Always emit ... exactly:`.

A fifth category from issue `#44`'s scope — **renumber** — is **dropped from
v1**. There is no real removed instance to ground it on (Phase 6 sub-projects
C/E, which would have produced one, were explicitly deprioritized rather than
shipped — see the program design doc's Phase 6 entry). Worse, a bare
`renumber(ing)?` word-anchor was checked against the current repo and hits
three real lines in `learning.md`, all of which state entries are *never*
renumbered (a stability guarantee, the opposite of a violation) — shipping it
would deny any future commit touching that file. Filed as a follow-up: this
category ships only once a real removed instance exists to anchor it on.

**Sequencing decision:** the count/tally pattern (`Pin to the count seen in`)
also hits a live, currently-shipped line — `end-session.md`'s "Drift check"
section still hand-derives the exact majority-vote rerun that Phase 6-B
scripted into `hooks/lib/test-count-rerun.sh`/`.jq` for `primer.md` (filed as
`#54`, found during Phase 6-B's own review, explicitly out of that plan's
scope). Fixing `#54` is Task 1 of this plan, before the gate is wired in
(Task 3) — otherwise every future commit touching `end-session.md`, including
unrelated ones, would deny until someone adds an escape-hatch line.

**Tech Stack:** bash (macOS default, no bash-4 features — matches every
existing gate), zsh for the smoke-test harness (matches
`meta/superpowers/validation/lib/gate-test-common.zsh`'s existing convention),
`git`, `grep -E`.

**Spec:** `meta/superpowers/specs/2026-09-02-determinism-program-design.md`
(Phase 7 entry, lines 242–249; the "Six categories of avoidable work" section,
lines 64–112, is the source the mined phrases above are grounded against). No
separate Phase-7-specific spec file exists — the design was brainstormed and
approved in chat this session; the grounding detail above is the durable
record of that design, since there's nowhere else for it to live once this
plan itself points here.

## Global Constraints

- Every new gate check must be traceable to an actual diff (cite commit hash +
  file) or explicitly labeled as ungrounded — no guessed patterns ship without
  that label. (This is why `renumber` is dropped, not shipped ungrounded.)
- Escape hatch label: `Derived-value-gate: N/A — <reason>` (decoration
  tolerant, per `gate_has_escape`'s existing convention — backticks/asterisks
  stripped before matching).
- `gate_in_scope` matches `commands/*.md` at repo root only (the seven files:
  `end-session.md`, `primer.md`, `learning.md`, `doctor.md`, `help.md`,
  `spike-check.md`, `update.md`) — not nested `commands/` directories
  elsewhere, matching how `occurrence-gate.sh` scopes to `.session-continuity/
  LEARNINGS.md` rather than any `LEARNINGS.md`.
- No new external dependencies. Pure `grep -E`, no `jq`, no `awk` beyond what
  `gate-common.sh` already uses.
- Before wiring the gate into `hooks.json` (Task 3), the real, current content
  of all seven `commands/*.md` files must pass it clean (zero denials) — the
  gate ships enforcing an invariant the repo already satisfies, not one it's
  about to start violating.

---

**Gate escape hatches (for this document itself, not the code it
describes):** this plan names several existing gates by filename and quotes
their trigger vocabulary, which trips two of them on their own scope
(`*/plans/*.md`) purely by self-reference — the documented failure mode for
grep-based gates scanning a document about themselves (this repo's own
`LEARNINGS.md` entry 7). Per that entry's own fix, the right response is the
escape hatch, not loosening the gate:

> **Proven-gate:** N/A — this plan names `proven-gate.sh` by filename only;
> it makes no proven/verified claim about tested work.
> **Evidence-gate:** N/A — this plan's smoke-test fixtures call the existing
> `gt_cleanup` test-teardown helper; there is no smoke run here needing
> preserve-before-teardown language.
> **Backend-parity:** N/A — this plan names `backend-parity-gate.sh` by
> filename only; it does not frame anything as multi-backend.

---

## Task 1: Fix `#54` — converge `end-session.md`'s drift-check rerun onto `test-count-rerun.sh`

**Files:**
- Modify: `commands/end-session.md:223-245` (the hand-derived retry/pin-to-
  majority prose) and `commands/end-session.md:281` (the refresh flow's
  reference to "after the 3× retry")

**Interfaces:**
- Consumes: `hooks/lib/test-count-rerun.sh` (existing, unmodified — usage:
  `test-count-rerun.sh <project-dir> <last-primer-commit>`, prints
  `KEY=value` lines: `TEST_CMD`, `RECORDED_COUNT`, `MODE`
  (`skip|no-command|no-count|run`), `RETRIES`, `OBSERVED`, `UNPARSEABLE`,
  `DRIFT`, `PINNED_COUNT`, `SPREAD`), `hooks/lib/require-script.sh`'s
  `require_script` function (existing, already used identically in
  `commands/primer.md:309-316`).

This task has no automated test of its own — it's a markdown prompt-text
edit, not code. Its "test" is: (a) a byte-diff confirming only the intended
lines changed, (b) confirming the file still parses as valid markdown (no
broken code fences), and (c) Task 2's gate-pattern sanity check (later in this
plan) finding zero hits in the corrected file.

- [ ] **Step 1: Replace the hand-derived retry prose**

In `commands/end-session.md`, find this exact block (currently lines
223–245):

```markdown
If the primer has a test-counts section, decide whether to re-run it (logic
lives in Step 5.3 of `commands/primer.md` — summarized here). Do this as
**one Bash call**, timed, tracking a `RETRIES` count (0 if skipped or the
first run matched, else the number of *extra* runs actually executed
beyond the first):

- **Skip the rerun** if the commit list already computed above
  (`<last-primer-commit>..HEAD`) contains no file outside
  `.session-continuity/` — no source or test file changed, so the recorded
  count cannot have drifted.
- **Otherwise, run the test command(s) once.** Matches the primer's
  recorded count → stop, no drift on this axis.
- **Only if that first run disagrees**, retry up to 2 more times (3 total)
  to rule out flakiness. Pin to the count seen in ≥2 of 3 runs — if that
  pinned count matches the primer, the first run was the flake and there's
  no drift; if it still differs, report drift with the pinned count. If all
  three runs disagree with each other, surface the spread (`saw 1162 / 1161
  / 1162 across 3 runs — using 1162; suite is unstable`) instead of
  silently picking one.

Common cases stay cheap: zero test runs when nothing relevant changed, one
run when the count still holds, three only when there's an actual
discrepancy to resolve.
```

Replace it with (mirrors `commands/primer.md:304-345` exactly — same script,
same output contract, same presentation-per-`MODE` rules — so both call sites
stay in lockstep by construction):

```markdown
Run the shared test-count rerun script — the same one `commands/primer.md`
Step 4 item 3 calls, so both commands stay in lockstep — timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
LAST_PRIMER_COMMIT=$(git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md)
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/test-count-rerun.sh" 1; then
  RERUN_OUTPUT="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/test-count-rerun.sh" . "$LAST_PRIMER_COMMIT" 2>&1)"
  RERUN_STATUS=$?
else
  RERUN_OUTPUT="$SC_REQUIRE_SCRIPT_MSG"
  RERUN_STATUS=1
fi
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
RETRIES=$(printf '%s' "$RERUN_OUTPUT" | awk -F= '/^RETRIES=/{print $2}')
echo "$RERUN_OUTPUT"
echo "RERUN_STATUS=$RERUN_STATUS"
```

Run this as the **same Bash tool call** as the pre-existing perf-log block a
few lines below ("At the end of this Bash call (whichever branch above
ran):", unmodified by this task) — that block reads `$_PERF_DURATION` and
`$RETRIES` from this one. A separate tool invocation would see both empty
and silently log a wrong duration/retries.

**If `RERUN_STATUS` is nonzero, or `$RERUN_OUTPUT` has no `MODE=` line:**
report `$RERUN_OUTPUT` to the user and fall back to `TBD` for this axis —
never fabricate a drift verdict from a failed script.

**Otherwise**, report per `MODE`:
- `skip` — no relevant file changed; say nothing (matches today's silent
  skip).
- `no-command` — no test command recorded; nothing to check.
- `no-count`, `RETRIES=0`, `DRIFT=0` always — nothing recorded yet to
  compare against; no report needed on this axis.
- `run` with `DRIFT=0` — the count held (whether on the first try or after
  majority-vote confirmation); no report needed.
- `run` with `DRIFT=1` — report drift using `PINNED_COUNT` (`"Test count
  drifted: recorded <RECORDED_COUNT>, now <PINNED_COUNT> (confirmed over
  <RETRIES>+1 runs)."`).
- `run` with `SPREAD=1` — report instability using the comma-joined
  `OBSERVED` values (`"Test suite is unstable: saw <OBSERVED, /-joined>
  across 3 runs."`), not a drift verdict.
- `run` with `UNPARSEABLE=1` and no `PINNED_COUNT` — report `"Test command
  produced no parseable count after <RETRIES>+1 attempts."`
```

(The nested code fence above is literal — `end-session.md` already contains
markdown-inside-markdown at every other Bash-call step in this file; match
the existing fence style around it exactly rather than introducing a new
convention.)

- [ ] **Step 2: Fix the refresh flow's stale reference to manual retries**

In `commands/end-session.md`, find (currently line 281, inside "### Refresh
flow"):

```markdown
2. If the primer has a test-counts section and the counts changed (after the 3× retry), update them to match current output.
```

Replace with:

```markdown
2. If `MODE=run` and `DRIFT=1` (per the test-count rerun script's output
   above), update the test-counts section to `PINNED_COUNT`.
```

- [ ] **Step 3: Verify the file still renders correctly**

Run: `grep -c '^```' commands/end-session.md`
Expected: an even number (every fence opened is closed). Compare against the
count before this edit (`git show HEAD:commands/end-session.md | grep -c
'^```'`) — the two edits above replace one fenced block with one fenced
block and touch no other fence, so the count should be unchanged.

- [ ] **Step 4: Confirm the removed phrases are gone**

Run (as two independent checks — the original prose wraps "logic" and
"lives in Step 5.3" across a markdown line break, so a single pattern
spanning both words would never match even before this fix and would prove
nothing):

```bash
grep -inE 'Pin to the count seen in|Step 5\.3|after the 3× retry' commands/end-session.md
```
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add commands/end-session.md
git commit -m "fix: end-session.md's drift check now calls test-count-rerun.sh (closes #54)"
```

## Task 2: `hooks/derived-value-gate.sh` + smoke test

**Files:**
- Create: `hooks/derived-value-gate.sh`
- Create: `meta/superpowers/validation/2026-09-09-derived-value-gate-smoke.zsh`

**Interfaces:**
- Consumes: `hooks/lib/gate-common.sh`'s `gate_load`, `gate_is_commit`,
  `gate_scan_staged`, `gate_has_escape`, `gate_mask_escape`, `deny` (all
  existing, unmodified). `meta/superpowers/validation/lib/gate-test-common.zsh`'s
  `gt_make_repo`, `gt_stage`, `gt_commit_payload`, `gt_run`, `gt_is_deny`,
  `gt_cleanup` (all existing, unmodified).
- Produces: `hooks/derived-value-gate.sh`, an executable script taking the
  same stdin-JSON payload shape as the other six gates. No other file
  consumes this in this plan (Task 3 wires it into `hooks.json`).

- [ ] **Step 1: Write the failing smoke test**

Create `meta/superpowers/validation/2026-09-09-derived-value-gate-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++)); else print -r -- "FAIL - $1 (want $2 got $3)"; ((fail++)); fi }
verdict() { gt_is_deny "$1" && print deny || print allow; }

# 1. duration: epoch-subtraction idiom -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/end-session.md" $'prior_epoch="$(date -u -j -f \'%Y-%m-%dT%H:%M:%SZ\' "$prior_ts" +%s)"\n_DUR="$(( now_epoch - prior_epoch ))"\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "epoch subtraction -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 2. count/tally: majority-vote-by-eye phrase -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/primer.md" $'Pin to the count seen in 2 of 3 runs.\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "pin-to-count phrase -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 3. compare claimed-vs-actual: eyeball-diff phrase -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/doctor.md" $'Does the git log --oneline -5 block inside it match the git log --oneline -5 output above?\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "does-X-match-Y-above -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 4. print-verbatim: reference-doc-as-instruction phrase -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/learning.md" $'Never omit it. Never replace it with paraphrased prose.\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "never-paraphrase phrase -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 5. safe: names a script that owns the computation -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/learning.md" $'Run `bash hooks/lib/learnings-index.sh report`, which prints `MAX <n>`. Use that value.\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "delegates to named script -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 6. escape hatch (decorated) -> allow even with a violation present
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/end-session.md" $'> **Derived-value-gate:** N/A — quoting the old prose in a changelog entry.\nPin to the count seen in 2 of 3 runs.\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "decorated escape -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 7. out-of-scope path (not commands/*.md) -> allow even with a violation present
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/notes.md" $'Pin to the count seen in 2 of 3 runs.\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "out-of-scope path -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 8. dot-prefixed scratch file under commands/ -> allow (skipped)
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/.scratch.md" $'Pin to the count seen in 2 of 3 runs.\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "scratch file skipped -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 9. sanity: the real, current commands/*.md content (post-#54-fix) is clean
repo="$(gt_make_repo)"
REPO_ROOT="${HERE:h:h:h}"
for f in "$REPO_ROOT"/commands/*.md; do
  gt_stage "$repo" "commands/${f:t}" "$(cat "$f")"
done
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "real commands/*.md content -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"; [[ $fail -eq 0 ]]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zsh meta/superpowers/validation/2026-09-09-derived-value-gate-smoke.zsh`
Expected: every case FAILs (or the run errors) — `hooks/derived-value-gate.sh`
doesn't exist yet, so `gt_run` can't find it.

- [ ] **Step 3: Write minimal implementation**

Create `hooks/derived-value-gate.sh`:

```bash
#!/usr/bin/env bash
# derived-value-gate.sh — commit-time content gate (session-continuity plugin,
# Determinism Phase 7, closes #44).
#
# Fires before Bash(git commit *). For each staged commands/*.md file, BLOCKS
# prompt text instructing a model to (1) compute a duration by hand, (2)
# tally/vote on a count by eye, (3) eyeball-compare a claimed value against an
# actual one, or (4) print fixed reference text as if it were an instruction —
# the four defect classes Phases 0-6 of the determinism program removed. See
# meta/superpowers/specs/2026-09-02-determinism-program-design.md and
# meta/superpowers/plans/2026-09-09-determinism-phase-7-derived-value-gate.md
# for the grounding (which real diff each pattern below is anchored to).
#
# A fifth class named in #44 — "renumber" — is deliberately NOT checked here:
# no real removed instance exists to ground a pattern on (see the plan above),
# and a naive word-anchor false-positives on learning.md's own anti-renumber
# stability guarantees.
#
# Escape: `Derived-value-gate: N/A — <reason>`.
set -euo pipefail
# shellcheck disable=SC1091 # dynamically-resolved path; gate-common.sh is shellcheck-clean standalone
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_in_scope() {
  case "$1" in commands/*.md) return 0 ;; *) return 1 ;; esac
}

# Each check takes (masked-content, path) and calls deny (exits) on a hit.
# Citation format matches occurrence-gate.sh's own: grep -n gives "N:match".

_dvg_deny() {  # <path> <label> <hit "N:text"> <explanation>
  local path="$1" label="$2" hit="$3" explanation="$4" line matched
  line="${hit%%:*}"
  matched="$(printf '%s' "${hit#*:}" | cut -c1-120)"
  deny "In staged file $path, line $line: $label (\"$matched\"). $explanation Add: Derived-value-gate: N/A — <reason> (decoration fine)."
}

_dvg_check_duration() {
  local content="$1" path="$2" hit
  hit="$(printf '%s' "$content" | grep -inoE 'date -u -j -f|date -u -d "|\$\(\([^)]*_epoch[^)]*-[^)]*_epoch' | head -1)"
  [ -n "$hit" ] || return 0
  _dvg_deny "$path" "instructs a model to compute a duration by hand (epoch subtraction)" "$hit" \
    "A script owns duration math — see hooks/lib/perf-log.sh's since subcommand."
}

_dvg_check_count() {
  local content="$1" path="$2" hit
  hit="$(printf '%s' "$content" | grep -inoE 'cardinality|Pin to the count seen in|RETRIES count|across[[:space:]]+[0-9]+[[:space:]]+runs' | head -1)"
  [ -n "$hit" ] || return 0
  _dvg_deny "$path" "instructs a model to tally or vote on a count by eye" "$hit" \
    "A script owns cardinality/majority-vote math — see hooks/lib/token-overlap.sh and hooks/lib/test-count-rerun.sh."
}

_dvg_check_compare() {
  local content="$1" path="$2" hit
  hit="$(printf '%s' "$content" | grep -inoE 'match(es)?[[:space:]]+the[^.]*output above|disagrees with the recorded|does[^.]*match[^.]*above' | head -1)"
  [ -n "$hit" ] || return 0
  _dvg_deny "$path" "instructs a model to eyeball-compare a claimed value against an actual one" "$hit" \
    "A script owns the comparison (an awk range extract plus diff, or the same shape as hooks/lib/primer-detect.sh)."
}

_dvg_check_verbatim() {
  local content="$1" path="$2" hit
  hit="$(printf '%s' "$content" | grep -inoE 'not instructions to you|Illustrative only|List every file[^.]*do not summarize|Never omit it\. Never replace it with paraphrased prose|Always emit[^.]*exactly:' | head -1)"
  [ -n "$hit" ] || return 0
  _dvg_deny "$path" "ships fixed reference text or a determinism-compensating instruction as prompt prose" "$hit" \
    "Fixed output belongs in the script that computes the values around it (skills/session-continuity/REFERENCE.md or a spec, not a command body)."
}

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_check() {
  local content="$1" path="$2" masked
  if gate_has_escape "$content" "Derived-value-gate"; then return 0; fi
  masked="$(gate_mask_escape "$content" "Derived-value-gate")"
  # Fixed priority order below (duration > count > compare > verbatim): a
  # line tripping two categories at once is cited under the first one
  # checked, not necessarily the earliest line in the file. Harmless — one
  # escape hatch clears every category — but worth knowing when reading a
  # denial that names a category other than the one you expected.
  _dvg_check_duration "$masked" "$path"
  _dvg_check_count "$masked" "$path"
  _dvg_check_compare "$masked" "$path"
  _dvg_check_verbatim "$masked" "$path"
}

gate_load
gate_is_commit || exit 0
gate_scan_staged gate_in_scope gate_check
exit 0
```

Run: `chmod +x hooks/derived-value-gate.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `zsh meta/superpowers/validation/2026-09-09-derived-value-gate-smoke.zsh`
Expected: `pass=9 fail=0`.

If case 9 (the real-file sanity check) fails, do not weaken the pattern to
force a pass — that means either Task 1 didn't fully remove the offending
phrase, or a pattern is broader than intended. Re-read the denial's cited
line and fix the root cause (the command file, or the pattern's specificity)
before re-running.

- [ ] **Step 5: Commit**

```bash
git add hooks/derived-value-gate.sh meta/superpowers/validation/2026-09-09-derived-value-gate-smoke.zsh
git commit -m "feat: add derived-value-gate.sh, the Phase 7 commit-time content gate"
```

## Task 3: Wire into `hooks.json`

**Files:**
- Modify: `hooks/hooks.json`

**Interfaces:**
- Consumes: `hooks/derived-value-gate.sh` (Task 2), `hooks/lib/perf-wrap.sh`
  (existing, unmodified).

- [ ] **Step 1: Add the gate to the `Bash` matcher group**

In `hooks/hooks.json`, inside the `PreToolUse` → `matcher: "Bash"` array,
add a new entry immediately after the `occurrence-gate.sh` line (so the
Bash-matcher array reads: `pre-commit-check`, `flaky-gate`, `proven-gate`,
`smoke-gate`, `evidence-gate`, `backend-parity-gate`, `occurrence-gate`,
`derived-value-gate`, `learnings-surface`):

```json
          { "type": "command", "if": "Bash(git commit *)", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh derived-value-gate.sh" },
```

- [ ] **Step 2: Validate JSON syntax**

Run: `python3 -m json.tool hooks/hooks.json >/dev/null && echo OK`
Expected: `OK`.

- [ ] **Step 3: Re-run the smoke test (regression check on the wiring)**

Run: `zsh meta/superpowers/validation/2026-09-09-derived-value-gate-smoke.zsh`
Expected: `pass=9 fail=0` (unchanged — this step doesn't touch the gate's own
logic, only its registration).

- [ ] **Step 4: Sanity-check against this repo's own real staged state**

Run:
```bash
git add -A
bash hooks/derived-value-gate.sh <<<"$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$(pwd)")"
```
Expected: no output (silent allow) — confirms the gate, wired exactly as it
will run in production, denies nothing against the real, currently-staged
repo state. Run `git reset` afterward to unstage (this step is a dry run,
not an actual commit).

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: wire derived-value-gate.sh into hooks.json"
```

## Task 4: Doc pointers, `SECURITY.md` correction, changelog, version bump

**Files:**
- Modify: `SECURITY.md:39-42`
- Modify: `meta/superpowers/specs/2026-09-02-determinism-program-design.md:242-249`
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Correct `SECURITY.md`'s stale hook-matcher-scope section**

In `SECURITY.md`, find (currently lines 39–42):

```markdown
- **Hook matcher scope.** `hooks/hooks.json` registers one `SessionStart` hook and seven `PreToolUse` hooks, split across two matcher groups:
  - `matcher: "Bash"` — `pre-commit-check.sh` and `flaky-gate.sh`'s commit-message check both carry a per-hook `if: Bash(git commit *)` filter, so they only spawn on `git commit`. `learnings-surface.sh` has no `if` filter in this group — it spawns on every `Bash` call, not just commits, since its job is to match the imminent command text against LEARNINGS trigger regexes.
  - `matcher: "Write|Edit"` — `learnings-surface.sh`, `smoke-gate.sh`, `proven-gate.sh`, `occurrence-gate.sh`, `evidence-gate.sh`, `flaky-gate.sh`, and `backend-parity-gate.sh` all spawn on every `Write`/`Edit` call. Each self-scopes internally (by file path pattern — plan files, spec files, or `LEARNINGS.md`) and exits 0 immediately for files outside its scope, so the broad matcher is narrowed in-script rather than in `hooks.json`.
  - Five of these seven (`smoke-gate`, `proven-gate`, `occurrence-gate`, `evidence-gate`, `backend-parity-gate`, and `flaky-gate`'s Write/Edit path) can return `permissionDecision:"deny"` and block the tool call — the others (`session-start.sh`, `pre-commit-check.sh`, `learnings-surface.sh`) are non-blocking, `permissionDecision:"allow"` or silent-exit only.
```

Replace with (matches the real, current `hooks.json` after Task 3 — verify
the hook count against `grep -c '"type"' hooks/hooks.json` before committing,
since a future gate addition will make this stale again):

```markdown
- **Hook matcher scope.** `hooks/hooks.json` registers one `SessionStart` hook (`session-start.sh`), one `UserPromptSubmit` hook (`prompt-intercept.sh`), and ten `PreToolUse` hooks, split across two matcher groups:
  - `matcher: "Bash"` — nine hooks. Eight carry a per-hook `if: Bash(git commit *)` filter (`pre-commit-check.sh`, `flaky-gate.sh`, `proven-gate.sh`, `smoke-gate.sh`, `evidence-gate.sh`, `backend-parity-gate.sh`, `occurrence-gate.sh`, `derived-value-gate.sh`) so they only spawn on `git commit`. `learnings-surface.sh` has no `if` filter — it spawns on every `Bash` call, not just commits, since its job is to match the imminent command text against LEARNINGS trigger regexes.
  - `matcher: "Write|Edit"` — `learnings-surface.sh` only.
  - Seven of the nine `Bash`-matcher hooks are content gates that can return `permissionDecision:"deny"` and block the tool call: `flaky-gate`, `proven-gate`, `smoke-gate`, `evidence-gate`, `backend-parity-gate`, `occurrence-gate`, and `derived-value-gate`. The rest (`pre-commit-check.sh`, `learnings-surface.sh`, `session-start.sh`, `prompt-intercept.sh`) are non-blocking, `permissionDecision:"allow"` or silent-exit only.
```

- [ ] **Step 2: Collapse the program design doc's Phase 7 entry to a pointer**

In `meta/superpowers/specs/2026-09-02-determinism-program-design.md`, find
(currently lines 242–249):

```markdown
**Phase 7 `#44` — the gate that keeps it true.** A commit-time content gate on
staged `commands/*.md` that blocks prompt text instructing a model to count,
tally, renumber, compute a duration, compare a claimed value against an
actual one, or print fixed text verbatim, with the usual
`<Gate-name>: N/A — <reason>` escape. This is the reconciler-level enforcement
of the invariant; every other phase is a one-time cleanup that decays without
it. Ships last because the gate's pattern list should be written from what the
earlier phases actually removed, not guessed beforehand.
```

Replace with (matching the "entry format" convention this doc states at
lines 154–159 — once a phase has its own artifact, its entry collapses to a
pointer):

```markdown
**Phase 7 `#44` — the gate that keeps it true.** Shipped as
`hooks/derived-value-gate.sh`, covering four of the five originally-scoped
classes (renumber dropped — no grounded removal exists to anchor it on).
Also fixed `#54` (an un-migrated duplicate of Phase 6-B's majority-vote logic
that the gate's own count pattern would otherwise have immediately flagged).
Plan: `meta/superpowers/plans/2026-09-09-determinism-phase-7-derived-value-gate.md`.
```

- [ ] **Step 3: Bump the version and changelog**

In `.claude-plugin/plugin.json`, change `"version": "0.34.0"` to
`"version": "0.35.0"`.

In `CHANGELOG.md`, insert a new entry directly above the existing
`## [0.34.0] — 2026-09-09` heading:

```markdown
## [0.35.0] — 2026-09-09

### Added
- **A seventh commit-time content gate, `hooks/derived-value-gate.sh`.**
  Blocks new `commands/*.md` prompt text that instructs a model to compute a
  duration by hand, tally/vote on a count by eye, eyeball-compare a claimed
  value against an actual one, or print fixed reference text as if it were
  an instruction — the reconciler-level enforcement of the determinism
  program's invariant (every other phase is a one-time cleanup that decays
  without this). Escape hatch: `Derived-value-gate: N/A — <reason>`.

### Fixed
- **`end-session.md`'s drift check now calls `test-count-rerun.sh`** instead
  of hand-deriving the same majority-vote rerun Phase 6-B already scripted
  for `primer.md` — the two command files were computing the identical
  algorithm two different ways.
```

- [ ] **Step 4: Verify the doc edits are internally consistent**

Run: `grep -n '"version"' .claude-plugin/plugin.json` — confirm `0.35.0`.
Run: `head -8 CHANGELOG.md` — confirm the new entry is above `[0.34.0]`.

Run (counts per event type from the real JSON structure, not by eyeballing
quote characters — `grep -c '"type"'` over the whole file would also catch
`SessionStart` and `UserPromptSubmit`, which is exactly the kind of
by-eye-miscount this plan exists to stop making):

```bash
python3 -c "
import json
d = json.load(open('hooks/hooks.json'))['hooks']
print('SessionStart:', sum(len(g['hooks']) for g in d.get('SessionStart', [])))
print('UserPromptSubmit:', sum(len(g['hooks']) for g in d.get('UserPromptSubmit', [])))
print('PreToolUse:', sum(len(g['hooks']) for g in d.get('PreToolUse', [])))
"
```
Expected: `SessionStart: 1`, `UserPromptSubmit: 1`, `PreToolUse: 10` — matches
the counts named in the `SECURITY.md` edit above.

- [ ] **Step 5: Close out the GitHub issues and commit**

```bash
git add SECURITY.md meta/superpowers/specs/2026-09-02-determinism-program-design.md CHANGELOG.md .claude-plugin/plugin.json
git commit -m "docs: Phase 7 doc pointers, SECURITY.md correction, changelog, and version bump"
gh issue close 44 --reason completed
gh issue close 54 --reason completed
```
