#!/usr/bin/env zsh
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++)); else print -r -- "FAIL - $1 (want $2 got $3)"; ((fail++)); fi }
verdict() { gt_is_deny "$1" && print deny || print allow; }

gt_dirty_repo() {  # <relpath> <content> -> repo with one committed file, one dirty edit
  local repo; repo="$(gt_make_repo)"
  gt_stage "$repo" "$1" "baseline"
  git -C "$repo" commit -qm base
  print -rn -- "$2" > "$repo/$1"
  print -r -- "$repo"
}

# 1. git reset --hard on a dirty tree -> deny
repo="$(gt_dirty_repo "f.txt" "edited")"
out="$(gt_run dirty-tree-gate.sh "$(gt_commit_payload "$repo" "git reset --hard")")"
check "reset --hard on dirty tree -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 2. git reset --hard on a clean tree -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "f.txt" "content"
git -C "$repo" commit -qm base
out="$(gt_run dirty-tree-gate.sh "$(gt_commit_payload "$repo" "git reset --hard")")"
check "reset --hard on clean tree -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 3. git checkout -- <path> on a dirty tree -> deny
repo="$(gt_dirty_repo "f.txt" "edited")"
out="$(gt_run dirty-tree-gate.sh "$(gt_commit_payload "$repo" "git checkout -- f.txt")")"
check "checkout -- <path> on dirty tree -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 4. git checkout . on a dirty tree -> deny
repo="$(gt_dirty_repo "f.txt" "edited")"
out="$(gt_run dirty-tree-gate.sh "$(gt_commit_payload "$repo" "git checkout .")")"
check "checkout . on dirty tree -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 5. git checkout <branch> (no -- , not a bare dot) is a branch switch, not a
#    discard — must allow even on a dirty tree.
repo="$(gt_dirty_repo "f.txt" "edited")"
git -C "$repo" branch other >/dev/null
out="$(gt_run dirty-tree-gate.sh "$(gt_commit_payload "$repo" "git checkout other")")"
check "checkout <branch> on dirty tree -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 6. git restore <path> (default, worktree-affecting) on a dirty tree -> deny
repo="$(gt_dirty_repo "f.txt" "edited")"
out="$(gt_run dirty-tree-gate.sh "$(gt_commit_payload "$repo" "git restore f.txt")")"
check "restore <path> on dirty tree -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 7. git restore --staged <path> (unstage only, worktree untouched) -> allow
repo="$(gt_dirty_repo "f.txt" "edited")"
out="$(gt_run dirty-tree-gate.sh "$(gt_commit_payload "$repo" "git restore --staged f.txt")")"
check "restore --staged only -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 8. Escape hatch env var bypasses the deny.
repo="$(gt_dirty_repo "f.txt" "edited")"
out="$(SESSION_CONTINUITY_SKIP_DIRTY_GATE=1 gt_run dirty-tree-gate.sh "$(gt_commit_payload "$repo" "git reset --hard")")"
check "escape hatch env var bypasses deny" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 9. Non-Bash tool call -> allow (no crash on missing tool_input.command)
repo="$(gt_dirty_repo "f.txt" "edited")"
out="$(print -rn -- '{"tool_name":"Write","cwd":"'"$repo"'"}' | bash "${HERE:h:h:h}/hooks/dirty-tree-gate.sh")"
check "non-Bash tool -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 10. A commit message that merely QUOTES 'git reset --hard' as prose must
#     allow, even on a dirty tree — regression test: an earlier draft
#     substring-searched the whole raw command instead of anchoring to each
#     segment's start, so this quoted mention inside `git commit -m "..."`
#     was misdetected as the invoked subcommand. See the comment in
#     dtg_is_destructive.
repo="$(gt_dirty_repo "f.txt" "edited")"
out="$(gt_run dirty-tree-gate.sh "$(gt_commit_payload "$repo" 'git commit -m "docs: explain how git reset --hard works, dangerous"')")"
check "commit message quoting 'git reset --hard' as prose -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
