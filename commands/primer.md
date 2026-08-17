---
description: Init, refresh, or check .session-continuity/SESSION_PRIMER.md — dispatches based on current state.
---

# /session-continuity:primer

You are responding to the `/session-continuity:primer` slash command.

**Your job: dispatch based on the current state of `.session-continuity/SESSION_PRIMER.md`.**

## Step 1 — Detect state

Gather the raw data for every check below in **one Bash call**, timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
[ -f .session-continuity/SESSION_PRIMER.md ] && echo "PRIMER_EXISTS=1" || echo "PRIMER_EXISTS=0"
[ -f .session-continuity/LEARNINGS.md ] && echo "LEARNINGS_EXISTS=1" || echo "LEARNINGS_EXISTS=0"
[ -f .session-continuity/PROJECT_CONTEXT.md ] && echo "PROJECT_CONTEXT_EXISTS=1" || echo "PROJECT_CONTEXT_EXISTS=0"
git log --oneline -5
git diff --cached --name-only
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-1-detect-state --duration="$_PERF_DURATION"
```

Interpret the output:

1. Do `.session-continuity/SESSION_PRIMER.md` and `.session-continuity/LEARNINGS.md` exist? (`PRIMER_EXISTS` / `LEARNINGS_EXISTS` above.)
2. If a primer exists, does the `git log --oneline -5` block inside it match the `git log --oneline -5` output above? (mtime is intentionally not checked — formatters, save-on-blur, and `cat | tee` all bump mtime without changing content. The log-block diff is the authoritative drift signal.)
3. Does the `git diff --cached --name-only` output above contain any file outside `docs/`, `.session-continuity/`, `README*`, `CHANGELOG*`, `LICENSE*`? (Code is staged and a commit is imminent — the primer will be stale the moment that commit lands.)
4. If a primer exists, does `.session-continuity/PROJECT_CONTEXT.md` also exist? (`PROJECT_CONTEXT_EXISTS` above.)

Four states result:

- **No primer** → init mode (Step 2)
- **Primer exists but unsplit** (no `PROJECT_CONTEXT.md` yet) → split mode (Step 3)
- **Primer exists but stale** (log block drifted or code staged for commit) → refresh mode (Step 4)
- **Primer exists and current** (nothing staged) → check mode (Step 5)

## Step 2 — Init mode

1. Create `.session-continuity/` if it doesn't exist.
2. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/SESSION_PRIMER.md` to `.session-continuity/SESSION_PRIMER.md`.
3. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/LEARNINGS.md` to `.session-continuity/LEARNINGS.md`.
4. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/PROJECT_CONTEXT.md` to `.session-continuity/PROJECT_CONTEXT.md`.
5. Fill in placeholders Claude can derive automatically. Gather the raw
   data in **one Bash call**, timed:

   ```bash
   _PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   pwd
   basename "$(pwd)"
   [ -f package.json ] && grep -m1 '"name"' package.json
   [ -f Cargo.toml ] && grep -m1 '^name' Cargo.toml
   [ -f pyproject.toml ] && grep -m1 '^name' pyproject.toml
   git log --oneline -5
   [ -f package.json ] && grep -A1 '"scripts"' package.json | grep '"test"'
   find . -maxdepth 2 -not -path './node_modules/*' -not -path './.git/*'
   _PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   _PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
   bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-2-init-derive-placeholders --duration="$_PERF_DURATION"
   ```

   Derive from that output:
   - `{{PROJECT_NAME}}` — from `package.json` `name`, `Cargo.toml` `name`, `pyproject.toml` `name`, or the current directory basename.
   - `{{LATEST_COMMIT_HASH_N}}` / `{{LATEST_COMMIT_SUBJECT_N}}` — from the `git log --oneline -5` output above.
   - `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}` — from the `pwd` output above.
   - `{{TEST_COMMAND_SUMMARY}}` — from the `scripts.test` grep above, if present.
   - `{{REPO_LAYOUT_SUMMARY}}` — from the `find` output above, plus a one-line description Claude infers from the file extensions present.
   - `{{MODULES_TABLE}}` — leave as `TBD` unless the project has an obvious package/module manifest to read (`package.json` workspaces, Cargo workspace members, etc.) — don't invent structure that isn't there.
6. Ask the user for the blanks that can't be derived: `{{GROUND_RULES}}`, `{{WORKFLOW_CONVENTIONS}}`, `{{WHERE_TO_LOOK_ROWS}}`, `{{STUCK_ESCALATION_STEPS}}`, `{{OUTSTANDING_ITEMS}}`. **Wait for their answer.** Do not proceed to Step 8 until the user responds.
7. **Replace any remaining `{{PLACEHOLDER}}` tokens with `TBD` before staging.** If the user skipped a field, declined to answer, or asked you to stage/commit without filling everything in, substitute `TBD` (with an empty body line where the template had prose). Never leave `{{...}}` syntax in a file you are about to stage — `grep -n '{{' .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .session-continuity/LEARNINGS.md` must return nothing after this step.
8. Stage all three files: `git add .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .session-continuity/LEARNINGS.md`.
9. Tell the user: "Primer, PROJECT_CONTEXT, and LEARNINGS staged. Review and commit with `git commit -m 'docs: initialize session continuity'` when ready." Include a one-line note listing any fields that were set to `TBD` so the user knows what to fill in later.

**Do not commit automatically.** The user commits when ready.

## Step 3 — Split mode

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
7. Fall through into whichever of refresh mode (Step 4) or check mode
   (Step 5) applies against the now-split primer.

**Do not commit automatically.** Staging only.

## Step 4 — Refresh mode

1. Read the current `.session-continuity/SESSION_PRIMER.md`.
2. Regenerate the `git log --oneline -5` block. **One Bash call**, timed:

   ```bash
   _PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   git log --oneline -5
   _PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   _PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
   bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-4-git-log-refresh --duration="$_PERF_DURATION"
   ```

   Use the output above to regenerate the primer's block.
3. If the primer has a test-counts section, decide whether to re-run it.
   Do this as **one Bash call**, timed, tracking a `RETRIES` count (0
   if skipped or the first run matched, else the number of *extra*
   runs actually executed beyond the first):
   - **Skip the rerun** if `git diff <last-primer-commit>..HEAD --name-only` (the commit range since the primer was last touched) contains no file outside `.session-continuity/` — no source or test file changed, so the recorded count cannot have drifted. Reuse this diff if already computed elsewhere in this flow; don't recompute it just for this check.
   - **Otherwise, run the test command(s) once.** If that single run's count matches the primer's recorded count, stop there — no drift on this axis, no further runs.
   - **Only if that first run disagrees with the recorded count**, retry up to 2 more times (3 runs total) to rule out flakiness before reporting drift — a single sample can swing a pass/fail count and produce a false drift alarm. Pin to the count seen in ≥2 of the 3 runs. If that pinned count matches the primer's recorded count, the first run was the flake — no drift. If it differs, report drift with the pinned count. If all three runs disagree with each other, surface the spread (`saw 1162 / 1161 / 1162 across 3 runs — using 1162; suite is unstable`) instead of silently picking one.

   This keeps the common cases cheap: zero test runs when no relevant file changed, one run when relevant files changed but the count still holds, and the full 3-run majority vote only when there's an actual discrepancy to resolve.

   At the end of this Bash call (whichever branch above ran), call:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-4-test-count-rerun --duration="$_PERF_DURATION" --retries="$RETRIES"
   ```
   using the same `_PERF_START`/`_PERF_END`/`_PERF_DURATION` pattern
   shown in item 2 above, captured around this whole check.
4. **Surface activity since the last primer refresh.** **One Bash
   call**, timed:

   ```bash
   _PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   LAST_PRIMER_COMMIT=$(git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md)
   git log "$LAST_PRIMER_COMMIT"..HEAD --oneline
   _PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   _PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
   bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-4-activity-surface --duration="$_PERF_DURATION"
   ```

   Present the subject list from the `git log` output above to the
   user as candidate prompts:
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

## Step 5 — Check mode

Gather the report data in **one Bash call**, timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
git rev-parse --short HEAD
stat -f '%Sm' .session-continuity/SESSION_PRIMER.md 2>/dev/null || stat -c '%y' .session-continuity/SESSION_PRIMER.md
grep -c '^[0-9]\+\.' .session-continuity/SESSION_PRIMER.md 2>/dev/null || echo 0
grep -c '^### [0-9]\+\.' .session-continuity/LEARNINGS.md 2>/dev/null || echo 0
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-5-check-mode --duration="$_PERF_DURATION"
```

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
- **Split mode never deletes.** It only adds/rewrites tracked files — the original content survives in git history even though it's been moved between files.
