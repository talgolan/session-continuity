#!/usr/bin/env bash
# backend-parity-gate.sh — commit-time content gate (session-continuity plugin).
# Fires before Bash(git commit *). For each staged plan file that frames smoke as
# multi-backend (mentions "backend(s)"), BLOCKS when fewer than two concrete
# backends are named. Escape: `Backend-parity: N/A — <reason>`.
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
  local content="$1" path="$2" n hit_count=0
  if gate_has_escape "$content" "Backend-parity"; then return 0; fi
  # "Backend-parity" itself contains "backend": scan with the hatch blanked so
  # the line that exempts this doc cannot be the sole "backend" mention that
  # triggers this gate in the first place.
  local scan; scan="$(gate_mask_escape "$content" "Backend-parity")"
  printf '%s' "$scan" | grep -Eiq 'backends?\b' || return 0
  for n in docker apple podman containerd colima kata lima orbstack; do
    if printf '%s' "$scan" | grep -Eiq "\\b${n}\\b"; then hit_count=$((hit_count + 1)); fi
  done
  if [ "$hit_count" -lt 2 ]; then
    deny "In staged file $path: mentions 'backend(s)' but names fewer than two concrete backends. A smoke runner proven on only one backend has an unverified half — pair every backend-specific section with the other (e.g. Docker + Apple container). Name the second backend, or add: Backend-parity: N/A — <reason> (decoration fine) if there genuinely is only one."
  fi
}

gate_load
gate_is_commit || exit 0
gate_scan_staged gate_in_scope gate_check
exit 0
