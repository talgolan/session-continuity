#!/usr/bin/env bash
# hooks/dirty-tree-gate.sh — Family B blocking gate (session-continuity
# plugin, #73 remediation 1).
#
# Fires on every Bash call (matcher "Bash", no `if` filter — deliberately not
# scoped to `Bash(git commit *)`; this has nothing to do with commits). Denies
# `git reset --hard`, `git checkout -- <path>`/`.`, or `git restore <path>`/`.`
# when the target repo's working tree already has uncommitted changes to
# lose. Driving incident: architect-workbench #122 — an advisory-only
# LEARNINGS reminder missed a `git reset --hard` that wiped uncommitted work
# under pressure; this is the blocking version of that reminder.
#
# Escape hatch: SESSION_CONTINUITY_SKIP_DIRTY_GATE=1 in the hook's own
# process environment allows the command through regardless of dirty state —
# for the rare case where discarding is genuinely intended. Same naming
# convention as the existing SESSION_CONTINUITY_SKIP_UPDATE_CHECK.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

# shellcheck disable=SC2329 # called indirectly by the driver guard below
dtg_is_destructive() {  # <command> -> 0 iff some SEGMENT is itself a discard-form git op
  # Anchored to the start of each ; && || | / newline-delimited segment, not
  # a substring search over the whole command — a substring search would
  # misfire on `git commit -m "docs: explain git reset --hard"`, matching
  # inside the quoted commit message rather than an actually-invoked
  # subcommand. Same segment-splitting shape as cp-mv-rm-gate.sh's
  # cmrg_offending_segment (real newlines stay real separators; see that
  # gate's comment for why collapsing them first is wrong).
  local cmd="$1" seg
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$seg" ] || continue
    printf '%s' "$seg" | LC_ALL=C grep -Eq '^git[[:space:]]+reset[[:space:]]+.*--hard\b' && return 0
    printf '%s' "$seg" | LC_ALL=C grep -Eq '^git[[:space:]]+checkout([[:space:]]+(--([[:space:]]|$)|\.([[:space:]]|$))|[[:space:]]+[^-].*[[:space:]]--([[:space:]]|$))' && return 0
    if printf '%s' "$seg" | LC_ALL=C grep -Eq '^git[[:space:]]+restore\b'; then
      if printf '%s' "$seg" | LC_ALL=C grep -Eq -- '--staged\b'; then
        printf '%s' "$seg" | LC_ALL=C grep -Eq -- '--worktree\b' && return 0
        continue
      fi
      return 0
    fi
  done <<EOF
$(printf '%s' "$cmd" | sed -E 's/(&&|\|\||;|\|)/\n/g')
EOF
  return 1
}

dtg_deny() {  # <command>
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(json_escape "Working tree has uncommitted changes and this command discards them: \`$1\`. Stash (git stash -u) or commit first, or set SESSION_CONTINUITY_SKIP_DIRTY_GATE=1 if discarding is genuinely intended.")"
  exit 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  gate_load
  [ "${GATE_TOOL:-}" = "Bash" ] || exit 0
  [ "${SESSION_CONTINUITY_SKIP_DIRTY_GATE:-}" != "1" ] || exit 0
  dtg_is_destructive "${GATE_COMMAND:-}" || exit 0
  [ -n "${GATE_CWD:-}" ] && [ -d "${GATE_CWD:-}" ] || exit 0
  [ -n "$(git -C "$GATE_CWD" status --porcelain 2>/dev/null || true)" ] || exit 0
  dtg_deny "${GATE_COMMAND:-}"
fi
