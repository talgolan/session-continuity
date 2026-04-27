#!/usr/bin/env bash
# SessionStart hook for session-continuity.
# Reads stdin JSON from Claude Code, extracts cwd, and emits a
# read-reminder when docs/SESSION_PRIMER.md is present in that cwd.
# Then invokes version-check.sh (weekly freshness check). Silent otherwise.

set -eu

payload="$(cat || true)"

cwd="$(printf '%s' "$payload" \
  | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*"cwd"[[:space:]]*:[[:space:]]*"(.*)"/\1/')"

if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
  exit 0
fi

primer="$cwd/docs/SESSION_PRIMER.md"

if [ ! -f "$primer" ]; then
  exit 0
fi

cat <<'EOF'
<system-reminder>
This project has docs/SESSION_PRIMER.md. Read it before any work — it's the fastest path to context. Also check docs/LEARNINGS.md if anything surprises you.
</system-reminder>
EOF

# Weekly freshness check (best-effort, silent on failure).
script_dir="$(dirname "$0")"
if [ -x "$script_dir/version-check.sh" ]; then
  bash "$script_dir/version-check.sh" || true
fi

exit 0
