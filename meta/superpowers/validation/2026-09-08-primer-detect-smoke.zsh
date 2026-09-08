#!/usr/bin/env zsh
# primer-detect.sh/.jq smoke test. Hermetic: one scratch git repo per case,
# built fresh via mk_repo. No mocking needed -- every fact is a real file
# or a real git command against a real (throwaway) repository.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
tool="$lib/primer-detect.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# mk_repo <dir> <split:0|1> <oi_file:0|1> <bl_file:0|1> <inline:0|1> <origin:gh|other> <staged:none|code|docs>
# Builds a fresh scratch repo with .session-continuity/ populated per the
# flags, commits everything, then writes SESSION_PRIMER.md's log block to
# exactly match the post-commit `git log --oneline -5` (never re-committed
# afterward -- see this plan's Task 1 notes on why that avoids a
# self-referential-hash problem). Callers that want DRIFT instead
# overwrite the block themselves after calling mk_repo.
mk_repo() {
  local dir="$1" split=$2 oi=$3 bl=$4 inline=$5 origin=$6 staged=$7
  rm -rf "$dir"
  mkdir -p "$dir/.session-continuity"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name Test
  if [[ "$origin" == "gh" ]]; then
    git -C "$dir" remote add origin https://github.com/example/repo.git
  else
    git -C "$dir" remote add origin https://example.com/example/repo.git
  fi
  : > "$dir/.session-continuity/LEARNINGS.md"
  (( split ))  && : > "$dir/.session-continuity/PROJECT_CONTEXT.md"
  : > "$dir/.session-continuity/ROADMAP.md"
  (( oi ))     && : > "$dir/.session-continuity/OUTSTANDING_ITEMS.md"
  (( bl ))     && : > "$dir/.session-continuity/BACKLOG.md"
  local heading=""
  (( inline )) && heading=$'## Outstanding items\n1. something\n\n'
  print -r -- "${heading}# Primer

placeholder body, overwritten below with the real log block
" > "$dir/.session-continuity/SESSION_PRIMER.md"
  git -C "$dir" add -A
  git -C "$dir" commit -qm init
  local log
  log="$(git -C "$dir" log --oneline -5)"
  print -r -- "${heading}# Primer

**Current \`git log --oneline -5\` (primary branch):**

\`\`\`
$log
\`\`\`
" > "$dir/.session-continuity/SESSION_PRIMER.md"
  case "$staged" in
    code) print -r -- x > "$dir/src.js"; git -C "$dir" add src.js ;;
    docs) print -r -- x >> "$dir/.session-continuity/LEARNINGS.md"; git -C "$dir" add .session-continuity/LEARNINGS.md ;;
  esac
}

steps_of() { bash "$tool" "$1" | awk -F= '/^STEPS=/{print $2}'; }

# --- 1: fresh install (no .session-continuity/ at all) -> init -------------
d="$work/case1"; mkdir -p "$d"
git -C "$d" init -q; git -C "$d" config user.email t@t.com; git -C "$d" config user.name T
: > "$d/README.md"; git -C "$d" add -A; git -C "$d" commit -qm init
git -C "$d" remote add origin https://github.com/example/repo.git
[[ "$(steps_of "$d")" == "init" ]] && ok "1: fresh install -> init" || bad "1: got '$(steps_of "$d")'"

# --- 2: existing unsplit primer, otherwise current -> split -----------------
d="$work/case2"; mk_repo "$d" 0 0 1 0 other none
[[ "$(steps_of "$d")" == "split" ]] && ok "2: unsplit only -> split" || bad "2: got '$(steps_of "$d")'"

# --- 3: split + current + clean -> empty ------------------------------------
d="$work/case3"; mk_repo "$d" 1 0 1 0 other none
[[ "$(steps_of "$d")" == "" ]] && ok "3: split+current+clean -> empty" || bad "3: got '$(steps_of "$d")'"

# --- 4: recorded log block differs from actual -> refresh -------------------
d="$work/case4"; mk_repo "$d" 1 0 1 0 other none
print -r -- "# Primer

**Current \`git log --oneline -5\` (primary branch):**

\`\`\`
0000000 stale placeholder
\`\`\`
" > "$d/.session-continuity/SESSION_PRIMER.md"
[[ "$(steps_of "$d")" == "refresh" ]] && ok "4: log drift -> refresh" || bad "4: got '$(steps_of "$d")'"

# --- 5: non-allowlisted file staged -> refresh -------------------------------
d="$work/case5"; mk_repo "$d" 1 0 1 0 other code
[[ "$(steps_of "$d")" == "refresh" ]] && ok "5: non-allowlisted staged -> refresh" || bad "5: got '$(steps_of "$d")'"

# --- docs-only staged -> NOT refresh (allowlisted) --------------------------
d="$work/case5b"; mk_repo "$d" 1 0 1 0 other docs
[[ "$(steps_of "$d")" == "" ]] && ok "5b: docs-only staged -> no refresh (allowlisted)" || bad "5b: got '$(steps_of "$d")'"

# --- 6: inline heading, no OUTSTANDING_ITEMS.md -> outstanding_split -------
d="$work/case6"; mk_repo "$d" 1 0 1 1 other none
[[ "$(steps_of "$d")" == "outstanding_split" ]] && ok "6: inline+no file -> outstanding_split" || bad "6: got '$(steps_of "$d")'"

# --- 7: both unsplit AND inline -> split,outstanding_split (order) ---------
d="$work/case7"; mk_repo "$d" 0 0 1 1 other none
[[ "$(steps_of "$d")" == "split,outstanding_split" ]] && ok "7: unsplit+inline -> split,outstanding_split in order" || bad "7: got '$(steps_of "$d")'"

# --- 8: OUTSTANDING_ITEMS.md exists, no BACKLOG.md -> backlog_rename -------
d="$work/case8"; mk_repo "$d" 1 1 0 0 other none
[[ "$(steps_of "$d")" == "backlog_rename" ]] && ok "8: outstanding file, no backlog -> backlog_rename" || bad "8: got '$(steps_of "$d")'"

# --- 9: BACKLOG.md exists, github origin -> backlog_to_issues --------------
d="$work/case9"; mk_repo "$d" 1 0 1 0 gh none
[[ "$(steps_of "$d")" == "backlog_to_issues" ]] && ok "9: backlog exists, github -> backlog_to_issues" || bad "9: got '$(steps_of "$d")'"

# --- 10: BACKLOG.md exists, non-github origin -> empty (fossil, no GH call) -
d="$work/case10"; mk_repo "$d" 1 0 1 0 other none
[[ "$(steps_of "$d")" == "" ]] && ok "10: backlog exists, non-github -> empty (fossil)" || bad "10: got '$(steps_of "$d")'"

# --- 11: full worst-case stack, exact order ---------------------------------
d="$work/case11"; mk_repo "$d" 0 0 0 1 gh none
[[ "$(steps_of "$d")" == "split,outstanding_split,backlog_rename,backlog_to_issues" ]] \
  && ok "11: full stack fires in dependency order" || bad "11: got '$(steps_of "$d")'"

# --- 12: operational failure -- missing filter, no STEPS line at all -------
badlib="$work/badlib"; mkdir -p "$badlib"
cp "$lib/primer-detect.sh" "$badlib/"
out="$(bash "$badlib/primer-detect.sh" "$work/case3" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"STEPS="* ]] \
  && ok "12: missing filter -> nonzero exit, no STEPS= line" || bad "12: rc=$rc out='$out'"

# --- 13: operational failure -- not a git repo ------------------------------
notgit="$work/notgit"; mkdir -p "$notgit"
out="$(bash "$tool" "$notgit" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"STEPS="* ]] \
  && ok "13: not a git repo -> nonzero exit, no STEPS= line" || bad "13: rc=$rc out='$out'"

# --- 14: operational failure -- wrong CONTRACT_VERSION -----------------------
wronglib="$work/wronglib"; mkdir -p "$wronglib"
cp "$lib/primer-detect.sh" "$wronglib/"
sed 's/CONTRACT_VERSION=1/CONTRACT_VERSION=99/' "$lib/primer-detect.jq" > "$wronglib/primer-detect.jq"
out="$(bash "$wronglib/primer-detect.sh" "$work/case3" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"STEPS="* ]] \
  && ok "14: wrong CONTRACT_VERSION -> nonzero exit, no STEPS= line" || bad "14: rc=$rc out='$out'"

# --- 15: operational failure -- jq absent from PATH -------------------------
nojq="$work/nojq"; mkdir -p "$nojq/bin"
for b in bash git awk grep sed head cat mktemp dirname; do
  p="$(command -v "$b")"; [[ -n "$p" ]] && ln -sf "$p" "$nojq/bin/$b"
done
out="$(PATH="$nojq/bin" bash "$tool" "$work/case3" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"STEPS="* ]] \
  && ok "15: jq absent from PATH -> nonzero exit, no STEPS= line" || bad "15: rc=$rc out='$out'"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
