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
3. If a primer exists at the canonical location, does the `git log --oneline -5` block inside it match the actual output of `git log --oneline -5` for the primary branch? (mtime is intentionally not checked — formatters, save-on-blur, and `cat | tee` all bump mtime without changing content. The log-block diff is the authoritative drift signal.)
4. Does `git diff --cached --name-only` contain any file outside `docs/`, `.session-continuity/`, `README*`, `CHANGELOG*`, `LICENSE*`? (Code is staged and a commit is imminent — the primer will be stale the moment that commit lands.)
5. If a primer exists at the canonical location, does `.session-continuity/PROJECT_CONTEXT.md` also exist?

Six states result:

- **Legacy-only layout** (files exist under `docs/` but not under `.session-continuity/`) → migrate mode (Step 2)
- **No primer anywhere** → init mode (Step 3)
- **Conflicting layouts** (files exist at *both* old and new paths) → conflict mode (Step 4)
- **Canonical primer exists but unsplit** (no `PROJECT_CONTEXT.md` yet) → split mode (Step 5)
- **Primer exists at canonical path but stale** (log block drifted or code staged for commit) → refresh mode (Step 6)
- **Primer exists at canonical path and current (nothing staged)** → check mode (Step 7)

## Step 2 — Migrate mode

The repo has session-continuity files at the legacy `docs/` location and
none at `.session-continuity/`. Move them.

1. Create `.session-continuity/` if it doesn't exist: `mkdir -p .session-continuity`.
2. If `docs/SESSION_PRIMER.md` exists: `git mv docs/SESSION_PRIMER.md .session-continuity/SESSION_PRIMER.md`.
3. If `docs/LEARNINGS.md` exists: `git mv docs/LEARNINGS.md .session-continuity/LEARNINGS.md`.
4. **Do not** `rmdir docs/` even if it's now empty — the user may have other docs there now or in the future.
5. Tell the user: "Migrated session-continuity files from `docs/` to `.session-continuity/`. Moves are staged. Commit alongside your next substantive change, or as a one-shot catch-up if no code change is imminent."
6. Then fall through into refresh mode (Step 6) against the new path so the primer reflects the move in its "Current state" block.

**Do not commit automatically.** Staging only.

## Step 3 — Init mode

1. Create `.session-continuity/` if it doesn't exist.
2. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/SESSION_PRIMER.md` to `.session-continuity/SESSION_PRIMER.md`.
3. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/LEARNINGS.md` to `.session-continuity/LEARNINGS.md`.
4. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/PROJECT_CONTEXT.md` to `.session-continuity/PROJECT_CONTEXT.md`.
5. Fill in placeholders Claude can derive automatically:
   - `{{PROJECT_NAME}}` — from `package.json` `name`, `Cargo.toml` `name`, `pyproject.toml` `name`, or the current directory basename.
   - `{{LATEST_COMMIT_HASH_N}}` / `{{LATEST_COMMIT_SUBJECT_N}}` — from `git log --oneline -5`.
   - `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}` — from `pwd`.
   - `{{TEST_COMMAND_SUMMARY}}` — from `package.json` `scripts.test` if present.
   - `{{REPO_LAYOUT_SUMMARY}}` — best-effort from `find . -maxdepth 2 -not -path './node_modules/*' -not -path './.git/*'` plus a one-line description Claude infers from the file extensions present.
   - `{{MODULES_TABLE}}` — leave as `TBD` unless the project has an obvious package/module manifest to read (`package.json` workspaces, Cargo workspace members, etc.) — don't invent structure that isn't there.
6. Ask the user for the blanks that can't be derived: `{{GROUND_RULES}}`, `{{WORKFLOW_CONVENTIONS}}`, `{{WHERE_TO_LOOK_ROWS}}`, `{{STUCK_ESCALATION_STEPS}}`, `{{OUTSTANDING_ITEMS}}`. **Wait for their answer.** Do not proceed to Step 8 until the user responds.
7. **Replace any remaining `{{PLACEHOLDER}}` tokens with `TBD` before staging.** If the user skipped a field, declined to answer, or asked you to stage/commit without filling everything in, substitute `TBD` (with an empty body line where the template had prose). Never leave `{{...}}` syntax in a file you are about to stage — `grep -n '{{' .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .session-continuity/LEARNINGS.md` must return nothing after this step.
8. Stage all three files: `git add .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .session-continuity/LEARNINGS.md`.
9. Tell the user: "Primer, PROJECT_CONTEXT, and LEARNINGS staged. Review and commit with `git commit -m 'docs: initialize session continuity'` when ready." Include a one-line note listing any fields that were set to `TBD` so the user knows what to fill in later.

**Do not commit automatically.** The user commits when ready.

## Step 4 — Conflict mode

Files exist at *both* `docs/` and `.session-continuity/`. This is rare —
it usually means a partial manual migration. Do not move or merge
automatically. Report:

> "Found session-continuity files at both `.session-continuity/` (canonical) and `docs/` (legacy). The `.session-continuity/` copies are treated as canonical. If `docs/SESSION_PRIMER.md` and/or `docs/LEARNINGS.md` are obsolete, remove them manually with `git rm`. Then re-run `/session-continuity:primer`."

Exit without making changes.

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
   responsibility)" and its body updated to describe both files).
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

## Step 6 — Refresh mode

1. Read the current `.session-continuity/SESSION_PRIMER.md`.
2. Regenerate the `git log --oneline -5` block with current output.
3. If the primer has a test-counts section, run the test command(s) found there. **Retry up to 3× when counts disagree across runs** before reporting drift; flaky suites can swing one or two pass/fail counts between runs and a single sample will produce false drift alarms. Pin to the highest stable count (the count seen in ≥2 of 3 runs). If all three runs disagree, surface the spread (`saw 1162 / 1161 / 1162 across 3 runs — using 1162; suite is unstable`) instead of silently picking one.
4. **Surface activity since the last primer refresh.** Find the last commit that touched the primer with `git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md` (fall back to the legacy `docs/SESSION_PRIMER.md` path if needed). Run `git log <that-hash>..HEAD --oneline` and present the subject list to the user as candidate prompts:
   > "Since the last primer refresh, these commits landed:
   > - `<sha> <subject>`
   > - …
   >
   > Any of these resolve outstanding items, or warrant a new LEARNINGS entry?"
   This is a candidate list, not an auto-close. Do not modify outstanding items based on subject heuristics — wait for the user's answer.
5. Ask the user: "Outstanding items — anything to remove (finished) or add (new follow-ups flagged)?"
6. Apply the edits.
7. Stage the updated primer: `git add .session-continuity/SESSION_PRIMER.md`.
8. Tell the user: "Primer refreshed and staged. Include it in your next commit (same commit as the substantive change — do not primer-commit alone)."

## Step 7 — Check mode

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
- **Split mode never deletes.** Like Migrate mode, it only adds/rewrites tracked files — the original content survives in git history even though it's been moved between files.
