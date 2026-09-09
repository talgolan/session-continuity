#!/usr/bin/env bash
# CONTRACT_VERSION=1
# primer-freshness.sh — substantive-change probe since last primer commit.
# Usage: primer-freshness.sh [<project-dir>]
# Stdout: STALE=0|1|?
# Always exit 0.
set -u
DIR="${1:-.}"
PRIMER=".session-continuity/SESSION_PRIMER.md"

if [[ ! -f "$DIR/$PRIMER" ]]; then
  echo "STALE=?"
  exit 0
fi

primer_tip="$(git -C "$DIR" log -1 --format=%H -- "$PRIMER" 2>/dev/null || true)"
if [[ -z "$primer_tip" ]]; then
  echo "STALE=?"
  exit 0
fi

stale=0
paths="$(git -C "$DIR" log "${primer_tip}..HEAD" --name-only --pretty=format: 2>/dev/null | sort -u || true)"
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  # Ignore anything under the continuity dir (prefix).
  [[ "$path" == .session-continuity/* ]] && continue
  bn="$(basename "$path")"
  # Basename-only ignore list (docs/README.md ignored; src/readme_utils.sh not).
  if [[ "$bn" == README* || "$bn" == CHANGELOG* || "$bn" == LICENSE* ]]; then
    continue
  fi
  stale=1
  break
done <<< "$paths"

echo "STALE=$stale"
exit 0
