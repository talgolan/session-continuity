# `/session-continuity:end-session` v0.3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `/session-continuity:end-session` as part of v0.3.0 — a zero-arg close-out ritual that refreshes the primer, surfaces LEARNINGS candidates from session context, and reports a ✓/⚠️ checklist of staged/unstaged/untracked/unpushed state.

**Architecture:** Prose slash-command file (`commands/end-session.md`) that instructs Claude to execute named steps from `commands/primer.md` (refresh) and `commands/learning.md` (append), then emit a structured checklist using real git commands. No new hooks, templates, or shared modules. Subroutine-by-reference pattern: one source of truth per concern.

**Tech Stack:** Markdown (command file), JSON (plugin.json bump), shell (git probing inside the command's prose), existing release workflow (no changes).

**Working directory:** `/Users/tal.golan/.claude/skills/session-continuity/`

**Spec reference:** [docs/superpowers/specs/2026-04-28-end-session-command-design.md](../specs/2026-04-28-end-session-command-design.md)

---

## File Structure

**Created:**
- `commands/end-session.md` — the new slash command (prose + frontmatter)

**Modified:**
- `.claude-plugin/plugin.json` — version bump to `0.3.0`
- `CHANGELOG.md` — new `[0.3.0]` section
- `README.md` — mention the new command under "What you get" and "Usage"
- `skills/session-continuity/SKILL.md` — one-line addition to the plugin-affordances paragraph mentioning end-session

**Preserved (not touched):**
- `commands/primer.md` — referenced from end-session.md by step name, not modified
- `commands/learning.md` — referenced from end-session.md by step name, not modified
- `hooks/` — no new hooks, no changes
- `skills/session-continuity/templates/` — unchanged

---

## Task 1: Precondition check — clean starting state

**Files:** none modified; verification only.

- [ ] **Step 1.1: Verify we're in the right directory**

Run: `pwd`
Expected: `/Users/tal.golan/.claude/skills/session-continuity`

- [ ] **Step 1.2: Verify clean working tree**

Run: `git status`
Expected: `On branch main`, `nothing to commit, working tree clean`.

If not clean, stop and resolve before proceeding — the plan assumes a clean starting state so each task's commit is isolated.

- [ ] **Step 1.3: Verify v0.2.0 is the latest tag**

Run: `git tag --sort=-v:refname | head -3`
Expected: `v0.2.0` appears at or near the top.

- [ ] **Step 1.4: Verify we have the spec**

Run: `test -f docs/superpowers/specs/2026-04-28-end-session-command-design.md && echo ok`
Expected: `ok`

---

## Task 2: Write `commands/end-session.md`

**Files:**
- Create: `commands/end-session.md`

- [ ] **Step 2.1: Write the command file**

Create `commands/end-session.md` with this exact content:

````markdown
---
description: Refresh the primer, surface LEARNINGS candidates from this session, and report a close-out checklist. Zero args.
---

# /session-continuity:end-session

You are responding to the `/session-continuity:end-session` slash command.

**Your job: run a close-out ritual that (1) refreshes `docs/SESSION_PRIMER.md`, (2) surfaces LEARNINGS candidates from this session's conversation, and (3) reports a structured ✓ / ⚠️ checklist of the repo's state so the user can walk away knowing nothing is forgotten.**

Zero arguments. Never commits. Never pushes.

## Step 0 — Preconditions

Check both files exist:

1. `docs/SESSION_PRIMER.md`
2. `docs/LEARNINGS.md`

If either is missing, tell the user:

> "No `docs/SESSION_PRIMER.md` (or `docs/LEARNINGS.md`) found. Run `/session-continuity:primer` first to initialize session-continuity in this project."

Exit. Do not proceed.

## Step 1 — Refresh the primer

Follow the logic in **Step 3 of `commands/primer.md`** (refresh mode):

1. Read the current `docs/SESSION_PRIMER.md`.
2. Regenerate the `git log --oneline -5` block with current output.
3. If the primer has a test-counts section, run the test command(s) found there and update the counts to match current output.
4. Ask the user: "Outstanding items — anything to remove (finished) or add (new follow-ups flagged)?"
5. Apply the edits.
6. Stage the updated primer: `git add docs/SESSION_PRIMER.md`.

If the primer is already current (`git log` block matches, no test counts to update, user has no outstanding-items changes), skip the prompt and note in Step 3's checklist that primer refresh was a no-op (still ✓).

**Do not** commit. Staging only.

## Step 2 — Session reflection for learnings

Review this session's conversation context and surface candidates for new LEARNINGS entries.

**A candidate is worth surfacing when:**
- A problem took multiple attempts or involved a wrong theory before the right fix landed.
- A platform or tool quirk surprised us (hook behavior, CLI defaults, API shape).
- The final code relies on a workaround whose reasoning isn't obvious from reading it.

**Not candidates:**
- Routine implementation ("wrote the endpoint, tests passed first try").
- Decisions that are already captured in commit messages or spec docs.
- Things the user already knew going in.

### Presentation

Show candidates as a numbered menu:

```
A few things from this session looked like LEARNINGS candidates:

1. <one-line description of candidate 1>
2. <one-line description of candidate 2>

Capture any of these? (1, 2, both, none, or describe another)
```

If you find **zero** candidates, skip the prompt and note "no new learnings" in Step 3's checklist.

### Capture flow for each accepted candidate

For each candidate the user picks, follow **Steps 2-6 of `commands/learning.md`**:

- Pre-fill the **Title** from the candidate description.
- Pre-draft **The trap**, **Symptom**, **Fix**, and **Diagnostic signal** from session context where you can, then present the draft to the user for confirmation / revision. Do not invent details the session does not support — leave a field blank and ask if unclear.
- Choose section per Step 3 of `commands/learning.md`.
- Compute the next number per Step 4.
- Insert at the top of the chosen section per Step 5.
- Stage: `git add docs/LEARNINGS.md` per Step 6.

If the user describes "another" candidate not on your list, treat that description as a pre-filled title and follow the same flow.

**Do not** commit. Staging only.

## Step 3 — Final checklist

Run real git commands and emit a structured checklist. Every item must reflect actual repo state, not an assertion.

### Gather the facts

Run each of these and record the results:

```bash
git diff --cached --name-only          # staged files
git diff --name-only                    # unstaged modifications
git ls-files --others --exclude-standard   # untracked (ignoring .gitignore'd)
git rev-parse --abbrev-ref HEAD         # current branch (or "HEAD" if detached)
git rev-parse --abbrev-ref @{u} 2>/dev/null  # upstream branch, or empty if none
git rev-list --count @{u}..HEAD 2>/dev/null  # unpushed commits, empty if no upstream
```

Handle these edge cases explicitly:

- **Not a git repo.** If `git rev-parse` fails, the precondition in Step 0 should have caught this, but belt-and-suspenders: report "⚠️ not inside a git repo" once and skip git-dependent rows.
- **Detached HEAD.** `git rev-parse --abbrev-ref HEAD` returns `HEAD`. Note "⚠️ detached HEAD at `<short-sha>`" in the unpushed-commits row.
- **No upstream.** `git rev-parse --abbrev-ref @{u}` fails. Note "⚠️ branch `<name>` has no upstream — set one with `git push -u origin <name>`" in the unpushed-commits row.

### Emit the checklist

Output using this structure. Use ✓ (green), ⚠️ (yellow), or → (suggestion):

| Row | Marker | Content |
|---|---|---|
| Primer refresh | ✓ | "Primer refreshed and staged" OR "Primer already current (no-op)" |
| New learnings | ✓ | "N LEARNINGS entry/entries captured (#X, \"<title>\" …)" OR "No new learnings" |
| Staged files | ✓ | "Staged: <file1>, <file2>, …" OR "Nothing staged" |
| Unstaged modifications | ✓ if none, else ⚠️ | "No unstaged modifications" OR "⚠️ Unstaged: <file1>, <file2>, …" |
| Untracked files | ✓ if none, else ⚠️ | "No untracked files" OR "⚠️ N untracked: <file1>, <file2>, … — ignore, add, or delete?" |
| Unpushed commits | ✓ / ⚠️ | "Up to date with origin/<branch>" OR "⚠️ Branch <name> is N commits ahead of origin — push before closing?" OR the detached-HEAD / no-upstream variants |
| Suggested commit | → | Derived from staged files + captured learnings. Omit row entirely if nothing is staged. |

### Suggested commit message

If files are staged, derive a commit message from the pattern:

- Only `docs/` staged → `docs: update session continuity`.
- `docs/LEARNINGS.md` is staged with code → pick the most prominent captured learning's title (or the primary code-change theme) and use conventional-commit style: `<type>(<scope>): <subject>`. Keep subject line ≤ 72 chars.
- Only code staged (no docs) → should not happen if Step 1 ran; if it does, suggest based on the file paths.

Prefix with `→ Suggested:` and wrap in a fenced code block so the user can copy-paste.

### Example output

```
✓ Primer refreshed and staged
✓ 1 LEARNINGS entry captured (#7, "awk range collapse on single-version CHANGELOG")
✓ Staged: docs/SESSION_PRIMER.md, docs/LEARNINGS.md, .github/workflows/release.yml
✓ No unstaged modifications
⚠️ 2 untracked files: scratch.md, tmp/debug.log — ignore, add, or delete?
⚠️ Branch "main" is 3 commits ahead of origin — push before closing?
→ Suggested:
    git commit -m "fix(ci): extract CHANGELOG section with proper awk range"
```

## Notes

- **Never commit automatically.** Stage only, across both Step 1 and Step 2.
- **Never push.** The checklist flags unpushed commits; the user decides.
- **Never invent LEARNINGS details.** If you can't draft a field from session context, leave it blank and ask the user — same rule as `/session-continuity:learning`.
- **Respect the primer-only-commit rule.** If the user, after seeing the checklist, commits only the primer, the `PreToolUse` hook's nudge still applies — nothing to do here.
- **Zero arguments.** If the user passed text after `/session-continuity:end-session`, ignore it — session reflection provides all context needed.
````

- [ ] **Step 2.2: Verify the file exists and has correct frontmatter**

Run: `head -5 commands/end-session.md`
Expected output starts with:
```
---
description: Refresh the primer, surface LEARNINGS candidates from this session, and report a close-out checklist. Zero args.
---
```

- [ ] **Step 2.3: Verify file length is sane**

Run: `wc -l commands/end-session.md`
Expected: 120-180 lines. (The command is more prose than `primer.md` or `learning.md` because Step 3's checklist is dense, but not 300+ lines.)

- [ ] **Step 2.4: Commit**

```bash
git add commands/end-session.md
git commit -m "$(cat <<'EOF'
feat: add /session-continuity:end-session slash command

Zero-arg close-out ritual:
- Step 1 refreshes docs/SESSION_PRIMER.md by delegating to Step 3 of
  commands/primer.md (refresh mode).
- Step 2 reflects on the current session's conversation for LEARNINGS
  candidates, presents a numbered menu, and delegates each accepted
  candidate to Steps 2-6 of commands/learning.md with title pre-filled
  and trap/symptom/fix/diagnostic pre-drafted.
- Step 3 runs real git commands and emits a ✓ / ⚠️ checklist covering
  staged / unstaged / untracked / unpushed state, plus a suggested
  commit message derived from the staged files and captured learnings.

Never commits, never pushes — stages only, matching /primer and
/learning's contract.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: commit succeeds. `git log --oneline | head -3` shows the new commit on top.

---

## Task 3: Bump `plugin.json` to 0.3.0

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 3.1: Read the current file**

Run: `cat .claude-plugin/plugin.json`
Expected: version is `"0.2.0"`.

- [ ] **Step 3.2: Change the version field**

Replace the line:
```json
  "version": "0.2.0",
```
with:
```json
  "version": "0.3.0",
```

Leave everything else untouched.

- [ ] **Step 3.3: Validate the JSON**

Run: `python3 -c "import json; print(json.load(open('.claude-plugin/plugin.json'))['version'])"`
Expected: `0.3.0`

- [ ] **Step 3.4: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump plugin.json to 0.3.0"
```

Expected: commit succeeds.

---

## Task 4: Update `CHANGELOG.md`

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 4.1: Read the current CHANGELOG**

Run: `head -10 CHANGELOG.md`
Expected: the file starts with the standard Keep-a-Changelog header, and the first versioned section is `## [0.2.0] — 2026-04-27`.

- [ ] **Step 4.2: Insert a `[0.3.0]` section above the `[0.2.0]` section**

The new section goes immediately after the introductory paragraph and immediately before `## [0.2.0] — 2026-04-27`.

Insert this block:

```markdown
## [0.3.0] — 2026-04-28

### Added
- `/session-continuity:end-session` slash command — zero-arg close-out ritual. Refreshes the primer (Step 1 delegates to `/session-continuity:primer` refresh mode), reflects on session context to surface LEARNINGS candidates and appends any the user accepts (Step 2 delegates to `/session-continuity:learning`), then emits a ✓ / ⚠️ checklist of staged / unstaged / untracked / unpushed state with a suggested commit message.

### Changed
- `README.md` lists the new command.
- `SKILL.md` plugin-affordances paragraph mentions the new command.

```

(Note the trailing blank line before the `[0.2.0]` section — preserve CHANGELOG spacing.)

- [ ] **Step 4.3: Verify the structure**

Run: `grep -nE '^## \[' CHANGELOG.md`
Expected output (order matters):
```
5:## [0.3.0] — 2026-04-28
<N>:## [0.2.0] — 2026-04-27
<M>:## [0.1.0] — 2026-04-26
```

The `[0.3.0]` section must come first after the header so the release workflow's awk extraction matches it when `v0.3.0` is tagged.

- [ ] **Step 4.4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add [0.3.0] to CHANGELOG — end-session command"
```

Expected: commit succeeds.

---

## Task 5: Update `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 5.1: Read the relevant sections**

Run: `grep -nE '^##|^-' README.md | head -40`
Identify the "What you get" section (bulleted list) and the "Usage" section (paragraphs with example invocations).

- [ ] **Step 5.2: Add the end-session bullet to "What you get"**

Find the existing bullets that list slash commands (they look like):
```markdown
- **`/session-continuity:primer`** — init / refresh / check the primer. …
- **`/session-continuity:learning`** — append a new LEARNINGS entry interactively. …
```

Immediately after the `/session-continuity:learning` bullet, add:

```markdown
- **`/session-continuity:end-session`** — close-out ritual. Refreshes the primer, surfaces LEARNINGS candidates from this session's context, and reports a ✓ / ⚠️ checklist of staged / unstaged / untracked / unpushed state with a suggested commit message. Never commits.
```

- [ ] **Step 5.3: Add an end-session subsection to "Usage"**

Find the existing usage subsections (they open with a bold phrase like `**Before a commit:**`). Immediately after the `/session-continuity:learning` subsection (the "After a painful bug" one), insert:

```markdown
**Ending a work session:**

```
/session-continuity:end-session
```

Refreshes the primer, asks whether anything from today is worth a LEARNINGS entry (Claude looks at the session's conversation context to propose candidates), and prints a checklist so you know nothing is forgotten before you close the laptop. Stages changes — does not commit.

```

- [ ] **Step 5.4: Verify line count is still reasonable**

Run: `wc -l README.md`
Expected: under 140 lines. (v0.2 target was ~120; end-session adds ~15 lines of content.)

- [ ] **Step 5.5: Commit**

```bash
git add README.md
git commit -m "docs: document /session-continuity:end-session in README"
```

Expected: commit succeeds.

---

## Task 6: Update `SKILL.md`

**Files:**
- Modify: `skills/session-continuity/SKILL.md`

- [ ] **Step 6.1: Read the plugin-affordances paragraph**

Run: `grep -n "plugin, two commands" skills/session-continuity/SKILL.md`
Expected: finds a line containing "If installed as a plugin, two commands are available:".

- [ ] **Step 6.2: Update "two commands" to "three commands" and add the new command**

Find this paragraph (should be near the top of the body, after the opening description):

```markdown
If installed as a plugin, two commands are available: `/session-continuity:primer` (init/refresh/check the primer) and `/session-continuity:learning` (append a new LEARNINGS entry interactively). Hooks in `hooks/hooks.json` remind Claude to read the primer on session start and nudge when a `git commit` lands without a primer refresh staged.
```

Replace with:

```markdown
If installed as a plugin, three commands are available: `/session-continuity:primer` (init/refresh/check the primer), `/session-continuity:learning` (append a new LEARNINGS entry interactively), and `/session-continuity:end-session` (close-out ritual — refresh the primer, capture any new learnings from this session, and report a ✓/⚠️ checklist before you close the laptop). Hooks in `hooks/hooks.json` remind Claude to read the primer on session start and nudge when a `git commit` lands without a primer refresh staged.
```

- [ ] **Step 6.3: Verify the change**

Run: `grep -n "three commands" skills/session-continuity/SKILL.md`
Expected: finds exactly one match.

Run: `grep -n "two commands" skills/session-continuity/SKILL.md`
Expected: no matches.

- [ ] **Step 6.4: Commit**

```bash
git add skills/session-continuity/SKILL.md
git commit -m "docs(skill): mention /session-continuity:end-session in affordances paragraph"
```

Expected: commit succeeds.

---

## Task 7: Live smoke test in a scratch repo

**Files:** none modified; verification only.

Mirrors the Task 11 smoke test from v0.2 — set up a throwaway repo, exercise the command, confirm each step works.

- [ ] **Step 7.1: Create a fresh scratch repo**

```bash
rm -rf /tmp/sc-end-session-smoke
mkdir -p /tmp/sc-end-session-smoke && cd /tmp/sc-end-session-smoke
git init -b main
echo "# end-session smoke test" > README.md
git add README.md
git commit -m "init"
```

Expected: fresh repo on `main` with one commit.

- [ ] **Step 7.2: Initialize session-continuity in the scratch repo**

Launch Claude with the plugin:
```bash
claude --plugin-dir /Users/tal.golan/.claude/skills/session-continuity
```

Invoke: `/session-continuity:primer`

Give minimal answers when prompted (e.g., "smoke test project, no packages, no outstanding, no test command"). Accept the filled templates.

Exit Claude, then in the shell:
```bash
git commit -m "docs: initialize session continuity"
```

Expected: two commits now (`init`, `docs: initialize session continuity`).

- [ ] **Step 7.3: Seed one learning so LEARNINGS.md isn't empty**

Relaunch Claude:
```bash
claude --plugin-dir /Users/tal.golan/.claude/skills/session-continuity
```

Invoke: `/session-continuity:learning` and answer: title "smoke test seed", trap "n/a — this is a seed entry for smoke testing", symptom "n/a", fix "n/a", no diagnostic signal. Pick any section (a new one named "General" is fine).

Exit Claude. In the shell:
```bash
git commit -m "docs: seed learning"
```

Expected: three commits.

- [ ] **Step 7.4: Prepare the dirty-state scenario**

```bash
mkdir -p src
echo "console.log('hello');" > src/foo.js
git add src/foo.js
echo "random" > scratch.md            # untracked, not added
git status
```

Expected: `src/foo.js` staged, `scratch.md` untracked, primer clean.

- [ ] **Step 7.5: Invoke end-session and verify Step 1 (primer refresh)**

Relaunch Claude:
```bash
claude --plugin-dir /Users/tal.golan/.claude/skills/session-continuity
```

Invoke: `/session-continuity:end-session`

Expected early in the response:
- Claude reads `docs/SESSION_PRIMER.md` and `docs/LEARNINGS.md`.
- Claude regenerates the `git log --oneline -5` block and notices drift (the `docs: initialize` and `docs: seed learning` commits weren't in the original primer).
- Claude asks about outstanding items.
- Claude stages `docs/SESSION_PRIMER.md`.

- [ ] **Step 7.6: Verify Step 2 (learnings reflection)**

Expected mid-response:
- Claude surveys the current Claude session and either (a) surfaces a candidate drawn from this very smoke-test conversation (unlikely to find one, since the session was mechanical) or (b) notes "no new learnings" and moves on.
- If Claude presents a candidate: decline ("none") to keep the test clean, unless you want to exercise the append-learning subroutine.

- [ ] **Step 7.7: Verify Step 3 (checklist)**

Expected at the end of the response:

```
✓ Primer refreshed and staged
✓ No new learnings  (or "1 LEARNINGS entry captured ...")
✓ Staged: docs/SESSION_PRIMER.md, src/foo.js
✓ No unstaged modifications
⚠️ 1 untracked file: scratch.md — ignore, add, or delete?
⚠️ Branch "main" has no upstream — set one with `git push -u origin main`
→ Suggested:
    git commit -m "<some conventional-commit subject>"
```

Key things to verify:
- `scratch.md` appears in the untracked row with ⚠️.
- The no-upstream case is handled (scratch repo has no remote).
- The suggested commit appears because `src/foo.js` + primer are staged.
- Primer row says "refreshed and staged", not "no-op".

- [ ] **Step 7.8: Edge-case run — everything clean**

In the Claude session, commit everything:

```
Run: git commit -m "test: smoke-test sample commit"
```

(The `PreToolUse` hook should NOT fire this time because the primer is staged. Verify by noting Claude's response doesn't mention a primer nudge.)

Then re-invoke `/session-continuity:end-session`.

Expected:
- Primer row: ✓ "Primer already current (no-op)" (nothing has drifted since the last refresh).
- No new learnings.
- Staged: "Nothing staged" ✓.
- Unstaged: ✓ none.
- Untracked: ⚠️ still shows `scratch.md`.
- Unpushed: `main is 1 commit ahead ...` wait, no — still no upstream. ⚠️ no-upstream message.
- No suggested commit row (nothing staged).

- [ ] **Step 7.9: Exit and clean up**

Exit Claude. Then:
```bash
cd /Users/tal.golan/.claude/skills/session-continuity
rm -rf /tmp/sc-end-session-smoke
```

- [ ] **Step 7.10: If anything failed**

Fix the bug in `commands/end-session.md`, commit with a clear message (`fix(command): …`), and re-run Task 7 from Step 7.1. Do not bump `plugin.json` yet — the 0.3.0 version is still pre-release.

If everything passed: proceed to Task 8.

---

## Task 8: Tag and publish v0.3.0

**Files:** none modified; external action.

Requires explicit user confirmation before running. These steps push to a public repo.

- [ ] **Step 8.1: Confirm with the user**

Before running any commands in this task, confirm with the user:

> "Task 7 smoke passed. Ready to tag and push v0.3.0? This will trigger the release workflow and publish a new GitHub Release."

Proceed only on explicit yes.

- [ ] **Step 8.2: Verify remote state is current**

```bash
git fetch origin
git status
```

Expected: `Your branch is up to date with 'origin/main'` (after pushing the task-by-task commits) or `ahead of origin by N commits` — not behind.

If ahead, push first:
```bash
git push
```

- [ ] **Step 8.3: Verify the CHANGELOG extraction works locally**

The v0.2.0 release hit a bug where the awk range collapsed on a single-version CHANGELOG. That bug is fixed, but verify against the real file before tagging:

```bash
version="0.3.0"
awk -v ver="$version" '
  $0 ~ "^## \\[" ver "\\]" { in_section=1; next }
  in_section && /^## \[/   { exit }
  in_section                { print }
' CHANGELOG.md
```

Expected: prints the `### Added` and `### Changed` content of the `[0.3.0]` section. If empty or wrong, fix `CHANGELOG.md` (likely a missing blank line) before tagging.

- [ ] **Step 8.4: Tag and push**

```bash
git tag v0.3.0
git push origin v0.3.0
```

Expected: tag created and pushed. The release workflow fires within ~60 seconds.

- [ ] **Step 8.5: Verify the workflow run**

Wait ~15 seconds, then:
```bash
gh run list --workflow=release.yml --limit=3 --repo talgolan/session-continuity
```

Expected: the most recent run is for `v0.3.0` with `completed / success`.

- [ ] **Step 8.6: Verify the release body**

```bash
gh release view v0.3.0 --repo talgolan/session-continuity
```

Expected: the release exists, body contains the `### Added` and `### Changed` content from the `[0.3.0]` CHANGELOG section. Empty body or "No CHANGELOG section for 0.3.0" means the extraction failed — see Task 8.7.

- [ ] **Step 8.7: If the release body is empty or wrong**

Delete the release and tag, fix the CHANGELOG or workflow, and re-tag:

```bash
gh release delete v0.3.0 --yes --repo talgolan/session-continuity
git tag -d v0.3.0
git push --delete origin v0.3.0
# fix the issue, commit
git tag v0.3.0
git push origin v0.3.0
```

Re-verify Steps 8.5 and 8.6.

---

## Task 9: Dogfood — run `/session-continuity:end-session` on this repo

**Files:** none modified; dogfooding verification.

- [ ] **Step 9.1: Verify this repo has a primer**

Run: `test -f docs/SESSION_PRIMER.md && test -f docs/LEARNINGS.md && echo ok`

If not `ok`, this repo hasn't dogfooded `/session-continuity:primer` yet. That's Task 15.3 from the v0.2 plan, still pending. Run:

```bash
claude --plugin-dir /Users/tal.golan/.claude/skills/session-continuity
```

Then in the Claude session: `/session-continuity:primer`. Let it init. Exit. Commit the primer.

(This is the v0.2-era TODO; doing it now is the simplest way to unblock Task 9.)

- [ ] **Step 9.2: Launch Claude with the plugin**

```bash
cd /Users/tal.golan/.claude/skills/session-continuity
claude --plugin-dir /Users/tal.golan/.claude/skills/session-continuity
```

- [ ] **Step 9.3: Invoke `/session-continuity:end-session`**

Expected:
- Primer refresh: detects the new commits from Tasks 2-6 + 8 and offers to regenerate the `git log` block.
- Learnings reflection: Claude reviews *this* session's conversation context. Given the bugs we hit (PreToolUse stdout injection, awk range collapse), Claude should surface at least one candidate. Accept the most useful one (the `PreToolUse` + `additionalContext` lesson is the strongest candidate) so LEARNINGS.md gets a real entry.
- Checklist: reflects the repo's current state.

- [ ] **Step 9.4: Commit the outputs**

If the primer and/or a new LEARNINGS entry got staged, commit them in the Claude session or in the shell:

```bash
git commit -m "docs: refresh primer + capture learning from v0.3 session"
git push
```

- [ ] **Step 9.5: Final verification**

```bash
git status            # clean
gh release view v0.3.0 --repo talgolan/session-continuity | head -5  # released
cat docs/LEARNINGS.md | grep -E '^### [0-9]+\.' | head -3  # shows at least one numbered entry
```

Expected: all three succeed.

---

## Task 10: Wrap up

**Files:** none modified; final verification.

- [ ] **Step 10.1: Review final commit log**

```bash
git log --oneline | head -15
```

Expected: clean commit history for v0.3.0 work, no fixup/amend noise.

- [ ] **Step 10.2: Tell the user**

> "v0.3.0 published. Repo at https://github.com/talgolan/session-continuity. New command `/session-continuity:end-session` is live. Dogfooded on this repo — LEARNINGS.md now contains at least one real entry from the v0.3 development session."

- [ ] **Step 10.3: If any v0.2 tasks are still pending**

v0.2 Tasks 13 (second-machine install) and 14 (marketplace submission) remain open. Surface them to the user as follow-ups. They are not blockers for v0.3 but also not done.

---

## Self-review

**Spec coverage:**

| Spec section | Task(s) |
|---|---|
| Problem / Goal | Tasks 2 (the command), 5 (README explains it) |
| Non-goals (no auto-commit, no push, no args, no flags) | Task 2 — all enforced in command prose |
| Command surface (name, file, frontmatter) | Task 2 |
| Step 0 — Precondition | Task 2 (Step 0 section of command) + Task 7 (implicitly, since smoke test uses a primed repo) |
| Step 1 — Primer refresh by delegation | Task 2 (Step 1 section) + Task 7.5 (smoke test) |
| Step 2 — Session reflection + append via /learning | Task 2 (Step 2 section) + Task 7.6 + Task 9.3 (real reflection candidates) |
| Step 3 — Checklist with all 7 rows | Task 2 (Step 3 section) + Task 7.7 + Task 7.8 (edge case) |
| Edge cases (not a git repo, detached HEAD, no upstream) | Task 2 (explicit in Step 3 prose); no upstream exercised in Task 7.7 |
| Suggested commit message derivation | Task 2 (Step 3 prose) + Task 7.7 (verifies message appears) |
| Architecture (single-file, subroutine-by-reference) | Task 2 — no new files beyond the command |
| No new hooks, templates | Tasks 2-6 only touch listed files |
| plugin.json → 0.3.0 | Task 3 |
| CHANGELOG [0.3.0] | Task 4 |
| README updates | Task 5 |
| SKILL.md updates | Task 6 |
| Testing Layer 1 (prose consistency) | Implicit in Tasks 2-6 via the Step `head` / `grep` / `wc -l` checks |
| Testing Layer 2 (live smoke) | Task 7 (full flow + edge case) |
| Testing Layer 3 (dogfood) | Task 9 |
| Acceptance criteria 1 (command loads) | Task 7.5 |
| Acceptance criteria 2 (all three behaviors live-tested) | Task 7.5-7.8 |
| Acceptance criteria 3 (version + CHANGELOG + README) | Tasks 3, 4, 5 |
| Acceptance criteria 4 (v0.3.0 tag + release) | Task 8 |
| Acceptance criteria 5 (dogfood clean) | Task 9 |
| Open questions (stashes, worktrees, msg length) | Deliberately out of scope — revisit post-ship |

All spec requirements have at least one task covering them.

**Placeholder scan:** No TBD / TODO / "fill in later" / "handle edge cases" / "similar to Task N" anywhere. Each code/command step contains the exact content needed.

**Type / name consistency:**
- Command name: `/session-continuity:end-session` used in every reference.
- Version: `0.3.0` consistent across Task 3 (plugin.json), Task 4 (CHANGELOG), Task 8 (tag).
- Step numbering inside `commands/end-session.md` (Steps 0, 1, 2, 3) consistent between Task 2's prose and Task 7's verification steps.
- Subroutine references: "Step 3 of `commands/primer.md`" and "Steps 2-6 of `commands/learning.md`" used consistently (matches the actual section numbering in those files).
- Checklist markers: ✓ / ⚠️ / → used consistently across Task 2's prose, Task 7's expected output, and the example in the command file.

No inconsistencies found.

---

## Execution handoff

Plan complete and saved to [docs/superpowers/plans/2026-04-28-end-session-command-v0.3.md](2026-04-28-end-session-command-v0.3.md). Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints.

Which approach?
