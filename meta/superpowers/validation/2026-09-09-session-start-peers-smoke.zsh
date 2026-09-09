#!/usr/bin/env zsh
# SessionStart peer hard-stop + missing-primer nudge smoke.
# Hermetic: temp dirs as cwd JSON payload; mocked ENGRIM_BIN + fixture graph.
# Prefer no nested git — peers are mocked without repos.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
hook="$repo/hooks/session-start.sh"

export SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

# Workspace-local temp (sandbox-safe).
tmpdir_root="$repo/.superpowers/sdd/tmp"
mkdir -p "$tmpdir_root"
export TMPDIR="$tmpdir_root"
work="$(mktemp -d "$tmpdir_root/peers-smoke.XXXXXX")"
trap 'rm -rf "$work"' EXIT

payload() { printf '{"cwd":"%s"}' "$1"; }

mock_ok="$work/mock-engrim-ok"
cat > "$mock_ok" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$mock_ok"

# --- 1: empty dir → missing-primer nudge -----------------------------------
d1="$work/empty"
mkdir -p "$d1"
out1="$(payload "$d1" | bash "$hook")"
[[ "$out1" == *"/session-continuity:primer"* ]] \
  && ok "1: empty dir nudges /session-continuity:primer" \
  || bad "1: expected '/session-continuity:primer' in: $out1"

# --- 2: primer + missing peers → hard-stop ---------------------------------
d2="$work/no-peers"
mkdir -p "$d2/.session-continuity"
print -r -- '# Session Primer' > "$d2/.session-continuity/SESSION_PRIMER.md"
touch "$d2/.session-continuity/LEARNINGS.md"
# Force engrim missing (do not inherit a real engrim from PATH).
out2="$(payload "$d2" | env ENGRIM_BIN=/nonexistent/engrim bash "$hook")"
[[ "$out2" == *"PEER SETUP INCOMPLETE"* ]] \
  && ok "2a: PEER SETUP INCOMPLETE" \
  || bad "2a: missing PEER SETUP INCOMPLETE in: $out2"
[[ "$out2" == *"graphify-out/graph.json"* ]] \
  && ok "2b: mentions graphify-out/graph.json" \
  || bad "2b: missing graphify path in: $out2"
[[ "$out2" == *"engrim"* ]] \
  && ok "2c: mentions engrim" \
  || bad "2c: missing engrim in: $out2"

# --- 3: primer + peers ok → normal reminder, no hard-stop ------------------
d3="$work/peers-ok"
mkdir -p "$d3/.session-continuity" "$d3/graphify-out"
print -r -- '# Session Primer

## Mid-flight
- open work
' > "$d3/.session-continuity/SESSION_PRIMER.md"
touch "$d3/.session-continuity/LEARNINGS.md"
print -r -- '{"nodes":[]}' > "$d3/graphify-out/graph.json"
out3="$(payload "$d3" | env ENGRIM_BIN="$mock_ok" bash "$hook")"
if [[ "$out3" == *"SESSION_PRIMER"* || "$out3" == *"Mid-flight"* ]]; then
  ok "3a: peers ok emits SESSION_PRIMER or Mid-flight"
else
  bad "3a: expected SESSION_PRIMER or Mid-flight in: $out3"
fi
[[ "$out3" != *"PEER SETUP INCOMPLETE"* ]] \
  && ok "3b: peers ok has no PEER SETUP INCOMPLETE" \
  || bad "3b: unexpected hard-stop in: $out3"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
