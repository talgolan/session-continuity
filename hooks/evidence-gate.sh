#!/usr/bin/env bash
#
# evidence-gate.sh — PreToolUse hook (session-continuity plugin).
#
# Fires before Write / Edit. Self-scopes to spec/plan files (path under a
# */specs/ or */plans/ dir, *.md). BLOCKS the write when the smoke-design
# prose in a spec/plan describes a failure-destroying or single-signal
# pattern without the corresponding safeguard:
#
#   (A) mentions teardown/cleanup on a smoke SUT but never says the failure
#       diagnostic is captured/preserved BEFORE that teardown runs.
#   (B) mentions a poll/wait loop but never says it watches both a success
#       AND a failure signal (vs. success-only, which burns the full
#       timeout on every failure and can't tell "slow" from "broken").
#
# Rationale: "never guess; preserve evidence" (feedback_never_guess_preserve_
# evidence) — a smoke section that tears down on failure or polls
# success-only destroys the evidence needed to diagnose without guessing.
# Noticing the gap while authoring is the step that fails unaided.
#
# Escape hatch (explicit skip-with-reason): a line matching
#   Evidence-gate: N/A — <reason>   (em-dash or --, non-empty reason)
# passes the gate unconditionally.
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

# Pull the written content. Write -> content; Edit -> new_string. Bounded
# best-effort decode (same as proven-gate.sh) — the gate errs toward
# blocking and the escape hatch is the override, so an imperfect decode is
# safe.
raw="$(printf '%s' "$payload" \
  | sed -nE 's/.*"content"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
  | head -1)"
[ -z "$raw" ] && raw="$(printf '%s' "$payload" \
  | sed -nE 's/.*"new_string"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
  | head -1)"
[ -z "$raw" ] && exit 0

content="$(printf '%s' "$raw" \
  | sed -E 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g; s/\\\\/\\/g')"

# Only in scope when the plan is actually discussing a smoke section. A
# spec/plan that never mentions smoke has nothing for this gate to check.
printf '%s' "$content" | grep -Eiq 'smoke' || exit 0

# Escape hatch first.
if printf '%s' "$content" | grep -Eiq 'Evidence-gate:[[:space:]]*N/A[[:space:]]*(—|--)[[:space:]]*[^[:space:]]'; then
  exit 0
fi

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# (A) teardown/cleanup mentioned without an adjacent preserve-before-teardown
# safeguard.
if printf '%s' "$content" | grep -Eiq 'teardown|tear down|cleanup|clean up'; then
  if ! printf '%s' "$content" | grep -Eiq 'before teardown|before tear down|keep_on_fail|preserve[^.]*(diagnostic|evidence|log)|diagnostic[^.]*before|on failure[^.]*(preserve|keep|dump|surface)'; then
    deny "This spec/plan's smoke section mentions teardown/cleanup but never states that the failure diagnostic is captured BEFORE teardown runs. Teardown-on-fail destroys the evidence needed to diagnose without guessing (feedback_never_guess_preserve_evidence). Add a line describing the preserve-before-teardown behavior (e.g. 'surface the diagnostic into the log before any teardown' or reference SMOKE_KEEP_ON_FAIL), or add: Evidence-gate: N/A — <reason> if this plan's smoke section genuinely never tears anything down on failure."
  fi
fi

# (B) a poll/wait loop mentioned without a dual-signal (success AND failure)
# safeguard.
if printf '%s' "$content" | grep -Eiq 'poll|wait[_-]?for|readiness check|timeout loop'; then
  if ! printf '%s' "$content" | grep -Eiq 'poll_until|both[^.]*(success|pass)[^.]*(failure|fail)|success and failure|dual.signal|failure signal'; then
    deny "This spec/plan's smoke section mentions a poll/wait loop but never states it watches BOTH a success signal AND a failure signal. A success-only poll burns the full timeout on every failure and can't distinguish 'slow' from 'broken' (feedback_never_guess_preserve_evidence). Add a line naming the dual-signal poll (e.g. 'poll_until <success> <failure> <timeout>'), or add: Evidence-gate: N/A — <reason> if this plan's smoke section genuinely has no poll/wait loop."
  fi
fi

exit 0
