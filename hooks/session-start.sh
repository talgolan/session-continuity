#!/usr/bin/env bash
#
# session-start.sh — SessionStart hook for the session-continuity plugin.
#
# Claude Code invokes this script once per session with a JSON payload on
# stdin. We do two things:
#
#   1. If the user's working directory contains docs/SESSION_PRIMER.md, emit a
#      <system-reminder> block so Claude is nudged to read the primer before
#      doing any work.
#   2. Invoke hooks/version-check.sh (weekly freshness check against the
#      GitHub Releases API) — silently fails and is entirely optional.
#
# Plain stdout from SessionStart hooks is injected into Claude's additional
# context (the PreToolUse contract is different — see pre-commit-check.sh).
# So we just print, no JSON wrapper required.
#
# Security notes:
#   * All expansions are quoted.
#   * `$cwd` is extracted from the JSON payload and only used as an argument
#     to directory/file existence tests. It is never `eval`ed or passed
#     unquoted to a shell command.
#   * On any unexpected condition (no payload, no cwd, missing primer) we
#     exit 0 silently. A hook that crashes would only confuse the user.

set -euo pipefail

# Read the JSON payload Claude Code delivers on stdin. The `|| true` guards
# against `set -e` aborting if stdin is empty (smoke tests run the script
# with an empty payload).
payload="$(cat || true)"

# Extract the "cwd" field from the top of the payload. This is intentionally
# a minimal regex — not a real JSON parser — because we want to avoid a
# runtime dependency on `jq`. The tradeoff is that values containing
# embedded JSON-escaped quotes will be truncated; on truncation the hook
# exits silently below. We've confirmed on the Claude Code side that `cwd`
# is always a plain filesystem path, so escaped quotes are a theoretical
# concern rather than a real one.
cwd="$(printf '%s' "$payload" \
  | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*"cwd"[[:space:]]*:[[:space:]]*"(.*)"/\1/' \
  || true)"

if [ -z "${cwd:-}" ] || [ ! -d "$cwd" ]; then
  exit 0
fi

primer="$cwd/docs/SESSION_PRIMER.md"

if [ ! -f "$primer" ]; then
  exit 0
fi

# Inject the reminder into Claude's SessionStart context. `<system-reminder>`
# is the convention Claude Code uses for system-injected context that is
# treated as non-user-originating guidance.
cat <<'EOF'
<system-reminder>
This project has docs/SESSION_PRIMER.md. Read it before any work — it's the fastest path to context. Also check docs/LEARNINGS.md if anything surprises you.
</system-reminder>
EOF

# Weekly freshness check (best-effort, silent on failure). Runs AFTER the
# primer reminder so the reminder always lands even if version-check is
# slow or noisy.
script_dir="$(dirname "$0")"
if [ -x "$script_dir/version-check.sh" ]; then
  bash "$script_dir/version-check.sh" || true
fi

exit 0
