#!/usr/bin/env zsh
# require_script() version-skew guard runner. Hermetic: fixture scripts in a
# temp dir, no real hooks/lib files touched.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"

# Fixture: a script with a matching contract version.
cat > "$work/good.sh" <<'EOF'
#!/usr/bin/env bash
# CONTRACT_VERSION=1
echo hi
EOF

# Fixture: a script with a mismatched contract version (simulates a stale
# plugin cache running against newer command prose).
cat > "$work/stale.sh" <<'EOF'
#!/usr/bin/env bash
# CONTRACT_VERSION=0
echo hi
EOF

source "$lib/require-script.sh"

if require_script "$work/good.sh" 1; then
  ok "matching contract version returns 0"
else
  bad "matching contract version should return 0, got 1 (msg: $SC_REQUIRE_SCRIPT_MSG)"
fi

if require_script "$work/stale.sh" 1; then
  bad "mismatched contract version should return 1, got 0"
else
  ok "mismatched contract version returns 1"
  [[ -n "$SC_REQUIRE_SCRIPT_MSG" ]] && ok "mismatch sets a message" || bad "mismatch left SC_REQUIRE_SCRIPT_MSG empty"
fi

if require_script "$work/does-not-exist.sh" 1; then
  bad "missing script should return 1, got 0"
else
  ok "missing script returns 1"
  [[ -n "$SC_REQUIRE_SCRIPT_MSG" ]] && ok "missing-script sets a message" || bad "missing-script left SC_REQUIRE_SCRIPT_MSG empty"
fi

rm -rf "$work"
print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
