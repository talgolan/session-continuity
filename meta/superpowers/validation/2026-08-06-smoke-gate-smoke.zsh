#!/usr/bin/env zsh
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++)); else print -r -- "FAIL - $1 (want $2 got $3)"; ((fail++)); fi }
verdict() { gt_is_deny "$1" && print deny || print allow; }

# 1. binary/engine mention, no smoke at all -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'binary build step; deploy the engine.\n'
out="$(gt_run smoke-gate.sh "$(gt_commit_payload "$repo")")"
check "no-smoke binary/engine -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 2. smoke mentioned, not weak -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'Run the smoke test after building the binary.\n'
out="$(gt_run smoke-gate.sh "$(gt_commit_payload "$repo")")"
check "smoke mentioned, not weak -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 3. weak-smoke adjacent ("optional") -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'smoke test is optional for the binary.\n'
out="$(gt_run smoke-gate.sh "$(gt_commit_payload "$repo")")"
check "weak-smoke adjacent -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 4. explicit MANDATORY short-circuits before weak-smoke check -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'smoke is MANDATORY — never deferred. builds a binary.\n'
out="$(gt_run smoke-gate.sh "$(gt_commit_payload "$repo")")"
check "explicit MANDATORY -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 5. decorated escape line -> allow (even with binary mention)
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'> **Smoke:** N/A — pure docs change.\nThis plan touches a binary component.\n'
out="$(gt_run smoke-gate.sh "$(gt_commit_payload "$repo")")"
check "decorated escape -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 6. dot-prefixed scratch file with a case-1 violation -> allow (skipped)
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/.scratch.md" $'binary build step; deploy the engine.\n'
out="$(gt_run smoke-gate.sh "$(gt_commit_payload "$repo")")"
check "scratch file skipped -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 7. no binary/engine/smoke words at all -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'Update the documentation for the primer.\n'
out="$(gt_run smoke-gate.sh "$(gt_commit_payload "$repo")")"
check "no binary/engine/smoke words -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"; [[ $fail -eq 0 ]]
