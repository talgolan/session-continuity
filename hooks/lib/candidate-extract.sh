#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/candidate-extract.sh — LEARNINGS candidate extraction (Change 1).
# See meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md
#
# Usage: candidate-extract.sh <transcript-path>
# Prints one JSON object to stdout:
#   {"mode":"transcript"|"unavailable","candidates":[...],"overflow":N}
# Never fails loud: exit 0 always. Missing/unreadable/empty/stale (>5min)
# transcript, or a missing jq, yields mode:"unavailable" with empty
# candidates.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRANSCRIPT="${1:-}"

emit_unavailable() {
  printf '{"mode":"unavailable","candidates":[],"overflow":0}\n'
  exit 0
}

[[ -n "$TRANSCRIPT" ]] || emit_unavailable
[[ -r "$TRANSCRIPT" ]] || emit_unavailable
[[ -s "$TRANSCRIPT" ]] || emit_unavailable

MTIME_EPOCH="$(stat -f %m "$TRANSCRIPT" 2>/dev/null || stat -c %Y "$TRANSCRIPT" 2>/dev/null || echo "")"
if [[ "$MTIME_EPOCH" =~ ^[0-9]+$ ]]; then
  NOW_EPOCH="$(date -u +%s)"
  AGE=$(( NOW_EPOCH - MTIME_EPOCH ))
  [[ "$AGE" -le 300 ]] || emit_unavailable
fi

command -v jq >/dev/null 2>&1 || emit_unavailable

TRACKED_FILES_JSON="$(git ls-files 2>/dev/null | jq -R -s 'split("\n") | map(select(length>0))' 2>/dev/null || echo "[]")"

RESULT="$(jq -n --argjson tracked_files "$TRACKED_FILES_JSON" \
  -f "$SCRIPT_DIR/candidate-extract.jq" \
  "$TRANSCRIPT" 2>/dev/null)"

[[ -n "$RESULT" ]] || emit_unavailable

printf '%s\n' "$RESULT"
exit 0
