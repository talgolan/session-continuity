# Standalone OUTSTANDING_ITEMS.md Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the "Outstanding items" backlog out of `.session-continuity/SESSION_PRIMER.md` into a fourth peer file, `.session-continuity/OUTSTANDING_ITEMS.md`, with permanent numbering and a length cap — and repoint every consumer (`session-start.sh`, `end-session.md`, `primer.md`, `SKILL.md`, templates, README) at it.

**Architecture:** New file reuses LEARNINGS' exact `### N. <Title>` heading regex so no consumer needs a new parsing pattern. `primer.md`'s existing Split-mode pattern gets a second, independent detector for the one-time migration. Only one project consumes this plugin today, so migration is pushed immediately (both hooks nudge on detecting the old format) rather than tolerated indefinitely — no dual-path fallback code.

**Tech Stack:** Bash (hooks), Markdown command/skill files interpreted by Claude Code, no build step, no automated test runner (manual scratch-repo validation is this project's established practice for command/hook changes).

**Spec:** `meta/superpowers/specs/2026-08-30-outstanding-items-file-design.md`

## Global Constraints

- **Delete outright on close.** No archive section, anywhere. The closing commit is the historical record.
- **Permanent numbering.** A new item takes the next unused number. Never renumber, never reuse a number after deletion.
- **Before deleting a closed item, grep the whole repo for references to its number** (e.g. `\bitem #?N\b`, `outstanding item(s)? N`). A hit means fix the referencing text or leave a one-line "closed" stub instead of deleting.
- **Length cap.** Each item is a title + 1-3 sentences. Anything needing a design sketch, an invariant, or a rejected-alternatives discussion goes into a file under `meta/superpowers/` and gets linked, not inlined.
- **Scope boundary.** `SESSION_PRIMER.md`'s "In flight this session" bullets (uncommitted/staged work) stay in the primer. Only the "Outstanding items" backlog moves.
- **No dual-path fallback.** Every consumer detects the old inline-heading format and prompts immediate migration (`run /session-continuity:primer now`) — it never keeps parsing the old format alongside the new one.
- **Avoid the words "proven" and "verified" in this plan file itself** (word-boundary matches) and any mention of "binary/engine/container/daemon/--compile/bun build" without a MANDATORY marker — this repo's own commit-time content gates (`proven-gate.sh`, `smoke-gate.sh`) scan every staged `*/plans/*.md` file including this one. Use "confirm"/"validate"/"check" instead.

---

## Task 1: New template, retire the old placeholder

**Files:**
- Create: `skills/session-continuity/templates/OUTSTANDING_ITEMS.md`
- Modify: `skills/session-continuity/templates/SESSION_PRIMER.md`

**Interfaces:**
- Produces: the `### N. <Title>` heading convention every later task's consumer code parses via `grep -E '^### [0-9]+\.'`.

- [ ] **Step 1: Create the new template**

Write `skills/session-continuity/templates/OUTSTANDING_ITEMS.md`:

```markdown
# Outstanding Items — {{PROJECT_NAME}}

Backlog of explicitly deferred follow-ups and decisions — not bugs (those
go in `.session-continuity/LEARNINGS.md`), not current state (that's
`.session-continuity/SESSION_PRIMER.md`). An item lives here from the
moment it's flagged until the moment the code proves it resolved, then
it's deleted outright — the closing commit is the historical record, not
this file.

**Numbering is permanent.** A new item takes the next unused number;
closed items are deleted, never renumbered, never reused. Cross-references
("see item 4") stay valid as long as item 4 exists. Before deleting a
closed item, grep the whole repo for references to its number (e.g.
`\bitem #?4\b`, `outstanding item(s)? 4`) — a hit means fix the
referencing text or leave the closed item as a one-line "closed" stub
instead of deleting it.

**Length cap.** Each item is a title plus 1-3 sentences. If it needs a
design sketch, an invariant, or a rejected-alternatives discussion, put
that in a spec under `meta/superpowers/...` and link it here — this file
stays a scannable list, not a second spec repository.

{{OUTSTANDING_ITEMS}}

<!-- Example:
### 1. `/session-continuity:doctor` command

No way today for a project to ask "is this actually working" — found out
by hitting a gate denial cold. Check: hooks registered, all files fresh,
CLAUDE_PLUGIN_ROOT resolves, gate scripts executable.
-->
```

- [ ] **Step 2: Remove the old section from the SESSION_PRIMER.md template**

Read `skills/session-continuity/templates/SESSION_PRIMER.md`. It ends with:

```markdown
## Outstanding items (explicitly deferred — not bugs, decisions)

{{OUTSTANDING_ITEMS}}

<!-- Numbered list. One decision/deferral per item, with a one-line reason. -->
```

Delete that entire section (the `## Outstanding items` heading through the trailing HTML comment) so the template ends at the `git log` block's "Regenerate this block whenever you commit" line. Add one sentence to the file's intro paragraph (which currently reads "This file is the shortest path to what changed recently and what's outstanding.") pointing at the new file:

```markdown
You are picking up work on {{PROJECT_NAME}} from a previous session. This
file is the shortest path to what changed recently. For stable repo
context (layout, conventions, modules), read
`.session-continuity/PROJECT_CONTEXT.md` once per session — it changes
rarely. For the backlog of deferred decisions and follow-ups, read
`.session-continuity/OUTSTANDING_ITEMS.md`.
```//]: # (replaces the old intro paragraph)

- [ ] **Step 3: Confirm the heading regex matches**

```bash
grep -c '{{OUTSTANDING_ITEMS}}' skills/session-continuity/templates/OUTSTANDING_ITEMS.md
```

Expected: `1`.

```bash
grep -c '## Outstanding items' skills/session-continuity/templates/SESSION_PRIMER.md
```

Expected: `0` (section fully removed).

- [ ] **Step 4: Commit**

```bash
git add skills/session-continuity/templates/OUTSTANDING_ITEMS.md skills/session-continuity/templates/SESSION_PRIMER.md
git commit -m "feat: add OUTSTANDING_ITEMS.md template, retire primer's inline section"
```

---

## Task 2: Repoint `session-start.sh`

**Files:**
- Modify: `hooks/session-start.sh`

**Interfaces:**
- Consumes: `.session-continuity/OUTSTANDING_ITEMS.md` (from Task 1's format), falls back to detecting `.session-continuity/SESSION_PRIMER.md`'s inline `## Outstanding items` heading.
- Produces: no change to the hook's external contract (still a `<system-reminder>` block on stdout).

- [ ] **Step 1: Read the current file**

Read `hooks/session-start.sh` in full (120 lines) to get exact current text for the two blocks below (lines ~67-94 in the version read during brainstorming — confirm against the live file, don't assume line numbers are unchanged).

- [ ] **Step 2: Replace the outstanding-items block**

Find this block (the `status_outstanding` computation through the `outstanding_block` assignment):

```bash
# Outstanding items: count top-level numbered lines (`^N. `) inside the
# "Outstanding items" section. The awk block reads from the section
# heading until the next `## ` heading.
status_outstanding="$(awk '
  /^## Outstanding items/ { inside=1; next }
  inside && /^## / { exit }
  inside && /^[0-9]+\. / { count++ }
  END { print count+0 }
' "$cwd/$primer_path" 2>/dev/null || echo '?')"
status_learnings="$(grep -cE '^### [0-9]+\.' "$cwd/$learnings_path" 2>/dev/null || true)"
status_learnings="${status_learnings:-0}"

# Outstanding items: extract the first line only of each top-level numbered
# item (sub-bullets and continuation lines are intentionally dropped — see
# spec's Decision section for why no truncation heuristics are added).
# Empty when the section is missing or has no numbered items, which keeps
# the reminder identical to today's output in that case.
outstanding_items="$(awk '
  /^## Outstanding items/ { inside=1; next }
  inside && /^## / { exit }
  inside && /^[0-9]+\. / { print }
' "$cwd/$primer_path" 2>/dev/null || true)"

if [ -n "$outstanding_items" ]; then
  outstanding_block=$'\nOutstanding items:\n'"$outstanding_items"$'\n\nPresent these to the user as a numbered list, numbered starting at 1 (never 0), keeping the numbers above even in a short reply, and ask which of these (if any) they want to tackle this session.\n'
else
  outstanding_block=""
fi
```

Replace it with:

```bash
outstanding_path="$cwd/.session-continuity/OUTSTANDING_ITEMS.md"
status_learnings="$(grep -cE '^### [0-9]+\.' "$cwd/$learnings_path" 2>/dev/null || true)"
status_learnings="${status_learnings:-0}"

# Migration check: an old-format project has the inline heading in the
# primer but no OUTSTANDING_ITEMS.md yet. Only one project consumes this
# plugin today, so we push migration instead of tolerating both formats —
# no awk range-scan against the primer survives this change.
if [ -f "$outstanding_path" ]; then
  status_outstanding="$(grep -cE '^### [0-9]+\.' "$outstanding_path" 2>/dev/null || echo '?')"
  outstanding_items="$(grep -E '^### [0-9]+\.' "$outstanding_path" 2>/dev/null || true)"
  if [ -n "$outstanding_items" ]; then
    outstanding_block=$'\nOutstanding items:\n'"$outstanding_items"$'\n\nPresent these to the user as a numbered list, numbered starting at 1 (never 0), keeping the numbers above even in a short reply, and ask which of these (if any) they want to tackle this session.\n'
  else
    outstanding_block=""
  fi
elif grep -q '^## Outstanding items' "$cwd/$primer_path" 2>/dev/null; then
  status_outstanding="?"
  outstanding_block=$'\n⚠️ Outstanding items haven'"'"'t migrated to .session-continuity/OUTSTANDING_ITEMS.md yet — run /session-continuity:primer now to migrate before continuing.\n'
else
  status_outstanding="0"
  outstanding_block=""
fi
```

- [ ] **Step 3: Confirm the new-format path with a fixture**

```bash
tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/.session-continuity"
cat > "$tmpdir/.session-continuity/SESSION_PRIMER.md" <<'EOF'
# Session Primer — fixture
EOF
cat > "$tmpdir/.session-continuity/OUTSTANDING_ITEMS.md" <<'EOF'
# Outstanding Items — fixture

### 1. First item

Some text.

### 2. Second item

Some text.
EOF
cat > "$tmpdir/.session-continuity/LEARNINGS.md" <<'EOF'
# Learnings
EOF
cd "$tmpdir" && git init -q && git add -A && git commit -q -m init
printf '{"cwd":"%s"}' "$tmpdir" | bash "$OLDPWD/hooks/session-start.sh"
cd "$OLDPWD"
```

Expected output includes `Outstanding items: 2` in the status block and both `### 1.`/`### 2.` title lines rendered under "Outstanding items:", and does NOT contain the migration-nudge text (`run /session-continuity:primer now`) — a migrated project must never see the nudge.

- [ ] **Step 4: Confirm the migration-nudge path with a second fixture**

```bash
tmpdir2="$(mktemp -d)"
mkdir -p "$tmpdir2/.session-continuity"
cat > "$tmpdir2/.session-continuity/SESSION_PRIMER.md" <<'EOF'
# Session Primer — fixture

## Outstanding items (explicitly deferred — not bugs, decisions)

1. **Old-format item.** Still inline.
EOF
cat > "$tmpdir2/.session-continuity/LEARNINGS.md" <<'EOF'
# Learnings
EOF
cd "$tmpdir2" && git init -q && git add -A && git commit -q -m init
printf '{"cwd":"%s"}' "$tmpdir2" | bash "$OLDPWD/hooks/session-start.sh"
cd "$OLDPWD"
rm -rf "$tmpdir" "$tmpdir2"
```

Expected output contains: `run /session-continuity:primer now to migrate before continuing` and does NOT contain `Old-format item` (the hook must not fall back to displaying the old-format shortlist).

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start.sh
git commit -m "feat: repoint session-start.sh at OUTSTANDING_ITEMS.md, nudge migration"
```

---

## Task 3: `primer.md` Init mode — seed the fourth file

**Files:**
- Modify: `commands/primer.md`

**Interfaces:**
- Consumes: the `{{OUTSTANDING_ITEMS}}` template placeholder from Task 1.
- Produces: `.session-continuity/OUTSTANDING_ITEMS.md` as a fourth file staged alongside the other three at init.

- [ ] **Step 1: Read the current Init-mode section (Step 2 of the command)**

Read `commands/primer.md`, locate the numbered list of template copies (currently three: `SESSION_PRIMER.md`, `LEARNINGS.md`, `PROJECT_CONTEXT.md`) near the top of "Step 2 — Init mode."

- [ ] **Step 2: Add the fourth template copy**

After the existing line copying `PROJECT_CONTEXT.md` (`4. Copy the template from ".../templates/PROJECT_CONTEXT.md" to ".session-continuity/PROJECT_CONTEXT.md".`), insert:

```markdown
5. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/OUTSTANDING_ITEMS.md` to `.session-continuity/OUTSTANDING_ITEMS.md`.
```

Renumber the remaining steps in that list by one (every step after this insertion shifts down by one number).

- [ ] **Step 3: Add the conversion rule to the cold-ask step**

Find the step that asks the user for `{{GROUND_RULES}}`, `{{WORKFLOW_CONVENTIONS}}`, `{{WHERE_TO_LOOK_ROWS}}`, `{{STUCK_ESCALATION_STEPS}}`, `{{OUTSTANDING_ITEMS}}` (the cold-ask step). Add this sentence immediately after it:

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

- [ ] **Step 4: Update the placeholder-cleanup and staging steps**

Find the step that says "Replace any remaining `{{PLACEHOLDER}}` tokens with `TBD` before staging" — its final sentence currently reads:

```markdown
Never leave `{{...}}` syntax in a file you are about to stage — `grep -n '{{' .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .session-continuity/LEARNINGS.md` must return nothing after this step.
```

Add `.session-continuity/OUTSTANDING_ITEMS.md` to that grep command's file list.

Find the staging step (`git add .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .session-continuity/LEARNINGS.md`) and add `.session-continuity/OUTSTANDING_ITEMS.md` to it.

Find the final "Tell the user" message for Init mode ("Primer, PROJECT_CONTEXT, and LEARNINGS staged...") and change it to "Primer, PROJECT_CONTEXT, OUTSTANDING_ITEMS, and LEARNINGS staged...".

- [ ] **Step 5: Confirm the section reads correctly**

```bash
grep -n 'OUTSTANDING_ITEMS' commands/primer.md
```

Expected: at least 5 matches (the new template-copy step, the conversion rule, the grep-cleanup step, the staging step, the final message).

- [ ] **Step 6: Commit**

```bash
git add commands/primer.md
git commit -m "feat: primer.md Init mode seeds OUTSTANDING_ITEMS.md as a fourth file"
```

---

## Task 4: `primer.md` Split mode — extend with the new detector

**Files:**
- Modify: `commands/primer.md`

**Interfaces:**
- Consumes: an inline `## Outstanding items` heading inside a primer that also lacks `.session-continuity/OUTSTANDING_ITEMS.md`.
- Produces: `.session-continuity/OUTSTANDING_ITEMS.md` populated from the extracted section; primer with the section removed.

- [ ] **Step 1: Read the current "Step 1 — Detect state" and "Step 3 — Split mode" sections**

Read `commands/primer.md`. Note the current state-detection logic (four states: no primer / unsplit / stale / current) and the existing Split-mode steps that partition stable-vs-volatile content into `PROJECT_CONTEXT.md`.

- [ ] **Step 2: Add outstanding-items migration as a fifth detectable state**

In "Step 1 — Detect state," after the existing check for `PROJECT_CONTEXT_EXISTS`, add a check for the new file's existence and the primer's inline heading, gathered in the same Bash call already used for state detection:

```bash
[ -f .session-continuity/OUTSTANDING_ITEMS.md ] && echo "OUTSTANDING_ITEMS_EXISTS=1" || echo "OUTSTANDING_ITEMS_EXISTS=0"
grep -q '^## Outstanding items' .session-continuity/SESSION_PRIMER.md 2>/dev/null && echo "PRIMER_HAS_INLINE_OUTSTANDING=1" || echo "PRIMER_HAS_INLINE_OUTSTANDING=0"
```

Add this interpretation rule immediately after the existing four-state dispatch table: "If `PRIMER_HAS_INLINE_OUTSTANDING=1` AND `OUTSTANDING_ITEMS_EXISTS=0`, outstanding-items migration is needed — run it (Step 3b below) in addition to whichever of the four states above applies. **Sequencing:** if the primer is also unsplit (no `PROJECT_CONTEXT.md`), run the existing Split mode (Step 3) to completion first, then run Step 3b against the resulting primer, as two sequential edits — not simultaneous partitioning. The two splits touch disjoint sections of the primer (stable-context headings vs. the Outstanding items heading), so sequencing avoids any edit conflict."

- [ ] **Step 3: Add "Step 3b — Outstanding-items split" after the existing Step 3**

```markdown
## Step 3b — Outstanding-items split

Runs whenever `PRIMER_HAS_INLINE_OUTSTANDING=1` and
`OUTSTANDING_ITEMS_EXISTS=0` (see Step 1). Extract the primer's inline
`## Outstanding items` section into the new file; this is a one-time
content move, no numbering changes — the items keep whatever numbers
they currently have, and those become the first permanent IDs.

1. Read the existing `.session-continuity/SESSION_PRIMER.md` in full.
2. Copy every top-level numbered item under `## Outstanding items`
   (the numbered line plus indented continuation lines until the next
   top-level number) into a new `.session-continuity/OUTSTANDING_ITEMS.md`
   — or into the existing empty-skeleton file from Init mode if one was
   just created by Step 2/Step 3 above. Reformat each into the `### N.
   <Title>` heading shape (bold title text becomes the heading text; the
   rest of the item's prose becomes the body). If an item exceeds the
   title + 1-3 sentence length cap (a design sketch, an invariant
   statement, a rejected-alternatives discussion), extract the excess
   into a new file under `meta/superpowers/recommendations/` or
   `meta/superpowers/specs/` (name it descriptively — e.g.
   `<topic>-design-sketch.md`) and replace it in the item with a one-line
   pointer: `Design: <path>.` Preserve item order (ascending by number).
3. Verify content preservation before deleting the primer's section: `diff <(grep -E '^[0-9]+\.' .session-continuity/SESSION_PRIMER.md) <(grep -E '^### [0-9]+\.' .session-continuity/OUTSTANDING_ITEMS.md | sed -E 's/^### ([0-9]+)\. (.*)$/\1. **\2.**/')` — expect the item numbers and titles to line up; investigate any mismatch before proceeding rather than deleting the source section.
4. Delete the `## Outstanding items` section from
   `.session-continuity/SESSION_PRIMER.md` entirely.
5. Stage both: `git add .session-continuity/SESSION_PRIMER.md .session-continuity/OUTSTANDING_ITEMS.md`.
6. Tell the user: "Extracted the primer's inline Outstanding items section
   into `.session-continuity/OUTSTANDING_ITEMS.md` (N items, numbers
   preserved as permanent IDs). Both staged — review before committing."
7. Fall through to whichever of refresh mode (Step 4) or check mode
   (Step 5) applies against the now-split primer, same as Step 3's
   existing fall-through behavior.

**Do not commit automatically.** Staging only, same as every other split.
```

- [ ] **Step 4: Confirm the new section parses as valid markdown**

```bash
grep -c '^## Step 3b' commands/primer.md
```

Expected: `1`.

- [ ] **Step 5: Commit**

```bash
git add commands/primer.md
git commit -m "feat: primer.md gains Step 3b, the outstanding-items split detector"
```

---

## Task 5: `primer.md` Refresh flow — retarget to the new file

**Files:**
- Modify: `commands/primer.md`

**Interfaces:**
- Consumes: `.session-continuity/OUTSTANDING_ITEMS.md` (existing by this point in the flow — Step 3b migrates it before Step 4 ever runs against an old-format primer).
- Produces: edits to `.session-continuity/OUTSTANDING_ITEMS.md` instead of a primer section; staged alongside the primer.

- [ ] **Step 1: Read the current "Step 4 — Refresh mode" section**

Read `commands/primer.md`'s Step 4, specifically items 4-8 (the activity-surface prompt, the "Ask the user: Outstanding items..." step, "Apply the edits" with the verify-before-close rule added in the prior PR, the staging step, and the final message).

- [ ] **Step 2: Retarget item 4's candidate prompt**

The existing prompt text — `"Since the last primer refresh, these commits landed: ... Any of these resolve outstanding items, or warrant a new LEARNINGS entry?"` — stays worded the same; only its data source changes. Add a sentence immediately before it: "Read `.session-continuity/OUTSTANDING_ITEMS.md` for the current item list (not the primer — the backlog lives in the dedicated file now)."

- [ ] **Step 3: Retarget item 6's edit target**

Find (from the prior PR's fix):

```markdown
6. Apply the edits. **Before removing any item as DONE, verify it against the actual code** — one grep or read per load-bearing claim, even if the user confirms it from memory or a commit subject matched the item's keywords. A subject-line match does not prove the change shipped, and a fix landing inside an unrelated commit can leave an item reading OPEN when it already shipped — verify both directions, not just the one the candidate list surfaced.
```

Replace with:

```markdown
6. Apply the edits to `.session-continuity/OUTSTANDING_ITEMS.md` (not the
   primer). **Before removing any item as DONE, verify it against the
   actual code** — one grep or read per load-bearing claim, even if the
   user confirms it from memory or a commit subject matched the item's
   keywords. A subject-line match does not prove the change shipped, and
   a fix landing inside an unrelated commit can leave an item reading
   OPEN when it already shipped — verify both directions, not just the
   one the candidate list surfaced. **Before deleting a closed item, grep
   the whole repo for references to its number** (e.g. `\bitem #?N\b`) —
   a hit means fix the referencing text first, per the numbering rule in
   `.session-continuity/OUTSTANDING_ITEMS.md`'s own intro block. New
   items take the next unused number across the whole file, never a
   reused or renumbered one.
```

- [ ] **Step 4: Retarget the staging step**

Find `7. Stage the updated primer: \`git add .session-continuity/SESSION_PRIMER.md\`.` and change to:

```markdown
7. Stage the updated primer and, if outstanding items changed, the items
   file too: `git add .session-continuity/SESSION_PRIMER.md` and (only
   when Step 6 touched it) `git add .session-continuity/OUTSTANDING_ITEMS.md`.
```

- [ ] **Step 5: Confirm the section still reads coherently**

```bash
grep -n 'OUTSTANDING_ITEMS.md' commands/primer.md | grep -v 'templates/OUTSTANDING_ITEMS'
```

Expected: several matches inside Step 3b (Task 4) and Step 4 (this task) — none of them referencing a "## Outstanding items" heading inside the primer.

- [ ] **Step 6: Commit**

```bash
git add commands/primer.md
git commit -m "feat: primer.md Refresh flow edits OUTSTANDING_ITEMS.md, not the primer"
```

---

## Task 6: `end-session.md` — retarget verification, add the migration nudge

**Files:**
- Modify: `commands/end-session.md`

**Interfaces:**
- Consumes: `.session-continuity/OUTSTANDING_ITEMS.md`.
- Produces: same `appears-DONE`/`still-open`/`manual` verdict contract Step 3's checklist already relies on, now computed against the new file.

- [ ] **Step 1: Read the current "Outstanding-items verification" and "Refresh flow" subsections**

Read `commands/end-session.md`'s Step 1 in full (from "### Outstanding-items verification" through "### Refresh flow"), and Step 3's "Gather the facts" / "Emit the checklist" subsections.

- [ ] **Step 2: Retarget the verification section's data source and add the nudge**

Find the "Skip conditions" bullet under "### Outstanding-items verification":

```markdown
**Skip conditions.** Same as the overlay's existing skip clause (the "Skip
conditions" bullet in the Refresh flow): if the primer has no
`^## Outstanding items` heading (custom-modified primer), skip verification
silently. Additionally, when skipped, the Step 3 row reads
`Outstanding items: none tracked`. Likewise skip if the section is present but
empty.
```

Replace with:

```markdown
**Data source.** Read `.session-continuity/OUTSTANDING_ITEMS.md`, not a
heading inside the primer — the backlog lives in its own file now.

**Skip conditions.**
- If `.session-continuity/OUTSTANDING_ITEMS.md` doesn't exist AND the
  primer has no inline `## Outstanding items` heading either: skip
  verification silently (fresh/already-flat project). Step 3's row reads
  `Outstanding items: none tracked`.
- If `.session-continuity/OUTSTANDING_ITEMS.md` doesn't exist BUT the
  primer still has the inline heading: this is an unmigrated project.
  Skip only the outstanding-items verification sub-flow (this whole
  section) — everything else in Step 1 (fast path, drift check, git-log
  regeneration, test-count rerun) proceeds normally, independent of this
  condition. Tell the user once: "This project's outstanding items
  haven't migrated to `.session-continuity/OUTSTANDING_ITEMS.md` yet —
  run `/session-continuity:primer` first (it migrates automatically),
  then re-run `/session-continuity:end-session`." Step 3's row reads
  `Outstanding items: not migrated — run /session-continuity:primer`.
- If `.session-continuity/OUTSTANDING_ITEMS.md` exists but is empty
  (no `### N.` entries): skip verification, Step 3's row reads `none
  tracked`, same as the fresh-project case.
```

- [ ] **Step 3: Retarget item scoping inside the verification loop**

Find: `"For each top-level numbered item" under \`## Outstanding items\` (scope the item exactly as the overlay does: ...)`. Change `\`## Outstanding items\`` to `each \`### N.\` entry in \`.session-continuity/OUTSTANDING_ITEMS.md\``, and change the scoping description from "the numbered line plus indented continuation lines until the next top-level number" to "the heading line plus every line until the next `### N.` heading or end of file."

- [ ] **Step 4: Retarget the Refresh flow's overlay and staging**

In "### Refresh flow," find the overlay-computation bullet ("For each top-level numbered item under the primer's `## Outstanding items` heading: tokenize the item text...") and change the data source the same way as Step 3 above (each `### N.` entry in `.session-continuity/OUTSTANDING_ITEMS.md`).

Find the staging step:

```bash
git add .session-continuity/SESSION_PRIMER.md
git diff --quiet .session-continuity/PROJECT_CONTEXT.md 2>/dev/null || git add .session-continuity/PROJECT_CONTEXT.md
```

Add a third line:

```bash
git diff --quiet .session-continuity/OUTSTANDING_ITEMS.md 2>/dev/null || git add .session-continuity/OUTSTANDING_ITEMS.md
```

Apply the same change to the "Drift-clean close-candidate prompt" section's step 4 (which edits "only the primer's `## Outstanding items` section" today — change to "only `.session-continuity/OUTSTANDING_ITEMS.md`", and stage that file instead of the primer for this specific edit since the drift check already confirmed the primer's `git log` block is current and untouched).

- [ ] **Step 5: Retarget Step 3's checklist row**

Find the "Outstanding-items row — re-derive, do not cache" paragraph in Step 3. Change "Step 3 re-reads the `## Outstanding items` section from the primer AFTER any Step 1 closures" to "Step 3 re-reads `.session-continuity/OUTSTANDING_ITEMS.md` AFTER any Step 1 closures."

- [ ] **Step 6: Confirm no remaining references to the old heading location**

```bash
grep -n '## Outstanding items' commands/end-session.md
```

Expected: no output (every reference now points at `OUTSTANDING_ITEMS.md` instead of a primer heading).

- [ ] **Step 7: Commit**

```bash
git add commands/end-session.md
git commit -m "feat: end-session.md verification/staging targets OUTSTANDING_ITEMS.md"
```

---

## Task 7: `SKILL.md` — document the fourth file

**Files:**
- Modify: `skills/session-continuity/SKILL.md`

- [ ] **Step 1: Read the current file's opening description, decision-tree table, and maintenance-rules section**

Read `skills/session-continuity/SKILL.md` in full.

- [ ] **Step 2: Update the opening three-file description**

Find the bulleted description of the three files near the top (the `- **\`.session-continuity/SESSION_PRIMER.md\`**...` / `PROJECT_CONTEXT.md` / `LEARNINGS.md` list). Add a fourth bullet after `SESSION_PRIMER.md`'s bullet:

```markdown
- **`.session-continuity/OUTSTANDING_ITEMS.md`** — backlog of explicitly deferred follow-ups and decisions (not bugs, not current state). Permanent numbering (delete-on-close, never renumber, never reuse a number), title + 1-3 sentence length cap per item — anything longer moves to a linked file under `meta/superpowers/`.
```

Change "The three files are complementary" to "The four files are complementary" and extend the sentence that follows to mention the new file's role alongside the other three.

- [ ] **Step 3: Update the decision-tree table**

Find the row `| "We should refactor Y" | \`.session-continuity/SESSION_PRIMER.md\` → Outstanding items |`. Change to:

```markdown
| "We should follow up on X" | `.session-continuity/OUTSTANDING_ITEMS.md` → new numbered entry |
```

- [ ] **Step 4: Add the numbering-convention paragraph**

In the maintenance-rules section, after the existing "Outstanding items" bullet (the one already updated in the prior PR with the verify-before-close rule), add:

```markdown
**Numbering convention for OUTSTANDING_ITEMS.md — mirrors LEARNINGS.**
A new item takes the next unused number across the whole file. A closed
item is deleted outright, never renumbered, never reused — this keeps
cross-references ("see item 4") valid for as long as item 4 exists.
Before deleting, grep the repo for references to the item's number; a hit
means fix the reference or leave a one-line "closed" stub instead.
```

- [ ] **Step 5: Confirm the file mentions the fourth file at least 4 times**

```bash
grep -c 'OUTSTANDING_ITEMS' skills/session-continuity/SKILL.md
```

Expected: 4 or more.

- [ ] **Step 6: Commit**

```bash
git add skills/session-continuity/SKILL.md
git commit -m "docs: SKILL.md documents the fourth file, OUTSTANDING_ITEMS.md"
```

---

## Task 8: `CLAUDE_MD_SNIPPET.md` and `README.md`

**Files:**
- Modify: `skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md`
- Modify: `README.md`

- [ ] **Step 1: Update the CLAUDE.md snippet**

Read `skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md`. Find its opening paragraph:

```markdown
Before touching anything, read `.session-continuity/SESSION_PRIMER.md`
(current state, outstanding items) and `.session-continuity/LEARNINGS.md`
(bugs that were expensive to diagnose — grep it when something surprises
you). Read `.session-continuity/PROJECT_CONTEXT.md` once per session for
stable repo shape; it changes rarely.
```

Replace with:

```markdown
Before touching anything, read `.session-continuity/SESSION_PRIMER.md`
(current state) and `.session-continuity/LEARNINGS.md` (bugs that were
expensive to diagnose — grep it when something surprises you). Read
`.session-continuity/PROJECT_CONTEXT.md` once per session for stable repo
shape, and `.session-continuity/OUTSTANDING_ITEMS.md` for the backlog of
deferred decisions and follow-ups; both change rarely.
```

- [ ] **Step 2: Update README.md's "What's in the box" table**

Read `README.md`. In the "What's in the box" table, add a row after the `PROJECT_CONTEXT.md` row:

```markdown
| **`.session-continuity/OUTSTANDING_ITEMS.md`** | Backlog of explicitly deferred follow-ups and decisions. Permanent numbering, delete-on-close, title + 1-3 sentence cap per item. |
```

- [ ] **Step 3: Update "The three files" section header and body**

Change the heading `## The three files` to `## The four files`. Add a new paragraph after the `PROJECT_CONTEXT.md` paragraph:

```markdown
**`.session-continuity/OUTSTANDING_ITEMS.md`** is the backlog: explicitly
deferred decisions and follow-ups, not bugs and not current state. Item
numbers are permanent — a closed item is deleted outright, never
renumbered — so a cross-reference to "item 4" stays valid for as long as
item 4 exists. Each item is capped at a title plus 1-3 sentences; anything
longer belongs in a linked spec, not inlined here.
```

Change "All three files ship as templates" to "All four files ship as templates."

- [ ] **Step 4: Update the primer command's four-behaviors bullet list**

Find the `### /session-continuity:primer` section's bullet list (the "No primer yet" / "Primer exists but not yet split" / "Primer exists but drifted" / "Primer current" four bullets). Add a fifth bullet after "Primer exists but not yet split":

```markdown
- **Primer has an inline Outstanding items section, no OUTSTANDING_ITEMS.md yet** → extracts that section verbatim into the new file, preserving item numbers as permanent IDs, and removes it from the primer. Runs immediately on detection — this plugin has one consumer today, so migration is pushed, not offered indefinitely.
```

- [ ] **Step 5: Update "Why three files" section header and body**

Change `## Why three files` to `## Why four files`. In the body, change "Most memory systems lump everything together" paragraph's framing from three to four contexts, and add one sentence about the backlog's update contract (slow-changing, but not append-only like LEARNINGS since items delete on close) after the existing LEARNINGS paragraph.

- [ ] **Step 6: Update the "What goes where" decision table**

Find the row `| "We should refactor Y" | \`.session-continuity/SESSION_PRIMER.md\` → Outstanding items |`. Change to:

```markdown
| "We should follow up on X" | `.session-continuity/OUTSTANDING_ITEMS.md` → new numbered entry |
```

- [ ] **Step 7: Confirm no stale "three files"/"three plain-Markdown docs" phrasing remains**

```bash
grep -in 'three.*file\|three plain' README.md
```

Expected: no output (every instance updated to "four").

- [ ] **Step 8: Commit**

```bash
git add skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md README.md
git commit -m "docs: CLAUDE_MD_SNIPPET.md and README.md document the fourth file"
```

---

## Task 9: Migrate this repo's own primer (dogfood)

**Files:**
- Create: `.session-continuity/OUTSTANDING_ITEMS.md`
- Create: `meta/superpowers/recommendations/docguard-design-sketch.md`
- Modify: `.session-continuity/SESSION_PRIMER.md`

**Interfaces:** none — this is data migration, not code. Confirms Task 4's Step 3b logic produces a correct result when run for real, not just built.

- [ ] **Step 1: Read the current primer's Outstanding items section in full**

Read `.session-continuity/SESSION_PRIMER.md`'s `## Outstanding items` section (9 items, items 1-9). Confirm item 6's current wording — the Init-mode enrichment it describes as "committed on branch `docs/gate-chain-trap-and-primer-drift-check`, not yet merged" is stale: that branch merged via PR #18 (verify: `git log --oneline main | grep -i "Merge pull request #18"`). Update the wording to "merged to main via PR #18" as part of this migration, per the verify-before-close rule this project now enforces on itself — the rewording happens here since the item's text is being rewritten into the new file anyway.

- [ ] **Step 2: Extract item 4's design sketch**

Item 4 ("Global docs-current hooks check 'touched,' not 'accurate'") carries an inline "Design sketch" and "Why not build it now" block that exceeds the new length cap. Create `meta/superpowers/recommendations/docguard-design-sketch.md`:

```markdown
# Design sketch: generalized docs-current gate

Extracted from `.session-continuity/OUTSTANDING_ITEMS.md` item 4 during
the 2026-08-30 outstanding-items-file migration — this is the design
detail that exceeded the new file's length cap, not new content.

## The gap

Neither `~/.githooks/pre-commit` nor the global Claude Code `Stop` hook
(`~/.claude/hooks/docs-current-check.sh`) verifies that a doc's claims
stay true — both only check whether *a* doc file was touched. The one
exception is `pre-commit`'s hard block when a primer's `"NN pass"` line
disagrees with the real `bun test` count — a single hard-coded special
case, not a generalizable check. Every drift found in the 2026-08-13 docs
sweep (file counts, command counts, hook counts, a stale marketplace repo
name) is a claim-vs-reality mismatch neither hook would have caught.

**Invariant (per CLAUDE.md rule 4):** every count or named-entity-list
claim in a repo's shipped docs must match the actual repo state at commit
time — enforced at the gate that runs on every commit, not left to
whoever's authoring the next PR to remember.

## Design sketch (not built — lives outside any git repo)

Generalize the existing `"NN pass"` special case into a declarative
per-repo config (e.g. `.docguard.yml`): a list of `{doc: <glob>,
claim_pattern: <regex w/ capture>, actual_command: <shell>}` entries. On
each staged doc file matching an entry, extract the claimed value, run
the command, hard-block on mismatch — reusing the same code path and
escape-hatch pattern (`DOCGUARD_SKIP_COUNT=1`, generalized) the pass-count
check already has, rather than inventing a second mechanism.

## Why not build it now

Touches `~/.githooks` and `~/.claude/hooks`, not this repo — changes
behavior for every git commit on the machine, not just this project.
Bigger blast radius, deserves its own session and explicit go-ahead.
```

- [ ] **Step 3: Write the new `.session-continuity/OUTSTANDING_ITEMS.md`**

Copy the template from Task 1, then populate it with all 9 items reformatted to `### N. <Title>` headings, each trimmed to the length cap. Items 1, 2, 3, 5, 7, 8, 9 already fit the cap or close to it — trim lightly, preserving the substantive content. Item 4 gets the pointer added (`Design: meta/superpowers/recommendations/docguard-design-sketch.md.`) in place of its inline sketch. Item 6 gets the corrected "merged via PR #18" wording from Step 1.

- [ ] **Step 4: Verify content preservation**

```bash
grep -cE '^### [0-9]+\.' .session-continuity/OUTSTANDING_ITEMS.md
```

Expected: `9`.

```bash
for n in 1 2 3 4 5 6 7 8 9; do
  grep -q "^### $n\." .session-continuity/OUTSTANDING_ITEMS.md && echo "item $n: present" || echo "item $n: MISSING"
done
```

Expected: all 9 lines read "present."

- [ ] **Step 5: Remove the section from the primer**

Delete the `## Outstanding items` heading and everything under it from `.session-continuity/SESSION_PRIMER.md`.

```bash
grep -c '## Outstanding items' .session-continuity/SESSION_PRIMER.md
```

Expected: `0`.

- [ ] **Step 6: Cross-reference sweep**

```bash
grep -rn 'outstanding item[s]\? [0-9]\|item #\?[0-9]\+' --include='*.md' . | grep -v '.session-continuity/OUTSTANDING_ITEMS.md\|.session-continuity/SESSION_PRIMER.md\|meta/superpowers/plans/2026-08-30\|meta/superpowers/specs/2026-08-30'
```

Confirm no unexpected cross-references to old item numbers exist elsewhere in the repo that would go stale (the grep excludes this plan/spec and the two migrated files themselves, which legitimately discuss item numbers).

- [ ] **Step 7: Commit**

```bash
git add .session-continuity/OUTSTANDING_ITEMS.md .session-continuity/SESSION_PRIMER.md meta/superpowers/recommendations/docguard-design-sketch.md
git commit -m "docs: migrate this repo's own outstanding items to the new file"
```

---

## Task 10: End-to-end scratch validation

**Files:** none modified — this task confirms Tasks 1-9 work together against a fresh scratch repo, per the spec's Testing section.

- [ ] **Step 1: Set up a scratch repo**

```bash
scratch="$(mktemp -d)"
cd "$scratch" && git init -q && echo "test" > README.md && git add -A && git commit -q -m init
cd "$OLDPWD"
```

- [ ] **Step 2: Confirm fresh init produces all four files**

Using this plugin's dev path (`claude --plugin-dir <this-repo-path>` from inside `$scratch`, running `/session-continuity:primer`), confirm the command stages `.session-continuity/SESSION_PRIMER.md`, `.session-continuity/PROJECT_CONTEXT.md`, `.session-continuity/LEARNINGS.md`, and `.session-continuity/OUTSTANDING_ITEMS.md`. Check the new file's format:

```bash
grep -c '{{' "$scratch/.session-continuity/OUTSTANDING_ITEMS.md"
```

Expected: `0` (no leftover placeholders after init).

- [ ] **Step 3: Confirm the Step 3b split against a scratch unsplit primer**

In a second scratch dir, hand-craft a primer with an inline `## Outstanding items` section and no `PROJECT_CONTEXT.md`/`OUTSTANDING_ITEMS.md` (reuse the fixture shape from Task 2 Step 4), then run `/session-continuity:primer` again and confirm: `PROJECT_CONTEXT.md` created first, then `OUTSTANDING_ITEMS.md` created from the inline section, primer's inline section removed, item numbers preserved.

- [ ] **Step 4: Confirm `session-start.sh`'s reminder reflects the new file**

Re-run the Task 2 Step 3/Step 4 fixture checks against this scratch repo's real files (not synthetic fixtures) to confirm the hook's behavior holds end-to-end, not just against hand-built fixtures.

- [ ] **Step 5: Confirm `/session-continuity:end-session`'s verification pipeline**

Add a code-verifiable item to the scratch repo's `OUTSTANDING_ITEMS.md` (e.g. "add a `.gitignore` entry for `*.tmp`" with the entry already present), run `/session-continuity:end-session`, and confirm it classifies the item `appears-DONE` with cited evidence, and that closing it deletes the entry rather than archiving it.

- [ ] **Step 6: Confirm `/session-continuity:end-session`'s migration-nudge path**

Reuse the Task 2 Step 4 unmigrated fixture shape (inline `## Outstanding items` heading, no `OUTSTANDING_ITEMS.md`) as a third scratch repo. Run `/session-continuity:end-session` and confirm: it prints the "run `/session-continuity:primer` first" nudge, it does NOT attempt to classify or close the old inline item, and Step 1's fast path / drift check / git-log regeneration still ran normally (check the checklist's other rows aren't silently skipped alongside the outstanding-items one).

- [ ] **Step 7: Clean up scratch directories**

```bash
rm -rf "$scratch"
```

- [ ] **Step 8: No commit for this task** — validation only, nothing in this repo changes. If any check in Steps 2-6 fails, stop and fix the relevant task (1-9) before proceeding; do not mark this plan complete with a failing validation step.
