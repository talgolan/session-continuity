#!/usr/bin/env bash
#
# session-start.sh — SessionStart hook for the session-continuity plugin.
#
# Claude Code invokes this script once per session with a JSON payload on
# stdin. We do two things:
#
#   1. If the user's working directory contains a session-continuity primer at
#      either .session-continuity/SESSION_PRIMER.md (v0.5.0+ canonical path)
#      or docs/SESSION_PRIMER.md (v0.4-and-earlier legacy path), emit a
#      <system-reminder> block so Claude is nudged to read the primer before
#      doing any work. The reminder interpolates whichever path is actually
#      present, so a fresh session reads the right file.
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

# Prefer the v0.5.0+ canonical location (.session-continuity/); fall back to
# the legacy docs/ path so unmigrated repos keep working. The reminder text
# uses whichever path actually exists so Claude reads the right file.
primer_new="$cwd/.session-continuity/SESSION_PRIMER.md"
primer_old="$cwd/docs/SESSION_PRIMER.md"

if [ -f "$primer_new" ]; then
  primer_path=".session-continuity/SESSION_PRIMER.md"
  learnings_path=".session-continuity/LEARNINGS.md"
elif [ -f "$primer_old" ]; then
  primer_path="docs/SESSION_PRIMER.md"
  learnings_path="docs/LEARNINGS.md"
else
  exit 0
fi

# Compute a 4-line status line ("Check mode" output) so the user and
# Claude both see at a glance how fresh the primer is. Every probe is
# best-effort — any failure falls back to "?" so the reminder still
# lands even on shallow clones, missing primers, etc.
status_sha="$(cd "$cwd" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo '?')"
status_mtime="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$cwd/$primer_path" 2>/dev/null \
  || stat -c '%y' "$cwd/$primer_path" 2>/dev/null \
  || echo '?')"
# Outstanding items: count top-level numbered lines (`^N. `) inside the
# "Outstanding items" section. The awk block reads from the section
# heading until the next `## ` heading.
status_outstanding="$(awk '
  /^## Outstanding items/ { inside=1; next }
  inside && /^## / { exit }
  inside && /^[0-9]+\. / { count++ }
  END { print count+0 }
' "$cwd/$primer_path" 2>/dev/null || echo '?')"
status_learnings="$(grep -cE '^### [0-9]+\.' "$cwd/$learnings_path" 2>/dev/null || echo '0')"

# Inject the reminder into Claude's SessionStart context. `<system-reminder>`
# is the convention Claude Code uses for system-injected context that is
# treated as non-user-originating guidance.
cat <<EOF
<system-reminder>
This project has $primer_path. Read it before any work — it's the fastest path to context. Also check $learnings_path if anything surprises you.

Primer status (auto):
- HEAD: $status_sha
- Last primer change: $status_mtime
- Outstanding items: $status_outstanding
- Learnings: $status_learnings
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
