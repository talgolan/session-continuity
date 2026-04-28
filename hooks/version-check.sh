#!/usr/bin/env bash
#
# version-check.sh — weekly freshness check for the session-continuity plugin.
#
# Called from hooks/session-start.sh at the tail end of a SessionStart hook.
# Exits silently in every "not interesting" case — no noise, no blocking.
# Only produces output (a <system-reminder> pointing at the new release) when
# all of the following are true:
#
#   1. The user has not opted out (SESSION_CONTINUITY_SKIP_UPDATE_CHECK != 1).
#   2. The last successful check was more than 7 days ago (or never).
#   3. The plugin manifest is readable and parses to a version string.
#   4. GitHub's Releases API is reachable within 3 seconds.
#   5. The latest release tag is newer (per `sort -V`) than the installed
#      version — and specifically *not* the same as or behind it (a dev build
#      that happens to be ahead of the last release stays silent).
#
# Failure mode is always "exit 0 silently" — a crashed update check must never
# break the user's session. Output, when it happens, is a <system-reminder>
# block for Claude's SessionStart context, not anything printed to the user's
# terminal (Claude decides whether/when to surface it).
#
# Security notes:
#   * No user input is ever interpolated into a shell command. All variable
#     expansions are quoted. No `eval`. No subshells constructed from
#     user-controlled strings.
#   * The repository URL is derived from .claude-plugin/plugin.json's
#     "repository" field (falling back to a hardcoded default only if the
#     field is missing), so renaming or transferring the repo does not
#     silently stop the update check from working.
#   * The curl call uses -s (silent), -f (fail on HTTP >= 400 rather than
#     printing HTML error bodies), and -m 3 (3-second total timeout).

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Opt-out
# ---------------------------------------------------------------------------

if [ "${SESSION_CONTINUITY_SKIP_UPDATE_CHECK:-}" = "1" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Rate-limit via mtime-stamped cache file
# ---------------------------------------------------------------------------

# Honour XDG_CACHE_HOME when set; otherwise fall back to $HOME/.cache (this is
# the XDG fallback on Linux and works fine on macOS too — it just isn't the
# macOS-native convention).
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/session-continuity"
cache_file="$cache_dir/last-check"

mkdir -p "$cache_dir"

if [ -f "$cache_file" ]; then
  now="$(date +%s)"
  # Prefer BSD stat syntax (macOS), fall back to GNU stat (Linux). If both
  # fail, treat the file as missing.
  mtime="$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)"
  age=$(( now - mtime ))
  # 604800 = 7 * 24 * 60 * 60
  if [ "$age" -lt 604800 ]; then
    exit 0
  fi
fi

# Touch the cache BEFORE the network call. If curl fails (no network,
# GitHub returning 5xx, rate-limited from too many hooks, etc.) we still
# want to back off for a week rather than retry every single session.
touch "$cache_file"

# ---------------------------------------------------------------------------
# 3. Read installed version + repository URL from plugin.json
# ---------------------------------------------------------------------------

script_dir="$(cd "$(dirname "$0")" && pwd)"
plugin_json="$script_dir/../.claude-plugin/plugin.json"

if [ ! -f "$plugin_json" ]; then
  exit 0
fi

# A tiny JSON extractor that grabs the value of a top-level string field.
# Not RFC-compliant — it doesn't handle escaped quotes, nested objects, or
# multi-line strings — but plugin.json's "version" and "repository" fields
# are under our control and always simple strings, so this is safe here.
# Using jq would be cleaner but would add a runtime dependency that is not
# guaranteed to be on every contributor's PATH.
json_field() {
  local field="$1"
  # `|| true` on the whole pipeline prevents `set -e`/`pipefail` from
  # aborting when the field is absent — we want empty output, not a crash.
  (grep -oE "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" "$plugin_json" \
    | head -1 \
    | sed -E "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/") \
    || true
}

installed="$(json_field version)"

if [ -z "$installed" ]; then
  exit 0
fi

# Derive the "owner/repo" slug used in GitHub API URLs from the repository
# field. Accepts either "https://github.com/owner/repo" or plain
# "owner/repo"; falls back to the hardcoded default if the field is
# missing or malformed.
repo_url="$(json_field repository)"
repo_slug=""
case "$repo_url" in
  https://github.com/*/*)
    # Strip the leading URL prefix and any trailing ".git" / "/".
    repo_slug="${repo_url#https://github.com/}"
    repo_slug="${repo_slug%.git}"
    repo_slug="${repo_slug%/}"
    ;;
  http://github.com/*/*)
    repo_slug="${repo_url#http://github.com/}"
    repo_slug="${repo_slug%.git}"
    repo_slug="${repo_slug%/}"
    ;;
  git@github.com:*/*)
    repo_slug="${repo_url#git@github.com:}"
    repo_slug="${repo_slug%.git}"
    ;;
  */*)
    repo_slug="$repo_url"
    ;;
esac

# Defensive fallback — if parsing produced something that isn't exactly
# "owner/repo" (two non-empty path components and nothing else), use the
# hardcoded default rather than letting a malformed value into the URL.
if ! printf '%s' "$repo_slug" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
  repo_slug="talgolan/session-continuity"
fi

# ---------------------------------------------------------------------------
# 4. Fetch latest release tag
# ---------------------------------------------------------------------------

api_url="https://api.github.com/repos/${repo_slug}/releases/latest"
response="$(curl -sfm 3 "$api_url" 2>/dev/null || true)"

if [ -z "$response" ]; then
  exit 0
fi

latest="$(printf '%s' "$response" \
  | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
  | head -1 \
  | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/')"

if [ -z "$latest" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. Compare versions (skip silently if installed >= latest)
# ---------------------------------------------------------------------------

if [ "$installed" = "$latest" ]; then
  exit 0
fi

# `sort -V` gives us semantic-ish version ordering; the later of the two
# sorts last. If that last line is not $latest, the installed build is
# ahead of the most recent release (a dev build) — stay silent.
top="$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | tail -1)"

if [ "$top" != "$latest" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 6. Emit the upgrade reminder
# ---------------------------------------------------------------------------

# Plain stdout from SessionStart hooks IS injected into Claude's additional
# context, so we don't need a JSON wrapper here (unlike PreToolUse hooks,
# which do require hookSpecificOutput.additionalContext — see LEARNINGS #1).
cat <<EOF
<system-reminder>
💡 session-continuity v$latest is available (you have v$installed). Run \`/plugin marketplace update session-continuity && /reload-plugins\` to upgrade.
See: https://github.com/${repo_slug}/releases/tag/v$latest
(Opt out: SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1)
</system-reminder>
EOF

exit 0
