#!/usr/bin/env zsh
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++)); else print -r -- "FAIL - $1 (want $2 got $3)"; ((fail++)); fi }
verdict() { gt_is_deny "$1" && print deny || print allow; }

repo="$(gt_make_repo)"

# 1. Bare rm -> deny
out="$(gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" "rm -rf /tmp/x")")"
check "bare rm -> deny" "deny" "$(verdict "$out")"

# 2. Bare cp -> deny
out="$(gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" "cp a b")")"
check "bare cp -> deny" "deny" "$(verdict "$out")"

# 3. Bare mv -> deny
out="$(gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" "mv a b")")"
check "bare mv -> deny" "deny" "$(verdict "$out")"

# 4. Backslash-escaped -> allow
out="$(gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" '\rm -rf /tmp/x')")"
check "backslash-escaped rm -> allow" "allow" "$(verdict "$out")"

# 5. command-prefixed -> allow
out="$(gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" "command rm -rf /tmp/x")")"
check "command-prefixed rm -> allow" "allow" "$(verdict "$out")"

# 6. Unrelated command with cp/mv/rm as a substring of a longer word -> allow
out="$(gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" "rmdir /tmp/empty")")"
check "rmdir is not rm -> allow" "allow" "$(verdict "$out")"
out2="$(gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" "cpio -o < list")")"
check "cpio is not cp -> allow" "allow" "$(verdict "$out2")"

# 7. Full-path invocation bypasses the alias already -> allow
out="$(gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" "/bin/rm -rf /tmp/x")")"
check "/bin/rm full path -> allow" "allow" "$(verdict "$out")"

# 8. Bare rm as the SECOND segment of a chained command -> deny
out="$(gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" "echo hi && rm -rf /tmp/x")")"
check "bare rm as second chained segment -> deny" "deny" "$(verdict "$out")"

# 9. Escaped rm as the second segment, unescaped ls elsewhere -> allow
out="$(gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" 'ls -la && \rm -rf /tmp/x')")"
check "chained but escaped rm -> allow" "allow" "$(verdict "$out")"

# 10. Bare rm on its OWN LINE of a multi-line command (no ; or && before it)
#     -> deny. Regression test: an earlier draft collapsed newlines to
#     spaces before splitting on ; && || |, which merged this line into the
#     tail of the previous one and silently missed it — see the comment in
#     cmrg_offending_segment.
multiline="$(print -r -- $'echo start\nrm -rf /tmp/x')"
out="$(gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" "$multiline")")"
check "bare rm on its own line of a multi-line command -> deny" "deny" "$(verdict "$out")"

# 11. No cp/mv/rm at all -> allow
out="$(gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" "git status")")"
check "unrelated command -> allow" "allow" "$(verdict "$out")"

# 12. Escape hatch bypasses a real bare-rm deny.
out="$(SESSION_CONTINUITY_SKIP_CP_MV_RM_GATE=1 gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" "rm -rf /tmp/x")")"
check "escape hatch bypasses bare rm -> allow" "allow" "$(verdict "$out")"

# 13. Bug report repro: quoted text containing " | rm " is not a real pipe,
# but the splitter has no quote-awareness and misdetects the trailing
# `rm b"` as a bare rm invocation. No way for the user to \-escape text
# inside someone else's string, so this denies without the escape hatch and
# is allowed through with it.
out="$(gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" 'echo "a | rm b"')")"
check "quoted text false positive denies without escape hatch" "deny" "$(verdict "$out")"
out="$(SESSION_CONTINUITY_SKIP_CP_MV_RM_GATE=1 gt_run cp-mv-rm-gate.sh "$(gt_commit_payload "$repo" 'echo "a | rm b"')")"
check "quoted text false positive allowed with escape hatch" "allow" "$(verdict "$out")"

gt_cleanup "$repo"
print -r -- "---"; print -r -- "pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
