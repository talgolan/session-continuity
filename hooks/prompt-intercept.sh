#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/prompt-intercept.sh — UserPromptSubmit hook for the session-continuity
# plugin. Intercepts a fixed, small set of read-only prompts (backlog,
# learnings, help, update — natural language plus their fully plugin-scoped
# slash forms) and answers them directly via hooks/lib/render.sh, at zero
# model calls. See meta/superpowers/plans/2026-09-02-zero-turn-read-only-
# commands.md and meta/superpowers/specs/2026-09-02-zero-turn-read-only-
# commands-design.md.
#
# Usage (from hooks/hooks.json, via perf-wrap.sh): the UserPromptSubmit JSON
# payload arrives on stdin; see the design spec's Measurement 1 for its
# shape. `prompt` is the raw, unexpanded prompt text — the same field for
# both natural language and literal slash-command text. There is no
# `command_name` field on this event (Measurement 2); the matcher never
# looks for one.
#
# A false positive here erases real user work with no transcript entry, so
# every ambiguity resolves to "let the prompt through" — silent exit 0, no
# stdout. Fails open on all of:
#   - jq not on PATH
#   - empty stdin
#   - a payload that is not valid JSON
#   - a payload whose `prompt` field is missing or not a string
#   - a normalized prompt that is not an EXACT match against the fixed
#     table below (never substring/regex — "show the backlog and then fix
#     item 3" must fall through untouched)
#   - hooks/lib/render.sh missing/unreadable, exiting non-zero, or
#     printing nothing
#
# On a match: emits a single JSON object on stdout —
#   {"decision":"block","reason":"<rendered text>",
#    "hookSpecificOutput":{"hookEventName":"UserPromptSubmit",
#                           "suppressOriginalPrompt":true}}
# `suppressOriginalPrompt` MUST be nested under `hookSpecificOutput`, not
# top-level — the top-level placement was directly measured to NOT suppress
# the echoed prompt (design spec, Measurement 4). Built exclusively with
# `jq -n --arg`, never `hooks/lib/gate-common.sh`'s `json_escape` (which
# flattens newlines to spaces via `tr '\000-\037' ' '` and would destroy a
# multi-line reason — the same defect class as the 2026-08-12 hook-JSON
# escaping fix).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENDER_SH="$SCRIPT_DIR/lib/render.sh"

command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD="$(cat)"
[[ -n "$PAYLOAD" ]] || exit 0

# Fixed match table: normalized-prompt -> subcommand name. Exact equality
# only. Slash forms are matched ONLY in the fully plugin-scoped form
# (never a bare `/backlog`) — UserPromptSubmit's payload carries no
# `command_name`, only raw `prompt` text, so a bare-slash entry here would
# risk swallowing another installed plugin's identically-named command
# before it ever runs. That is exactly the false-positive class this hook
# must never produce; a user who types a bare `/backlog` simply falls
# through to the normal (already-working) prompt path, which is not a
# regression.
LOOKUP="$(cat <<'JSONEOF'
{
  "backlog": "backlog",
  "the backlog": "backlog",
  "backlog list": "backlog",
  "show backlog": "backlog",
  "show the backlog": "backlog",
  "show me the backlog": "backlog",
  "list the backlog": "backlog",
  "what's in the backlog": "backlog",
  "/session-continuity:backlog": "backlog",
  "learnings": "learnings",
  "the learnings": "learnings",
  "learnings list": "learnings",
  "show the learnings": "learnings",
  "show me the learnings": "learnings",
  "list the learnings": "learnings",
  "what's in learnings": "learnings",
  "/session-continuity:learnings": "learnings",
  "/session-continuity:help": "help",
  "/session-continuity:update": "update"
}
JSONEOF
)"

# Normalization, applied in this exact order (per the plan): trim, collapse
# internal whitespace runs to one space, lowercase, strip one optional
# trailing "?" or ".", strip a leading "please ". Parsing (.prompt/.cwd) and
# normalization both happen inside jq — a real parser and a real string
# engine, never a hand-rolled regex over raw JSON text, because a user
# prompt can legitimately contain quotes and newlines.
FILTER='
def norm:
  sub("^[ \t\r\n]+"; "")
  | sub("[ \t\r\n]+$"; "")
  | gsub("[ \t\r\n]+"; " ")
  | ascii_downcase
  | sub("[?.]$"; "")
  | sub("^please "; "");

(.prompt // null) as $p
| if ($p | type) != "string" then
    {cmd: null, cwd: ""}
  else
    ($p | norm) as $n
    | ((.cwd // null) as $c | if ($c | type) == "string" then $c else "" end) as $cwd
    | {cmd: ($lookup[$n] // null), cwd: $cwd}
  end
'

RESULT="$(printf '%s' "$PAYLOAD" | jq -c --argjson lookup "$LOOKUP" "$FILTER" 2>/dev/null)"
[[ $? -eq 0 ]] || exit 0
[[ -n "$RESULT" ]] || exit 0

CMD="$(printf '%s' "$RESULT" | jq -r '.cmd // ""' 2>/dev/null)"
[[ $? -eq 0 ]] || exit 0
[[ -n "$CMD" ]] || exit 0

CWD="$(printf '%s' "$RESULT" | jq -r '.cwd // ""' 2>/dev/null)"
[[ $? -eq 0 ]] || exit 0

[[ -r "$RENDER_SH" ]] || exit 0

case "$CMD" in
  backlog|learnings)
    RENDERED="$(bash "$RENDER_SH" "$CMD" "$CWD" 2>/dev/null)"
    ;;
  help|update)
    RENDERED="$(bash "$RENDER_SH" "$CMD" 2>/dev/null)"
    ;;
  *)
    # Not one of the four known subcommands — cannot happen given LOOKUP's
    # fixed value set, but fail open rather than assume.
    exit 0
    ;;
esac
RENDER_STATUS=$?
[[ $RENDER_STATUS -eq 0 ]] || exit 0
[[ -n "$RENDERED" ]] || exit 0

OUT="$(jq -n --arg reason "$RENDERED" '{
  decision: "block",
  reason: $reason,
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    suppressOriginalPrompt: true
  }
}' 2>/dev/null)"
[[ $? -eq 0 ]] || exit 0
[[ -n "$OUT" ]] || exit 0

printf '%s\n' "$OUT"
exit 0
