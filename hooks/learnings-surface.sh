#!/usr/bin/env bash
#
# learnings-surface.sh — PreToolUse hook (session-continuity plugin).
#
# Fires before Bash / Write / Edit actions. If the user's repo has a
# LEARNINGS.md whose entries carry a `Trigger: <tool> /<regex>/` line, and
# the imminent action matches one, inject a NON-BLOCKING reminder naming the
# entry so the relevant hard-won lesson surfaces BEFORE the action runs —
# not only after a symptom makes it greppable.
#
# Output contract (see LEARNINGS #1): PreToolUse hooks must emit a JSON
# object with hookSpecificOutput.additionalContext to reach Claude's context;
# plain stdout goes to debug logs only. permissionDecision:"allow" keeps this
# non-blocking — it surfaces, it never vetoes.
#
# Security: $cwd is only used in [ -f ] tests and as a grep file arg, never
# eval'd. Trigger regexes come from the repo's own LEARNINGS.md (same trust
# level as the code being committed). Any unexpected input -> silent exit 0.

set -euo pipefail

payload="$(cat || true)"
[ -z "${payload:-}" ] && exit 0

cwd="$(printf '%s' "$payload" \
  | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*"cwd"[[:space:]]*:[[:space:]]*"(.*)"/\1/' \
  || true)"
[ -z "${cwd:-}" ] && exit 0
[ ! -d "$cwd" ] && exit 0

learnings="$cwd/.session-continuity/LEARNINGS.md"
[ -f "$learnings" ] || learnings="$cwd/docs/LEARNINGS.md"
[ -f "$learnings" ] || exit 0

tool="$(printf '%s' "$payload" \
  | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' \
  || true)"
[ -z "${tool:-}" ] && exit 0

# Match-text is the full raw payload. The action's command/content/path are
# all inside it, JSON-escaped. Matching against the whole payload keeps the
# parser trivial and robust to multiline content; the only cost is that a
# trigger regex could in principle match a different field. Acceptable: this
# hook is advisory (allow-only), and triggers are authored to be specific.
match_text="$payload"

# Walk LEARNINGS for `### N. Title` headings each optionally followed by a
# `Trigger: <tool> /<regex>/` line. awk emits, per entry that has a trigger:
#   <num>\t<tool>\t<regex>\t<title>
entries="$(awk '
  /^### [0-9]+\./ {
    num=$2; sub(/\./,"",num);
    title=$0; sub(/^### [0-9]+\.[[:space:]]*/,"",title);
    next;
  }
  /^Trigger:[[:space:]]/ {
    line=$0; sub(/^Trigger:[[:space:]]*/,"",line);
    # line = "<tool> /<regex>/"
    ttool=line; sub(/[[:space:]].*$/,"",ttool);
    tre=line; sub(/^[^[:space:]]+[[:space:]]*/,"",tre);
    sub(/^\//,"",tre); sub(/\/[[:space:]]*$/,"",tre);
    if (num != "" && tre != "") {
      printf "%s\t%s\t%s\t%s\n", num, ttool, tre, title;
    }
    next;
  }
' "$learnings" 2>/dev/null || true)"

[ -z "${entries:-}" ] && exit 0

hits=""
while IFS=$'\t' read -r num ttool tre title; do
  [ -z "$num" ] && continue
  # tool gate: "*" matches any; else must equal the action tool
  if [ "$ttool" != "*" ] && [ "$ttool" != "$tool" ]; then
    continue
  fi
  if printf '%s' "$match_text" | grep -Eq -- "$tre" 2>/dev/null; then
    # JSON-escape the title (minimal: backslash + quote)
    safe_title="$(printf '%s' "$title" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    hits="${hits}#${num} (${safe_title}); "
  fi
done <<< "$entries"

[ -z "${hits:-}" ] && exit 0

msg="⚠️ Known LEARNINGS may apply to this action before you run it: ${hits}Read the full entry in LEARNINGS.md before proceeding."
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"%s"}}\n' "$msg"
exit 0
