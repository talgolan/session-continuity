#!/usr/bin/env zsh
# Hermetic self-test for hooks/commit-gate-multiplexer.sh.
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++)); else print -r -- "FAIL - $1 (want $2 got $3)"; ((fail++)); fi }
verdict() { gt_is_deny "$1" && print deny || print allow; }

# 1. A clean commit with no gate-worthy content allows silently.
repo="$(gt_make_repo)"
gt_stage "$repo" "src/x.txt" $'plain file\n'
out="$(gt_run commit-gate-multiplexer.sh "$(gt_commit_payload "$repo")")"
check "no violations -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 2. A proven-gate violation (single gate) still denies through the multiplexer.
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'We verified the pipeline works end to end.\n'
out="$(gt_run commit-gate-multiplexer.sh "$(gt_commit_payload "$repo")")"
check "proven-gate violation via multiplexer -> deny" "deny" "$(verdict "$out")"
check "denial names Proven-gate" "yes" "$(print -rn -- "$out" | grep -qi 'Real path' && print yes || print no)"
gt_cleanup "$repo"

# 3. A flaky-gate violation (different gate) also denies through the multiplexer.
repo="$(gt_make_repo)"
gt_stage "$repo" ".session-continuity/LEARNINGS.md" $'This was a flaky test.\n'
out="$(gt_run commit-gate-multiplexer.sh "$(gt_commit_payload "$repo")")"
check "flaky-gate violation via multiplexer -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 4. Ordering: a commit that trips BOTH flaky-gate and proven-gate reports the
#    earlier one in hooks.json's original array order (flaky before proven) —
#    locks in the documented "first denier wins" behavior change.
repo="$(gt_make_repo)"
gt_stage "$repo" ".session-continuity/LEARNINGS.md" $'This was a flaky test.\n'
gt_stage "$repo" "meta/plans/p.md" $'We verified the pipeline works end to end.\n'
out="$(gt_run commit-gate-multiplexer.sh "$(gt_commit_payload "$repo")")"
check "both violations present -> deny" "deny" "$(verdict "$out")"
check "flaky-gate (earlier in order) wins over proven-gate" "yes" \
  "$(print -rn -- "$out" | grep -qi 'Mechanism' && print yes || print no)"
gt_cleanup "$repo"

# 5. Non-commit Bash command allows without running any gate.
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'We verified the pipeline works end to end.\n'
out="$(gt_run commit-gate-multiplexer.sh "$(gt_commit_payload "$repo" "git status")")"
check "non-commit command -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 6. Advisory-only path: pre-commit-check's primer nudge still fires when no
#    gate denies but the primer is unstaged.
repo="$(gt_make_repo)"
mkdir -p "$repo/.session-continuity"
gt_stage "$repo" ".session-continuity/SESSION_PRIMER.md" $'primer\n'
git -C "$repo" commit -qm base
gt_stage "$repo" "src/code.js" $'console.log(1);\n'
out="$(gt_run commit-gate-multiplexer.sh "$(gt_commit_payload "$repo")")"
check "primer nudge still fires with no gate violation" "yes" \
  "$(print -rn -- "$out" | grep -q 'not staged for this commit' && print yes || print no)"
gt_cleanup "$repo"

# 7. Single git diff --cached --name-status call for the whole multiplexer
#    run, even though 7 different gates each call gate_scan_staged — the
#    actual perf claim this task exists to deliver.
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/a.md" $'first\n'
gt_stage "$repo" "commands/b.md" $'second\n'
mkdir -p "$repo/bin"
real_git="$(command -v git)"
count_file="$repo/name-status.count"
cat > "$repo/bin/git" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *" --name-status "*) printf 'probe\n' >> "$GIT_COUNT_FILE" ;;
esac
exec "$GIT_REAL" "$@"
EOF
chmod +x "$repo/bin/git"
HOOKS="${HERE:h:h:h}/hooks"
PATH="$repo/bin:$PATH" GIT_REAL="$real_git" GIT_COUNT_FILE="$count_file" \
  bash "$HOOKS/commit-gate-multiplexer.sh" <<< "$(gt_commit_payload "$repo")" >/dev/null
probe_count="$(wc -l < "$count_file" | tr -d ' ')"
check "multiplexer runs name-status once across all 7 gates" "1" "$probe_count"
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
