# Design: BACKLOG.md rename, ROADMAP.md, and /session-continuity:help

Date: 2026-08-31
Status: approved for planning

## Problem

`.session-continuity/OUTSTANDING_ITEMS.md` is the wrong name for what the
file actually holds — a backlog of deferred work, not "items outstanding"
(which reads like open bugs/debt). Separately, the plugin has no file for
strategic direction (near/mid/long-term intent) distinct from tactical
backlog, and no single command that explains what the plugin is for and
what each file is responsible for — a new user has to read `SKILL.md` end
to end to get that picture.

## Goals

1. Rename `OUTSTANDING_ITEMS.md` → `BACKLOG.md` everywhere (template,
   commands, hooks, skill docs, this repo's own instance), with the same
   semantics (permanent numbering, delete-on-close, title + 1-3-sentence
   cap).
2. Add a new stub file, `ROADMAP.md`, for strategic direction — Now / Next
   / Later sections, no version numbers, no numbering/permanence rules.
3. Add `/session-continuity:help` — zero-arg, read-only — explaining the
   plugin's purpose, why it exists, and the intent of each of the five
   `.session-continuity/` files plus the command list.
4. Migrate existing installs (including this repo) automatically via
   `/session-continuity:primer`, rather than leaving a manual rename step
   for every consuming project.

## Non-goals

- No change to BACKLOG's numbering/closing rules — pure rename.
- No auto-population of ROADMAP.md content — stub only, user fills it in.
- No new hook behavior beyond updating existing path references and adding
  one migration branch to the existing elif chain in `session-start.sh`.

## File inventory (every touchpoint)

Renamed / content-updated:

- `skills/session-continuity/templates/OUTSTANDING_ITEMS.md` → renamed to
  `skills/session-continuity/templates/BACKLOG.md` (heading "Outstanding
  Items" → "Backlog", `{{OUTSTANDING_ITEMS}}` placeholder → `{{BACKLOG}}`,
  prose otherwise unchanged).
- `hooks/session-start.sh` — `outstanding_path` var, reminder text
  ("Outstanding items:" → "Backlog:"), migration elif chain (see below).
- `commands/primer.md` — Step 1 detection vars, Step 3b heading/prose
  (existing outstanding-items-file migration step, itself now historical —
  rename its file references), new Step 3c (see Migration below), Steps 4
  and 5 prose/paths.
- `commands/doctor.md` — file-existence loop (`OUTSTANDING_ITEMS.md` →
  `BACKLOG.md`, add `ROADMAP.md` as a sixth tracked file), report row text.
- `commands/end-session.md` — checklist row referencing the file.
- `skills/session-continuity/SKILL.md` — file list (intro bullets, "four
  in-repo files" → "five in-repo files"), numbering-convention section,
  maintenance-rules section, quick-start sections, command list (add
  `/session-continuity:help`).
- `skills/session-continuity/REFERENCE.md` — decision tree, "what goes
  where," any other mentions.
- `skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md` — file list
  the snippet tells consuming projects to add to their own CLAUDE.md.
- `.claude-plugin/plugin.json` — `description` field (four docs → five;
  add `help` to command surface if commands are enumerated there — they
  are not today, skip if so).
- `README.md` — file list / command list sections.
- `CHANGELOG.md` — new entry for this version.
- `.session-continuity/OUTSTANDING_ITEMS.md` (this repo's own instance) —
  migrated via the same primer.md logic (dogfooding — see Rollout).

New:

- `skills/session-continuity/templates/ROADMAP.md` — new stub template.
- `commands/help.md` — new command.

## BACKLOG.md — rename details

Content is a straight carry-over from `OUTSTANDING_ITEMS.md`: same rules
(permanent numbering, delete-on-close, grep-before-delete, title + 1-3
sentence cap, link-out for anything longer). Only the heading ("Outstanding
Items — {{PROJECT_NAME}}" → "Backlog — {{PROJECT_NAME}}"), the placeholder
token (`{{OUTSTANDING_ITEMS}}` → `{{BACKLOG}}`), and the "not bugs... not
current state" framing sentence (unchanged in substance, just renamed)
change.

## ROADMAP.md — new stub template

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

Init mode (`/session-continuity:primer`, Step 2) creates this file
alongside the other four, same placeholder-to-`TBD` fallback rule as every
other template field. Not required reading every session — `SKILL.md`'s
"quick start" sequence stays primer → project_context → backlog →
learnings; roadmap is consulted when direction, not day-to-day state, is
in question.

## Migration — primer.md Step 3c (new)

Runs whenever `BACKLOG.md` doesn't exist AND `OUTSTANDING_ITEMS.md` does
(the existing Step 3b migration — inline-heading-to-file — has already
happened or doesn't apply; Step 3c is strictly the file-rename, one level
up). Detection added to primer.md's Step 1 gather block:

```bash
[ -f .session-continuity/BACKLOG.md ] && echo "BACKLOG_EXISTS=1" || echo "BACKLOG_EXISTS=0"
[ -f .session-continuity/ROADMAP.md ] && echo "ROADMAP_EXISTS=1" || echo "ROADMAP_EXISTS=0"
```

Sequencing rule (mirrors Step 3b's own sequencing note): if the primer is
also unsplit or has inline outstanding items, run Steps 3/3b to completion
first, then 3c — the migrations touch content that must exist in its
final (post-3b) shape before the straight rename happens.

Step 3c body:

1. `git mv .session-continuity/OUTSTANDING_ITEMS.md .session-continuity/BACKLOG.md`.
2. Rewrite the moved file's heading (`# Outstanding Items — X` → `# Backlog
   — X`) and the "not bugs... not current state" framing sentence's file
   reference — content and item numbers otherwise untouched.
3. Rewrite every reference to `OUTSTANDING_ITEMS.md` inside
   `.session-continuity/SESSION_PRIMER.md` (if any remain post-3b) to
   `BACKLOG.md`.
4. If `.session-continuity/ROADMAP.md` doesn't exist, create it from the
   template with `{{ROADMAP_NOW/NEXT/LATER}}` set to `TBD` (no interactive
   prompt — stub only, same one-event-not-two rule as the design's Goal 4).
5. Stage all touched/new files:
   `git add .session-continuity/BACKLOG.md .session-continuity/ROADMAP.md .session-continuity/SESSION_PRIMER.md`
   (only add SESSION_PRIMER.md if step 3 actually changed it).
6. Tell the user: "Migrated `.session-continuity/OUTSTANDING_ITEMS.md` →
   `BACKLOG.md` (N items, numbers preserved) and stubbed in
   `.session-continuity/ROADMAP.md`. Both staged — review before
   committing."
7. Fall through to whichever of refresh mode or check mode applies next,
   same fall-through convention as Steps 3 and 3b.

**Do not commit automatically.** Staging only — same rule as every other
split/migration step in this command.

### session-start.sh — new elif branch

Add a branch to the existing `if/elif/else` chain (currently: BACKLOG-file
path exists → read counts; elif old inline heading present → warn to
migrate; else → zero/empty) so a project with `OUTSTANDING_ITEMS.md` but
no `BACKLOG.md` yet gets the same "migrate now" nudge the inline-heading
case already gets, rather than silently reporting zero backlog items.

## /session-continuity:help — command design

`commands/help.md`, frontmatter description: "Explain what this plugin
does, why, and what each `.session-continuity/` file is for. Zero args,
read-only, no state mutation."

Structure:

1. **One Bash line** (parse installed version):
   ```bash
   grep -m1 '"version"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null || echo "version unknown (vendored install)"
   ```
2. **Static prose**, assembled by Claude from the command file's own
   content (not re-derived per run — this is fixed reference text, unlike
   doctor's live probes):
   - **What this is** — one paragraph, from `plugin.json`'s description
     line, expanded slightly: cross-session memory for Claude Code
     projects via five in-repo docs.
   - **Why** — the handoff problem: a fresh session (or a fresh Claude
     instance) has no memory of prior sessions; these files are the
     mechanism that survives a `/clear`, a new terminal, a new day.
   - **The five files**, one paragraph each: `SESSION_PRIMER.md`
     (volatile, current state, refreshed alongside substantive commits),
     `PROJECT_CONTEXT.md` (stable, changes rarely), `BACKLOG.md` (tactical,
     deferred work, permanently numbered), `ROADMAP.md` (strategic
     direction, freeform, no numbering), `LEARNINGS.md` (durable wisdom,
     append-only, numbered).
   - **Commands** — list of all six (soon seven) `/session-continuity:*`
     commands with a one-line purpose each, pulled from each command's own
     frontmatter `description` rather than hand-duplicated prose (reduces
     drift risk — if a command's description changes, help's list is
     regenerated from source, not maintained by hand in two places).
3. No file writes, no git operations. Matches doctor's "never mutates
   anything" note verbatim.

## Rollout

- Branch: `feature/backlog-roadmap-help` off `main`.
- Version bump: 0.21.1 → 0.22.0 (minor — new command + new file type is a
  visible behavior addition, not a patch).
- `CHANGELOG.md` entry under the new version.
- This repo's own `.session-continuity/OUTSTANDING_ITEMS.md` is migrated
  by running the updated `/session-continuity:primer` against this repo as
  part of the same PR — proves the migration path works before it ships to
  any other consumer, and leaves this repo in the same five-file shape it
  will tell other projects to adopt.
- PR against `main` once tests/docs pass and the primer/backlog/roadmap
  files in this repo reflect the change.

## Open questions

None — all three decision points (migration behavior, ROADMAP shape,
help command staticness) were resolved during brainstorming; recommended
options accepted in each case.
