#!/usr/bin/env zsh
# Smoke runner for hooks/session-start.sh's outstanding-items surfacing.
# Hermetic: builds a scratch fixture repo per case, feeds a synthetic
# SessionStart payload on stdin, asserts on stdout. No live session, no
# network (SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1 short-circuits
# version-check.sh's GitHub call).
#
# Rewritten for v0.18.0 (.session-continuity/OUTSTANDING_ITEMS.md): the
# hook no longer parses an inline "## Outstanding items" heading inside
# SESSION_PRIMER.md at all — it reads the standalone file, or (if the
# heading exists but the file doesn't) emits a migration nudge instead of
# rendering old-format content. Cases below cover both paths plus the
# empty-file edge case that regressed once already (LEARNINGS: grep -c
# prints 0 AND exits 1 on no match, so a naive `|| echo '?'` fallback
# double-fires).
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

# --- Case set 1: new-format project, .session-continuity/OUTSTANDING_ITEMS.md
# with multiple entries, no inline heading in the primer ---
d1="$(mktemp -d)"
mkdir -p "$d1/.session-continuity"
cat > "$d1/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
cat > "$d1/.session-continuity/OUTSTANDING_ITEMS.md" <<'ITEMS'
# Outstanding Items

### 1. First item, single line.

One sentence of body.

### 2. Second item header text: (rejected — details below)

Body line that should never surface — only the heading line is echoed.

### 3. Third item, single line.

Another sentence of body.
ITEMS
touch "$d1/.session-continuity/LEARNINGS.md"

out1="$(payload "$d1" | bash "$hook")"
assert "1a lists item 1 heading" '### 1. First item, single line.' "$out1"
assert "1b lists item 2 heading only" '### 2. Second item header text: (rejected — details below)' "$out1"
assert_not "1c drops item 2 body line" 'Body line that should never surface' "$out1"
assert "1d lists item 3 heading" '### 3. Third item, single line.' "$out1"
assert "1e includes numbered-list-echo instruction" 'Present these to the user as a numbered list' "$out1"
assert_not "1f no migration nudge on a migrated project" "run /session-continuity:primer now" "$out1"
rm -rf "$d1"

# --- Case set 2: legacy docs/ path is no longer recognized (v0.14.0 dropped
# the fallback — .session-continuity/ is the only canonical location now) ---
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
assert "2a legacy docs/-only primer produces no reminder" "EMPTY" "$out2"
rm -rf "$d2"

# --- Case set 3: migrated project, OUTSTANDING_ITEMS.md exists but has zero
# entries -> clean "0", no header block, no nudge. Regression guard: grep -c
# prints 0 AND exits 1 on no match, so a naive `|| echo '?'` fallback would
# double-fire here (fixed in v0.18.0's final review). ---
d3="$(mktemp -d)"
mkdir -p "$d3/.session-continuity"
cat > "$d3/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
cat > "$d3/.session-continuity/OUTSTANDING_ITEMS.md" <<'ITEMS'
# Outstanding Items

Backlog of explicitly deferred follow-ups. Empty right now.
ITEMS
touch "$d3/.session-continuity/LEARNINGS.md"

out3="$(payload "$d3" | bash "$hook")"
assert "3a reports a clean zero, not a malformed value" $'- Outstanding items: 0\n' "$out3"
assert_not "3b no Outstanding items: header block" $'\nOutstanding items:\n' "$out3"
assert_not "3c no numbered-list-echo instruction" 'Present these to the user as a numbered list' "$out3"
assert_not "3d no migration nudge (file exists, just empty)" "run /session-continuity:primer now" "$out3"
rm -rf "$d3"

# --- Case set 4: missing Outstanding items section AND no OUTSTANDING_ITEMS.md
# -> fresh/flat project, zero items, no nudge ---
d4="$(mktemp -d)"
mkdir -p "$d4/.session-continuity"
cat > "$d4/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
touch "$d4/.session-continuity/LEARNINGS.md"

out4="$(payload "$d4" | bash "$hook")"
assert_not "4a no Outstanding items: header block when section absent" $'\nOutstanding items:\n' "$out4"
assert_not "4b no migration nudge (nothing to migrate)" "run /session-continuity:primer now" "$out4"
rm -rf "$d4"

# --- Case set 5: old-format project, inline ## Outstanding items heading with
# real items, no OUTSTANDING_ITEMS.md yet -> migration nudge fires, old item
# text never rendered (no dual-path fallback) ---
d5="$(mktemp -d)"
mkdir -p "$d5/.session-continuity"
cat > "$d5/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Outstanding items

1. Old-format item that must never be echoed.
2. Another old-format item.

## Workflow conventions
PRIMER
touch "$d5/.session-continuity/LEARNINGS.md"

out5="$(payload "$d5" | bash "$hook")"
assert "5a migration nudge fires" "run /session-continuity:primer now" "$out5"
assert_not "5b old item text never rendered" "Old-format item that must never be echoed" "$out5"
assert_not "5c no numbered-list-echo instruction (that's the new-format path)" 'Present these to the user as a numbered list' "$out5"
rm -rf "$d5"

# --- Case set 6: old-format project, inline heading present but EMPTY (zero
# items under it), no OUTSTANDING_ITEMS.md -> migration nudge still fires.
# The detection is heading-presence, not item-count: an empty inline heading
# is still old-format cruft Step 3b should clean up, so nudging is correct
# even though there's nothing substantive to lose. ---
d6="$(mktemp -d)"
mkdir -p "$d6/.session-continuity"
cat > "$d6/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Outstanding items

## Workflow conventions
PRIMER
touch "$d6/.session-continuity/LEARNINGS.md"

out6="$(payload "$d6" | bash "$hook")"
assert "6a migration nudge fires even for an empty inline heading" "run /session-continuity:primer now" "$out6"
rm -rf "$d6"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
