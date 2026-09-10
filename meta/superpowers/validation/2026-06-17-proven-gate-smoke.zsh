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

repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'Proven-gate: N/A — glossary\nwe verified nothing\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "accepted hatch via driver short-circuit -> allow" "allow" "$(verdict "$out")"
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

# 11. an unrelated addition does not re-litigate an incomplete claim in HEAD
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'we verified the spike\n'
git -C "$repo" commit -qm base
print -rn -- $'we verified the spike\nunrelated\n' > "$repo/meta/plans/p.md"
git -C "$repo" add "meta/plans/p.md"
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "unrelated edit over incomplete claim in HEAD -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 12. removing a satisfaction field rechecks the remaining claim
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'we verified the spike\nReal path: hooks/x.sh\nStubbed: nothing\n'
git -C "$repo" commit -qm base
print -rn -- $'we verified the spike\nStubbed: nothing\n' > "$repo/meta/plans/p.md"
git -C "$repo" add "meta/plans/p.md"
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "delete Real path leave verified -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 13. removing the claim together with its satisfaction fields leaves no
# claim to reconcile, so the deletion is allowed.
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'we verified the spike\nReal path: hooks/x.sh\nStubbed: nothing\n'
git -C "$repo" commit -qm base
print -rn -- $'replacement text with no claim\n' > "$repo/meta/plans/p.md"
git -C "$repo" add "meta/plans/p.md"
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "delete claim and both fields -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 14. A low-score rename+edit is not a pure rename. The real driver must scan
# its added violating claim rather than skipping every R* status.
repo="$(gt_make_repo)"
mkdir -p "$repo/meta/plans"
for i in {1..20}; do print -r -- "baseline line $i"; done > "$repo/meta/plans/old.md"
git -C "$repo" add "meta/plans/old.md"
git -C "$repo" commit -qm base
git -C "$repo" mv "meta/plans/old.md" "meta/plans/new.md"
{
  for i in {1..20}; do print -r -- "baseline line $i"; done
  for i in {1..8}; do print -r -- "new filler $i"; done
  print -r -- "We verified the pipeline."
} > "$repo/meta/plans/new.md"
git -C "$repo" add -A
rename_status="$(git -C "$repo" diff --cached --name-status -M --no-color | cut -f1)"
case "$rename_status" in
  R100|"") status_ok="no:$rename_status" ;;
  R*) status_ok=yes ;;
  *) status_ok="no:$rename_status" ;;
esac
check "fixture is a low-score rename" "yes" "$status_ok"
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "rename+edit adding claim -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 15. An exact rename from outside the gate's path scope into scope is a new
# scoped document and must be evaluated even though its content is unchanged.
repo="$(gt_make_repo)"
gt_stage "$repo" "notes/p.md" $'We verified the pipeline.\n'
git -C "$repo" commit -qm base
mkdir -p "$repo/meta/plans"
git -C "$repo" mv "notes/p.md" "meta/plans/p.md"
rename_status="$(git -C "$repo" diff --cached --name-status -M --no-color | cut -f1)"
check "rename into scope fixture is R100" "R100" "$rename_status"
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "pure rename into scope with claim -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 16. An exact rename whose source and destination are both already in scope
# changes no gated content and remains allowed.
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/old.md" $'We verified the pipeline.\n'
git -C "$repo" commit -qm base
git -C "$repo" mv "meta/plans/old.md" "meta/plans/new.md"
rename_status="$(git -C "$repo" diff --cached --name-status -M --no-color | cut -f1)"
check "within-scope rename fixture is R100" "R100" "$rename_status"
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "pure rename within scope -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 17. Promoting a dot-prefixed scratch file into a real in-scope doc is new
# gated content: the source was never scanned (scratch skip), so R100 must
# not treat "source in scope" as already-evaluated.
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/.scratch.md" $'We verified the pipeline.\n'
git -C "$repo" commit -qm base
git -C "$repo" mv "meta/plans/.scratch.md" "meta/plans/plan.md"
rename_status="$(git -C "$repo" diff --cached --name-status -M --no-color | cut -f1)"
check "scratch-promote rename fixture is R100" "R100" "$rename_status"
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "pure rename scratch into real with claim -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"; [[ $fail -eq 0 ]]
