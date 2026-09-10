#!/usr/bin/env bash
# evidence-gate.sh — commit-time content gate (session-continuity plugin).
# Fires before Bash(git commit *). For each staged */specs/*.md or */plans/*.md
# that discusses a smoke section, BLOCKS (A) teardown without preserve-before-
# teardown, or (B) a poll/wait loop without a dual (success+failure) signal.
# Escape: `Evidence-gate: N/A — reason` (driver short-circuit).
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
  local sat_td='before teardown|before tear down|keep_on_fail|preserve[^.]*(diagnostic|evidence|log)|diagnostic[^.]*before|on failure[^.]*(preserve|keep|dump|surface)'
  local sat_poll='poll_until|both[^.]*(success|pass)[^.]*(failure|fail)|success and failure|dual.signal|failure signal'
  local trig_td='teardown|tear down|cleanup|clean up'
  local trig_poll='poll|wait[_-]?for|readiness check|timeout loop'
  local fire=0
  if gate_triggered 'smoke' "$sat_td" "$sat_poll"; then fire=1; fi
  if [ "$fire" -eq 0 ] && printf '%s' "$content" | LC_ALL=C grep -Eiq 'smoke'; then
    if gate_triggered "$trig_td" "$sat_td" || gate_triggered "$trig_poll" "$sat_poll"; then
      fire=1
    fi
  fi
  [ "$fire" -eq 1 ] || return 0

  if printf '%s' "$content" | LC_ALL=C grep -Eiq "$trig_td"; then
    if ! printf '%s' "$content" | LC_ALL=C grep -Eiq "$sat_td"; then
      deny "In staged file $path: the smoke section mentions teardown/cleanup but never states the failure diagnostic is captured BEFORE teardown. Teardown-on-fail destroys evidence needed to diagnose without guessing. Add a preserve-before-teardown line (e.g. 'surface the diagnostic into the log before any teardown' or SMOKE_KEEP_ON_FAIL), or add: Evidence-gate: N/A — <reason> (decoration fine)."
    fi
  fi
  if printf '%s' "$content" | LC_ALL=C grep -Eiq "$trig_poll"; then
    if ! printf '%s' "$content" | LC_ALL=C grep -Eiq "$sat_poll"; then
      deny "In staged file $path: the smoke section mentions a poll/wait loop but never states it watches BOTH a success AND a failure signal. A success-only poll burns the full timeout on every failure and can't tell 'slow' from 'broken'. Name the dual-signal poll (e.g. 'poll_until <success> <failure> <timeout>'), or add: Evidence-gate: N/A — <reason> (decoration fine)."
    fi
  fi
}

gate_load
gate_is_commit || exit 0
# shellcheck disable=SC2034 # consumed by sourced gate_scan_staged
GATE_LABEL="Evidence-gate"
gate_scan_staged gate_in_scope gate_check
exit 0
