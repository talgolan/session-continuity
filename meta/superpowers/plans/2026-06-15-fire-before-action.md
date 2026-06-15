# Fire Before the Action — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two PreToolUse hooks to the session-continuity plugin so known guidance fires *before* an action — a LEARNINGS retrieval hook keyed on the imminent command/file, and a smoke-gate hook that blocks plan writes lacking a MANDATORY smoke task.

**Architecture:** Two new pure stdin→stdout bash hook scripts under `hooks/`, registered in `hooks/hooks.json` on the same JSON `hookSpecificOutput` contract the existing `pre-commit-check.sh` already uses (`permissionDecision: allow` to nudge, `deny` to block). LEARNINGS entries gain an optional `Trigger: <tool> /<regex>/` line; the `/learning` command and the template teach the syntax. A hermetic `.zsh` smoke runner drives both scripts with crafted stdin payloads.

**Tech Stack:** Bash (POSIX-ish, no `jq` — `grep`/`sed` payload parsing, matching existing hooks), zsh smoke runner, Claude Code PreToolUse hook JSON contract.

**Smoke (MANDATORY):** Task 7 ships `meta/superpowers/validation/2026-06-15-fire-before-action-smoke.zsh` driving both hooks with payload fixtures. NOT optional, NOT deferred — this change touches executable hooks, so the smoke runner is part of done.

---

## File Structure

- **Create** `hooks/learnings-surface.sh` — PreToolUse hook (Bash + Write|Edit). Reads stdin payload, extracts the imminent action's tool + match-text, greps LEARNINGS `Trigger:` lines, emits non-blocking `additionalContext` for each matching entry.
- **Create** `hooks/smoke-gate.sh` — PreToolUse hook (Write|Edit). Self-scopes to plan files, reads written content, emits `deny` on weak-smoke or engine-keyword-without-smoke; honors a `Smoke: N/A — <reason>` escape hatch.
- **Create** `meta/superpowers/validation/2026-06-15-fire-before-action-smoke.zsh` — hermetic smoke runner for both hooks.
- **Modify** `hooks/hooks.json` — register the two new PreToolUse hooks.
- **Modify** `commands/learning.md` — add the optional Trigger field (Step 2) + emit it (Step 5).
- **Modify** `skills/session-continuity/SKILL.md` — document Trigger syntax + smoke-gate.
- **Modify** `skills/session-continuity/templates/LEARNINGS.md` — example `Trigger:` line.
- **Modify** `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` — version 0.7.0 → 0.8.0.
- **Modify** `CHANGELOG.md` — v0.8.0 entry.
- **Modify** `README.md` — note the two new gates.

## Payload contract (reference for all hook tasks)

Claude Code delivers a JSON payload on stdin to PreToolUse hooks. Fields the hooks read (parsed with minimal `grep -oE`/`sed`, same style as existing hooks — NO `jq`):

- `"cwd": "<abs path>"` — user repo dir (NOT `$CLAUDE_PROJECT_DIR`).
- `"tool_name": "Bash" | "Write" | "Edit"`.
- `tool_input.command` — the Bash command string (Bash only).
- `tool_input.file_path` — target path (Write/Edit).
- `tool_input.content` — full file content (Write).
- `tool_input.new_string` — replacement text (Edit).

Because `content`/`new_string`/`command` can contain newlines and escaped quotes, the hooks read these with a tolerant approach: extract the value with a `python3`-free `sed` that captures from the key to the matching close. Where multiline JSON-string parsing is too fragile for pure sed, the hook greps the WHOLE raw payload for the trigger pattern (the payload contains the content verbatim, JSON-escaped) — false matches are acceptable for the non-blocking learnings hook, but the blocking smoke-gate must be precise (see Task 4 for the bounded extraction it uses).

---

### Task 1: LEARNINGS trigger parsing helper (test-first, pure)

Build the matching logic as a standalone shell function first, tested in isolation, before wiring stdin.

**Files:**
- Create: `hooks/learnings-surface.sh`
- Test: `meta/superpowers/validation/2026-06-15-fire-before-action-smoke.zsh` (created in Task 7; Task 1 tests the function via a temporary inline harness)

- [ ] **Step 1: Write `hooks/learnings-surface.sh` with the parse/match core**

```bash
#!/usr/bin/env bash
#
# learnings-surface.sh — PreToolUse hook (session-continuity plugin).
#
# Fires before Bash / Write / Edit actions. If the user's repo has a
# LEARNINGS.md whose entries carry a `Trigger: <tool> /<regex>/` line, and
# the imminent action matches one, inject a NON-BLOCKING reminder naming the
# entry so the relevant hard-won lesson surfaces BEFORE the action runs —
# not only after a symptom makes it greppable.
#
# Output contract (see LEARNINGS #1): PreToolUse hooks must emit a JSON
# object with hookSpecificOutput.additionalContext to reach Claude's context;
# plain stdout goes to debug logs only. permissionDecision:"allow" keeps this
# non-blocking — it surfaces, it never vetoes.
#
# Security: $cwd is only used in [ -f ] tests and as a grep file arg, never
# eval'd. Trigger regexes come from the repo's own LEARNINGS.md (same trust
# level as the code being committed). Any unexpected input -> silent exit 0.

set -euo pipefail

payload="$(cat || true)"
[ -z "${payload:-}" ] && exit 0

cwd="$(printf '%s' "$payload" \
  | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*"cwd"[[:space:]]*:[[:space:]]*"(.*)"/\1/' \
  || true)"
[ -z "${cwd:-}" ] && exit 0
[ ! -d "$cwd" ] && exit 0

learnings="$cwd/.session-continuity/LEARNINGS.md"
[ -f "$learnings" ] || learnings="$cwd/docs/LEARNINGS.md"
[ -f "$learnings" ] || exit 0

tool="$(printf '%s' "$payload" \
  | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' \
  || true)"
[ -z "${tool:-}" ] && exit 0

# Match-text is the full raw payload. The action's command/content/path are
# all inside it, JSON-escaped. Matching against the whole payload keeps the
# parser trivial and robust to multiline content; the only cost is that a
# trigger regex could in principle match a different field. Acceptable: this
# hook is advisory (allow-only), and triggers are authored to be specific.
match_text="$payload"

# Walk LEARNINGS for `### N. Title` headings each optionally followed by a
# `Trigger: <tool> /<regex>/` line. awk emits, per entry that has a trigger:
#   <num>\t<tool>\t<regex>\t<title>
entries="$(awk '
  /^### [0-9]+\./ {
    # flush previous (no trigger seen -> skip)
    num=$2; sub(/\./,"",num);
    title=$0; sub(/^### [0-9]+\.[[:space:]]*/,"",title);
    have_trigger=0; t_tool=""; t_re="";
    next;
  }
  /^Trigger:[[:space:]]/ {
    line=$0; sub(/^Trigger:[[:space:]]*/,"",line);
    # line = "<tool> /<regex>/"
    ttool=line; sub(/[[:space:]].*$/,"",ttool);
    tre=line; sub(/^[^[:space:]]+[[:space:]]*/,"",tre);
    sub(/^\//,"",tre); sub(/\/[[:space:]]*$/,"",tre);
    if (num != "" && tre != "") {
      printf "%s\t%s\t%s\t%s\n", num, ttool, tre, title;
    }
    next;
  }
' "$learnings" 2>/dev/null || true)"

[ -z "${entries:-}" ] && exit 0

hits=""
while IFS=$'\t' read -r num ttool tre title; do
  [ -z "$num" ] && continue
  # tool gate: "*" matches any; else must equal the action tool
  if [ "$ttool" != "*" ] && [ "$ttool" != "$tool" ]; then
    continue
  fi
  if printf '%s' "$match_text" | grep -Eq -- "$tre" 2>/dev/null; then
    # JSON-escape the title (minimal: backslash + quote)
    safe_title="$(printf '%s' "$title" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g')"
    hits="${hits}#${num} (${safe_title}); "
  fi
done <<< "$entries"

[ -z "${hits:-}" ] && exit 0

msg="⚠️ Known LEARNINGS may apply to this action before you run it: ${hits}Read the full entry in LEARNINGS.md before proceeding."
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"%s"}}\n' "$msg"
exit 0
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x hooks/learnings-surface.sh`

- [ ] **Step 3: Smoke the match path manually (temporary)**

```bash
tmp="$(mktemp -d)"; mkdir -p "$tmp/.session-continuity"
cat > "$tmp/.session-continuity/LEARNINGS.md" <<'EOF'
### 124. smoke SUT dist/itb != local bin
Trigger: Bash /smoke|run\.zsh/
**The trap.** stale binary.
EOF
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"./run.zsh"}}' "$tmp" \
  | bash hooks/learnings-surface.sh
```
Expected: a JSON line containing `#124` and `permissionDecision":"allow"`.

- [ ] **Step 4: Smoke the no-match + no-trigger paths**

```bash
# no match (command doesn't hit the regex)
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"ls -la"}}' "$tmp" \
  | bash hooks/learnings-surface.sh; echo "rc=$?"
# entry with no Trigger line -> never fires
printf '### 7. some entry\n**The trap.** x.\n' > "$tmp/.session-continuity/LEARNINGS.md"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"./run.zsh"}}' "$tmp" \
  | bash hooks/learnings-surface.sh; echo "rc=$?"
rm -rf "$tmp"
```
Expected: both produce NO stdout and `rc=0`.

- [ ] **Step 5: Commit**

```bash
git add hooks/learnings-surface.sh
git commit -m "feat(hooks): learnings-surface PreToolUse hook (Trigger-keyed retrieval)"
```

---

### Task 2: smoke-gate hook

**Files:**
- Create: `hooks/smoke-gate.sh`

- [ ] **Step 1: Write `hooks/smoke-gate.sh`**

```bash
#!/usr/bin/env bash
#
# smoke-gate.sh — PreToolUse hook (session-continuity plugin).
#
# Fires before Write / Edit. Self-scopes to plan files (path under a
# */plans/ dir or a *plan*.md basename). BLOCKS the write when an
# engine/binary-touching plan lacks a MANDATORY smoke task:
#
#   (1) weak-smoke   — mentions "smoke" but a smoke line is tagged
#                      optional/deferred/after-merge/nice-to-have.
#   (2) no-smoke     — mentions binary/engine/container/daemon/--compile/
#                      "bun build" but has no "smoke" mention at all.
#
# Escape hatch (explicit skip-with-reason): a line matching
#   Smoke: N/A — <reason>   (em-dash or --, non-empty reason)
# passes the gate unconditionally.
#
# Output contract: permissionDecision:"deny" blocks the tool call and shows
# the reason to Claude. permissionDecision:"allow" (or silent exit 0) lets
# it through.
#
# Security: $cwd / file_path used only in path tests + grep; never eval'd.

set -euo pipefail

payload="$(cat || true)"
[ -z "${payload:-}" ] && exit 0

file_path="$(printf '%s' "$payload" \
  | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' \
  || true)"
[ -z "${file_path:-}" ] && exit 0

# Self-scope: only plan files. */plans/*.md OR basename *plan*.md
base="${file_path##*/}"
case "$file_path" in
  */plans/*) : ;;
  *)
    case "$base" in
      *plan*.md) : ;;
      *) exit 0 ;;
    esac
    ;;
esac
case "$base" in *.md) : ;; *) exit 0 ;; esac

# Pull the written content. Write -> content; Edit -> new_string. We extract
# everything after the key's opening quote to end of payload, then strip the
# trailing JSON, and UN-escape \n and \" so line-oriented greps work. This is
# a bounded best-effort decode; the gate errs toward blocking, and the
# escape hatch gives an explicit override, so imperfect decode is safe.
raw="$(printf '%s' "$payload" \
  | sed -nE 's/.*"content"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
  | head -1)"
[ -z "$raw" ] && raw="$(printf '%s' "$payload" \
  | sed -nE 's/.*"new_string"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
  | head -1)"
[ -z "$raw" ] && exit 0

# Decode JSON-escaped newlines/quotes/tabs into real characters.
content="$(printf '%s' "$raw" \
  | sed -E 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g; s/\\\\/\\/g')"

# Escape hatch first.
if printf '%s' "$content" | grep -Eiq 'Smoke:[[:space:]]*N/A[[:space:]]*(—|--)[[:space:]]*[^[:space:]]'; then
  exit 0
fi

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

mentions_smoke="$(printf '%s' "$content" | grep -ci 'smoke' || true)"

# (1) weak-smoke
if [ "${mentions_smoke:-0}" -gt 0 ]; then
  if printf '%s' "$content" | grep -i 'smoke' \
       | grep -Eiq 'optional|deferred|after.?merge|nice.?to.?have'; then
    deny "Smoke task is marked optional/deferred. Engine/binary features need a MANDATORY smoke task — part of done, never deferred/after-merge. Re-mark it MANDATORY, or add a line: Smoke: N/A — <reason> if this plan genuinely touches no binary/engine."
  fi
  exit 0
fi

# (2) engine keyword, no smoke at all
if printf '%s' "$content" | grep -Eiq 'binary|engine|container|daemon|--compile|bun build'; then
  deny "This plan mentions binary/engine/container work but has no smoke task. Add a MANDATORY smoke task, or add a line: Smoke: N/A — <reason> if it genuinely touches no binary/engine."
fi

exit 0
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x hooks/smoke-gate.sh`

- [ ] **Step 3: Manual smoke — the four cases**

```bash
mkplan() { printf '{"file_path":"/x/plans/p.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }
# (a) weak-smoke -> deny
mkplan 'Task 7: smoke runner (optional, after merge).' | bash hooks/smoke-gate.sh
# (b) engine keyword, no smoke -> deny
mkplan 'Task 1: bun build --compile the binary.' | bash hooks/smoke-gate.sh
# (c) mandatory smoke -> allow (silent)
mkplan 'Task 7: smoke runner (MANDATORY). bun build the binary.' | bash hooks/smoke-gate.sh; echo "rc=$?"
# (d) escape hatch -> allow (silent)
mkplan 'Pure docs change. Smoke: N/A — no binary touched.' | bash hooks/smoke-gate.sh; echo "rc=$?"
# (e) non-plan path -> silent regardless
printf '{"file_path":"/x/src/foo.ts","tool_name":"Write","tool_input":{"content":"bun build optional smoke deferred"}}' | bash hooks/smoke-gate.sh; echo "rc=$?"
```
Expected: (a) and (b) emit `permissionDecision":"deny"`; (c), (d), (e) emit nothing, `rc=0`.

- [ ] **Step 4: Commit**

```bash
git add hooks/smoke-gate.sh
git commit -m "feat(hooks): smoke-gate PreToolUse hook (block plans missing mandatory smoke)"
```

---

### Task 3: Register both hooks in hooks.json

**Files:**
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Replace `hooks/hooks.json` with the three-event registration**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(git commit *)",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/pre-commit-check.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/learnings-surface.sh"
          }
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/learnings-surface.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/smoke-gate.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate JSON**

Run: `python3 -c "import json,sys; json.load(open('hooks/hooks.json'))" && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat(hooks): register learnings-surface + smoke-gate PreToolUse hooks"
```

---

### Task 4: `/learning` command — optional Trigger field

**Files:**
- Modify: `commands/learning.md`

- [ ] **Step 1: Add the Trigger prompt to Step 2**

In `commands/learning.md`, find the Step 2 numbered list (ends at item 5,
"Diagnostic signal"). Add item 6 immediately after item 5:

```markdown
6. **Trigger** (optional — how this entry resurfaces *before* the action): a tool + regex that the `learnings-surface` hook matches against the imminent command or file. Form: `<tool> /<regex>/` where `<tool>` is `Bash`, `Write`, `Edit`, or `*`. E.g. `Bash /smoke|run\.zsh/` to resurface a smoke-runner trap before a smoke run. Skip if no mechanical trigger fits.
```

- [ ] **Step 2: Emit the Trigger line in Step 5**

In `commands/learning.md` Step 5, change the composed entry block so the
`Trigger:` line is emitted immediately under the heading when supplied.
Replace the existing markdown code block (the `### <N>. <Title>` template)
with:

````markdown
```markdown
### <N>. <Title>
Trigger: <tool> /<regex>/      ← include ONLY if the user supplied a trigger; omit the whole line otherwise

**The trap.** <trap text>

**Symptom.** <symptom text>

**Fix.** <fix text>

[optional code block]

**Diagnostic signal** *(optional)*. <diagnostic text if supplied>

---
```
````

Add a sentence after the block: "The `Trigger:` line, when present, must sit on the line directly below the `### N.` heading (no blank line between) so the `learnings-surface` hook's parser associates it with the entry."

- [ ] **Step 3: Commit**

```bash
git add commands/learning.md
git commit -m "feat(learning): optional Trigger field for action-keyed retrieval"
```

---

### Task 5: Template + SKILL.md documentation

**Files:**
- Modify: `skills/session-continuity/templates/LEARNINGS.md`
- Modify: `skills/session-continuity/SKILL.md`

- [ ] **Step 1: Add a commented Trigger example to the template**

In `skills/session-continuity/templates/LEARNINGS.md`, under the `### 1. {{ENTRY_TITLE}}` heading, insert directly below the heading line (before `**The trap.**`):

```markdown
<!-- Optional: a Trigger line resurfaces this entry BEFORE a matching action runs
     (via the learnings-surface hook). Form: Trigger: <tool> /<regex>/  where
     <tool> is Bash | Write | Edit | *. Delete if no mechanical trigger fits.
     Example:  Trigger: Bash /smoke|run\.zsh/  -->
```

- [ ] **Step 2: Document both gates in SKILL.md**

In `skills/session-continuity/SKILL.md`, find the paragraph ending
"Hooks in `hooks/hooks.json` remind Claude to read the primer on session
start and nudge when a `git commit` lands without a primer refresh staged."
Append two sentences to that paragraph:

```markdown
Two further PreToolUse gates fire *before* an action rather than after a symptom: a **retrieval hook** surfaces any LEARNINGS entry carrying a `Trigger: <tool> /<regex>/` line when the imminent Bash command or Write/Edit matches that regex (non-blocking — it names the entry so you read it first), and a **smoke-gate** blocks writing a plan file that touches binary/engine work but lacks a MANDATORY smoke task (override with an explicit `Smoke: N/A — <reason>` line).
```

- [ ] **Step 3: Add a "Trigger lines" subsection under the LEARNINGS rules**

In `skills/session-continuity/SKILL.md`, after the "Numbering convention." paragraph in the "### On a hard-won bug — add to LEARNINGS.md" section, add:

```markdown
**Trigger lines (optional, action-keyed retrieval).** An entry may carry a single `Trigger: <tool> /<regex>/` line directly below its `### N.` heading. The `learnings-surface` hook matches the regex against the imminent action — the Bash command string, or a Write/Edit file path + content — and surfaces the entry *before* it runs. `<tool>` is `Bash`, `Write`, `Edit`, or `*` (any). Author triggers narrowly so they fire on the specific trap, not on incidental word overlap. Entries with no `Trigger:` line never fire — there is no cost to omitting it. This is the mechanism that turns LEARNINGS from a read-after-symptom file into a read-before-action gate.
```

- [ ] **Step 4: Commit**

```bash
git add skills/session-continuity/templates/LEARNINGS.md skills/session-continuity/SKILL.md
git commit -m "docs(skill): document Trigger syntax + smoke-gate"
```

---

### Task 6: Version bump + CHANGELOG + README

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] **Step 1: Bump plugin.json**

In `.claude-plugin/plugin.json` change `"version": "0.7.0"` → `"version": "0.8.0"`.

- [ ] **Step 2: Bump marketplace.json**

In `.claude-plugin/marketplace.json` change the nested `"version": "0.7.0"` → `"version": "0.8.0"`.

- [ ] **Step 3: Add CHANGELOG entry**

Insert directly below the `## [0.7.0] — 2026-05-23` line's section break (i.e. above the `## [0.7.0]` heading) a new block:

```markdown
## [0.8.0] — 2026-06-15

### Added
- **Fire-before-action PreToolUse gates.** Two new hooks make known guidance surface *before* an action, not after a symptom.
  - **`learnings-surface.sh` (Bash + Write|Edit).** A LEARNINGS entry may carry an optional `Trigger: <tool> /<regex>/` line directly below its `### N.` heading. When the imminent Bash command (or Write/Edit path + content) matches the regex, the hook injects a non-blocking reminder naming the entry, so the relevant hard-won lesson is read before the action runs. Entries with no `Trigger:` line never fire — zero noise.
  - **`smoke-gate.sh` (Write|Edit, plan files only).** Blocks writing a plan that mentions binary/engine/container work but either marks its smoke task optional/deferred/after-merge or has no smoke task at all. Override with an explicit `Smoke: N/A — <reason>` line. Enforces "every engine/binary feature needs a MANDATORY smoke task" mechanically, where a passive note had failed twice.
- **`/session-continuity:learning` optional Trigger field.** The command prompts for an optional trigger and emits the `Trigger:` line when supplied.

### Compatibility
- Additive. Existing LEARNINGS entries without `Trigger:` lines are unaffected; the smoke-gate only acts on plan-file writes. No migration. Upgrading installs gain the gates on next session.
```

- [ ] **Step 4: Note the gates in README**

In `README.md`, find the hooks description (search for `pre-commit` or `SessionStart`). Add a bullet/sentence near it:

```markdown
- **`learnings-surface`** (PreToolUse): surfaces a LEARNINGS entry tagged with a matching `Trigger:` line before the action it warns about runs.
- **`smoke-gate`** (PreToolUse): blocks plan writes that touch binary/engine work without a MANDATORY smoke task.
```

(Match the surrounding README format — if hooks are described in prose, add a sentence instead of bullets.)

- [ ] **Step 5: Verify version-sync guard passes**

Run: `bash .githooks/pre-commit && echo "version-sync OK"`
Expected: `version-sync OK` (no version-mismatch error).

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md README.md
git commit -m "chore(release): v0.8.0 — fire-before-action gates"
```

---

### Task 7: MANDATORY smoke runner

**Files:**
- Create: `meta/superpowers/validation/2026-06-15-fire-before-action-smoke.zsh`

This task is MANDATORY (the change ships executable hooks). NOT optional, NOT deferred.

- [ ] **Step 1: Write the smoke runner**

```zsh
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
ok()   { print -P "%F{green}✓%f $1"; (( pass++ )); }
bad()  { print -P "%F{red}✗%f $1"; (( fail++ )); }

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

out="$(plan 'Pure docs. Smoke: N/A — no binary touched.' | bash "$sg_hook")"
assert "sg: escape hatch -> silent" EMPTY "$out"

out="$(printf '{"file_path":"/x/src/foo.ts","tool_name":"Write","tool_input":{"content":"bun build optional smoke deferred"}}' | bash "$sg_hook")"
assert "sg: non-plan path -> silent" EMPTY "$out"

# plan with NO engine keyword and NO smoke -> silent (not every plan needs smoke)
out="$(plan 'Task 1: rename a variable in the docs.' | bash "$sg_hook")"
assert "sg: non-engine plan -> silent" EMPTY "$out"

rm -rf "$tmp"
print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x meta/superpowers/validation/2026-06-15-fire-before-action-smoke.zsh`

- [ ] **Step 3: Run the smoke runner — all assertions pass**

Run: `zsh meta/superpowers/validation/2026-06-15-fire-before-action-smoke.zsh`
Expected: `Result: N passed, 0 failed`, exit 0. If any assertion fails, fix the hook (not the test) and re-run.

- [ ] **Step 4: Commit**

```bash
git add meta/superpowers/validation/2026-06-15-fire-before-action-smoke.zsh
git commit -m "test(smoke): hermetic runner for both fire-before-action hooks"
```

---

### Task 8: Backfill real triggers + integration check on this repo

Validate the hooks against this plugin's OWN LEARNINGS.md (dogfooding) and add at least one real Trigger to prove the round-trip.

**Files:**
- Modify: `.session-continuity/LEARNINGS.md`

- [ ] **Step 1: Add a Trigger to LEARNINGS #1 (the hook-contract entry)**

In `.session-continuity/LEARNINGS.md`, under `### 1. PreToolUse hooks must emit JSON to reach Claude's context`, insert directly below the heading:

```markdown
Trigger: Write /hooks/.*\.sh|hooks\.json/
```

- [ ] **Step 2: Confirm the live repo round-trip**

```bash
printf '{"cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s/hooks/foo.sh","content":"x"}}' "$PWD" "$PWD" \
  | bash hooks/learnings-surface.sh
```
Expected: JSON citing `#1`, `permissionDecision":"allow"`.

- [ ] **Step 3: Confirm smoke-gate lets THIS plan through**

This plan file (`meta/superpowers/plans/2026-06-15-fire-before-action.md`) mentions "smoke" and marks Task 7 MANDATORY, and the engine-keyword path is moot because smoke IS mentioned. Verify:

```bash
content="$(sed 's/"/\\"/g' meta/superpowers/plans/2026-06-15-fire-before-action.md | awk 'BEGIN{ORS="\\n"}{print}')"
printf '{"file_path":"%s/meta/superpowers/plans/2026-06-15-fire-before-action.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$PWD" "$content" \
  | bash hooks/smoke-gate.sh; echo "rc=$?"
```
Expected: NO `deny`, `rc=0` (this very plan satisfies its own gate).

- [ ] **Step 4: Commit**

```bash
git add .session-continuity/LEARNINGS.md
git commit -m "chore(learnings): backfill Trigger on #1 (dogfood the retrieval hook)"
```

---

## Self-review notes

- **Spec coverage:** Component A → Tasks 1, 4, 5, 8. Component B → Tasks 2, 5. Registration → Task 3. Cross-cutting (version/CHANGELOG/README/SKILL) → Tasks 5, 6. MANDATORY smoke → Task 7. All spec sections mapped.
- **Self-gating:** Task 7 is marked MANDATORY (satisfies the new smoke-gate's rule against the plan being authored — Task 8 Step 3 verifies the plan passes its own gate).
- **No placeholders:** every hook script and the smoke runner are written in full.
- **Naming consistency:** `learnings-surface.sh` / `smoke-gate.sh` used identically across hooks.json, SKILL.md, CHANGELOG, README, and the smoke runner.
