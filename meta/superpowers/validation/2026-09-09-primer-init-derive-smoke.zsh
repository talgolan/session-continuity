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
