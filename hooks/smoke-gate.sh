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

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

mentions_smoke="$(printf '%s' "$content" | grep -ci 'smoke' || true)"

# (1) weak-smoke
if [ "${mentions_smoke:-0}" -gt 0 ]; then
  if printf '%s' "$content" | grep -i 'smoke' \
       | grep -Eiq 'optional|deferred|after.?merge|nice.?to.?have'; then
    deny "Smoke task is marked optional/deferred. Engine/binary features need a MANDATORY smoke task — part of done, never deferred/after-merge. Re-mark it MANDATORY, or add a line: Smoke: N/A — <reason> if this plan genuinely touches no binary/engine."
  fi
  exit 0
fi

# (2) engine keyword, no smoke at all
if printf '%s' "$content" | grep -Eiq 'binary|engine|container|daemon|--compile|bun build'; then
  deny "This plan mentions binary/engine/container work but has no smoke task. Add a MANDATORY smoke task, or add a line: Smoke: N/A — <reason> if it genuinely touches no binary/engine."
fi

exit 0
