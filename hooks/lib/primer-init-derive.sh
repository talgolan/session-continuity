#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/primer-init-derive.sh — placeholder derivation for
# /session-continuity:primer Step 2 (Init mode). See
# meta/superpowers/specs/2026-09-09-primer-init-derive-design.md for the
# full contract this implements and
# meta/superpowers/plans/2026-09-09-primer-init-derive.md for the
# implementation plan.
#
# Usage: TEST_CMD=<cmd> TEST_OUTPUT=<captured output> primer-init-derive.sh <project-dir>
# TEST_CMD/TEST_OUTPUT are read from the environment, not discovered or
# executed here -- commands/primer.md's Step 2 Bash block already discovers
# and runs the test command once and exports both before calling this
# script. Unset/empty is treated as "no test command" (TEST_COMMAND_SUMMARY
# becomes TBD) -- this script never re-runs a test command itself.
#
# Prints KEY=value lines to stdout on success: PROJECT_NAME,
# WORKING_DIRECTORY_ABSOLUTE_PATH, COMMIT_COUNT, LATEST_COMMIT_HASH_1..5,
# LATEST_COMMIT_SUBJECT_1..5, TEST_CMD, TEST_COMMAND_SUMMARY.
#
# Operational failure (jq missing, primer-init-derive.jq missing or from a
# different CONTRACT_VERSION, <project-dir> not a readable directory) prints
# one diagnostic line to stderr and exits 1 with NO PROJECT_NAME= line on
# stdout at all.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ_FILTER="$SCRIPT_DIR/primer-init-derive.jq"
DIR="${1:-.}"

die() {  # <message>
  printf 'primer-init-derive.sh: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 \
  || die "jq is not installed, so placeholder derivation cannot run."
[[ -r "$JQ_FILTER" ]] \
  || die "primer-init-derive.jq is missing from $SCRIPT_DIR — the plugin cache is incomplete. Run \`/session-continuity:update\`."
grep -q '^# CONTRACT_VERSION=1$' "$JQ_FILTER" \
  || die "primer-init-derive.jq is from a different plugin version — run \`/session-continuity:update\`."
[[ -d "$DIR" ]] \
  || die "$DIR is not a directory."

cd "$DIR" || die "cannot cd into $DIR."

PKG_NAME=""
[[ -f package.json ]] && PKG_NAME="$(grep -m1 '"name"' package.json | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
CARGO_NAME=""
[[ -f Cargo.toml ]] && CARGO_NAME="$(grep -m1 '^name' Cargo.toml | sed -E 's/^name[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')"
PYPROJECT_NAME=""
[[ -f pyproject.toml ]] && PYPROJECT_NAME="$(grep -m1 '^name' pyproject.toml | sed -E 's/^name[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')"
DIRNAME="$(basename "$(pwd)")"

GIT_LOG=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_LOG="$(git log --oneline -5 2>/dev/null || true)"
fi

# TEST_CMD/TEST_OUTPUT are supplied by the caller's environment -- see the
# usage note above. Never discovered or executed here.
TEST_CMD="${TEST_CMD:-}"
TEST_OUTPUT="${TEST_OUTPUT:-}"

PWD_ABS="$(pwd)"

ERRFILE="$(mktemp)"
RESULT="$(
  jq -r -n \
    --arg pkg_name "$PKG_NAME" \
    --arg cargo_name "$CARGO_NAME" \
    --arg pyproject_name "$PYPROJECT_NAME" \
    --arg dirname "$DIRNAME" \
    --arg pwd "$PWD_ABS" \
    --arg git_log "$GIT_LOG" \
    --arg test_cmd "$TEST_CMD" \
    --arg test_output "$TEST_OUTPUT" \
    -f "$JQ_FILTER" 2>"$ERRFILE"
)"
JQ_STATUS=$?
DETAIL="$(head -1 "$ERRFILE" 2>/dev/null)"
rm -f "$ERRFILE"

if [[ "$JQ_STATUS" -ne 0 || -z "$RESULT" ]]; then
  die "the derivation filter failed: ${DETAIL:-jq exited $JQ_STATUS}"
fi

printf '%s\n' "$RESULT"
