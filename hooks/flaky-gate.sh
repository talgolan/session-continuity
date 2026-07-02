#!/usr/bin/env bash
#
# flaky-gate.sh — PreToolUse hook (session-continuity plugin).
#
# Fires before Bash(git commit *) and before Write / Edit. Handles two
# input shapes:
#
#   (1) Bash: extracts the git commit message text from tool_input.command.
#   (2) Write/Edit: self-scopes to LEARNINGS.md under a .session-continuity/
#       or docs/ path (same scope as occurrence-gate.sh), extracts the
#       written content.
#
# In both cases, BLOCKS when the text calls a failure "flaky" / "transient"
# / "CDN blip" / "CDN flake" without also naming the mechanism behind it —
#
#   Mechanism: <named deterministic cause: race, shared/global state, an
#               environment or sandbox dependency, etc.>
#
# Rationale (CLAUDE.md rule 1 / feedback_never_guess_preserve_evidence): "an
# intermittent failure has a deterministic cause... never label a failure
# 'flaky' and move on." A 2nd identical failure is diagnosed from artifacts,
# never re-run and shrugged off as transient.
#
# Escape hatch (explicit skip-with-reason): a line matching
#   Flaky-gate: N/A — <reason>   (em-dash or --, non-empty reason)
# passes the gate unconditionally (quoting another entry, a glossary, a spec
# about the gate).
#
# Output contract (LEARNINGS #1): permissionDecision:"deny" blocks and shows
# the reason. Silent exit 0 allows. PreToolUse does NOT inject plain stdout.
#
# Self-reference (LEARNINGS #7): verify ONLY via the hermetic fixture runner,
# never by self-scanning real commits/LEARNINGS. The loose hatch is
# intentional.
#
# Security: $file_path / $content / $command used only in path tests + grep;
# never eval'd.

set -euo pipefail

payload="$(cat || true)"
[ -z "${payload:-}" ] && exit 0

tool="$(printf '%s' "$payload" \
  | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' \
  || true)"

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

check_text() {
  local text="$1"
  [ -z "$text" ] && return 0

  # Escape hatch first.
  if printf '%s' "$text" | grep -Eiq 'Flaky-gate:[[:space:]]*N/A[[:space:]]*(—|--)[[:space:]]*[^[:space:]]'; then
    return 0
  fi

  printf '%s' "$text" | grep -Eiq '\b(flaky|transient)\b|CDN[[:space:]]+(blip|flake)' || return 0

  if ! printf '%s' "$text" | grep -Eiq 'Mechanism:[[:space:]]*[^[:space:]]'; then
    deny "This calls a failure 'flaky'/'transient'/a 'CDN blip' without naming the deterministic cause behind it. CLAUDE.md rule 1: an intermittent failure has a deterministic cause (a race, shared/global state, an environment or sandbox dependency) — name it or state the precise fail condition, never label it flaky and move on. Add a 'Mechanism: <named cause>' line, or add: Flaky-gate: N/A — <reason> for a non-diagnostic use (quoting, glossary, a doc about the gate)."
  fi
}

case "$tool" in
  Bash)
    command="$(printf '%s' "$payload" \
      | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
      | head -1 \
      | sed -E 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g; s/\\\\/\\/g')"
    [ -z "${command:-}" ] && exit 0
    # Only in scope for a git commit invocation — anything else is noise.
    printf '%s' "$command" | grep -Eq 'git[[:space:]]+commit' || exit 0
    check_text "$command"
    ;;
  Write|Edit)
    file_path="$(printf '%s' "$payload" \
      | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -1 \
      | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' \
      || true)"
    [ -z "${file_path:-}" ] && exit 0
    base="${file_path##*/}"
    [ "$base" = "LEARNINGS.md" ] || exit 0
    case "$file_path" in
      */.session-continuity/*|*/docs/*) : ;;
      *) exit 0 ;;
    esac
    raw="$(printf '%s' "$payload" \
      | sed -nE 's/.*"content"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
      | head -1)"
    [ -z "$raw" ] && raw="$(printf '%s' "$payload" \
      | sed -nE 's/.*"new_string"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
      | head -1)"
    [ -z "$raw" ] && exit 0
    content="$(printf '%s' "$raw" \
      | sed -E 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g; s/\\\\/\\/g')"
    check_text "$content"
    ;;
  *)
    exit 0
    ;;
esac

exit 0
