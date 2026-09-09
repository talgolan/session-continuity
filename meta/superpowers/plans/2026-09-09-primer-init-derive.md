# Determinism Phase 6, sub-project D — `primer-init-derive.sh`/`.jq` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `commands/primer.md` Step 2 item 6's four mechanical
placeholder derivations (`{{PROJECT_NAME}}`, `{{LATEST_COMMIT_HASH_N}}`/
`{{LATEST_COMMIT_SUBJECT_N}}`, `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}`,
`{{TEST_COMMAND_SUMMARY}}`) with one script, `hooks/lib/primer-init-derive.sh`,
called after the existing raw-fact-gathering Bash block. `{{MODULES_TABLE}}`,
`{{REPO_LAYOUT_SUMMARY}}`, and `{{WORKFLOW_CONVENTIONS}}` are untouched —
excluded per the design's "Problem"/"Non-goals" sections.

**Architecture:** `primer-init-derive.sh` (bash, I/O — re-derives the
manifest-name and `git log --oneline -5` facts locally, since the existing
Step 2 Bash block never captured those into named variables and re-reading
two files plus one `git log` call is cheap and side-effect-free) hands the
raw text to `primer-init-derive.jq` (pure parse function — no I/O,
fixture-testable with synthetic string args) for the manifest-priority pick,
git-log line split, and pass/fail count regex. `TEST_CMD`/`TEST_OUTPUT` are
the one exception: the existing Bash block already discovers and runs the
test command once, so it exports both, and the script reads them from its
inherited environment rather than rediscovering or re-running anything test-
related — an earlier draft had the script redo that discovery-and-execution
independently, which would have run the project's real test suite twice per
Init-mode invocation; caught before implementation, see the spec's "Test
command: read, never re-run."

**Spec:** `meta/superpowers/specs/2026-09-09-primer-init-derive-design.md`.

## Global Constraints

- `primer-init-derive.sh` and `primer-init-derive.jq` both carry a
  `# CONTRACT_VERSION=1` header. `commands/primer.md` calls the `.sh`
  through `require_script`, exactly like `primer-detect.sh` and
  `test-count-rerun.sh` already are. `primer-init-derive.sh` itself checks
  its sibling `.jq`'s `CONTRACT_VERSION` before invoking it.
- **No fabricated derivation on operational failure.** jq missing, the `.jq`
  filter missing/version-mismatched, or `<project-dir>` unreadable each print
  one diagnostic line to stderr and exit nonzero with no `PROJECT_NAME=` line
  on stdout. `commands/primer.md` falls back to asking the user for the
  affected fields manually — it must not invent a project name, commit list,
  or test summary.
- **Never invent a test count.** `TEST_COMMAND_SUMMARY` includes a fail count
  only when a fail-count regex match was actually found in the captured
  output — never defaulted to `0`. See spec's "`TEST_COMMAND_SUMMARY` rules."
- Both count regexes (`[0-9]+ pass(ed)?`, `[0-9]+ fail(ed)?`) are copied
  verbatim in spirit from `hooks/lib/test-count-rerun.sh`'s `run_once()` —
  same pattern, same `head -1` first-match convention — not re-derived from
  scratch, so the two scripts recognize test output identically.
- **Never re-run the test command.** `primer-init-derive.sh` reads
  `TEST_CMD`/`TEST_OUTPUT` from its inherited environment — exported by
  `commands/primer.md`'s existing Bash block right after it runs the
  command once — and does not discover or execute a test command itself.
  Running the project's real test suite twice per Init-mode invocation is
  not an acceptable cost of this refactor.
- **Every git-log line yields exactly one `commits[]` entry, parseable or
  not.** `capture(re)` with no match produces zero outputs in jq — a naive
  `map(capture(...))` silently drops non-matching lines, shrinking
  `COMMIT_COUNT` and shifting every following commit's index. Guard with
  `test(...)` first; fall back to a hash-only entry on no match.
- The raw-fact-gathering Bash block in `commands/primer.md` Step 2 item 6
  (manifest checks, `git log --oneline -5`, the `@module` grep, test-command
  discovery and execution) stays exactly as it is except for one added line
  exporting `TEST_CMD TEST_OUTPUT` — this plan only replaces what reads that
  output afterward, and only for the four fields named above.
- Do not touch `{{MODULES_TABLE}}`, `{{REPO_LAYOUT_SUMMARY}}`, or
  `{{WORKFLOW_CONVENTIONS}}` — prose, unchanged, per the spec's Non-goals.
- Do not touch `hooks/lib/primer-detect.sh`/`.jq` (sub-project A),
  `hooks/lib/test-count-rerun.sh`/`.jq` (sub-project B), or
  `hooks/lib/token-overlap.sh`/`.jq` (Phase 5) — unrelated to this plan.

---

## File Structure

| File | Responsibility |
|---|---|
| `hooks/lib/primer-init-derive.jq` (new) | Pure parse function: given manifest name-lines, a git-log block, and a test-run's captured output as string args, computes `PROJECT_NAME`, `LATEST_COMMIT_HASH_N`/`SUBJECT_N` (1-5), `TEST_COMMAND_SUMMARY`. No I/O. |
| `hooks/lib/primer-init-derive.sh` (new) | I/O: re-runs the manifest/git-log/test-command gathering already described in `commands/primer.md` Step 2 item 6, passes raw text to the filter. |
| `commands/primer.md` (modified) | Step 2 item 6's four mechanical bullets collapse to one script call; the `{{MODULES_TABLE}}`, `{{REPO_LAYOUT_SUMMARY}}`, `{{WORKFLOW_CONVENTIONS}}` bullets are untouched. |
| `meta/superpowers/validation/2026-09-09-primer-init-derive-smoke.zsh` (new) | Smoke test: `.jq`-only fixtures (synthetic string args, no git/subprocess) plus `.sh` integration fixtures (scratch git repos with real manifests and a fake `TEST_CMD`) plus operational-failure cases. |
| `meta/superpowers/specs/2026-09-02-determinism-program-design.md` (modified) | Phase 6 entry notes sub-project D shipped; C/E remain pending. |
| `CHANGELOG.md` (modified) | New version entry. |
| `.claude-plugin/plugin.json` (modified) | Version bump `0.33.0` → `0.34.0`. |

---

### Task 1: `hooks/lib/primer-init-derive.jq` + `hooks/lib/primer-init-derive.sh`

**Files:**
- Create: `hooks/lib/primer-init-derive.jq`
- Create: `hooks/lib/primer-init-derive.sh`
- Test: `meta/superpowers/validation/2026-09-09-primer-init-derive-smoke.zsh`

**Interfaces:**
- Produces: `bash primer-init-derive.sh <project-dir>`. Prints `KEY=value`
  lines to stdout per the spec's Output contract (`PROJECT_NAME`,
  `WORKING_DIRECTORY_ABSOLUTE_PATH`, `COMMIT_COUNT`,
  `LATEST_COMMIT_HASH_1..5`, `LATEST_COMMIT_SUBJECT_1..5`, `TEST_CMD`,
  `TEST_COMMAND_SUMMARY`). Exits 0 on success. On operational failure,
  prints one diagnostic line to stderr and exits 1 with **no**
  `PROJECT_NAME=` line anywhere in stdout.
- Consumes: `jq` (hard dependency), `git`. Reads `TEST_CMD`/`TEST_OUTPUT`
  from its inherited environment — does not itself run a test command, so
  it has no `timeout` dependency.

- [ ] **Step 1: Write the failing smoke test**

Create `meta/superpowers/validation/2026-09-09-primer-init-derive-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# primer-init-derive.sh/.jq smoke test. Two layers:
#   Part A: .jq fixtures via synthetic string args (no git, no subprocess) --
#           the manifest-priority pick, git-log split, count-regex matrix.
#   Part B: .sh integration fixtures via scratch git repos with real
#           manifests and a fake TEST_CMD -- gathering + end-to-end wiring.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
jq_filter="$lib/primer-init-derive.jq"
tool="$lib/primer-init-derive.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# ---------------------------------------------------------------------------
# Part A: .jq fixtures
# ---------------------------------------------------------------------------

# jq_run <pkg_name> <cargo_name> <pyproject_name> <dirname> <git_log> <test_cmd> <test_output>
jq_run() {
  jq -r -n \
    --arg pkg_name "$1" --arg cargo_name "$2" --arg pyproject_name "$3" \
    --arg dirname "$4" --arg pwd "/tmp/$4" --arg git_log "$5" \
    --arg test_cmd "$6" --arg test_output "$7" \
    -f "$jq_filter"
}
jq_field() {  # <output> <KEY> -> value
  print -r -- "$1" | awk -F= -v k="$2" '$1==k{print substr($0, length(k)+2)}'
}

# A1: package.json name wins over Cargo.toml even when both present
out="$(jq_run pkgname cratename "" dirfallback "" "" "")"
[[ "$(jq_field "$out" PROJECT_NAME)" == "pkgname" ]] \
  && ok "A1: package.json name wins priority" || bad "A1: got '$out'"

# A2: only Cargo.toml present
out="$(jq_run "" cratename "" dirfallback "" "" "")"
[[ "$(jq_field "$out" PROJECT_NAME)" == "cratename" ]] \
  && ok "A2: Cargo.toml name used when package.json absent" || bad "A2: got '$out'"

# A3: only pyproject.toml present
out="$(jq_run "" "" pyname dirfallback "" "" "")"
[[ "$(jq_field "$out" PROJECT_NAME)" == "pyname" ]] \
  && ok "A3: pyproject.toml name used when others absent" || bad "A3: got '$out'"

# A4: no manifest -> directory basename fallback
out="$(jq_run "" "" "" dirfallback "" "" "")"
[[ "$(jq_field "$out" PROJECT_NAME)" == "dirfallback" ]] \
  && ok "A4: directory basename fallback" || bad "A4: got '$out'"

# A5: 5-line git log -> COMMIT_COUNT=5, all pairs filled
gitlog5=$'aaa1111 first commit\nbbb2222 second commit\nccc3333 third\nddd4444 fourth\neee5555 fifth'
out="$(jq_run pkg "" "" dir "$gitlog5" "" "")"
[[ "$(jq_field "$out" COMMIT_COUNT)" == "5" \
   && "$(jq_field "$out" LATEST_COMMIT_HASH_1)" == "aaa1111" \
   && "$(jq_field "$out" LATEST_COMMIT_SUBJECT_1)" == "first commit" \
   && "$(jq_field "$out" LATEST_COMMIT_HASH_5)" == "eee5555" ]] \
  && ok "A5: 5-commit log fully split" || bad "A5: got '$out'"

# A6: 2-line git log (fresh repo) -> COMMIT_COUNT=2, pairs 3-5 empty
gitlog2=$'aaa1111 only commit\nbbb2222 init'
out="$(jq_run pkg "" "" dir "$gitlog2" "" "")"
[[ "$(jq_field "$out" COMMIT_COUNT)" == "2" \
   && "$(jq_field "$out" LATEST_COMMIT_HASH_3)" == "" \
   && "$(jq_field "$out" LATEST_COMMIT_SUBJECT_5)" == "" ]] \
  && ok "A6: 2-commit log leaves 3-5 empty" || bad "A6: got '$out'"

# A7: empty git log (no commits yet) -> COMMIT_COUNT=0, all empty
out="$(jq_run pkg "" "" dir "" "" "")"
[[ "$(jq_field "$out" COMMIT_COUNT)" == "0" \
   && "$(jq_field "$out" LATEST_COMMIT_HASH_1)" == "" ]] \
  && ok "A7: empty git log -> COMMIT_COUNT=0" || bad "A7: got '$out'"

# A8: empty TEST_CMD -> TBD
out="$(jq_run pkg "" "" dir "" "" "")"
[[ "$(jq_field "$out" TEST_COMMAND_SUMMARY)" == "TBD" ]] \
  && ok "A8: no test command -> TBD" || bad "A8: got '$out'"

# A9: pass + fail both parseable -> full summary
out="$(jq_run pkg "" "" dir "" "bun test" "12 pass, 0 fail")"
[[ "$(jq_field "$out" TEST_COMMAND_SUMMARY)" == '`bun test` — 12 pass / 0 fail' ]] \
  && ok "A9: pass+fail parseable -> full summary" || bad "A9: got '$out'"

# A10: pass parseable, fail not -> bare command, no invented fail count
out="$(jq_run pkg "" "" dir "" "bun test" "12 pass")"
[[ "$(jq_field "$out" TEST_COMMAND_SUMMARY)" == '`bun test`' ]] \
  && ok "A10: pass only, no fail match -> bare command" || bad "A10: got '$out'"

# A11: no recognizable count anywhere -> bare command
out="$(jq_run pkg "" "" dir "" "bun test" "something went wrong, no counts here")"
[[ "$(jq_field "$out" TEST_COMMAND_SUMMARY)" == '`bun test`' ]] \
  && ok "A11: no parseable count -> bare command" || bad "A11: got '$out'"

# A12: pytest-style "N passed, M failed" phrasing
out="$(jq_run pkg "" "" dir "" "pytest" "5 passed, 1 failed in 0.42s")"
[[ "$(jq_field "$out" TEST_COMMAND_SUMMARY)" == '`pytest` — 5 pass / 1 fail' ]] \
  && ok "A12: pytest phrasing parses" || bad "A12: got '$out'"

# A13: a git-log line with no whitespace at all (no parseable subject)
# still yields exactly one commits[] entry instead of being silently
# dropped by a bare map(capture(...)).
gitlog_nospace=$'aaa1111 real commit\nnospacehash'
out="$(jq_run pkg "" "" dir "$gitlog_nospace" "" "")"
[[ "$(jq_field "$out" COMMIT_COUNT)" == "2" \
   && "$(jq_field "$out" LATEST_COMMIT_HASH_2)" == "nospacehash" \
   && "$(jq_field "$out" LATEST_COMMIT_SUBJECT_2)" == "" ]] \
  && ok "A13: non-matching git-log line still yields one commits[] entry" || bad "A13: got '$out'"

# ---------------------------------------------------------------------------
# Part B: .sh integration fixtures
# ---------------------------------------------------------------------------

# mk_repo <dir> [package.json contents]
mk_repo() {
  local dir="$1"
  rm -rf "$dir"; mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name Test
  print -r -- "init" > "$dir/README.md"
  git -C "$dir" add -A; git -C "$dir" commit -qm "init commit"
  print -r -- "second" >> "$dir/README.md"
  git -C "$dir" add -A; git -C "$dir" commit -qm "second commit"
}

# B1: package.json present -> PROJECT_NAME from it, real git log split
d="$work/b1"; mk_repo "$d"
print -r -- '{"name": "real-pkg-name"}' > "$d/package.json"
git -C "$d" add -A; git -C "$d" commit -qm "add package.json"
out="$(cd "$d" && bash "$tool" "$d" 2>&1)"
[[ "$(jq_field "$out" PROJECT_NAME)" == "real-pkg-name" \
   && "$(jq_field "$out" COMMIT_COUNT)" == "3" ]] \
  && ok "B1: real package.json + git log wired end to end" || bad "B1: got '$out'"

# B2: no manifest -> directory basename fallback
d="$work/b2-namedrepo"; mk_repo "$d"
out="$(cd "$d" && bash "$tool" "$d" 2>&1)"
[[ "$(jq_field "$out" PROJECT_NAME)" == "b2-namedrepo" ]] \
  && ok "B2: no manifest -> real directory basename" || bad "B2: got '$out'"

# B3: WORKING_DIRECTORY_ABSOLUTE_PATH matches the real path
d="$work/b3"; mk_repo "$d"
out="$(cd "$d" && bash "$tool" "$d" 2>&1)"
[[ "$(jq_field "$out" WORKING_DIRECTORY_ABSOLUTE_PATH)" == "$d" ]] \
  && ok "B3: WORKING_DIRECTORY_ABSOLUTE_PATH is the real path" || bad "B3: got '$out'"

# B4: TEST_CMD/TEST_OUTPUT come from the environment, not from a real run --
# the tool must never itself execute a test command, so a TEST_CMD naming a
# script that (if actually run) would fail the whole smoke test is a
# deliberate canary: if the tool ever re-introduces its own execution, this
# assertion starts failing loudly instead of just timing out quietly.
d="$work/b4"; mk_repo "$d"
out="$(cd "$d" && TEST_CMD='exit 1; echo THIS_MUST_NEVER_RUN' TEST_OUTPUT='7 passed, 1 failed' bash "$tool" "$d" 2>&1)"
[[ "$(jq_field "$out" TEST_CMD)" == 'exit 1; echo THIS_MUST_NEVER_RUN' \
   && "$(jq_field "$out" TEST_COMMAND_SUMMARY)" == '`exit 1; echo THIS_MUST_NEVER_RUN` — 7 pass / 1 fail' ]] \
  && ok "B4: TEST_CMD/TEST_OUTPUT read from env, never executed" || bad "B4: got '$out'"

# B5: no TEST_CMD in the environment -> TBD, same as the no-manifest case
d="$work/b5"; mk_repo "$d"
out="$(cd "$d" && bash "$tool" "$d" 2>&1)"
[[ "$(jq_field "$out" TEST_COMMAND_SUMMARY)" == "TBD" ]] \
  && ok "B5: no TEST_CMD in environment -> TBD" || bad "B5: got '$out'"

# ---------------------------------------------------------------------------
# Operational failure cases
# ---------------------------------------------------------------------------

# B6: missing .jq filter
d="$work/b6"; mk_repo "$d"
badlib="$work/badlib"; mkdir -p "$badlib"; cp "$tool" "$badlib/"
out="$(cd "$d" && bash "$badlib/primer-init-derive.sh" "$d" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"PROJECT_NAME="* ]] \
  && ok "B6: missing filter -> nonzero exit, no PROJECT_NAME= line" || bad "B6: rc=$rc out='$out'"

# B7: wrong CONTRACT_VERSION
d="$work/b7"; mk_repo "$d"
wronglib="$work/wronglib"; mkdir -p "$wronglib"; cp "$tool" "$wronglib/"
sed 's/CONTRACT_VERSION=1/CONTRACT_VERSION=99/' "$jq_filter" > "$wronglib/primer-init-derive.jq"
out="$(cd "$d" && bash "$wronglib/primer-init-derive.sh" "$d" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"PROJECT_NAME="* ]] \
  && ok "B7: wrong CONTRACT_VERSION -> nonzero exit, no PROJECT_NAME= line" || bad "B7: rc=$rc out='$out'"

# B8: jq absent from PATH
d="$work/b8"; mk_repo "$d"
nojq="$work/nojq"; mkdir -p "$nojq/bin"
for b in bash git awk grep sed head cat mktemp dirname timeout wc tr; do
  p="$(command -v "$b")"; [[ -n "$p" ]] && ln -sf "$p" "$nojq/bin/$b"
done
out="$(cd "$d" && PATH="$nojq/bin" bash "$tool" "$d" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"PROJECT_NAME="* ]] \
  && ok "B8: jq absent from PATH -> nonzero exit, no PROJECT_NAME= line" || bad "B8: rc=$rc out='$out'"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x meta/superpowers/validation/2026-09-09-primer-init-derive-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-primer-init-derive-smoke.zsh
```

Expected: FAIL on every assertion — neither
`hooks/lib/primer-init-derive.jq` nor `hooks/lib/primer-init-derive.sh`
exists yet.

- [ ] **Step 3: Write `hooks/lib/primer-init-derive.jq`**

```jq
# CONTRACT_VERSION=1
# hooks/lib/primer-init-derive.jq — pure placeholder-derivation for
# /session-continuity:primer Step 2 (Init mode). Invoked via
# primer-init-derive.sh; see that file for the CLI contract and
# meta/superpowers/specs/2026-09-09-primer-init-derive-design.md for the
# full output contract this implements.

(if $pkg_name != "" then $pkg_name
 elif $cargo_name != "" then $cargo_name
 elif $pyproject_name != "" then $pyproject_name
 else $dirname end) as $project_name

| ($git_log | split("\n") | map(select(length > 0))
   | map(if test("^\\S+\\s+.*$") then capture("^(?<hash>\\S+)\\s+(?<subject>.*)$")
         else {hash: ., subject: ""} end)
   | .[0:5]) as $commits
| ($commits | length) as $commit_count

| (if $test_cmd == "" then "TBD"
   else
     ( ($test_output | [scan("[0-9]+ pass(?:ed)?")] | .[0]?
        | if . then capture("^(?<n>[0-9]+)").n else null end) as $p
     | ($test_output | [scan("[0-9]+ fail(?:ed)?")] | .[0]?
        | if . then capture("^(?<n>[0-9]+)").n else null end) as $f
     | if $p != null and $f != null then
         "`" + $test_cmd + "` — " + $p + " pass / " + $f + " fail"
       else
         "`" + $test_cmd + "`"
       end
     )
   end) as $test_summary

| "PROJECT_NAME=" + $project_name,
  "WORKING_DIRECTORY_ABSOLUTE_PATH=" + $pwd,
  "COMMIT_COUNT=" + ($commit_count|tostring),
  (range(0;5) as $i
   | "LATEST_COMMIT_HASH_\($i+1)=" + ($commits[$i].hash // ""),
     "LATEST_COMMIT_SUBJECT_\($i+1)=" + ($commits[$i].subject // "")),
  "TEST_CMD=" + $test_cmd,
  "TEST_COMMAND_SUMMARY=" + $test_summary
```

Note: `scan("[0-9]+ pass(?:ed)?")` returns the full matched substring (e.g.
`"12 pass"`), so it needs its own `capture("^(?<n>[0-9]+)")` to pull just the
digits — this mirrors `test-count-rerun.sh`'s two-regex `grep | grep` pipe
(`[0-9]+ pass(ed)?` then `^[0-9]+`) translated into jq's regex functions,
same two-step extraction, same reason (the first regex finds the phrase,
the second isolates the number from it).

Note: the commit-line `if test(...) then capture(...) else {hash:., subject:""} end`
guard exists because `capture(re)` with no match produces **zero outputs**,
not an error and not `null` — confirmed directly: `jq -n '"onetoken" |
capture("^(?<hash>\\S+)\\s+(?<subject>.*)$")'` exits 0 and prints nothing.
A bare `map(capture(...))` would silently drop any line that doesn't match
`<hash><space><subject>`, shrinking `$commits`'s length below the number of
real git-log lines and shifting every subsequent commit into the wrong `_N`
slot. The guard verified against both a no-space line (`"aaa1111"` →
`{hash:"aaa1111", subject:""}`) and a normal line, so `$commits`'s length
always equals the input's non-empty line count.

- [ ] **Step 4: Write `hooks/lib/primer-init-derive.sh`**

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/primer-init-derive.sh — placeholder derivation for
# /session-continuity:primer Step 2 (Init mode). See
# meta/superpowers/specs/2026-09-09-primer-init-derive-design.md for the
# full contract this implements and
# meta/superpowers/plans/2026-09-09-primer-init-derive.md for the
# implementation plan.
#
# Usage: TEST_CMD=<cmd> TEST_OUTPUT=<captured output> primer-init-derive.sh <project-dir>
# TEST_CMD/TEST_OUTPUT are read from the environment, not discovered or
# executed here -- commands/primer.md's Step 2 Bash block already discovers
# and runs the test command once and exports both before calling this
# script. Unset/empty is treated as "no test command" (TEST_COMMAND_SUMMARY
# becomes TBD) -- this script never re-runs a test command itself.
#
# Prints KEY=value lines to stdout on success: PROJECT_NAME,
# WORKING_DIRECTORY_ABSOLUTE_PATH, COMMIT_COUNT, LATEST_COMMIT_HASH_1..5,
# LATEST_COMMIT_SUBJECT_1..5, TEST_CMD, TEST_COMMAND_SUMMARY.
#
# Operational failure (jq missing, primer-init-derive.jq missing or from a
# different CONTRACT_VERSION, <project-dir> not a readable directory) prints
# one diagnostic line to stderr and exits 1 with NO PROJECT_NAME= line on
# stdout at all.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ_FILTER="$SCRIPT_DIR/primer-init-derive.jq"
DIR="${1:-.}"

die() {  # <message>
  printf 'primer-init-derive.sh: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 \
  || die "jq is not installed, so placeholder derivation cannot run."
[[ -r "$JQ_FILTER" ]] \
  || die "primer-init-derive.jq is missing from $SCRIPT_DIR — the plugin cache is incomplete. Run \`/session-continuity:update\`."
grep -q '^# CONTRACT_VERSION=1$' "$JQ_FILTER" \
  || die "primer-init-derive.jq is from a different plugin version — run \`/session-continuity:update\`."
[[ -d "$DIR" ]] \
  || die "$DIR is not a directory."

cd "$DIR" || die "cannot cd into $DIR."

PKG_NAME=""
[[ -f package.json ]] && PKG_NAME="$(grep -m1 '"name"' package.json | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
CARGO_NAME=""
[[ -f Cargo.toml ]] && CARGO_NAME="$(grep -m1 '^name' Cargo.toml | sed -E 's/^name[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')"
PYPROJECT_NAME=""
[[ -f pyproject.toml ]] && PYPROJECT_NAME="$(grep -m1 '^name' pyproject.toml | sed -E 's/^name[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')"
DIRNAME="$(basename "$(pwd)")"

GIT_LOG=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_LOG="$(git log --oneline -5 2>/dev/null || true)"
fi

# TEST_CMD/TEST_OUTPUT are supplied by the caller's environment -- see the
# usage note above. Never discovered or executed here.
TEST_CMD="${TEST_CMD:-}"
TEST_OUTPUT="${TEST_OUTPUT:-}"

PWD_ABS="$(pwd)"

ERRFILE="$(mktemp)"
RESULT="$(
  jq -r -n \
    --arg pkg_name "$PKG_NAME" \
    --arg cargo_name "$CARGO_NAME" \
    --arg pyproject_name "$PYPROJECT_NAME" \
    --arg dirname "$DIRNAME" \
    --arg pwd "$PWD_ABS" \
    --arg git_log "$GIT_LOG" \
    --arg test_cmd "$TEST_CMD" \
    --arg test_output "$TEST_OUTPUT" \
    -f "$JQ_FILTER" 2>"$ERRFILE"
)"
JQ_STATUS=$?
DETAIL="$(head -1 "$ERRFILE" 2>/dev/null)"
rm -f "$ERRFILE"

if [[ "$JQ_STATUS" -ne 0 || -z "$RESULT" ]]; then
  die "the derivation filter failed: ${DETAIL:-jq exited $JQ_STATUS}"
fi

printf '%s\n' "$RESULT"
```

```bash
chmod +x hooks/lib/primer-init-derive.sh
```

- [ ] **Step 5: Run the smoke test to verify all assertions pass**

```bash
zsh meta/superpowers/validation/2026-09-09-primer-init-derive-smoke.zsh
```

Expected: `Result: 21 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add hooks/lib/primer-init-derive.jq hooks/lib/primer-init-derive.sh meta/superpowers/validation/2026-09-09-primer-init-derive-smoke.zsh
git commit -m "feat: add primer-init-derive.sh/.jq, scripting primer Step 2's placeholder derivation"
```

---

### Task 2: `commands/primer.md` — call the script

**Files:**
- Modify: `commands/primer.md` (Step 2 item 6, currently lines 75-117 as of
  `eee17b8`)

**Interfaces:**
- Consumes: `hooks/lib/primer-init-derive.sh` (Task 1), resolved via
  `CLAUDE_PLUGIN_ROOT` and `require_script`, exactly like `primer-detect.sh`
  and `test-count-rerun.sh` already are.

- [ ] **Step 1: Replace item 6 in full**

Using the Edit tool, replace this exact block (currently `commands/primer.md`
lines 75-117 as of `eee17b8`, from `6. Fill in placeholders...` through the
`{{WORKFLOW_CONVENTIONS}} (draft)` bullet):

````markdown
6. Fill in placeholders Claude can derive automatically. Gather the raw
   data in **one Bash call**, timed:

   ```bash
   _PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   pwd
   basename "$(pwd)"
   [ -f package.json ] && grep -m1 '"name"' package.json
   [ -f Cargo.toml ] && grep -m1 '^name' Cargo.toml
   [ -f pyproject.toml ] && grep -m1 '^name' pyproject.toml
   git log --oneline -5
   [ -f package.json ] && grep -A1 '"scripts"' package.json | grep '"test"'
   find . -maxdepth 2 -not -path './node_modules/*' -not -path './.git/*'
   [ -f CLAUDE.md ] && echo "--- CLAUDE.md ---" && cat CLAUDE.md
   grep -rn -B1 -A2 '@module' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' -- src lib 2>/dev/null | head -100
   TEST_CMD=""
   if [ -f package.json ]; then
     TEST_CMD=$(grep -A1 '"scripts"' package.json | grep '"test"' | sed -E 's/.*"test":[[:space:]]*"([^"]+)".*/\1/')
   elif [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
     TEST_CMD="cargo test"
   elif [ -f pyproject.toml ] && command -v pytest >/dev/null 2>&1; then
     TEST_CMD="pytest"
   fi
   if [ -n "$TEST_CMD" ]; then
     echo "--- test run: $TEST_CMD ---"
     TEST_OUTPUT=$(timeout 120 bash -c "$TEST_CMD" 2>&1)
     TEST_EXIT=$?
     echo "$TEST_OUTPUT" | tail -20
     echo "TEST_RUN_EXIT=$TEST_EXIT"
   fi
   _PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   _PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-2-init-derive-placeholders --duration="$_PERF_DURATION"
   ```

   Derive from that output:
   - `{{PROJECT_NAME}}` — from `package.json` `name`, `Cargo.toml` `name`, `pyproject.toml` `name`, or the current directory basename.
   - `{{LATEST_COMMIT_HASH_N}}` / `{{LATEST_COMMIT_SUBJECT_N}}` — from the `git log --oneline -5` output above.
   - `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}` — from the `pwd` output above.
   - `{{TEST_COMMAND_SUMMARY}}` — if `TEST_RUN_EXIT=0` and the captured output contains a recognizable count (`N pass`, `N passed`, `test result: ok. N passed`, etc.), seed this as "`<TEST_CMD>` — N pass / M fail" from that single run. If `TEST_CMD` was empty, the run timed out (`TEST_RUN_EXIT=124`), or the output has no parseable count, fall back to the bare `scripts.test` string (or `TBD`) — never invent a count.
   - `{{REPO_LAYOUT_SUMMARY}}` — from the `find` output above, plus a one-line description Claude infers from the file extensions present.
   - `{{MODULES_TABLE}}` — if the `@module` grep above found matches, build one table row per file: Component = file path, Purpose = the `@module` value (plus the docblock's one-line description if present), Notes = the adjacent `Exports:` line if present. If it found nothing, leave `TBD` as before — don't invent structure that isn't there.
   - `{{WORKFLOW_CONVENTIONS}} (draft)` — if `CLAUDE.md` exists (cat output above), draft this field by quoting its relevant conventions (runtime choice, commit style, workflow/never-do rules) under a "Conventions inherited from CLAUDE.md" sub-heading, instead of leaving it blank for the user to retype. Present the draft in Step 7 for confirmation rather than asking cold.
````

with:

````markdown
6. Fill in placeholders Claude can derive automatically. Gather the raw
   data in **one Bash call**, timed:

   ```bash
   _PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   pwd
   basename "$(pwd)"
   [ -f package.json ] && grep -m1 '"name"' package.json
   [ -f Cargo.toml ] && grep -m1 '^name' Cargo.toml
   [ -f pyproject.toml ] && grep -m1 '^name' pyproject.toml
   git log --oneline -5
   [ -f package.json ] && grep -A1 '"scripts"' package.json | grep '"test"'
   find . -maxdepth 2 -not -path './node_modules/*' -not -path './.git/*'
   [ -f CLAUDE.md ] && echo "--- CLAUDE.md ---" && cat CLAUDE.md
   grep -rn -B1 -A2 '@module' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' -- src lib 2>/dev/null | head -100
   TEST_CMD=""
   if [ -f package.json ]; then
     TEST_CMD=$(grep -A1 '"scripts"' package.json | grep '"test"' | sed -E 's/.*"test":[[:space:]]*"([^"]+)".*/\1/')
   elif [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
     TEST_CMD="cargo test"
   elif [ -f pyproject.toml ] && command -v pytest >/dev/null 2>&1; then
     TEST_CMD="pytest"
   fi
   if [ -n "$TEST_CMD" ]; then
     echo "--- test run: $TEST_CMD ---"
     TEST_OUTPUT=$(timeout 120 bash -c "$TEST_CMD" 2>&1)
     TEST_EXIT=$?
     echo "$TEST_OUTPUT" | tail -20
     echo "TEST_RUN_EXIT=$TEST_EXIT"
   fi
   _PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   _PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-2-init-derive-placeholders --duration="$_PERF_DURATION"
   export TEST_CMD TEST_OUTPUT
   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
   if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-init-derive.sh" 1; then
     DERIVE_OUTPUT="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-init-derive.sh" . 2>&1)"
     DERIVE_STATUS=$?
   else
     DERIVE_OUTPUT="$SC_REQUIRE_SCRIPT_MSG"
     DERIVE_STATUS=1
   fi
   echo "$DERIVE_OUTPUT"
   echo "DERIVE_STATUS=$DERIVE_STATUS"
   ```

   **If `DERIVE_STATUS` is nonzero, or `$DERIVE_OUTPUT` has no
   `PROJECT_NAME=` line:** report `$DERIVE_OUTPUT` to the user and ask for
   `{{PROJECT_NAME}}`, the commit placeholders, and `{{TEST_COMMAND_SUMMARY}}`
   manually in Step 7 below — never fabricate these from a failed script.

   **Otherwise**, fill directly from `$DERIVE_OUTPUT`'s fields:
   - `{{PROJECT_NAME}}` — `PROJECT_NAME`.
   - `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}` — `WORKING_DIRECTORY_ABSOLUTE_PATH`.
   - `{{LATEST_COMMIT_HASH_N}}` / `{{LATEST_COMMIT_SUBJECT_N}}` — for each
     `N` from 1 to `COMMIT_COUNT`, `LATEST_COMMIT_HASH_N` /
     `LATEST_COMMIT_SUBJECT_N`. If `COMMIT_COUNT` is below 5, leave the
     template's remaining `N` slots as `TBD` rather than writing empty pairs.
   - `{{TEST_COMMAND_SUMMARY}}` — `TEST_COMMAND_SUMMARY`, verbatim.
   - `{{REPO_LAYOUT_SUMMARY}}` — from the `find` output above, plus a one-line description Claude infers from the file extensions present.
   - `{{MODULES_TABLE}}` — if the `@module` grep above found matches, build one table row per file: Component = file path, Purpose = the `@module` value (plus the docblock's one-line description if present), Notes = the adjacent `Exports:` line if present. If it found nothing, leave `TBD` as before — don't invent structure that isn't there.
   - `{{WORKFLOW_CONVENTIONS}} (draft)` — if `CLAUDE.md` exists (cat output above), draft this field by quoting its relevant conventions (runtime choice, commit style, workflow/never-do rules) under a "Conventions inherited from CLAUDE.md" sub-heading, instead of leaving it blank for the user to retype. Present the draft in Step 7 for confirmation rather than asking cold.
````

Note what changed and what didn't: the raw gathering Bash block is
byte-for-byte identical through the `fi` that closes the test-run block;
only three lines are added after the existing `perf-log.sh record` call
(`export TEST_CMD TEST_OUTPUT`, the `require_script`/script-call block, and
the two `echo` lines). The `{{REPO_LAYOUT_SUMMARY}}`, `{{MODULES_TABLE}}`,
and `{{WORKFLOW_CONVENTIONS}} (draft)` bullets are carried over verbatim,
unchanged — only the four mechanical bullets above them are replaced.

- [ ] **Step 2: Verify the old prose is gone**

```bash
grep -c 'from the .git log --oneline -5. output above\|seed this as' commands/primer.md
```

Expected: `0` — the derivation mechanics now live only in
`primer-init-derive.jq`, referenced by its output fields everywhere else.

- [ ] **Step 3: Commit**

```bash
git add commands/primer.md
git commit -m "refactor: primer.md Step 2 item 6 dispatches via primer-init-derive.sh"
```

---

### Task 3: Doc pointers, regression pass, changelog

**Files:**
- Modify: `meta/superpowers/specs/2026-09-02-determinism-program-design.md`
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Update the design doc's Phase 6 entry**

Using the Edit tool, replace the "Still pending: C ... D ... E ..." sentence
at the end of the Phase 6 entry in
`meta/superpowers/specs/2026-09-02-determinism-program-design.md` with a
version that adds "**Sub-project D shipped** — Step 2's placeholder
derivation (`{{PROJECT_NAME}}`, commit hash/subject pairs,
`{{TEST_COMMAND_SUMMARY}}`), now `hooks/lib/primer-init-derive.sh`/`.jq`.
Spec: `meta/superpowers/specs/2026-09-09-primer-init-derive-design.md`. Plan:
`meta/superpowers/plans/2026-09-09-primer-init-derive.md`." and narrows
"Still pending" to just C and E.

- [ ] **Step 2: Full regression pass**

```bash
for f in \
  meta/superpowers/validation/2026-09-09-primer-init-derive-smoke.zsh \
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

Add a new section at the top of `CHANGELOG.md`, directly under the
`# Changelog` header and its description line:

```markdown
## [0.34.0] — 2026-09-09

### Changed
- **`/session-continuity:primer`'s Step 2 placeholder derivation is now
  scripted.** New `hooks/lib/primer-init-derive.sh`/`.jq` replace four
  hand-evaluated derivations (`{{PROJECT_NAME}}`'s manifest-priority pick,
  `{{LATEST_COMMIT_HASH_N}}`/`{{LATEST_COMMIT_SUBJECT_N}}`'s git-log split,
  `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}`'s passthrough,
  `{{TEST_COMMAND_SUMMARY}}`'s pass/fail-count regex) with one script call.
  `{{MODULES_TABLE}}`'s docblock parsing, `{{REPO_LAYOUT_SUMMARY}}`'s
  inferred sentence, and `{{WORKFLOW_CONVENTIONS}}`'s draft stay prose —
  each depends on arbitrary per-project convention, not a fixed format, the
  same reasoning that already excluded the latter two from this program.
  Determinism Phase 6 (#43) sub-project D; sub-projects C and E remain
  pending.
```

- [ ] **Step 4: Bump the plugin version**

Using the Edit tool, update `.claude-plugin/plugin.json`'s `"version"` field
from `"0.33.0"` to `"0.34.0"`.

- [ ] **Step 5: Commit**

```bash
git add meta/superpowers/specs/2026-09-02-determinism-program-design.md CHANGELOG.md .claude-plugin/plugin.json
git commit -m "docs: Phase 6 sub-project D doc pointers, changelog, and version bump"
```
