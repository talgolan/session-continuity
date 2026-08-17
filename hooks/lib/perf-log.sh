#!/usr/bin/env bash
# hooks/lib/perf-log.sh — shared performance-log writer (session-continuity plugin).
#
# Single 'record' subcommand, used by hooks/lib/perf-wrap.sh (hook timing)
# and by the self-reported timers in commands/primer.md and
# commands/end-session.md. See
# meta/superpowers/specs/2026-08-17-performance-logging-design.md.
#
# Usage:
#   perf-log.sh record --source=hook --name=<script> --duration=<seconds> --exit=<code>
#   perf-log.sh record --source=command --name=<slug> --step=<slug> --duration=<seconds> [--retries=<n>] [--items=<n>]
#
# Never fails loud: any error here prints to stderr and returns 0. Logging
# must never be the reason a hook blocks a commit or a command errors out.

set -u

subcommand="${1:-}"
shift || true
if [[ "$subcommand" != "record" ]]; then
  echo "perf-log.sh: unknown subcommand '$subcommand' (only 'record' is supported)" >&2
  exit 0
fi

SOURCE=""; NAME=""; DURATION=""; EXIT=""; STEP=""; RETRIES=""; ITEMS=""
for arg in "$@"; do
  case "$arg" in
    --source=*)   SOURCE="${arg#*=}" ;;
    --name=*)     NAME="${arg#*=}" ;;
    --duration=*) DURATION="${arg#*=}" ;;
    --exit=*)     EXIT="${arg#*=}" ;;
    --step=*)     STEP="${arg#*=}" ;;
    --retries=*)  RETRIES="${arg#*=}" ;;
    --items=*)    ITEMS="${arg#*=}" ;;
    *) : ;;  # ignore unknown flags rather than fail
  esac
done

if [[ -z "$SOURCE" || -z "$NAME" || -z "$DURATION" ]]; then
  echo "perf-log.sh: record requires --source, --name, --duration" >&2
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$REPO_ROOT" ]] && exit 0   # not a git repo: silent no-op

SC_DIR="$REPO_ROOT/.session-continuity"
LOG_FILE="$SC_DIR/performance.log"
MARKER="$SC_DIR/.gitignore-ensured"

mkdir -p "$SC_DIR" 2>/dev/null || { echo "perf-log.sh: could not create $SC_DIR" >&2; exit 0; }

if [[ ! -f "$MARKER" ]]; then
  GITIGNORE="$REPO_ROOT/.gitignore"
  LINE=".session-continuity/performance.log"
  touch "$GITIGNORE" 2>/dev/null
  if ! grep -qxF "$LINE" "$GITIGNORE" 2>/dev/null; then
    printf '%s\n' "$LINE" >> "$GITIGNORE" 2>/dev/null
  fi
  touch "$MARKER" 2>/dev/null
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

json_escape() {
  printf '%s' "$1" | sed -E 's/\\/\\\\/g; s/"/\\"/g' | tr '\000-\037' ' '
}

LINE_JSON="{\"ts\":\"$(json_escape "$TS")\",\"source\":\"$(json_escape "$SOURCE")\",\"name\":\"$(json_escape "$NAME")\",\"duration_s\":$(json_escape "$DURATION")"
[[ -n "$EXIT" ]]    && LINE_JSON+=",\"exit\":$(json_escape "$EXIT")"
[[ -n "$STEP" ]]    && LINE_JSON+=",\"step\":\"$(json_escape "$STEP")\""
[[ -n "$RETRIES" ]] && LINE_JSON+=",\"retries\":$(json_escape "$RETRIES")"
[[ -n "$ITEMS" ]]   && LINE_JSON+=",\"items\":$(json_escape "$ITEMS")"
LINE_JSON+="}"

printf '%s\n' "$LINE_JSON" >> "$LOG_FILE" 2>/dev/null || echo "perf-log.sh: could not write $LOG_FILE" >&2
exit 0
