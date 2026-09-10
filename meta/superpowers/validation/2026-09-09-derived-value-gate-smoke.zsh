#!/usr/bin/env zsh
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++)); else print -r -- "FAIL - $1 (want $2 got $3)"; ((fail++)); fi }
verdict() { gt_is_deny "$1" && print deny || print allow; }

# 1. duration: epoch-subtraction idiom -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/end-session.md" $'prior_epoch="$(date -u -j -f \'%Y-%m-%dT%H:%M:%SZ\' "$prior_ts" +%s)"\n_DUR="$(( now_epoch - prior_epoch ))"\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "epoch subtraction -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 2. count/tally: majority-vote-by-eye phrase -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/primer.md" $'Pin to the count seen in 2 of 3 runs.\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "pin-to-count phrase -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 3. compare claimed-vs-actual: eyeball-diff phrase -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/doctor.md" $'Does the git log --oneline -5 block inside it match the git log --oneline -5 output above?\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "does-X-match-Y-above -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 4. print-verbatim: reference-doc-as-instruction phrase -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/learning.md" $'Never omit it. Never replace it with paraphrased prose.\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "never-paraphrase phrase -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 5. safe: names a script that owns the computation -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/learning.md" $'Run `bash hooks/lib/learnings-index.sh report`, which prints `MAX <n>`. Use that value.\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "delegates to named script -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 6. escape hatch (decorated) -> allow even with a violation present
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/end-session.md" $'> **Derived-value-gate:** N/A — quoting the old prose in a changelog entry.\nPin to the count seen in 2 of 3 runs.\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "decorated escape -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 7. out-of-scope path (not commands/*.md) -> allow even with a violation present
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/notes.md" $'Pin to the count seen in 2 of 3 runs.\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "out-of-scope path -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 8. dot-prefixed scratch file under commands/ -> allow (skipped)
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/.scratch.md" $'Pin to the count seen in 2 of 3 runs.\n'
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "scratch file skipped -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 9. sanity: the real, current commands/*.md content (post-#54-fix) is clean
repo="$(gt_make_repo)"
REPO_ROOT="${HERE:h:h:h}"
for f in "$REPO_ROOT"/commands/*.md; do
  gt_stage "$repo" "commands/${f:t}" "$(cat "$f")"
done
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "real commands/*.md content -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 10. unrelated edits do not re-trigger a pre-existing derived-value phrase
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/primer.md" $'Pin to the count seen in 2 of 3 runs.\n'
git -C "$repo" commit -qm base
print -rn -- $'Pin to the count seen in 2 of 3 runs.\nUnrelated prose.\n' > "$repo/commands/primer.md"
git -C "$repo" add "commands/primer.md"
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "unrelated edit over existing derived phrase -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 11. a newly added derived-value phrase still denies and cites its document line
repo="$(gt_make_repo)"
gt_stage "$repo" "commands/primer.md" $'Existing introduction.\n'
git -C "$repo" commit -qm base
print -rn -- $'Existing introduction.\nPin to the count seen in 2 of 3 runs.\n' > "$repo/commands/primer.md"
git -C "$repo" add "commands/primer.md"
out="$(gt_run derived-value-gate.sh "$(gt_commit_payload "$repo")")"
check "new derived-value phrase -> deny" "deny" "$(verdict "$out")"
print -r -- "$out" | grep -q 'line 2:' && cited=yes || cited=no
check "new derived-value phrase cites document line" "yes" "$cited"
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"; [[ $fail -eq 0 ]]
