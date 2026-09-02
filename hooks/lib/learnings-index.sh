#!/usr/bin/env bash
# CONTRACT_VERSION=2
# hooks/lib/learnings-index.sh — LEARNINGS.md derivations.
# See meta/superpowers/plans/2026-09-01-learnings-generation-hardening.md
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
# Two failure classes, deliberately distinct:
#   Bad input (missing/unreadable file) — `report` prints "MAX 0", `reindex`
#   is a silent no-op, both exit 0.
#   Broken install (an awk sibling missing or from another plugin version, or
#   an awk pass exiting non-zero, or a regenerated file that is empty or has
#   lost entries) — a one-line message on stderr and exit 2, with the target
#   file never opened for writing. Losing LEARNINGS.md is worse than any
#   ritual that fails to finish.
#
# The regenerated index applies this script's own rule (hard 12-word cutoff
# + ellipsis, dictionary-order case-insensitive sort) consistently. It does
# not reproduce a prior hand-authored index byte-for-byte.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBCOMMAND="${1:-}"
FILE="${2:-}"
WORK=""

AWK_SIBLINGS="learnings-index-report.awk learnings-index-bullets.awk learnings-index-splice.awk"

die_install() {
  [[ -n "$WORK" && -d "$WORK" ]] && rm -rf "$WORK"
  printf 'learnings-index.sh: %s\n' "$1" >&2
  exit 2
}

check_siblings() {
  local f
  for f in $AWK_SIBLINGS; do
    [[ -r "$SCRIPT_DIR/$f" ]] || die_install \
      "$f is missing from $SCRIPT_DIR — the plugin cache is incomplete. Run \`/session-continuity:update\`. LEARNINGS.md was not modified."
    grep -q '^# CONTRACT_VERSION=2$' "$SCRIPT_DIR/$f" || die_install \
      "$f is from a different plugin version — run \`/session-continuity:update\`. LEARNINGS.md was not modified."
  done
}

count_entries() {
  grep -cE '^### [0-9]+\.' "$1" 2>/dev/null || true
}

report() {
  check_siblings
  awk -f "$SCRIPT_DIR/learnings-index-report.awk" "$1" \
    || die_install "the report pass failed (awk exited non-zero)."
}

reindex() {
  local file="$1" has_index=0 bullets tmp n_bullets before after

  check_siblings

  WORK="$(mktemp -d)" || die_install "could not create a temp directory."
  bullets="$WORK/bullets"
  tmp="$WORK/out"

  grep -q '^## Symptoms index' "$file" && has_index=1

  awk -f "$SCRIPT_DIR/learnings-index-bullets.awk" "$file" | LC_ALL=C sort -d -f > "$bullets" \
    || die_install "the bullet pass failed (awk or sort exited non-zero). LEARNINGS.md was not modified."

  awk -v bfile="$bullets" -v has_index="$has_index" \
    -f "$SCRIPT_DIR/learnings-index-splice.awk" "$file" > "$tmp" \
    || die_install "the splice pass failed (awk exited non-zero). LEARNINGS.md was not modified."

  # Write gate. Both conditions are checked at the one place that writes, so
  # a future change to either awk pass cannot route around them.
  [[ -s "$tmp" ]] || die_install \
    "the regenerated file came out empty. LEARNINGS.md was not modified."

  before="$(count_entries "$file")"
  after="$(count_entries "$tmp")"
  [[ "$before" == "$after" ]] || die_install \
    "entry count changed during regeneration ($before -> $after). LEARNINGS.md was not modified."

  n_bullets="$(wc -l < "$bullets" | tr -d ' ')"

  if cmp -s "$file" "$tmp"; then
    rm -rf "$WORK"; WORK=""
    echo "no change"
  else
    cat "$tmp" > "$file"
    rm -rf "$WORK"; WORK=""
    echo "regenerated $n_bullets bullet(s)"
  fi
}

if [[ ! -r "$FILE" ]]; then
  [[ "$SUBCOMMAND" == "report" ]] && echo "MAX 0"
  exit 0
fi

case "$SUBCOMMAND" in
  report)  report "$FILE" ;;
  reindex) reindex "$FILE" ;;
  *) echo "learnings-index.sh: unknown subcommand '$SUBCOMMAND' (report|reindex)" >&2 ;;
esac
exit 0
