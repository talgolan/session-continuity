#!/usr/bin/env bash
# smoke-gate.sh — Escape via driver: Smoke: N/A — <reason>.
set -euo pipefail
# shellcheck disable=SC1091 # dynamically-resolved path; gate-common.sh is shellcheck-clean standalone
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_in_scope() {
  case "${1##*/}" in *.md) : ;; *) return 1 ;; esac
  case "$1" in */plans/*) return 0 ;; esac
  case "${1##*/}" in *plan*.md) return 0 ;; *) return 1 ;; esac
}

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_check() {
  local content="$1" path="$2" offender
  local weak='optional|deferred|after.?merge|nice.?to.?have'
  local bin='binary|engine|container|daemon|--compile|bun build'
  # MANDATORY smoke anywhere in document allows the change.
  if printf '%s' "$content" | LC_ALL=C grep -Eiq 'smoke.*\bMANDATORY\b|\bMANDATORY\b.*smoke'; then
    return 0
  fi
  # Weak-smoke applies only when smoke appears in the delta.
  if gate_triggered 'smoke'; then
    offender="$(printf '%s' "${GATE_DELTA_ADDED}" | grep -Ei "smoke[^.]{0,20}($weak)|($weak)[^.]{0,20}smoke" | head -1 || true)"
    if [ -n "$offender" ]; then
      deny "In staged file $path: smoke task looks optional/deferred (matched: \"${offender}\"). If incidental prose, reword; if the smoke task is mandatory add the word MANDATORY on a smoke line, or add: Smoke: N/A — <reason> (markdown decoration is fine) if this plan touches no binary/engine."
    fi
    return 0
  fi
  # Without smoke in the delta, newly added binary/engine work needs document satisfaction.
  if gate_triggered "$bin"; then
    if ! printf '%s' "$content" | LC_ALL=C grep -Eiq 'smoke'; then
      deny "In staged file $path: mentions binary/engine/container work but has no smoke task. Add a MANDATORY smoke task, or add: Smoke: N/A — <reason> (markdown decoration is fine) if it genuinely touches no binary/engine."
    fi
  fi
}

gate_load
gate_is_commit || exit 0
# shellcheck disable=SC2034 # consumed by sourced gate_scan_staged
GATE_LABEL="Smoke"
gate_scan_staged gate_in_scope gate_check
exit 0
