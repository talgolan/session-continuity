#!/usr/bin/env zsh
# Smoke runner for the fire-before-action hooks. Hermetic: builds a tmp repo
# with a crafted LEARNINGS.md, pipes synthetic PreToolUse payloads into each
# hook script, asserts the JSON (or silence) on stdout. No containers.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
ls_hook="$repo/hooks/learnings-surface.sh"
sg_hook="$repo/hooks/smoke-gate.sh"

pass=0; fail=0
ok()   { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad()  { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

# assert <desc> <expected-substr-or-EMPTY> <actual>
assert() {
  local desc="$1" exp="$2" act="$3"
  if [[ "$exp" == "EMPTY" ]]; then
    [[ -z "$act" ]] && ok "$desc" || bad "$desc (expected empty, got: $act)"
  else
    [[ "$act" == *"$exp"* ]] && ok "$desc" || bad "$desc (expected '*$exp*', got: $act)"
  fi
}

tmp="$(mktemp -d)"
mkdir -p "$tmp/.session-continuity"
cat > "$tmp/.session-continuity/LEARNINGS.md" <<'EOF'
### 124. smoke SUT dist != local bin
Trigger: Bash /smoke|run\.zsh/
**The trap.** stale binary.

### 200. editing config schema
Trigger: Edit /settings\.json/
**The trap.** enum drift.

### 7. no trigger here
**The trap.** never fires.
EOF

# --- learnings-surface ---
out="$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"./run.zsh"}}' "$tmp" | bash "$ls_hook")"
assert "ls: Bash match surfaces #124" '#124' "$out"
assert "ls: response is allow"        'allow' "$out"

out="$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"ls -la"}}' "$tmp" | bash "$ls_hook")"
assert "ls: no match -> silent" EMPTY "$out"

out="$(printf '{"cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"/x/settings.json","new_string":"x"}}' "$tmp" | bash "$ls_hook")"
assert "ls: Edit match surfaces #200" '#200' "$out"

out="$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"infocmp settings.json"}}' "$tmp" | bash "$ls_hook")"
assert "ls: Edit-tool trigger does NOT fire for Bash" EMPTY "$out"

# entry #7 (no Trigger) must never appear
out="$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"never fires here"}}' "$tmp" | bash "$ls_hook")"
assert "ls: untagged entry silent" EMPTY "$out"

# --- smoke-gate ---
plan() { printf '{"file_path":"/x/plans/p.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }

out="$(plan 'Task 7: smoke runner (optional, after merge).' | bash "$sg_hook")"
assert "sg: weak-smoke -> deny" 'deny' "$out"

out="$(plan 'Task 1: bun build --compile the binary.' | bash "$sg_hook")"
assert "sg: engine keyword no smoke -> deny" 'deny' "$out"

out="$(plan 'Task 7: smoke runner (MANDATORY). bun build the binary.' | bash "$sg_hook")"
assert "sg: mandatory smoke -> allow/silent" EMPTY "$out"

# escape hatch on content that WOULD otherwise deny (engine keyword, no smoke task)
out="$(plan 'Task 1: bun build --compile the binary. Smoke: N/A — pure refactor, no behavior change.' | bash "$sg_hook")"
assert "sg: escape hatch overrides a would-be deny" EMPTY "$out"

out="$(printf '{"file_path":"/x/src/foo.ts","tool_name":"Write","tool_input":{"content":"bun build optional smoke deferred"}}' | bash "$sg_hook")"
assert "sg: non-plan path -> silent" EMPTY "$out"

# plan with NO engine keyword and NO smoke -> silent (not every plan needs smoke)
out="$(plan 'Task 1: rename a variable in the docs.' | bash "$sg_hook")"
assert "sg: non-engine plan -> silent" EMPTY "$out"

rm -rf "$tmp"
print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
