#!/usr/bin/env bash
# Weekly freshness check against GitHub Releases. Called by session-start.sh.
# Silent on offline, rate-limited, opted-out, or already-checked-this-week.

set -eu

# Opt-out.
if [ "${SESSION_CONTINUITY_SKIP_UPDATE_CHECK:-}" = "1" ]; then
  exit 0
fi

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/session-continuity"
cache_file="$cache_dir/last-check"

mkdir -p "$cache_dir"

# Skip if cache file exists and was touched within the last 7 days.
if [ -f "$cache_file" ]; then
  now="$(date +%s)"
  mtime="$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)"
  age=$(( now - mtime ))
  if [ "$age" -lt 604800 ]; then
    exit 0
  fi
fi

# Update cache timestamp BEFORE the network call so failure doesn't
# cause retry-every-session.
touch "$cache_file"

# Read installed version from plugin.json (parent of this script's dir).
script_dir="$(cd "$(dirname "$0")" && pwd)"
plugin_json="$script_dir/../.claude-plugin/plugin.json"

if [ ! -f "$plugin_json" ]; then
  exit 0
fi

installed="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$plugin_json" \
  | head -1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"

if [ -z "$installed" ]; then
  exit 0
fi

# Fetch latest release tag.
response="$(curl -sfm 3 https://api.github.com/repos/talgolan/session-continuity/releases/latest 2>/dev/null || true)"

if [ -z "$response" ]; then
  exit 0
fi

latest="$(printf '%s' "$response" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
  | head -1 | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/')"

if [ -z "$latest" ]; then
  exit 0
fi

# Compare using sort -V.
if [ "$installed" = "$latest" ]; then
  exit 0
fi

top="$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | tail -1)"

if [ "$top" != "$latest" ]; then
  # Installed is newer than latest release (dev build). Nothing to do.
  exit 0
fi

cat <<EOF
<system-reminder>
💡 session-continuity v$latest is available (you have v$installed). Run \`/plugin update session-continuity\` to upgrade.
See: https://github.com/talgolan/session-continuity/releases/tag/v$latest
(Opt out: SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1)
</system-reminder>
EOF

exit 0
