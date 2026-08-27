#!/usr/bin/env zsh
# Shared hermetic harness for the gate runners.

# Captured at source time: $0 here is this file's own path (zsh sets $0 to
# the sourced file during `source`) — this file's location relative to repo
# root is fixed, so this is invariant regardless of which runner sources it.
_GT_HOOKS_DIR="${0:A:h:h:h:h:h}/hooks"

gt_make_repo() {
  local d; d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email "t@t.t"
  git -C "$d" config user.name "t"
  git -C "$d" config commit.gpgsign false
  print -r -- "$d"
}
gt_stage() {  # <repo> <relpath> <content>
  local repo="$1" rel="$2" content="$3"
  mkdir -p "$repo/${rel:h}"
  print -rn -- "$content" > "$repo/$rel"
  git -C "$repo" add "$rel"
}
gt_commit_payload() {  # <repo> <command> ; command defaults to a plain commit
  local repo="$1" cmd="${2:-git commit -m msg}"
  # JSON with cwd top-level and command nested; escape backslashes and quotes.
  local esc="${cmd//\\/\\\\}"; esc="${esc//\"/\\\"}"
  print -r -- "{\"tool_name\":\"Bash\",\"cwd\":\"$repo\",\"tool_input\":{\"command\":\"$esc\"}}"
}
gt_run() {  # <gate-name> <payload>  -> gate stdout
  local gate="$1" payload="$2"
  print -rn -- "$payload" | bash "$_GT_HOOKS_DIR/$gate"
}
gt_is_deny() { print -rn -- "$1" | grep -q '"permissionDecision":"deny"'; }
gt_is_allow() { ! gt_is_deny "$1"; }   # allow == not a deny (silent or allow JSON)
gt_cleanup() { if [[ -n "${1:-}" && -d "$1" ]]; then rm -rf "$1"; fi; }
