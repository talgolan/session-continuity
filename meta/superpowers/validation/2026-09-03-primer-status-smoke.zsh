#!/usr/bin/env zsh
# primer-status.sh smoke test. Hermetic: throwaway temp git repo + mocked
# GH_BIN. Never touches this repo's own working tree or the live GitHub API.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
tool="$lib/primer-status.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

get() { print -r -- "$1" | sed -n "s/^$2=//p"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q
git -C "$work" config user.email "test@example.com"
git -C "$work" config user.name "Test"
mkdir -p "$work/.session-continuity"

mock="$work/fake-gh"
cat > "$mock" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${GH_MOCK_OUT:-}" && -f "${GH_MOCK_OUT}" ]]; then
  cat "${GH_MOCK_OUT}"
  exit 0
fi
exit 0
EOF
chmod +x "$mock"
export GH_BIN="$mock"

# --- no primer/learnings yet, no github origin, but a real commit exists ---
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
[[ "$backlog" == "?" ]] && ok "BACKLOG_COUNT: ? when origin is not github.com" \
  || bad "BACKLOG_COUNT: expected ?, got $backlog"
[[ "$learnings" == "0" ]] && ok "LEARNINGS_COUNT: 0 when LEARNINGS.md is missing" \
  || bad "LEARNINGS_COUNT: expected 0, got $learnings"

# --- github origin + mocked issues + primer + learnings --------------------
git -C "$work" remote add origin "https://github.com/example/repo.git"
printf '#12\tAlpha\n#15\tBeta\n' > "$work/two.tsv"
export GH_MOCK_OUT="$work/two.tsv"
printf '# primer\n' > "$work/.session-continuity/SESSION_PRIMER.md"
printf '# learnings\n\n### 1. one\n' > "$work/.session-continuity/LEARNINGS.md"

out="$(bash "$tool" "$work")"
mtime="$(get "$out" PRIMER_MTIME)"
backlog="$(get "$out" BACKLOG_COUNT)"
learnings="$(get "$out" LEARNINGS_COUNT)"

[[ "$mtime" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && ok "PRIMER_MTIME: YYYY-MM-DD-prefixed when the file exists" \
  || bad "PRIMER_MTIME: expected YYYY-MM-DD prefix, got $mtime"
[[ "$backlog" == "2" ]] && ok "BACKLOG_COUNT: 2 from mocked gh" \
  || bad "BACKLOG_COUNT: expected 2, got $backlog"
[[ "$learnings" == "1" ]] && ok "LEARNINGS_COUNT: 1 real entry counted" \
  || bad "LEARNINGS_COUNT: expected 1, got $learnings"

# --- defaults to "." when no argument is given -----------------------------
out="$(cd "$work" && bash "$tool")"
backlog="$(get "$out" BACKLOG_COUNT)"
[[ "$backlog" == "2" ]] && ok "no argument: defaults to cwd" \
  || bad "no argument: expected 2, got $backlog"

# --- empty issue list counts as 0 ------------------------------------------
: > "$work/empty.tsv"
export GH_MOCK_OUT="$work/empty.tsv"
out="$(bash "$tool" "$work")"
backlog="$(get "$out" BACKLOG_COUNT)"
[[ "$backlog" == "0" ]] && ok "BACKLOG_COUNT: 0 when gh returns no issues" \
  || bad "BACKLOG_COUNT empty: expected 0, got $backlog"

# --- not a git repo: HEAD_SHA is ? but the script still exits 0 ------------
nogit="$(mktemp -d)"
out="$(bash "$tool" "$nogit")"
rc=$?
sha="$(get "$out" HEAD_SHA)"
backlog="$(get "$out" BACKLOG_COUNT)"
line_count="$(print -r -- "$out" | wc -l | tr -d ' ')"
if [[ "$rc" == "0" && "$sha" == "?" && "$line_count" == "4" && "$backlog" == "?" ]]; then
  ok "non-git dir: HEAD_SHA=?, BACKLOG_COUNT=?, all four lines, exit 0"
else
  bad "non-git dir: expected rc=0 sha=? backlog=? lines=4, got rc=$rc sha=$sha backlog=$backlog lines=$line_count"
fi
rm -rf "$nogit"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
