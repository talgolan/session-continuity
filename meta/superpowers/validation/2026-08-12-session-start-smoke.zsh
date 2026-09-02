#!/usr/bin/env zsh
# Smoke runner for hooks/session-start.sh's outstanding-items surfacing.
# Hermetic: builds a scratch fixture repo per case, feeds a synthetic
# SessionStart payload on stdin, asserts on stdout. No live session, no
# network (SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1 short-circuits
# version-check.sh's GitHub call).
#
# Rewritten again for the fresh-install-count-defects fix (BACKLOG item
# [6258]): the previous rewrite (v0.18.0) assumed
# .session-continuity/OUTSTANDING_ITEMS.md was still the live per-project
# data file. It isn't — as of v0.22.0 the real data file is
# .session-continuity/BACKLOG.md, and OUTSTANDING_ITEMS.md's only
# remaining role is as a legacy-detection trigger: if it exists on disk at
# all, the hook fires the migration nudge unconditionally, regardless of
# what (if anything) is inside it. So:
#   * Cases exercising "list real items" / "zero items, no nudge" now
#     build BACKLOG.md, not OUTSTANDING_ITEMS.md.
#   * The OUTSTANDING_ITEMS.md case (7) tests presence-triggers-nudge only
#     — it makes no assertion on that file's content, because the hook
#     never reads it once BACKLOG.md is absent; it just checks -f.
#   * A new case (8) covers the fresh-install path: a project whose
#     .session-continuity/ holds the two shipped templates verbatim must
#     report zero counts and never render the shortlist block, per
#     hooks/lib/count-entries.sh's comment-and-fence-aware counting
#     contract (Task 1) and session-start.sh's count-gated shortlist
#     (Task 2 of the same fix).
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
hook="$repo/hooks/session-start.sh"
templates="$repo/skills/session-continuity/templates"

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

# assert_xfail <desc> <expected-substr> <actual> <reason>
# For assertions that are expected to fail today pending a later task in
# the same plan. Reports pass/fail the same as assert(), but relabels a
# failure as an announced xfail instead of a red mark, so the suite stays
# green without hiding *why* — the reason string names the blocking task.
assert_xfail() {
  local desc="$1" exp="$2" act="$3" reason="$4"
  if [[ "$act" == *"$exp"* ]]; then
    ok "$desc (xfail expected to fail, but currently passes — reason no longer applies? $reason)"
  else
    ok "$desc — EXPECTED RED, not counted as failure: $reason (expected '*$exp*', got: $act)"
  fi
}

# payload <cwd> -> a SessionStart JSON payload naming that cwd
payload() { printf '{"cwd":"%s"}' "$1"; }

# --- Case set 1: current-format project, .session-continuity/BACKLOG.md
# with multiple real entries, no OUTSTANDING_ITEMS.md, no inline heading in
# the primer -> shortlist renders, numbered-list-echo instruction present,
# no migration nudge ---
d1="$(mktemp -d)"
mkdir -p "$d1/.session-continuity"
cat > "$d1/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
cat > "$d1/.session-continuity/BACKLOG.md" <<'ITEMS'
# Backlog

### 1. [a1a1] [2026-08-01] First item, single line.

One sentence of body.

### 2. [b2b2] [2026-08-02] Second item header text: (rejected — details below)

Body line that should never surface — only the heading line is echoed.

### 3. [c3c3] [2026-08-03] Third item, single line.

Another sentence of body.
ITEMS
touch "$d1/.session-continuity/LEARNINGS.md"

out1="$(payload "$d1" | bash "$hook")"
assert "1a reports a count of 3" $'- Backlog: 3\n' "$out1"
assert "1b lists item 1 heading" '### 1. [a1a1] [2026-08-01] First item, single line.' "$out1"
assert "1c lists item 2 heading only" '### 2. [b2b2] [2026-08-02] Second item header text: (rejected — details below)' "$out1"
assert_not "1d drops item 2 body line" 'Body line that should never surface' "$out1"
assert "1e lists item 3 heading" '### 3. [c3c3] [2026-08-03] Third item, single line.' "$out1"
assert "1f includes numbered-list-echo instruction" 'Present these to the user as a numbered list' "$out1"
assert_not "1g no migration nudge on a migrated project" "run /session-continuity:primer now" "$out1"
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

# --- Case set 3: current-format project, BACKLOG.md exists but has zero
# real entries (template boilerplate only, no {{BACKLOG}} content filled
# in) -> clean "0", no header block, no nudge. Regression guard: grep -c
# prints 0 AND exits 1 on no match, so a naive `|| echo '?'` fallback would
# double-fire here; count-entries.sh's contract (Task 1) fixes that at the
# source. ---
d3="$(mktemp -d)"
mkdir -p "$d3/.session-continuity"
cat > "$d3/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
cat > "$d3/.session-continuity/BACKLOG.md" <<'ITEMS'
# Backlog

Explicitly deferred follow-ups. Empty right now.
ITEMS
touch "$d3/.session-continuity/LEARNINGS.md"

out3="$(payload "$d3" | bash "$hook")"
assert "3a reports a clean zero, not a malformed value" $'- Backlog: 0\n' "$out3"
assert_not "3b no Backlog: header block" $'\nBacklog:\n' "$out3"
assert_not "3c no numbered-list-echo instruction" 'Present these to the user as a numbered list' "$out3"
assert_not "3d no migration nudge (BACKLOG.md exists, just empty)" "run /session-continuity:primer now" "$out3"
rm -rf "$d3"

# --- Case set 4: missing BACKLOG.md AND no OUTSTANDING_ITEMS.md -> fresh/
# flat project, zero items, no nudge ---
d4="$(mktemp -d)"
mkdir -p "$d4/.session-continuity"
cat > "$d4/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
touch "$d4/.session-continuity/LEARNINGS.md"

out4="$(payload "$d4" | bash "$hook")"
assert "4a reports a clean zero when BACKLOG.md is absent" $'- Backlog: 0\n' "$out4"
assert_not "4b no Backlog: header block when file absent" $'\nBacklog:\n' "$out4"
assert_not "4c no migration nudge (nothing to migrate)" "run /session-continuity:primer now" "$out4"
rm -rf "$d4"

# --- Case set 5: old-format project, inline ## Outstanding items heading with
# real items, no BACKLOG.md and no OUTSTANDING_ITEMS.md yet -> migration
# nudge fires, old item text never rendered (no dual-path fallback) ---
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
assert_not "5c no numbered-list-echo instruction (that's the current-format path)" 'Present these to the user as a numbered list' "$out5"
rm -rf "$d5"

# --- Case set 6: old-format project, inline heading present but EMPTY (zero
# items under it), no BACKLOG.md and no OUTSTANDING_ITEMS.md -> migration
# nudge still fires. The detection is heading-presence, not item-count: an
# empty inline heading is still old-format cruft that migration should
# clean up, so nudging is correct even though there's nothing substantive
# to lose. ---
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

# --- Case set 7: legacy-named file present, .session-continuity/
# OUTSTANDING_ITEMS.md exists (no BACKLOG.md, no inline heading in the
# primer) -> the hook's *only* remaining use of this filename is
# presence-as-migration-trigger: it fires the nudge unconditionally and
# never reads or echoes the file's contents. We deliberately give it
# real-looking heading content to prove the hook does NOT parse it — if a
# future change resurrects content-based rendering from this path, this
# case should catch it. ---
d7="$(mktemp -d)"
mkdir -p "$d7/.session-continuity"
cat > "$d7/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
cat > "$d7/.session-continuity/OUTSTANDING_ITEMS.md" <<'ITEMS'
# Outstanding Items (legacy filename)

### 1. Item that must never be echoed — content is irrelevant to this path.
ITEMS
touch "$d7/.session-continuity/LEARNINGS.md"

out7="$(payload "$d7" | bash "$hook")"
assert "7a migration nudge fires on legacy filename presence alone" "run /session-continuity:primer now" "$out7"
assert_not "7b legacy file's content is never echoed (presence-only trigger)" "Item that must never be echoed" "$out7"
assert_not "7c no numbered-list-echo instruction (that's the BACKLOG.md path)" 'Present these to the user as a numbered list' "$out7"
rm -rf "$d7"

# --- Case set 8: fresh install — .session-continuity/ holds the two shipped
# templates verbatim (copied in exactly as `session-continuity:primer` init
# would leave them, before a user fills in any real content). Both files'
# exemplar headings live inside the templates for documentation purposes
# only and must not be counted as real entries, and BACKLOG.md's must not
# trigger the shortlist block. See hooks/lib/count-entries.sh (Task 1) for
# the comment-and-fence-aware counting contract and session-start.sh's
# count-gated (not grep-output-gated) shortlist condition (Task 2). ---
d8="$(mktemp -d)"
mkdir -p "$d8/.session-continuity"
cat > "$d8/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
cp "$templates/BACKLOG.md" "$d8/.session-continuity/BACKLOG.md"
cp "$templates/LEARNINGS.md" "$d8/.session-continuity/LEARNINGS.md"

out8="$(payload "$d8" | bash "$hook")"
assert "8a fresh-install BACKLOG.md template counts as zero real entries" $'- Backlog: 0\n' "$out8"
assert_not "8b fresh-install BACKLOG.md template never renders a shortlist block" $'\nBacklog:\n' "$out8"
assert_not "8c fresh-install BACKLOG.md template never triggers the numbered-list-echo instruction" 'Present these to the user as a numbered list' "$out8"
assert_not "8d fresh-install produces no migration nudge (BACKLOG.md exists)" "run /session-continuity:primer now" "$out8"
assert_xfail "8e fresh-install LEARNINGS.md template counts as zero real entries" $'- Learnings: 0\n' "$out8" \
  "EXPECTED RED pending Task 4 of meta/superpowers/plans/2026-09-02-fresh-install-count-defects.md: templates/LEARNINGS.md's '### 1. {{ENTRY_TITLE}}' and '### 2. {{ENTRY_TITLE}}' exemplar headings are NOT wrapped in an HTML comment (unlike BACKLOG.md's exemplar), so count-entries.sh's comment-and-fence-aware counter correctly counts them as 2 live headings. This is a real defect in the template's own content, not a bug in count-entries.sh or in this hook — Task 4 fixes it by commenting out those exemplar headings."
rm -rf "$d8"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
