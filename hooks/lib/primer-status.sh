#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/primer-status.sh — shared status computation for the primer's
# "current state" report. Prints four key=value lines on stdout,
# best-effort, always exits 0. Used by hooks/session-start.sh (resolved
# next to itself, no CONTRACT_VERSION gate — same convention
# count-entries.sh already follows there) and by commands/primer.md's
# check mode (resolved via CLAUDE_PLUGIN_ROOT, gated by require_script) so
# the two can no longer disagree about what "current" means. See the
# Phase 3 entry of
# meta/superpowers/specs/2026-09-02-determinism-program-design.md.
#
# Usage: primer-status.sh [<dir>]
# <dir> defaults to "." — the directory containing .session-continuity/.
#
# Prints exactly:
#   HEAD_SHA=<short-sha or ?>
#   PRIMER_MTIME=<YYYY-MM-DD HH:MM or ?>
#   BACKLOG_COUNT=<int or ?>
#   LEARNINGS_COUNT=<int or ?>
#
# Every value is independently best-effort: a failure on one line never
# blocks the others, and never aborts the script.

set -u

DIR="${1:-.}"
HERE="$(dirname "$0")"

sha="$(git -C "$DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"

primer_path="$DIR/.session-continuity/SESSION_PRIMER.md"
mtime="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$primer_path" 2>/dev/null \
  || stat -c '%y' "$primer_path" 2>/dev/null \
  || echo '?')"

count_helper="$HERE/count-entries.sh"
if [ -f "$count_helper" ]; then
  backlog_count="$(bash "$count_helper" "$DIR/.session-continuity/BACKLOG.md" 2>/dev/null || echo '?')"
  learnings_count="$(bash "$count_helper" "$DIR/.session-continuity/LEARNINGS.md" 2>/dev/null || echo '?')"
else
  backlog_count="?"
  learnings_count="?"
fi

echo "HEAD_SHA=$sha"
echo "PRIMER_MTIME=$mtime"
echo "BACKLOG_COUNT=$backlog_count"
echo "LEARNINGS_COUNT=$learnings_count"
exit 0
