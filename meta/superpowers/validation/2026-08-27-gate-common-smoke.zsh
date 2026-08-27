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

print -r -- "---"; print -r -- "pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
