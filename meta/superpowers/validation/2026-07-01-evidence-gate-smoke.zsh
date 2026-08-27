#!/usr/bin/env zsh
# Smoke runner for the evidence-gate hook (commit-time). Hermetic: stages
# synthetic content into a throwaway repo, drives a `git commit` PreToolUse
# payload through hooks/evidence-gate.sh, asserts deny/allow verdict.
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++)); else print -r -- "FAIL - $1 (want $2 got $3)"; ((fail++)); fi }
verdict() { gt_is_deny "$1" && print deny || print allow; }

# 1. teardown mentioned, no preserve-before-teardown safeguard -> deny (A)
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/specs/s.md" $'smoke SUT teardown on failure\n'
out="$(gt_run evidence-gate.sh "$(gt_commit_payload "$repo")")"
check "teardown, no preserve -> deny (A)" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 2. teardown mentioned WITH preserve-before-teardown safeguard -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/specs/s.md" $'smoke: surface the diagnostic into the log before any teardown\n'
out="$(gt_run evidence-gate.sh "$(gt_commit_payload "$repo")")"
check "teardown, preserve-before -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 3. poll/wait loop mentioned, no dual-signal safeguard -> deny (B)
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/specs/s.md" $'smoke poll loop with a timeout\n'
out="$(gt_run evidence-gate.sh "$(gt_commit_payload "$repo")")"
check "poll loop, no dual-signal -> deny (B)" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 4. poll/wait loop mentioned WITH dual-signal safeguard -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/specs/s.md" $'smoke poll_until <success> <failure> <timeout>\n'
out="$(gt_run evidence-gate.sh "$(gt_commit_payload "$repo")")"
check "poll_until dual-signal -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 5. no "smoke" word at all, even though teardown is discussed -> allow
# (out of section scope: the gate only fires once a spec is discussing smoke)
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/specs/s.md" $'The deploy pipeline runs teardown and cleanup after every run.\n'
out="$(gt_run evidence-gate.sh "$(gt_commit_payload "$repo")")"
check "no smoke word, has teardown -> allow (out of scope)" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 6. decorated escape line overrides teardown+smoke violation -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/specs/s.md" $'> **Evidence-gate:** N/A — reason\nsmoke SUT teardown on failure\n'
out="$(gt_run evidence-gate.sh "$(gt_commit_payload "$repo")")"
check "decorated escape -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 7. dot-prefixed scratch file with a case-1 violation -> allow (skipped)
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/specs/.scratch.md" $'smoke SUT teardown on failure\n'
out="$(gt_run evidence-gate.sh "$(gt_commit_payload "$repo")")"
check "scratch file skipped -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"; [[ $fail -eq 0 ]]
