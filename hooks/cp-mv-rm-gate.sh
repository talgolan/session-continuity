#!/usr/bin/env bash
# hooks/cp-mv-rm-gate.sh — Family B blocking gate (session-continuity plugin,
# #73 remediation 2, engrim decision #43).
#
# Fires on every Bash call (matcher "Bash", no `if` filter). Denies any
# command segment (split on ; && || |) whose first word is a bare cp, mv, or
# rm — the shape that silently hangs when the user's shell has
# `alias cp='cp -i'` (etc.) and the Bash tool's non-interactive stdin can
# never answer the overwrite prompt. `\cp`/`command cp` bypass the alias and
# are always allowed through.
#
# Escape hatch: SESSION_CONTINUITY_SKIP_CP_MV_RM_GATE=1 in the hook's own
# process environment allows the command through unconditionally — for the
# false-positive class where the splitter's quote-unawareness misdetects a
# bare cp/mv/rm sitting inside a quoted string literal (e.g. `echo "a | rm
# b"`), which the user cannot fix with `\rm`/`command rm` since that text
# belongs to someone else's string. Same naming convention as
# dirty-tree-gate.sh's SESSION_CONTINUITY_SKIP_DIRTY_GATE.
#
# Known limitation: does not detect the covered forms when hidden inside a
# subshell `(...)`, `{ ...; }` grouping, `eval`, or `bash -c` — this is a
# best-effort net on top-level commands, not a hardened boundary.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

# shellcheck disable=SC2329 # called indirectly by the driver guard below
cmrg_offending_segment() {  # <command> -> first bare cp/mv/rm segment, or empty
  local cmd="$1" seg first
  # Deliberately do NOT collapse newlines to spaces before splitting: a real
  # newline is a statement separator too (Claude's Bash tool_input is
  # routinely multi-line), and `while read` already breaks on it. Collapsing
  # first would merge "rm -rf x" sitting on its own line into the tail of
  # the previous line's segment and miss it — verified via repro during
  # plan review (meta/superpowers/plans/2026-09-14-hooks-sprawl-remediation.md
  # Task 5 caveman-review pass).
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$seg" ] || continue
    case "$seg" in
      '\'*) continue ;;
      'command '*) continue ;;
    esac
    first="${seg%%[[:space:]]*}"
    case "$first" in
      cp|mv|rm) printf '%s' "$seg"; return 0 ;;
    esac
  done <<EOF
$(printf '%s' "$cmd" | sed -E 's/(&&|\|\||;|\|)/\n/g')
EOF
  return 1
}

cmrg_deny() {  # <segment>
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(json_escape "Bare command hangs if this shell has an interactive -i alias for cp/mv/rm and cannot be answered non-interactively: \`$1\`. Bypass the alias: \`\\$1\` or \`command $1\`. If this is a false positive (e.g. quoted text, not a real invocation), set SESSION_CONTINUITY_SKIP_CP_MV_RM_GATE=1.")"
  exit 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  gate_load
  [ "${GATE_TOOL:-}" = "Bash" ] || exit 0
  [ "${SESSION_CONTINUITY_SKIP_CP_MV_RM_GATE:-}" != "1" ] || exit 0
  offender="$(cmrg_offending_segment "${GATE_COMMAND:-}")" || exit 0
  cmrg_deny "$offender"
fi
