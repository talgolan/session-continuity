---
description: Init, refresh, or check docs/SESSION_PRIMER.md — dispatches based on current state.
---

# /session-continuity:primer

You are responding to the `/session-continuity:primer` slash command.

**Your job: dispatch based on the current state of `docs/SESSION_PRIMER.md`.**

## Step 1 — Detect state

Run these checks:

1. Does `docs/SESSION_PRIMER.md` exist?
2. If yes, does the `git log --oneline -5` block inside it match the actual output of `git log --oneline -5` for the primary branch?
3. If yes, is the primer file's mtime newer than HEAD's commit date?

Three states result:

- **No primer** → init mode (Step 2)
- **Primer exists but stale** (log block drifted, or mtime older than HEAD) → refresh mode (Step 3)
- **Primer exists and current** → check mode (Step 4)

## Step 2 — Init mode

1. Create `docs/` if it doesn't exist.
2. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/SESSION_PRIMER.md` to `docs/SESSION_PRIMER.md`.
3. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/LEARNINGS.md` to `docs/LEARNINGS.md`.
4. Fill in placeholders Claude can derive automatically:
   - `{{PROJECT_NAME}}` — from `package.json` `name`, `Cargo.toml` `name`, `pyproject.toml` `name`, or the current directory basename.
   - `{{LATEST_COMMIT_HASH_N}}` / `{{LATEST_COMMIT_SUBJECT_N}}` — from `git log --oneline -5`.
   - `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}` — from `pwd`.
   - `{{TEST_COMMAND_N}}` — from `package.json` `scripts.test` if present.
5. Ask the user for the blanks that can't be derived (layout summary, packages, outstanding items, workflow conventions).
6. Stage both files: `git add docs/SESSION_PRIMER.md docs/LEARNINGS.md`.
7. Tell the user: "Primer and LEARNINGS staged. Review and commit with `git commit -m 'docs: initialize session continuity'` when ready."

**Do not commit automatically.** The user commits when ready.

## Step 3 — Refresh mode

1. Read the current `docs/SESSION_PRIMER.md`.
2. Regenerate the `git log --oneline -5` block with current output.
3. If the primer has a test-counts section, run the test command(s) found there and update the counts to match current output.
4. Ask the user: "Outstanding items — anything to remove (finished) or add (new follow-ups flagged)?"
5. Apply the edits.
6. Stage the updated primer: `git add docs/SESSION_PRIMER.md`.
7. Tell the user: "Primer refreshed and staged. Include it in your next commit (same commit as the substantive change — do not primer-commit alone)."

## Step 4 — Check mode

Report:

```
docs/SESSION_PRIMER.md: up to date against HEAD (<short-sha>)
Last refresh: <primer mtime>
Outstanding items: <count from primer>
Learnings: <count from docs/LEARNINGS.md>
```

No changes made. Exit.

## Notes

- **Never commit automatically.** Stage only.
- **Never invent test counts or outstanding items.** If something can't be derived or isn't supplied, mark it `TBD` and tell the user.
- **Respect the primer-only-commit rule.** If the user asks you to commit only the primer, warn them per `skills/session-continuity/SKILL.md` and proceed only if they confirm it's a catch-up.
