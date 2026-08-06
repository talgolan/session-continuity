#!/usr/bin/env zsh
# Smoke runner for the smoke-gate hook. Hermetic: pipes synthetic PreToolUse
# payloads into hooks/smoke-gate.sh, asserts the JSON (or silence) on stdout.
# See LEARNINGS #7 — the ONLY correct way to verify the gate; never self-scan
# a real spec/plan.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
sg_hook="$repo/hooks/smoke-gate.sh"

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

# plan <content> -> a Write payload to a */plans/*.md path
plan() { printf '{"file_path":"/x/plans/p.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }

# --- MANDATORY honoring (new) --------------------------------------------

# Case 1 (REGRESSION): incidental weak-word near an unrelated thing on one
# line, PLUS an explicit Smoke: MANDATORY line -> allow.
out="$(plan 'Task 8: document the optional mcp.config.json and how to run zsh smoke/run.zsh.\n**Smoke:** MANDATORY — part of done.' | bash "$sg_hook")"
assert "1 incidental co-occurrence + MANDATORY line -> silent" EMPTY "$out"

# Case 2 (NEGATION): smoke + MANDATORY co-occur on one line, weak-words are
# negated ("never deferred/after-merge") -> allow.
out="$(plan 'Smoke is MANDATORY — never deferred/after-merge.' | bash "$sg_hook")"
assert "2 negation line (MANDATORY, never deferred) -> silent" EMPTY "$out"

# --- Genuine weak-smoke denies -------------------------------------------

# Case 3: "smoke test is optional", no MANDATORY marker -> deny, and the deny
# reason echoes the offending line text.
out="$(plan 'The smoke test is optional for this change.' | bash "$sg_hook")"
assert "3 smoke test optional -> deny" 'deny' "$out"
assert "3 deny reason contains offending line" 'The smoke test is optional' "$out"

# Case 4: weak-word ADJACENT to smoke, no MANDATORY -> deny (adjacency scope).
out="$(plan 'We can add a smoke test later — deferred until after-merge.' | bash "$sg_hook")"
assert "4 smoke ... deferred (adjacent) -> deny" 'deny' "$out"

# Case 5 (was the false positive): weak-word FAR from smoke on the same long
# line, no MANDATORY -> allow (adjacency scope kills incidental prose).
out="$(plan 'Document the optional mcp.config.json prerequisite, the activity log feature, and how to run zsh smoke/run.zsh at the end.' | bash "$sg_hook")"
assert "5 weak-word far from smoke, no MANDATORY -> silent" EMPTY "$out"

# --- Escape hatch + branches (existing behavior, keep green) -------------

# Case 6: escape hatch overrides everything -> silent.
out="$(plan 'The smoke test is optional. Smoke: N/A — pure docs change, no binary.' | bash "$sg_hook")"
assert "6 escape hatch -> silent" EMPTY "$out"

# Case 7: no-smoke branch — engine keyword, no smoke mention at all -> deny.
out="$(plan 'This plan rebuilds the binary and restarts the daemon.' | bash "$sg_hook")"
assert "7 engine keyword, no smoke -> deny" 'deny' "$out"

# Case 8: mentions smoke, no weak-word, no MANDATORY -> silent (nothing wrong).
out="$(plan 'Smoke section 01 asserts the config file was written correctly.' | bash "$sg_hook")"
assert "8 smoke, no weak-word -> silent" EMPTY "$out"

# Case 9: non-plan path -> silent (out of scope).
out="$(printf '{"file_path":"/x/src/foo.ts","tool_name":"Write","tool_input":{"content":"The smoke test is optional."}}' | bash "$sg_hook")"
assert "9 non-plan path -> silent" EMPTY "$out"

# Case 10: deny payload is valid hook JSON (LEARNINGS #1 contract).
out="$(plan 'The smoke test is optional.' | bash "$sg_hook")"
assert "10 deny carries hookSpecificOutput" 'hookSpecificOutput' "$out"
assert "10 deny names permissionDecision" 'permissionDecision' "$out"

# Case 11: Edit new_string path also gated (weak-smoke, no MANDATORY) -> deny.
out="$(printf '{"file_path":"/x/plans/p.md","tool_name":"Edit","tool_input":{"new_string":"The smoke check is nice-to-have."}}' | bash "$sg_hook")"
assert "11 Edit new_string weak-smoke -> deny" 'deny' "$out"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
