#!/usr/bin/env bash
#
# pre-commit-check.sh — PreToolUse hook for the session-continuity plugin.
#
# Registered in hooks/hooks.json with `matcher: "Bash"` and a per-hook
# `if: "Bash(git commit *)"` filter, so Claude Code only spawns this script
# when the user is about to run `git commit` — NOT on every ls/grep/cat.
#
# What it does: if the user's repo has docs/SESSION_PRIMER.md and the user
# is committing code without also staging a primer refresh, nudge Claude to
# consider staging one. The hook never blocks the commit — it only injects
# a non-blocking reminder into Claude's additional context.
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
#   * `$cwd` is only used with `[ -d ]`, `[ -f ]`, and `git -C "$cwd"` —
#     all quoted. It is never `eval`ed or interpolated into an executed
#     shell string.
#   * `$command_value` is not used at all in v0.4 — the `if` filter in
#     hooks.json already guarantees we're looking at a `git commit` call,
#     so we don't need to re-check the command string. (Earlier versions
#     did; the filter made that redundant.)
#   * All unexpected inputs cause a silent `exit 0`.

set -euo pipefail

# Read the JSON payload Claude Code delivers on stdin. `|| true` guards
# against an empty-stdin test scenario.
payload="$(cat || true)"

if [ -z "${payload:-}" ]; then
  exit 0
fi

# Extract the cwd Claude is running in. NOTE: this is deliberately NOT
# $CLAUDE_PROJECT_DIR — for plugin installs that env var usually points at
# the plugin's own directory, not at the user's repo where the commit is
# about to happen. The stdin payload's `cwd` field is the canonical source
# for the user's repo directory.
cwd="$(printf '%s' "$payload" \
  | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*"cwd"[[:space:]]*:[[:space:]]*"(.*)"/\1/' \
  || true)"

if [ -z "${cwd:-}" ] || [ ! -d "$cwd" ]; then
  exit 0
fi

primer="$cwd/docs/SESSION_PRIMER.md"

# Nothing to remind about if the project doesn't use session-continuity.
if [ ! -f "$primer" ]; then
  exit 0
fi

# Ask git what's staged. `-C "$cwd"` is safe — git treats that flag as a
# path, not a shell string. Any non-zero exit (not a git repo, corrupt
# index, etc.) falls through to an empty `$staged`, which then causes a
# silent early-exit below.
staged="$(git -C "$cwd" diff --cached --name-only 2>/dev/null || true)"

# If the primer is already staged, nothing to remind about — the commit
# will carry its refresh.
if printf '%s\n' "$staged" | grep -Fxq "docs/SESSION_PRIMER.md"; then
  exit 0
fi

# Consider only "code" changes as worth reminding about. A commit whose
# staged set is entirely docs/, README*, CHANGELOG*, LICENSE*, or (empty
# line from grep's \n handling) probably doesn't change the primer's
# reality — the user is already dealing with the docs layer.
code_staged="$(printf '%s\n' "$staged" | grep -Ev '^(docs/|README|CHANGELOG|LICENSE|$)' || true)"

if [ -z "$code_staged" ]; then
  exit 0
fi

# Emit the reminder as JSON. permissionDecision:"allow" keeps this
# non-blocking; additionalContext is what Claude will actually see.
# Docs: https://code.claude.com/docs/en/hooks.md#decision-control-with-json-output
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"⚠️ docs/SESSION_PRIMER.md is not staged for this commit, but code files are. Consider `git add docs/SESSION_PRIMER.md` if outstanding items or landed commits need an update. Skip if the primer is genuinely unaffected by this change."}}
EOF

exit 0
