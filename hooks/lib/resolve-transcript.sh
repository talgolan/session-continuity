#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/resolve-transcript.sh — resolve the current session's transcript
# path. See meta/superpowers/specs/2026-09-02-end-session-step2-rendering-design.md.
#
# Usage: resolve-transcript.sh
# Prints the resolved transcript path on stdout, or nothing, and always
# exits 0 — best-effort, no error path. An empty result feeds
# candidate-extract.sh an empty path, which itself reports
# mode:"unavailable"; that is the one fallback path, not a second one here.
#
# Resolution: encode `pwd` with '/' -> '-' (a leading '/' becomes a leading
# '-'), look under ~/.claude/projects/<encoded-cwd>/, and pick the .jsonl
# file with the newest mtime. Prints nothing if that directory does not
# exist or holds no .jsonl file.
#
# Staleness (>5min) is NOT checked here. candidate-extract.sh already checks
# it and must stay correct when handed a path from any source, so that check
# stays the one place responsible for it.

set -uo pipefail

# Same GNU/BSD stat ordering trap as candidate-extract.sh: GNU stat's -f
# means --file-system and writes to stdout while exiting 1, so the BSD form
# must never be tried first inside a command substitution.
mtime_epoch() {
  local v
  v="$(stat -c %Y "$1" 2>/dev/null)"
  [[ "$v" =~ ^[0-9]+$ ]] && { printf '%s' "$v"; return 0; }
  v="$(stat -f %m "$1" 2>/dev/null)"
  [[ "$v" =~ ^[0-9]+$ ]] && { printf '%s' "$v"; return 0; }
  return 1
}

encoded="$(pwd | sed 's#/#-#g')"
dir="$HOME/.claude/projects/$encoded"

[[ -d "$dir" ]] || exit 0

best=""
best_mtime=-1
for f in "$dir"/*.jsonl; do
  [[ -e "$f" ]] || continue
  m="$(mtime_epoch "$f")" || continue
  [[ "$m" =~ ^[0-9]+$ ]] || continue
  if (( m > best_mtime )); then
    best_mtime="$m"
    best="$f"
  fi
done

[[ -n "$best" ]] && printf '%s\n' "$best"
exit 0
