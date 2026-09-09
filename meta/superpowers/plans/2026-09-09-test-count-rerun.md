# Determinism Phase 6, sub-project B — `test-count-rerun.sh`/`.jq` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `commands/primer.md` Step 4 item 3 (the test-count majority-vote rerun that runs during Refresh mode) with one script, `hooks/lib/test-count-rerun.sh`, that reads the recorded test count back from `PROJECT_CONTEXT.md`, decides whether/how many times to rerun the test command, and prints a definitive `MODE`/`DRIFT`/`PINNED_COUNT`/`SPREAD` verdict.

**Architecture:** `test-count-rerun.sh` (bash, I/O — parses `PROJECT_CONTEXT.md`'s `TEST_COMMAND_SUMMARY` line, runs the git-diff skip check, executes the test command 0-3 times per the existing match-then-retry rule) hands the collected observations to `test-count-rerun.jq` (pure decision function — no I/O, fixture-testable with synthetic JSON) for the majority-vote/drift/spread computation. The `.jq` filter's vote algorithm is mode-agnostic: it derives every output field generically from `{mode, recorded, observed}`, so `skip`/`no-command`/`no-count`'s "always empty/zero" outputs fall out of the same generic logic applied to a 0- or 1-element `observed` array, rather than needing special-cased branches per mode.

**Tech Stack:** Bash, `jq` (already a hard dependency across this plugin), zsh (smoke tests only).

**Spec:** `meta/superpowers/specs/2026-09-09-test-count-rerun-design.md`. That spec was corrected once during writing (caveman-review found the `run-unparseable` mode conflated "dispatch mode" with "internal outcome," an underspecified majority rule when a run is unparseable, an undocumented `N`-vs-`M` comparison choice, and a testing-list gap) — all four fixes are already folded into the spec text; this plan implements it as it now reads.

## Global Constraints

- `test-count-rerun.sh` and `test-count-rerun.jq` both carry a `# CONTRACT_VERSION=1` header. `commands/primer.md` calls the `.sh` through `require_script`, exactly like `primer-detect.sh` already is in Step 1 and `primer-status.sh` in Step 5. `test-count-rerun.sh` itself checks its sibling `.jq`'s `CONTRACT_VERSION` before invoking it, exactly like `primer-detect.sh` does.
- **No fabricated verdict on operational failure.** jq missing, the `.jq` filter missing/version-mismatched, or `PROJECT_CONTEXT.md` unreadable each print one diagnostic line to stderr and exit nonzero with no `MODE=` line on stdout. Unlike `primer-detect.sh`, a wrong guess here is not destructive (no `git mv`/`git rm` downstream), but `commands/primer.md` still must not invent a drift verdict on failure — it falls back to `TBD`/manual reporting.
- **Never invent a test count.** `RECORDED_COUNT`/`OBSERVED` entries are either a real parsed integer or empty/`null` — this plan changes *how* the rerun decision is computed, never invents a count `PROJECT_CONTEXT.md` or a test run didn't actually produce.
- All vote/drift/spread decision logic lives in `test-count-rerun.jq`; `test-count-rerun.sh`'s only jobs are parsing `PROJECT_CONTEXT.md`, the skip check, and running the test command the right number of times.
- Only `<TEST_CMD>`'s pass count (`N`) round-trips for drift comparison. The fail count (`M`), when present in `PROJECT_CONTEXT.md`'s `N pass / M fail` line, is not parsed or compared by this script — an inherited limitation from the current prose, not introduced here (see spec's "Recorded-count format" section).
- Do not touch `commands/primer.md` Step 4 items 1, 2, 4, 5, 6, 7, 8, or Step 2's inline placeholder-derivation prose (sub-project D's scope) — this plan only replaces item 3.
- Do not touch `hooks/lib/primer-detect.sh`/`.jq` (sub-project A, already shipped) or `hooks/lib/token-overlap.sh`/`.jq` (Phase 5, already shipped) — unrelated to this plan.

---

## File Structure

| File | Responsibility |
|---|---|
| `hooks/lib/test-count-rerun.jq` (new) | Pure decision function: given `{mode, recorded, observed}`, computes `RETRIES`, `UNPARSEABLE`, `DRIFT`, `PINNED_COUNT`, `SPREAD` and prints the full `KEY=value` block (including pass-through fields). No I/O. |
| `hooks/lib/test-count-rerun.sh` (new) | I/O: parses `PROJECT_CONTEXT.md`'s Test-expectations section for `TEST_CMD`/`RECORDED_COUNT`, runs the git-diff skip check, executes `TEST_CMD` 0-3 times per mode, invokes the filter. |
| `commands/primer.md` (modified) | Step 4 item 3's ~8-line prose collapses to one script call plus a short per-`MODE` reporting table. |
| `meta/superpowers/validation/2026-09-09-test-count-rerun-smoke.zsh` (new) | Smoke test: `.jq`-only fixtures (synthetic JSON, no git/subprocess) plus `.sh` integration fixtures (scratch git repos with a fake, invocation-counted `TEST_CMD`) plus operational-failure cases. |
| `meta/superpowers/specs/2026-09-02-determinism-program-design.md` (modified) | Phase 6 entry notes sub-project B shipped; C/D/E remain listed as pending. |
| `CHANGELOG.md` (modified) | New version entry. |
| `.claude-plugin/plugin.json` (modified) | Version bump `0.32.0` → `0.33.0`. |

---

### Task 1: `hooks/lib/test-count-rerun.jq` + `hooks/lib/test-count-rerun.sh`

**Files:**
- Create: `hooks/lib/test-count-rerun.jq`
- Create: `hooks/lib/test-count-rerun.sh`
- Test: `meta/superpowers/validation/2026-09-09-test-count-rerun-smoke.zsh`

**Interfaces:**
- Produces: `bash test-count-rerun.sh <project-dir> <last-primer-commit>`. Prints `KEY=value` lines to stdout, ending in the fields listed in the spec's Output contract (`TEST_CMD`, `RECORDED_COUNT`, `MODE`, `RETRIES`, `OBSERVED`, `UNPARSEABLE`, `DRIFT`, `PINNED_COUNT`, `SPREAD`). Exits 0 on success. On operational failure, prints one diagnostic line to stderr and exits 1 with **no** `MODE=` line anywhere in stdout.
- Consumes: `jq` (hard dependency), `git`, `timeout` (GNU coreutils — already assumed elsewhere in this plugin, e.g. Step 2's init test run).

**Extraction-format note (read before writing tests):** `PROJECT_CONTEXT.md`'s `{{TEST_COMMAND_SUMMARY}}` placeholder is seeded by Step 2 as `` `<TEST_CMD>` — N pass / M fail `` (backtick-wrapped command, then an em dash, then the counts), or freeform prose (this repo's own file: "No automated test suite. Validation is manual: ..."), or a bare fallback string, or `TBD`. This script only ever treats the line as having a real `TEST_CMD` when it starts with a backtick-quoted command — any other content (freeform prose, `TBD`, missing section) is `MODE=no-command` with `TEST_CMD` empty. This is the conservative direction: never invent a command to execute from prose that wasn't written as one.

**jq mode-agnostic vote design (read before writing tests):** the `.jq` filter takes `$mode` (string, pass-through only — it does not gate any branch), `$recorded` (int or `null`), and `$observed` (JSON array of ints and/or `null`s, one entry per run actually executed — `null` means that run produced no parseable count). It computes `RETRIES` from `$observed`'s length, the parseable subset (dropping `null`s) for voting, `PINNED_COUNT` as the parseable value with ≥2 occurrences (or empty if none), `SPREAD` as "no value pinned but ≥2 distinct parseable values exist," and `DRIFT` as "a value was pinned and it differs from `$recorded`." A 0- or 1-element `$observed` (the `skip`/`no-command`/`no-count` cases, and the "matched on first try" case) can never produce a pinned majority by construction, so `DRIFT`/`SPREAD` fall out as `0` automatically — no per-mode special casing needed inside the filter.

- [ ] **Step 1: Write the failing smoke test**

Create `meta/superpowers/validation/2026-09-09-test-count-rerun-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# test-count-rerun.sh/.jq smoke test. Two layers:
#   Part A: .jq fixtures via synthetic JSON (no git, no subprocess) -- the
#           vote/drift/spread/unparseable matrix.
#   Part B: .sh integration fixtures via scratch git repos with a fake,
#           invocation-counted TEST_CMD -- the skip check, the
#           extraction format, and the match-then-retry run count.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
jq_filter="$lib/test-count-rerun.jq"
tool="$lib/test-count-rerun.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# ---------------------------------------------------------------------------
# Part A: .jq fixtures
# ---------------------------------------------------------------------------

jq_run() {  # <mode> <recorded-json> <observed-json> -> full KEY=value output
  # --arg test_cmd "" is required even though these fixtures don't care
  # about TEST_CMD's value: jq errors at compile time on an unbound $var,
  # it does not treat a never-passed --arg as null, so the filter's own
  # "$test_cmd // \"\"" guard never gets a chance to run without this.
  jq -r -n --arg mode "$1" --argjson recorded "$2" --argjson observed "$3" --arg test_cmd "" -f "$jq_filter"
}
jq_field() {  # <output> <KEY> -> value
  print -r -- "$1" | awk -F= -v k="$2" '$1==k{print substr($0, length(k)+2)}'
}

# A1: skip mode, empty observed -> all zeros
out="$(jq_run skip null '[]')"
[[ "$(jq_field "$out" MODE)" == "skip" && "$(jq_field "$out" RETRIES)" == "0" \
   && "$(jq_field "$out" DRIFT)" == "0" && "$(jq_field "$out" SPREAD)" == "0" \
   && "$(jq_field "$out" UNPARSEABLE)" == "0" ]] \
  && ok "A1: skip -> all zeros" || bad "A1: got '$out'"

# A2: match on first run -> no drift, no pin (only 1 observation)
out="$(jq_run run 1162 '[1162]')"
[[ "$(jq_field "$out" DRIFT)" == "0" && "$(jq_field "$out" PINNED_COUNT)" == "" \
   && "$(jq_field "$out" RETRIES)" == "0" ]] \
  && ok "A2: first-run match -> no drift, unpinned" || bad "A2: got '$out'"

# A3: 2-of-3 majority confirms drift
out="$(jq_run run 1162 '[1161,1161,1162]')"
[[ "$(jq_field "$out" PINNED_COUNT)" == "1161" && "$(jq_field "$out" DRIFT)" == "1" \
   && "$(jq_field "$out" SPREAD)" == "0" && "$(jq_field "$out" RETRIES)" == "2" ]] \
  && ok "A3: 2-of-3 majority -> drift confirmed" || bad "A3: got '$out'"

# A4: 2-of-3 majority matches recorded -> first run was the flake, no drift
out="$(jq_run run 1162 '[1161,1162,1162]')"
[[ "$(jq_field "$out" PINNED_COUNT)" == "1162" && "$(jq_field "$out" DRIFT)" == "0" ]] \
  && ok "A4: 2-of-3 majority matches recorded -> no drift" || bad "A4: got '$out'"

# A5: all 3 disagree -> spread, no pin, no drift
out="$(jq_run run 1162 '[1160,1161,1162]')"
[[ "$(jq_field "$out" SPREAD)" == "1" && "$(jq_field "$out" PINNED_COUNT)" == "" \
   && "$(jq_field "$out" DRIFT)" == "0" ]] \
  && ok "A5: 3-way disagreement -> spread" || bad "A5: got '$out'"

# A6: 2 parseable disagree + 1 unparseable -> spread (not a false no-drift)
out="$(jq_run run 1162 '[1161,null,1162]')"
[[ "$(jq_field "$out" SPREAD)" == "1" && "$(jq_field "$out" UNPARSEABLE)" == "1" \
   && "$(jq_field "$out" DRIFT)" == "0" ]] \
  && ok "A6: 2 disagree + 1 unparseable -> spread" || bad "A6: got '$out'"

# A7: 2-of-2 parseable agree, 3rd unparseable -> majority still pins
out="$(jq_run run 1162 '[1161,null,1161]')"
[[ "$(jq_field "$out" PINNED_COUNT)" == "1161" && "$(jq_field "$out" DRIFT)" == "1" \
   && "$(jq_field "$out" SPREAD)" == "0" && "$(jq_field "$out" UNPARSEABLE)" == "1" ]] \
  && ok "A7: 2-of-2 parseable agree (3rd unparseable) -> pinned" || bad "A7: got '$out'"

# A8: all 3 unparseable -> no pin, no spread, UNPARSEABLE=1
out="$(jq_run run 1162 '[null,null,null]')"
[[ "$(jq_field "$out" UNPARSEABLE)" == "1" && "$(jq_field "$out" SPREAD)" == "0" \
   && "$(jq_field "$out" PINNED_COUNT)" == "" && "$(jq_field "$out" DRIFT)" == "0" ]] \
  && ok "A8: all 3 unparseable -> no pin, no spread" || bad "A8: got '$out'"

# A9: no-count mode, single run, no recorded value -> never drifts
out="$(jq_run no-count null '[1162]')"
[[ "$(jq_field "$out" DRIFT)" == "0" && "$(jq_field "$out" SPREAD)" == "0" \
   && "$(jq_field "$out" RECORDED_COUNT)" == "" ]] \
  && ok "A9: no-count -> never drifts, recorded stays empty" || bad "A9: got '$out'"

# A10: no-command mode, no observations
out="$(jq_run no-command null '[]')"
[[ "$(jq_field "$out" MODE)" == "no-command" && "$(jq_field "$out" RETRIES)" == "0" ]] \
  && ok "A10: no-command -> zero retries" || bad "A10: got '$out'"

# ---------------------------------------------------------------------------
# Part B: .sh integration fixtures
# ---------------------------------------------------------------------------

# mk_repo <dir> <summary-line> -> scratch repo with PROJECT_CONTEXT.md's Test
# expectations section set to <summary-line>, committed, primer touched at
# HEAD (so <last-primer-commit> == HEAD unless the caller commits more after).
mk_repo() {
  local dir="$1" summary="$2"
  rm -rf "$dir"; mkdir -p "$dir/.session-continuity"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name Test
  print -r -- "# Context

## Test expectations — these must stay green

$summary

## End-to-end check
" > "$dir/.session-continuity/PROJECT_CONTEXT.md"
  print -r -- "# Primer" > "$dir/.session-continuity/SESSION_PRIMER.md"
  git -C "$dir" add -A
  git -C "$dir" commit -qm init
}

# fake_cmd <dir> <counter-file> <sequence...> -> writes a TEST_CMD script at
# <dir>/fake-test.sh that pops one value off <sequence> per invocation
# (appending its own PID-independent invocation count to <counter-file>) and
# echoes "<value> pass" (or nothing, for a deliberately unparseable run,
# encoded as the literal token "UNPARSEABLE").
fake_cmd() {
  local dir="$1" counter="$2"; shift 2
  : > "$counter"
  print -r -- '#!/usr/bin/env bash' > "$dir/fake-test.sh"
  print -r -- "seq=($*)" >> "$dir/fake-test.sh"
  cat >> "$dir/fake-test.sh" <<'EOF'
n=$(wc -l < "$COUNTER_FILE")
val="${seq[$n]}"
echo "run" >> "$COUNTER_FILE"
if [[ "$val" == "UNPARSEABLE" ]]; then
  echo "no count here"
else
  echo "$val pass"
fi
EOF
  chmod +x "$dir/fake-test.sh"
}

last_commit() { git -C "$1" log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md; }

# B1: skip mode -- only .session-continuity/ files changed since last primer touch
d="$work/b1"; mk_repo "$d" '`./fake-test.sh` — 3 pass / 0 fail'
lc="$(last_commit "$d")"
print -r -- x >> "$d/.session-continuity/LEARNINGS.md"
git -C "$d" add -A; git -C "$d" commit -qm "docs only"
out="$(cd "$d" && bash "$tool" "$d" "$lc" 2>&1)"
[[ "$out" == *"MODE=skip"* ]] && ok "B1: docs-only change -> skip" || bad "B1: got '$out'"

# B2: no-command mode -- freeform prose, no backtick-quoted command
d="$work/b2"; mk_repo "$d" 'No automated test suite. Validation is manual.'
lc="$(last_commit "$d")"
out="$(cd "$d" && bash "$tool" "$d" "$lc" 2>&1)"
[[ "$(jq_field "$out" MODE)" == "no-command" && "$(jq_field "$out" TEST_CMD)" == "" ]] \
  && ok "B2: freeform prose -> no-command, empty TEST_CMD" || bad "B2: got '$out'"

# B3: no-count mode -- backtick command present, no parseable count
d="$work/b3"; mk_repo "$d" '`./fake-test.sh`'
fake_cmd "$d" "$d/counter" "3"
out="$(cd "$d" && COUNTER_FILE="$d/counter" bash "$tool" "$d" "$(last_commit "$d")" 2>&1)"
[[ "$(jq_field "$out" MODE)" == "no-count" ]] && ok "B3: bare command, no count -> no-count" || bad "B3: got '$out'"

# B4: run mode, first-run match -> exactly 1 invocation, no drift
d="$work/b4"; mk_repo "$d" '`./fake-test.sh` — 3 pass / 0 fail'
fake_cmd "$d" "$d/counter" "3"
out="$(cd "$d" && COUNTER_FILE="$d/counter" bash "$tool" "$d" "$(last_commit "$d")" 2>&1)"
invocations="$(wc -l < "$d/counter" | tr -d ' ')"
[[ "$(jq_field "$out" MODE)" == "run" && "$(jq_field "$out" DRIFT)" == "0" && "$invocations" == "1" ]] \
  && ok "B4: first-run match -> 1 invocation, no drift" || bad "B4: got '$out' (invocations=$invocations)"

# B5: run mode, first-run mismatch -> retries to 3, drift confirmed
d="$work/b5"; mk_repo "$d" '`./fake-test.sh` — 3 pass / 0 fail'
fake_cmd "$d" "$d/counter" "4" "4" "4"
out="$(cd "$d" && COUNTER_FILE="$d/counter" bash "$tool" "$d" "$(last_commit "$d")" 2>&1)"
invocations="$(wc -l < "$d/counter" | tr -d ' ')"
[[ "$(jq_field "$out" DRIFT)" == "1" && "$(jq_field "$out" PINNED_COUNT)" == "4" && "$invocations" == "3" ]] \
  && ok "B5: mismatch -> 3 invocations, drift confirmed" || bad "B5: got '$out' (invocations=$invocations)"

# B6: run mode, all 3 runs unparseable -> well-formed OBSERVED, no crash
d="$work/b6"; mk_repo "$d" '`./fake-test.sh` — 3 pass / 0 fail'
fake_cmd "$d" "$d/counter" "UNPARSEABLE" "UNPARSEABLE" "UNPARSEABLE"
out="$(cd "$d" && COUNTER_FILE="$d/counter" bash "$tool" "$d" "$(last_commit "$d")" 2>&1)"
[[ "$out" == *"UNPARSEABLE=1"* && "$out" == *"OBSERVED=,,"* ]] \
  && ok "B6: all 3 unparseable -> well-formed OBSERVED, UNPARSEABLE=1" || bad "B6: got '$out'"

# ---------------------------------------------------------------------------
# Operational failure cases
# ---------------------------------------------------------------------------

# B7: missing .jq filter
d="$work/b7"; mk_repo "$d" '`./fake-test.sh` — 3 pass / 0 fail'
badlib="$work/badlib"; mkdir -p "$badlib"; cp "$tool" "$badlib/"
out="$(bash "$badlib/test-count-rerun.sh" "$d" "$(last_commit "$d")" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"MODE="* ]] \
  && ok "B7: missing filter -> nonzero exit, no MODE= line" || bad "B7: rc=$rc out='$out'"

# B8: wrong CONTRACT_VERSION
d="$work/b8"; mk_repo "$d" '`./fake-test.sh` — 3 pass / 0 fail'
wronglib="$work/wronglib"; mkdir -p "$wronglib"; cp "$tool" "$wronglib/"
sed 's/CONTRACT_VERSION=1/CONTRACT_VERSION=99/' "$jq_filter" > "$wronglib/test-count-rerun.jq"
out="$(bash "$wronglib/test-count-rerun.sh" "$d" "$(last_commit "$d")" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"MODE="* ]] \
  && ok "B8: wrong CONTRACT_VERSION -> nonzero exit, no MODE= line" || bad "B8: rc=$rc out='$out'"

# B9: jq absent from PATH
d="$work/b9"; mk_repo "$d" '`./fake-test.sh` — 3 pass / 0 fail'
nojq="$work/nojq"; mkdir -p "$nojq/bin"
for b in bash git awk grep sed head cat mktemp dirname timeout wc tr; do
  p="$(command -v "$b")"; [[ -n "$p" ]] && ln -sf "$p" "$nojq/bin/$b"
done
out="$(PATH="$nojq/bin" bash "$tool" "$d" "$(last_commit "$d")" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"MODE="* ]] \
  && ok "B9: jq absent from PATH -> nonzero exit, no MODE= line" || bad "B9: rc=$rc out='$out'"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x meta/superpowers/validation/2026-09-09-test-count-rerun-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-test-count-rerun-smoke.zsh
```

Expected: FAIL on every assertion — neither `hooks/lib/test-count-rerun.jq` nor `hooks/lib/test-count-rerun.sh` exists yet.

- [ ] **Step 3: Write `hooks/lib/test-count-rerun.jq`**

```jq
# CONTRACT_VERSION=1
# hooks/lib/test-count-rerun.jq — pure vote/drift/spread decision for
# /session-continuity:primer Step 4's test-count rerun. Invoked via
# test-count-rerun.sh; see that file for the CLI contract and
# meta/superpowers/specs/2026-09-09-test-count-rerun-design.md for the
# full output contract this implements.
#
# Mode-agnostic by design: $mode is pass-through only (it never gates a
# branch here). skip/no-command/no-count's "always empty" outputs fall
# out of running this same algorithm against a 0- or 1-element $observed
# array — see the design spec's "MODE=run" outcomes table for why a
# majority can never be pinned from fewer than 2 parseable votes.

($observed | length) as $n
| ($observed | map(select(. != null))) as $parseable
| (if $n == 0 then 0 else $n - 1 end) as $retries
| (any($observed[]; . == null)) as $unparseable
| ($parseable | group_by(.) | map({value: .[0], count: length})
   | map(select(.count >= 2))) as $majority
| ($majority[0].value // null) as $pinned
| (if $pinned != null then false
   else ($parseable | unique | length) >= 2
   end) as $spread
| ($pinned != null and $recorded != null and $pinned != $recorded) as $drift

| "TEST_CMD=" + ($test_cmd // ""),
  "RECORDED_COUNT=" + (if $recorded == null then "" else ($recorded|tostring) end),
  "MODE=" + $mode,
  "RETRIES=" + ($retries|tostring),
  "OBSERVED=" + ($observed | map(if . == null then "" else (.|tostring) end) | join(",")),
  "UNPARSEABLE=" + (if $unparseable then "1" else "0" end),
  "DRIFT=" + (if $drift then "1" else "0" end),
  "PINNED_COUNT=" + (if $pinned == null then "" else ($pinned|tostring) end),
  "SPREAD=" + (if $spread then "1" else "0" end)
```

Note: `$test_cmd` must always be passed via `--arg` by any caller — jq errors at compile time on an unbound variable, it does not default to `null`, so `$test_cmd // ""` only guards against an *empty string* value, never against a missing `--arg`. The smoke test's `jq_run` helper (Part A) passes `--arg test_cmd ""` for exactly this reason even though those fixtures don't care about the field's value. `test-count-rerun.sh` (Step 4 below) always passes the real value.

- [ ] **Step 4: Write `hooks/lib/test-count-rerun.sh`**

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/test-count-rerun.sh — test-count majority-vote rerun for
# /session-continuity:primer Step 4 (Refresh mode). See
# meta/superpowers/specs/2026-09-09-test-count-rerun-design.md for the
# full contract this implements (unchanged behavior from the prior
# hand-evaluated prose, just executable instead of hand-derived per
# invocation) and meta/superpowers/plans/2026-09-09-test-count-rerun.md
# for the implementation plan.
#
# Usage: test-count-rerun.sh <project-dir> <last-primer-commit>
# Prints KEY=value lines to stdout on success: TEST_CMD, RECORDED_COUNT,
# MODE (skip|no-command|no-count|run), RETRIES, OBSERVED, UNPARSEABLE,
# DRIFT, PINNED_COUNT, SPREAD.
#
# Operational failure (jq missing, test-count-rerun.jq missing or from a
# different CONTRACT_VERSION, <project-dir> not inside a git repository,
# PROJECT_CONTEXT.md unreadable) prints one diagnostic line to stderr and
# exits 1 with NO MODE= line on stdout at all.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ_FILTER="$SCRIPT_DIR/test-count-rerun.jq"
DIR="${1:-.}"
LAST_PRIMER_COMMIT="${2:-}"

die() {  # <message>
  printf 'test-count-rerun.sh: %s\n' "$1" >&2
  exit 1
}

[[ -n "$LAST_PRIMER_COMMIT" ]] \
  || die "usage: test-count-rerun.sh <project-dir> <last-primer-commit>"
command -v jq >/dev/null 2>&1 \
  || die "jq is not installed, so the test-count rerun cannot be computed."
[[ -r "$JQ_FILTER" ]] \
  || die "test-count-rerun.jq is missing from $SCRIPT_DIR — the plugin cache is incomplete. Run \`/session-continuity:update\`."
grep -q '^# CONTRACT_VERSION=1$' "$JQ_FILTER" \
  || die "test-count-rerun.jq is from a different plugin version — run \`/session-continuity:update\`."
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "$DIR is not inside a git repository."
CONTEXT_FILE="$DIR/.session-continuity/PROJECT_CONTEXT.md"
[[ -r "$CONTEXT_FILE" ]] \
  || die "$CONTEXT_FILE is not readable."

# --- extract the Test-expectations summary line ----------------------------
# Skip any HTML-comment lines (single- or multi-line <!-- ... -->) so a
# template's own exemplar comment is never mistaken for real content.
SUMMARY_LINE="$(awk '
  /^## Test expectations/ { insec=1; next }
  insec && /^## / { exit }
  insec {
    if ($0 ~ /<!--/) incomment=1
    if (!incomment && $0 !~ /^[[:space:]]*$/) { print; exit }
    if ($0 ~ /-->/) incomment=0
  }
' "$CONTEXT_FILE")"

TEST_CMD=""
if [[ "$SUMMARY_LINE" =~ ^\`([^\`]+)\` ]]; then
  TEST_CMD="${BASH_REMATCH[1]}"
fi

RECORDED_COUNT=""
if [[ -n "$TEST_CMD" ]]; then
  RECORDED_COUNT="$(printf '%s' "$SUMMARY_LINE" | grep -oE '[0-9]+ pass(ed)?' | head -1 | grep -oE '^[0-9]+' || true)"
fi

# --- mode dispatch (labeling only -- the .jq filter's vote logic is the
#     same regardless of which label sh assigns here) ----------------------
if [[ -z "$TEST_CMD" ]]; then
  MODE="no-command"
else
  CHANGED_FILES="$(git -C "$DIR" diff "$LAST_PRIMER_COMMIT"..HEAD --name-only 2>/dev/null || true)"
  SKIP=1
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in .session-continuity/*) ;; *) SKIP=0 ;; esac
  done <<<"$CHANGED_FILES"
  if [[ "$SKIP" -eq 1 ]]; then
    MODE="skip"
  elif [[ -z "$RECORDED_COUNT" ]]; then
    MODE="no-count"
  else
    MODE="run"
  fi
fi

# --- run the command 0-3 times per mode -------------------------------------
# run_once's exit code is deliberately never inspected: "unparseable" is
# defined purely by the absence of a recognizable count in the output,
# not by a nonzero exit or a timeout. A `timeout`-killed run and a
# zero-exit run that simply printed no count both fall through to the
# same "no parseable count" outcome below -- there is exactly one code
# path for both, which is why the smoke test (B6) only needs to exercise
# unparseable *output*, not a separate timeout-specific fixture.
run_once() {  # prints the parsed count, or nothing, on stdout
  local out
  out="$(cd "$DIR" && timeout 120 bash -c "$TEST_CMD" 2>&1)"
  printf '%s' "$out" | grep -oE '[0-9]+ pass(ed)?' | head -1 | grep -oE '^[0-9]+' || true
}

OBSERVED_JSON="[]"
case "$MODE" in
  skip|no-command)
    : # OBSERVED stays empty; the command never runs.
    ;;
  no-count)
    v="$(run_once)"
    OBSERVED_JSON="[$( [[ -n "$v" ]] && echo "$v" || echo null )]"
    ;;
  run)
    v1="$(run_once)"
    if [[ -n "$v1" && "$v1" == "$RECORDED_COUNT" ]]; then
      OBSERVED_JSON="[$v1]"
    else
      v2="$(run_once)"
      v3="$(run_once)"
      to_json() { [[ -n "$1" ]] && echo "$1" || echo null; }
      OBSERVED_JSON="[$(to_json "$v1"),$(to_json "$v2"),$(to_json "$v3")]"
    fi
    ;;
esac

RECORDED_JSON="null"
[[ -n "$RECORDED_COUNT" ]] && RECORDED_JSON="$RECORDED_COUNT"

ERRFILE="$(mktemp)"
RESULT="$(
  jq -r -n \
    --arg test_cmd "$TEST_CMD" \
    --arg mode "$MODE" \
    --argjson recorded "$RECORDED_JSON" \
    --argjson observed "$OBSERVED_JSON" \
    -f "$JQ_FILTER" 2>"$ERRFILE"
)"
JQ_STATUS=$?
DETAIL="$(head -1 "$ERRFILE" 2>/dev/null)"
rm -f "$ERRFILE"

if [[ "$JQ_STATUS" -ne 0 || -z "$RESULT" ]]; then
  die "the vote filter failed: ${DETAIL:-jq exited $JQ_STATUS}"
fi

printf '%s\n' "$RESULT"
```

```bash
chmod +x hooks/lib/test-count-rerun.sh
```

- [ ] **Step 5: Run the smoke test to verify all assertions pass**

```bash
zsh meta/superpowers/validation/2026-09-09-test-count-rerun-smoke.zsh
```

Expected: `Result: 19 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add hooks/lib/test-count-rerun.jq hooks/lib/test-count-rerun.sh meta/superpowers/validation/2026-09-09-test-count-rerun-smoke.zsh
git commit -m "feat: add test-count-rerun.sh/.jq, scripting primer Step 4's rerun vote"
```

---

### Task 2: `commands/primer.md` — call the script

**Files:**
- Modify: `commands/primer.md` (Step 4 item 3, currently lines 285-300 as of `de381a8`)

**Interfaces:**
- Consumes: `hooks/lib/test-count-rerun.sh` (Task 1), resolved via `CLAUDE_PLUGIN_ROOT` and `require_script`, exactly like `primer-detect.sh` already is in Step 1.

- [ ] **Step 1: Replace item 3 in full**

Using the Edit tool, replace this exact block (currently `commands/primer.md` lines 285-300, from `3. If the primer has a test-counts section...` through the line ending `...captured around this whole check.`):

````markdown
3. If the primer has a test-counts section, decide whether to re-run it.
   Do this as **one Bash call**, timed, tracking a `RETRIES` count (0
   if skipped or the first run matched, else the number of *extra*
   runs actually executed beyond the first):
   - **Skip the rerun** if `git diff <last-primer-commit>..HEAD --name-only` (the commit range since the primer was last touched) contains no file outside `.session-continuity/` — no source or test file changed, so the recorded count cannot have drifted. Reuse this diff if already computed elsewhere in this flow; don't recompute it just for this check.
   - **Otherwise, run the test command(s) once.** If that single run's count matches the primer's recorded count, stop there — no drift on this axis, no further runs.
   - **Only if that first run disagrees with the recorded count**, retry up to 2 more times (3 runs total) to rule out flakiness before reporting drift — a single sample can swing a pass/fail count and produce a false drift alarm. Pin to the count seen in ≥2 of the 3 runs. If that pinned count matches the primer's recorded count, the first run was the flake — no drift. If it differs, report drift with the pinned count. If all three runs disagree with each other, surface the spread (`saw 1162 / 1161 / 1162 across 3 runs — using 1162; suite is unstable`) instead of silently picking one.

   This keeps the common cases cheap: zero test runs when no relevant file changed, one run when relevant files changed but the count still holds, and the full 3-run majority vote only when there's an actual discrepancy to resolve.

   At the end of this Bash call (whichever branch above ran), call:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-4-test-count-rerun --duration="$_PERF_DURATION" --retries="$RETRIES"
   ```
   using the same `_PERF_START`/`_PERF_END`/`_PERF_DURATION` pattern
   shown in item 2 above, captured around this whole check.
````

with:

````markdown
3. Run the shared test-count rerun script, timed:

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
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-4-test-count-rerun --duration="$_PERF_DURATION" --retries="${RETRIES:-0}"
   echo "$RERUN_OUTPUT"
   echo "RERUN_STATUS=$RERUN_STATUS"
   ```

   **If `RERUN_STATUS` is nonzero, or `$RERUN_OUTPUT` has no `MODE=` line:**
   report `$RERUN_OUTPUT` to the user and fall back to `TBD` for this
   axis — never fabricate a drift verdict from a failed script.

   **Otherwise**, report per `MODE`:
   - `skip` — no relevant file changed; say nothing (matches today's
     silent skip).
   - `no-command` — no test command recorded; nothing to check.
   - `no-count`, `RETRIES=0`, `DRIFT=0` always — nothing recorded yet
     to compare against; no report needed on this axis.
   - `run` with `DRIFT=0` — the count held (whether on the first try or
     after majority-vote confirmation); no report needed.
   - `run` with `DRIFT=1` — report drift using `PINNED_COUNT`
     (`"Test count drifted: recorded <RECORDED_COUNT>, now
     <PINNED_COUNT> (confirmed over <RETRIES>+1 runs)."`).
   - `run` with `SPREAD=1` — report instability using the comma-joined
     `OBSERVED` values (`"Test suite is unstable: saw
     <OBSERVED, /-joined> across 3 runs."`), not a drift verdict.
   - `run` with `UNPARSEABLE=1` and no `PINNED_COUNT` — report
     `"Test command produced no parseable count after <RETRIES>+1
     attempts."`
````

- [ ] **Step 2: Verify the old prose is gone**

```bash
grep -c 'retry up to 2 more times\|Pin to the count seen in' commands/primer.md
```

Expected: `0` — the majority-vote mechanics now live only in `test-count-rerun.jq`, referenced by its output fields everywhere else.

- [ ] **Step 3: Commit**

```bash
git add commands/primer.md
git commit -m "refactor: primer.md Step 4 item 3 dispatches via test-count-rerun.sh"
```

---

### Task 3: Doc pointers, regression pass, changelog

**Files:**
- Modify: `meta/superpowers/specs/2026-09-02-determinism-program-design.md`
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Update the design doc's Phase 6 entry**

Using the Edit tool, replace this exact block in `meta/superpowers/specs/2026-09-02-determinism-program-design.md`:

```markdown
**Phase 6 `#43` — `primer` detect, migrate, init, drift.** Decomposed into
five sub-projects (see `meta/superpowers/specs/2026-09-08-primer-detect-design.md`'s
Context section for the full breakdown and why): **sub-project A shipped**
— Step 1's mode detection plus all three migration triggers, previously
hand-evaluated nested conditionals with an easy-to-miss sequencing rule,
now `hooks/lib/primer-detect.sh`/`.jq`. Plan:
`meta/superpowers/plans/2026-09-08-primer-detect.md`. Still pending:
sub-project B (Step 4's test-count majority-vote rerun — the same
compare-a-claimed-value-against-an-actual-one class Phase 7 is being
built to gate against), C (Step 3c/3d's `git mv`/`git rm` migration
mechanics themselves — sub-project A only scripted *whether* they run,
not *what* they do), D (Step 2's placeholder-derivation gather-and-regex),
E (Step 3/3b's section-bucketing judgment, lowest priority — near-zero
remaining audience, most judgment-heavy of the five).
```

with:

```markdown
**Phase 6 `#43` — `primer` detect, migrate, init, drift.** Decomposed into
five sub-projects (see `meta/superpowers/specs/2026-09-08-primer-detect-design.md`'s
Context section for the full breakdown and why): **sub-project A shipped**
— Step 1's mode detection plus all three migration triggers, now
`hooks/lib/primer-detect.sh`/`.jq`. Plan:
`meta/superpowers/plans/2026-09-08-primer-detect.md`. **Sub-project B
shipped** — Step 4's test-count majority-vote rerun (the
compare-a-claimed-value-against-an-actual-one class Phase 7 is being
built to gate against), now `hooks/lib/test-count-rerun.sh`/`.jq`. Spec:
`meta/superpowers/specs/2026-09-09-test-count-rerun-design.md`. Plan:
`meta/superpowers/plans/2026-09-09-test-count-rerun.md`. Still pending:
C (Step 3c/3d's `git mv`/`git rm` migration mechanics themselves —
sub-project A only scripted *whether* they run, not *what* they do), D
(Step 2's placeholder-derivation gather-and-regex), E (Step 3/3b's
section-bucketing judgment, lowest priority — near-zero remaining
audience, most judgment-heavy of the five).
```

- [ ] **Step 2: Full regression pass**

```bash
for f in \
  meta/superpowers/validation/2026-09-09-test-count-rerun-smoke.zsh \
  meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh \
  meta/superpowers/validation/2026-09-08-checklist-assemble-smoke.zsh \
  meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh \
  meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh \
  meta/superpowers/validation/2026-08-12-session-start-smoke.zsh \
  meta/superpowers/validation/2026-09-01-require-script-smoke.zsh \
  meta/superpowers/validation/2026-09-07-backlog-issues-smoke.zsh \
  meta/superpowers/validation/2026-09-01-agent-active-smoke.zsh \
  meta/superpowers/validation/2026-09-02-resolve-transcript-smoke.zsh \
  meta/superpowers/validation/2026-09-02-count-entries-smoke.zsh \
  meta/superpowers/validation/2026-09-02-candidate-render-smoke.zsh \
  meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh
do
  echo "--- $f ---"
  zsh "$f" || echo "FAILED: $f"
done
```

Expected: every runner ends `0 failed`.

- [ ] **Step 3: Add a CHANGELOG entry**

Add a new section at the top of `CHANGELOG.md`, directly under the `# Changelog` header and its description line, above the current top entry:

```markdown
## [0.33.0] — 2026-09-09

### Changed
- **`/session-continuity:primer`'s Step 4 test-count rerun is now scripted.** New `hooks/lib/test-count-rerun.sh`/`.jq` replace ~8 lines of hand-evaluated majority-vote prose (skip-check, run-once-then-compare, retry-to-3-on-mismatch, pin-to-majority, spread-on-3-way-disagreement) with one script call. The `.jq` filter's vote algorithm is mode-agnostic — the `skip`/`no-command`/`no-count` cases' "always empty" outputs fall out of the same generic majority computation applied to a 0- or 1-element observation array, with no per-mode special casing. Unparseable test runs (timeout, crash, no recognizable count) are now handled explicitly: they consume a retry slot but cast no vote, so a 2-of-2 parseable majority still pins even when the third run was unparseable, and a genuine 2-way disagreement with one unparseable run reports spread rather than a false no-drift. Determinism Phase 6 (#43) sub-project B; sub-projects C-E remain pending.
```

- [ ] **Step 4: Bump the plugin version**

Using the Edit tool, update `.claude-plugin/plugin.json`'s `"version"` field from `"0.32.0"` to `"0.33.0"`.

- [ ] **Step 5: Commit**

```bash
git add meta/superpowers/specs/2026-09-02-determinism-program-design.md CHANGELOG.md .claude-plugin/plugin.json
git commit -m "docs: Phase 6 sub-project B doc pointers, changelog, and version bump"
```
