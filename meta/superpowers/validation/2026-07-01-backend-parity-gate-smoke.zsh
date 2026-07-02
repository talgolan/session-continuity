#!/usr/bin/env zsh
# Smoke runner for the backend-parity-gate hook. Hermetic: pipes synthetic
# PreToolUse payloads into hooks/backend-parity-gate.sh, asserts JSON (or
# silence). See LEARNINGS #7 — the ONLY correct way to verify the gate;
# never self-scan a real plan.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
bp_hook="$repo/hooks/backend-parity-gate.sh"

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

# plan <content> -> a Write payload to a */plans/*.md path
plan() { printf '{"file_path":"/x/plans/p.md","tool_input":{"content":"%s"}}' "$1"; }

# Case 1: mentions backends + two named backends -> silent
out="$(plan 'Smoke covers both backends: Docker and Apple container parity sections.' | bash "$bp_hook")"
assert "1 backends + 2 names -> silent" EMPTY "$out"

# Case 2: mentions backends, only one named -> deny
out="$(plan 'Smoke covers backend parity, tested against Docker.' | bash "$bp_hook")"
assert "2 backends, 1 name -> deny" 'deny' "$out"

# Case 3: mentions backends, zero named -> deny
out="$(plan 'This plan needs full backend parity coverage in smoke.' | bash "$bp_hook")"
assert "3 backends, 0 names -> deny" 'deny' "$out"

# Case 4: no mention of backend(s) at all -> silent (out of scope)
out="$(plan 'This plan adds a new CLI flag and a unit test.' | bash "$bp_hook")"
assert "4 no backend mention -> silent" EMPTY "$out"

# Case 5: escape hatch overrides -> silent
out="$(plan 'Backend parity is required in general. Backend-parity: N/A — this project only ships one engine.' | bash "$bp_hook")"
assert "5 escape hatch -> silent" EMPTY "$out"

# Case 6: two different named engines (podman + docker) -> silent
out="$(plan 'Backend coverage: Podman and Docker both smoke-tested.' | bash "$bp_hook")"
assert "6 podman+docker -> silent" EMPTY "$out"

# Case 7: non-plan path -> silent (out of scope)
out="$(printf '{"file_path":"/x/src/foo.ts","tool_input":{"content":"backend parity only on Docker"}}' | bash "$bp_hook")"
assert "7 non-plan path -> silent" EMPTY "$out"

# Case 8: deny payload is valid hook JSON (LEARNINGS #1 contract)
out="$(plan 'Backend parity, Docker only.' | bash "$bp_hook")"
assert "8 deny carries hookSpecificOutput" 'hookSpecificOutput' "$out"
assert "8 deny names permissionDecision" 'permissionDecision' "$out"

# Case 9: Edit new_string path also gated
out="$(printf '{"file_path":"/x/plans/2026-07-01-plan.md","tool_input":{"new_string":"Smoke needs backend parity, only Apple covered."}}' | bash "$bp_hook")"
assert "9 Edit new_string, 1 name -> deny" 'deny' "$out"

# Case 10: basename *plan*.md outside a plans/ dir also in scope
out="$(printf '{"file_path":"/x/notes/my-plan-draft.md","tool_input":{"content":"backend parity coverage, Docker only"}}' | bash "$bp_hook")"
assert "10 *plan*.md basename, 1 name -> deny" 'deny' "$out"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
