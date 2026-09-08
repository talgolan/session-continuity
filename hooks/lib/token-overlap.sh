#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/token-overlap.sh — commit-subject / backlog-issue-title token
# overlap gate. Replaces the two hand-computed prose copies that used to
# live in commands/end-session.md (the "Overlap gate" and the refresh
# flow's "backlog overlay") with one deterministic computation, run once.
#
# Usage: token-overlap.sh <issues-file> <commits-file>
#   <issues-file>  — raw backlog-issues.sh list output, one issue per line:
#                    "N. #NUMBER Title text"
#   <commits-file> — raw `git log --oneline <range>` output, one commit per
#                    line: "<abbrev-hash> subject text"
#
# Prints TSV to stdout, one line per (issue, commit) pair whose tokenized
# titles share >=3 tokens after dropping short tokens and stopwords:
#   #NUMBER<TAB>commit subject
# Zero matches is a normal, silent outcome (empty stdout, exit 0) — the
# caller treats "no line for this issue" / "no line for this subject" as
# "no match," not as an error.
#
# Operational failure (jq missing, filter missing/wrong version, a missing
# input file) prints one diagnostic line to stderr and exits 1. Callers
# that don't check the exit code still degrade safely: empty stdout reads
# as zero matches either way, which is the conservative direction for both
# call sites (skip-with-manual-verdict, or no overlay suggestion).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ_FILTER="$SCRIPT_DIR/token-overlap.jq"
ISSUES_FILE="${1:-}"
COMMITS_FILE="${2:-}"

die() {
  printf 'token-overlap.sh: %s\n' "$1" >&2
  exit 1
}

[[ -n "$ISSUES_FILE" && -n "$COMMITS_FILE" ]] \
  || die "usage: token-overlap.sh <issues-file> <commits-file>"
[[ -r "$ISSUES_FILE" ]] || die "issues file is not readable: $ISSUES_FILE"
[[ -r "$COMMITS_FILE" ]] || die "commits file is not readable: $COMMITS_FILE"
command -v jq >/dev/null 2>&1 \
  || die "jq is not installed, so the overlap gate cannot run."
[[ -r "$JQ_FILTER" ]] \
  || die "token-overlap.jq is missing from $SCRIPT_DIR — the plugin cache is incomplete. Run \`/session-continuity:update\`."
grep -q '^# CONTRACT_VERSION=1$' "$JQ_FILTER" \
  || die "token-overlap.jq is from a different plugin version — run \`/session-continuity:update\`."

ISSUES_RAW="$(cat "$ISSUES_FILE")"
COMMITS_RAW="$(cat "$COMMITS_FILE")"

jq -r -n --arg issues_raw "$ISSUES_RAW" --arg commits_raw "$COMMITS_RAW" -f "$JQ_FILTER" \
  || die "the overlap filter failed."
