#!/usr/bin/env bash
#
# session-start.sh — SessionStart hook for the session-continuity plugin.
#
# Claude Code invokes this script once per session with a JSON payload on
# stdin. We do two things:
#
#   1. If the user's working directory contains a session-continuity primer at
#      .session-continuity/SESSION_PRIMER.md, emit a <system-reminder> block so
#      Claude is nudged to read the primer before doing any work.
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

primer_new="$cwd/.session-continuity/SESSION_PRIMER.md"

if [ -f "$primer_new" ]; then
  primer_path=".session-continuity/SESSION_PRIMER.md"
  learnings_path=".session-continuity/LEARNINGS.md"
else
  exit 0
fi

# Compute a 4-line status line ("Check mode" output) so the user and
# Claude both see at a glance how fresh the primer is. Every probe is
# best-effort — any failure falls back to "?" so the reminder still
# lands even on shallow clones, missing primers, etc.
# Shared status computation (see hooks/lib/primer-status.sh for the
# contract) — the same script commands/primer.md's check mode calls, so the
# two can no longer disagree about sha/mtime/counts. Resolved next to this
# script rather than via CLAUDE_PLUGIN_ROOT so the hook keeps working when a
# test harness runs it directly. Its absence falls back to "?" for every
# field, like the other best-effort probes here.
status_helper="$(dirname "$0")/lib/primer-status.sh"
if [ -f "$status_helper" ]; then
  status_out="$(bash "$status_helper" "$cwd" 2>/dev/null || true)"
else
  status_out=""
fi
status_sha="$(printf '%s\n' "$status_out" | sed -n 's/^HEAD_SHA=//p')"; status_sha="${status_sha:-?}"
status_mtime="$(printf '%s\n' "$status_out" | sed -n 's/^PRIMER_MTIME=//p')"; status_mtime="${status_mtime:-?}"
status_backlog_count="$(printf '%s\n' "$status_out" | sed -n 's/^BACKLOG_COUNT=//p')"; status_backlog_count="${status_backlog_count:-?}"
status_learnings="$(printf '%s\n' "$status_out" | sed -n 's/^LEARNINGS_COUNT=//p')"; status_learnings="${status_learnings:-?}"

status_outstanding="$status_backlog_count"
issues_helper="$(dirname "$0")/lib/backlog-issues.sh"
if [ -f "$issues_helper" ]; then
  outstanding_items="$(bash "$issues_helper" "$cwd" 2>/dev/null || true)"
else
  outstanding_items=""
fi

# Live queue first. Old-format leftovers still nudge primer so they get
# migrated; a leftover BACKLOG.md is a fossil and is never read.
if printf '%s\n' "$outstanding_items" | grep -qE '^[0-9]+\. #'; then
  outstanding_block=$'\nBacklog:\n'"$outstanding_items"$'\n\nPresent these to the user as a numbered list, numbered starting at 1 (never 0), showing each item as `#N Title`, and ask which of these (if any) they want to tackle this session.\n'
elif grep -q '^## Outstanding items' "$cwd/$primer_path" 2>/dev/null; then
  status_outstanding="?"
  outstanding_block=$'\n⚠️ Outstanding items haven\'t migrated to GitHub Issues yet — run /session-continuity:primer now to migrate before continuing.\n'
elif [ -f "$cwd/.session-continuity/OUTSTANDING_ITEMS.md" ]; then
  status_outstanding="?"
  outstanding_block=$'\n⚠️ .session-continuity/OUTSTANDING_ITEMS.md hasn\'t migrated to GitHub Issues yet — run /session-continuity:primer now to migrate before continuing.\n'
else
  outstanding_block=""
fi

# Inject the reminder into Claude's SessionStart context. `<system-reminder>`
# is the convention Claude Code uses for system-injected context that is
# treated as non-user-originating guidance.
cat <<EOF
<system-reminder>
This project has $primer_path. Read it before any work — it's the fastest path to context. Also check $learnings_path if anything surprises you.

Primer status (auto):
- HEAD: $status_sha
- Last primer change: $status_mtime
- Backlog: $status_outstanding
- Learnings: $status_learnings
${outstanding_block}</system-reminder>
EOF

# Weekly freshness check (best-effort, silent on failure). Runs AFTER the
# primer reminder so the reminder always lands even if version-check is
# slow or noisy.
script_dir="$(dirname "$0")"
if [ -x "$script_dir/version-check.sh" ]; then
  bash "$script_dir/version-check.sh" || true
fi

exit 0
