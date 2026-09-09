#!/usr/bin/env zsh
# peer-probes.sh smoke. Hermetic: temp project dir + mocked ENGRIM_BIN.
# Fixtures live inside mktemp; never touches a shared fixtures dir.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
helper="$repo/hooks/lib/peer-probes.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# run_probe <dir> [env assignments as NAME=val ...]
# Sets globals: out, last_rc. Must not run inside $() (subshell).
last_rc=0
out=""
run_probe() {
  local dir="$1"; shift
  last_rc=0
  out="$(env "$@" bash "$helper" "$dir" 2>/dev/null)" || last_rc=$?
}

# --- 1: no graph.json, nonexistent ENGRIM_BIN → both missing ---------------
d="$work/case1"; mkdir -p "$d"
run_probe "$d" ENGRIM_BIN=/nonexistent/engrim
engrim_line="$(print -r -- "$out" | sed -n '1p')"
graphify_line="$(print -r -- "$out" | sed -n '2p')"
[[ "$engrim_line" == "ENGRIM=missing" && "$graphify_line" == "GRAPHIFY=missing" ]] \
  && ok "1: no peers -> ENGRIM=missing GRAPHIFY=missing" \
  || bad "1: got '$out' (rc=$last_rc)"
[[ "$last_rc" -eq 0 ]] && ok "1b: exit 0 when both missing" \
  || bad "1b: rc=$last_rc (want 0)"

# --- 2: non-empty graph.json → GRAPHIFY=ok ---------------------------------
d="$work/case2"; mkdir -p "$d/graphify-out"
print -r -- '{"nodes":[]}' > "$d/graphify-out/graph.json"
run_probe "$d" ENGRIM_BIN=/nonexistent/engrim
graphify_line="$(print -r -- "$out" | sed -n '2p')"
[[ "$graphify_line" == "GRAPHIFY=ok" ]] \
  && ok "2: non-empty graph.json -> GRAPHIFY=ok" \
  || bad "2: got '$out'"

# --- 3: empty graph.json → GRAPHIFY=missing --------------------------------
d="$work/case3"; mkdir -p "$d/graphify-out"
: > "$d/graphify-out/graph.json"
run_probe "$d" ENGRIM_BIN=/nonexistent/engrim
graphify_line="$(print -r -- "$out" | sed -n '2p')"
[[ "$graphify_line" == "GRAPHIFY=missing" ]] \
  && ok "3: empty graph.json -> GRAPHIFY=missing" \
  || bad "3: got '$out'"

# --- 4: mock ENGRIM_BIN exit 0 → ENGRIM=ok ----------------------------------
d="$work/case4"; mkdir -p "$d"
mock_ok="$work/mock-engrim-ok"
cat > "$mock_ok" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$mock_ok"
run_probe "$d" ENGRIM_BIN="$mock_ok"
engrim_line="$(print -r -- "$out" | sed -n '1p')"
[[ "$engrim_line" == "ENGRIM=ok" ]] \
  && ok "4: mock exit 0 -> ENGRIM=ok" \
  || bad "4: got '$out'"

# --- 5: mock ENGRIM_BIN exit 1 → ENGRIM=error -------------------------------
d="$work/case5"; mkdir -p "$d"
mock_fail="$work/mock-engrim-fail"
cat > "$mock_fail" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$mock_fail"
run_probe "$d" ENGRIM_BIN="$mock_fail"
engrim_line="$(print -r -- "$out" | sed -n '1p')"
[[ "$engrim_line" == "ENGRIM=error" ]] \
  && ok "5: mock exit 1 -> ENGRIM=error" \
  || bad "5: got '$out'"
[[ "$last_rc" -eq 0 ]] && ok "5b: exit 0 when ENGRIM=error" \
  || bad "5b: rc=$last_rc (want 0)"

# --- 6: mock sleep 5 with PEER_PROBES_TIMEOUT=1 → ENGRIM=error -------------
d="$work/case6"; mkdir -p "$d"
mock_slow="$work/mock-engrim-slow"
cat > "$mock_slow" <<'EOF'
#!/usr/bin/env bash
sleep 5
exit 0
EOF
chmod +x "$mock_slow"
run_probe "$d" ENGRIM_BIN="$mock_slow" PEER_PROBES_TIMEOUT=1
engrim_line="$(print -r -- "$out" | sed -n '1p')"
[[ "$engrim_line" == "ENGRIM=error" ]] \
  && ok "6: timeout -> ENGRIM=error" \
  || bad "6: got '$out'"

# --- 7: always exit 0 even when peers fail (combined) ----------------------
d="$work/case7"; mkdir -p "$d"
run_probe "$d" ENGRIM_BIN=/nonexistent/engrim
[[ "$last_rc" -eq 0 ]] && ok "7: helper always exits 0" \
  || bad "7: rc=$last_rc out='$out'"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
