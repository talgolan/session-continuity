#!/usr/bin/env zsh
# Smoke runner for the evidence-gate hook. Hermetic: pipes synthetic
# PreToolUse payloads into hooks/evidence-gate.sh, asserts JSON (or silence).
# See LEARNINGS #7 — the ONLY correct way to verify the gate; never self-scan
# a real spec/plan.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
eg_hook="$repo/hooks/evidence-gate.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

# assert <desc> <expected-substr-or-EMPTY> <actual>
assert() {
  local desc="$1" exp="$2" act="$3"
  if [[ "$exp" == "EMPTY" ]]; then
    [[ -z "$act" ]] && ok "$desc" || bad "$desc (expected empty, got: $act)"
  else
    [[ "$act" == *"$exp"* ]] && ok "$desc" || bad "$desc (expected '*$exp*', got: $act)"
  fi
}

# spec <content> -> a Write payload to a */plans/*.md path
spec() { printf '{"file_path":"/x/plans/p.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }

# Case 1: teardown mentioned + preserve-before-teardown safeguard -> silent
out="$(spec 'Smoke section 01: on failure, surface the diagnostic into the log before teardown. Teardown-on-pass is fine.' | bash "$eg_hook")"
assert "1 teardown + preserve-before -> silent" EMPTY "$out"

# Case 2: teardown mentioned, no safeguard -> deny
out="$(spec 'Smoke section 01: runs the container then does cleanup at the end.' | bash "$eg_hook")"
assert "2 teardown, no safeguard -> deny" 'deny' "$out"

# Case 3: poll/wait mentioned + dual-signal safeguard -> silent
out="$(spec 'Smoke section 02: poll_until the readiness probe and the failure marker, timeout 60s.' | bash "$eg_hook")"
assert "3 poll + dual-signal -> silent" EMPTY "$out"

# Case 4: poll/wait mentioned, success-only -> deny
out="$(spec 'Smoke section 02: wait_for the service to come up, timeout 60s.' | bash "$eg_hook")"
assert "4 poll, success-only -> deny" 'deny' "$out"

# Case 5: escape hatch overrides teardown check -> silent
out="$(spec 'Smoke section 01: does cleanup at the end. Evidence-gate: N/A — never tears down on failure.' | bash "$eg_hook")"
assert "5 escape hatch -> silent" EMPTY "$out"

# Case 6: no mention of smoke at all -> silent (out of scope)
out="$(spec 'This plan renames a function and updates its callers.' | bash "$eg_hook")"
assert "6 no smoke mention -> silent" EMPTY "$out"

# Case 7: mentions smoke, no teardown, no poll -> silent (nothing to flag)
out="$(spec 'Smoke section 01 asserts the config file was written correctly.' | bash "$eg_hook")"
assert "7 smoke, no teardown/poll -> silent" EMPTY "$out"

# Case 8: non-plan path -> silent (out of scope)
out="$(printf '{"file_path":"/x/src/foo.ts","tool_name":"Write","tool_input":{"content":"Smoke section does cleanup at the end."}}' | bash "$eg_hook")"
assert "8 non-plan path -> silent" EMPTY "$out"

# Case 9: deny payload is valid hook JSON (LEARNINGS #1 contract)
out="$(spec 'Smoke section: cleanup at the end.' | bash "$eg_hook")"
assert "9 deny carries hookSpecificOutput" 'hookSpecificOutput' "$out"
assert "9 deny names permissionDecision" 'permissionDecision' "$out"

# Case 10: Edit new_string path also gated
out="$(printf '{"file_path":"/x/specs/s.md","tool_name":"Edit","tool_input":{"new_string":"Smoke: teardown runs after every section, pass or fail."}}' | bash "$eg_hook")"
assert "10 Edit new_string, teardown no safeguard -> deny" 'deny' "$out"

# Case 11: both teardown and poll gaps present -> deny fires on the first
# checked (teardown), still a single deny (permission decisions are terminal)
out="$(spec 'Smoke section: cleanup at the end, and wait_for readiness with a plain timeout.' | bash "$eg_hook")"
assert "11 both gaps -> deny" 'deny' "$out"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
