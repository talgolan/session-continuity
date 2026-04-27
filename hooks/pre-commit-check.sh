#!/usr/bin/env bash
# PreToolUse hook for session-continuity. Fires on Bash tool calls.
# If the tool is about to run `git commit` AND docs/SESSION_PRIMER.md
# exists AND is not staged AND the staged diff includes code, emit a
# non-blocking reminder. Never blocks.

set -eu

# CLAUDE_TOOL_INPUT is a JSON blob describing the tool call. Extract
# the command field with a cheap grep rather than requiring jq.
command_field="$(printf '%s' "${CLAUDE_TOOL_INPUT:-}" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 || true)"

if [ -z "$command_field" ]; then
  exit 0
fi

# Extract the quoted value of the command.
command_value="$(printf '%s' "$command_field" | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"(.*)"/\1/')"

# Only act on `git commit` invocations.
case "$command_value" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

primer="docs/SESSION_PRIMER.md"

if [ ! -f "$primer" ]; then
  exit 0
fi

# Is the primer already staged?
if git diff --cached --name-only 2>/dev/null | grep -Fxq "$primer"; then
  exit 0
fi

# Is there any staged file outside docs/, README*, CHANGELOG*, LICENSE*?
code_staged="$(git diff --cached --name-only 2>/dev/null \
  | grep -Ev '^(docs/|README|CHANGELOG|LICENSE)' || true)"

if [ -z "$code_staged" ]; then
  exit 0
fi

cat <<'EOF'
<system-reminder>
⚠️ docs/SESSION_PRIMER.md is not staged for this commit, but code files are. Consider `git add docs/SESSION_PRIMER.md` if outstanding items or landed commits need an update. Skip if the primer is genuinely unaffected by this change.
</system-reminder>
EOF

exit 0
