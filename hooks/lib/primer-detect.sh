#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/primer-detect.sh — dispatch decision for /session-continuity:primer.
# See meta/superpowers/specs/2026-09-08-primer-detect-design.md for the full
# state machine this ports (unchanged behavior, just executable instead of
# hand-evaluated per invocation) and
# meta/superpowers/plans/2026-09-08-primer-detect.md for the implementation
# plan.
#
# Usage: primer-detect.sh [<project-dir>]   (default: .)
# Prints KEY=value lines to stdout on success, ending in
# STEPS=<comma,separated,ordered,list> (possibly empty — empty means check
# mode, primer is current and no migration triggers fired):
#   PRIMER_EXISTS=0|1              LEARNINGS_EXISTS=0|1
#   PROJECT_CONTEXT_EXISTS=0|1     OUTSTANDING_ITEMS_EXISTS=0|1
#   PRIMER_HAS_INLINE_OUTSTANDING=0|1   BACKLOG_EXISTS=0|1
#   ROADMAP_EXISTS=0|1             GITHUB_ORIGIN=0|1
#   LOG_DRIFT=0|1                  CODE_STAGED=0|1
#   STEPS=<split,outstanding_split,backlog_rename,backlog_to_issues,refresh,init>
#
# Operational failure (jq missing, primer-detect.jq missing or from a
# different CONTRACT_VERSION, <project-dir> not inside a git repository)
# prints one diagnostic line to stderr and exits 1 with NO STEPS= line on
# stdout at all — no conservative default dispatch. Some STEPS values gate
# destructive migrations (git mv/git rm in Steps 3c/3d), so guessing wrong
# on failure is worse than stopping; the caller must treat a missing
# STEPS= line as a hard stop, not degrade to any default step list.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ_FILTER="$SCRIPT_DIR/primer-detect.jq"
DIR="${1:-.}"

die() {  # <message>
  printf 'primer-detect.sh: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 \
  || die "jq is not installed, so the primer dispatch cannot be computed."
[[ -r "$JQ_FILTER" ]] \
  || die "primer-detect.jq is missing from $SCRIPT_DIR — the plugin cache is incomplete. Run \`/session-continuity:update\`."
grep -q '^# CONTRACT_VERSION=1$' "$JQ_FILTER" \
  || die "primer-detect.jq is from a different plugin version — run \`/session-continuity:update\`."
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "$DIR is not inside a git repository."

file_flag() {  # <path relative to $DIR> -> 1|0
  [[ -f "$DIR/$1" ]] && echo 1 || echo 0
}

PRIMER_EXISTS="$(file_flag .session-continuity/SESSION_PRIMER.md)"
LEARNINGS_EXISTS="$(file_flag .session-continuity/LEARNINGS.md)"
PROJECT_CONTEXT_EXISTS="$(file_flag .session-continuity/PROJECT_CONTEXT.md)"
OUTSTANDING_ITEMS_EXISTS="$(file_flag .session-continuity/OUTSTANDING_ITEMS.md)"
BACKLOG_EXISTS="$(file_flag .session-continuity/BACKLOG.md)"
ROADMAP_EXISTS="$(file_flag .session-continuity/ROADMAP.md)"

PRIMER_CONTENT=""
[[ "$PRIMER_EXISTS" == "1" ]] && PRIMER_CONTENT="$(cat "$DIR/.session-continuity/SESSION_PRIMER.md")"

ORIGIN_URL="$(git -C "$DIR" remote get-url origin 2>/dev/null || true)"
GIT_LOG="$(git -C "$DIR" log --oneline -5 2>/dev/null || true)"
STAGED_FILES="$(git -C "$DIR" diff --cached --name-only 2>/dev/null || true)"

ERRFILE="$(mktemp)"
RESULT="$(
  jq -r -n \
    --argjson primer_exists "$PRIMER_EXISTS" \
    --argjson learnings_exists "$LEARNINGS_EXISTS" \
    --argjson project_context_exists "$PROJECT_CONTEXT_EXISTS" \
    --argjson outstanding_items_exists "$OUTSTANDING_ITEMS_EXISTS" \
    --argjson backlog_exists "$BACKLOG_EXISTS" \
    --argjson roadmap_exists "$ROADMAP_EXISTS" \
    --arg origin_url "$ORIGIN_URL" \
    --arg git_log "$GIT_LOG" \
    --arg staged_files "$STAGED_FILES" \
    --arg primer_content "$PRIMER_CONTENT" \
    -f "$JQ_FILTER" 2>"$ERRFILE"
)"
JQ_STATUS=$?
DETAIL="$(head -1 "$ERRFILE" 2>/dev/null)"
rm -f "$ERRFILE"

if [[ "$JQ_STATUS" -ne 0 || -z "$RESULT" ]]; then
  die "the detect filter failed: ${DETAIL:-jq exited $JQ_STATUS}"
fi

printf '%s\n' "$RESULT"
