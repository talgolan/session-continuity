---
description: Init, migrate, refresh, or check .session-continuity/SESSION_PRIMER.md — dispatches based on current state.
---

# /session-continuity:primer

You are responding to the `/session-continuity:primer` slash command.

**Your job: dispatch based on the current state of `.session-continuity/SESSION_PRIMER.md`.**

As of v0.5.0 the canonical location is `.session-continuity/`. Earlier
versions used `docs/`. Projects created against v0.4 and earlier need to
be migrated; this command does so automatically when it detects the old
layout (Step 2).

## Step 1 — Detect state

Run these checks, in order:

1. Do `.session-continuity/SESSION_PRIMER.md` and `.session-continuity/LEARNINGS.md` exist?
2. Do `docs/SESSION_PRIMER.md` and/or `docs/LEARNINGS.md` exist?
3. If a primer exists at the canonical location, does the `git log --oneline -5` block inside it match the actual output of `git log --oneline -5` for the primary branch?
4. If yes to (3), is the primer file's mtime newer than HEAD's commit date?
5. If yes to (4), does `git diff --cached --name-only` contain any file outside `docs/`, `.session-continuity/`, `README*`, `CHANGELOG*`, `LICENSE*`? (Code is staged and a commit is imminent — the primer will be stale the moment that commit lands.)

Five states result:

- **Legacy-only layout** (files exist under `docs/` but not under `.session-continuity/`) → migrate mode (Step 2)
- **No primer anywhere** → init mode (Step 3)
- **Conflicting layouts** (files exist at *both* old and new paths) → conflict mode (Step 4)
- **Primer exists at canonical path but stale** (log block drifted, mtime older than HEAD, or code staged for commit) → refresh mode (Step 5)
- **Primer exists at canonical path and current (nothing staged)** → check mode (Step 6)

## Step 2 — Migrate mode

The repo has session-continuity files at the legacy `docs/` location and
none at `.session-continuity/`. Move them.

1. Create `.session-continuity/` if it doesn't exist: `mkdir -p .session-continuity`.
2. If `docs/SESSION_PRIMER.md` exists: `git mv docs/SESSION_PRIMER.md .session-continuity/SESSION_PRIMER.md`.
3. If `docs/LEARNINGS.md` exists: `git mv docs/LEARNINGS.md .session-continuity/LEARNINGS.md`.
4. **Do not** `rmdir docs/` even if it's now empty — the user may have other docs there now or in the future.
5. Tell the user: "Migrated session-continuity files from `docs/` to `.session-continuity/`. Moves are staged. Commit alongside your next substantive change, or as a one-shot catch-up if no code change is imminent."
6. Then fall through into refresh mode (Step 5) against the new path so the primer reflects the move in its "Current state" block.

**Do not commit automatically.** Staging only.

## Step 3 — Init mode

1. Create `.session-continuity/` if it doesn't exist.
2. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/SESSION_PRIMER.md` to `.session-continuity/SESSION_PRIMER.md`.
3. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/LEARNINGS.md` to `.session-continuity/LEARNINGS.md`.
4. Fill in placeholders Claude can derive automatically:
   - `{{PROJECT_NAME}}` — from `package.json` `name`, `Cargo.toml` `name`, `pyproject.toml` `name`, or the current directory basename.
   - `{{LATEST_COMMIT_HASH_N}}` / `{{LATEST_COMMIT_SUBJECT_N}}` — from `git log --oneline -5`.
   - `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}` — from `pwd`.
   - `{{TEST_COMMAND_N}}` — from `package.json` `scripts.test` if present.
5. Ask the user for the blanks that can't be derived (layout summary, packages, outstanding items, workflow conventions). **Wait for their answer.** Do not proceed to Step 7 until the user responds.
6. **Replace any remaining `{{PLACEHOLDER}}` tokens with `TBD` before staging.** If the user skipped a field, declined to answer, or asked you to stage/commit without filling everything in, substitute `TBD` (with an empty body line where the template had prose). Never leave `{{...}}` syntax in a file you are about to stage — `grep -n '{{' .session-continuity/SESSION_PRIMER.md .session-continuity/LEARNINGS.md` must return nothing after this step.
7. Stage both files: `git add .session-continuity/SESSION_PRIMER.md .session-continuity/LEARNINGS.md`.
8. Tell the user: "Primer and LEARNINGS staged. Review and commit with `git commit -m 'docs: initialize session continuity'` when ready." Include a one-line note listing any fields that were set to `TBD` so the user knows what to fill in later.

**Do not commit automatically.** The user commits when ready.

## Step 4 — Conflict mode

Files exist at *both* `docs/` and `.session-continuity/`. This is rare —
it usually means a partial manual migration. Do not move or merge
automatically. Report:

> "Found session-continuity files at both `.session-continuity/` (canonical) and `docs/` (legacy). The `.session-continuity/` copies are treated as canonical. If `docs/SESSION_PRIMER.md` and/or `docs/LEARNINGS.md` are obsolete, remove them manually with `git rm`. Then re-run `/session-continuity:primer`."

Exit without making changes.

## Step 5 — Refresh mode

1. Read the current `.session-continuity/SESSION_PRIMER.md`.
2. Regenerate the `git log --oneline -5` block with current output.
3. If the primer has a test-counts section, run the test command(s) found there and update the counts to match current output.
4. Ask the user: "Outstanding items — anything to remove (finished) or add (new follow-ups flagged)?"
5. Apply the edits.
6. Stage the updated primer: `git add .session-continuity/SESSION_PRIMER.md`.
7. Tell the user: "Primer refreshed and staged. Include it in your next commit (same commit as the substantive change — do not primer-commit alone)."

## Step 6 — Check mode

Report:

```
.session-continuity/SESSION_PRIMER.md: up to date against HEAD (<short-sha>)
Last refresh: <primer mtime>
Outstanding items: <count from primer>
Learnings: <count from .session-continuity/LEARNINGS.md>
```

No changes made. Exit.

## Notes

- **Never commit automatically.** Stage only.
- **Never invent test counts or outstanding items.** If something can't be derived or isn't supplied, mark it `TBD` and tell the user.
- **Respect the primer-only-commit rule.** If the user asks you to commit only the primer, warn them per `skills/session-continuity/SKILL.md` and proceed only if they confirm it's a catch-up.
- **Migrate mode never deletes.** It moves with `git mv` (preserving history) and leaves `docs/` itself alone in case the user has unrelated docs there.
