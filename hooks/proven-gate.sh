#!/usr/bin/env bash
#
# proven-gate.sh — PreToolUse hook (session-continuity plugin).
#
# Fires before Write / Edit. Self-scopes to spec/plan files (path under a
# */specs/ or */plans/ dir, *.md). BLOCKS the write when the content makes a
# "proven"-class claim (proven | verified | spike conclusive, matched on word
# boundaries) but does NOT also carry both fields:
#
#   Real path: <which production code path actually ran>
#   Stubbed:   <what stood in — or "nothing">
#
# Rationale: a forward "proven" claim is only meaningful if it names the real
# path exercised and what was stubbed. The Stubbed: field forces a stand-in
# into the open. See meta/superpowers/specs/2026-06-17-proven-gate-design.md
# and the project-change-the-odds workstream.
#
# Escape hatch (explicit skip-with-reason): a line matching
#   Proven-gate: N/A — <reason>   (em-dash or --, non-empty reason)
# passes the gate unconditionally (quoting, glossary, a spec about the gate).
#
# Output contract (LEARNINGS #1): permissionDecision:"deny" blocks and shows
# the reason. Silent exit 0 allows. PreToolUse does NOT inject plain stdout.
#
# Self-reference (LEARNINGS #7): verify ONLY via the hermetic fixture runner,
# never by self-scanning a real spec/plan. The loose hatch is intentional.
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

# Self-scope: only spec/plan markdown. */specs/*.md OR */plans/*.md
base="${file_path##*/}"
case "$file_path" in
  */specs/*|*/plans/*) : ;;
  *) exit 0 ;;
esac
case "$base" in *.md) : ;; *) exit 0 ;; esac

# Pull the written content. Write -> content; Edit -> new_string. Extract
# everything after the key's opening quote to end of payload, then un-escape
# \n \t \" \\ so line-oriented greps work. Bounded best-effort decode; the
# gate errs toward blocking and the escape hatch is the override, so an
# imperfect decode is safe.
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
if printf '%s' "$content" | grep -Eiq 'Proven-gate:[[:space:]]*N/A[[:space:]]*(—|--)[[:space:]]*[^[:space:]]'; then
  exit 0
fi

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Claim-word detection — WORD BOUNDARIES (deviation from smoke-gate substring).
# "proven"/"verified" as whole words; "spike conclusive" as a phrase.
has_claim=0
if printf '%s' "$content" | grep -Eiqw 'proven|verified'; then has_claim=1; fi
if printf '%s' "$content" | grep -Eiq 'spike[[:space:]]+conclusive'; then has_claim=1; fi
[ "$has_claim" -eq 0 ] && exit 0

# Require BOTH fields (label case-insensitive, non-empty value after colon).
has_real=0; has_stub=0
if printf '%s' "$content" | grep -Eiq 'Real path:[[:space:]]*[^[:space:]]'; then has_real=1; fi
if printf '%s' "$content" | grep -Eiq 'Stubbed:[[:space:]]*[^[:space:]]'; then has_stub=1; fi

if [ "$has_real" -eq 0 ] || [ "$has_stub" -eq 0 ]; then
  deny "This spec/plan makes a 'proven/verified/spike conclusive' claim but does not name what was actually tested. Add both fields next to the claim — 'Real path: <which production code path ran>' and 'Stubbed: <what stood in, or \"nothing\">'. If the stubbed thing is the feature under test, the claim is not proven. Or add a line: Proven-gate: N/A — <reason> for a non-claim use (quoting, glossary, a doc about the gate)."
fi

exit 0
