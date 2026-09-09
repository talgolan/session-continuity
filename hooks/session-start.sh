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
#   * On any unexpected condition (no payload, no cwd) we exit 0 silently.
#     A hook that crashes would only confuse the user. Never exit non-zero.
#   * Missing primer → init nudge. Missing peers → hard-stop. Inject-only —
#     never writes SESSION_PRIMER.md.

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

if [ ! -f "$primer_new" ]; then
  cat <<'EOF'
<system-reminder>
No .session-continuity/SESSION_PRIMER.md. Run /session-continuity:primer to init. Required peers: engrim + graphify-out/graph.json.
</system-reminder>
EOF
  script_dir="$(dirname "$0")"
  if [ -x "$script_dir/version-check.sh" ]; then
    bash "$script_dir/version-check.sh" || true
  fi
  exit 0
fi

primer_path=".session-continuity/SESSION_PRIMER.md"
learnings_path=".session-continuity/LEARNINGS.md"

# Peer probes (engrim CLI + graphify-out/graph.json). ENGRIM_BIN is read
# from the environment by peer-probes.sh — export it so nested calls inherit.
peers_helper="$(dirname "$0")/lib/peer-probes.sh"
if [ -n "${ENGRIM_BIN:-}" ]; then
  export ENGRIM_BIN
fi
if [ -f "$peers_helper" ]; then
  peers_out="$(bash "$peers_helper" "$cwd" 2>/dev/null || true)"
else
  peers_out=""
fi
engrim_status="$(printf '%s\n' "$peers_out" | sed -n 's/^ENGRIM=//p' | head -1)"
graphify_status="$(printf '%s\n' "$peers_out" | sed -n 's/^GRAPHIFY=//p' | head -1)"
engrim_status="${engrim_status:-missing}"
graphify_status="${graphify_status:-missing}"

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

# Hard-stop when peers are incomplete. Inject-only — never write the primer.
# Optional backlog shortlist still appends after the stop line.
if [ "$engrim_status" != "ok" ] || [ "$graphify_status" != "ok" ]; then
  cat <<EOF
<system-reminder>
PEER SETUP INCOMPLETE: engrim and graphify-out/graph.json are required. Do not start feature work until /session-continuity:doctor is green.
${outstanding_block}</system-reminder>
EOF
  script_dir="$(dirname "$0")"
  if [ -x "$script_dir/version-check.sh" ]; then
    bash "$script_dir/version-check.sh" || true
  fi
  exit 0
fi

# Freshness (substantive commits since last primer change). STALE=1 → warn.
freshness_helper="$(dirname "$0")/lib/primer-freshness.sh"
stale_line=""
if [ -f "$freshness_helper" ]; then
  freshness_out="$(bash "$freshness_helper" "$cwd" 2>/dev/null || true)"
  if printf '%s\n' "$freshness_out" | grep -qx 'STALE=1'; then
    stale_line=$'\n⚠️ Primer may be stale — substantive commits landed since the last primer update.\n'
  fi
fi

# Inject the reminder into Claude's SessionStart context. `<system-reminder>`
# is the convention Claude Code uses for system-injected context that is
# treated as non-user-originating guidance.
cat <<EOF
<system-reminder>
This project has $primer_path. Read it before any work — it's the fastest path to context. Also check $learnings_path if anything surprises you.

Read Mid-flight and Confirm in the primer before starting work.

Primer status (auto):
- HEAD: $status_sha
- Last primer change: $status_mtime
- Backlog: $status_outstanding
- Learnings: $status_learnings
${outstanding_block}${stale_line}</system-reminder>
EOF

# Weekly freshness check (best-effort, silent on failure). Runs AFTER the
# primer reminder so the reminder always lands even if version-check is
# slow or noisy.
script_dir="$(dirname "$0")"
if [ -x "$script_dir/version-check.sh" ]; then
  bash "$script_dir/version-check.sh" || true
fi

exit 0
