#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/backlog-issues.sh — list/count open GitHub Issues labeled
# `backlog`. Called by render.sh, session-start.sh, and primer-status.sh.
#
# Usage:
#   backlog-issues.sh [--count] <project-dir>
#
# List mode prints one line per open issue:
#   N. #NUMBER Title
# Empty-but-working: "No open backlog issues."
# Operational failure (no git, origin host gh isn't authenticated for,
#   gh missing/fail/timeout): one warning line, exit 0.
#
# Works against github.com or any GitHub Enterprise Server host — the
# check is "does `gh` have auth for this remote's host", not a literal
# "github.com" string match, so it doesn't need to know your GHE hostname.
#
# --count prints an integer, or ? on failure, or 0 when the list is empty.
#
# Environment:
#   GH_BIN                 path to gh (default: gh). Tests inject a mock.
#   BACKLOG_ISSUES_TIMEOUT seconds (default: 3)

set -u

WARN="Backlog unavailable: GitHub Issues required (gh, authenticated for this remote's host). Run /session-continuity:doctor."

count_only=0
if [[ "${1:-}" == "--count" ]]; then
  count_only=1
  shift
fi

fail_open() {
  if [[ "$count_only" -eq 1 ]]; then
    echo '?'
  else
    printf '%s\n' "$WARN"
  fi
  exit 0
}

if [[ $# -eq 0 ]]; then
  DIR="."
else
  DIR="$1"
  [[ -z "$DIR" ]] && fail_open
fi

url="$(git -C "$DIR" remote get-url origin 2>/dev/null || true)"
[[ -z "$url" ]] && fail_open

host="$(printf '%s' "$url" | sed -E 's#^(https?://|git@|ssh://git@)##; s#[:/].*##')"
[[ -z "$host" ]] && fail_open

gh_bin="${GH_BIN:-gh}"
if [[ ! -x "$gh_bin" ]] && ! command -v "$gh_bin" >/dev/null 2>&1; then
  fail_open
fi

"$gh_bin" auth status --hostname "$host" >/dev/null 2>&1 || fail_open

timeout_s="${BACKLOG_ISSUES_TIMEOUT:-3}"
raw="$(
  timeout "$timeout_s" "$gh_bin" issue list \
    --label backlog --state open \
    --json number,title \
    --jq '.[] | "#\(.number)\t\(.title)"' \
    --limit 100 \
    2>/dev/null
)" || fail_open

n=0
lines=""
while IFS= read -r row || [[ -n "$row" ]]; do
  [[ -z "$row" ]] && continue
  num="${row%%$'\t'*}"
  title="${row#*$'\t'}"
  n=$((n + 1))
  if [[ -n "$lines" ]]; then
    lines+=$'\n'
  fi
  lines+="${n}. ${num} ${title}"
done <<< "$raw"

if [[ "$count_only" -eq 1 ]]; then
  echo "$n"
  exit 0
fi

if [[ "$n" -eq 0 ]]; then
  echo "No open backlog issues."
else
  printf '%s\n' "$lines"
fi
exit 0
