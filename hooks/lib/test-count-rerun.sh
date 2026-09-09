#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/test-count-rerun.sh — test-count majority-vote rerun for
# /session-continuity:primer Step 4 (Refresh mode). See
# meta/superpowers/specs/2026-09-09-test-count-rerun-design.md for the
# full contract this implements (unchanged behavior from the prior
# hand-evaluated prose, just executable instead of hand-derived per
# invocation) and meta/superpowers/plans/2026-09-09-test-count-rerun.md
# for the implementation plan.
#
# Usage: test-count-rerun.sh <project-dir> <last-primer-commit>
# Prints KEY=value lines to stdout on success: TEST_CMD, RECORDED_COUNT,
# MODE (skip|no-command|no-count|run), RETRIES, OBSERVED, UNPARSEABLE,
# DRIFT, PINNED_COUNT, SPREAD.
#
# Operational failure (jq missing, test-count-rerun.jq missing or from a
# different CONTRACT_VERSION, <project-dir> not inside a git repository,
# PROJECT_CONTEXT.md unreadable) prints one diagnostic line to stderr and
# exits 1 with NO MODE= line on stdout at all.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ_FILTER="$SCRIPT_DIR/test-count-rerun.jq"
DIR="${1:-.}"
LAST_PRIMER_COMMIT="${2:-}"

die() {  # <message>
  printf 'test-count-rerun.sh: %s\n' "$1" >&2
  exit 1
}

[[ -n "$LAST_PRIMER_COMMIT" ]] \
  || die "usage: test-count-rerun.sh <project-dir> <last-primer-commit>"
command -v jq >/dev/null 2>&1 \
  || die "jq is not installed, so the test-count rerun cannot be computed."
[[ -r "$JQ_FILTER" ]] \
  || die "test-count-rerun.jq is missing from $SCRIPT_DIR — the plugin cache is incomplete. Run \`/session-continuity:update\`."
grep -q '^# CONTRACT_VERSION=1$' "$JQ_FILTER" \
  || die "test-count-rerun.jq is from a different plugin version — run \`/session-continuity:update\`."
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "$DIR is not inside a git repository."
CONTEXT_FILE="$DIR/.session-continuity/PROJECT_CONTEXT.md"
[[ -r "$CONTEXT_FILE" ]] \
  || die "$CONTEXT_FILE is not readable."

# --- extract the Test-expectations summary line ----------------------------
# Skip any HTML-comment lines (single- or multi-line <!-- ... -->) so a
# template's own exemplar comment is never mistaken for real content.
SUMMARY_LINE="$(awk '
  /^## Test expectations/ { insec=1; next }
  insec && /^## / { exit }
  insec {
    if ($0 ~ /<!--/) incomment=1
    if (!incomment && $0 !~ /^[[:space:]]*$/) { print; exit }
    if ($0 ~ /-->/) incomment=0
  }
' "$CONTEXT_FILE")"

TEST_CMD=""
if [[ "$SUMMARY_LINE" =~ ^\`([^\`]+)\` ]]; then
  TEST_CMD="${BASH_REMATCH[1]}"
fi

RECORDED_COUNT=""
if [[ -n "$TEST_CMD" ]]; then
  RECORDED_COUNT="$(printf '%s' "$SUMMARY_LINE" | grep -oE '[0-9]+ pass(ed)?' | head -1 | grep -oE '^[0-9]+' || true)"
fi

# --- mode dispatch (labeling only -- the .jq filter's vote logic is the
#     same regardless of which label sh assigns here) ----------------------
if [[ -z "$TEST_CMD" ]]; then
  MODE="no-command"
else
  CHANGED_FILES="$(git -C "$DIR" diff "$LAST_PRIMER_COMMIT"..HEAD --name-only 2>/dev/null || true)"
  SKIP=1
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in .session-continuity/*) ;; *) SKIP=0 ;; esac
  done <<<"$CHANGED_FILES"
  if [[ "$SKIP" -eq 1 ]]; then
    MODE="skip"
  elif [[ -z "$RECORDED_COUNT" ]]; then
    MODE="no-count"
  else
    MODE="run"
  fi
fi

# --- run the command 0-3 times per mode -------------------------------------
# run_once's exit code is deliberately never inspected: "unparseable" is
# defined purely by the absence of a recognizable count in the output,
# not by a nonzero exit or a timeout. A `timeout`-killed run and a
# zero-exit run that simply printed no count both fall through to the
# same "no parseable count" outcome below -- there is exactly one code
# path for both, which is why the smoke test (B6) only needs to exercise
# unparseable *output*, not a separate timeout-specific fixture.
run_once() {  # prints the parsed count, or nothing, on stdout
  local out
  out="$(cd "$DIR" && timeout 120 bash -c "$TEST_CMD" 2>&1)"
  printf '%s' "$out" | grep -oE '[0-9]+ pass(ed)?' | head -1 | grep -oE '^[0-9]+' || true
}

OBSERVED_JSON="[]"
case "$MODE" in
  skip|no-command)
    : # OBSERVED stays empty; the command never runs.
    ;;
  no-count)
    v="$(run_once)"
    OBSERVED_JSON="[$( [[ -n "$v" ]] && echo "$v" || echo null )]"
    ;;
  run)
    v1="$(run_once)"
    if [[ -n "$v1" && "$v1" == "$RECORDED_COUNT" ]]; then
      OBSERVED_JSON="[$v1]"
    else
      v2="$(run_once)"
      v3="$(run_once)"
      to_json() { [[ -n "$1" ]] && echo "$1" || echo null; }
      OBSERVED_JSON="[$(to_json "$v1"),$(to_json "$v2"),$(to_json "$v3")]"
    fi
    ;;
esac

RECORDED_JSON="null"
[[ -n "$RECORDED_COUNT" ]] && RECORDED_JSON="$RECORDED_COUNT"

ERRFILE="$(mktemp)"
RESULT="$(
  jq -r -n \
    --arg test_cmd "$TEST_CMD" \
    --arg mode "$MODE" \
    --argjson recorded "$RECORDED_JSON" \
    --argjson observed "$OBSERVED_JSON" \
    -f "$JQ_FILTER" 2>"$ERRFILE"
)"
JQ_STATUS=$?
DETAIL="$(head -1 "$ERRFILE" 2>/dev/null)"
rm -f "$ERRFILE"

if [[ "$JQ_STATUS" -ne 0 || -z "$RESULT" ]]; then
  die "the vote filter failed: ${DETAIL:-jq exited $JQ_STATUS}"
fi

printf '%s\n' "$RESULT"
