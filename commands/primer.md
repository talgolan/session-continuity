---
description: Init, refresh, or check .session-continuity/SESSION_PRIMER.md — dispatches based on current state.
---

# /session-continuity:primer

You are responding to the `/session-continuity:primer` slash command.

**Your job: dispatch based on the current state of `.session-continuity/SESSION_PRIMER.md`.**

## Step 1 — Detect state

Run the shared dispatch script once, timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-detect.sh" 1; then
  DETECT_OUTPUT="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-detect.sh" . 2>&1)"
  DETECT_STATUS=$?
else
  DETECT_OUTPUT="$SC_REQUIRE_SCRIPT_MSG"
  DETECT_STATUS=1
fi
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-1-detect-state --duration="$_PERF_DURATION"
echo "$DETECT_OUTPUT"
echo "DETECT_STATUS=$DETECT_STATUS"
```

**If `DETECT_STATUS` is nonzero, or `$DETECT_OUTPUT` has no `STEPS=` line:
stop.** Report `$DETECT_OUTPUT` to the user (it carries the diagnostic
either way — `require_script`'s message, or `primer-detect.sh`'s own
stderr, merged into stdout above) and do not execute any step below —
there is no safe default dispatch, since some steps run destructive
migrations (`git mv` in Step 3c, `git rm` in Step 3d).

**Otherwise**, read `STEPS=` from `$DETECT_OUTPUT` and **execute every
name it lists, in the order given, then stop.** Do not re-derive which
steps should run from the individual `KEY=value` facts printed above
`STEPS=` — those are for transparency/debugging only, not a second
source of dispatch truth. If `STEPS` contains `slim_migrate`, Step 4b
is terminal — do not run Step 4 or Step 5 afterward. Else if `STEPS`
contains `refresh`, Step 4 is terminal (its reporting covers what
Step 5 would say) — but first gate with `require_script` +
`primer-validate.sh` on the current primer; if validate fails with
fat-class reasons (headings outside the hard template, banlisted
`git log` content, line-budget blowouts, Mid-flight >5) **or** the
primer still has an `## Outstanding items` heading / leftover
`.session-continuity/BACKLOG.md` fossil, run Step 4b instead of
Step 4. Else run Step 5 (check mode) as the final step after
everything else `STEPS` named — this covers both the fully-empty case
(primer is current, nothing else to do) and a migrations-only case
(migrations ran, but the primer itself isn't otherwise stale; Step 5's
status report is still owed).

| Name in `STEPS` | Run |
|---|---|
| `init` | Step 2 (the only value `STEPS` can ever carry alone) |
| `split` | Step 3 |
| `outstanding_split` | Step 3b |
| `backlog_rename` | Step 3c |
| `backlog_to_issues` | Step 3d |
| `slim_migrate` | Step 4b |
| `refresh` | Step 4 |

Steps 3, 3b, 3c, and 3d's own bodies still say to "fall through" to
refresh or check mode after they finish — that phrasing predates this
dispatch. Treat it as already satisfied by the rule above: continue to
the next name in `STEPS` (if any), then apply the
slim-migrate/refresh/Step-5 rule once, at the very end. Do not let a
step's own fall-through sentence trigger Step 4, 4b, or Step 5 a
second time.

## Step 2 — Init mode

1. Create `.session-continuity/` if it doesn't exist.
2. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/SESSION_PRIMER.md` to `.session-continuity/SESSION_PRIMER.md`.
3. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/LEARNINGS.md` to `.session-continuity/LEARNINGS.md`.
4. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/PROJECT_CONTEXT.md` to `.session-continuity/PROJECT_CONTEXT.md`.
5. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/ROADMAP.md` to `.session-continuity/ROADMAP.md`.
   Do **not** create `.session-continuity/BACKLOG.md` — the backlog is GitHub Issues labeled `backlog`.
6. Fill in placeholders Claude can derive automatically. Gather the raw
   data in **one Bash call**, timed:

   ```bash
   _PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   pwd
   basename "$(pwd)"
   [ -f package.json ] && grep -m1 '"name"' package.json
   [ -f Cargo.toml ] && grep -m1 '^name' Cargo.toml
   [ -f pyproject.toml ] && grep -m1 '^name' pyproject.toml
   [ -f package.json ] && grep -A1 '"scripts"' package.json | grep '"test"'
   find . -maxdepth 2 -not -path './node_modules/*' -not -path './.git/*'
   [ -f CLAUDE.md ] && echo "--- CLAUDE.md ---" && cat CLAUDE.md
   grep -rn -B1 -A2 '@module' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' -- src lib 2>/dev/null | head -100
   TEST_CMD=""
   if [ -f package.json ]; then
     TEST_CMD=$(grep -A1 '"scripts"' package.json | grep '"test"' | sed -E 's/.*"test":[[:space:]]*"([^"]+)".*/\1/')
   elif [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
     TEST_CMD="cargo test"
   elif [ -f pyproject.toml ] && command -v pytest >/dev/null 2>&1; then
     TEST_CMD="pytest"
   fi
   if [ -n "$TEST_CMD" ]; then
     echo "--- test run: $TEST_CMD ---"
     TEST_OUTPUT=$(timeout 120 bash -c "$TEST_CMD" 2>&1)
     TEST_EXIT=$?
     echo "$TEST_OUTPUT" | tail -20
     echo "TEST_RUN_EXIT=$TEST_EXIT"
   fi
   _PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   _PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-2-init-derive-placeholders --duration="$_PERF_DURATION"
   export TEST_CMD TEST_OUTPUT
   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
   if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-init-derive.sh" 1; then
     DERIVE_OUTPUT="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-init-derive.sh" . 2>&1)"
     DERIVE_STATUS=$?
   else
     DERIVE_OUTPUT="$SC_REQUIRE_SCRIPT_MSG"
     DERIVE_STATUS=1
   fi
   echo "$DERIVE_OUTPUT"
   echo "DERIVE_STATUS=$DERIVE_STATUS"
   ```

   **If `DERIVE_STATUS` is nonzero, or `$DERIVE_OUTPUT` has no
   `PROJECT_NAME=` line:** report `$DERIVE_OUTPUT` to the user and ask for
   `{{PROJECT_NAME}}` and `{{TEST_COMMAND_SUMMARY}}` manually in Step 7
   below — never fabricate these from a failed script.

   **Otherwise**, fill directly from `$DERIVE_OUTPUT`'s fields:
   - **SESSION_PRIMER.md (thin hard template):** `{{PROJECT_NAME}}` —
     `PROJECT_NAME`. Leave `{{MID_FLIGHT_BULLET}}` for Step 7 (or set
     one honest TBD bullet). Do **not** embed git-log blocks, test-count
     tables, or Outstanding-items sections — the thin template has no
     place for them. Peers stubs are already in the template.
   - **PROJECT_CONTEXT.md (stable):**
     - `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}` — `WORKING_DIRECTORY_ABSOLUTE_PATH`.
     - `{{TEST_COMMAND_SUMMARY}}` — `TEST_COMMAND_SUMMARY`, verbatim.
     - `{{REPO_LAYOUT_SUMMARY}}` — from the `find` output above, plus a one-line description Claude infers from the file extensions present.
     - `{{MODULES_TABLE}}` — if the `@module` grep above found matches, build one table row per file: Component = file path, Purpose = the `@module` value (plus the docblock's one-line description if present), Notes = the adjacent `Exports:` line if present. If it found nothing, leave `TBD` as before — don't invent structure that isn't there.
     - `{{WORKFLOW_CONVENTIONS}} (draft)` — if `CLAUDE.md` exists (cat output above), draft this field by quoting its relevant conventions (runtime choice, commit style, workflow/never-do rules) under a "Conventions inherited from CLAUDE.md" sub-heading, instead of leaving it blank for the user to retype. Present the draft in Step 7 for confirmation rather than asking cold.

   After the thin primer is written, print the install-order blurb once:
   > Install order: primer → graphify (commit `graphify-out/graph.json`) → engrim → `/session-continuity:doctor`.
7. Ask the user for the blanks that can't be derived: up to 5 Mid-flight
   bullets for the primer (`{{MID_FLIGHT_BULLET}}` / additional `- `
   lines, capped at 5), plus `{{GROUND_RULES}}`, `{{WHERE_TO_LOOK_ROWS}}`,
   `{{STUCK_ESCALATION_STEPS}}`, and `{{WORKFLOW_CONVENTIONS}}` only if no
   `CLAUDE.md` draft was produced above. If a draft was produced, show it
   and ask the user to confirm or amend it rather than asking a blank
   question. **Wait for their answer.** Do not proceed to Step 9 until
   the user responds.

   **Backlog.** Do not write a markdown backlog file. If origin contains `github.com` and the user named follow-ups, file each as a GitHub Issue:

   ```bash
   gh label create backlog --description "Agent backlog (session-continuity)" --force
   gh issue create --label backlog --title "<title>" --body "<1-3 sentences>"
   ```

   Title plus 1-3 sentences per issue. If they said "none" or skipped, file nothing.
8. **Replace any remaining `{{PLACEHOLDER}}` tokens with `TBD` before staging.** If the user skipped a field, declined to answer, or asked you to stage/commit without filling everything in, substitute `TBD` (with an empty body line where the template had prose). Never leave `{{...}}` syntax in a file you are about to stage — `grep -n '{{' .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .session-continuity/LEARNINGS.md .session-continuity/ROADMAP.md` must return nothing after this step.
9. Stage four files: `git add .session-continuity/SESSION_PRIMER.md .session-continuity/PROJECT_CONTEXT.md .session-continuity/LEARNINGS.md .session-continuity/ROADMAP.md`.
10. Tell the user: "Primer, PROJECT_CONTEXT, ROADMAP, and LEARNINGS staged. Review and commit with `git commit -m 'docs: initialize session continuity'` when ready." Include a one-line note listing any fields that were set to `TBD` so the user knows what to fill in later. If issues were filed, list their `#N` numbers. Remind them: `/session-continuity:doctor` stays red until peers exist — finish install order (graphify commit of `graphify-out/graph.json`, then engrim on PATH) and re-doctor.

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

## Step 3b — Outstanding-items split

Runs when `outstanding_split` appears in Step 1's `STEPS`. Extract the
primer's inline `## Outstanding items` section into the new file; this
is a one-time content move, no numbering changes — the items keep
whatever numbers they currently have, and those become the first
permanent IDs.

1. Read the existing `.session-continuity/SESSION_PRIMER.md` in full.
2. Copy every top-level numbered item under `## Outstanding items`
   (the numbered line plus indented continuation lines until the next
   top-level number) into a new `.session-continuity/OUTSTANDING_ITEMS.md`.
   Reformat each into the `### N.
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

## Step 3c — Backlog rename migration

Runs when `backlog_rename` appears in Step 1's `STEPS`. This is strictly
the `OUTSTANDING_ITEMS.md` → `BACKLOG.md` rename, one level up from Step
3b (which may have just created `OUTSTANDING_ITEMS.md` under its old
name this same run — `STEPS` already places `backlog_rename` after
`outstanding_split` when both fire).

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

## Step 3d — BACKLOG.md → GitHub Issues

Runs when `backlog_to_issues` appears in Step 1's `STEPS`. If it doesn't
(non-github origin, or no backlog to migrate), leave any existing
`BACKLOG.md` in place as a fossil and tell the user
`/session-continuity:doctor` will warn that the queue is inactive. Do
not keep writing to the fossil.

1. `gh label create backlog --description "Agent backlog (session-continuity)" --force`
2. For each `### N. [tag] [YYYY-MM-DD] Title` heading whose title is
   **not** a `— closed.` stub: `gh issue create --label backlog --title "<Title>" --body "<item body, 1-3 sentences>"`. Record the new `#N` next to the old hex tag.
3. `git rm .session-continuity/BACKLOG.md`
4. Rewrite any remaining hex-tag mentions in `.session-continuity/` and
   specs/plans you can map. Historical CHANGELOG lines may keep old
   names.
5. Tell the user the issue numbers created and that the markdown file is
   gone.

If `gh` fails, stop, leave the file, report the error. Do not delete
the file unless the issues exist.

## Step 4 — Refresh mode

Thin refresh only. Rewrite **Mid-flight** and **Confirm** (and update
**Peers** status lines in the file). Peers status lines are
agent-maintained on refresh/slim-migrate only — **not** by SessionStart.
Do **not** regenerate git-log blocks, test-count tables, or any other
fat-primer section.

1. Read the current `.session-continuity/SESSION_PRIMER.md`.
2. Optionally surface activity since the last primer refresh (for the
   backlog prompt below — not for writing into the primer). **One Bash
   call**, timed:

   ```bash
   _PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   LAST_PRIMER_COMMIT=$(git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md)
   git log "$LAST_PRIMER_COMMIT"..HEAD --oneline
   _PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   _PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-4-activity-surface --duration="$_PERF_DURATION"
   ```

   Run `bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-issues.sh" .` for
   the current open-issue list. Present the subject list from the
   `git log` output above as candidate prompts (candidate list, not
   auto-close — wait for the user's answer).
3. Ask the user: "Backlog — anything to close (finished) or file (new follow-ups)?" Close with `gh issue close N --reason completed` only after checking the claim against the actual code. File new follow-ups with `gh issue create --label backlog --title "..." --body "..."` (title plus 1-3 sentences). Never create or edit `.session-continuity/BACKLOG.md`.
4. Rewrite Mid-flight (≤5 bullets of currently open work + pointer + optional one-line trap) and Confirm (≤5 counted commands that falsify Mid-flight if they fail). Update Peers status lines from a `require_script` + `peer-probes.sh` probe if useful — do not grow the file past the hard template.
5. After the write, validate before staging:

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
   if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-validate.sh" 1; then
     bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-validate.sh" .session-continuity/SESSION_PRIMER.md
   else
     echo "$SC_REQUIRE_SCRIPT_MSG" >&2
     false
   fi
   ```

   **On failure: stop.** Show the validator's stderr (`INVALID: …` lines)
   to the user. Do not stage a failing primer. If the failure is fat-class
   or fossils remain, divert to Step 4b instead of retrying a partial
   patch.
6. Stage the updated primer: `git add .session-continuity/SESSION_PRIMER.md`.
7. Tell the user: "Primer refreshed and staged. Include it in your next commit (same commit as the substantive change — do not primer-commit alone)."

## Step 4b — Slim-migrate mode

One-shot rewrite from a fat (or fossil-bearing) primer to the thin hard
template. Triggered when `STEPS` contains `slim_migrate`, or when Step 4's
pre-gate / post-write validate fails with fat-class reasons, or leftover
`## Outstanding items` / `.session-continuity/BACKLOG.md` fossils remain.

1. Read the current fat primer (and any Outstanding / BACKLOG fossils) in full.
2. Copy the thin template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/SESSION_PRIMER.md` over `.session-continuity/SESSION_PRIMER.md`.
3. Fill `{{PROJECT_NAME}}` from the old primer title or repo name.
4. Select ≤5 Mid-flight bullets from the old narrative (open work + pointer + optional trap). Remaining open work → file as GitHub Issues labeled `backlog` if needed; drop the rest. Do not dual-write old sections.
5. Write Confirm commands (≤5 counted) that falsify those Mid-flight bullets if they fail. Update Peers status lines (agent-maintained here — not SessionStart).
6. Validate before stage:

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
   if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-validate.sh" 1; then
     bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-validate.sh" .session-continuity/SESSION_PRIMER.md
   else
     echo "$SC_REQUIRE_SCRIPT_MSG" >&2
     false
   fi
   ```

   **On failure: stop** and show stderr. Do not stage.
7. If a markdown BACKLOG fossil exists and origin is GitHub, prefer migrating items to Issues (same rules as Step 3d) rather than leaving the fossil; otherwise leave it and note that doctor will warn.
8. Stage: `git add .session-continuity/SESSION_PRIMER.md` (and any Issue-migration paths touched).
9. Tell the user the primer was slim-migrated to the thin hard template, list Mid-flight bullets chosen, and remind install order if peers are still missing: primer → graphify (commit `graphify-out/graph.json`) → engrim → re-doctor.

**Do not commit automatically.** Staging only.

## Step 5 — Check mode

Gather status, shape, and peer summary — all via `require_script`. Timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"

if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-status.sh" 1; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-status.sh" .
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
fi

echo "--- primer validate ---"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-validate.sh" 1; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-validate.sh" .session-continuity/SESSION_PRIMER.md \
    && echo "PRIMER_VALIDATE=ok" || echo "PRIMER_VALIDATE=fail"
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
  echo "PRIMER_VALIDATE=fail"
fi

echo "--- peer probes ---"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/peer-probes.sh" 1; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/peer-probes.sh" .
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
  echo "ENGRIM=?"
  echo "GRAPHIFY=?"
fi

_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-5-check-mode --duration="$_PERF_DURATION"
```

Report `primer-status.sh`'s `KEY=value` lines (any `?` stays `?` — never
invent), then shape (`PRIMER_VALIDATE=ok|fail` plus any `INVALID:`
reasons), then peers (`ENGRIM=…`, `GRAPHIFY=…`). If peers are not ok,
include install order: primer → graphify (commit `graphify-out/graph.json`)
→ engrim → re-doctor.

No changes made. Exit.

## Notes

- **Never commit automatically.** Stage only.
- **Never invent test counts or outstanding items.** If something can't be derived or isn't supplied, mark it `TBD` and tell the user.
- **Respect the primer-only-commit rule.** If the user asks you to commit only the primer, warn them per `skills/session-continuity/SKILL.md` and proceed only if they confirm it's a catch-up.
- **Split mode never deletes.** It only adds/rewrites tracked files — the original content survives in git history even though it's been moved between files.
