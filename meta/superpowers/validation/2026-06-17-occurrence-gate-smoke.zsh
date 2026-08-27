#!/usr/bin/env zsh
# Smoke runner for the occurrence-gate hook (commit-time). Hermetic: stages
# synthetic content into a throwaway repo, drives a `git commit` PreToolUse
# payload through hooks/occurrence-gate.sh, asserts deny/allow verdict.
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++)); else print -r -- "FAIL - $1 (want $2 got $3)"; ((fail++)); fi }
verdict() { gt_is_deny "$1" && print deny || print allow; }

# 1. Occurrence count 2 of 2, no Invariant -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" ".session-continuity/LEARNINGS.md" $'Occurrence count: 2 of 2\nFix: patched it again.\n'
out="$(gt_run occurrence-gate.sh "$(gt_commit_payload "$repo")")"
check "occ2, no invariant -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 2. Occurrence count 3 of 3, WITH an Invariant line -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" ".session-continuity/LEARNINGS.md" $'Occurrence count: 3 of 3\nInvariant: reconciler enforces X on every path.\n'
out="$(gt_run occurrence-gate.sh "$(gt_commit_payload "$repo")")"
check "occ3 + invariant -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 3. Occurrence count 1 of 2 (N<2) -> allow (nothing owed yet)
repo="$(gt_make_repo)"
gt_stage "$repo" ".session-continuity/LEARNINGS.md" $'Occurrence count: 1 of 2\nFirst time we hit this.\n'
out="$(gt_run occurrence-gate.sh "$(gt_commit_payload "$repo")")"
check "occ1 (N<2) -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 4. decorated escape line overrides an occ2/no-invariant violation -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" ".session-continuity/LEARNINGS.md" $'> **Occurrence-gate:** N/A — quoting\nOccurrence count: 2 of 2\nFix: patched it again.\n'
out="$(gt_run occurrence-gate.sh "$(gt_commit_payload "$repo")")"
check "decorated escape -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 5. same violation, wrong basename (NOTES.md) under .session-continuity/ -> allow (out of scope)
repo="$(gt_make_repo)"
gt_stage "$repo" ".session-continuity/NOTES.md" $'Occurrence count: 2 of 2\nFix: patched it again.\n'
out="$(gt_run occurrence-gate.sh "$(gt_commit_payload "$repo")")"
check "wrong basename NOTES.md -> allow (out of scope)" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 6. same violation, right basename but NOT under .session-continuity/ -> allow (out of scope)
repo="$(gt_make_repo)"
gt_stage "$repo" "LEARNINGS.md" $'Occurrence count: 2 of 2\nFix: patched it again.\n'
out="$(gt_run occurrence-gate.sh "$(gt_commit_payload "$repo")")"
check "top-level LEARNINGS.md -> allow (out of scope)" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"; [[ $fail -eq 0 ]]
