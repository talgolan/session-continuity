#!/usr/bin/env zsh
# Smoke runner for the flaky-gate hook. Hermetic: pipes synthetic PreToolUse
# payloads (Bash git-commit and Write/Edit LEARNINGS.md shapes) into
# hooks/flaky-gate.sh, asserts JSON (or silence). See LEARNINGS #7 — the
# ONLY correct way to verify the gate; never self-scan real commits/LEARNINGS.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
fg_hook="$repo/hooks/flaky-gate.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

assert() {
  local desc="$1" exp="$2" act="$3"
  if [[ "$exp" == "EMPTY" ]]; then
    [[ -z "$act" ]] && ok "$desc" || bad "$desc (expected empty, got: $act)"
  else
    [[ "$act" == *"$exp"* ]] && ok "$desc" || bad "$desc (expected '*$exp*', got: $act)"
  fi
}

# commit <msg> -> a Bash git-commit payload
commit() { printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m \\"%s\\""}}' "$1"; }
# learn <content> -> a Write payload to a canonical LEARNINGS.md path
learn() { printf '{"file_path":"/x/.session-continuity/LEARNINGS.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }

# Case 1: commit calls it flaky, no mechanism -> deny
out="$(commit 'fix: retry the flaky upload test' | bash "$fg_hook")"
assert "1 commit flaky, no mechanism -> deny" 'deny' "$out"

# Case 2: commit calls it flaky, names mechanism -> silent
out="$(commit 'fix: upload race (Mechanism: shared tmp dir across parallel runs)' | bash "$fg_hook")"
assert "2 commit flaky + mechanism -> silent" EMPTY "$out"

# Case 3: LEARNINGS entry says transient, no mechanism -> deny
out="$(learn 'The build failed again, looks transient.' | bash "$fg_hook")"
assert "3 learnings transient, no mechanism -> deny" 'deny' "$out"

# Case 4: LEARNINGS entry says CDN blip, no mechanism -> deny
out="$(learn 'Download failed, probably a CDN blip.' | bash "$fg_hook")"
assert "4 learnings CDN blip, no mechanism -> deny" 'deny' "$out"

# Case 5: LEARNINGS entry names mechanism -> silent
out="$(learn 'The download failed twice. Mechanism: proxy secret mismatch from a squatting helper on the same port.' | bash "$fg_hook")"
assert "5 learnings + mechanism -> silent" EMPTY "$out"

# Case 6: escape hatch overrides -> silent
out="$(learn 'This entry quotes a vendor report calling it flaky. Flaky-gate: N/A — quoting a vendor report.' | bash "$fg_hook")"
assert "6 escape hatch -> silent" EMPTY "$out"

# Case 7: commit with no flaky/transient language -> silent
out="$(commit 'fix: null pointer in the parser' | bash "$fg_hook")"
assert "7 no flaky language -> silent" EMPTY "$out"

# Case 8: non-commit Bash command -> silent (out of scope)
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"grep flaky test.log"}}' | bash "$fg_hook")"
assert "8 non-commit bash -> silent" EMPTY "$out"

# Case 9: non-LEARNINGS Write path -> silent (out of scope)
out="$(printf '{"file_path":"/x/specs/s.md","tool_name":"Write","tool_input":{"content":"This test is flaky."}}' | bash "$fg_hook")"
assert "9 non-LEARNINGS path -> silent" EMPTY "$out"

# Case 10: deny payload is valid hook JSON (LEARNINGS #1 contract)
out="$(commit 'fix: the flaky test' | bash "$fg_hook")"
assert "10 deny carries hookSpecificOutput" 'hookSpecificOutput' "$out"
assert "10 deny names permissionDecision" 'permissionDecision' "$out"

# Case 11: Edit new_string on LEARNINGS path also gated
out="$(printf '{"file_path":"/x/docs/LEARNINGS.md","tool_name":"Edit","tool_input":{"new_string":"Still transient, re-ran and it passed."}}' | bash "$fg_hook")"
assert "11 Edit new_string transient, no mechanism -> deny" 'deny' "$out"

# Case 12: word-boundary guard — "flakiness" as a topic word in a Mechanism
# discussion should not be blocked once Mechanism: is present
out="$(learn 'Discussing flaky test theory. Mechanism: none — this entry is about the concept, not a real failure.' | bash "$fg_hook")"
assert "12 flaky + mechanism present -> silent" EMPTY "$out"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
