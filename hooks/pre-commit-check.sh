#!/usr/bin/env bash
# PreToolUse hook for session-continuity. Fires on Bash tool calls.
# If the tool is about to run `git commit` AND docs/SESSION_PRIMER.md
# exists in the user's cwd AND is not staged AND the staged diff
# includes code, emit a non-blocking reminder. Never blocks.

set -eu

# Read stdin JSON payload from Claude Code.
payload="$(cat || true)"

if [ -z "$payload" ]; then
  exit 0
fi

# Extract tool_input.command (first "command": "..." in the payload).
command_value="$(printf '%s' "$payload" \
  | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"(.*)"/\1/')"

if [ -z "$command_value" ]; then
  exit 0
fi

# Only act on `git commit` invocations.
case "$command_value" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# Extract cwd (the directory where Claude's session is running, not
# $CLAUDE_PROJECT_DIR which is typically the plugin root).
cwd="$(printf '%s' "$payload" \
  | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*"cwd"[[:space:]]*:[[:space:]]*"(.*)"/\1/')"

if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
  exit 0
fi

primer="$cwd/docs/SESSION_PRIMER.md"

if [ ! -f "$primer" ]; then
  exit 0
fi

# Is the primer already staged (in the user's repo)?
staged="$(git -C "$cwd" diff --cached --name-only 2>/dev/null || true)"

if printf '%s\n' "$staged" | grep -Fxq "docs/SESSION_PRIMER.md"; then
  exit 0
fi

# Is there any staged file outside docs/, README*, CHANGELOG*, LICENSE*?
code_staged="$(printf '%s\n' "$staged" | grep -Ev '^(docs/|README|CHANGELOG|LICENSE|$)' || true)"

if [ -z "$code_staged" ]; then
  exit 0
fi

# PreToolUse hooks do NOT inject plain stdout as context — they need
# JSON with hookSpecificOutput.additionalContext. SessionStart hooks,
# by contrast, do inject plain stdout. See:
# https://code.claude.com/docs/en/hooks.md
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"⚠️ docs/SESSION_PRIMER.md is not staged for this commit, but code files are. Consider `git add docs/SESSION_PRIMER.md` if outstanding items or landed commits need an update. Skip if the primer is genuinely unaffected by this change."}}
EOF

exit 0
