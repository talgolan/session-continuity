#!/usr/bin/env zsh
# primer-freshness.sh smoke. Hermetic: temp git repos inside mktemp.
# Never touches this repo's working tree.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
helper="$repo/hooks/lib/primer-freshness.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

last_rc=0
out=""
run_fresh() {
  local dir="$1"
  last_rc=0
  out="$(bash "$helper" "$dir" 2>/dev/null)" || last_rc=$?
}

# init_repo <dir> — empty git repo with identity set
init_repo() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email "test@example.com"
  git -C "$d" config user.name "Test"
}

# commit_primer <dir> — thin primer as sole content of a commit
commit_primer() {
  local d="$1"
  mkdir -p "$d/.session-continuity"
  cat > "$d/.session-continuity/SESSION_PRIMER.md" <<'EOF'
# Session Primer — Example

## Boot order
1. context

## Mid-flight
- open

## Confirm
```bash
true
```

## Peers
- engrim: required
EOF
  git -C "$d" add .session-continuity/SESSION_PRIMER.md
  git -C "$d" commit -qm "add primer"
}

# --- 1: primer only → STALE=0 ----------------------------------------------
d="$work/case1"
init_repo "$d"
commit_primer "$d"
run_fresh "$d"
[[ "$out" == "STALE=0" && "$last_rc" -eq 0 ]] \
  && ok "1: primer only -> STALE=0 exit 0" \
  || bad "1: got '$out' rc=$last_rc (want STALE=0 rc=0)"

# --- 2: src/foo.sh after primer → STALE=1 ----------------------------------
d="$work/case2"
init_repo "$d"
commit_primer "$d"
mkdir -p "$d/src"
print -r -- 'echo hi' > "$d/src/foo.sh"
git -C "$d" add src/foo.sh
git -C "$d" commit -qm "add foo"
run_fresh "$d"
[[ "$out" == "STALE=1" && "$last_rc" -eq 0 ]] \
  && ok "2: src/foo.sh after primer -> STALE=1" \
  || bad "2: got '$out' rc=$last_rc (want STALE=1 rc=0)"

# --- 3: only CHANGELOG.md after primer → STALE=0 ---------------------------
d="$work/case3"
init_repo "$d"
commit_primer "$d"
print -r -- '# changelog' > "$d/CHANGELOG.md"
git -C "$d" add CHANGELOG.md
git -C "$d" commit -qm "changelog"
run_fresh "$d"
[[ "$out" == "STALE=0" && "$last_rc" -eq 0 ]] \
  && ok "3: CHANGELOG.md only -> STALE=0" \
  || bad "3: got '$out' rc=$last_rc (want STALE=0 rc=0)"

# --- 4: only docs/README.md after primer → STALE=0 (basename) --------------
d="$work/case4"
init_repo "$d"
commit_primer "$d"
mkdir -p "$d/docs"
print -r -- '# readme' > "$d/docs/README.md"
git -C "$d" add docs/README.md
git -C "$d" commit -qm "docs readme"
run_fresh "$d"
[[ "$out" == "STALE=0" && "$last_rc" -eq 0 ]] \
  && ok "4: docs/README.md basename ignore -> STALE=0" \
  || bad "4: got '$out' rc=$last_rc (want STALE=0 rc=0)"

# --- 5: only .session-continuity/LEARNINGS.md → STALE=0 --------------------
d="$work/case5"
init_repo "$d"
commit_primer "$d"
print -r -- '# learnings' > "$d/.session-continuity/LEARNINGS.md"
git -C "$d" add .session-continuity/LEARNINGS.md
git -C "$d" commit -qm "learnings"
run_fresh "$d"
[[ "$out" == "STALE=0" && "$last_rc" -eq 0 ]] \
  && ok "5: LEARNINGS.md under .session-continuity/ -> STALE=0" \
  || bad "5: got '$out' rc=$last_rc (want STALE=0 rc=0)"

# --- 6: no primer → STALE=? ------------------------------------------------
d="$work/case6"
init_repo "$d"
print -r -- 'x' > "$d/README.md"
git -C "$d" add README.md
git -C "$d" commit -qm "init without primer"
run_fresh "$d"
[[ "$out" == "STALE=?" && "$last_rc" -eq 0 ]] \
  && ok "6: no primer -> STALE=? exit 0" \
  || bad "6: got '$out' rc=$last_rc (want STALE=? rc=0)"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
