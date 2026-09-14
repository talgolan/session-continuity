#!/usr/bin/env bash
#
# pre-commit-check.sh — PreToolUse hook for the session-continuity plugin.
#
# Registered in hooks/hooks.json with `matcher: "Bash"` and a per-hook
# `if: "Bash(git commit *)"` filter, so Claude Code only spawns this script
# when the user is about to run `git commit` — NOT on every ls/grep/cat.
#
# What it does: if the user's repo has a session-continuity primer (at
# .session-continuity/SESSION_PRIMER.md) and the user is committing code
# without also staging a primer refresh, nudge Claude to consider staging
# one. The hook never blocks the commit — it only injects a non-blocking
# reminder into Claude's additional context.
#
# Claude Code contract (this is the gotcha that cost us a session — see
# LEARNINGS #1):
#
#   * PreToolUse hooks do NOT treat plain stdout as additional context.
#     Plain stdout goes to debug logs only.
#   * To get a reminder into Claude's context you must emit a JSON object
#     with `hookSpecificOutput.additionalContext` and exit 0 with
#     `permissionDecision: "allow"` to stay non-blocking.
#
# Security notes:
#   * `cwd`/staged-files now come from `gate_load`/`gate_staged_files` in
#     `lib/gate-common.sh` rather than re-deriving them inline. `gate_load`
#     populates `GATE_CWD` from the same stdin `cwd` field this file used to
#     parse by hand; `gate_staged_files` runs `git -C "$GATE_CWD" diff
#     --cached --name-status` (memoized) instead of this file's own `git
#     diff --cached --name-only` call.
#   * `$GATE_CWD` is only used with `[ -d ]`, `[ -f ]`, and `git -C` —
#     all quoted. It is never `eval`ed or interpolated into an executed
#     shell string.
#   * `$command_value` is not used at all in v0.4 — the `if` filter in
#     hooks.json already guarantees we're looking at a `git commit` call,
#     so we don't need to re-check the command string. (Earlier versions
#     did; the filter made that redundant.)
#   * All unexpected inputs cause a silent `exit 0`.

set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

# shellcheck disable=SC2329 # called indirectly from the driver guard below
precommit_check() {
  local cwd="${GATE_CWD:-}" primer_new primer_rel staged code_staged
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0

  primer_new="$cwd/.session-continuity/SESSION_PRIMER.md"
  [ -f "$primer_new" ] || return 0
  primer_rel=".session-continuity/SESSION_PRIMER.md"

  staged="$(gate_staged_files)"
  if printf '%s\n' "$staged" | grep -Fxq "$primer_rel"; then
    return 0
  fi

  code_staged="$(printf '%s\n' "$staged" | grep -Ev '^(docs/|\.session-continuity/|README|CHANGELOG|LICENSE|$)' || true)"
  [ -n "$code_staged" ] || return 0

  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"⚠️ $primer_rel is not staged for this commit, but code files are. Consider \`git add $primer_rel\` after refreshing Mid-flight and Confirm only — do not grow the file. Skip if Mid-flight/Confirm are genuinely unaffected by this change."}}
EOF
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  gate_load
  precommit_check
  exit 0
fi
