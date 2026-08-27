#!/usr/bin/env bash
# evidence-gate.sh — commit-time content gate (session-continuity plugin).
# Fires before Bash(git commit *). For each staged */specs/*.md or */plans/*.md
# that discusses a smoke section, BLOCKS (A) teardown without preserve-before-
# teardown, or (B) a poll/wait loop without a dual (success+failure) signal.
# Escape: `Evidence-gate: N/A — reason`.
set -euo pipefail
# shellcheck disable=SC1091 # dynamically-resolved path; gate-common.sh is shellcheck-clean standalone
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_in_scope() {
  case "$1" in */specs/*|*/plans/*) : ;; *) return 1 ;; esac
  case "${1##*/}" in *.md) return 0 ;; *) return 1 ;; esac
}

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_check() {
  local content="$1" path="$2"
  # Only relevant when the file discusses smoke.
  printf '%s' "$content" | grep -Eiq 'smoke' || return 0
  if gate_has_escape "$content" "Evidence-gate"; then return 0; fi
  if printf '%s' "$content" | grep -Eiq 'teardown|tear down|cleanup|clean up'; then
    if ! printf '%s' "$content" | grep -Eiq 'before teardown|before tear down|keep_on_fail|preserve[^.]*(diagnostic|evidence|log)|diagnostic[^.]*before|on failure[^.]*(preserve|keep|dump|surface)'; then
      deny "In staged file $path: the smoke section mentions teardown/cleanup but never states the failure diagnostic is captured BEFORE teardown. Teardown-on-fail destroys evidence needed to diagnose without guessing. Add a preserve-before-teardown line (e.g. 'surface the diagnostic into the log before any teardown' or SMOKE_KEEP_ON_FAIL), or add: Evidence-gate: N/A — <reason> (decoration fine)."
    fi
  fi
  if printf '%s' "$content" | grep -Eiq 'poll|wait[_-]?for|readiness check|timeout loop'; then
    if ! printf '%s' "$content" | grep -Eiq 'poll_until|both[^.]*(success|pass)[^.]*(failure|fail)|success and failure|dual.signal|failure signal'; then
      deny "In staged file $path: the smoke section mentions a poll/wait loop but never states it watches BOTH a success AND a failure signal. A success-only poll burns the full timeout on every failure and can't tell 'slow' from 'broken'. Name the dual-signal poll (e.g. 'poll_until <success> <failure> <timeout>'), or add: Evidence-gate: N/A — <reason> (decoration fine)."
    fi
  fi
}

gate_load
gate_is_commit || exit 0
gate_scan_staged gate_in_scope gate_check
exit 0
