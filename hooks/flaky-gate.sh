#!/usr/bin/env bash
# flaky-gate.sh — commit-time gate (session-continuity plugin). DUAL surface:
# Fires before Bash(git commit *). BLOCKS when a failure is called "flaky"/
# "transient"/"CDN blip|flake" without a `Mechanism:` line, in EITHER the commit
# message OR any staged LEARNINGS.md under .session-continuity/. Escape:
# `Flaky-gate: N/A — <reason>`.
set -euo pipefail
# shellcheck disable=SC1091 # dynamically-resolved path; gate-common.sh is shellcheck-clean standalone
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_in_scope() {
  [ "${1##*/}" = "LEARNINGS.md" ] || return 1
  case "$1" in .session-continuity/*|*/.session-continuity/*) return 0 ;; *) return 1 ;; esac
}

gate_check() {  # <text> <label-for-reason>
  local text="$1" where="$2"
  if [ -z "$text" ]; then return 0; fi
  if gate_has_escape "$text" "Flaky-gate"; then return 0; fi
  printf '%s' "$text" | grep -Eiq '\b(flaky|transient)\b|CDN[[:space:]]+(blip|flake)' || return 0
  if ! printf '%s' "$text" | grep -Eiq 'Mechanism:[[:space:]]*[^[:space:]]'; then
    deny "In $where: calls a failure 'flaky'/'transient'/a 'CDN blip' without naming the deterministic cause. CLAUDE.md rule 1: an intermittent failure has a deterministic cause (race, shared/global state, an env/sandbox dependency) — name it or state the precise fail condition. Add a 'Mechanism: <named cause>' line, or add: Flaky-gate: N/A — <reason> (decoration fine)."
  fi
}

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_check_file() { gate_check "$1" "staged file $2"; }

gate_load
gate_is_commit || exit 0
# (1) commit message text
gate_check "$GATE_COMMAND" "the commit message"
# (2) staged LEARNINGS.md content
gate_scan_staged gate_in_scope gate_check_file
exit 0
