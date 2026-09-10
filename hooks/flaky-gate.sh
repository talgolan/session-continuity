#!/usr/bin/env bash
# flaky-gate.sh — commit-time gate. DUAL surface: commit message + LEARNINGS.md.
# Escape via driver / gate_scan_commit_message: Flaky-gate: N/A — <reason>.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_in_scope() {
  [ "${1##*/}" = "LEARNINGS.md" ] || return 1
  case "$1" in .session-continuity/*|*/.session-continuity/*) return 0 ;; *) return 1 ;; esac
}

# shellcheck disable=SC2329 # called indirectly by gate_scan_commit_message
gate_check_message() {
  local text="$1"
  [ -z "$text" ] && return 0
  printf '%s' "$text" | LC_ALL=C grep -Eiq '\b(flaky|transient)\b|CDN[[:space:]]+(blip|flake)' || return 0
  if ! printf '%s' "$text" | LC_ALL=C grep -Eiq 'Mechanism:[[:space:]]*[^[:space:]]'; then
    deny "In the commit message: calls a failure 'flaky'/'transient'/a 'CDN blip' without naming the deterministic cause. CLAUDE.md rule 1: an intermittent failure has a deterministic cause (race, shared/global state, an env/sandbox dependency) — name it or state the precise fail condition. Add a 'Mechanism: <named cause>' line, or add: Flaky-gate: N/A — <reason> (decoration fine)."
  fi
}

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_check_file() {
  local content="$1" path="$2"
  if ! gate_triggered '\b(flaky|transient)\b|CDN[[:space:]]+(blip|flake)' \
      'Mechanism:[[:space:]]*[^[:space:]]'; then
    return 0
  fi
  if ! printf '%s' "$content" | LC_ALL=C grep -Eiq 'Mechanism:[[:space:]]*[^[:space:]]'; then
    deny "In staged file $path: calls a failure 'flaky'/'transient'/a 'CDN blip' without naming the deterministic cause. CLAUDE.md rule 1: an intermittent failure has a deterministic cause (race, shared/global state, an env/sandbox dependency) — name it or state the precise fail condition. Add a 'Mechanism: <named cause>' line, or add: Flaky-gate: N/A — <reason> (decoration fine)."
  fi
}

gate_load
gate_is_commit || exit 0
# shellcheck disable=SC2034 # consumed by sourced helpers
GATE_LABEL="Flaky-gate"
gate_scan_commit_message gate_check_message
gate_scan_staged gate_in_scope gate_check_file
exit 0
