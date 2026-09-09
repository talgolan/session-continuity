#!/usr/bin/env zsh
# primer-validate.sh smoke. Hermetic: heredoc primers in mktemp.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
helper="$repo/hooks/lib/primer-validate.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

last_rc=0
err=""
run_validate() {
  local file="$1"
  last_rc=0
  err="$(bash "$helper" "$file" 2>&1 >/dev/null)" || last_rc=$?
}

# Shared thin primer body (valid baseline)
thin_body() {
  cat <<'EOF'
# Session Primer — Example

## Boot order
1. `.session-continuity/PROJECT_CONTEXT.md`
2. `.session-continuity/LEARNINGS.md` (grep on surprise)
3. engrim context / recall (required)
4. graphify query when the question is about code structure
5. This file — Mid-flight + Confirm
6. `/session-continuity:backlog` for the deferred queue

## Mid-flight
- Example open work — `hooks/lib/foo.sh` — trap: none

## Confirm
```bash
true
```

## Peers
- engrim: required — ok
- graphify: required — `graphify-out/graph.json`
- backlog: GitHub Issues labeled `backlog`
EOF
}

# --- 1: thin primer → exit 0 ------------------------------------------------
f="$work/thin.md"
thin_body > "$f"
run_validate "$f"
[[ "$last_rc" -eq 0 ]] && ok "1: thin primer -> exit 0" \
  || bad "1: rc=$last_rc err='$err'"

# --- 2: fat primer (unknown ## + git-log fence) → fail + INVALID: ----------
f="$work/fat.md"
cat > "$f" <<'EOF'
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

## Outstanding
```bash
git log --oneline -5
```
EOF
run_validate "$f"
[[ "$last_rc" -ne 0 && "$err" == *"INVALID:"* ]] \
  && ok "2: fat primer -> non-zero + INVALID:" \
  || bad "2: rc=$last_rc err='$err'"

# --- 3: thin + 6th Mid-flight bullet → fail ---------------------------------
f="$work/six-bullets.md"
{
  thin_body | awk '
    /^## Confirm$/ { print "- b2"; print "- b3"; print "- b4"; print "- b5"; print "- b6" }
    { print }
  '
} > "$f"
run_validate "$f"
[[ "$last_rc" -ne 0 && "$err" == *"INVALID:"* ]] \
  && ok "3: 6 Mid-flight bullets -> fail" \
  || bad "3: rc=$last_rc err='$err'"

# --- 4: Confirm fence with 6 command lines → fail ---------------------------
f="$work/six-cmds.md"
cat > "$f" <<'EOF'
# Session Primer — Example

## Boot order
1. context

## Mid-flight
- open — `x` — trap: none

## Confirm
```bash
true
true
true
true
true
true
```

## Peers
- engrim: required — ok
- graphify: required — `graphify-out/graph.json`
- backlog: GitHub Issues labeled `backlog`
EOF
run_validate "$f"
[[ "$last_rc" -ne 0 && "$err" == *"INVALID:"* ]] \
  && ok "4: 6 Confirm commands -> fail" \
  || bad "4: rc=$last_rc err='$err'"

# --- 5: unknown ## History → fail -------------------------------------------
f="$work/history.md"
{
  thin_body
  print ""
  print "## History"
  print -r -- "- old"
} > "$f"
run_validate "$f"
[[ "$last_rc" -ne 0 && "$err" == *"INVALID:"* ]] \
  && ok "5: unknown ## History -> fail" \
  || bad "5: rc=$last_rc err='$err'"

# --- 6: # comment lines in Confirm do not count -----------------------------
f="$work/comments.md"
cat > "$f" <<'EOF'
# Session Primer — Example

## Boot order
1. `.session-continuity/PROJECT_CONTEXT.md`
2. `.session-continuity/LEARNINGS.md` (grep on surprise)
3. engrim context / recall (required)
4. graphify query when the question is about code structure
5. This file — Mid-flight + Confirm
6. `/session-continuity:backlog` for the deferred queue

## Mid-flight
- Example open work — `hooks/lib/foo.sh` — trap: none

## Confirm
```bash
# this is a comment
true
# another comment
false && true
# third comment
```

## Peers
- engrim: required — ok
- graphify: required — `graphify-out/graph.json`
- backlog: GitHub Issues labeled `backlog`
EOF
run_validate "$f"
[[ "$last_rc" -eq 0 ]] && ok "6: Confirm # comments ignored (2 cmds ok)" \
  || bad "6: rc=$last_rc err='$err'"

# --- 7: Confirm line git log -1 --oneline → banlist fail --------------------
f="$work/ban-gitlog.md"
cat > "$f" <<'EOF'
# Session Primer — Example

## Boot order
1. `.session-continuity/PROJECT_CONTEXT.md`
2. `.session-continuity/LEARNINGS.md` (grep on surprise)
3. engrim context / recall (required)
4. graphify query when the question is about code structure
5. This file — Mid-flight + Confirm
6. `/session-continuity:backlog` for the deferred queue

## Mid-flight
- Example open work — `hooks/lib/foo.sh` — trap: none

## Confirm
```bash
git log -1 --oneline
```

## Peers
- engrim: required — ok
- graphify: required — `graphify-out/graph.json`
- backlog: GitHub Issues labeled `backlog`
EOF
run_validate "$f"
[[ "$last_rc" -ne 0 && "$err" == *"INVALID:"* ]] \
  && ok "7: git log -1 --oneline in fence -> banlist fail" \
  || bad "7: rc=$last_rc err='$err'"

# --- 8: prose "see git history" without git log → pass ----------------------
f="$work/prose.md"
cat > "$f" <<'EOF'
# Session Primer — Example

## Boot order
1. `.session-continuity/PROJECT_CONTEXT.md`
2. `.session-continuity/LEARNINGS.md` (grep on surprise)
3. engrim context / recall (required)
4. graphify query when the question is about code structure
5. This file — Mid-flight + Confirm
6. `/session-continuity:backlog` for the deferred queue

## Mid-flight
- Example open work — see git history for prior attempts — `hooks/lib/foo.sh` — trap: none

## Confirm
```bash
true
```

## Peers
- engrim: required — ok
- graphify: required — `graphify-out/graph.json`
- backlog: GitHub Issues labeled `backlog`
EOF
run_validate "$f"
[[ "$last_rc" -eq 0 ]] && ok "8: prose 'see git history' still passes" \
  || bad "8: rc=$last_rc err='$err'"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
