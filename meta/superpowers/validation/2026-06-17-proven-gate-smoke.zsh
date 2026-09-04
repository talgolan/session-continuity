#!/usr/bin/env zsh
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++)); else print -r -- "FAIL - $1 (want $2 got $3)"; ((fail++)); fi }
verdict() { gt_is_deny "$1" && print deny || print allow; }

# 1. staged plan with a bare "verified" claim, no fields -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'We verified the pipeline works end to end.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "claim without fields -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 2. same claim WITH Real path + Stubbed -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'Verified.\nReal path: prod runner ran.\nStubbed: nothing.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "claim with both fields -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 3. decorated escape line -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'Verified by reading source.\n> **Proven-gate:** N/A — reads only, nothing run.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "decorated escape -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 4. dot-prefixed scratch file with a violation -> allow (skipped)
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/.grounding.md" $'We verified it.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "scratch file skipped -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 5. no matching staged file (wrong dir) -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "src/x.md" $'We verified it.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "out-of-scope path -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 6. non-git-commit Bash command -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'We verified it.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo" "git status")")"
check "non-commit command -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 7. word-boundary: "unproven" alone does not trigger
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'This remains unproven for now.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "unproven not a claim -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 8. self-condemnation: the doc's ONLY trigger word is its own escape line, and
#    that line is malformed (no dash/reason) so gate_has_escape rejects it. The
#    gate must fail OPEN on its own hatch, not treat it as the condemning claim.
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'A plan with no claims at all.\nProven-gate: N/A\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "malformed own hatch is not a claim -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 9. a real claim elsewhere still denies even when a malformed hatch is present
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'Proven-gate: N/A\nWe verified the pipeline end to end.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "real claim beside malformed hatch -> deny" "deny" "$(verdict "$out")"
# 10. and the deny names the offending line number, so it is diagnosable in one read
if print -rn -- "$out" | grep -q 'line 2'; then
  check "deny names the matched line number" "yes" "yes"
else
  check "deny names the matched line number" "yes" "no"
fi
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"; [[ $fail -eq 0 ]]
