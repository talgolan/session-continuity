#!/usr/bin/env zsh
# Hermetic self-test for hooks/lib/gate-common.sh.
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
HOOKS="${HERE:h:h:h}/hooks"   # meta/superpowers/validation -> repo root -> hooks

pass=0; fail=0
check() {  # <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++))
  else print -r -- "FAIL - $1 (expected [$2] got [$3])"; ((fail++)); fi
}

# gate_command with trailing "description" field
payload='{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":"git commit -m test","description":"ignored"}}'
out="$(bash -c 'export GATE_PAYLOAD='"'"''"$payload"''"'"'; source "'"$HOOKS"'/lib/gate-common.sh"; gate_command')"
check "gate_command stops at closing quote (no description)" "git commit -m test" "$out"

# gate_is_scratch
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_is_scratch ".x.md" && echo yes || echo no')"
check "dot-prefixed is scratch" "yes" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_is_scratch "a/b/plan.md" && echo yes || echo no')"
check "normal not scratch" "no" "$out"

# gate_has_escape: bare and decorated both match; absent does not
esc_bare='Proven-gate: N/A — reason here'
esc_dec='> **Proven-gate:** N/A — reason here'
none='no hatch on this line'
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_has_escape "'"$esc_bare"'" "Proven-gate" && echo yes || echo no')"
check "bare escape matches" "yes" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_has_escape "'"$esc_dec"'" "Proven-gate" && echo yes || echo no')"
check "decorated escape matches" "yes" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_has_escape "'"$none"'" "Proven-gate" && echo yes || echo no')"
check "no escape does not match" "no" "$out"

# staged enumeration + blob read against a real temp repo
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/x.md" $'line one\nRealword\n'
files="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_CWD="'"$repo"'"; gate_staged_files')"
check "staged file listed" "meta/plans/x.md" "$files"
blob="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_CWD="'"$repo"'"; gate_staged_blob "meta/plans/x.md"' | head -1)"
check "staged blob read" "line one" "$blob"
gt_cleanup "$repo"

# _GT_HOOKS_DIR is captured at source time and resolves to repo root/hooks
hooks_dir_test="$(zsh -c 'source "'"$HERE"'/lib/gate-test-common.zsh"; echo "$_GT_HOOKS_DIR"')"
real_hooks="$HOOKS"
check "_GT_HOOKS_DIR resolves correctly" "$real_hooks" "$hooks_dir_test"

# Verify the resolved directory contains hooks.json (exists at repo root/hooks/)
if [[ -f "$hooks_dir_test/hooks.json" ]]; then
  check "_GT_HOOKS_DIR contains hooks.json" "true" "true"
  ((pass++))
else
  print -r -- "FAIL - _GT_HOOKS_DIR should contain hooks.json"
  ((fail++))
fi

print -r -- "---"; print -r -- "pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
