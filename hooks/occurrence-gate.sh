#!/usr/bin/env bash
# occurrence-gate.sh — commit-time content gate (session-continuity plugin).
# Fires before Bash(git commit *). For each staged LEARNINGS.md under a
# .session-continuity/ path, BLOCKS an entry that records `Occurrence count: N
# of M` (N>=2) without a non-empty `Invariant:` line. Escape:
# `Occurrence-gate: N/A — <reason>`.
set -euo pipefail
# shellcheck disable=SC1091 # dynamically-resolved path; gate-common.sh is shellcheck-clean standalone
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_in_scope() {
  [ "${1##*/}" = "LEARNINGS.md" ] || return 1
  case "$1" in .session-continuity/*|*/.session-continuity/*) return 0 ;; *) return 1 ;; esac
}

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_check() {
  local content="$1" path="$2" n max_n=0 has_inv=0
  if gate_has_escape "$content" "Occurrence-gate"; then return 0; fi
  while IFS= read -r n; do
    if [ -z "$n" ]; then continue; fi
    if [ "$n" -gt "$max_n" ] 2>/dev/null; then max_n="$n"; fi
  done <<EOF
$(printf '%s' "$content" \
  | grep -oiE 'Occurrence count:[[:space:]]*[0-9]+[[:space:]]+of[[:space:]]+[0-9]+' \
  | grep -oiE '[0-9]+[[:space:]]+of' \
  | grep -oE '^[0-9]+')
EOF
  [ "$max_n" -ge 2 ] || return 0
  if printf '%s' "$content" | grep -Eiq 'Invariant:[[:space:]]*[^[:space:]]'; then has_inv=1; fi
  if [ "$has_inv" -eq 0 ]; then
    deny "In staged file $path: records occurrence #${max_n} of a mistake-class but names no end-state invariant. CLAUDE.md rule 4: a class fixed across 2+ attempts needs an 'Invariant: <what must hold on EVERY path, enforced at the reconciler/entry gate>' line — not another trigger-patch. Add it next to the 'Occurrence count:' line, or add: Occurrence-gate: N/A — <reason> (decoration fine)."
  fi
}

gate_load
gate_is_commit || exit 0
gate_scan_staged gate_in_scope gate_check
exit 0
