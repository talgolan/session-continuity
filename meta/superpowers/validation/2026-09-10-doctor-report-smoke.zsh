#!/usr/bin/env zsh
# doctor-report.sh smoke. Hermetic: scratch project dirs + a throwaway
# plugin-root copy for NOEXEC / missing-peer cases. Never hits live GitHub
# for the core rows (GH_BIN mock / auth may still ⚠️ — assert markers, not
# exact backlog count text).
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
tool="$repo/hooks/lib/doctor-report.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Minimal thin primer that primer-validate accepts.
write_thin_primer() {
  local d="$1"
  mkdir -p "$d/.session-continuity"
  cat > "$d/.session-continuity/SESSION_PRIMER.md" <<'EOF'
# Session Primer — fixture

## Boot order
1. `.session-continuity/PROJECT_CONTEXT.md`

## Mid-flight
- fixture mid-flight bullet one

## Confirm
```bash
true
```

## Peers
- engrim: required
- graphify: required
EOF
  for f in PROJECT_CONTEXT.md ROADMAP.md LEARNINGS.md; do
    print -r -- "# $f" > "$d/.session-continuity/$f"
  done
}

# --- 1: real plugin root against this repo ---------------------------------
export CLAUDE_PLUGIN_ROOT="$repo"
out="$(bash "$tool" "$repo" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && ok "1: exit 0 on real repo" || bad "1: exit $rc"
print -r -- "$out" | grep -q '| Install mode | ✓ | Plugin v' \
  && ok "1: plugin install mode row" || bad "1: install row: $out"
print -r -- "$out" | grep -q '| Hooks registered | ✓ |' \
  && ok "1: hooks ok" || bad "1: hooks: $out"
print -r -- "$out" | grep -q 'Gate scripts executable | ✓ | All 11' \
  && ok "1: 11 gate scripts checked (incl. derived-value-gate)" \
  || bad "1: gates: $(print -r -- "$out" | grep 'Gate scripts')"

# --- 2: forced vendored (empty CLAUDE_PLUGIN_ROOT) -------------------------
out="$(CLAUDE_PLUGIN_ROOT= bash "$tool" "$repo" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && ok "2: vendored exit 0" || bad "2: exit $rc"
print -r -- "$out" | grep -q 'Vendored (CLAUDE_PLUGIN_ROOT unresolved)' \
  && ok "2: vendored install mode" || bad "2: $out"
print -r -- "$out" | grep -q 'skipped (vendored mode)' \
  && ok "2: root+gates skipped in vendored" || bad "2: skip rows missing"

# --- 3: peer-fail (empty graph.json) in scratch ----------------------------
d="$work/peers"
write_thin_primer "$d"
mkdir -p "$d/graphify-out"
: > "$d/graphify-out/graph.json"   # empty → GRAPHIFY=missing
git -C "$d" init -q
git -C "$d" config user.email t@e.com
git -C "$d" config user.name T
git -C "$d" add -A
git -C "$d" commit -qm init
# Copy a non-empty engrim-ok isn't controllable; GRAPHIFY=missing is enough for ✗
export CLAUDE_PLUGIN_ROOT="$repo"
out="$(bash "$tool" "$d" 2>&1)"
print -r -- "$out" | grep -qE '\| \.session-continuity/ files \| ✗ \|' \
  && ok "3: peer-fail hard marker ✗" \
  || bad "3: expected ✗ peers row, got: $(print -r -- "$out" | grep 'session-continuity')"

# --- 4: fossil BACKLOG.md --------------------------------------------------
d="$work/fossil"
write_thin_primer "$d"
print -r -- "# old backlog" > "$d/.session-continuity/BACKLOG.md"
# Need a valid graph for peers ok so fossil shows as ⚠️ not buried under ✗
mkdir -p "$d/graphify-out"
print -r -- '{"nodes":[{"id":"n"}],"edges":[]}' > "$d/graphify-out/graph.json"
git -C "$d" init -q
git -C "$d" config user.email t@e.com
git -C "$d" config user.name T
git -C "$d" add -A
git -C "$d" commit -qm init
out="$(bash "$tool" "$d" 2>&1)"
print -r -- "$out" | grep -qi 'fossil BACKLOG' \
  && ok "4: fossil BACKLOG mentioned" || bad "4: no fossil note: $out"

# --- 5: NOEXEC gate in throwaway plugin root -------------------------------
plug="$work/plug"
mkdir -p "$plug/hooks/lib" "$plug/.claude-plugin"
cp -R "$repo/hooks/." "$plug/hooks/"
cp "$repo/.claude-plugin/plugin.json" "$plug/.claude-plugin/"
# Make one gate non-executable
chmod a-x "$plug/hooks/derived-value-gate.sh"
d="$work/noexec-proj"
write_thin_primer "$d"
mkdir -p "$d/graphify-out"
print -r -- '{"nodes":[{"id":"n"}],"edges":[]}' > "$d/graphify-out/graph.json"
git -C "$d" init -q
git -C "$d" config user.email t@e.com
git -C "$d" config user.name T
git -C "$d" add -A
git -C "$d" commit -qm init
out="$(CLAUDE_PLUGIN_ROOT="$plug" bash "$plug/hooks/lib/doctor-report.sh" "$d" 2>&1)"
print -r -- "$out" | grep -q 'not executable:.*derived-value-gate' \
  && ok "5: NOEXEC derived-value-gate reported" \
  || bad "5: gates row: $(print -r -- "$out" | grep 'Gate scripts')"

# --- 6: broken install (missing sibling) → exit 2 --------------------------
badlib="$work/badlib"
mkdir -p "$badlib"
cp "$tool" "$badlib/doctor-report.sh"
out="$(CLAUDE_PLUGIN_ROOT="$repo" bash "$badlib/doctor-report.sh" "$repo" 2>&1)"; rc=$?
[[ "$rc" -eq 2 ]] && ok "6: missing sibling exits 2" || bad "6: expected exit 2, got $rc out=$out"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
