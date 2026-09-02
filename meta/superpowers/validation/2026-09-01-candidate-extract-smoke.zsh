#!/usr/bin/env zsh
# candidate-extract.sh smoke test. Hermetic: synthetic JSONL fixtures, a
# throwaway git repo for the tracked-file check, temp files cleaned up.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
source "$here/lib/gate-test-common.zsh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

jline() { print -r -- "$1"; }  # readability alias

work_ce="$(mktemp -d)"
mk_edit() {  # <ts> <tool_use_id>
  jline "{\"type\":\"assistant\",\"timestamp\":\"$1\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Edit\",\"id\":\"$2\",\"input\":{\"file_path\":\"/tmp/x.ts\"}}]}}"
}
mk_bash_call() {  # <ts> <tool_use_id> <command>
  jline "{\"type\":\"assistant\",\"timestamp\":\"$1\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"id\":\"$2\",\"input\":{\"command\":\"$3\"}}]}}"
}
mk_result() {  # <ts> <tool_use_id> <is_error> <text>
  jline "{\"type\":\"user\",\"timestamp\":\"$1\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"$2\",\"is_error\":$3,\"content\":\"$4\"}]}}"
}

# --- degradation cases (now include detail field per new taxonomy) -----------

out="$(bash "$lib/candidate-extract.sh" /no/such/file.jsonl)"
mode="$(print -r -- "$out" | jq -r .mode)"
[[ "$mode" == "unavailable" ]] && ok "missing transcript -> mode:unavailable" || bad "missing transcript: got $out"

empty_f="$(mktemp)"
out="$(bash "$lib/candidate-extract.sh" "$empty_f")"
mode="$(print -r -- "$out" | jq -r .mode)"
[[ "$mode" == "unavailable" ]] && ok "empty transcript -> mode:unavailable" || bad "empty transcript: got $out"
rm -f "$empty_f"

stale_f="$(mktemp)"
jline '{"type":"user","timestamp":"2026-01-01T00:00:00.000Z","message":{"content":[]}}' > "$stale_f"
touch -t 202001010000 "$stale_f" 2>/dev/null || touch -mt 202001010000 "$stale_f"
out="$(bash "$lib/candidate-extract.sh" "$stale_f")"
mode="$(print -r -- "$out" | jq -r .mode)"
[[ "$mode" == "unavailable" ]] && ok "stale (>5min old) transcript -> mode:unavailable" || bad "stale transcript: got $out"
rm -f "$stale_f"

# --- Heuristic A: retry burst ------------------------------------------------

a_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:00:01.000Z" "t1" true "Exit code 1\\nFAIL src/foo.test.ts"
  mk_edit      "2026-09-01T00:00:30.000Z" "e1"
  mk_bash_call "2026-09-01T00:01:00.000Z" "t2" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:01:01.000Z" "t2" true "Exit code 1\\nFAIL src/foo.test.ts"
  mk_bash_call "2026-09-01T00:02:00.000Z" "t3" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:02:01.000Z" "t3" false "Exit code 0\\nPASS"
} > "$a_f"
out="$(bash "$lib/candidate-extract.sh" "$a_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "retry-burst")' >/dev/null 2>&1 \
  && ok "Heuristic A: 3x identical command with an edit between triggers retry-burst" \
  || bad "Heuristic A did not trigger: $out"

# Same burst, no edit between: polling, not investigation.
noedit_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "n1" "bun test src/foo.test.ts"
  mk_bash_call "2026-09-01T00:01:00.000Z" "n2" "bun test src/foo.test.ts"
  mk_bash_call "2026-09-01T00:02:00.000Z" "n3" "bun test src/foo.test.ts"
} > "$noedit_f"
out="$(bash "$lib/candidate-extract.sh" "$noedit_f")"
[[ "$(print -r -- "$out" | jq '.candidates | length')" -eq 0 ]] \
  && ok "Heuristic A: a burst with no file edits produces nothing" \
  || bad "Heuristic A fired without any file edit: $out"
rm -f "$noedit_f"

# Regression: three heredoc commits are three different commands, not a burst.
heredoc_f="$(mktemp)"
{
  for i in 1 2 3; do
    jline "{\"type\":\"assistant\",\"timestamp\":\"2026-09-01T00:0${i}:00.000Z\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"id\":\"h$i\",\"input\":{\"command\":\"git commit -m \\\"\$(cat <<'EOF'\\nfix(area): change number $i\\nEOF\\n)\\\"\"}}]}}"
    mk_edit "2026-09-01T00:0${i}:30.000Z" "he$i"
  done
} > "$heredoc_f"
out="$(bash "$lib/candidate-extract.sh" "$heredoc_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "retry-burst")' >/dev/null 2>&1 \
  && bad "heredoc commits were grouped as a retry burst: $out" \
  || ok "Heuristic A: heredoc commits with different bodies are not a burst"
rm -f "$heredoc_f"

# Regression: bookkeeping commands never surface.
book_f="$(mktemp)"
{
  for i in 1 2 3 4; do
    mk_bash_call "2026-09-01T00:0${i}:00.000Z" "b$i" "git status --short"
    mk_edit      "2026-09-01T00:0${i}:30.000Z" "be$i"
  done
} > "$book_f"
out="$(bash "$lib/candidate-extract.sh" "$book_f")"
[[ "$(print -r -- "$out" | jq '.candidates | length')" -eq 0 ]] \
  && ok "Heuristic A: git status is bookkeeping, not investigation" \
  || bad "bookkeeping command produced a candidate: $out"
rm -f "$book_f"

# Variants differing only in a numeric flag value merge into one candidate.
fam_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "f1" "bun test 2>&1 | tail -8"
  mk_edit      "2026-09-01T00:00:30.000Z" "fe1"
  mk_bash_call "2026-09-01T00:01:00.000Z" "f2" "bun test 2>&1 | tail -10"
  mk_bash_call "2026-09-01T00:02:00.000Z" "f3" "bun test 2>&1 | tail -15"
} > "$fam_f"
out="$(bash "$lib/candidate-extract.sh" "$fam_f")"
n="$(print -r -- "$out" | jq '[.candidates[] | select(.heuristic=="retry-burst")] | length')"
[[ "$n" -eq 1 ]] && ok "Heuristic A: tail -8/-10/-15 merge into one candidate" \
  || bad "expected 1 merged retry-burst, got $n: $out"
rm -f "$fam_f"

# --- Heuristic B: revert / reset (needs a real tracked file) ---------------

repo_dir="$(gt_make_repo)"
gt_stage "$repo_dir" "src/broken.ts" "old content"
git -C "$repo_dir" commit -q -m "add broken.ts"
b_f="$(mktemp)"
mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "rm -rf src/broken.ts" > "$b_f"
out="$(cd "$repo_dir" && bash "$lib/candidate-extract.sh" "$b_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "revert")' >/dev/null 2>&1 \
  && ok "Heuristic B: rm -rf on a tracked file triggers revert" \
  || bad "Heuristic B did not trigger: $out"
rm -f "$b_f"
gt_cleanup "$repo_dir"

# Regression: a command that merely mentions the revert verbs is not a revert.
# The real false positive was the jq program that ran this heuristic by hand.
mention_f="$(mktemp)"
mk_bash_call "2026-09-01T00:00:00.000Z" "m1" \
  "jq -r 'select(.command | test(\\\"git reset --hard|git revert|git restore\\\"))' /tmp/extracted.json" > "$mention_f"
out="$(bash "$lib/candidate-extract.sh" "$mention_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "revert")' >/dev/null 2>&1 \
  && bad "a command merely mentioning the revert verbs was treated as a revert: $out" \
  || ok "Heuristic B: revert verbs only count at a command position"
rm -f "$mention_f"

# A real revert behind unrelated leading commands is still found, and the title
# names the segment that matched rather than the head of the command.
seg_f="$(mktemp)"
mk_bash_call "2026-09-01T00:00:00.000Z" "s1" \
  "tmux kill-session -t smoke 2>/dev/null; git checkout -- docs/history.jsonl; echo done" > "$seg_f"
out="$(bash "$lib/candidate-extract.sh" "$seg_f")"
title="$(print -r -- "$out" | jq -r '.candidates[] | select(.heuristic=="revert") | .title')"
[[ "$title" == "Reverted approach: git checkout -- docs/history.jsonl." ]] \
  && ok "Heuristic B: the title names the matched segment" \
  || bad "Heuristic B title was not the matched segment: $title"
rm -f "$seg_f"

# --- Heuristic C: error recurrence ------------------------------------------

c_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "c1" "bun run build"
  mk_result    "2026-09-01T00:00:01.000Z" "c1" true "Exit code 1\\nError: Cannot find module 'foo'"
  mk_bash_call "2026-09-01T00:08:00.000Z" "c2" "bun run build"
  mk_result    "2026-09-01T00:08:01.000Z" "c2" true "Exit code 1\\nError: Cannot find module 'foo'"
} > "$c_f"
out="$(bash "$lib/candidate-extract.sh" "$c_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "error-recurrence")' >/dev/null 2>&1 \
  && ok "Heuristic C: 2x same error over >=5min triggers error-recurrence" \
  || bad "Heuristic C did not trigger: $out"
print -r -- "$out" | jq -r '.candidates[] | select(.heuristic=="error-recurrence") | .title' | grep -q 'Cannot find module' \
  && ok "Heuristic C: title carries the error message, not the exit-code line" \
  || bad "Heuristic C title was not the error message: $out"
rm -f "$c_f"

# A test runner's version banner is not the error. Prefer a line that reads
# like one.
banner_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "v1" "bun test"
  mk_result    "2026-09-01T00:00:01.000Z" "v1" true "Exit code 1\\nbun test v1.3.14 (0d9b296a)\\nFAIL src/x.test.ts"
  mk_bash_call "2026-09-01T00:08:00.000Z" "v2" "bun test"
  mk_result    "2026-09-01T00:08:01.000Z" "v2" true "Exit code 1\\nbun test v1.3.14 (0d9b296a)\\nFAIL src/x.test.ts"
} > "$banner_f"
out="$(bash "$lib/candidate-extract.sh" "$banner_f")"
title="$(print -r -- "$out" | jq -r '.candidates[] | select(.heuristic=="error-recurrence") | .title')"
[[ "$title" == *"FAIL src/x.test.ts"* ]] && ok "Heuristic C: skips the version banner for the failing line" \
  || bad "Heuristic C picked the version banner: $title"
rm -f "$banner_f"

# Long error text is capped so a recurring hook-deny message cannot become a
# several-hundred-character candidate title.
long_f="$(mktemp)"
long_err="Error: $(printf 'x%.0s' {1..400})"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "l1" "bun run build"
  mk_result    "2026-09-01T00:00:01.000Z" "l1" true "Exit code 1\\n$long_err"
  mk_bash_call "2026-09-01T00:08:00.000Z" "l2" "bun run build"
  mk_result    "2026-09-01T00:08:01.000Z" "l2" true "Exit code 1\\n$long_err"
} > "$long_f"
out="$(bash "$lib/candidate-extract.sh" "$long_f")"
title="$(print -r -- "$out" | jq -r '.candidates[] | select(.heuristic=="error-recurrence") | .title')"
[[ "${#title}" -lt 200 ]] && ok "Heuristic C: long error text is truncated in the title" \
  || bad "Heuristic C title was ${#title} chars: $title"
rm -f "$long_f"

# --- Heuristic D: fix burst ---------------------------------------------------

d_f="$(mktemp)"
{
  # 12 investigatory calls; the first 3 share a family, giving the cluster.
  for i in 00 01 02; do
    mk_bash_call "2026-09-01T00:${i}:00.000Z" "d$i" "bun test src/bar.test.ts 2>&1 | tail -10"
    mk_result    "2026-09-01T00:${i}:01.000Z" "d$i" true "Exit code 1\\nFAIL src/bar.test.ts"
    mk_edit      "2026-09-01T00:${i}:30.000Z" "de$i"
  done
  for i in 03 04 05 06 07 08 09 10 11; do
    mk_bash_call "2026-09-01T00:${i}:00.000Z" "x$i" "bun run build --target $i"
  done
  jline "{\"type\":\"assistant\",\"timestamp\":\"2026-09-01T00:15:00.000Z\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"id\":\"dc\",\"input\":{\"command\":\"git commit -m 'fix(bar): correct off-by-one in parser'\"}}]}}"
} > "$d_f"
out="$(bash "$lib/candidate-extract.sh" "$d_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "fix-burst")' >/dev/null 2>&1 \
  && ok "Heuristic D: fix commit after a clustered investigation triggers fix-burst" \
  || bad "Heuristic D did not trigger: $out"
title="$(print -r -- "$out" | jq -r '.candidates[] | select(.heuristic=="fix-burst") | .title')"
[[ "$title" == "fix(bar): correct off-by-one in parser"* ]] \
  && ok "Heuristic D: title starts with the parsed commit subject" \
  || bad "Heuristic D title was not the parsed subject: $title"
[[ "$title" != *"git commit"* ]] && ok "Heuristic D: title carries no raw command text" \
  || bad "Heuristic D title leaked the raw command: $title"
rm -f "$d_f"

# A fix commit with no retry cluster in its window is a straightforward fix.
d2_f="$(mktemp)"
{
  for i in 00 01 02 03 04 05 06 07 08 09 10 11; do
    mk_bash_call "2026-09-01T00:${i}:00.000Z" "y$i" "bun run build --target $i"
  done
  jline "{\"type\":\"assistant\",\"timestamp\":\"2026-09-01T00:15:00.000Z\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"id\":\"dc2\",\"input\":{\"command\":\"git commit -m 'fix(bar): rename a variable'\"}}]}}"
} > "$d2_f"
out="$(bash "$lib/candidate-extract.sh" "$d2_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "fix-burst")' >/dev/null 2>&1 \
  && bad "fix-burst fired with no retry cluster in the window: $out" \
  || ok "Heuristic D: no retry cluster means no fix-burst"
rm -f "$d2_f"

# --- per-heuristic cap --------------------------------------------------------

cap_f="$(mktemp)"
{
  # Three genuinely distinct command families -- not the same command with
  # one substring swapped -- so their titles share only the boilerplate
  # suffix and don't Jaccard-collapse under dedup before the cap can trim
  # them. (An earlier draft used "bun test src/$fam.test.ts" for fam in
  # alpha/beta/gamma; those titles differ by one token out of sixteen and
  # overlap() scored them at 1.0, so dedup -- not the cap -- was what
  # produced the survivor count. Verified via a standalone jq check.)
  mk_bash_call "2026-09-01T01:01:00.000Z" "cap1a" "bun test src/foo.test.ts"
  mk_bash_call "2026-09-01T02:02:00.000Z" "cap1b" "bun test src/foo.test.ts"
  mk_bash_call "2026-09-01T03:03:00.000Z" "cap1c" "bun test src/foo.test.ts"
  mk_edit      "2026-09-01T01:30:00.000Z" "cape1"

  mk_bash_call "2026-09-01T04:04:00.000Z" "cap2a" "pytest tests/bar_test.py -k slow"
  mk_bash_call "2026-09-01T05:05:00.000Z" "cap2b" "pytest tests/bar_test.py -k slow"
  mk_bash_call "2026-09-01T06:06:00.000Z" "cap2c" "pytest tests/bar_test.py -k slow"
  mk_edit      "2026-09-01T04:30:00.000Z" "cape2"

  mk_bash_call "2026-09-01T07:07:00.000Z" "cap3a" "cargo test --package qux integration"
  mk_bash_call "2026-09-01T08:08:00.000Z" "cap3b" "cargo test --package qux integration"
  mk_bash_call "2026-09-01T09:09:00.000Z" "cap3c" "cargo test --package qux integration"
  mk_edit      "2026-09-01T07:30:00.000Z" "cape3"
} > "$cap_f"
out="$(bash "$lib/candidate-extract.sh" "$cap_f")"
n="$(print -r -- "$out" | jq '[.candidates[] | select(.heuristic=="retry-burst")] | length')"
[[ "$n" -eq 2 ]] && ok "per-heuristic cap keeps at most 2 retry-bursts" \
  || bad "expected 2 retry-bursts after the cap, got $n: $out"
[[ "$(print -r -- "$out" | jq .overflow)" -eq 1 ]] && ok "the capped candidate is counted in overflow" \
  || bad "overflow did not count the capped candidate: $out"
rm -f "$cap_f"

# --- privacy ------------------------------------------------------------------

priv_f="$(mktemp)"
{
  for i in 1 2 3; do
    mk_bash_call "2026-09-01T00:0${i}:00.000Z" "p$i" "bun test /Users/someone/secretproj/src/a.test.ts"
  done
  mk_edit "2026-09-01T00:01:30.000Z" "pe1"
} > "$priv_f"
out="$(bash "$lib/candidate-extract.sh" "$priv_f")"
print -r -- "$out" | grep -q '/Users/someone/' \
  && bad "a home directory path reached the candidate output: $out" \
  || ok "home directory paths are rewritten to ~/"
rm -f "$priv_f"

# --- failure taxonomy: bad input vs broken install ---------------------------

out="$(bash "$lib/candidate-extract.sh" /no/such/file.jsonl)"
mode="$(print -r -- "$out" | jq -r .mode)"
[[ "$mode" == "unavailable" ]] && ok "missing transcript -> mode:unavailable" || bad "missing transcript gave mode:$mode"
[[ -n "$(print -r -- "$out" | jq -r .detail)" ]] && ok "unavailable carries a detail string" || bad "unavailable had an empty detail"

# A missing .jq sibling is an install fault, not missing input.
mkdir -p "$work_ce/orphan"
cp "$lib/candidate-extract.sh" "$work_ce/orphan/"
fresh_f="$(mktemp)"
mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "bun test" > "$fresh_f"
out="$(bash "$work_ce/orphan/candidate-extract.sh" "$fresh_f")"
mode="$(print -r -- "$out" | jq -r .mode)"
[[ "$mode" == "error" ]] && ok "missing candidate-extract.jq -> mode:error" || bad "missing .jq gave mode:$mode (out: $out)"
print -r -- "$out" | jq -r .detail | grep -q 'session-continuity:update' \
  && ok "mode:error names the update command" || bad "mode:error detail was unhelpful: $out"

# A contract-skewed .jq sibling is also an install fault.
mkdir -p "$work_ce/skewed"
cp "$lib/candidate-extract.sh" "$work_ce/skewed/"
sed 's/^# CONTRACT_VERSION=2$/# CONTRACT_VERSION=1/' "$lib/candidate-extract.jq" > "$work_ce/skewed/candidate-extract.jq"
out="$(bash "$work_ce/skewed/candidate-extract.sh" "$fresh_f")"
mode="$(print -r -- "$out" | jq -r .mode)"
[[ "$mode" == "error" ]] && ok "contract-skewed .jq -> mode:error" || bad "contract-skewed .jq gave mode:$mode"

# A malformed timestamp must not abort the whole filter.
mixed_f="$(mktemp)"
{
  jline '{"type":"assistant","timestamp":"not-a-timestamp","message":{"content":[{"type":"tool_use","name":"Bash","id":"bad","input":{"command":"bun test src/x.test.ts"}}]}}'
  mk_bash_call "2026-09-01T00:00:00.000Z" "m1" "bun test src/x.test.ts"
  mk_edit      "2026-09-01T00:00:30.000Z" "e1"
  mk_bash_call "2026-09-01T00:01:00.000Z" "m2" "bun test src/x.test.ts"
  mk_bash_call "2026-09-01T00:02:00.000Z" "m3" "bun test src/x.test.ts"
} > "$mixed_f"
out="$(bash "$lib/candidate-extract.sh" "$mixed_f")"
mode="$(print -r -- "$out" | jq -r .mode)"
[[ "$mode" == "transcript" ]] && ok "a malformed timestamp does not abort the filter" \
  || bad "malformed timestamp gave mode:$mode (out: $out)"
rm -f "$mixed_f" "$fresh_f"

# --- self-timing ------------------------------------------------------------

timing_repo="$(gt_make_repo)"
timing_f="$(mktemp)"
mk_bash_call "2026-09-01T00:00:00.000Z" "s1" "bun test" > "$timing_f"
( cd "$timing_repo" && bash "$lib/candidate-extract.sh" "$timing_f" > /dev/null )
if grep -q '"step":"step-2-transcript-extraction"' "$timing_repo/.session-continuity/performance.log" 2>/dev/null; then
  ok "the script logs its own step-2-transcript-extraction line"
else
  bad "no step-2-transcript-extraction line was logged by the script"
fi
rm -f "$timing_f"
gt_cleanup "$timing_repo"

# --- determinism -------------------------------------------------------------

out1="$(bash "$lib/candidate-extract.sh" "$a_f" 2>/dev/null || true)"
a_f2="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:00:01.000Z" "t1" true "Exit code 1\\nFAIL src/foo.test.ts"
  mk_edit      "2026-09-01T00:00:30.000Z" "e1"
  mk_bash_call "2026-09-01T00:01:00.000Z" "t2" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:01:01.000Z" "t2" true "Exit code 1\\nFAIL src/foo.test.ts"
  mk_bash_call "2026-09-01T00:02:00.000Z" "t3" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:02:01.000Z" "t3" false "Exit code 0\\nPASS"
} > "$a_f2"
out2="$(bash "$lib/candidate-extract.sh" "$a_f2")"
[[ "$out1" == "$out2" ]] && ok "determinism: identical transcript twice -> identical JSON" || bad "determinism: outputs differ"
rm -f "$a_f" "$a_f2"

rm -rf "$work_ce"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
