#!/usr/bin/env bash
# CONTRACT_VERSION=2
# hooks/lib/candidate-extract.sh — LEARNINGS candidate extraction.
# See meta/superpowers/plans/2026-09-01-learnings-generation-hardening.md
#
# Usage: candidate-extract.sh <transcript-path>
# Prints one JSON object to stdout and always exits 0:
#   {"mode":"transcript"|"unavailable"|"error","candidates":[...],
#    "overflow":N,"detail":"<string>"}
#
#   transcript  — the filter ran; candidates may still be empty.
#   unavailable — bad input: no path, unreadable, empty, or stale (>5min)
#                 transcript. The caller falls back to context-window mode.
#   error       — broken install or environment: jq absent, the .jq filter
#                 missing or from another plugin version, the filter itself
#                 failing, or an mtime that cannot be read on this platform.
#                 The caller surfaces `detail` to the user. Never silently
#                 equivalent to "no candidates" — that equivalence is how the
#                 prose version's derivations went missing for weeks.
#
# Times itself through perf-log.sh so the measurement cannot be dropped by a
# command file being rewritten around it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRANSCRIPT="${1:-}"
JQ_FILTER="$SCRIPT_DIR/candidate-extract.jq"

# BSD date has no %N and prints a literal "N"; rewrite it to a zero so the
# arithmetic below degrades to whole-second resolution instead of breaking.
_START="$(date +%s.%N 2>/dev/null | sed 's/N$/0/')"
[[ "$_START" =~ ^[0-9]+(\.[0-9]+)?$ ]] || _START=""

json_escape() {
  printf '%s' "$1" | sed -E 's/\\/\\\\/g; s/"/\\"/g' | tr '\000-\037' ' '
}

finish() {
  if [[ -n "$_START" ]]; then
    local end dur
    end="$(date +%s.%N 2>/dev/null | sed 's/N$/0/')"
    dur="$(awk -v a="$_START" -v b="$end" 'BEGIN{d=b-a; if (d<0) d=0; printf "%.3f", d}' 2>/dev/null)"
    if [[ -n "$dur" ]]; then
      bash "$SCRIPT_DIR/perf-log.sh" record --source=command --name=end-session \
        --step=step-2-transcript-extraction --duration="$dur" >/dev/null 2>&1 || true
    fi
  fi
  exit 0
}

emit() {  # <mode> <detail>
  printf '{"mode":"%s","candidates":[],"overflow":0,"detail":"%s"}\n' "$1" "$(json_escape "$2")"
  finish
}

# GNU stat's -f means --file-system and writes to stdout while exiting 1, so
# the BSD form must never be tried first inside a command substitution.
mtime_epoch() {
  local v
  v="$(stat -c %Y "$1" 2>/dev/null)"
  [[ "$v" =~ ^[0-9]+$ ]] && { printf '%s' "$v"; return 0; }
  v="$(stat -f %m "$1" 2>/dev/null)"
  [[ "$v" =~ ^[0-9]+$ ]] && { printf '%s' "$v"; return 0; }
  return 1
}

[[ -n "$TRANSCRIPT" ]] || emit unavailable "no transcript path was given."
[[ -r "$TRANSCRIPT" ]] || emit unavailable "the transcript is not readable: $TRANSCRIPT"
[[ -s "$TRANSCRIPT" ]] || emit unavailable "the transcript is empty: $TRANSCRIPT"

command -v jq >/dev/null 2>&1 \
  || emit error "jq is not installed, so LEARNINGS candidates cannot be extracted. Install jq and re-run."
[[ -r "$JQ_FILTER" ]] \
  || emit error "candidate-extract.jq is missing from $SCRIPT_DIR — the plugin cache is incomplete. Run \`/session-continuity:update\`."
grep -q '^# CONTRACT_VERSION=2$' "$JQ_FILTER" \
  || emit error "candidate-extract.jq is from a different plugin version — run \`/session-continuity:update\`."

MTIME="$(mtime_epoch "$TRANSCRIPT")" \
  || emit error "neither \`stat -c %Y\` nor \`stat -f %m\` works on this platform, so transcript staleness cannot be checked."
NOW="$(date -u +%s)"
AGE=$(( NOW - MTIME ))
[[ "$AGE" -le 300 ]] \
  || emit unavailable "the transcript is stale (last written $(( AGE / 60 )) minutes ago) — it is probably not this session."

TRACKED_FILES_JSON="$(git ls-files 2>/dev/null | jq -R -s 'split("\n") | map(select(length>0))' 2>/dev/null)"
[[ -n "$TRACKED_FILES_JSON" ]] || TRACKED_FILES_JSON="[]"

ERRFILE="$(mktemp)"
RESULT="$(jq -n --argjson tracked_files "$TRACKED_FILES_JSON" -f "$JQ_FILTER" "$TRANSCRIPT" 2>"$ERRFILE")"
JQ_STATUS=$?
DETAIL="$(head -1 "$ERRFILE" 2>/dev/null)"
rm -f "$ERRFILE"

if [[ "$JQ_STATUS" -ne 0 || -z "$RESULT" ]]; then
  emit error "the candidate filter failed: ${DETAIL:-jq exited $JQ_STATUS}"
fi

printf '%s\n' "$RESULT"
finish
