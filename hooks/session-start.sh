#!/usr/bin/env bash
# SessionStart hook for session-continuity.
# Emits a read-reminder when docs/SESSION_PRIMER.md is present in cwd,
# then invokes version-check.sh (weekly freshness check). Silent otherwise.

set -eu

primer="docs/SESSION_PRIMER.md"

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
