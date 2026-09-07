#!/usr/bin/env zsh
# render.sh / backlog-issues.sh / render-learnings.awk smoke test.
# Hermetic: mocked GH_BIN + synthetic LEARNINGS fixtures + this repo's
# real LEARNINGS.md copied into a temp dir. Never hits the live GitHub API.
#
# NOTE: learnings(real) pins the live LEARNINGS.md entry count and the
# help case pins plugin.json version + commands/*.md count. Update those
# pins in the same commit when those sources change.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
render="$lib/render.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

WARN="Backlog unavailable: GitHub Issues required (gh, authenticated for this remote's host). Run /session-continuity:doctor."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mock="$work/fake-gh"
cat > "$mock" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${GH_MOCK_OUT:-}" && -f "${GH_MOCK_OUT}" ]]; then
  cat "${GH_MOCK_OUT}"
  exit 0
fi
exit 0
EOF
chmod +x "$mock"
export GH_BIN="$mock"

mk_gh_proj() {
  local d="$1"
  mkdir -p "$d/.session-continuity"
  git -C "$d" init -q
  git -C "$d" config user.email "test@example.com"
  git -C "$d" config user.name "Test"
  git -C "$d" remote add origin "https://github.com/example/repo.git"
}

# --- mocked GitHub Issues: two open backlog items --------------------------

proj1="$work/proj-issues"
mk_gh_proj "$proj1"
printf '#12\tAlpha item\n#15\tBeta item\n' > "$work/two.tsv"
export GH_MOCK_OUT="$work/two.tsv"
out="$(bash "$render" backlog "$proj1")"
rc=$?
expect=$'1. #12 Alpha item\n2. #15 Beta item'
[[ "$rc" -eq 0 && "$out" == "$expect" ]] && ok "backlog: two mocked issues" \
  || bad "backlog two: rc=$rc out='$out'"

# --- empty open list -------------------------------------------------------

: > "$work/empty.tsv"
export GH_MOCK_OUT="$work/empty.tsv"
out="$(bash "$render" backlog "$proj1")"; rc=$?
[[ "$rc" -eq 0 && "$out" == "No open backlog issues." ]] \
  && ok "backlog: empty list -> no-open message, exit 0" \
  || bad "backlog empty: rc=$rc out='$out'"

# --- real LEARNINGS.md: verbatim numbers, grouped by section, zero-entry ----
# sections and Symptoms index dropped ----------------------------------------

proj2="$work/proj-real2"
mkdir -p "$proj2/.session-continuity"
cp "$repo/.session-continuity/LEARNINGS.md" "$proj2/.session-continuity/LEARNINGS.md"
lout="$(bash "$render" learnings "$proj2")"
rc=$?
ln="$(print -r -- "$lout" | grep -cE '^[0-9]+\. ')"
[[ "$rc" -eq 0 ]] && ok "learnings(real): exit 0" || bad "learnings(real): exit $rc"
[[ "$ln" -eq 16 ]] && ok "learnings(real): renders all 16 entries" \
  || bad "learnings(real): expected 16 rendered entries, got $ln"
print -r -- "$lout" | grep -q '^## Symptoms index$' \
  && bad "learnings(real): Symptoms index section leaked into output" \
  || ok "learnings(real): Symptoms index section dropped"
print -r -- "$lout" | grep -qE '^## (Security incidents|Anti-patterns we were tempted by|Checklist for a fresh dev-env setup)$' \
  && bad "learnings(real): a zero-entry section leaked into output" \
  || ok "learnings(real): zero-entry sections (Security incidents, Anti-patterns, Checklist) dropped"
print -r -- "$lout" | grep -q '^## Claude Code plugin mechanics$' \
  && ok "learnings(real): section headings present" \
  || bad "learnings(real): missing 'Claude Code plugin mechanics' section heading"
first_three="$(print -r -- "$lout" | awk '/^## Claude Code plugin mechanics/{f=1;next} f && /^## /{exit} f && /^[0-9]/{print; c++} c==3{exit}')"
expect=$'11. `$CLAUDE_PLUGIN_ROOT` inside a bash fence in a skill/command file is never resolved — only the braced `${CLAUDE_PLUGIN_ROOT}` form is\n8. `git -C` and compound commands blocked inside a worktree-isolated session\n2. awk CHANGELOG range collapses on single-version files'
[[ "$first_three" == "$expect" ]] && ok "learnings(real): entries stay in file order (11, 8, 2), not sorted" \
  || bad "learnings(real): file-order check got: $first_three"

# --- synthetic: learnings numbers are verbatim — duplicate/non-contiguous --

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

# --- empty LEARNINGS file: no crash, no items, exit 0 ----------------------

mkdir -p "$work/proj-empty/.session-continuity"
: > "$work/proj-empty/.session-continuity/LEARNINGS.md"
out="$(bash "$render" learnings "$work/proj-empty")"; rc=$?
[[ "$rc" -eq 0 && "$out" == "LEARNINGS.md has no entries." ]] \
  && ok "learnings: empty file -> 'no entries' message, exit 0" \
  || bad "learnings: empty file gave rc=$rc out='$out'"

# --- missing LEARNINGS file: bad input, not broken install, exit 0 ---------

out="$(bash "$render" learnings "$work/does-not-exist-proj")"; rc=$?
[[ "$rc" -eq 0 ]] && ok "learnings: missing project dir exits 0 (bad input, not broken install)" \
  || bad "learnings: missing project dir exit $rc"
print -r -- "$out" | grep -q '/session-continuity:primer' \
  && ok "learnings: missing file message points at /session-continuity:primer" \
  || bad "learnings: missing file message was: $out"

# --- backlog with no github origin: warning, exit 0 ------------------------

out="$(bash "$render" backlog "$work/does-not-exist-proj")"; rc=$?
[[ "$rc" -eq 0 && "$out" == "$WARN" ]] \
  && ok "backlog: missing/non-git dir prints GitHub warning, exit 0" \
  || bad "backlog missing dir: rc=$rc out='$out'"

out="$(bash "$render" backlog 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out" == "$WARN" ]] \
  && ok "backlog with no project-dir prints GitHub warning, exit 0" \
  || bad "backlog with no project-dir: rc=$rc out='$out'"

# --- install-fault paths: missing/skewed sibling -> exit 2, one line -------

mkdir -p "$work/orphan"
cp "$render" "$work/orphan/render.sh"
out="$(bash "$work/orphan/render.sh" backlog "$proj1" 2>&1)"; rc=$?
[[ "$rc" -eq 2 ]] && ok "missing backlog-issues.sh sibling exits 2" \
  || bad "missing sibling: expected exit 2, got $rc (out: $out)"
[[ "$(print -r -- "$out" | wc -l | tr -d ' ')" -eq 1 ]] && ok "missing sibling: exactly one line on stderr" \
  || bad "missing sibling: expected one line, got: $out"
out="$(bash "$work/orphan/render.sh" learnings "$proj2" 2>&1)"; rc=$?
[[ "$rc" -eq 2 ]] && ok "missing render-learnings.awk sibling exits 2" \
  || bad "missing sibling: expected exit 2, got $rc (out: $out)"

mkdir -p "$work/skewed"
cp "$render" "$work/skewed/render.sh"
sed 's/^# CONTRACT_VERSION=1$/# CONTRACT_VERSION=99/' "$lib/backlog-issues.sh" > "$work/skewed/backlog-issues.sh"
sed 's/^# CONTRACT_VERSION=1$/# CONTRACT_VERSION=99/' "$lib/render-learnings.awk" > "$work/skewed/render-learnings.awk"
out="$(bash "$work/skewed/render.sh" backlog "$proj1" 2>&1)"; rc=$?
[[ "$rc" -eq 2 ]] && ok "contract-skewed backlog-issues.sh exits 2" \
  || bad "contract-skewed sibling: expected exit 2, got $rc (out: $out)"

# --- unknown subcommand -> exit 2 ------------------------------------------

out="$(bash "$render" bogus 2>&1)"; rc=$?
[[ "$rc" -eq 2 ]] && ok "unknown subcommand exits 2" || bad "unknown subcommand: expected exit 2, got $rc (out: $out)"

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
print -r -- "$hout" | grep -q 'GitHub Issues' \
  && ok "help: describes GitHub Issues as the queue" \
  || bad "help: missing GitHub Issues mention"
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

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
