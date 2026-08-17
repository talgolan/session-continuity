#!/usr/bin/env bash
# hooks/lib/perf-wrap.sh — timing wrapper for shipped hooks (session-continuity plugin).
#
# Usage (from hooks/hooks.json): bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh <script-name> [args...]
#
# Execs the real hook by name (resolved under hooks/, or used directly if
# already an executable path — the latter exists so tests can point this at
# a throwaway stub without touching hooks/), times it, logs via
# perf-log.sh, then exits with the real hook's own exit code. Never reads
# or alters stdin/stdout/stderr — the wrapped hook's JSON output and
# block/allow semantics pass through untouched. See
# meta/superpowers/specs/2026-08-17-performance-logging-design.md.

set -u

SCRIPT_NAME="${1:-}"
shift || true

if [[ -z "$SCRIPT_NAME" ]]; then
  echo "perf-wrap.sh: no script name given" >&2
  exit 0
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$HERE")"

if [[ "$SCRIPT_NAME" == */* && -x "$SCRIPT_NAME" ]]; then
  TARGET="$SCRIPT_NAME"
else
  TARGET="$HOOKS_DIR/$SCRIPT_NAME"
fi
NAME_FOR_LOG="$(basename "$SCRIPT_NAME")"

# Deliberately fail OPEN (not found = allow, not block) — a logging wrapper
# should never brick tool use because a hook path is misconfigured.
if [[ ! -x "$TARGET" ]]; then
  echo "perf-wrap.sh: $TARGET not found or not executable" >&2
  exit 0
fi

PROBE="$(date +%s.%N 2>/dev/null || true)"
if [[ "$PROBE" == *[0-9].[0-9]* ]]; then
  PRECISE=1
  START="$PROBE"
else
  PRECISE=0
  START="$SECONDS"
fi

bash "$TARGET" "$@"
EXIT_CODE=$?

if [[ "$PRECISE" == "1" ]]; then
  END="$(date +%s.%N)"
  DURATION="$(awk -v a="$START" -v b="$END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "0")"
else
  DURATION="$(( SECONDS - START ))"
fi

bash "$HERE/perf-log.sh" record --source=hook --name="$NAME_FOR_LOG" --duration="$DURATION" --exit="$EXIT_CODE" >/dev/null

exit "$EXIT_CODE"
