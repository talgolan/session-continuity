#!/usr/bin/env bash
# occurrence-gate.sh — Escape via driver: Occurrence-gate: N/A — <reason>.
set -euo pipefail
# shellcheck disable=SC1091 # dynamically-resolved path; gate-common.sh is shellcheck-clean standalone
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_in_scope() {
  [ "${1##*/}" = "LEARNINGS.md" ] || return 1
  case "$1" in .session-continuity/*|*/.session-continuity/*) return 0 ;; *) return 1 ;; esac
}

_occurrence_max_n() {  # <text> -> max N from Occurrence count: N of M
  local text="$1" n max_n=0
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    if [ "$n" -gt "$max_n" ] 2>/dev/null; then max_n="$n"; fi
  done <<EOF
$(printf '%s' "$text" \
  | grep -oiE 'Occurrence count:[[:space:]]*[0-9]+[[:space:]]+of[[:space:]]+[0-9]+' \
  | grep -oiE '[0-9]+[[:space:]]+of' \
  | grep -oE '^[0-9]+')
EOF
  printf '%s' "$max_n"
}

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_check() {
  local content="$1" path="$2" max_n=0 max_added=0 has_inv=0 fire=0
  max_added="$(_occurrence_max_n "${GATE_DELTA_ADDED:-}")"
  max_n="$(_occurrence_max_n "$content")"
  if [ "$max_added" -ge 2 ]; then fire=1; fi
  if [ "$fire" -eq 0 ] && [ "$max_n" -ge 2 ] \
    && printf '%s' "${GATE_DELTA_REMOVED:-}" | LC_ALL=C grep -Eiq 'Invariant:[[:space:]]*[^[:space:]]'; then
    fire=1
  fi
  [ "$fire" -eq 1 ] || return 0
  [ "$max_n" -ge 2 ] || return 0
  if printf '%s' "$content" | LC_ALL=C grep -Eiq 'Invariant:[[:space:]]*[^[:space:]]'; then has_inv=1; fi
  if [ "$has_inv" -eq 0 ]; then
    deny "In staged file $path: records occurrence #${max_n} of a mistake-class but names no end-state invariant. CLAUDE.md rule 4: a class fixed across 2+ attempts needs an 'Invariant: <what must hold on EVERY path, enforced at the reconciler/entry gate>' line — not another trigger-patch. Add it next to the 'Occurrence count:' line, or add: Occurrence-gate: N/A — <reason> (decoration fine)."
  fi
}

gate_load
gate_is_commit || exit 0
# shellcheck disable=SC2034 # consumed by sourced gate_scan_staged
GATE_LABEL="Occurrence-gate"
gate_scan_staged gate_in_scope gate_check
exit 0
