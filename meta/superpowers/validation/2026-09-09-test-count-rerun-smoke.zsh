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

# B3: no-count mode -- backtick command present, no parseable count.
# Must NOT run the suite (nothing to compare; primer never seeds OBSERVED).
d="$work/b3"; mk_repo "$d" '`./fake-test.sh`'
lc="$(last_commit "$d")"
touch "$d/some-file"
git -C "$d" add -A; git -C "$d" commit -qm "code change"
fake_cmd "$d" "$d/counter" "3"
out="$(cd "$d" && COUNTER_FILE="$d/counter" bash "$tool" "$d" "$lc" 2>&1)"
invocations="$(wc -l < "$d/counter" | tr -d ' ')"
[[ "$(jq_field "$out" MODE)" == "no-count" && "$(jq_field "$out" RETRIES)" == "0" && "$invocations" == "0" ]] \
  && ok "B3: bare command, no count -> no-count, zero runs" \
  || bad "B3: got '$out' (invocations=$invocations)"

# B4: run mode, first-run match -> exactly 1 invocation, no drift
d="$work/b4"; mk_repo "$d" '`./fake-test.sh` — 3 pass / 0 fail'
lc="$(last_commit "$d")"
touch "$d/some-file"
git -C "$d" add -A; git -C "$d" commit -qm "code change"
fake_cmd "$d" "$d/counter" "3"
out="$(cd "$d" && COUNTER_FILE="$d/counter" bash "$tool" "$d" "$lc" 2>&1)"
invocations="$(wc -l < "$d/counter" | tr -d ' ')"
[[ "$(jq_field "$out" MODE)" == "run" && "$(jq_field "$out" DRIFT)" == "0" && "$invocations" == "1" ]] \
  && ok "B4: first-run match -> 1 invocation, no drift" || bad "B4: got '$out' (invocations=$invocations)"

# B5: run mode, first-run mismatch -> retries to 3, drift confirmed
d="$work/b5"; mk_repo "$d" '`./fake-test.sh` — 3 pass / 0 fail'
lc="$(last_commit "$d")"
touch "$d/some-file"
git -C "$d" add -A; git -C "$d" commit -qm "code change"
fake_cmd "$d" "$d/counter" "4" "4" "4"
out="$(cd "$d" && COUNTER_FILE="$d/counter" bash "$tool" "$d" "$lc" 2>&1)"
invocations="$(wc -l < "$d/counter" | tr -d ' ')"
[[ "$(jq_field "$out" DRIFT)" == "1" && "$(jq_field "$out" PINNED_COUNT)" == "4" && "$invocations" == "3" ]] \
  && ok "B5: mismatch -> 3 invocations, drift confirmed" || bad "B5: got '$out' (invocations=$invocations)"

# B6: run mode, all 3 runs unparseable -> well-formed OBSERVED, no crash
d="$work/b6"; mk_repo "$d" '`./fake-test.sh` — 3 pass / 0 fail'
lc="$(last_commit "$d")"
touch "$d/some-file"
git -C "$d" add -A; git -C "$d" commit -qm "code change"
fake_cmd "$d" "$d/counter" "UNPARSEABLE" "UNPARSEABLE" "UNPARSEABLE"
out="$(cd "$d" && COUNTER_FILE="$d/counter" bash "$tool" "$d" "$lc" 2>&1)"
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
