#!/usr/bin/env zsh
# Smoke runner for the occurrence-gate hook. Hermetic: pipes synthetic
# PreToolUse payloads into hooks/occurrence-gate.sh, asserts JSON (or silence).
# See LEARNINGS #7 — the ONLY correct way to verify the gate; never self-scan a
# real LEARNINGS.md.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
og_hook="$repo/hooks/occurrence-gate.sh"

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

# learn <content> -> Write payload to a canonical LEARNINGS.md path
learn() { printf '{"file_path":"/x/.session-continuity/LEARNINGS.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }

# Case 1: occurrence 2 + invariant -> silent (allow)
out="$(learn 'Occurrence count: 2 of 2\nInvariant: host-global port implies host-global secret.' | bash "$og_hook")"
assert "1 occ2 + invariant -> silent" EMPTY "$out"

# Case 2: occurrence 2, no invariant -> deny
out="$(learn 'Occurrence count: 2 of 2\nFix: reaped the stale port again.' | bash "$og_hook")"
assert "2 occ2, no invariant -> deny" 'deny' "$out"

# Case 3: occurrence 1, no invariant -> silent (nothing owed)
out="$(learn 'Occurrence count: 1 of 2\nFirst time we hit this.' | bash "$og_hook")"
assert "3 occ1 -> silent" EMPTY "$out"

# Case 4: no occurrence line -> silent (ordinary entry)
out="$(learn 'A normal learning with a Fix and a Symptom.' | bash "$og_hook")"
assert "4 no occurrence line -> silent" EMPTY "$out"

# Case 5: occurrence 3 of 5, no invariant -> deny (N>=2)
out="$(learn 'Occurrence count: 3 of 5\nYet another trigger patch.' | bash "$og_hook")"
assert "5 occ3, no invariant -> deny" 'deny' "$out"

# Case 6: escape hatch overrides -> silent
out="$(learn 'Occurrence count: 2 of 2\nOccurrence-gate: N/A — quoting #149 in a glossary.' | bash "$og_hook")"
assert "6 escape hatch -> silent" EMPTY "$out"

# Case 7: non-LEARNINGS path -> silent (out of scope)
out="$(printf '{"file_path":"/x/specs/s.md","tool_name":"Write","tool_input":{"content":"Occurrence count: 2 of 2\\nno invariant"}}' | bash "$og_hook")"
assert "7 non-LEARNINGS path -> silent" EMPTY "$out"

# Case 8: Edit new_string on a LEARNINGS path -> deny
out="$(printf '{"file_path":"/x/.session-continuity/LEARNINGS.md","tool_name":"Edit","tool_input":{"new_string":"Occurrence count: 2 of 2\\nFix only, no invariant"}}' | bash "$og_hook")"
assert "8 Edit new_string occ2, no invariant -> deny" 'deny' "$out"

# Case 9: deny payload is valid hook JSON (LEARNINGS #1 contract)
out="$(learn 'Occurrence count: 2 of 2\nno invariant here.' | bash "$og_hook")"
assert "9 deny carries hookSpecificOutput" 'hookSpecificOutput' "$out"
assert "9 deny names permissionDecision" 'permissionDecision' "$out"

# Case 10: Invariant label present but value EMPTY -> deny
out="$(learn 'Occurrence count: 2 of 2\nInvariant: \nFix: patched it.' | bash "$og_hook")"
assert "10 empty Invariant value -> deny" 'deny' "$out"

# Case 11: legacy docs/LEARNINGS.md path -> deny (dual-path scope)
out="$(printf '{"file_path":"/x/docs/LEARNINGS.md","tool_name":"Write","tool_input":{"content":"Occurrence count: 2 of 2\\nno invariant"}}' | bash "$og_hook")"
assert "11 legacy docs path occ2, no invariant -> deny" 'deny' "$out"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
