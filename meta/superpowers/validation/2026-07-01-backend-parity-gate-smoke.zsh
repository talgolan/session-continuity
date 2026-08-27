#!/usr/bin/env zsh
# Smoke runner for the backend-parity-gate hook (commit-time). Hermetic: stages
# synthetic content into a throwaway repo, drives a `git commit` PreToolUse
# payload through hooks/backend-parity-gate.sh, asserts deny/allow verdict.
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++)); else print -r -- "FAIL - $1 (want $2 got $3)"; ((fail++)); fi }
verdict() { gt_is_deny "$1" && print deny || print allow; }

# 1. framed as multi-backend, names only ONE concrete backend -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'Smoke on the docker backend only.\n'
out="$(gt_run backend-parity-gate.sh "$(gt_commit_payload "$repo")")"
check "one backend named -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 2. framed as multi-backend, names TWO concrete backends -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'Smoke on docker and the apple container backend.\n'
out="$(gt_run backend-parity-gate.sh "$(gt_commit_payload "$repo")")"
check "two backends named -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 3. no "backend"/"backends" word at all (names only docker) -> allow
# (out of scope: the gate only fires once a plan frames coverage as multi-backend)
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'Smoke test runs against docker only.\n'
out="$(gt_run backend-parity-gate.sh "$(gt_commit_payload "$repo")")"
check "no backend word, names docker -> allow (out of scope)" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 4. decorated escape line overrides one-backend violation -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'> **Backend-parity:** N/A — single backend\nSmoke on the backend docker only.\n'
out="$(gt_run backend-parity-gate.sh "$(gt_commit_payload "$repo")")"
check "decorated escape -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 5. dot-prefixed scratch file with a case-1 violation -> allow (skipped)
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/.scratch.md" $'Smoke on the docker backend only.\n'
out="$(gt_run backend-parity-gate.sh "$(gt_commit_payload "$repo")")"
check "scratch file skipped -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"; [[ $fail -eq 0 ]]
