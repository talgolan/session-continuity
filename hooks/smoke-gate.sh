#!/usr/bin/env bash
#
# smoke-gate.sh — PreToolUse hook (session-continuity plugin).
#
# Fires before Write / Edit. Self-scopes to plan files (path under a
# */plans/ dir or a *plan*.md basename). BLOCKS the write when an
# engine/binary-touching plan lacks a MANDATORY smoke task:
#
#   (1) weak-smoke   — mentions "smoke" but a smoke line is tagged
#                      optional/deferred/after-merge/nice-to-have.
#   (2) no-smoke     — mentions binary/engine/container/daemon/--compile/
#                      "bun build" but has no "smoke" mention at all.
#
# Escape hatch (explicit skip-with-reason): a line matching
#   Smoke: N/A — <reason>   (em-dash or --, non-empty reason)
# passes the gate unconditionally.
#
# Output contract: permissionDecision:"deny" blocks the tool call and shows
# the reason to Claude. permissionDecision:"allow" (or silent exit 0) lets
# it through.
#
# Security: $cwd / file_path used only in path tests + grep; never eval'd.

set -euo pipefail

payload="$(cat || true)"
[ -z "${payload:-}" ] && exit 0

file_path="$(printf '%s' "$payload" \
  | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' \
  || true)"
[ -z "${file_path:-}" ] && exit 0

# Self-scope: only plan files. */plans/*.md OR basename *plan*.md
base="${file_path##*/}"
case "$file_path" in
  */plans/*) : ;;
  *)
    case "$base" in
      *plan*.md) : ;;
      *) exit 0 ;;
    esac
    ;;
esac
case "$base" in *.md) : ;; *) exit 0 ;; esac

# Pull the written content. Write -> content; Edit -> new_string. We extract
# everything after the key's opening quote to end of payload, then strip the
# trailing JSON, and UN-escape \n and \" so line-oriented greps work. This is
# a bounded best-effort decode; the gate errs toward blocking, and the
# escape hatch gives an explicit override, so imperfect decode is safe.
raw="$(printf '%s' "$payload" \
  | sed -nE 's/.*"content"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
  | head -1)"
[ -z "$raw" ] && raw="$(printf '%s' "$payload" \
  | sed -nE 's/.*"new_string"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
  | head -1)"
[ -z "$raw" ] && exit 0

# Decode JSON-escaped newlines/quotes/tabs into real characters.
content="$(printf '%s' "$raw" \
  | sed -E 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g; s/\\\\/\\/g')"

# Escape hatch first.
if printf '%s' "$content" | grep -Eiq 'Smoke:[[:space:]]*N/A[[:space:]]*(—|--)[[:space:]]*[^[:space:]]'; then
  exit 0
fi

# Escape a value for embedding in a JSON string literal. Backslash first, then
# double-quote — the reverse order re-escapes the backslashes the quote rule
# just inserted. Raw control characters are illegal inside a JSON string
# (RFC 8259) and make the payload unparseable, so every C0 byte (0x00-0x1F —
# tab and newline are the ones a grep capture is likely to carry, but the
# fold covers the whole range, not just those) collapses to a space.
json_escape() {
  printf '%s' "$1" | sed -E 's/\\/\\\\/g; s/"/\\"/g' | tr '\000-\037' ' '
}

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(json_escape "$1")"
  exit 0
}

# Explicit-MANDATORY pass: if any line has "smoke" and the word MANDATORY
# co-occurring (either order), the author has affirmatively declared the smoke
# task mandatory — pass unconditionally. This must run BEFORE the weak-smoke
# branch, so a "Smoke: MANDATORY" declaration is never overridden by an
# incidental weak-word elsewhere, and a negation line ("smoke is MANDATORY —
# never deferred/after-merge") is honored, not punished.
if printf '%s' "$content" \
     | grep -Eiq 'smoke.*\bMANDATORY\b|\bMANDATORY\b.*smoke'; then
  exit 0
fi

mentions_smoke="$(printf '%s' "$content" | grep -ci 'smoke' || true)"

# (1) weak-smoke — only when a weak-word sits ADJACENT to "smoke" (within ~20
# non-period chars, either order), so it actually modifies the smoke task.
# Line-scoped co-occurrence is not enough: prose routinely pairs "smoke" with
# an unrelated "optional"/"deferred" on one long sentence. grep runs per line,
# so the period-stop ([^.]) keeps the match inside one sentence.
weak='optional|deferred|after.?merge|nice.?to.?have'
if [ "${mentions_smoke:-0}" -gt 0 ]; then
  offender="$(printf '%s' "$content" \
    | grep -Ei "smoke[^.]{0,20}($weak)|($weak)[^.]{0,20}smoke" \
    | head -1)"
  if [ -n "$offender" ]; then
    deny "Smoke task looks optional/deferred (matched: \"${offender}\"). If this is incidental prose, reword; if the smoke task is truly mandatory, add the word MANDATORY on a smoke line, or add a line: Smoke: N/A — <reason> if this plan genuinely touches no binary/engine."
  fi
  exit 0
fi

# (2) engine keyword, no smoke at all
if printf '%s' "$content" | grep -Eiq 'binary|engine|container|daemon|--compile|bun build'; then
  deny "This plan mentions binary/engine/container work but has no smoke task. Add a MANDATORY smoke task, or add a line: Smoke: N/A — <reason> if it genuinely touches no binary/engine."
fi

exit 0
