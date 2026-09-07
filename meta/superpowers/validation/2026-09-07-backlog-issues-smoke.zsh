#!/usr/bin/env zsh
# backlog-issues.sh smoke. Hermetic: temp git repo + mocked GH_BIN.
# Never talks to the live GitHub API.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
helper="$repo/hooks/lib/backlog-issues.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

WARN='Backlog unavailable: GitHub Issues required (gh, github.com remote, auth). Run /session-continuity:doctor.'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git -C "$work" init -q
git -C "$work" config user.email "test@example.com"
git -C "$work" config user.name "Test"
: > "$work/README.md"
git -C "$work" add README.md
git -C "$work" commit -qm "init"
git -C "$work" remote add origin "https://github.com/example/repo.git"

mock="$work/fake-gh"
cat > "$mock" <<'EOF'
#!/usr/bin/env bash
if [[ "${GH_MOCK_FAIL:-}" == "1" ]]; then
  echo "boom" >&2
  exit 1
fi
if [[ -n "${GH_MOCK_OUT:-}" && -f "${GH_MOCK_OUT}" ]]; then
  cat "${GH_MOCK_OUT}"
  exit 0
fi
exit 0
EOF
chmod +x "$mock"

export GH_BIN="$mock"

# --- two issues ----------------------------------------------------------
printf '#12\tAlpha\n#15\tBeta\n' > "$work/two.tsv"
export GH_MOCK_OUT="$work/two.tsv"
out="$(bash "$helper" "$work")"
rc=$?
expect=$'1. #12 Alpha\n2. #15 Beta'
[[ "$rc" -eq 0 && "$out" == "$expect" ]] && ok "list: two issues numbered 1..N" \
  || bad "list two: rc=$rc out='$out'"

cnt="$(bash "$helper" --count "$work")"
[[ "$cnt" == "2" ]] && ok "--count: 2" || bad "--count two: got '$cnt'"

# --- empty list ----------------------------------------------------------
: > "$work/empty.tsv"
export GH_MOCK_OUT="$work/empty.tsv"
out="$(bash "$helper" "$work")"
[[ "$out" == "No open backlog issues." ]] && ok "list: empty -> no-open message" \
  || bad "list empty: got '$out'"

cnt="$(bash "$helper" --count "$work")"
[[ "$cnt" == "0" ]] && ok "--count: 0 when empty" || bad "--count empty: got '$cnt'"

# --- origin not github.com -----------------------------------------------
git -C "$work" remote set-url origin "https://gitlab.com/example/repo.git"
out="$(bash "$helper" "$work")"
cnt="$(bash "$helper" --count "$work")"
[[ "$out" == "$WARN" ]] && ok "non-github origin: warning line" \
  || bad "non-github list: got '$out'"
[[ "$cnt" == "?" ]] && ok "non-github origin: count ?" || bad "non-github count: got '$cnt'"
git -C "$work" remote set-url origin "https://github.com/example/repo.git"

# --- ssh github origin still works ---------------------------------------
git -C "$work" remote set-url origin "git@github.com:example/repo.git"
export GH_MOCK_OUT="$work/two.tsv"
out="$(bash "$helper" "$work")"
[[ "$out" == "$expect" ]] && ok "ssh github.com origin accepted" \
  || bad "ssh origin: got '$out'"
git -C "$work" remote set-url origin "https://github.com/example/repo.git"

# --- gh missing ----------------------------------------------------------
out="$(GH_BIN="/nonexistent/gh-binary-for-test" bash "$helper" "$work")"
cnt="$(GH_BIN="/nonexistent/gh-binary-for-test" bash "$helper" --count "$work")"
[[ "$out" == "$WARN" ]] && ok "missing gh: warning line" || bad "missing gh list: got '$out'"
[[ "$cnt" == "?" ]] && ok "missing gh: count ?" || bad "missing gh count: got '$cnt'"

# --- gh non-zero ---------------------------------------------------------
export GH_MOCK_FAIL=1
out="$(bash "$helper" "$work")"
cnt="$(bash "$helper" --count "$work")"
[[ "$out" == "$WARN" ]] && ok "gh exit 1: warning line" || bad "gh fail list: got '$out'"
[[ "$cnt" == "?" ]] && ok "gh exit 1: count ?" || bad "gh fail count: got '$cnt'"
unset GH_MOCK_FAIL

# --- no git dir ----------------------------------------------------------
nogit="$(mktemp -d)"
out="$(bash "$helper" "$nogit")"
cnt="$(bash "$helper" --count "$nogit")"
[[ "$out" == "$WARN" ]] && ok "non-git dir: warning line" || bad "nongit list: got '$out'"
[[ "$cnt" == "?" ]] && ok "non-git dir: count ?" || bad "nongit count: got '$cnt'"
rm -rf "$nogit"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
