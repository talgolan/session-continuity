#!/usr/bin/env zsh
# Smoke runner for the proven-gate hook. Hermetic: pipes synthetic PreToolUse
# payloads into hooks/proven-gate.sh, asserts the JSON (or silence) on stdout.
# No containers, no live session. See LEARNINGS #7 — this is the ONLY correct
# way to verify the gate; never self-scan a real spec/plan.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
pg_hook="$repo/hooks/proven-gate.sh"

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

# spec <content> -> a Write payload to a */specs/*.md path
spec() { printf '{"file_path":"/x/specs/s.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }

# Case 1: claim-word + both fields filled -> silent (allow)
out="$(spec 'Approach is proven. Real path: ran src/egressProxy.ts CONNECT auth. Stubbed: nothing.' | bash "$pg_hook")"
assert "1 proven + both fields -> silent" EMPTY "$out"

# Case 2: claim-word, no fields -> deny
out="$(spec 'Approach is proven, option A.' | bash "$pg_hook")"
assert "2 proven, no fields -> deny" 'deny' "$out"

# Case 3: verified + Real path only (no Stubbed) -> deny
out="$(spec 'Verified end to end. Real path: ran the real binary.' | bash "$pg_hook")"
assert "3 verified, Real path only -> deny" 'deny' "$out"

# Case 4: spike conclusive + Stubbed only (no Real path) -> deny
out="$(spec 'Spike conclusive. Stubbed: a no-auth /tmp proxy.' | bash "$pg_hook")"
assert "4 spike conclusive, Stubbed only -> deny" 'deny' "$out"

# Case 5: claim-word + escape hatch -> silent
out="$(spec 'This is proven upstream. Proven-gate: N/A — quoting the vendor doc.' | bash "$pg_hook")"
assert "5 escape hatch overrides -> silent" EMPTY "$out"

# Case 6: non-spec path with claim-word, no fields -> silent (out of scope)
out="$(printf '{"file_path":"/x/src/foo.ts","tool_name":"Write","tool_input":{"content":"this is proven, no fields"}}' | bash "$pg_hook")"
assert "6 non-spec path -> silent" EMPTY "$out"

# Case 7: spec file, no claim-word -> silent
out="$(spec 'Renamed a variable in the parser.' | bash "$pg_hook")"
assert "7 no claim-word -> silent" EMPTY "$out"

# Case 8: word-boundary guard — improven / unproven must NOT trigger
out="$(spec 'The approach is unproven and improven, needs work.' | bash "$pg_hook")"
assert "8 substring improven/unproven -> silent" EMPTY "$out"

# Case 9: dropped word — confirmed must NOT trigger
out="$(spec 'Confirmed the user choice in the meeting.' | bash "$pg_hook")"
assert "9 confirmed -> silent" EMPTY "$out"

# Case 10: deny payload is valid hook JSON (LEARNINGS #1 contract)
out="$(spec 'Approach is proven.' | bash "$pg_hook")"
assert "10 deny carries hookSpecificOutput" 'hookSpecificOutput' "$out"
assert "10 deny names permissionDecision" 'permissionDecision' "$out"

# Case 11: Edit tool (new_string) path also gated
out="$(printf '{"file_path":"/x/plans/p.md","tool_name":"Edit","tool_input":{"new_string":"now proven, option A"}}' | bash "$pg_hook")"
assert "11 Edit new_string on plan path -> deny" 'deny' "$out"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
