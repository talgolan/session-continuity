#!/usr/bin/env bash
# hooks/lib/perf-log.sh — shared performance-log writer (session-continuity plugin).
#
# Three subcommands:
#   record — append one JSON line with a caller-supplied duration.
#   mark   — a record whose duration is always 0.000: a named timestamp for
#            a later 'since' call to read back.
#   since  — read the most recent mark/record for a given name+step, then
#            either (a) record the elapsed time under a new step, or
#            (b) print the resolved epoch on stdout for a caller that needs
#            the raw number (e.g. to hand to another script), not a
#            duration to log.
#
# Used by hooks/lib/perf-wrap.sh (hook timing), by the self-reported timers
# in commands/primer.md and commands/end-session.md, and (mark/since) by
# end-session.md's prompt-wait and ritual-complete/agent-active timing. See
# meta/superpowers/specs/2026-08-17-performance-logging-design.md and the
# Phase 3 entry of meta/superpowers/specs/2026-09-02-determinism-program-design.md.
#
# Usage:
#   perf-log.sh record --source=hook --name=<script> --duration=<seconds> --exit=<code>
#   perf-log.sh record --source=command --name=<slug> --step=<slug> --duration=<seconds> [--retries=<n>] [--items=<n>]
#   perf-log.sh mark --source=<hook|command> --name=<slug> --step=<slug>
#   perf-log.sh since --source=<hook|command> --name=<slug> --mark-step=<slug> --emit-step=<slug> [--retries=<n>] [--items=<n>]
#   perf-log.sh since --print-epoch --name=<slug> --mark-step=<slug>
#
# Never fails loud: any error here prints to stderr and returns 0. Logging
# must never be the reason a hook blocks a commit or a command errors out.

set -u

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

json_escape() {
  printf '%s' "$1" | sed -E 's/\\/\\\\/g; s/"/\\"/g' | tr '\000-\037' ' '
}

# write_record <source> <name> <duration> <exit> <step> <retries> <items>
# Appends one JSON line to .session-continuity/performance.log, ensuring the
# gitignore entries exist first. Silent no-op outside a git repo. Never
# fails loud.
write_record() {
  local SOURCE="$1" NAME="$2" DURATION="$3" EXIT="$4" STEP="$5" RETRIES="$6" ITEMS="$7"

  [[ -z "$REPO_ROOT" ]] && return 0   # not a git repo: silent no-op

  local SC_DIR="$REPO_ROOT/.session-continuity"
  local LOG_FILE="$SC_DIR/performance.log"
  local MARKER="$SC_DIR/.gitignore-ensured"

  mkdir -p "$SC_DIR" 2>/dev/null || { echo "perf-log.sh: could not create $SC_DIR" >&2; return 0; }

  if [[ ! -f "$MARKER" ]]; then
    local GITIGNORE="$REPO_ROOT/.gitignore"
    touch "$GITIGNORE" 2>/dev/null
    local LINE
    for LINE in ".session-continuity/performance.log" ".session-continuity/.gitignore-ensured" ".session-continuity/.end-session-checklist.tsv"; do
      if ! grep -qxF "$LINE" "$GITIGNORE" 2>/dev/null; then
        printf '%s\n' "$LINE" >> "$GITIGNORE" 2>/dev/null
      fi
    done
    touch "$MARKER" 2>/dev/null
  fi

  local TS
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local LINE_JSON
  LINE_JSON="{\"ts\":\"$(json_escape "$TS")\",\"source\":\"$(json_escape "$SOURCE")\",\"name\":\"$(json_escape "$NAME")\",\"duration_s\":$(json_escape "$DURATION")"
  [[ -n "$EXIT" ]]    && LINE_JSON+=",\"exit\":$(json_escape "$EXIT")"
  [[ -n "$STEP" ]]    && LINE_JSON+=",\"step\":\"$(json_escape "$STEP")\""
  [[ -n "$RETRIES" ]] && LINE_JSON+=",\"retries\":$(json_escape "$RETRIES")"
  [[ -n "$ITEMS" ]]   && LINE_JSON+=",\"items\":$(json_escape "$ITEMS")"
  LINE_JSON+="}"

  printf '%s\n' "$LINE_JSON" >> "$LOG_FILE" 2>/dev/null || echo "perf-log.sh: could not write $LOG_FILE" >&2
  return 0
}

# resolve_mark_epoch <name> <step>
# Finds the most recent performance.log line matching name+step, parses its
# ts, prints the epoch on stdout, returns 0. Returns 1 (prints nothing) if
# unfound/unparseable/no log file — callers must treat that as "skip, do
# not log or use a bogus value", never fall back to `now`.
resolve_mark_epoch() {
  local NAME="$1" STEP="$2"
  [[ -z "$REPO_ROOT" ]] && return 1
  local LOG_FILE="$REPO_ROOT/.session-continuity/performance.log"
  [[ -r "$LOG_FILE" ]] || return 1

  local ts epoch
  ts="$(grep "\"name\":\"$NAME\"" "$LOG_FILE" 2>/dev/null \
    | grep "\"step\":\"$STEP\"" | tail -1 \
    | sed -E 's/.*"ts":"([^"]*)".*/\1/' || true)"
  [[ -z "$ts" ]] && return 1

  epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null \
    || date -u -d "$ts" +%s 2>/dev/null || true)"
  [[ "$epoch" =~ ^[0-9]+$ ]] || return 1

  printf '%s' "$epoch"
  return 0
}

subcommand="${1:-}"
shift || true

case "$subcommand" in
  record)
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
        *) : ;;
      esac
    done

    if [[ -z "$SOURCE" || -z "$NAME" || -z "$DURATION" ]]; then
      echo "perf-log.sh: record requires --source, --name, --duration" >&2
      exit 0
    fi
    if ! [[ "$DURATION" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
      echo "perf-log.sh: record requires --source, --name, --duration" >&2
      exit 0
    fi
    [[ -n "$EXIT" && ! "$EXIT" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && EXIT=""
    [[ -n "$RETRIES" && ! "$RETRIES" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && RETRIES=""
    [[ -n "$ITEMS" && ! "$ITEMS" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && ITEMS=""

    write_record "$SOURCE" "$NAME" "$DURATION" "$EXIT" "$STEP" "$RETRIES" "$ITEMS"
    ;;

  mark)
    SOURCE=""; NAME=""; STEP=""
    for arg in "$@"; do
      case "$arg" in
        --source=*) SOURCE="${arg#*=}" ;;
        --name=*)   NAME="${arg#*=}" ;;
        --step=*)   STEP="${arg#*=}" ;;
        *) : ;;
      esac
    done
    if [[ -z "$SOURCE" || -z "$NAME" || -z "$STEP" ]]; then
      echo "perf-log.sh: mark requires --source, --name, --step" >&2
      exit 0
    fi
    write_record "$SOURCE" "$NAME" "0.000" "" "$STEP" "" ""
    ;;

  since)
    SOURCE=""; NAME=""; MARK_STEP=""; EMIT_STEP=""; RETRIES=""; ITEMS=""; PRINT_EPOCH=0
    for arg in "$@"; do
      case "$arg" in
        --source=*)     SOURCE="${arg#*=}" ;;
        --name=*)       NAME="${arg#*=}" ;;
        --mark-step=*)  MARK_STEP="${arg#*=}" ;;
        --emit-step=*)  EMIT_STEP="${arg#*=}" ;;
        --retries=*)    RETRIES="${arg#*=}" ;;
        --items=*)      ITEMS="${arg#*=}" ;;
        --print-epoch)  PRINT_EPOCH=1 ;;
        *) : ;;
      esac
    done

    if [[ -z "$NAME" || -z "$MARK_STEP" ]]; then
      echo "perf-log.sh: since requires --name and --mark-step" >&2
      exit 0
    fi

    if [[ "$PRINT_EPOCH" == "1" ]]; then
      epoch="$(resolve_mark_epoch "$NAME" "$MARK_STEP")" || exit 0
      printf '%s\n' "$epoch"
      exit 0
    fi

    if [[ -z "$SOURCE" || -z "$EMIT_STEP" ]]; then
      echo "perf-log.sh: since requires --source and --emit-step (or --print-epoch)" >&2
      exit 0
    fi

    [[ -n "$RETRIES" && ! "$RETRIES" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && RETRIES=""
    [[ -n "$ITEMS" && ! "$ITEMS" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && ITEMS=""

    mark_epoch="$(resolve_mark_epoch "$NAME" "$MARK_STEP")" || exit 0
    now_epoch="$(date -u +%s)"
    duration="$(( now_epoch - mark_epoch )).000"

    write_record "$SOURCE" "$NAME" "$duration" "" "$EMIT_STEP" "$RETRIES" "$ITEMS"
    ;;

  *)
    echo "perf-log.sh: unknown subcommand '$subcommand' (expected 'record', 'mark', or 'since')" >&2
    exit 0
    ;;
esac

exit 0
