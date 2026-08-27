#!/usr/bin/env bash
# proven-gate.sh — commit-time content gate (session-continuity plugin).
#
# Fires before Bash(git commit *). For each staged */specs/*.md or */plans/*.md
# file (skipping dot-prefixed scratch), BLOCKS the commit when the file makes a
# "proven"/"verified"/"spike conclusive" claim (word boundaries) without BOTH:
#   Real path: <which production code path actually ran>
#   Stubbed:   <what stood in — or "nothing">
# Escape hatch (decoration tolerant): a line `Proven-gate: N/A — <reason>`.
# See meta/superpowers/specs/2026-08-27-commit-time-content-gates-design.md.
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
  if gate_has_escape "$content" "Proven-gate"; then return 0; fi
  local has_claim=0
  if printf '%s' "$content" | grep -Eiqw 'proven|verified'; then has_claim=1; fi
  if printf '%s' "$content" | grep -Eiq 'spike[[:space:]]+conclusive'; then has_claim=1; fi
  [ "$has_claim" -eq 0 ] && return 0
  local has_real=0 has_stub=0
  if printf '%s' "$content" | grep -Eiq 'Real path:[[:space:]]*[^[:space:]]'; then has_real=1; fi
  if printf '%s' "$content" | grep -Eiq 'Stubbed:[[:space:]]*[^[:space:]]'; then has_stub=1; fi
  if [ "$has_real" -eq 0 ] || [ "$has_stub" -eq 0 ]; then
    deny "In staged file $path: makes a 'proven/verified/spike conclusive' claim but does not name what was tested. Add both fields next to the claim — 'Real path: <which production code path ran>' and 'Stubbed: <what stood in, or \"nothing\">'. If the stubbed thing is the feature under test, the claim is not proven. Or add a line (markdown decoration is fine): Proven-gate: N/A — <reason>."
  fi
}

gate_load
gate_is_commit || exit 0
gate_scan_staged gate_in_scope gate_check
exit 0
