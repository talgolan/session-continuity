# BACKLOG/ROADMAP rename + /session-continuity:help Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename `.session-continuity/OUTSTANDING_ITEMS.md` to `BACKLOG.md` everywhere in this plugin, add a new `ROADMAP.md` stub file, add a `/session-continuity:help` command, and migrate existing installs (including this repo) automatically.

**Architecture:** No code, no runtime — this plugin is Markdown command/skill instructions plus two Bash hook scripts. Every task is either (a) a literal-string rename across prompt/doc files, (b) a new template/command file, or (c) new dispatch logic inside `commands/primer.md` and `hooks/session-start.sh`. There is no compiler and no test runner; "tests" in this plan are `grep`/`diff` invariant checks run by hand after each edit.

**Tech Stack:** Bash (hook scripts), Markdown (commands/skill/templates), git.

**Spec:** `meta/superpowers/specs/2026-08-31-backlog-roadmap-help-design.md`

## Global Constraints

- No automated test harness exists in this repo (confirmed: no `*.bats`, no `test/` dir). Every task's verification step is a `grep`/`diff` check run via Bash, not a test-runner invocation.
- Never commit automatically inside any command's own logic (`primer.md`, `doctor.md`, `end-session.md`) — staging only. This plan's own git commits (one per task, made by the implementer) are a different thing and are expected.
- Every `OUTSTANDING_ITEMS.md` / `OUTSTANDING_ITEMS` / "Outstanding items" / "Outstanding Items" string that refers to the **live, current** file or its heading gets renamed to `BACKLOG.md` / `BACKLOG` / "Backlog". Strings inside `CHANGELOG.md` describing **already-shipped past versions**, and one historical narrative bullet inside this repo's own `.session-continuity/SESSION_PRIMER.md` (identified in Task 13), are **not** rewritten — they describe what was true at the time and stay as history.
- Branch: work happens on `feature/backlog-roadmap-help` (already created, spec already committed there as `06247c2`/`2928c65`).
- Version: bump `.claude-plugin/plugin.json` `version` from `0.21.1` to `0.22.0` in Task 11.

---

### Task 1: Rename template `OUTSTANDING_ITEMS.md` → `BACKLOG.md`

**Files:**
- Create: `skills/session-continuity/templates/BACKLOG.md`
- Delete: `skills/session-continuity/templates/OUTSTANDING_ITEMS.md`

**Interfaces:**
- Produces: the placeholder token `{{BACKLOG}}` (renamed from `{{OUTSTANDING_ITEMS}}`), which Task 5 (`primer.md` Step 2/7/8) must reference by this exact name.

- [ ] **Step 1: git mv and edit content**

```bash
git mv skills/session-continuity/templates/OUTSTANDING_ITEMS.md skills/session-continuity/templates/BACKLOG.md
```

Then edit the moved file's first two lines from:

```markdown
# Outstanding Items — {{PROJECT_NAME}}

Backlog of explicitly deferred follow-ups and decisions — not bugs (those
```

to:

```markdown
# Backlog — {{PROJECT_NAME}}

Explicitly deferred follow-ups and decisions — not bugs (those
```

And the placeholder line (currently `{{OUTSTANDING_ITEMS}}` on its own line, near the bottom, just above the `<!-- Example:` block) to `{{BACKLOG}}`.

- [ ] **Step 2: Verify no old name remains in the new file, placeholder renamed**

```bash
grep -c "OUTSTANDING_ITEMS" skills/session-continuity/templates/BACKLOG.md
```

Expected: command exits non-zero / prints nothing matching (grep with no matches on `-c` prints `0`) — confirm output is exactly `0`.

```bash
grep -c "{{BACKLOG}}" skills/session-continuity/templates/BACKLOG.md
```

Expected: `1`.

- [ ] **Step 3: Commit**

```bash
git add skills/session-continuity/templates/BACKLOG.md
git commit -m "feat: rename OUTSTANDING_ITEMS.md template to BACKLOG.md"
```

---

### Task 2: New template `ROADMAP.md`

**Files:**
- Create: `skills/session-continuity/templates/ROADMAP.md`

**Interfaces:**
- Produces: placeholders `{{ROADMAP_NOW}}`, `{{ROADMAP_NEXT}}`, `{{ROADMAP_LATER}}`, which Task 5 (`primer.md` Step 2 and Step 3c) fill with `TBD` when not user-supplied.

- [ ] **Step 1: Write the template**

```markdown
# Roadmap — {{PROJECT_NAME}}

Strategic direction — where this project is headed, not the tactical
queue (that's `.session-continuity/BACKLOG.md`). Freeform: no numbering,
no permanence rules, no length cap. Rewrite sections wholesale as
direction changes; this file's history lives in git, not in careful
edits.

## Now

{{ROADMAP_NOW}}

## Next

{{ROADMAP_NEXT}}

## Later

{{ROADMAP_LATER}}
```

- [ ] **Step 2: Verify placeholders present**

```bash
grep -Ec '\{\{ROADMAP_NOW\}\}|\{\{ROADMAP_NEXT\}\}|\{\{ROADMAP_LATER\}\}' skills/session-continuity/templates/ROADMAP.md
```

Expected: `3`.

- [ ] **Step 3: Commit**

```bash
git add skills/session-continuity/templates/ROADMAP.md
git commit -m "feat: add ROADMAP.md template"
```

---

### Task 3: New command `/session-continuity:help`

**Files:**
- Create: `commands/help.md`

**Interfaces:**
- Consumes: nothing from earlier tasks (this task can run independently of 1/2, though it references BACKLOG/ROADMAP by name in its static prose).
- Produces: nothing other tasks depend on — this is a leaf.

- [ ] **Step 1: Write the command file**

The whole block below (through the closing ` ```` ` at the end of this step) is the entire, literal content of `commands/help.md` — write it as one file. It uses a 4-backtick outer fence here only because the file's own content contains 3-backtick code fences; do not include the outer 4-backtick markers in the actual file.

```` markdown
---
description: Explain what this plugin does, why, and what each `.session-continuity/` file is for. Zero args, read-only, no state mutation.
---

# /session-continuity:help

You are responding to the `/session-continuity:help` slash command.

**Your job: answer "what is this plugin and why should I care" directly, without sending the user to read `SKILL.md` end to end.** Read-only — never edits, stages, or commits anything.

## Step 1 — Get the installed version

```bash
grep -m1 '"version"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null || echo "version unknown (vendored install)"
```

## Step 2 — Report

Print the following, substituting the parsed version into the first line. This is fixed reference text — do not re-derive it from `SKILL.md` per invocation, and do not omit any of the five files or any command.

```
session-continuity v<X.Y.Z>

WHAT THIS IS
Cross-session memory for Claude Code projects, via five in-repo Markdown
docs. A fresh Claude session (or a fresh terminal, or tomorrow) starts
cold — these files are how it gets caught up without you re-explaining
the project.

WHY
Claude doesn't remember yesterday's debugging, last week's refactor, or
the bug you spent three hours cornering. These files are a low-tech fix:
plain Markdown, committed to git alongside the code, readable by humans
and Claude alike. Every change is an auditable commit; no vendor-specific
storage, no opaque memory layer.

THE FIVE FILES
- SESSION_PRIMER.md    — volatile. Current state, latest commits. Refresh
                          alongside every substantive commit.
- PROJECT_CONTEXT.md   — stable. Repo layout, conventions, module table.
                          Changes rarely — only when the project's shape
                          changes.
- BACKLOG.md           — tactical. Explicitly deferred follow-ups and
                          decisions. Permanently numbered; closed items
                          are deleted, never renumbered.
- ROADMAP.md           — strategic. Now/Next/Later direction. Freeform,
                          no numbering, rewritten wholesale as direction
                          changes.
- LEARNINGS.md         — durable wisdom. Append-only, numbered. One entry
                          per bug that took 15+ minutes to diagnose.

COMMANDS
```

Then list every `/session-continuity:*` command by reading each file's own frontmatter `description` field — do not hand-copy descriptions into this command file, since that duplicates a source of truth that will drift. Gather them in one Bash call:

```bash
for f in "${CLAUDE_PLUGIN_ROOT}"/commands/*.md; do
  name="$(basename "$f" .md)"
  desc="$(grep -m1 '^description:' "$f" | sed -E 's/^description:[[:space:]]*//')"
  echo "/session-continuity:$name — $desc"
done
```

Render each line under the `COMMANDS` heading above, one per command, in the order the `for` loop produced them.

## Notes

- **Never mutates anything.** No file writes, no `git add`, no `chmod` — matches `/session-continuity:doctor`'s same rule.
- **Never invent a command description.** If a command file has no `description:` frontmatter line, print `(no description found)` for that line rather than guessing.
````

- [ ] **Step 2: Verify frontmatter is well-formed**

```bash
head -5 commands/help.md
```

Expected: starts with `---`, has a `description:` line, closes with `---` before the `# /session-continuity:help` heading — same shape as `commands/doctor.md`.

- [ ] **Step 3: Commit**

```bash
git add commands/help.md
git commit -m "feat: add /session-continuity:help command"
```

---

### Task 4: `hooks/session-start.sh` — rename + migration-nudge branch

**Files:**
- Modify: `hooks/session-start.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks (this is the runtime hook; it doesn't read the templates).
- Produces: the reminder text convention ("Backlog:" line) that Task 8 (SKILL.md) and Task 12 (README.md) describe in prose.

- [ ] **Step 1: Rename the path variable and reminder label**

Change:
```bash
outstanding_path="$cwd/.session-continuity/OUTSTANDING_ITEMS.md"
```
to:
```bash
outstanding_path="$cwd/.session-continuity/BACKLOG.md"
```

Change the comment above it:
```bash
# Migration check: an old-format project has the inline heading in the
# primer but no OUTSTANDING_ITEMS.md yet. Only one project consumes this
# plugin today, so we push migration instead of tolerating both formats —
# no awk range-scan against the primer survives this change.
```
to:
```bash
# Migration check: an old-format project has the inline heading in the
# primer but no BACKLOG.md yet, OR has OUTSTANDING_ITEMS.md under its old
# name. Only one project consumes this plugin today, so we push migration
# instead of tolerating multiple formats — no awk range-scan against the
# primer survives this change.
```

Change the reminder text:
```bash
    outstanding_block=$'\nOutstanding items:\n'"$outstanding_items"$'\n\nPresent these to the user as a numbered list, numbered starting at 1 (never 0), keeping the numbers above even in a short reply, and ask which of these (if any) they want to tackle this session.\n'
```
to:
```bash
    outstanding_block=$'\nBacklog:\n'"$outstanding_items"$'\n\nPresent these to the user as a numbered list, numbered starting at 1 (never 0), keeping the numbers above even in a short reply, and ask which of these (if any) they want to tackle this session.\n'
```

And the final status line:
```bash
- Outstanding items: $status_outstanding
```
to:
```bash
- Backlog: $status_outstanding
```

- [ ] **Step 2: Add the new elif branch for the OUTSTANDING_ITEMS.md → BACKLOG.md migration**

Current chain (after Step 1's rename, `outstanding_path` now points at `BACKLOG.md`):
```bash
if [ -f "$outstanding_path" ]; then
  status_outstanding="$(grep -cE '^### [0-9]+\.' "$outstanding_path" 2>/dev/null || true)"
  status_outstanding="${status_outstanding:-0}"
  outstanding_items="$(grep -E '^### [0-9]+\.' "$outstanding_path" 2>/dev/null || true)"
  if [ -n "$outstanding_items" ]; then
    outstanding_block=$'\nBacklog:\n'"$outstanding_items"$'\n\nPresent these to the user as a numbered list, numbered starting at 1 (never 0), keeping the numbers above even in a short reply, and ask which of these (if any) they want to tackle this session.\n'
  else
    outstanding_block=""
  fi
elif grep -q '^## Outstanding items' "$cwd/$primer_path" 2>/dev/null; then
  status_outstanding="?"
  outstanding_block=$'\n⚠️ Outstanding items haven\'t migrated to .session-continuity/BACKLOG.md yet — run /session-continuity:primer now to migrate before continuing.\n'
else
  status_outstanding="0"
  outstanding_block=""
fi
```

Insert a new branch between the `elif grep -q '^## Outstanding items'` branch and the final `else`, so a project with the old `OUTSTANDING_ITEMS.md` file (but no `BACKLOG.md` yet) also gets a nudge instead of silently reporting zero:

```bash
elif [ -f "$cwd/.session-continuity/OUTSTANDING_ITEMS.md" ]; then
  status_outstanding="?"
  outstanding_block=$'\n⚠️ .session-continuity/OUTSTANDING_ITEMS.md hasn\'t migrated to BACKLOG.md yet — run /session-continuity:primer now to migrate before continuing.\n'
```

Full resulting chain (for reference — the `if`/two-`elif`/`else` shape):
```bash
if [ -f "$outstanding_path" ]; then
  status_outstanding="$(grep -cE '^### [0-9]+\.' "$outstanding_path" 2>/dev/null || true)"
  status_outstanding="${status_outstanding:-0}"
  outstanding_items="$(grep -E '^### [0-9]+\.' "$outstanding_path" 2>/dev/null || true)"
  if [ -n "$outstanding_items" ]; then
    outstanding_block=$'\nBacklog:\n'"$outstanding_items"$'\n\nPresent these to the user as a numbered list, numbered starting at 1 (never 0), keeping the numbers above even in a short reply, and ask which of these (if any) they want to tackle this session.\n'
  else
    outstanding_block=""
  fi
elif grep -q '^## Outstanding items' "$cwd/$primer_path" 2>/dev/null; then
  status_outstanding="?"
  outstanding_block=$'\n⚠️ Outstanding items haven\'t migrated to .session-continuity/BACKLOG.md yet — run /session-continuity:primer now to migrate before continuing.\n'
elif [ -f "$cwd/.session-continuity/OUTSTANDING_ITEMS.md" ]; then
  status_outstanding="?"
  outstanding_block=$'\n⚠️ .session-continuity/OUTSTANDING_ITEMS.md hasn\'t migrated to BACKLOG.md yet — run /session-continuity:primer now to migrate before continuing.\n'
else
  status_outstanding="0"
  outstanding_block=""
fi
```

- [ ] **Step 3: Shellcheck and manual smoke test**

```bash
shellcheck hooks/session-start.sh
```

Expected: no new warnings versus the pre-edit baseline (run `git stash` + `shellcheck` first if unsure of the baseline, then `git stash pop`).

Manual smoke test — simulate the new elif branch by faking an old-format `.session-continuity/` in a scratch dir:

```bash
tmpdir="$(mktemp -d)"
cd "$tmpdir" && git init -q
mkdir .session-continuity
cat > .session-continuity/SESSION_PRIMER.md <<'EOF'
# Session Primer — scratch

## Current state
placeholder
EOF
cat > .session-continuity/LEARNINGS.md <<'EOF'
# Learnings
EOF
cat > .session-continuity/OUTSTANDING_ITEMS.md <<'EOF'
# Outstanding Items — scratch

### 1. Example item
EOF
git add -A && git commit -q -m "scratch"
echo "{\"cwd\": \"$tmpdir\"}" | bash /Users/tal.golan/active_development/TG/session-continuity-plugin/hooks/session-start.sh
cd - && rm -rf "$tmpdir"
```

Expected: output includes `⚠️ .session-continuity/OUTSTANDING_ITEMS.md hasn't migrated to BACKLOG.md yet — run /session-continuity:primer now to migrate before continuing.` and `- Backlog: ?`.

- [ ] **Step 4: Commit**

```bash
git add hooks/session-start.sh
git commit -m "feat: session-start.sh recognizes BACKLOG.md, nudges old OUTSTANDING_ITEMS.md installs"
```

---

### Task 5: `commands/primer.md` — detection, init mode, migration Step 3c, placeholder rename

**Files:**
- Modify: `commands/primer.md`

**Interfaces:**
- Consumes: `{{BACKLOG}}` placeholder name from Task 1, `skills/session-continuity/templates/BACKLOG.md` and `skills/session-continuity/templates/ROADMAP.md` paths from Tasks 1–2.
- Produces: the Step 3c migration behavior that Task 13 (this repo's own dogfood migration) exercises manually.

- [ ] **Step 1: Step 1 (Detect state) — add BACKLOG/ROADMAP existence probes**

In the Step 1 gather block, after the `PRIMER_HAS_INLINE_OUTSTANDING` line, add:
```bash
[ -f .session-continuity/BACKLOG.md ] && echo "BACKLOG_EXISTS=1" || echo "BACKLOG_EXISTS=0"
[ -f .session-continuity/ROADMAP.md ] && echo "ROADMAP_EXISTS=1" || echo "ROADMAP_EXISTS=0"
```
(The existing `OUTSTANDING_ITEMS_EXISTS` line stays — Step 3c's trigger condition needs it.)

After the existing sequencing paragraph for Step 3b, add a second paragraph:

```markdown
If `OUTSTANDING_ITEMS_EXISTS=1` AND `BACKLOG_EXISTS=0`, a file-rename
migration is needed — run it (Step 3c below) in addition to whichever of
the four states above applies. **Sequencing:** if Step 3b also fired this
run (inline heading present, no file yet), run Step 3b to completion
first — it still writes `OUTSTANDING_ITEMS.md` under the old name — then
run Step 3c against that result. Step 3c is strictly the one-level-up
file rename; it never inspects primer content.
```

- [ ] **Step 2: Step 2 (Init mode) — copy BACKLOG.md and ROADMAP.md instead of OUTSTANDING_ITEMS.md**

Change item 5:
```markdown
5. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/OUTSTANDING_ITEMS.md` to `.session-continuity/OUTSTANDING_ITEMS.md`.
```
to:
```markdown
5. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/BACKLOG.md` to `.session-continuity/BACKLOG.md`.
6. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/ROADMAP.md` to `.session-continuity/ROADMAP.md`.
```
(renumber every subsequent item in Step 2 by +1 — old item 6 "Fill in placeholders..." becomes item 7, old item 7 "Ask the user..." becomes item 8, old item 8 "Replace any remaining..." becomes item 9, old item 9 "Stage all four files" becomes item 10, old item 10 "Tell the user" becomes item 11).

In renumbered item 8 (was 7 — "Ask the user for the blanks"), change:
```markdown
7. Ask the user for the blanks that can't be derived: `{{GROUND_RULES}}`, `{{WHERE_TO_LOOK_ROWS}}`, `{{STUCK_ESCALATION_STEPS}}`, `{{OUTSTANDING_ITEMS}}`, and `{{WORKFLOW_CONVENTIONS}}` only if no `CLAUDE.md` draft was produced above.
```
to:
```markdown
8. Ask the user for the blanks that can't be derived: `{{GROUND_RULES}}`, `{{WHERE_TO_LOOK_ROWS}}`, `{{STUCK_ESCALATION_STEPS}}`, `{{BACKLOG}}`, and `{{WORKFLOW_CONVENTIONS}}` only if no `CLAUDE.md` draft was produced above.
```
Rest of that item's sentence: keep "**Wait for their answer.**" as-is, and update the step-number reference from "Do not proceed to Step 9 until the user responds" to **"Do not proceed to Step 10 until the user responds"** — item 10 is the renumbered staging step, which is what this sentence gates on.

Change the sub-heading "**Outstanding-items conversion rule.**" paragraph — rename every `{{OUTSTANDING_ITEMS}}` in it to `{{BACKLOG}}`, and rename `.session-continuity/OUTSTANDING_ITEMS.md` to `.session-continuity/BACKLOG.md`:
```markdown
**Outstanding-items conversion rule.** The user's answer for
`{{OUTSTANDING_ITEMS}}` is free-form prose — a list, a paragraph, however
they typed it. Convert it into one `### N.` entry per distinct item in
`.session-continuity/OUTSTANDING_ITEMS.md`, numbered sequentially
starting at 1, trimming each to a title plus 1-3 sentences (the same
length cap every item in that file follows). Never paste the raw answer
in as a single unstructured blob. If the user said "none" or skipped the
question, leave the file's `{{OUTSTANDING_ITEMS}}` placeholder area empty
(substituted per the existing placeholder-cleanup step below, same as any
other skipped field).
```
becomes:
```markdown
**Backlog conversion rule.** The user's answer for
`{{BACKLOG}}` is free-form prose — a list, a paragraph, however
they typed it. Convert it into one `### N.` entry per distinct item in
`.session-continuity/BACKLOG.md`, numbered sequentially
starting at 1, trimming each to a title plus 1-3 sentences (the same
length cap every item in that file follows). Never paste the raw answer
in as a single unstructured blob. If the user said "none" or skipped the
question, leave the file's `{{BACKLOG}}` placeholder area empty
(substituted per the existing placeholder-cleanup step below, same as any
other skipped field).
```

Renumbered item 9 (was 8 — placeholder cleanup), change:
```markdown
8. **Replace any remaining `{{PLACEHOLDER}}` tokens with `TBD` before staging.** ... `grep -n '{{' .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .session-continuity/LEARNINGS.md .session-continuity/OUTSTANDING_ITEMS.md` must return nothing after this step.
```
to:
```markdown
9. **Replace any remaining `{{PLACEHOLDER}}` tokens with `TBD` before staging.** If the user skipped a field, declined to answer, or asked you to stage/commit without filling everything in, substitute `TBD` (with an empty body line where the template had prose). Never leave `{{...}}` syntax in a file you are about to stage — `grep -n '{{' .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .session-continuity/LEARNINGS.md .session-continuity/BACKLOG.md .session-continuity/ROADMAP.md` must return nothing after this step.
```

Renumbered item 10 (was 9 — stage), change:
```markdown
9. Stage all four files: `git add .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .session-continuity/LEARNINGS.md .session-continuity/OUTSTANDING_ITEMS.md`.
```
to:
```markdown
10. Stage all five files: `git add .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .session-continuity/LEARNINGS.md .session-continuity/BACKLOG.md .session-continuity/ROADMAP.md`.
```

Renumbered item 11 (was 10 — tell the user), change:
```markdown
10. Tell the user: "Primer, PROJECT_CONTEXT, OUTSTANDING_ITEMS, and LEARNINGS staged. Review and commit with `git commit -m 'docs: initialize session continuity'` when ready." Include a one-line note listing any fields that were set to `TBD` so the user knows what to fill in later.
```
to:
```markdown
11. Tell the user: "Primer, PROJECT_CONTEXT, BACKLOG, ROADMAP, and LEARNINGS staged. Review and commit with `git commit -m 'docs: initialize session continuity'` when ready." Include a one-line note listing any fields that were set to `TBD` so the user knows what to fill in later.
```

- [ ] **Step 3: Insert new Step 3c section, after the existing Step 3b section**

Insert this whole section directly after Step 3b's closing `**Do not commit automatically.** Staging only, same as every other split.` line, before the `## Step 4 — Refresh mode` heading:

```markdown
## Step 3c — Backlog rename migration

Runs whenever `BACKLOG_EXISTS=0` AND `OUTSTANDING_ITEMS_EXISTS=1` (see
Step 1). This is strictly the `OUTSTANDING_ITEMS.md` → `BACKLOG.md`
rename, one level up from Step 3b (which may have just created
`OUTSTANDING_ITEMS.md` under its old name this same run — Step 3c runs
after it, per the sequencing note in Step 1).

1. `git mv .session-continuity/OUTSTANDING_ITEMS.md .session-continuity/BACKLOG.md`.
2. Rewrite the moved file's first heading line from `# Outstanding Items
   — <project>` to `# Backlog — <project>`. Also rewrite line 3 (after
   the blank line 2) — the body's opening sentence, currently starting
   "Backlog of explicitly deferred follow-ups..." — to "Explicitly
   deferred follow-ups..." (drop the leading "Backlog of"), so the file
   doesn't read "# Backlog" immediately followed by "Backlog of..."
   (same redundancy Task 1 avoids in the fresh-install template).
   Content and item numbers are otherwise untouched.
3. Grep `.session-continuity/SESSION_PRIMER.md` for any remaining literal
   reference to `OUTSTANDING_ITEMS.md` (a leftover pointer sentence from
   before Step 3b/3c ran) and rewrite each to `BACKLOG.md`.
4. If `.session-continuity/ROADMAP.md` doesn't exist, create it from
   `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/ROADMAP.md`
   with `{{PROJECT_NAME}}` filled from the primer's own project name and
   `{{ROADMAP_NOW}}`/`{{ROADMAP_NEXT}}`/`{{ROADMAP_LATER}}` all set to
   `TBD` — no interactive prompt. Bundled into this same step so the
   rename and the stub land as one migration event/commit, not two.
5. Stage the touched/new files:
   `git add .session-continuity/BACKLOG.md .session-continuity/ROADMAP.md`
   and, only if Step 3 above actually changed it,
   `git add .session-continuity/SESSION_PRIMER.md`.
6. Tell the user: "Migrated `.session-continuity/OUTSTANDING_ITEMS.md` →
   `BACKLOG.md` (N items, numbers preserved) and stubbed in
   `.session-continuity/ROADMAP.md`. Both staged — review before
   committing."
7. Fall through to whichever of refresh mode (Step 4) or check mode
   (Step 5) applies against the now-migrated primer, same fall-through
   convention as Steps 3 and 3b.

**Do not commit automatically.** Staging only — same rule as every other
split/migration step in this command.
```

- [ ] **Step 4: Update Step 4 (Refresh mode) and Step 5 (Check mode) body references**

In Step 4, change every occurrence of `.session-continuity/OUTSTANDING_ITEMS.md` to `.session-continuity/BACKLOG.md` (appears in item 4's "Read `.session-continuity/OUTSTANDING_ITEMS.md`..." sentence, item 6's two sentences, and item 7's `git add` line). Change "Outstanding items" prose label to "Backlog" everywhere it appears as a user-facing label (item 5's question: `"Outstanding items — anything to remove...?"` → `"Backlog — anything to remove...?"`; item 8's confirmation message stays about "the primer", no rename needed there).

In Step 5's gather block, change:
```bash
grep -cE '^### [0-9]+\.' .session-continuity/OUTSTANDING_ITEMS.md 2>/dev/null || echo 0
```
to:
```bash
grep -cE '^### [0-9]+\.' .session-continuity/BACKLOG.md 2>/dev/null || echo 0
```
And in the report block, change:
```
Outstanding items: <count from OUTSTANDING_ITEMS.md>
```
to:
```
Backlog: <count from BACKLOG.md>
```

- [ ] **Step 5: Update the Notes section**

Change:
```markdown
- **Respect the primer-only-commit rule.** If the user asks you to commit only the primer, warn them per `skills/session-continuity/SKILL.md` and proceed only if they confirm it's a catch-up.
```
Leave unchanged (no rename needed). No other Notes-section changes required.

- [ ] **Step 6: Verify — grep sweep of the file**

```bash
grep -n "OUTSTANDING_ITEMS" commands/primer.md
```

Expected: every remaining hit is inside Step 3b (untouched, by design — it still targets the old filename for the inline-heading case) or inside Step 3c/Step 1 where it names the *trigger condition* (`OUTSTANDING_ITEMS_EXISTS`, or the literal old filename being migrated *from*). No hit should be a "current file to read/write" reference outside those two contexts. Read the full grep output and manually confirm each line before proceeding.

- [ ] **Step 7: Commit**

```bash
git add commands/primer.md
git commit -m "feat: primer.md inits BACKLOG.md+ROADMAP.md, migrates old OUTSTANDING_ITEMS.md installs"
```

---

### Task 6: `commands/doctor.md` — track BACKLOG.md and ROADMAP.md

**Files:**
- Modify: `commands/doctor.md`

**Interfaces:**
- Consumes: nothing new — same probe pattern as before, extended to 5 files.

- [ ] **Step 1: Edit the file-existence loop**

Change:
```bash
for f in SESSION_PRIMER.md OUTSTANDING_ITEMS.md PROJECT_CONTEXT.md LEARNINGS.md; do
```
to:
```bash
for f in SESSION_PRIMER.md BACKLOG.md ROADMAP.md PROJECT_CONTEXT.md LEARNINGS.md; do
```

- [ ] **Step 2: Edit row 3's description and the report table**

Change:
```markdown
3. **Four `.session-continuity/` files exist; primer not stale.**
```
to:
```markdown
3. **Five `.session-continuity/` files exist; primer not stale.**
```

In the report table, change:
```markdown
| .session-continuity/ files | ✓ / ⚠️ | "All four present, primer current" OR "⚠️ missing: `<names>`" OR "⚠️ primer stale — run /session-continuity:primer" |
```
to:
```markdown
| .session-continuity/ files | ✓ / ⚠️ | "All five present, primer current" OR "⚠️ missing: `<names>`" OR "⚠️ primer stale — run /session-continuity:primer" |
```

- [ ] **Step 3: Verify**

```bash
grep -En "OUTSTANDING_ITEMS|four \`.session-continuity" commands/doctor.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add commands/doctor.md
git commit -m "feat: doctor.md tracks BACKLOG.md and ROADMAP.md"
```

---

### Task 7: `commands/end-session.md` — rename throughout

**Files:**
- Modify: `commands/end-session.md`

**Interfaces:**
- Consumes: nothing new.

- [ ] **Step 1: Global literal-string rename**

Every occurrence of `.session-continuity/OUTSTANDING_ITEMS.md` → `.session-continuity/BACKLOG.md`, and `OUTSTANDING_ITEMS.md` (bare) → `BACKLOG.md`. This affects (line numbers from the pre-edit file, re-verify after each edit since line numbers shift):

- Step 1's "Outstanding-items verification" sub-heading and its "Data source" line, "Skip conditions" bullets (3 occurrences), and the "For each `### N.` entry in..." line.
- The "Routing `appears-DONE` candidates" prose (no direct filename mention — skip).
- The drift-clean prompt's step 4: `git diff --quiet .session-continuity/OUTSTANDING_ITEMS.md ... git add .session-continuity/OUTSTANDING_ITEMS.md`.
- The Refresh flow's step 3's overlay bullet: `For each \`### N.\` entry in \`.session-continuity/OUTSTANDING_ITEMS.md\``.
- The Refresh flow's step 6: `git diff --quiet .session-continuity/OUTSTANDING_ITEMS.md ... git add .session-continuity/OUTSTANDING_ITEMS.md`.
- Step 3's "Outstanding-items verdicts" bullet: `re-read \`.session-continuity/OUTSTANDING_ITEMS.md\``.
- Step 3's "Outstanding-items row — re-derive, do not cache" paragraph: two occurrences of `.session-continuity/OUTSTANDING_ITEMS.md`.

Do this with `sd` (or `sed`) across the whole file rather than editing each site by hand, then manually re-check every remaining `OUTSTANDING` hit:

```bash
sd '\.session-continuity/OUTSTANDING_ITEMS\.md' '.session-continuity/BACKLOG.md' commands/end-session.md
sd '`OUTSTANDING_ITEMS\.md`' '`BACKLOG.md`' commands/end-session.md
```

- [ ] **Step 2: Rename the user-facing "Outstanding items" label**

The checklist row header and the two user-facing prompt strings say "Outstanding items". Rename all of them to "Backlog":

- Row header in Step 3's table: `| Outstanding items | checkmark if none stale, else warning | ...` → `| Backlog | checkmark if none stale, else warning | ...`.
- Prompt in the drift-clean close-candidate flow: `"Outstanding items — N appears-DONE (see list). Close any, or leave as-is?"` → `"Backlog — N appears-DONE (see list). Close any, or leave as-is?"`.
- Prompt in the Refresh flow: `"Outstanding items — close any from the overlay, add new follow-ups, or no changes?"` → `"Backlog — close any from the overlay, add new follow-ups, or no changes?"`.
- Migration-nudge message: `"This project's outstanding items haven't migrated to \`.session-continuity/OUTSTANDING_ITEMS.md\` yet — run \`/session-continuity:primer\` first (it migrates automatically), then re-run \`/session-continuity:end-session\`."` → `"This project's backlog hasn't migrated to \`.session-continuity/BACKLOG.md\` yet — run \`/session-continuity:primer\` first (it migrates automatically), then re-run \`/session-continuity:end-session\`."` (this message now also covers the OUTSTANDING_ITEMS.md-old-name case, not just the inline-heading case — leave the surrounding skip-condition prose as-is, it already says "unmigrated project" generically).
- Example output block's row: `⚠️ Outstanding items: 5 tracked — ...` → `⚠️ Backlog: 5 tracked — ...`.

- [ ] **Step 3: Verify**

```bash
grep -En "OUTSTANDING_ITEMS|Outstanding items" commands/end-session.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add commands/end-session.md
git commit -m "feat: end-session.md reads/reports BACKLOG.md instead of OUTSTANDING_ITEMS.md"
```

---

### Task 8: `skills/session-continuity/SKILL.md` — rename, five files, add help command

**Files:**
- Modify: `skills/session-continuity/SKILL.md`

**Interfaces:**
- Consumes: nothing new.

- [ ] **Step 1: Frontmatter description (line 3)**

Change:
```markdown
description: Establish and maintain cross-session memory for a project via four in-repo docs — .session-continuity/SESSION_PRIMER.md (current state, refreshed alongside substantive commits), .session-continuity/OUTSTANDING_ITEMS.md (explicitly deferred work), .session-continuity/PROJECT_CONTEXT.md (stable repo context, changes rarely), and .session-continuity/LEARNINGS.md (append-only wisdom for 15+ min bugs). Use when starting, before commits, or after hard-won bugs.
```
to:
```markdown
description: Establish and maintain cross-session memory for a project via five in-repo docs — .session-continuity/SESSION_PRIMER.md (current state, refreshed alongside substantive commits), .session-continuity/BACKLOG.md (explicitly deferred work), .session-continuity/ROADMAP.md (strategic direction), .session-continuity/PROJECT_CONTEXT.md (stable repo context, changes rarely), and .session-continuity/LEARNINGS.md (append-only wisdom for 15+ min bugs). Use when starting, before commits, or after hard-won bugs.
```

- [ ] **Step 2: Intro bullet list (lines 8-15)**

Change the intro line "Four in-repo files act as a handoff..." to "Five in-repo files act as a handoff...".

Change the `OUTSTANDING_ITEMS.md` bullet:
```markdown
- **`.session-continuity/OUTSTANDING_ITEMS.md`** — backlog of explicitly deferred follow-ups and decisions (not bugs, not current state). Permanent numbering (delete-on-close, never renumber, never reuse a number), title + 1-3 sentence length cap per item — anything longer moves to a linked file under `meta/superpowers/`.
```
to:
```markdown
- **`.session-continuity/BACKLOG.md`** — explicitly deferred follow-ups and decisions (not bugs, not current state). Permanent numbering (delete-on-close, never renumber, never reuse a number), title + 1-3 sentence length cap per item — anything longer moves to a linked file under `meta/superpowers/`.
- **`.session-continuity/ROADMAP.md`** — strategic direction: Now/Next/Later. Freeform — no numbering, no permanence rules, no length cap. Rewritten wholesale as direction changes.
```

Change the paragraph after the bullets:
```markdown
The four files are complementary: primer is volatile current-state, OUTSTANDING_ITEMS captures explicitly deferred work, PROJECT_CONTEXT is stable reference, LEARNINGS is durable wisdom. A fresh session reads the primer first to get oriented, skims PROJECT_CONTEXT once per session for the shape of the repo, consults OUTSTANDING_ITEMS for the decision backlog, then consults LEARNINGS when something surprising happens.
```
to:
```markdown
The five files are complementary: primer is volatile current-state, BACKLOG captures explicitly deferred work, ROADMAP captures strategic direction, PROJECT_CONTEXT is stable reference, LEARNINGS is durable wisdom. A fresh session reads the primer first to get oriented, skims PROJECT_CONTEXT once per session for the shape of the repo, consults BACKLOG for the decision backlog, then consults LEARNINGS when something surprising happens.
```

- [ ] **Step 3: Command list (line 17)**

Change:
```markdown
If installed as a plugin, six commands are available: `/session-continuity:primer` (init/split/refresh/check the primer), `/session-continuity:learning` (append a new LEARNINGS entry interactively), `/session-continuity:end-session` (close-out ritual — refresh the primer, capture any new learnings from this session, and report a ✓/⚠️ checklist before you close the laptop), `/session-continuity:spike-check` (force a spike to be designed against the real load-bearing path before it's built), `/session-continuity:doctor` (read-only diagnostic — is the install actually wired up: hooks registered, all four files present and not stale, plugin root resolved and not a stale cache, gate scripts executable), and `/session-continuity:update` (print the commands to pull and activate the plugin's latest published version).
```
to:
```markdown
If installed as a plugin, seven commands are available: `/session-continuity:primer` (init/split/refresh/check the primer), `/session-continuity:learning` (append a new LEARNINGS entry interactively), `/session-continuity:end-session` (close-out ritual — refresh the primer, capture any new learnings from this session, and report a ✓/⚠️ checklist before you close the laptop), `/session-continuity:spike-check` (force a spike to be designed against the real load-bearing path before it's built), `/session-continuity:doctor` (read-only diagnostic — is the install actually wired up: hooks registered, all five files present and not stale, plugin root resolved and not a stale cache, gate scripts executable), `/session-continuity:update` (print the commands to pull and activate the plugin's latest published version), and `/session-continuity:help` (explain what the plugin does and what each file is for).
```

- [ ] **Step 4: Quick-start (new project) section (line 58)**

Change:
```markdown
Run `/session-continuity:primer`. The command detects that no primer exists, copies all four templates from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/` into the project's `.session-continuity/`, fills in every placeholder it can derive automatically (project name, latest commits, working directory, test command), prompts the user for anything left blank, and stages all four files. It does not commit.
```
to:
```markdown
Run `/session-continuity:primer`. The command detects that no primer exists, copies all five templates from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/` into the project's `.session-continuity/`, fills in every placeholder it can derive automatically (project name, latest commits, working directory, test command), prompts the user for anything left blank, and stages all five files. It does not commit.
```

Change the second paragraph:
```markdown
After the user commits, remind them of the two maintenance rules: refresh the primer alongside substantive commits (stage the refresh in the same commit as the real change — do not commit the primer by itself), and add a LEARNINGS entry for every bug that took 15+ minutes to diagnose.
```
Leave unchanged (no rename needed).

Change the fallback sentence:
```markdown
If the `/session-continuity:primer` command is not installed (e.g. this skill was vendored manually, not installed as a plugin), fall back to copying the templates by hand from [`templates/SESSION_PRIMER.md`](templates/SESSION_PRIMER.md), [`templates/OUTSTANDING_ITEMS.md`](templates/OUTSTANDING_ITEMS.md), [`templates/PROJECT_CONTEXT.md`](templates/PROJECT_CONTEXT.md), and [`templates/LEARNINGS.md`](templates/LEARNINGS.md) into the project's `.session-continuity/`, filling placeholders, and committing the set.
```
to:
```markdown
If the `/session-continuity:primer` command is not installed (e.g. this skill was vendored manually, not installed as a plugin), fall back to copying the templates by hand from [`templates/SESSION_PRIMER.md`](templates/SESSION_PRIMER.md), [`templates/BACKLOG.md`](templates/BACKLOG.md), [`templates/ROADMAP.md`](templates/ROADMAP.md), [`templates/PROJECT_CONTEXT.md`](templates/PROJECT_CONTEXT.md), and [`templates/LEARNINGS.md`](templates/LEARNINGS.md) into the project's `.session-continuity/`, filling placeholders, and committing the set.
```

- [ ] **Step 5: Maintenance-rules section (lines 95-110)**

Change:
```markdown
Alongside the primer, also update the separate file
`.session-continuity/OUTSTANDING_ITEMS.md`: remove things you just
finished, add newly-flagged follow-ups from code review or user
feedback.
```
to:
```markdown
Alongside the primer, also update the separate file
`.session-continuity/BACKLOG.md`: remove things you just
finished, add newly-flagged follow-ups from code review or user
feedback.
```

Change:
```markdown
**Numbering convention for OUTSTANDING_ITEMS.md — mirrors LEARNINGS.**
```
to:
```markdown
**Numbering convention for BACKLOG.md — mirrors LEARNINGS.**
```

- [ ] **Step 6: Verify**

```bash
grep -En "OUTSTANDING_ITEMS|four in-repo|four files|four templates" skills/session-continuity/SKILL.md
```

Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add skills/session-continuity/SKILL.md
git commit -m "docs: SKILL.md documents BACKLOG.md, ROADMAP.md, and /help"
```

---

### Task 9: `skills/session-continuity/REFERENCE.md` — rename

**Files:**
- Modify: `skills/session-continuity/REFERENCE.md`

**Interfaces:**
- Consumes: nothing new.

- [ ] **Step 1: Rename each hit**

```
L12: "...injects the outstanding-items shortlist. **Standing rule: whenever you discuss or echo outstanding items to the user — in this reminder, in `/session-continuity:end-session`'s prompts, or in free-form chat when directly asked — render them as a numbered list matching OUTSTANDING_ITEMS.md's own item numbers..."
```
Rename `OUTSTANDING_ITEMS.md` → `BACKLOG.md` in that sentence (keep "outstanding items"/"outstanding-items" prose as lowercase generic English if it reads naturally, but since Goal 1 renames the *concept* label too, replace "outstanding-items shortlist" → "backlog shortlist" and "outstanding items" → "backlog" in that sentence and in "render them as a numbered list matching").

```
L54: | "We should follow up on X" | `.session-continuity/OUTSTANDING_ITEMS.md` → new numbered entry |
```
→ `.session-continuity/BACKLOG.md`.

```
L75: - **"Outstanding items" section.** Use your own taxonomy: "blocked", "deferred", "needs decision". Keep it actionable.
```
→ `- **"Backlog" section.**` (rest unchanged).

```
L104: - OUTSTANDING_ITEMS: "What has been **explicitly deferred** (decisions, follow-ups, follow-ons) that we should not forget?"
```
→ `- BACKLOG: "What has been **explicitly deferred**...` (add a new line directly after it: `- ROADMAP: "Where is this headed, independent of what's in the tactical queue?"`)

```
L108: Together they compress the cost of session handoff from "re-explain everything" to "read a couple of files." The primer stays short (a shortlist, not a snapshot); OUTSTANDING_ITEMS accumulates deferred work; PROJECT_CONTEXT and LEARNINGS both grow organically but at different rates — one when the project's shape changes, the other with every hard-won bug. All four outlive any single session.
```
→
```markdown
Together they compress the cost of session handoff from "re-explain everything" to "read a couple of files." The primer stays short (a shortlist, not a snapshot); BACKLOG accumulates deferred work; ROADMAP holds direction independent of the tactical queue; PROJECT_CONTEXT and LEARNINGS both grow organically but at different rates — one when the project's shape changes, the other with every hard-won bug. All five outlive any single session.
```

- [ ] **Step 2: Verify**

```bash
grep -En "OUTSTANDING_ITEMS|All four" skills/session-continuity/REFERENCE.md
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add skills/session-continuity/REFERENCE.md
git commit -m "docs: REFERENCE.md documents BACKLOG.md and ROADMAP.md"
```

---

### Task 10: Templates `CLAUDE_MD_SNIPPET.md` and `SESSION_PRIMER.md` — rename + add ROADMAP

**Files:**
- Modify: `skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md`
- Modify: `skills/session-continuity/templates/SESSION_PRIMER.md`

**Interfaces:**
- Consumes: nothing new.

- [ ] **Step 1: `CLAUDE_MD_SNIPPET.md`**

Change:
```markdown
Before touching anything, read `.session-continuity/SESSION_PRIMER.md`
(current state) and `.session-continuity/LEARNINGS.md` (bugs that were
expensive to diagnose — grep it when something surprises you). Read
`.session-continuity/PROJECT_CONTEXT.md` once per session for stable repo
shape, and `.session-continuity/OUTSTANDING_ITEMS.md` for the backlog of
deferred decisions and follow-ups; both change rarely.
```
to:
```markdown
Before touching anything, read `.session-continuity/SESSION_PRIMER.md`
(current state) and `.session-continuity/LEARNINGS.md` (bugs that were
expensive to diagnose — grep it when something surprises you). Read
`.session-continuity/PROJECT_CONTEXT.md` once per session for stable repo
shape, `.session-continuity/BACKLOG.md` for deferred decisions and
follow-ups, and `.session-continuity/ROADMAP.md` for strategic direction;
all three change rarely.
```

Change:
```markdown
**Before marking any outstanding item DONE, verify it against the actual
code**
```
to:
```markdown
**Before marking any backlog item DONE, verify it against the actual
code**
```
(rest of that paragraph unchanged — no filename in it).

- [ ] **Step 2: `SESSION_PRIMER.md` template**

Change:
```markdown
You are picking up work on {{PROJECT_NAME}} from a previous session. This
file is the shortest path to what changed recently. For stable repo
context (layout, conventions, modules), read
`.session-continuity/PROJECT_CONTEXT.md` once per session — it changes
rarely. For the backlog of deferred decisions and follow-ups, read
`.session-continuity/OUTSTANDING_ITEMS.md`.
```
to:
```markdown
You are picking up work on {{PROJECT_NAME}} from a previous session. This
file is the shortest path to what changed recently. For stable repo
context (layout, conventions, modules), read
`.session-continuity/PROJECT_CONTEXT.md` once per session — it changes
rarely. For the backlog of deferred decisions and follow-ups, read
`.session-continuity/BACKLOG.md`; for strategic direction, read
`.session-continuity/ROADMAP.md`.
```

- [ ] **Step 3: Verify**

```bash
grep -n "OUTSTANDING_ITEMS" skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md skills/session-continuity/templates/SESSION_PRIMER.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md skills/session-continuity/templates/SESSION_PRIMER.md
git commit -m "docs: template pointers reference BACKLOG.md and ROADMAP.md"
```

---

### Task 11: `plugin.json` version bump, `PRIVACY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `PRIVACY.md`
- Modify: `CONTRIBUTING.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: nothing new.

- [ ] **Step 1: `plugin.json`**

Change:
```json
  "version": "0.21.1",
  "description": "Cross-session memory for Claude Code projects via four in-repo docs: SESSION_PRIMER.md (current state), PROJECT_CONTEXT.md (stable repo context), OUTSTANDING_ITEMS.md (deferred follow-ups), and LEARNINGS.md (hard-won bugs).",
```
to:
```json
  "version": "0.22.0",
  "description": "Cross-session memory for Claude Code projects via five in-repo docs: SESSION_PRIMER.md (current state), PROJECT_CONTEXT.md (stable repo context), BACKLOG.md (deferred follow-ups), ROADMAP.md (strategic direction), and LEARNINGS.md (hard-won bugs).",
```

- [ ] **Step 2: `PRIVACY.md`**

Change:
```markdown
- **File contents in your own repositories.** The slash commands `/session-continuity:primer`, `/session-continuity:learning`, and `/session-continuity:end-session` read and write `.session-continuity/SESSION_PRIMER.md`, `.session-continuity/PROJECT_CONTEXT.md`, `.session-continuity/OUTSTANDING_ITEMS.md`, and `.session-continuity/LEARNINGS.md` in the current git repository. These are ordinary files in your repo; the plugin stores nothing elsewhere. `/session-continuity:spike-check`, `/session-continuity:doctor`, and `/session-continuity:update` touch no files at all — they print a checklist/report/instructions and (for spike-check) ask questions in-conversation.
```
to:
```markdown
- **File contents in your own repositories.** The slash commands `/session-continuity:primer`, `/session-continuity:learning`, and `/session-continuity:end-session` read and write `.session-continuity/SESSION_PRIMER.md`, `.session-continuity/PROJECT_CONTEXT.md`, `.session-continuity/BACKLOG.md`, `.session-continuity/ROADMAP.md`, and `.session-continuity/LEARNINGS.md` in the current git repository. These are ordinary files in your repo; the plugin stores nothing elsewhere. `/session-continuity:spike-check`, `/session-continuity:doctor`, `/session-continuity:update`, and `/session-continuity:help` touch no files at all — they print a checklist/report/instructions and (for spike-check) ask questions in-conversation.
```

- [ ] **Step 3: `CONTRIBUTING.md`**

Change the directory-tree listing:
```
│       └── templates/
│           ├── SESSION_PRIMER.md
│           ├── PROJECT_CONTEXT.md
│           ├── OUTSTANDING_ITEMS.md
│           └── LEARNINGS.md
```
to:
```
│       └── templates/
│           ├── SESSION_PRIMER.md
│           ├── PROJECT_CONTEXT.md
│           ├── BACKLOG.md
│           ├── ROADMAP.md
│           └── LEARNINGS.md
```

And the commands listing:
```
├── commands/
│   ├── primer.md                # /session-continuity:primer
│   ├── learning.md              # /session-continuity:learning
│   ├── end-session.md           # /session-continuity:end-session
│   ├── spike-check.md           # /session-continuity:spike-check
│   ├── doctor.md                # /session-continuity:doctor
│   └── update.md                # /session-continuity:update
```
to:
```
├── commands/
│   ├── primer.md                # /session-continuity:primer
│   ├── learning.md              # /session-continuity:learning
│   ├── end-session.md           # /session-continuity:end-session
│   ├── spike-check.md           # /session-continuity:spike-check
│   ├── doctor.md                # /session-continuity:doctor
│   ├── update.md                # /session-continuity:update
│   └── help.md                  # /session-continuity:help
```

(Verify the exact current `update.md` line's trailing comment/tree-connector characters via `git show HEAD:CONTRIBUTING.md | sed -n '95,112p'` before editing, since the ASCII tree connectors — `├──` vs `└──` — must stay consistent after `update.md` stops being the last entry.)

- [ ] **Step 4: `CHANGELOG.md` — new entry**

Insert a new top entry directly below the `# Changelog` header/intro paragraph, above the existing `## [0.21.1] — 2026-08-31` entry:

```markdown
## [0.22.0] — 2026-08-31

### Added
- **New `.session-continuity/ROADMAP.md` file** — strategic direction (Now/Next/Later), freeform, no numbering. `/session-continuity:primer` creates it on Init mode and stubs it in for existing installs during the BACKLOG.md migration below.
- **New `/session-continuity:help` command** — explains what the plugin does, why, and what each of the five `.session-continuity/` files is for. Zero args, read-only.

### Changed
- **`.session-continuity/OUTSTANDING_ITEMS.md` renamed to `BACKLOG.md`.** Same semantics (permanent numbering, delete-on-close, title + 1-3 sentence cap) — rename only. `/session-continuity:primer` migrates existing installs automatically (new Step 3c): detects `OUTSTANDING_ITEMS.md` without a `BACKLOG.md` alongside it, `git mv`s the file, and stubs in `ROADMAP.md` in the same step. `hooks/session-start.sh` nudges any install still on the old filename to run `/session-continuity:primer`.
```

Use today's date if this task lands on a different day than assumed above — check `date +%Y-%m-%d` and use the actual date, not a hardcoded one.

- [ ] **Step 5: Verify**

```bash
grep -n "OUTSTANDING_ITEMS" .claude-plugin/plugin.json PRIVACY.md CONTRIBUTING.md
```

Expected: no output (CHANGELOG.md is intentionally excluded from this check — its historical entries below the new one still say `OUTSTANDING_ITEMS.md` on purpose).

```bash
grep -m1 '"version"' .claude-plugin/plugin.json
```

Expected: `"version": "0.22.0",`.

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/plugin.json PRIVACY.md CONTRIBUTING.md CHANGELOG.md
git commit -m "chore: bump to 0.22.0 — BACKLOG.md rename, ROADMAP.md, /help command"
```

---

### Task 12: `README.md` — full rename + five-file language + help command

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing new.

- [ ] **Step 1: Top summary line (line 3)**

Change:
```markdown
Cross-session memory for Claude Code projects. A skill Claude loads on its own, four plain-Markdown docs committed to your repo, six slash commands, and a set of session hooks that surface the right knowledge at the right moment.
```
to:
```markdown
Cross-session memory for Claude Code projects. A skill Claude loads on its own, five plain-Markdown docs committed to your repo, seven slash commands, and a set of session hooks that surface the right knowledge at the right moment.
```

- [ ] **Step 2: "Why this exists" section (line ~9)**

Change "Four files hold the memory, four slash commands keep them honest" → "Five files hold the memory, seven slash commands keep them honest".

Change:
```markdown
That's what `.session-continuity/SESSION_PRIMER.md`, `.session-continuity/PROJECT_CONTEXT.md`, `.session-continuity/OUTSTANDING_ITEMS.md`, and `.session-continuity/LEARNINGS.md` buy you: the ability to close the laptop at any point, come back cold, and have a new session up to speed in four file reads instead of rebuilding context by re-prompting.
```
to:
```markdown
That's what `.session-continuity/SESSION_PRIMER.md`, `.session-continuity/PROJECT_CONTEXT.md`, `.session-continuity/BACKLOG.md`, `.session-continuity/ROADMAP.md`, and `.session-continuity/LEARNINGS.md` buy you: the ability to close the laptop at any point, come back cold, and have a new session up to speed in five file reads instead of rebuilding context by re-prompting.
```

- [ ] **Step 3: "What's in the box" table**

Change:
```markdown
| **`session-continuity` skill** | Claude loads it automatically based on the task. It teaches Claude the four-file pattern, the maintenance rules, and the decision tree for what belongs where, even before you run any command. |
```
to:
```markdown
| **`session-continuity` skill** | Claude loads it automatically based on the task. It teaches Claude the five-file pattern, the maintenance rules, and the decision tree for what belongs where, even before you run any command. |
```

Change the `OUTSTANDING_ITEMS.md` row:
```markdown
| **`.session-continuity/OUTSTANDING_ITEMS.md`** | Backlog of explicitly deferred follow-ups and decisions. Permanent numbering, delete-on-close, title + 1-3 sentence cap per item. |
```
to:
```markdown
| **`.session-continuity/BACKLOG.md`** | Explicitly deferred follow-ups and decisions. Permanent numbering, delete-on-close, title + 1-3 sentence cap per item. |
| **`.session-continuity/ROADMAP.md`** | Strategic direction — Now/Next/Later. Freeform, no numbering, rewritten wholesale as direction changes. |
```

Change the `/session-continuity:doctor` row:
```markdown
| **`/session-continuity:doctor`** | Read-only diagnostic: is the install actually wired up — hooks registered, all four files present and not stale, plugin root resolved and not a stale cache, gate scripts executable. |
```
to:
```markdown
| **`/session-continuity:doctor`** | Read-only diagnostic: is the install actually wired up — hooks registered, all five files present and not stale, plugin root resolved and not a stale cache, gate scripts executable. |
```

Add a new row directly after the `/session-continuity:update` row:
```markdown
| **`/session-continuity:help`** | Explain what the plugin does, why, and what each of the five files is for. |
```

- [ ] **Step 4: "The four files" section → "The five files"**

Change the heading `## The four files` to `## The five files`.

Change:
```markdown
**`.session-continuity/OUTSTANDING_ITEMS.md`** is the backlog: explicitly
deferred decisions and follow-ups, not bugs and not current state. Item
numbers are permanent — a closed item is deleted outright, never
renumbered — so a cross-reference to "item 4" stays valid for as long as
item 4 exists. Each item is capped at a title plus 1-3 sentences; anything
longer belongs in a linked spec, not inlined here.
```
to:
```markdown
**`.session-continuity/BACKLOG.md`** is the tactical queue: explicitly
deferred decisions and follow-ups, not bugs and not current state. Item
numbers are permanent — a closed item is deleted outright, never
renumbered — so a cross-reference to "item 4" stays valid for as long as
item 4 exists. Each item is capped at a title plus 1-3 sentences; anything
longer belongs in a linked spec, not inlined here.

**`.session-continuity/ROADMAP.md`** is strategic direction, independent
of the tactical queue — Now/Next/Later, freeform. No numbering, no
permanence rules, no length cap; rewrite it wholesale as direction
changes rather than editing around old entries.
```

Change:
```markdown
All four files ship as templates, so you start from a real structure instead of a blank page.
```
to:
```markdown
All five files ship as templates, so you start from a real structure instead of a blank page.
```

- [ ] **Step 5: "The commands" section — primer's five behaviors → six**

Change:
```markdown
One command, five behaviors, dispatched on the repo's current state:
```
to:
```markdown
One command, six behaviors, dispatched on the repo's current state:
```

Change:
```markdown
- **Primer has an inline Outstanding items section, no OUTSTANDING_ITEMS.md yet** → extracts that section verbatim into the new file, preserving item numbers as permanent IDs, and removes it from the primer. Runs immediately on detection — this plugin has one consumer today, so migration is pushed, not offered indefinitely.
```
to (keep as-is, then add a new bullet directly after it):
```markdown
- **Primer has an inline Outstanding items section, no BACKLOG.md yet** → extracts that section verbatim into the new file, preserving item numbers as permanent IDs, and removes it from the primer. Runs immediately on detection — this plugin has one consumer today, so migration is pushed, not offered indefinitely.
- **Project has the old `OUTSTANDING_ITEMS.md` file, no `BACKLOG.md` yet** → renames it to `BACKLOG.md` (numbers and content unchanged) and stubs in `ROADMAP.md` if it doesn't already exist. Runs immediately on detection, same push-not-offer policy as the bullet above.
```

Change:
```markdown
- **Primer current** → reports a four-line status (HEAD, last refresh, outstanding-item count, learnings count) and exits without touching anything.
```
to:
```markdown
- **Primer current** → reports a four-line status (HEAD, last refresh, backlog count, learnings count) and exits without touching anything.
```

- [ ] **Step 6: "What goes where" table and "Why four files" → "Why five files" section**

Change:
```markdown
| "We should follow up on X" | `.session-continuity/OUTSTANDING_ITEMS.md` → new numbered entry |
```
to:
```markdown
| "We should follow up on X" | `.session-continuity/BACKLOG.md` → new numbered entry |
| "Where is this headed next quarter" | `.session-continuity/ROADMAP.md` → Now/Next/Later |
```

Change the heading `## Why four files` to `## Why five files`.

Change:
```markdown
**OUTSTANDING_ITEMS** shares PROJECT_CONTEXT's slow pace, but not its permanence: unlike LEARNINGS' append-only history, closed items are deleted outright, so the file only ever holds the live backlog, never a full record of everything ever deferred.
```
to:
```markdown
**BACKLOG** shares PROJECT_CONTEXT's slow pace, but not its permanence: unlike LEARNINGS' append-only history, closed items are deleted outright, so the file only ever holds the live backlog, never a full record of everything ever deferred.

**ROADMAP** is the newest of the five and the least ceremonious: no numbering, no permanence, no length cap. It exists because "what's the tactical backlog" and "what's the strategic direction" are different questions with different lifespans — a backlog item resolves in days or weeks; a roadmap entry describes a horizon that outlives any single item.
```

Change:
```markdown
Blending any of these forces bad tradeoffs. Current-state notes drown stable context or accumulated wisdom; wisdom gets edited away when someone trims "stale" entries. Keeping them in separate files with separate update contracts means the primer answers "what is true right now," PROJECT_CONTEXT answers "what is true about this project generally," OUTSTANDING_ITEMS answers "what have we deliberately deferred," and LEARNINGS answers "what should I know to avoid rediscovering pain" — and none of the four pretends to answer another's question.
```
to:
```markdown
Blending any of these forces bad tradeoffs. Current-state notes drown stable context or accumulated wisdom; wisdom gets edited away when someone trims "stale" entries. Keeping them in separate files with separate update contracts means the primer answers "what is true right now," PROJECT_CONTEXT answers "what is true about this project generally," BACKLOG answers "what have we deliberately deferred," ROADMAP answers "where is this headed," and LEARNINGS answers "what should I know to avoid rediscovering pain" — and none of the five pretends to answer another's question.
```

- [ ] **Step 7: Verify**

```bash
grep -En "OUTSTANDING_ITEMS|four plain-Markdown|six slash commands|four-file pattern|four files|four file reads|All four files|five behaviors|Why four files|none of the four" README.md
```

Expected: no output. (Run this, read every hit, fix, re-run — README.md is the largest single-file diff in this plan and the most likely place to miss one.)

- [ ] **Step 8: Commit**

```bash
git add README.md
git commit -m "docs: README documents BACKLOG.md, ROADMAP.md, and /help"
```

---

### Task 13: Dogfood — migrate this repo's own `.session-continuity/` instance

**Files:**
- Modify: `.session-continuity/OUTSTANDING_ITEMS.md` → `.session-continuity/BACKLOG.md` (rename)
- Create: `.session-continuity/ROADMAP.md`
- Modify: `.session-continuity/SESSION_PRIMER.md`

**Interfaces:**
- Consumes: Task 5's Step 3c logic (executed manually here, by hand, since running the actual `/session-continuity:primer` command from inside its own repo mid-implementation is circular — this task performs the same operations Step 3c specifies, verifying the spec's migration steps are correct by executing them for real).

- [ ] **Step 1: Rename**

```bash
git mv .session-continuity/OUTSTANDING_ITEMS.md .session-continuity/BACKLOG.md
```

Edit the moved file's first line from `# Outstanding Items — session-continuity` to `# Backlog — session-continuity`, and line 3 (after the blank line 2 — the body's opening sentence) from "Backlog of explicitly deferred follow-ups and decisions — not bugs (those" to "Explicitly deferred follow-ups and decisions — not bugs (those" — same redundancy fix as Task 5's Step 3c. Leave the four numbered items (1–4) and all other prose unchanged.

- [ ] **Step 2: Stub `ROADMAP.md`**

```markdown
# Roadmap — session-continuity

Strategic direction — where this project is headed, not the tactical
queue (that's `.session-continuity/BACKLOG.md`). Freeform: no numbering,
no permanence rules, no length cap. Rewrite sections wholesale as
direction changes; this file's history lives in git, not in careful
edits.

## Now

TBD

## Next

TBD

## Later

TBD
```

- [ ] **Step 3: Update `.session-continuity/SESSION_PRIMER.md`'s live repo-layout line**

Change (this is a live description of current repo layout, not historical narrative — it must be updated):
```markdown
- `.session-continuity/` holds `SESSION_PRIMER.md`, `PROJECT_CONTEXT.md` (new in v0.13.0), `OUTSTANDING_ITEMS.md` (new in v0.18.0), and `LEARNINGS.md`. Dev artifacts (marketplace-submission notes, specs, plans, recommendation docs) live under `meta/`.
```
to:
```markdown
- `.session-continuity/` holds `SESSION_PRIMER.md`, `PROJECT_CONTEXT.md` (new in v0.13.0), `BACKLOG.md` (new in v0.18.0 as `OUTSTANDING_ITEMS.md`, renamed in v0.22.0), `ROADMAP.md` (new in v0.22.0), and `LEARNINGS.md`. Dev artifacts (marketplace-submission notes, specs, plans, recommendation docs) live under `meta/`.
```

**Leave the other hit (the "v0.12.3 shipped" historical bullet describing the SessionStart hook's original inline-heading behavior, containing the phrase `extracts the "Outstanding items" section`) unchanged** — it's a historical record of what v0.12.3 did, predating even the old `OUTSTANDING_ITEMS.md` file's existence, and rewriting it would misrepresent history. Confirm this is the only other hit before moving on:

```bash
grep -En "OUTSTANDING|Outstanding" .session-continuity/SESSION_PRIMER.md
```

Expected: exactly one hit, the "v0.12.3 shipped" historical bullet.

- [ ] **Step 4: Regenerate the primer's `git log --oneline -5` block and add a current-state note**

```bash
git log --oneline -5
```

Update `.session-continuity/SESSION_PRIMER.md`'s `git log --oneline -5` block to match, and prepend a one-line note to the "Current state" narrative: `- **v0.22.0 in progress** — renamed OUTSTANDING_ITEMS.md to BACKLOG.md, added ROADMAP.md, added /session-continuity:help. Branch feature/backlog-roadmap-help, not yet merged.` This follows this repo's own maintenance rule (refresh the primer alongside substantive commits) — Task 14 will update this note once more to say "shipped" after the PR merges, per this repo's own primer-maintenance convention for release bullets.

- [ ] **Step 5: Verify**

```bash
grep -c "^### [0-9]\+\." .session-continuity/BACKLOG.md
```

Expected: `4` (all four existing items preserved, numbers unchanged).

```bash
diff <(git show HEAD:.session-continuity/OUTSTANDING_ITEMS.md | tail -n +4) <(tail -n +4 .session-continuity/BACKLOG.md)
```

Expected: no output (lines 1-3 — title, blank, reworded opening sentence — are excluded by `tail -n +4`; everything from line 4 onward, including all four numbered items, must be byte-identical).

- [ ] **Step 6: Commit**

```bash
git add .session-continuity/BACKLOG.md .session-continuity/ROADMAP.md .session-continuity/SESSION_PRIMER.md
git commit -m "docs: migrate this repo's own OUTSTANDING_ITEMS.md to BACKLOG.md, add ROADMAP.md"
```

---

### Task 14: Final full-repo verification and PR

**Files:** none (verification + PR only).

**Interfaces:**
- Consumes: the completed state of all prior tasks.

- [ ] **Step 1: Full-repo grep sweep**

```bash
grep -rn "OUTSTANDING_ITEMS" --include="*.md" --include="*.sh" --include="*.json" . 2>/dev/null | grep -v node_modules
```

Expected: every remaining hit is one of:
- `CHANGELOG.md` — historical entries below the new `[0.22.0]` entry (intentional, per Global Constraints).
- `commands/primer.md` — Step 1's `OUTSTANDING_ITEMS_EXISTS` variable name and Step 3b/3c's references to the *old filename being migrated from* (intentional, per Task 5).
- `hooks/session-start.sh` — the new elif branch's literal old-filename check and its warning message (intentional, per Task 4).
- `meta/superpowers/plans/*`, `meta/superpowers/specs/*`, `meta/superpowers/recommendations/*`, `meta/superpowers/validation/*` — historical design docs from before this change (out of scope — these describe decisions made under the old name; not rewritten).

If any hit doesn't fit one of the four buckets above, go back and fix the file it's in.

- [ ] **Step 2: Confirm no leftover template placeholder syntax**

```bash
grep -rn "{{OUTSTANDING_ITEMS}}" .
```

Expected: no output.

- [ ] **Step 3: Shellcheck the modified hook**

```bash
shellcheck hooks/session-start.sh
```

Expected: no warnings (already checked in Task 4, re-confirming after all edits landed).

- [ ] **Step 4: Manually exercise `/session-continuity:doctor` against this repo**

Since there's no automated harness, manually run the Bash block from `commands/doctor.md`'s Step 1 against this repo's own working tree and confirm the five-file loop reports `BACKLOG.md=EXISTS`, `ROADMAP.md=EXISTS`, `SESSION_PRIMER.md=EXISTS`, `PROJECT_CONTEXT.md=EXISTS`, `LEARNINGS.md=EXISTS`.

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin feature/backlog-roadmap-help
gh pr create --title "Rename OUTSTANDING_ITEMS.md to BACKLOG.md, add ROADMAP.md and /help" --body "$(cat <<'EOF'
## Summary
- Renames `.session-continuity/OUTSTANDING_ITEMS.md` to `BACKLOG.md` everywhere (template, commands, hooks, skill docs), with an automatic migration path (`primer.md` Step 3c) for existing installs.
- Adds a new `.session-continuity/ROADMAP.md` stub file for strategic direction (Now/Next/Later), separate from the tactical BACKLOG.
- Adds `/session-continuity:help` — explains the plugin's purpose and what each of the five files is for.
- Migrates this repo's own `.session-continuity/` instance as proof the migration path works.
- Bumps `0.21.1` → `0.22.0`.

## Test plan
- [x] Manual grep-invariant checks after every file edit (see plan tasks 1–13's verify steps)
- [x] `shellcheck hooks/session-start.sh` clean
- [x] Manual smoke test of the new `session-start.sh` elif branch against a scratch repo
- [x] Manual dry-run of `commands/doctor.md`'s file-existence loop against this repo
- [x] Full-repo grep sweep confirms no unintentional leftover `OUTSTANDING_ITEMS` reference

Spec: `meta/superpowers/specs/2026-08-31-backlog-roadmap-help-design.md`
Plan: `meta/superpowers/plans/2026-08-31-backlog-roadmap-help.md`
EOF
)"
```
