#!/usr/bin/env bash
# CONTRACT_VERSION=n/a (this file has no CONTRACT_VERSION itself — it is
# sourced directly by every command edit, never invoked through the guard
# it implements)
# hooks/lib/require-script.sh — version-skew guard (session-continuity plugin).
# SOURCED, never executed.
#
# Usage: require_script <path> <expected-contract-version>
# Returns 0 if <path> is readable and its first "# CONTRACT_VERSION=N" line
# equals <expected-contract-version>. Returns 1 and sets
# SC_REQUIRE_SCRIPT_MSG to a one-line message otherwise. No fallback: per
# meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md
# Resolved decision 2, a version mismatch is reported to the user, never
# silently degraded to an old prose path.

require_script() {
  local script_path="$1" expected="$2" found
  SC_REQUIRE_SCRIPT_MSG=""
  if [[ ! -r "$script_path" ]]; then
    SC_REQUIRE_SCRIPT_MSG="${script_path##*/} not found at $script_path — plugin cache is out of date. Run \`/session-continuity:update\`."
    return 1
  fi
  found="$(grep -m1 '^# CONTRACT_VERSION=' "$script_path" 2>/dev/null | sed -E 's/^# CONTRACT_VERSION=//')"
  if [[ "$found" != "$expected" ]]; then
    SC_REQUIRE_SCRIPT_MSG="${script_path##*/} contract version mismatch (found '${found:-none}', need '$expected') — plugin cache is out of date. Run \`/session-continuity:update\`."
    return 1
  fi
  return 0
}
