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

mk_bash_call() {  # <ts> <tool_use_id> <command>
  jline "{\"type\":\"assistant\",\"timestamp\":\"$1\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"id\":\"$2\",\"input\":{\"command\":\"$3\"}}]}}"
}
mk_result() {  # <ts> <tool_use_id> <is_error> <text>
  jline "{\"type\":\"user\",\"timestamp\":\"$1\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"$2\",\"is_error\":$3,\"content\":\"$4\"}]}}"
}

a_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:00:01.000Z" "t1" true "Exit code 1\\nFAIL src/foo.test.ts"
  mk_bash_call "2026-09-01T00:01:00.000Z" "t2" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:01:01.000Z" "t2" true "Exit code 1\\nFAIL src/foo.test.ts"
  mk_bash_call "2026-09-01T00:02:00.000Z" "t3" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:02:01.000Z" "t3" false "Exit code 0\\nPASS"
} > "$a_f"
out="$(bash "$lib/candidate-extract.sh" "$a_f")"
if print -r -- "$out" | jq -e '.candidates | any(.heuristic == "retry-burst")' >/dev/null 2>&1; then
  ok "Heuristic A: 3x identical command triggers retry-burst"
else
  bad "Heuristic A did not trigger: $out"
fi
# $a_f is reused below in the determinism check -- cleaned up there, not here.

# --- Heuristic B: revert / reset (needs a real tracked file) ---------------

repo_dir="$(gt_make_repo)"
gt_stage "$repo_dir" "src/broken.ts" "old content"
git -C "$repo_dir" commit -q -m "add broken.ts"
b_f="$(mktemp)"
mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "rm -rf src/broken.ts" > "$b_f"
out="$(cd "$repo_dir" && bash "$lib/candidate-extract.sh" "$b_f")"
if print -r -- "$out" | jq -e '.candidates | any(.heuristic == "revert")' >/dev/null 2>&1; then
  ok "Heuristic B: rm -rf on a tracked file triggers revert"
else
  bad "Heuristic B did not trigger: $out"
fi
rm -f "$b_f"
gt_cleanup "$repo_dir"

# --- Heuristic C: error recurrence ------------------------------------------

c_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "bun run build"
  mk_result    "2026-09-01T00:00:01.000Z" "t1" true "Error: Cannot find module 'foo'"
  mk_bash_call "2026-09-01T00:05:00.000Z" "t2" "bun run build"
  mk_result    "2026-09-01T00:05:01.000Z" "t2" true "Error: Cannot find module 'foo'"
  mk_bash_call "2026-09-01T00:20:00.000Z" "t3" "bun run build"
  mk_result    "2026-09-01T00:20:01.000Z" "t3" true "Error: Cannot find module 'foo'"
} > "$c_f"
out="$(bash "$lib/candidate-extract.sh" "$c_f")"
if print -r -- "$out" | jq -e '.candidates | any(.heuristic == "error-recurrence")' >/dev/null 2>&1; then
  ok "Heuristic C: 3x same error over >=15min triggers error-recurrence"
else
  bad "Heuristic C did not trigger: $out"
fi
rm -f "$c_f"

# --- Heuristic D: fix burst ---------------------------------------------------

d_f="$(mktemp)"
{
  # 10 investigatory calls, one per minute 00:00..00:09, all inside the 30
  # minutes preceding the 00:15 fix commit.
  for i in 00 01 02 03 04 05 06 07 08 09; do
    mk_bash_call "2026-09-01T00:${i}:00.000Z" "d$i" "bun test src/bar.test.ts"
    mk_result    "2026-09-01T00:${i}:01.000Z" "d$i" true "Exit code 1\\nFAIL src/bar.test.ts"
  done
  # single-quoted commit message -- mk_bash_call interpolates $3 straight
  # into a JSON string with no escaping, so it must not contain a `"`.
  mk_bash_call "2026-09-01T00:15:00.000Z" "dc" "git commit -m 'fix(bar): correct off-by-one in parser'"
} > "$d_f"
out="$(bash "$lib/candidate-extract.sh" "$d_f")"
if print -r -- "$out" | jq -e '.candidates | any(.heuristic == "fix-burst")' >/dev/null 2>&1; then
  ok "Heuristic D: fix commit preceded by >=10 calls in 30min triggers fix-burst"
else
  bad "Heuristic D did not trigger: $out"
fi
rm -f "$d_f"

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
