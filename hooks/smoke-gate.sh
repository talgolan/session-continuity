#!/usr/bin/env bash
# smoke-gate.sh — commit-time content gate (session-continuity plugin).
# Fires before Bash(git commit *). For each staged plan file (*/plans/*.md or a
# *plan*.md basename), BLOCKS a binary/engine-touching plan that lacks a
# MANDATORY smoke task (weak-smoke or no-smoke). Escape: `Smoke: N/A — <reason>`.
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
  local content="$1" path="$2" mentions_smoke offender
  if gate_has_escape "$content" "Smoke"; then return 0; fi
  # "Smoke:" is this gate's own hatch label, so an unmatched hatch line counts
  # as a smoke mention — which both suppresses the binary/engine check and, if
  # its reason contains a weak word ("N/A deferred …"), makes the hatch its own
  # weak-smoke offender. Blank it before every check below.
  local scan; scan="$(gate_mask_escape "$content" "Smoke")"
  # Explicit MANDATORY pass (before weak-smoke).
  if printf '%s' "$scan" | grep -Eiq 'smoke.*\bMANDATORY\b|\bMANDATORY\b.*smoke'; then return 0; fi
  mentions_smoke="$(printf '%s' "$scan" | grep -ci 'smoke' || true)"
  local weak='optional|deferred|after.?merge|nice.?to.?have'
  if [ "${mentions_smoke:-0}" -gt 0 ]; then
    offender="$(printf '%s' "$scan" | grep -Ei "smoke[^.]{0,20}($weak)|($weak)[^.]{0,20}smoke" | head -1 || true)"
    if [ -n "$offender" ]; then
      deny "In staged file $path: smoke task looks optional/deferred (matched: \"${offender}\"). If incidental prose, reword; if the smoke task is mandatory add the word MANDATORY on a smoke line, or add: Smoke: N/A — <reason> (markdown decoration is fine) if this plan touches no binary/engine."
    fi
    return 0
  fi
  if printf '%s' "$scan" | grep -Eiq 'binary|engine|container|daemon|--compile|bun build'; then
    deny "In staged file $path: mentions binary/engine/container work but has no smoke task. Add a MANDATORY smoke task, or add: Smoke: N/A — <reason> (markdown decoration is fine) if it genuinely touches no binary/engine."
  fi
}

gate_load
gate_is_commit || exit 0
gate_scan_staged gate_in_scope gate_check
exit 0
