#!/usr/bin/env zsh
# Smoke runner for hooks/session-start.sh's outstanding-items surfacing.
# Hermetic: builds a scratch fixture repo per case, feeds a synthetic
# SessionStart payload on stdin, asserts on stdout. No live session, no
# network (SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1 short-circuits
# version-check.sh's GitHub call).
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
hook="$repo/hooks/session-start.sh"

export SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1

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

# assert_not <desc> <forbidden-substr> <actual>
assert_not() {
  local desc="$1" forbidden="$2" act="$3"
  [[ "$act" != *"$forbidden"* ]] && ok "$desc" || bad "$desc (found forbidden '*$forbidden*')"
}

# payload <cwd> -> a SessionStart JSON payload naming that cwd
payload() { printf '{"cwd":"%s"}' "$1"; }

# --- Case set 1: canonical .session-continuity/ path, multi-line item ---
d1="$(mktemp -d)"
mkdir -p "$d1/.session-continuity"
cat > "$d1/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Outstanding items

1. First item, single line.
2. Second item header text: (rejected — details below)
   - sub-bullet A
   - sub-bullet B
3. Third item, single line.

## Workflow conventions
PRIMER
touch "$d1/.session-continuity/LEARNINGS.md"

out1="$(payload "$d1" | bash "$hook")"
assert "1a lists item 1 first line" '1. First item, single line.' "$out1"
assert "1b lists item 2 first line only" '2. Second item header text: (rejected — details below)' "$out1"
assert_not "1c drops item 2 sub-bullets" 'sub-bullet A' "$out1"
assert "1d lists item 3 first line" '3. Third item, single line.' "$out1"
assert "1e includes ask-the-user instruction" 'Ask the user which of these' "$out1"
rm -rf "$d1"

# --- Case set 2: legacy docs/ path gets the same treatment ---
d2="$(mktemp -d)"
mkdir -p "$d2/docs"
cat > "$d2/docs/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Outstanding items

1. Only item on the legacy path.

## Workflow conventions
PRIMER
touch "$d2/docs/LEARNINGS.md"

out2="$(payload "$d2" | bash "$hook")"
assert "2a legacy docs/ path also lists items" '1. Only item on the legacy path.' "$out2"
assert "2b legacy docs/ path also gets instruction" 'Ask the user which of these' "$out2"
rm -rf "$d2"

# --- Case set 3: empty Outstanding items section -> no block, no noise ---
d3="$(mktemp -d)"
mkdir -p "$d3/.session-continuity"
cat > "$d3/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Outstanding items

## Workflow conventions
PRIMER
touch "$d3/.session-continuity/LEARNINGS.md"

out3="$(payload "$d3" | bash "$hook")"
assert_not "3a no Outstanding items: header block" 'Outstanding items:' "$out3"
assert_not "3b no ask-the-user instruction" 'Ask the user which of these' "$out3"
assert "3c closing tag immediately follows Learnings line (no stray blank line)" $'- Learnings: 0\n</system-reminder>' "$out3"
rm -rf "$d3"

# --- Case set 4: missing Outstanding items section entirely -> no block ---
d4="$(mktemp -d)"
mkdir -p "$d4/.session-continuity"
cat > "$d4/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
touch "$d4/.session-continuity/LEARNINGS.md"

out4="$(payload "$d4" | bash "$hook")"
assert_not "4a no Outstanding items: header block when section absent" 'Outstanding items:' "$out4"
rm -rf "$d4"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
