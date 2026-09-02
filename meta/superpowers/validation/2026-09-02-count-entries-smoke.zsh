#!/usr/bin/env zsh
# count-entries.sh smoke test. Hermetic: synthetic fixtures written to a temp
# dir, plus this repo's own real files and shipped templates, opened
# read-only and never mutated (count-entries.sh only ever reads its
# argument).
# See meta/superpowers/plans/2026-09-02-fresh-install-count-defects.md (Task 1).
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
tool="$lib/count-entries.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

# Asserts count-entries.sh's stdout on $2 equals the integer $3, labeled $1.
assert_count() {
  local label="$1" file="$2" expected="$3" actual rc
  actual="$($tool "$file")"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    bad "$label: exited $rc (expected 0), printed '$actual'"
  elif [[ "$actual" == "$expected" ]]; then
    ok "$label: $actual"
  else
    bad "$label: expected $expected, got $actual"
  fi
}

work="$(mktemp -d)"

# --- regression anchors: real files, no comments or fences around headings -

# .session-continuity/LEARNINGS.md's true count as of this session, verified
# against `grep -cE '^### [0-9]+\.'` directly (the naive expression is
# correct here precisely because no real entry heading sits inside a
# comment or a fence — that only happens in the shipped templates below).
assert_count "real LEARNINGS.md" "$repo/.session-continuity/LEARNINGS.md" 15

# .session-continuity/BACKLOG.md's true count as of this session. The plan
# text that specified this task was written against an earlier BACKLOG.md
# (7 entries); nine more items were filed for the determinism program in a
# later commit (e7050a2) before this task started, bringing it to 16; Task 6
# (commit 8700944) filed one more (item 17: the `/doctor` retrofit), so the
# current correct answer is 17. Pinning the live number (rather than
# re-deriving it from grep in this test) keeps this a real regression
# anchor: if BACKLOG.md changes again, this assertion goes red and whoever
# touched it must update the pin, instead of the test silently tracking the
# file forever.
assert_count "real BACKLOG.md" "$repo/.session-continuity/BACKLOG.md" 17

# Independent cross-check that the pin above is still the naive-grep answer,
# i.e. that BACKLOG.md still has no comment/fence-wrapped heading of its own
# (only the shipped *template* does) — if this ever drifts from the helper,
# something is wrapping a real entry in a comment or fence.
grep_backlog="$(grep -cE '^### [0-9]+\.' "$repo/.session-continuity/BACKLOG.md")"
[[ "$grep_backlog" == "17" ]] && ok "real BACKLOG.md: naive grep also says 17 (sanity check on the pin)" \
  || bad "real BACKLOG.md: naive grep says $grep_backlog, expected 17 — the pin above is now stale"

# --- shipped templates: every one must count to zero -----------------------
#
# LEARNINGS.md's exemplar headings ("### 1. {{ENTRY_TITLE}}",
# "### 2. {{ENTRY_TITLE}}") are live content, not inside a comment, so this
# assertion is EXPECTED TO FAIL until Task 4 rewraps them. That is the point
# of writing this test now, before Task 4 lands: it is the red half of this
# task's own TDD cycle for the class of bug, and it will also catch the
# templates being un-fixed by any future edit. Every other shipped template
# already passes today.
for tmpl in BACKLOG.md LEARNINGS.md PROJECT_CONTEXT.md ROADMAP.md SESSION_PRIMER.md; do
  assert_count "shipped template $tmpl" "$repo/skills/session-continuity/templates/$tmpl" 0
done

# --- comment-awareness -------------------------------------------------------

cat > "$work/comment.md" <<'EOF'
# fixture

### 1. real entry

<!--
### 2. inside a comment, should not count
-->

### 3. another real entry
EOF
assert_count "heading inside <!-- --> block is not counted" "$work/comment.md" 2

cat > "$work/same-line-comment.md" <<'EOF'
### 1. real entry
<!-- ### 2. inline example, not counted -->
### 3. after inline comment, must still count
EOF
assert_count "comment that opens and closes on one line does not stick" "$work/same-line-comment.md" 2

# A heading line that ITSELF contains a self-closing inline comment (as
# opposed to the fixture above, where the comment delimiters are the whole
# line and the line never matches the heading pattern to begin with). This
# is the drift case from the final whole-branch review: render-backlog.awk
# and render-learnings.awk unconditionally `next` any line containing
# "<!--", self-closing or not, so a heading with an inline comment never
# renders. count-entries.sh must agree and not count it either.
cat > "$work/heading-with-inline-comment.md" <<'EOF'
### 1. real entry
### 2. [foo] [2026-01-01] Title with inline <!-- note --> text
### 3. another real entry
EOF
assert_count "heading line containing a self-closing inline comment is not counted (matches the renderers)" "$work/heading-with-inline-comment.md" 2

# --- fence-awareness ----------------------------------------------------------

cat > "$work/fence.md" <<'EOF'
# fixture

### 1. real entry

```
### 2. inside a fence, should not count
```

### 3. another real entry
EOF
assert_count "heading inside a \`\`\` fence is not counted" "$work/fence.md" 2

# --- nesting: a fence inside a comment ---------------------------------------

cat > "$work/fence-in-comment.md" <<'EOF'
# fixture

### 1. real entry

<!--
```
### 2. fenced heading inside a comment, should not count
```
-->

### 3. another real entry
EOF
assert_count "heading in a fence nested inside a comment is not counted" "$work/fence-in-comment.md" 2

# --- unterminated blocks at end of file --------------------------------------

cat > "$work/unterminated-comment.md" <<'EOF'
# fixture

### 1. real entry

<!--
### 2. never closes, should not count
### 3. also never counted
EOF
assert_count "unterminated comment: everything after the opener is dropped" "$work/unterminated-comment.md" 1

cat > "$work/unterminated-fence.md" <<'EOF'
# fixture

### 1. real entry

```
### 2. never closes, should not count
### 3. also never counted
EOF
assert_count "unterminated fence: everything after the opener is dropped" "$work/unterminated-fence.md" 1

# --- bad input: missing, unreadable, empty ----------------------------------

assert_count "missing file" "$work/does-not-exist.md" 0

: > "$work/empty.md"
assert_count "empty file" "$work/empty.md" 0

printf '### 1. x\n' > "$work/unreadable.md"
chmod 000 "$work/unreadable.md"
if [[ "$(id -u)" == "0" ]]; then
  print -P "%F{yellow}skip%f unreadable file: running as root, chmod 000 has no effect"
else
  assert_count "unreadable file" "$work/unreadable.md" 0
fi
chmod 644 "$work/unreadable.md"

out="$("$tool")"
rc=$?
[[ "$rc" -eq 0 && "$out" == "0" ]] && ok "no argument: prints 0, exits 0" \
  || bad "no argument: expected '0' exit 0, got '$out' exit $rc"

rm -rf "$work"
print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
