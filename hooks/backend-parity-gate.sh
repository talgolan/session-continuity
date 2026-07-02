#!/usr/bin/env bash
#
# backend-parity-gate.sh — PreToolUse hook (session-continuity plugin).
#
# Fires before Write / Edit. Self-scopes to plan files (path under a
# */plans/ dir or a *plan*.md basename — same scope as smoke-gate.sh).
# BLOCKS the write when the plan explicitly frames its smoke coverage as
# multi-backend (mentions the word "backend"/"backends") but names only ONE
# concrete backend, instead of naming a second one for parity coverage.
#
# Rationale (feedback_smoke_backend_parity): a smoke runner proven on only
# one backend has an unverified half — Apple `container` and Docker (or any
# two engines a project ships) genuinely differ on ports, networking,
# inspect schema, and exec semantics. Scope both into the plan's smoke task
# from the start; don't ship one and backfill the other later.
#
# Deliberately narrow trigger: this gate only activates when the plan text
# itself says "backend"/"backends" — so single-backend projects that never
# use that word are never touched. It is NOT itb-specific; the concrete
# name list below is a superset covering common container engines, not a
# requirement that a project use exactly these.
#
# Escape hatch (explicit skip-with-reason): a line matching
#   Backend-parity: N/A — <reason>   (em-dash or --, non-empty reason)
# passes the gate unconditionally.
#
# Output contract (LEARNINGS #1): permissionDecision:"deny" blocks and shows
# the reason. Silent exit 0 allows. PreToolUse does NOT inject plain stdout.
#
# Self-reference (LEARNINGS #7): verify ONLY via the hermetic fixture runner,
# never by self-scanning a real plan. The loose hatch is intentional.
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

raw="$(printf '%s' "$payload" \
  | sed -nE 's/.*"content"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
  | head -1)"
[ -z "$raw" ] && raw="$(printf '%s' "$payload" \
  | sed -nE 's/.*"new_string"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
  | head -1)"
[ -z "$raw" ] && exit 0

content="$(printf '%s' "$raw" \
  | sed -E 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g; s/\\\\/\\/g')"

# Only in scope when the plan itself frames this as multi-backend.
printf '%s' "$content" | grep -Eiq 'backends?\b' || exit 0

# Escape hatch first.
if printf '%s' "$content" | grep -Eiq 'Backend-parity:[[:space:]]*N/A[[:space:]]*(—|--)[[:space:]]*[^[:space:]]'; then
  exit 0
fi

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Count distinct named backends from a generic container/VM-engine name
# list. >=2 distinct hits -> parity named; <2 -> deny.
names="docker apple podman containerd colima kata lima orbstack"
hit_count=0
for n in $names; do
  if printf '%s' "$content" | grep -Eiq "\\b${n}\\b"; then
    hit_count=$((hit_count + 1))
  fi
done

if [ "$hit_count" -lt 2 ]; then
  deny "This plan mentions 'backend(s)' but names fewer than two concrete backends. A smoke runner proven on only one backend has an unverified half (feedback_smoke_backend_parity) — pair every backend-specific section with an equivalent for the other backend(s) (e.g. Docker + Apple container). Name the second backend, or add: Backend-parity: N/A — <reason> if this plan genuinely has only one backend to cover."
fi

exit 0
