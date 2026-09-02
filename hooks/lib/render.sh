#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/render.sh — zero-model-call renderer for the four read-only
# slash commands (/backlog, /learnings, /help, /update). Task 3's
# UserPromptSubmit hook (not this file) intercepts the prompt and calls
# this script directly, returning stdout to the user without a model call.
#
# Usage:
#   render.sh backlog <project-dir>    Renders <project-dir>/.session-continuity/BACKLOG.md
#   render.sh learnings <project-dir>  Renders <project-dir>/.session-continuity/LEARNINGS.md
#   render.sh help                     Renders commands/help.md's fixed reference text
#   render.sh update                   Renders commands/update.md's fixed reference text
#
# Prints plain text to stdout and exits 0 on every path except a broken
# install. Two failure classes, deliberately distinct (same split as
# hooks/lib/learnings-index.sh):
#   Bad input (missing BACKLOG.md/LEARNINGS.md, or a file with no items) —
#   one line on stdout naming the file and pointing at
#   `/session-continuity:primer`, exit 0. Task 3 branches on exit status;
#   this is not a broken-install signal.
#   Broken install (an awk sibling missing or from another plugin version,
#   or an awk pass exiting non-zero) — one line on stderr, exit 2.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUBCOMMAND="${1:-}"

die_install() {
  printf 'render.sh: %s\n' "$1" >&2
  exit 2
}

check_sibling() {
  local f="$1"
  [[ -r "$SCRIPT_DIR/$f" ]] || die_install \
    "$f is missing from $SCRIPT_DIR — the plugin cache is incomplete. Run \`/session-continuity:update\`."
  grep -q '^# CONTRACT_VERSION=1$' "$SCRIPT_DIR/$f" || die_install \
    "$f is from a different plugin version — run \`/session-continuity:update\`."
}

render_backlog() {
  local dir="$1" file out
  file="$dir/.session-continuity/BACKLOG.md"
  check_sibling "render-backlog.awk"

  if [[ ! -r "$file" ]]; then
    echo "No BACKLOG.md found at $file — run /session-continuity:primer to set up session continuity."
    return 0
  fi

  out="$(awk -f "$SCRIPT_DIR/render-backlog.awk" "$file")" \
    || die_install "the backlog render pass failed (awk exited non-zero)."

  if [[ -z "$out" ]]; then
    echo "BACKLOG.md has no items."
  else
    printf '%s\n' "$out"
  fi
}

render_learnings() {
  local dir="$1" file out
  file="$dir/.session-continuity/LEARNINGS.md"
  check_sibling "render-learnings.awk"

  if [[ ! -r "$file" ]]; then
    echo "No LEARNINGS.md found at $file — run /session-continuity:primer to set up session continuity."
    return 0
  fi

  out="$(awk -f "$SCRIPT_DIR/render-learnings.awk" "$file")" \
    || die_install "the learnings render pass failed (awk exited non-zero)."

  if [[ -z "$out" ]]; then
    echo "LEARNINGS.md has no entries."
  else
    printf '%s\n' "$out"
  fi
}

render_help() {
  local version_line version header

  version_line="$(grep -m1 '"version"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null)"
  if [[ -n "$version_line" ]]; then
    version="$(printf '%s' "$version_line" | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
  fi

  if [[ -n "${version:-}" ]]; then
    header="session-continuity v${version}"
  else
    header="session-continuity — version unknown (vendored install)"
  fi

  cat <<EOF
${header}

WHAT THIS IS
Cross-session memory for Claude Code projects, via five in-repo Markdown
docs. A fresh Claude session (or a fresh terminal, or tomorrow) starts
cold — these files are how it gets caught up without you re-explaining
the project.

WHY
Claude doesn't remember yesterday's debugging, last week's refactor, or
the bug you spent three hours cornering. These files are a low-tech fix:
plain Markdown, committed to git alongside the code, readable by humans
and Claude alike. Every change is an auditable commit; no vendor-specific
storage, no opaque memory layer.

THE FIVE FILES
- SESSION_PRIMER.md    — volatile. Current state, latest commits. Refresh
                          alongside every substantive commit.
- PROJECT_CONTEXT.md   — stable. Repo layout, conventions, module table.
                          Changes rarely — only when the project's shape
                          changes.
- BACKLOG.md           — tactical. Explicitly deferred follow-ups and
                          decisions. Permanently numbered; closed items
                          are deleted, never renumbered.
- ROADMAP.md           — strategic. Now/Next/Later direction. Freeform,
                          no numbering, rewritten wholesale as direction
                          changes.
- LEARNINGS.md         — durable wisdom. Append-only, numbered. One entry
                          per bug that took 15+ minutes to diagnose.

COMMANDS
EOF

  local f name desc
  for f in "$PLUGIN_ROOT"/commands/*.md; do
    [[ -r "$f" ]] || continue
    name="$(basename "$f" .md)"
    desc="$(grep -m1 '^description:' "$f" | sed -E 's/^description:[[:space:]]*//')"
    [[ -n "$desc" ]] || desc="(no description found)"
    echo "/session-continuity:$name — $desc"
  done
}

render_update() {
  cat <<'EOF'
/plugin marketplace update talgolan
/reload-plugins

1. `marketplace update talgolan` — refetches the `talgolan` marketplace catalog from GitHub so the latest release of every plugin in it, including this one, is visible. No-op if already current.
2. `/reload-plugins` — activates the new version in this session without a restart.
EOF
}

case "$SUBCOMMAND" in
  backlog)
    render_backlog "${2:-}"
    ;;
  learnings)
    render_learnings "${2:-}"
    ;;
  help)   render_help ;;
  update) render_update ;;
  *)
    die_install "unknown subcommand '$SUBCOMMAND' (backlog|learnings|help|update)."
    ;;
esac
exit 0
