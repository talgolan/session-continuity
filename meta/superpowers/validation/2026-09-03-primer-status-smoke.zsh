#!/usr/bin/env zsh
# primer-status.sh smoke test. Hermetic: runs against a throwaway temp git
# repo, never touches this repo's own working tree.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
tool="$lib/primer-status.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

# get <output> <key> — extract KEY=value's value from the tool's stdout.
get() { print -r -- "$1" | sed -n "s/^$2=//p"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q
git -C "$work" config user.email "test@example.com"
git -C "$work" config user.name "Test"
mkdir -p "$work/.session-continuity"

# --- no primer/backlog/learnings yet, but a real commit exists -------------
: > "$work/README.md"
git -C "$work" add README.md
git -C "$work" commit -qm "init"
expected_sha="$(git -C "$work" rev-parse --short HEAD)"

out="$(bash "$tool" "$work")"
sha="$(get "$out" HEAD_SHA)"
mtime="$(get "$out" PRIMER_MTIME)"
backlog="$(get "$out" BACKLOG_COUNT)"
learnings="$(get "$out" LEARNINGS_COUNT)"

[[ "$sha" == "$expected_sha" ]] && ok "HEAD_SHA matches git rev-parse --short HEAD" \
  || bad "HEAD_SHA: expected $expected_sha, got $sha"
[[ "$mtime" == "?" ]] && ok "PRIMER_MTIME: ? when SESSION_PRIMER.md is missing" \
  || bad "PRIMER_MTIME: expected ?, got $mtime"
[[ "$backlog" == "0" ]] && ok "BACKLOG_COUNT: 0 when BACKLOG.md is missing (count-entries.sh's own missing-file contract)" \
  || bad "BACKLOG_COUNT: expected 0, got $backlog"
[[ "$learnings" == "0" ]] && ok "LEARNINGS_COUNT: 0 when LEARNINGS.md is missing" \
  || bad "LEARNINGS_COUNT: expected 0, got $learnings"

# --- all four files present with real content -------------------------------
printf '# primer\n' > "$work/.session-continuity/SESSION_PRIMER.md"
printf '# backlog\n\n### 1. one\n### 2. two\n### 3. three\n' > "$work/.session-continuity/BACKLOG.md"
printf '# learnings\n\n### 1. one\n' > "$work/.session-continuity/LEARNINGS.md"

out="$(bash "$tool" "$work")"
mtime="$(get "$out" PRIMER_MTIME)"
backlog="$(get "$out" BACKLOG_COUNT)"
learnings="$(get "$out" LEARNINGS_COUNT)"

[[ "$mtime" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && ok "PRIMER_MTIME: YYYY-MM-DD-prefixed when the file exists" \
  || bad "PRIMER_MTIME: expected YYYY-MM-DD prefix, got $mtime"
[[ "$backlog" == "3" ]] && ok "BACKLOG_COUNT: 3 real entries counted" \
  || bad "BACKLOG_COUNT: expected 3, got $backlog"
[[ "$learnings" == "1" ]] && ok "LEARNINGS_COUNT: 1 real entry counted" \
  || bad "LEARNINGS_COUNT: expected 1, got $learnings"

# --- defaults to "." when no argument is given -------------------------------
out="$(cd "$work" && bash "$tool")"
backlog="$(get "$out" BACKLOG_COUNT)"
[[ "$backlog" == "3" ]] && ok "no argument: defaults to cwd" \
  || bad "no argument: expected 3, got $backlog"

# --- not a git repo: HEAD_SHA is ? but the script still exits 0 and prints all four lines ---
nogit="$(mktemp -d)"
out="$(bash "$tool" "$nogit")"
rc=$?
sha="$(get "$out" HEAD_SHA)"
line_count="$(print -r -- "$out" | wc -l | tr -d ' ')"
if [[ "$rc" == "0" && "$sha" == "?" && "$line_count" == "4" ]]; then
  ok "non-git dir: HEAD_SHA=?, all four lines still printed, exit 0"
else
  bad "non-git dir: expected rc=0 sha=? lines=4, got rc=$rc sha=$sha lines=$line_count"
fi
rm -rf "$nogit"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
