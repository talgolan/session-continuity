#!/usr/bin/env bash
#
# occurrence-gate.sh — PreToolUse hook (session-continuity plugin).
#
# Fires before Write / Edit. Self-scopes to a LEARNINGS.md under a
# .session-continuity/ or docs/ path. BLOCKS the write when the content records
# the 2nd-or-later occurrence of a mistake-class —
#
#   Occurrence count: N of M     (N >= 2)
#
# — but does NOT also carry a non-empty end-state invariant —
#
#   Invariant: <what must hold on EVERY path, enforced at the reconciler/gate>
#
# Rationale (CLAUDE.md rule 4 / change-the-odds #2): a class fixed across 2+
# attempts must name its end-state invariant, not ship another trigger-patch.
# Noticing the recurrence is the step that fails unaided — so a gate enforces it.
# See meta/superpowers/specs/2026-06-17-occurrence-counter-and-spike-check-design.md.
#
# Escape hatch (explicit skip-with-reason): a line matching
#   Occurrence-gate: N/A — <reason>   (em-dash or --, non-empty reason)
# passes the gate unconditionally (quoting another entry, glossary, a spec about
# the gate).
#
# Output contract (LEARNINGS #1): permissionDecision:"deny" blocks and shows the
# reason. Silent exit 0 allows. PreToolUse does NOT inject plain stdout.
#
# Self-reference (LEARNINGS #7): verify ONLY via the hermetic fixture runner,
# never by self-scanning a real LEARNINGS.md. The loose hatch is intentional.
#
# Security: $file_path / $content used only in path tests + grep; never eval'd.

set -euo pipefail

payload="$(cat || true)"
[ -z "${payload:-}" ] && exit 0

file_path="$(printf '%s' "$payload" \
  | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' \
  || true)"
[ -z "${file_path:-}" ] && exit 0

# Self-scope: basename LEARNINGS.md AND under a .session-continuity/ or docs/ dir.
base="${file_path##*/}"
[ "$base" = "LEARNINGS.md" ] || exit 0
case "$file_path" in
  */.session-continuity/*|*/docs/*) : ;;
  *) exit 0 ;;
esac

# Decode written content. Write -> content; Edit -> new_string. Same bounded
# best-effort decode as proven-gate.sh; the gate errs toward blocking and the
# escape hatch is the override, so an imperfect decode is safe.
raw="$(printf '%s' "$payload" \
  | sed -nE 's/.*"content"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
  | head -1)"
[ -z "$raw" ] && raw="$(printf '%s' "$payload" \
  | sed -nE 's/.*"new_string"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
  | head -1)"
[ -z "$raw" ] && exit 0

content="$(printf '%s' "$raw" \
  | sed -E 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g; s/\\\\/\\/g')"

# Escape hatch first.
if printf '%s' "$content" | grep -Eiq 'Occurrence-gate:[[:space:]]*N/A[[:space:]]*(—|--)[[:space:]]*[^[:space:]]'; then
  exit 0
fi

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Occurrence trigger: largest N in any "Occurrence count: N of M" line. No match
# or N < 2 -> silent allow.
max_n=0
while IFS= read -r n; do
  [ -z "$n" ] && continue
  if [ "$n" -gt "$max_n" ] 2>/dev/null; then max_n="$n"; fi
done <<EOF
$(printf '%s' "$content" \
  | grep -oiE 'Occurrence count:[[:space:]]*[0-9]+[[:space:]]+of[[:space:]]+[0-9]+' \
  | grep -oiE '[0-9]+[[:space:]]+of' \
  | grep -oE '^[0-9]+')
EOF

[ "$max_n" -ge 2 ] || exit 0

# Require a non-empty Invariant: line. Call deny() from inside the conditional
# (mirrors proven-gate.sh) so the trailing exit 0 stays reachable / shellcheck-clean.
has_inv=0
if printf '%s' "$content" | grep -Eiq 'Invariant:[[:space:]]*[^[:space:]]'; then has_inv=1; fi

if [ "$has_inv" -eq 0 ]; then
  deny "This LEARNINGS entry records occurrence #${max_n} of a mistake-class but does not name an end-state invariant. CLAUDE.md rule 4: a class fixed across 2+ attempts needs an 'Invariant: <what must hold on EVERY path, enforced at the reconciler/entry gate>' line — not another trigger-patch. Add it next to the 'Occurrence count:' line. Or add: Occurrence-gate: N/A — <reason> for a non-escalation use (quoting, glossary, a doc about the gate)."
fi

exit 0
