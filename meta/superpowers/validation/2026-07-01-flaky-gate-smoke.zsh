#!/usr/bin/env zsh
# Smoke runner for the flaky-gate hook (commit-time). Hermetic: stages
# synthetic content into a throwaway repo, drives `git commit` PreToolUse
# payloads through hooks/flaky-gate.sh, asserts deny/allow verdict. flaky-gate
# is the ONE gate that also inspects the commit MESSAGE text (not just staged
# file content) — cases 1-2 exercise the message path via the command string
# passed to gt_commit_payload; cases 3-7 exercise the staged LEARNINGS.md path.
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++)); else print -r -- "FAIL - $1 (want $2 got $3)"; ((fail++)); fi }
verdict() { gt_is_deny "$1" && print deny || print allow; }

# 1. commit message "fix flaky test", no staged LEARNINGS -> deny
repo="$(gt_make_repo)"
out="$(gt_run flaky-gate.sh "$(gt_commit_payload "$repo" 'git commit -m "fix flaky test"')")"
check "message: flaky, no Mechanism -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 2. commit message "fix flaky test. Mechanism: shared temp dir race" -> allow
repo="$(gt_make_repo)"
out="$(gt_run flaky-gate.sh "$(gt_commit_payload "$repo" 'git commit -m "fix flaky test. Mechanism: shared temp dir race"')")"
check "message: flaky + Mechanism -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 3. staged LEARNINGS.md "Test is flaky." (plain commit msg) -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" ".session-continuity/LEARNINGS.md" $'Test is flaky.\n'
out="$(gt_run flaky-gate.sh "$(gt_commit_payload "$repo")")"
check "file: flaky, no Mechanism -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 4. staged LEARNINGS.md "Test is flaky. Mechanism: DNS timeout in CI" -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" ".session-continuity/LEARNINGS.md" $'Test is flaky. Mechanism: DNS timeout in CI\n'
out="$(gt_run flaky-gate.sh "$(gt_commit_payload "$repo")")"
check "file: flaky + Mechanism -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 5. staged LEARNINGS.md flaky + decorated escape -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" ".session-continuity/LEARNINGS.md" $'flaky\n> **Flaky-gate:** N/A — glossary\n'
out="$(gt_run flaky-gate.sh "$(gt_commit_payload "$repo")")"
check "decorated escape -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 6. .session-continuity/.scratch.md with "flaky", plain msg -> allow (scratch + wrong basename)
repo="$(gt_make_repo)"
gt_stage "$repo" ".session-continuity/.scratch.md" $'flaky\n'
out="$(gt_run flaky-gate.sh "$(gt_commit_payload "$repo")")"
check "scratch + wrong basename -> allow (out of scope)" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 7. non-commit Bash (git status) with "flaky" in it -> allow (not a commit);
# also stage a violating LEARNINGS.md to prove neither check runs.
repo="$(gt_make_repo)"
gt_stage "$repo" ".session-continuity/LEARNINGS.md" $'Test is flaky.\n'
out="$(gt_run flaky-gate.sh "$(gt_commit_payload "$repo" 'git status --flaky')")"
check "non-commit Bash -> allow (not a commit)" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"; [[ $fail -eq 0 ]]
