#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/learnings-index.sh — LEARNINGS.md derivations (Change 3).
# See meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md
#
# Usage:
#   learnings-index.sh report <file>    Prints "MAX <n>" then one
#                                        "DUPNUM <n> <lines>" per duplicated
#                                        entry number and one "DUPSLUG
#                                        <slug> <lines>" per duplicated slug.
#   learnings-index.sh reindex <file>   Regenerates "## Symptoms index" in
#                                        place from every entry's
#                                        "**Symptom.**" line. Idempotent
#                                        from the first run. Prints
#                                        "regenerated <n> bullet(s)" or
#                                        "no change".
#
# Never fails loud: a missing/unreadable file makes `report` print "MAX 0"
# and `reindex` a silent no-op. Both exit 0 regardless.
#
# The regenerated index applies this script's own rule (hard 12-word
# cutoff + ellipsis, dictionary-order case-insensitive sort) consistently.
# It does not and should not reproduce a prior hand/LLM-authored index
# byte-for-byte where that index applied looser judgment — see the spec's
# Testing plan, Index script.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBCOMMAND="${1:-}"
FILE="${2:-}"

if [[ ! -r "$FILE" ]]; then
  [[ "$SUBCOMMAND" == "report" ]] && echo "MAX 0"
  exit 0
fi

report() {
  awk -f "$SCRIPT_DIR/learnings-index-report.awk" "$1"
}

reindex() {
  local file="$1" has_index=0 bullets tmp
  grep -q '^## Symptoms index' "$file" && has_index=1
  bullets="$(mktemp)"
  tmp="$(mktemp)"

  awk -f "$SCRIPT_DIR/learnings-index-bullets.awk" "$file" | LC_ALL=C sort -d -f > "$bullets"
  awk -v bfile="$bullets" -v has_index="$has_index" \
    -f "$SCRIPT_DIR/learnings-index-splice.awk" "$file" > "$tmp"

  local n_bullets
  n_bullets="$(wc -l < "$bullets" | tr -d ' ')"

  if diff -q "$file" "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp" "$bullets"
    echo "no change"
  else
    cat "$tmp" > "$file"
    rm -f "$tmp" "$bullets"
    echo "regenerated $n_bullets bullet(s)"
  fi
}

case "$SUBCOMMAND" in
  report)  report "$FILE" ;;
  reindex) reindex "$FILE" ;;
  *) echo "learnings-index.sh: unknown subcommand '$SUBCOMMAND' (report|reindex)" >&2 ;;
esac
exit 0
