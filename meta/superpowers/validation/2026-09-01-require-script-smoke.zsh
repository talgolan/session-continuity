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

# Fixture: a script with no CONTRACT_VERSION line at all.
cat > "$work/no-version.sh" <<'EOF'
#!/usr/bin/env bash
echo hi
EOF

# Source require-script.sh inside bash -c to avoid DevBar's grep wrapper function
# shadowing the real binary, following the pattern from gate-common-smoke.zsh

if bash -c 'source "'"$lib"'/require-script.sh"; require_script "'"$work/good.sh"'" 1'; then
  ok "matching contract version returns 0"
else
  bad "matching contract version should return 0, got 1"
fi

if bash -c 'source "'"$lib"'/require-script.sh"; require_script "'"$work/stale.sh"'" 1'; then
  bad "mismatched contract version should return 1, got 0"
else
  bash -c 'source "'"$lib"'/require-script.sh"; require_script "'"$work/stale.sh"'" 1; echo "$SC_REQUIRE_SCRIPT_MSG"' > /dev/null
  ok "mismatched contract version returns 1"
  msg="$(bash -c 'source "'"$lib"'/require-script.sh"; require_script "'"$work/stale.sh"'" 1; echo "$SC_REQUIRE_SCRIPT_MSG"')"
  [[ -n "$msg" ]] && ok "mismatch sets a message" || bad "mismatch left SC_REQUIRE_SCRIPT_MSG empty"
fi

if bash -c 'source "'"$lib"'/require-script.sh"; require_script "'"$work/does-not-exist.sh"'" 1'; then
  bad "missing script should return 1, got 0"
else
  ok "missing script returns 1"
  msg="$(bash -c 'source "'"$lib"'/require-script.sh"; require_script "'"$work/does-not-exist.sh"'" 1; echo "$SC_REQUIRE_SCRIPT_MSG"')"
  [[ -n "$msg" ]] && ok "missing-script sets a message" || bad "missing-script left SC_REQUIRE_SCRIPT_MSG empty"
fi

if bash -c 'source "'"$lib"'/require-script.sh"; require_script "'"$work/no-version.sh"'" 1'; then
  bad "script with no version should return 1, got 0"
else
  ok "script with no version returns 1"
  msg="$(bash -c 'source "'"$lib"'/require-script.sh"; require_script "'"$work/no-version.sh"'" 1; echo "$SC_REQUIRE_SCRIPT_MSG"')"
  [[ -n "$msg" ]] && ok "no-version sets a message" || bad "no-version left SC_REQUIRE_SCRIPT_MSG empty"
fi

# Regression guard for the zsh `path`/`$PATH` special-variable collision
# (require_script's own `local path=...` used to corrupt `$PATH` when
# sourced directly into a zsh shell, exactly what commands/end-session.md
# and commands/learning.md do — every `bash -c` wrapper above routes
# around that, so it stays untested without this). Source directly into
# *this* zsh process, no wrapper.
_before_path="$PATH"
source "$lib/require-script.sh"
if require_script "$work/good.sh" 1; then
  ok "sourced directly into zsh: matching contract version returns 0"
else
  bad "sourced directly into zsh: matching contract version should return 0, got 1 ($SC_REQUIRE_SCRIPT_MSG)"
fi
if [[ "$PATH" == "$_before_path" ]]; then
  ok "sourced directly into zsh: \$PATH unchanged after require_script"
else
  bad "sourced directly into zsh: \$PATH corrupted (before='$_before_path' after='$PATH')"
fi

rm -rf "$work"
print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
