#!/usr/bin/env zsh
# render.sh / render-backlog.awk / render-learnings.awk smoke test.
# Hermetic: synthetic fixtures + this repo's real BACKLOG.md/LEARNINGS.md,
# copied into a temp dir before every run. See
# meta/superpowers/sdd/2026-09-02-zero-turn-read-only-commands/task-2-brief.md
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
render="$lib/render.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"

# --- real BACKLOG.md: own counter 1..N, closed stub self-heals out ----------

proj1="$work/proj-real"
mkdir -p "$proj1/.session-continuity"
cp "$repo/.session-continuity/BACKLOG.md" "$proj1/.session-continuity/BACKLOG.md"
out="$(bash "$render" backlog "$proj1")"
rc=$?
n="$(print -r -- "$out" | grep -cE '^[0-9]+ \[')"
[[ "$rc" -eq 0 ]] && ok "backlog(real): exit 0" || bad "backlog(real): exit $rc"
[[ "$n" -eq 15 ]] && ok "backlog(real): renders 15 items (16 headings minus 1 closed stub)" \
  || bad "backlog(real): expected 15 rendered items, got $n"
print -r -- "$out" | grep -q '^1 \[d7f5\] \[2026-08-30\] Submit to the Anthropic marketplace$' \
  && ok "backlog(real): item 1 matches file order + own counter" \
  || bad "backlog(real): line 1 was: $(print -r -- "$out" | sed -n 1p)"
print -r -- "$out" | grep -q '^15 \[4a9d\] \[2026-09-02\] Decide whether' \
  && ok "backlog(real): last item renumbered to 15, not its file position (16)" \
  || bad "backlog(real): last line was: $(print -r -- "$out" | tail -1)"
print -r -- "$out" | grep -q '6258' \
  && bad "backlog(real): closed stub [6258] leaked into rendered output" \
  || ok "backlog(real): closed stub [6258] correctly skipped (no date field)"

# --- real LEARNINGS.md: verbatim numbers, grouped by section, zero-entry ----
# sections and Symptoms index dropped ----------------------------------------

proj2="$work/proj-real2"
mkdir -p "$proj2/.session-continuity"
cp "$repo/.session-continuity/LEARNINGS.md" "$proj2/.session-continuity/LEARNINGS.md"
lout="$(bash "$render" learnings "$proj2")"
rc=$?
ln="$(print -r -- "$lout" | grep -cE '^[0-9]+\. ')"
[[ "$rc" -eq 0 ]] && ok "learnings(real): exit 0" || bad "learnings(real): exit $rc"
[[ "$ln" -eq 15 ]] && ok "learnings(real): renders all 15 entries" \
  || bad "learnings(real): expected 15 rendered entries, got $ln"
print -r -- "$lout" | grep -q '^## Symptoms index$' \
  && bad "learnings(real): Symptoms index section leaked into output" \
  || ok "learnings(real): Symptoms index section dropped"
print -r -- "$lout" | grep -qE '^## (Security incidents|Anti-patterns we were tempted by|Checklist for a fresh dev-env setup)$' \
  && bad "learnings(real): a zero-entry section leaked into output" \
  || ok "learnings(real): zero-entry sections (Security incidents, Anti-patterns, Checklist) dropped"
print -r -- "$lout" | grep -q '^## Claude Code plugin mechanics$' \
  && ok "learnings(real): section headings present" \
  || bad "learnings(real): missing 'Claude Code plugin mechanics' section heading"
# File order within a section (not sorted): 11, 8, 2 under the first section.
first_three="$(print -r -- "$lout" | awk '/^## Claude Code plugin mechanics/{f=1;next} f && /^## /{exit} f && /^[0-9]/{print; c++} c==3{exit}')"
expect=$'11. `$CLAUDE_PLUGIN_ROOT` inside a bash fence in a skill/command file is never resolved — only the braced `${CLAUDE_PLUGIN_ROOT}` form is\n8. `git -C` and compound commands blocked inside a worktree-isolated session\n2. awk CHANGELOG range collapses on single-version files'
[[ "$first_three" == "$expect" ]] && ok "learnings(real): entries stay in file order (11, 8, 2), not sorted" \
  || bad "learnings(real): file-order check got: $first_three"

# --- synthetic: non-contiguous positions self-heal to 1..N -----------------

cat > "$work/noncontig.md" <<'EOF'
# fixture
### 5. [aaa1] [2026-01-01] First
### 9. [aaa2] [2026-01-02] Second
### 2. [aaa3] [2026-01-03] Third
EOF
mkdir -p "$work/proj-noncontig/.session-continuity"
cp "$work/noncontig.md" "$work/proj-noncontig/.session-continuity/BACKLOG.md"
out="$(bash "$render" backlog "$work/proj-noncontig")"
expect=$'1 [aaa1] [2026-01-01] First\n2 [aaa2] [2026-01-02] Second\n3 [aaa3] [2026-01-03] Third'
[[ "$out" == "$expect" ]] && ok "backlog: non-contiguous positions (5,9,2) renumber to 1,2,3" \
  || bad "backlog: non-contiguous case got: $out"

# --- synthetic: duplicate position self-heals, no dedup/crash --------------

cat > "$work/dup.md" <<'EOF'
# fixture
### 3. [bbb1] [2026-01-01] Alpha
### 3. [bbb2] [2026-01-02] Beta
EOF
mkdir -p "$work/proj-dup/.session-continuity"
cp "$work/dup.md" "$work/proj-dup/.session-continuity/BACKLOG.md"
out="$(bash "$render" backlog "$work/proj-dup")"
expect=$'1 [bbb1] [2026-01-01] Alpha\n2 [bbb2] [2026-01-02] Beta'
[[ "$out" == "$expect" ]] && ok "backlog: duplicate file position (3,3) still renders both items sequentially" \
  || bad "backlog: duplicate-position case got: $out"

# --- synthetic: a closed stub (tag, no date) self-heals out, not just the ---
# real file's specific one ---------------------------------------------------

cat > "$work/closed.md" <<'EOF'
# fixture
### 1. [g001] [2026-01-01] Alpha
### 2. [g002] — closed. Fixed in `abc123`.
### 3. [g003] [2026-01-02] Beta
EOF
mkdir -p "$work/proj-closed/.session-continuity"
cp "$work/closed.md" "$work/proj-closed/.session-continuity/BACKLOG.md"
out="$(bash "$render" backlog "$work/proj-closed")"
expect=$'1 [g001] [2026-01-01] Alpha\n2 [g003] [2026-01-02] Beta'
[[ "$out" == "$expect" ]] && ok "backlog: closed stub (tag, no date) is skipped and later items renumber down" \
  || bad "backlog: closed-stub case got: $out"

# --- synthetic: heading inside a fenced code block is not an entry ---------

cat > "$work/fenced-backlog.md" <<'EOF'
# fixture
### 1. [ccc1] [2026-01-01] Real item

```markdown
### 2. [zzzz] [2026-01-01] fenced example, not real
```

### 2. [ccc2] [2026-01-02] Second real item
EOF
mkdir -p "$work/proj-fenced/.session-continuity"
cp "$work/fenced-backlog.md" "$work/proj-fenced/.session-continuity/BACKLOG.md"
out="$(bash "$render" backlog "$work/proj-fenced")"
expect=$'1 [ccc1] [2026-01-01] Real item\n2 [ccc2] [2026-01-02] Second real item'
[[ "$out" == "$expect" ]] && ok "backlog: heading inside a fenced code block is ignored" \
  || bad "backlog: fenced-heading case got: $out"

# --- synthetic: heading inside an HTML comment is not an entry -------------

cat > "$work/commented-backlog.md" <<'EOF'
# fixture
### 1. [dddd] [2026-01-01] Real item

<!-- Example:
### 2. [eeee] [2026-01-01] example inside comment, not real
-->

### 2. [ffff] [2026-01-02] Second real item
EOF
mkdir -p "$work/proj-commented/.session-continuity"
cp "$work/commented-backlog.md" "$work/proj-commented/.session-continuity/BACKLOG.md"
out="$(bash "$render" backlog "$work/proj-commented")"
expect=$'1 [dddd] [2026-01-01] Real item\n2 [ffff] [2026-01-02] Second real item'
[[ "$out" == "$expect" ]] && ok "backlog: heading inside an HTML comment is ignored (fresh-install template defect class)" \
  || bad "backlog: commented-heading case got: $out"

# --- synthetic: learnings numbers are verbatim — duplicate/non-contiguous --
# across sections must NOT be deduped or renumbered --------------------------

cat > "$work/learnings-verbatim.md" <<'EOF'
# fixture

## Section A
### 5. Alpha

## Section B
### 5. Beta
### 1. Gamma
EOF
mkdir -p "$work/proj-lverbatim/.session-continuity"
cp "$work/learnings-verbatim.md" "$work/proj-lverbatim/.session-continuity/LEARNINGS.md"
out="$(bash "$render" learnings "$work/proj-lverbatim")"
expect=$'## Section A\n5. Alpha\n\n## Section B\n5. Beta\n1. Gamma'
[[ "$out" == "$expect" ]] && ok "learnings: duplicate/non-contiguous numbers render verbatim, never renumbered" \
  || bad "learnings: verbatim-number case got: $out"

# --- synthetic: learnings heading inside a fence/comment is not an entry ---

cat > "$work/learnings-fenced.md" <<'EOF'
# fixture

## Real section
### 3. Real entry

```md
### 4. fenced example, not real
```

<!--
### 6. commented example, not real
-->

### 5. Another real entry
EOF
mkdir -p "$work/proj-lfenced/.session-continuity"
cp "$work/learnings-fenced.md" "$work/proj-lfenced/.session-continuity/LEARNINGS.md"
out="$(bash "$render" learnings "$work/proj-lfenced")"
expect=$'## Real section\n3. Real entry\n5. Another real entry'
[[ "$out" == "$expect" ]] && ok "learnings: headings inside a fence or an HTML comment are not entries" \
  || bad "learnings: fenced/commented case got: $out"

# --- synthetic: Symptoms index and zero-entry sections are dropped ---------

cat > "$work/learnings-sections.md" <<'EOF'
# fixture

## Symptoms index
### 99. should not render

## Empty section

## Section With Entries
### 1. Something
EOF
mkdir -p "$work/proj-lsections/.session-continuity"
cp "$work/learnings-sections.md" "$work/proj-lsections/.session-continuity/LEARNINGS.md"
out="$(bash "$render" learnings "$work/proj-lsections")"
expect=$'## Section With Entries\n1. Something'
[[ "$out" == "$expect" ]] && ok "learnings: Symptoms index and zero-entry sections are dropped" \
  || bad "learnings: section-drop case got: $out"

# --- empty file: no crash, no items, exit 0 ---------------------------------

mkdir -p "$work/proj-empty/.session-continuity"
: > "$work/proj-empty/.session-continuity/BACKLOG.md"
: > "$work/proj-empty/.session-continuity/LEARNINGS.md"
out="$(bash "$render" backlog "$work/proj-empty")"; rc=$?
[[ "$rc" -eq 0 && "$out" == "BACKLOG.md has no items." ]] \
  && ok "backlog: empty file -> 'no items' message, exit 0" \
  || bad "backlog: empty file gave rc=$rc out='$out'"
out="$(bash "$render" learnings "$work/proj-empty")"; rc=$?
[[ "$rc" -eq 0 && "$out" == "LEARNINGS.md has no entries." ]] \
  && ok "learnings: empty file -> 'no entries' message, exit 0" \
  || bad "learnings: empty file gave rc=$rc out='$out'"

# --- missing file: bad input, not broken install, exit 0 -------------------

out="$(bash "$render" backlog "$work/does-not-exist-proj")"; rc=$?
[[ "$rc" -eq 0 ]] && ok "backlog: missing project dir exits 0 (bad input, not broken install)" \
  || bad "backlog: missing project dir exit $rc"
print -r -- "$out" | grep -q '/session-continuity:primer' \
  && ok "backlog: missing file message points at /session-continuity:primer" \
  || bad "backlog: missing file message was: $out"
out="$(bash "$render" learnings "$work/does-not-exist-proj")"; rc=$?
[[ "$rc" -eq 0 ]] && ok "learnings: missing project dir exits 0 (bad input, not broken install)" \
  || bad "learnings: missing project dir exit $rc"
print -r -- "$out" | grep -q '/session-continuity:primer' \
  && ok "learnings: missing file message points at /session-continuity:primer" \
  || bad "learnings: missing file message was: $out"

# --- install-fault paths: missing/skewed .awk sibling -> exit 2, one line ---

mkdir -p "$work/orphan"
cp "$render" "$work/orphan/render.sh"
out="$(bash "$work/orphan/render.sh" backlog "$proj1" 2>&1)"; rc=$?
[[ "$rc" -eq 2 ]] && ok "missing render-backlog.awk sibling exits 2" \
  || bad "missing sibling: expected exit 2, got $rc (out: $out)"
[[ "$(print -r -- "$out" | wc -l | tr -d ' ')" -eq 1 ]] && ok "missing sibling: exactly one line on stderr" \
  || bad "missing sibling: expected one line, got: $out"
out="$(bash "$work/orphan/render.sh" learnings "$proj2" 2>&1)"; rc=$?
[[ "$rc" -eq 2 ]] && ok "missing render-learnings.awk sibling exits 2" \
  || bad "missing sibling: expected exit 2, got $rc (out: $out)"

mkdir -p "$work/skewed"
cp "$render" "$work/skewed/render.sh"
sed 's/^# CONTRACT_VERSION=1$/# CONTRACT_VERSION=99/' "$lib/render-backlog.awk" > "$work/skewed/render-backlog.awk"
sed 's/^# CONTRACT_VERSION=1$/# CONTRACT_VERSION=99/' "$lib/render-learnings.awk" > "$work/skewed/render-learnings.awk"
out="$(bash "$work/skewed/render.sh" backlog "$proj1" 2>&1)"; rc=$?
[[ "$rc" -eq 2 ]] && ok "contract-skewed render-backlog.awk exits 2" \
  || bad "contract-skewed sibling: expected exit 2, got $rc (out: $out)"

# --- unknown subcommand -> exit 2 (broken/unsupported invocation) ----------

out="$(bash "$render" bogus 2>&1)"; rc=$?
[[ "$rc" -eq 2 ]] && ok "unknown subcommand exits 2" || bad "unknown subcommand: expected exit 2, got $rc (out: $out)"

# --- missing <project-dir> arg falls through to the bad-input path, exit 0 -
# (same class as a missing/unreadable file — per the brief's contract, this
# is not a broken-install condition)

out="$(bash "$render" backlog 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && ok "backlog with no project-dir exits 0 (bad input, not broken install)" \
  || bad "backlog with no project-dir: expected exit 0, got $rc (out: $out)"
print -r -- "$out" | grep -q '/session-continuity:primer' \
  && ok "backlog with no project-dir points at /session-continuity:primer" \
  || bad "backlog with no project-dir message was: $out"
out="$(bash "$render" learnings 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && ok "learnings with no project-dir exits 0 (bad input, not broken install)" \
  || bad "learnings with no project-dir: expected exit 0, got $rc (out: $out)"
print -r -- "$out" | grep -q '/session-continuity:primer' \
  && ok "learnings with no project-dir points at /session-continuity:primer" \
  || bad "learnings with no project-dir message was: $out"

# --- help: absorbs the version parse and commands/*.md frontmatter loop ----

hout="$(bash "$render" help)"; rc=$?
[[ "$rc" -eq 0 ]] && ok "help: exit 0" || bad "help: exit $rc"
real_version="$(grep -m1 '"version"' "$repo/.claude-plugin/plugin.json" | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
print -r -- "$hout" | grep -q "^session-continuity v${real_version}\$" \
  && ok "help: header carries the real plugin.json version ($real_version)" \
  || bad "help: version header was: $(print -r -- "$hout" | sed -n 1p)"
print -r -- "$hout" | grep -qE '^/session-continuity:help — ' \
  && ok "help: lists /session-continuity:help from commands/help.md frontmatter" \
  || bad "help: missing help command line"
n_cmds="$(print -r -- "$hout" | grep -cE '^/session-continuity:')"
n_files="$(ls "$repo/commands"/*.md | wc -l | tr -d ' ')"
[[ "$n_cmds" -eq "$n_files" ]] && ok "help: lists one line per commands/*.md file ($n_files)" \
  || bad "help: expected $n_files command lines, got $n_cmds"

# --- update: fixed text, verbatim -------------------------------------------

uout="$(bash "$render" update)"; rc=$?
expect=$'/plugin marketplace update talgolan\n/reload-plugins\n\n1. `marketplace update talgolan` — refetches the `talgolan` marketplace catalog from GitHub so the latest release of every plugin in it, including this one, is visible. No-op if already current.\n2. `/reload-plugins` — activates the new version in this session without a restart.'
[[ "$rc" -eq 0 ]] && ok "update: exit 0" || bad "update: exit $rc"
[[ "$uout" == "$expect" ]] && ok "update: fixed text matches commands/update.md verbatim" \
  || bad "update: got: $uout"

rm -rf "$work"
print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
