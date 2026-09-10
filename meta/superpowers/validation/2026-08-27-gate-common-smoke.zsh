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

# gate_hatch_class: strict accepted grammar, broader near-miss recognition.
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_hatch_class "Proven-gate: N/A — ok" "Proven-gate"')"
check "hatch class accepted" "accepted" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_hatch_class "Proven-gate: N/A - bad" "Proven-gate"')"
check "hatch class near-miss single hyphen" "near-miss" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_hatch_class "no hatch" "Proven-gate"')"
check "hatch class absent" "absent" "$out"

# gate_mask_escape: blanks this gate's own hatch line so the claim scan can
# never be triggered by the line that exempts the doc. Blanks rather than
# deletes, so reported line numbers still match the real file.
mask() {  # <text> <Label> -> masked text, newlines rendered as | for comparison
  MASK_IN="$1" bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_mask_escape "$MASK_IN" "'"$2"'"' | tr '\n' '|'
}
out="$(mask $'before\nProven-gate: N/A — reason here\nafter' "Proven-gate")"
check "well-formed hatch blanked, neighbours kept" "before||after|" "$out"
out="$(mask $'before\n> **Proven-gate:** N/A — reason\nafter' "Proven-gate")"
check "decorated hatch blanked" "before||after|" "$out"
# The load-bearing case: a hatch gate_has_escape REJECTS (no dash/reason) must
# still be masked, or it becomes the sole claim that condemns the doc.
out="$(mask $'before\nProven-gate: N/A\nafter' "Proven-gate")"
check "malformed hatch blanked too" "before||after|" "$out"
out="$(mask $'plain one\nplain two' "Proven-gate")"
check "no hatch leaves text untouched" "plain one|plain two|" "$out"
out="$(mask $'Smoke: N/A — not a binary plan\nkeep' "Proven-gate")"
check "another gate's hatch is not masked" "Smoke: N/A — not a binary plan|keep|" "$out"

# gate_first_match: word-boundary first hit, reported with its real line number
first() {  # <text> <ere> -> "N:line"
  MASK_IN="$1" bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_first_match "$MASK_IN" "'"$2"'"'
}
out="$(first $'nothing here\nwe verified it\nlater proven' 'proven|verified')"
check "first match reports real line number" "2:we verified it" "$out"
out="$(first $'unproven only' 'proven|verified')"
check "word boundary respected, no match is empty" "" "$out"

# staged enumeration + blob read against a real temp repo
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/x.md" $'line one\nRealword\n'
files="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_CWD="'"$repo"'"; gate_staged_files')"
check "staged file listed" "meta/plans/x.md" "$files"
blob="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_CWD="'"$repo"'"; gate_staged_blob "meta/plans/x.md"' | head -1)"
check "staged blob read" "line one" "$blob"
gt_cleanup "$repo"

repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/e.md" $'Proven-gate: N/A — skip me\nwe verified nothing\n'
hits="$(print -rn -- "$(gt_commit_payload "$repo")" | bash -c '
  source "'"$HOOKS"'/lib/gate-common.sh"
  GATE_LABEL="Proven-gate"
  GATE_CHECK_HITS=0
  gate_in_scope() { case "$1" in *.md) return 0;; *) return 1;; esac; }
  gate_check() { GATE_CHECK_HITS=$((GATE_CHECK_HITS+1)); }
  gate_load
  gate_scan_staged gate_in_scope gate_check
  printf "%s" "$GATE_CHECK_HITS"
')"
check "accepted hatch skips check_fn" "0" "$hits"
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

delta_added() {
  local repo="$1" relpath="$2"
  bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_CWD="'"$repo"'"; gate_staged_delta "'"$relpath"'"; printf "%s" "$GATE_DELTA_ADDED"'
}
delta_status() {
  local repo="$1" relpath="$2"
  bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_CWD="'"$repo"'"; gate_staged_status "'"$relpath"'"'
}

repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/d.md" $'keep\nsmoke here\n'
git -C "$repo" commit -qm base
print -rn -- $'keep\nsmoke here\nnew line\n' > "$repo/meta/plans/d.md"
git -C "$repo" add "meta/plans/d.md"
out="$(delta_added "$repo" "meta/plans/d.md")"
check "edit delta is added lines only" "new line" "$out"
gt_cleanup "$repo"

repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/n.md" $'a\nb\n'
out="$(delta_added "$repo" "meta/plans/n.md" | tr '\n' '|')"
check "new file delta is all lines" "a|b|" "$out"
gt_cleanup "$repo"

repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/r.md" $'body\n'
git -C "$repo" commit -qm base
git -C "$repo" mv meta/plans/r.md meta/plans/s.md
st="$(delta_status "$repo" "meta/plans/s.md")"
case "$st" in R*) st_ok=yes ;; *) st_ok="no:$st" ;; esac
check "pure rename status is R*" "yes" "$st_ok"
gt_cleanup "$repo"

repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/c.md" $'a\n'
git -C "$repo" commit -qm base
print -rn -- $'a\ncolor line\n' > "$repo/meta/plans/c.md"
git -C "$repo" add "meta/plans/c.md"
git -C "$repo" config color.diff always
out="$(delta_added "$repo" "meta/plans/c.md")"
check "color.diff=always still yields plain added line" "color line" "$out"
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
