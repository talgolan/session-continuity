# Primer volatile/stable split — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `.session-continuity/SESSION_PRIMER.md` into a volatile
shortlist (kept in `SESSION_PRIMER.md`) and stable reference material (moved
to a new `.session-continuity/PROJECT_CONTEXT.md`), with automatic migration
for existing unsplit projects and no change required for hooks.

**Architecture:** Two-file split with a content-boundary defined in the
spec. `commands/primer.md` gains a detection state + Split mode that
performs a one-time content move (not a file move — no `git mv`, since no
path is being renamed, content is being partitioned between two files).
Init mode is extended to seed both files from the start. Hooks are
untouched because their logic only ever reads the volatile file or matches
a directory prefix that already covers the new file.

**Tech Stack:** Markdown prose (slash-command skill bodies), bash (hooks,
unchanged), no build step, no automated test runner (this repo has none —
validation is manual, per its own stable "Test expectations" section).

**Spec:** `meta/superpowers/specs/2026-08-13-primer-volatile-stable-split-design.md`

## Global Constraints

- Canonical directory is `.session-continuity/` (v0.5.0+). Never write to
  `docs/` for new files.
- Never commit automatically — every task stages with `git add`, never
  `git commit`.
- Never delete or truncate `.session-continuity/LEARNINGS.md` history or
  numbering — this plan does not touch that file.
- Semantic versioning: bump `.claude-plugin/plugin.json` (`0.12.3` →
  `0.13.0`, minor — new file/feature, no breaking removal) and add a
  `CHANGELOG.md` `[0.13.0]` entry in the same commit as the feature.
- Conventional commit messages (`feat:`, `docs:`, `chore:`).

---

### Task 1: New PROJECT_CONTEXT.md template + trim SESSION_PRIMER.md template

**Files:**
- Create: `skills/session-continuity/templates/PROJECT_CONTEXT.md`
- Modify: `skills/session-continuity/templates/SESSION_PRIMER.md`

**Interfaces:**
- Consumes: nothing (templates are static files copied verbatim by
  `commands/primer.md`).
- Produces: the two template files that Task 2's Init mode and Split mode
  read placeholder tokens from. Placeholder token names introduced here
  (`{{PROJECT_NAME}}`, `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}`, etc.) must
  match exactly what Task 2 references.

- [ ] **Step 1: Read the current template to identify the exact split line**

Read `skills/session-continuity/templates/SESSION_PRIMER.md` in full (91
lines as of this plan). Identify which existing sections are stable
(everything except the intro line and whatever volatile placeholders exist
for "Current state" / "Outstanding items" — note this template currently
has **no** Current-state/Outstanding-items placeholder section at all; it
only has the layer/entry structure inherited from being copied from an
earlier, unsplit design). Cross-check against
`.session-continuity/SESSION_PRIMER.md` (this repo's own file, already
split conceptually per the spec) for the authoritative section list:

Stable (→ new template): Ground rules, First things first, Repo layout,
Working directory, The packages/modules, Test expectations, End-to-end
check, Workflow conventions, Where to look for what, If you get stuck,
Maintenance.

Volatile (stays in `SESSION_PRIMER.md` template): intro line, Current
state, Outstanding items.

- [ ] **Step 2: Write `skills/session-continuity/templates/PROJECT_CONTEXT.md`**

```markdown
# Project Context — {{PROJECT_NAME}}

Stable reference material for this project — layout, conventions, where to
look for what. Changes rarely; when it does, the change is usually the
point of a commit, not a side effect of one. For what changed recently and
what's outstanding, see `.session-continuity/SESSION_PRIMER.md` instead.

## Ground rules (how to work here)

{{GROUND_RULES}}

<!-- Example:
1. Don't assume. Don't hide confusion. Surface tradeoffs.
2. Minimum code that solves the problem. Nothing speculative.
3. Touch only what you must. Clean up only your own mess.
4. Define success criteria. Loop until verified.
-->

## Repo layout

{{REPO_LAYOUT_SUMMARY}}

<!-- Key paths, one bullet each. Note any install/setup commands. -->

## Working directory

```
{{WORKING_DIRECTORY_ABSOLUTE_PATH}}
```

{{WORKING_DIRECTORY_NOTES}}
<!-- Symlinks, worktrees, or other non-obvious path facts. Delete this line if none. -->

## The packages / modules

{{MODULES_TABLE}}

<!-- | Component | Purpose | Notes |
     |---|---|---|
     | ... | ... | ... | -->

## Test expectations — these must stay green

{{TEST_COMMAND_SUMMARY}}

<!-- e.g. "`{{TEST_COMMAND_1}}` — N pass / 0 fail" or "No automated test
     suite; validation is manual: ..." -->

## End-to-end check (real integration)

{{END_TO_END_CHECK}}

## Workflow conventions

{{WORKFLOW_CONVENTIONS}}

<!-- e.g. runtime choice, versioning scheme, commit message style,
     "never commit X alone" rules. -->

## Where to look for what

| Question | File |
|---|---|
{{WHERE_TO_LOOK_ROWS}}

## If you get stuck

In order of cost:

{{STUCK_ESCALATION_STEPS}}

<!-- Example:
1. Grep `.session-continuity/LEARNINGS.md` for your symptom.
2. Query the session memory system with your symptom.
3. Check for stale state (processes, caches, lockfiles) before assuming a code bug.
4. Ask the user.
-->

## Maintenance (your responsibility)

This file changes rarely — only when the project's shape changes (new
module, new convention, moved directory). For the file that changes with
every substantive commit, see `.session-continuity/SESSION_PRIMER.md` and
its own "Primer maintenance" section.

When you do edit this file, stage it alongside the change that made the
edit necessary — same non-standalone-commit discipline as the primer.
```

- [ ] **Step 3: Rewrite `skills/session-continuity/templates/SESSION_PRIMER.md`**

Replace the file with:

```markdown
# Session Primer — {{PROJECT_NAME}}

You are picking up work on {{PROJECT_NAME}} from a previous session. This
file is the shortest path to what changed recently and what's outstanding.
For stable repo context (layout, conventions, modules), read
`.session-continuity/PROJECT_CONTEXT.md` once per session — it changes
rarely.

## First things first (read these before touching anything)

1. **`.session-continuity/PROJECT_CONTEXT.md`** — stable repo context:
   layout, conventions, where to look for what.
2. **`.session-continuity/LEARNINGS.md`** — graveyard of subtle bugs,
   grouped by layer. If you hit something weird, grep this file first.
3. **Session memory system** (if the user has one in place) — prior
   sessions may have left searchable context. Query before guessing.

## Current state

{{CURRENT_STATE_SUMMARY}}

**Current `git log --oneline -5` (primary branch):**

```
{{LATEST_COMMIT_HASH_1}} {{LATEST_COMMIT_SUBJECT_1}}
{{LATEST_COMMIT_HASH_2}} {{LATEST_COMMIT_SUBJECT_2}}
{{LATEST_COMMIT_HASH_3}} {{LATEST_COMMIT_SUBJECT_3}}
{{LATEST_COMMIT_HASH_4}} {{LATEST_COMMIT_SUBJECT_4}}
{{LATEST_COMMIT_HASH_5}} {{LATEST_COMMIT_SUBJECT_5}}
```

Regenerate this block whenever you commit — see
`.session-continuity/PROJECT_CONTEXT.md`'s "Maintenance" section.

## Outstanding items (explicitly deferred — not bugs, decisions)

{{OUTSTANDING_ITEMS}}

<!-- Numbered list. One decision/deferral per item, with a one-line reason. -->
```

- [ ] **Step 4: Check for placeholder-token collisions between the two templates**

Run: `grep -oE '\{\{[A-Z_0-9]+\}\}' skills/session-continuity/templates/PROJECT_CONTEXT.md skills/session-continuity/templates/SESSION_PRIMER.md | sort -u`

Expected: every token appears in exactly one file (no token defined in
both — that would signal an ambiguous fill target for Task 2's Init mode).
Confirm by eye against the list above.

- [ ] **Step 5: Stage**

```bash
git add skills/session-continuity/templates/PROJECT_CONTEXT.md skills/session-continuity/templates/SESSION_PRIMER.md
```

---

### Task 2: `commands/primer.md` — split-mode detection, Split mode, Init mode update

**Files:**
- Modify: `commands/primer.md`

**Interfaces:**
- Consumes: `skills/session-continuity/templates/PROJECT_CONTEXT.md` (Task
  1) as the template Init mode copies.
- Produces: the Split-mode algorithm other tasks (5) apply by hand to this
  repo's own primer.

- [ ] **Step 1: Update Step 1 "Detect state" with the 6th state**

In `commands/primer.md`, after the existing check list (currently 4 numbered
checks under "## Step 1 — Detect state"), add a 5th check:

```markdown
5. If a primer exists at the canonical location, does
   `.session-continuity/PROJECT_CONTEXT.md` also exist?
```

Update the "Five states result:" line to "Six states result:" and add a new
bullet, inserted between the existing "Conflicting layouts" and "Primer
exists at canonical path but stale" bullets (ordering matters: split
detection must run before refresh/check dispatch, since a stale+unsplit
primer should split first, then refresh):

```markdown
- **Canonical primer exists but unsplit** (no `PROJECT_CONTEXT.md` yet) → split mode (Step 5)
```

Renumber: old Step 5 "Refresh mode" becomes Step 6, old Step 6 "Check mode"
becomes Step 7.

- [ ] **Step 2: Write the new "Step 5 — Split mode" section**

Insert after the (unchanged) "Step 4 — Conflict mode" section:

```markdown
## Step 5 — Split mode

The repo has a canonical `.session-continuity/SESSION_PRIMER.md` but no
`.session-continuity/PROJECT_CONTEXT.md` — it predates the volatile/stable
split. Partition its content; this is a one-time content move, not a file
move (no `git mv` — the primer's path doesn't change, only what it
contains).

1. Read the existing `.session-continuity/SESSION_PRIMER.md` in full.
2. Sort its `## `-level sections into two groups:
   - **Stable** (moves to the new file): Ground rules, Repo layout,
     Working directory, The packages / modules, Test expectations,
     End-to-end check, Workflow conventions, Where to look for what, If you
     get stuck, Primer maintenance / Maintenance.
   - **Volatile** (stays): the intro paragraph, First things first, Current
     state (including the `git log --oneline -5` block), Outstanding items.
   If a section doesn't match any name above exactly (the project may have
   added custom sections), ask the user which half it belongs to rather
   than guessing.
3. Write `.session-continuity/PROJECT_CONTEXT.md`: a new intro line ("Stable
   reference material for `<project>`...", matching the template's tone in
   `skills/session-continuity/templates/PROJECT_CONTEXT.md`) followed by
   every stable section, content unchanged, heading text unchanged (except
   "Primer maintenance (your responsibility)" is renamed "Maintenance (your
   responsibility)" and its body updated to describe both files — see Task
   1's template for the target wording).
4. Rewrite `.session-continuity/SESSION_PRIMER.md`: keep the intro
   paragraph (add one sentence pointing to `PROJECT_CONTEXT.md` for stable
   context), keep "First things first" but add a bullet at the top pointing
   to `.session-continuity/PROJECT_CONTEXT.md`, keep Current state and
   Outstanding items verbatim. Drop every section moved to
   `PROJECT_CONTEXT.md`.
5. Stage both: `git add .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md`.
6. Tell the user: "Split `.session-continuity/SESSION_PRIMER.md` into the
   volatile primer and a new `.session-continuity/PROJECT_CONTEXT.md` for
   stable context. Both staged — review the section boundaries before
   committing."
7. Fall through into whichever of refresh mode (Step 6) or check mode
   (Step 7) applies against the now-split primer, same pattern Migrate mode
   already uses (Step 2, point 6).

**Do not commit automatically.** Staging only.
```

- [ ] **Step 3: Update Init mode (renumbered — was Step 3, stays Step 3) to seed the third file**

In the existing Init mode numbered list, after the line that copies
`LEARNINGS.md`'s template, insert:

```markdown
3a. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/PROJECT_CONTEXT.md` to `.session-continuity/PROJECT_CONTEXT.md`.
```

(Renumber the subsequent steps in that list by one.) Extend the "Fill in
placeholders Claude can derive automatically" list with the
`PROJECT_CONTEXT.md`-specific tokens:
- `{{REPO_LAYOUT_SUMMARY}}` — best-effort from `find . -maxdepth 2 -not -path './node_modules/*' -not -path './.git/*'` plus a one-line description Claude infers from file extensions present.
- `{{MODULES_TABLE}}` — leave as `TBD` unless the project has an obvious
  package/module manifest to read (package.json workspaces, Cargo
  workspace members, etc.) — don't invent structure that isn't there.

Extend the "Ask the user for the blanks that can't be derived" list to
include: `{{GROUND_RULES}}`, `{{WORKFLOW_CONVENTIONS}}`,
`{{WHERE_TO_LOOK_ROWS}}`, `{{STUCK_ESCALATION_STEPS}}` (in addition to the
existing outstanding-items ask, which stays with the primer).

Update the final "Stage both files" line to "Stage all three files:
`git add .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .session-continuity/LEARNINGS.md`."

- [ ] **Step 4: Update the "## Notes" section**

Add one bullet:

```markdown
- **Split mode never deletes.** Like Migrate mode, it only adds/rewrites
  tracked files — the original content survives in git history even though
  it's been moved between files.
```

- [ ] **Step 5: Check the renumbering is internally consistent**

Run: `grep -n '^## Step' commands/primer.md`

Expected output, in order: Step 1, Step 2, Step 3, Step 4, Step 5 (new
Split mode), Step 6 (was Step 5, Refresh mode), Step 7 (was Step 6, Check
mode). Confirm every cross-reference inside the file (e.g. "fall through
into refresh mode (Step 5)" in old Migrate mode) was updated to the new
number. Run: `grep -n 'Step [0-9]' commands/primer.md` and manually check
each parenthetical step reference against the renumbered headings.

- [ ] **Step 6: Stage**

```bash
git add commands/primer.md
```

---

### Task 3: `commands/end-session.md` — stage PROJECT_CONTEXT.md when touched

**Files:**
- Modify: `commands/end-session.md`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing other tasks depend on — this is a leaf change.

- [ ] **Step 1: Locate the existing staging step**

Read `commands/end-session.md` around line 147 (`Stage the updated primer:
git add .session-continuity/SESSION_PRIMER.md.`).

- [ ] **Step 2: Extend the staging step**

Replace that single `git add` instruction with:

```markdown
6. Stage the updated primer, and `PROJECT_CONTEXT.md` too if it has
   unstaged changes (e.g. the session edited repo layout / conventions):

   ```bash
   git add .session-continuity/SESSION_PRIMER.md
   git diff --quiet .session-continuity/PROJECT_CONTEXT.md 2>/dev/null || git add .session-continuity/PROJECT_CONTEXT.md
   ```
```

- [ ] **Step 3: Check no other end-session step assumes only two files**

Run: `grep -n 'SESSION_PRIMER\|PROJECT_CONTEXT\|LEARNINGS' commands/end-session.md`

Confirm the preflight section (checks `.session-continuity/SESSION_PRIMER.md`
and `.session-continuity/LEARNINGS.md` exist) does **not** need
`PROJECT_CONTEXT.md` to exist (an unsplit or pre-migration project is a
valid state end-session already tolerates; don't add a hard dependency).

- [ ] **Step 4: Stage**

```bash
git add commands/end-session.md
```

---

### Task 4: `skills/session-continuity/SKILL.md` doc updates

**Files:**
- Modify: `skills/session-continuity/SKILL.md`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other tasks depend on — leaf change.

- [ ] **Step 1: Read the current file in full**

Read `skills/session-continuity/SKILL.md` (141+ lines) to find every place
that names the two files as a pair.

- [ ] **Step 2: Update the "two files" framing to three**

Wherever the file says "two in-repo docs" or lists exactly
`SESSION_PRIMER.md` + `LEARNINGS.md` as *the* files (the frontmatter
`description` line, the opening paragraph, and the numbered file
descriptions around lines 10-11), add `PROJECT_CONTEXT.md` as a third,
described as: "stable repo context (layout, conventions, modules) —
changes rarely, only when the project's shape changes."

- [ ] **Step 3: Update "Quick start (new project)"**

Add a mention that Init mode copies all three templates now (currently says
"copies both templates" — becomes "copies all three templates").

- [ ] **Step 4: Add a "Quick start (unsplit primer)" section**

Insert a new subsection parallel to the existing "Quick start (pre-v0.5.0
project — files still under `docs/`)" section:

```markdown
## Quick start (existing primer, not yet split)

If a project has `.session-continuity/SESSION_PRIMER.md` but no
`.session-continuity/PROJECT_CONTEXT.md`, it predates the volatile/stable
split. Run `/session-continuity:primer` — it detects the unsplit shape and
partitions the content automatically (Split mode). Review the section
boundaries before committing.
```

- [ ] **Step 5: Update the "Where to look for what" table**

Find the table rows that point at `SESSION_PRIMER.md` for stable questions
(repo layout, module table, conventions — likely near lines 114-120).
Repoint them to `PROJECT_CONTEXT.md`. Leave rows about "what changed
recently" / "current state" / "outstanding items" pointed at
`SESSION_PRIMER.md`.

- [ ] **Step 6: Stage**

```bash
git add skills/session-continuity/SKILL.md
```

---

### Task 5: Dogfood — split this repo's own primer, bump version, changelog

**Files:**
- Create: `.session-continuity/PROJECT_CONTEXT.md`
- Modify: `.session-continuity/SESSION_PRIMER.md`
- Modify: `.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Task 2's Split-mode algorithm (applied by hand here, since this
  repo's own primer is the unsplit-primer test case).
- Produces: nothing — terminal task for the repo's own files.

- [ ] **Step 1: Apply Split mode to this repo's primer by hand**

Read the current `.session-continuity/SESSION_PRIMER.md` (276 lines as of
this plan). Following Task 2 Step 2's algorithm: create
`.session-continuity/PROJECT_CONTEXT.md` containing Ground rules, Repo
layout, Working directory, The packages/modules, Test expectations,
End-to-end check, Workflow conventions, Where to look for what, If you get
stuck, and a renamed "Maintenance (your responsibility)" section (update its
body to describe maintaining both files — this file rarely, the primer with
every substantive commit).

Rewrite `.session-continuity/SESSION_PRIMER.md` to keep only: intro
(add the one-sentence pointer to `PROJECT_CONTEXT.md`), First things first
(add the `PROJECT_CONTEXT.md` bullet at the top), Current state (including
the git-log block), Outstanding items.

Note while splitting: the primer's Outstanding item #2 sub-bullets already
record the 2026-08-13 override decisions for §4.2/§4.3/§6 — carry those
notes over into the new `SESSION_PRIMER.md`'s Outstanding items section
unchanged; don't drop them.

- [ ] **Step 2: Check nothing was lost**

Run: `wc -l .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md`

Compare the combined line count against the pre-split 276 lines,
accounting for the small amount of added prose (new intro sentences,
renamed section). Spot-check by grepping a few distinctive phrases from the
pre-split file to confirm each landed in the expected file:

```bash
grep -l "The repo also lives at" .session-continuity/*.md   # expect PROJECT_CONTEXT.md
grep -l "9166fec" .session-continuity/*.md                   # expect SESSION_PRIMER.md
```

- [ ] **Step 3: Update Current state and bump the version**

Add a new bullet at the top of `SESSION_PRIMER.md`'s Current state section:
"**v0.13.0 shipped** — split `.session-continuity/SESSION_PRIMER.md` into
volatile (`SESSION_PRIMER.md`) and stable (`PROJECT_CONTEXT.md`) halves,
overriding the prior §6 rejection on explicit request 2026-08-13. Also
shipped this session: LEARNINGS.md gained an auto-generated Symptoms index
and `[[slug]]` cross-references (§4.2/§4.3, same override). Spec:
`meta/superpowers/specs/2026-08-13-primer-volatile-stable-split-design.md`.
Plan: `meta/superpowers/plans/2026-08-13-primer-volatile-stable-split.md`."

Regenerate the `git log --oneline -5` block with the actual current output
of that command at commit time (do this as the very last edit before
staging, so it reflects the true HEAD).

In `.claude-plugin/plugin.json`, bump `"version"` from `"0.12.3"` to
`"0.13.0"`.

- [ ] **Step 4: Add the CHANGELOG entry**

In `CHANGELOG.md`, insert above the `## [0.12.3]` entry:

```markdown
## [0.13.0] — 2026-08-13

### Added
- **Split `SESSION_PRIMER.md` into volatile + stable files.** Stable repo
  context (ground rules, repo layout, module table, workflow conventions,
  "where to look for what") now lives in a new
  `.session-continuity/PROJECT_CONTEXT.md`, seeded by Init mode and
  auto-migrated from unsplit primers by a new Split mode in
  `commands/primer.md`. `SESSION_PRIMER.md` keeps only the volatile
  shortlist: current state, the `git log --oneline -5` block, and
  outstanding items. No hook changes needed — `pre-commit-check.sh`'s
  `.session-continuity/` allowlist and `session-start.sh`'s primer-only
  read both already cover the new file for free.
- **LEARNINGS.md gains a Symptoms index and `[[slug]]` cross-references.**
  `/session-continuity:learning` now offers an optional stable slug per
  entry (for `[[slug]]`-style cross-references that survive renumbering)
  and regenerates an alphabetized `## Symptoms index` section at the top of
  the file from every entry's `**Symptom.**` line each time it appends.
```

- [ ] **Step 5: Stage**

```bash
git add .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .claude-plugin/plugin.json CHANGELOG.md
```

---

### Task 6: Manual validation pass

**Files:**
- None modified — this task only runs the commands below against the
  changes from Tasks 1-5.

**Interfaces:**
- Consumes: everything from Tasks 1-5.
- Produces: a pass/fail report for the user; no code changes.

- [ ] **Step 1: Templates are self-consistent**

```bash
grep -oE '\{\{[A-Z_0-9]+\}\}' skills/session-continuity/templates/PROJECT_CONTEXT.md skills/session-continuity/templates/SESSION_PRIMER.md skills/session-continuity/templates/LEARNINGS.md
```

Expected: no unresolved token appears that isn't documented in
`commands/primer.md`'s Init-mode derivation/ask lists (cross-check against
Task 2 Step 3's extended lists).

- [ ] **Step 2: `commands/primer.md`'s step numbering**

```bash
grep -n '^## Step' commands/primer.md
```

Expected: Step 1 through Step 7 in order, no gaps, no duplicates (repeats
Task 2 Step 5's check as a final gate).

- [ ] **Step 3: This repo's own split preserved every stable phrase**

```bash
for phrase in "Bun is the runtime" "claude plugins install" "In order of cost"; do
  grep -l "$phrase" .session-continuity/*.md
done
```

Expected: each phrase is found in exactly one file
(`.session-continuity/PROJECT_CONTEXT.md`), none missing, none duplicated
across both files.

- [ ] **Step 4: Hooks still fire correctly with the new file present**

```bash
echo '{"cwd":"'"$(pwd)"'","tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | bash hooks/pre-commit-check.sh
```

Expected: exit 0, no denial referencing `PROJECT_CONTEXT.md` as an
unexpected staged path (it falls inside the existing `.session-continuity/`
allowlist).

- [ ] **Step 5: plugin.json / CHANGELOG consistency**

```bash
grep '"version"' .claude-plugin/plugin.json
grep -m1 '^## \[' CHANGELOG.md
```

Expected: both show `0.13.0`.

- [ ] **Step 6: Report results to the user**

Summarize pass/fail for each of Steps 1-5 above. Real path: every check in
Steps 1-5 runs against the actual files this plan wrote/modified — no
fixture, no mock. Stubbed: nothing in this pass; the spec's Testing items 1
and 2 (fresh scratch-project init, and split-mode against a throwaway
unsplit primer) need a directory outside this repo and are left as a
follow-up manual check, not run here. Report per-step results plainly —
don't summarize Steps 1-5 into a single "looks good," list each one. If any
step fails, fix the root cause in the relevant task's files before
re-running this task from Step 1.

**Do not commit.** Staging only — the user commits when ready.
