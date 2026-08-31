---
name: session-continuity
description: Establish and maintain cross-session memory for a project via four in-repo docs — .session-continuity/SESSION_PRIMER.md (current state, refreshed alongside substantive commits), .session-continuity/OUTSTANDING_ITEMS.md (explicitly deferred work), .session-continuity/PROJECT_CONTEXT.md (stable repo context, changes rarely), and .session-continuity/LEARNINGS.md (append-only wisdom for 15+ min bugs). Use when starting, before commits, or after hard-won bugs.
---

# Session Continuity

Four in-repo files act as a handoff between Claude sessions on the same project:

- **`.session-continuity/SESSION_PRIMER.md`** — current-state snapshot (latest commits, working state). **Refresh alongside substantive commits** (stage the update in the same commit as the real change). Always reflects "what's true right now."
- **`.session-continuity/OUTSTANDING_ITEMS.md`** — backlog of explicitly deferred follow-ups and decisions (not bugs, not current state). Permanent numbering (delete-on-close, never renumber, never reuse a number), title + 1-3 sentence length cap per item — anything longer moves to a linked file under `meta/superpowers/`.
- **`.session-continuity/PROJECT_CONTEXT.md`** — stable repo context (layout, module table, workflow conventions, test expectations, "where to look for what"). Changes rarely — only when the project's shape itself changes.
- **`.session-continuity/LEARNINGS.md`** — accumulated wisdom (numbered entries, grouped by layer). Append-only log of bugs that were painful enough to not want to rediscover. **Update when a bug takes 15+ minutes to diagnose.**

The four files are complementary: primer is volatile current-state, OUTSTANDING_ITEMS captures explicitly deferred work, PROJECT_CONTEXT is stable reference, LEARNINGS is durable wisdom. A fresh session reads the primer first to get oriented, skims PROJECT_CONTEXT once per session for the shape of the repo, consults OUTSTANDING_ITEMS for the decision backlog, then consults LEARNINGS when something surprising happens.

If installed as a plugin, six commands are available: `/session-continuity:primer` (init/split/refresh/check the primer), `/session-continuity:learning` (append a new LEARNINGS entry interactively), `/session-continuity:end-session` (close-out ritual — refresh the primer, capture any new learnings from this session, and report a ✓/⚠️ checklist before you close the laptop), `/session-continuity:spike-check` (force a spike to be designed against the real load-bearing path before it's built), `/session-continuity:doctor` (read-only diagnostic — is the install actually wired up: hooks registered, all four files present and not stale, plugin root resolved and not a stale cache, gate scripts executable), and `/session-continuity:update` (print the commands to pull and activate the plugin's latest published version).

`hooks/hooks.json` also wires up several non-blocking and blocking hooks
— a SessionStart reminder that injects the outstanding-items shortlist,
a non-blocking pre-commit nudge, a retrieval hook that surfaces relevant
LEARNINGS entries before you act, and six commit-time content gates
(`smoke-gate.sh`, `proven-gate.sh`, `occurrence-gate.sh`,
`evidence-gate.sh`, `flaky-gate.sh`, `backend-parity-gate.sh`) that block
a `git commit` staging a spec/plan/LEARNINGS claim missing its required
fields. Each has a skip-with-reason escape hatch. **See
[`REFERENCE.md`](REFERENCE.md) for what each hook/gate checks and the
exact escape-hatch syntax** — the one thing to know day-to-day is the
chaining trap below.

### Gate mechanics — never chain `git add` and `git commit` in one call

All six gates above are `PreToolUse` hooks matched on `Bash(git commit
*)` against the **whole command string** passed to the Bash tool. If
that string is `git add some/file.md && git commit -m "..."` and a
gate denies it, the entire tool call is denied — not just the commit.
The `git add` never ran either, silently, and it will not run on a
bare retry of the same chained command since the string still matches
the same gate. Stage and commit as two separate Bash calls whenever a
gate-relevant file (a spec, plan, or LEARNINGS entry) is involved:
`git add <file>` first, then a plain `git commit` with no `-a` and no
pathspec, as its own call. This is a consuming-project trap, not a
plugin-internal one — it bites any repo with these gates installed the
first time a chained add+commit gets denied.

## When to use this skill

Invoke when:

- Starting work on a project that does not yet have `.session-continuity/SESSION_PRIMER.md`, `.session-continuity/PROJECT_CONTEXT.md`, and `.session-continuity/LEARNINGS.md` — initialize from the templates.
- About to commit code changes — refresh the primer's "Current state" section and `.session-continuity/OUTSTANDING_ITEMS.md` so the next session sees the truth.
- A bug has just been resolved after significant effort (15+ min, or required reading unfamiliar code, or surprised you) — add a LEARNINGS entry.
- The user says something like "help me preserve session memory," "how do I hand this off to the next session," "create a primer," or "add this to learnings."
- Picking up work on a project that already has these files — read them as the first step, before touching anything else.

## Quick start (new project)

Run `/session-continuity:primer`. The command detects that no primer exists, copies all four templates from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/` into the project's `.session-continuity/`, fills in every placeholder it can derive automatically (project name, latest commits, working directory, test command), prompts the user for anything left blank, and stages all four files. It does not commit.

After the user commits, remind them of the two maintenance rules: refresh the primer alongside substantive commits (stage the refresh in the same commit as the real change — do not commit the primer by itself), and add a LEARNINGS entry for every bug that took 15+ minutes to diagnose.

If the `/session-continuity:primer` command is not installed (e.g. this skill was vendored manually, not installed as a plugin), fall back to copying the templates by hand from [`templates/SESSION_PRIMER.md`](templates/SESSION_PRIMER.md), [`templates/OUTSTANDING_ITEMS.md`](templates/OUTSTANDING_ITEMS.md), [`templates/PROJECT_CONTEXT.md`](templates/PROJECT_CONTEXT.md), and [`templates/LEARNINGS.md`](templates/LEARNINGS.md) into the project's `.session-continuity/`, filling placeholders, and committing the set.

## Quick start (existing project with these files)

1. Read `.session-continuity/SESSION_PRIMER.md` end-to-end. It is designed for this exact moment.
2. Read `.session-continuity/PROJECT_CONTEXT.md` once per session — it changes rarely, so a stale read is unlikely, but skim it if anything about the repo's shape surprises you.
3. Follow the primer's "First things first" list.
4. Before doing ANY work, verify claimed state is still current (the primer can be stale — run its test commands, check `git log`, etc.).
5. When you commit, update the primer.

## Quick start (existing primer, not yet split)

If a project has `.session-continuity/SESSION_PRIMER.md` but no
`.session-continuity/PROJECT_CONTEXT.md`, it predates the volatile/stable
split. Run `/session-continuity:primer` — it detects the unsplit shape and
partitions the content automatically (Split mode). Review the section
boundaries before committing.

## The maintenance rules (read this before every commit)

### On every substantive commit — refresh SESSION_PRIMER.md in the same commit

**Substantive** means a real code or docs change — anything you would
commit even if the primer didn't exist. For every such commit, stage
the primer refresh alongside the real diff so they land together.

Sections of the primer most likely to be stale:

- **Current state / latest commits.** Regenerate the `git log --oneline -5` block to include the commit you are about to make.
- **Test expectations.** If you added, removed, or skipped tests, bump the count so it matches `<test command>` output.

Other sections (layout, packages, conventions) drift more slowly but are fair game if the repo shifted.

Alongside the primer, also update the separate file
`.session-continuity/OUTSTANDING_ITEMS.md`: remove things you just
finished, add newly-flagged follow-ups from code review or user
feedback. **Before marking any item DONE, verify it against the actual
code** — one grep or read per load-bearing claim, not against memory
and not against a commit subject line alone. A commit whose subject
mentions an item's keywords does not prove the item shipped; a fix
landing inside an unrelated commit can leave an item reading OPEN when
it already shipped. Both directions are real drift.

**Numbering convention for OUTSTANDING_ITEMS.md — mirrors LEARNINGS.**
A new item takes the next unused number across the whole file. A closed
item is deleted outright, never renumbered, never reused — this keeps
cross-references ("see item 4") valid for as long as item 4 exists.
Before deleting, grep the repo for references to the item's number; a hit
means fix the reference or leave a one-line "closed" stub instead.

### Do NOT commit the primer by itself

A primer-only commit creates a self-referential chain: every primer
refresh becomes a commit that the primer itself needs to reflect,
inviting another primer-only commit, and so on. Treat the primer as
metadata that rides along with substantive commits. Exceptions — rare
but legitimate:

- A one-shot catch-up when the primer has drifted badly and no code
  change is imminent.
- Correcting factual errors (wrong test counts, wrong branch names)
  discovered during review.
- **Recording a completed tag + push + release, immediately after doing
  it.** This is not busywork — a new git ref exists and a release is
  published, a real dateable state change — and it happens on a
  predictable cadence (every ship), unlike the other two exceptions. Do
  this the moment `gh release view <tag>` confirms the release is live;
  don't defer it waiting for a "real" change to bundle it with. Update the
  bullet from "shipped"/"pending release" to "released" with the commit
  SHA, tag, and release URL. Deferring this is exactly how a primer ends
  up claiming "pending release" after the release has already shipped —
  the gap this exception exists to close.

All three should be marked clearly in the commit message as catch-up work.
If you find yourself making repeated primer-only commits, stop and
bundle the refresh with the next real change instead.

If you genuinely have nothing substantive to commit, that's fine —
but *check* the primer the next time you do commit, and include the
refresh in that same commit.

### On a hard-won bug — add to LEARNINGS.md

A bug qualifies when any of:

- Took more than 15 minutes to diagnose.
- Required reading code in an unfamiliar layer of the stack.
- Surprised you — the behavior did not match what the docs or the naming implied.
- Bit you twice (the second time is a sign the first didn't leave enough of a mark).

**Write entry as a recipe, not a journal.** Each entry should contain:

- **The trap.** What you tried that seemed reasonable but was wrong.
- **Symptom.** The observable behavior, including the misleading error messages.
- **Fix.** What actually works, with code or commands.
- **Diagnostic signal** *(optional but useful)*. How to recognize this bug next time — a log line, an exit code, a process pattern.

**Numbering convention.** New entries go at the **top** of the relevant section but take the **next available number** (N+1). Old entries keep their numbers. This keeps cross-entry back-references ("see #7 above") stable even as new entries arrive. The primer and other docs should cite learnings by number (`LEARNINGS.md §12`).

**Trigger lines (optional, action-keyed retrieval).** An entry may carry a single `Trigger: <tool> /<regex>/` line directly below its `### N.` heading. The `learnings-surface` hook matches the regex against the imminent action — the Bash command string, or a Write/Edit file path + content — and surfaces the entry *before* it runs. `<tool>` is `Bash`, `Write`, `Edit`, or `*` (any). Author triggers narrowly so they fire on the specific trap, not on incidental word overlap. Entries with no `Trigger:` line never fire — there is no cost to omitting it. This is the mechanism that turns LEARNINGS from a read-after-symptom file into a read-before-action gate.

**Grouping by layer.** Standard sections: Runtime (one per runtime — Bun, Node, Python, etc.), Shell / scripts, Process management, Security, <project-specific layers like HTTP, DB, UI>, Git / repo layout, Anti-patterns we were tempted by. Adapt to the project; do not force structure where it doesn't fit.

## More detail

For the full gate/hook reference, the "what goes where" decision tree,
customization guidance, team-wide rollout steps, red flags for when
*not* to use this skill, complementary mechanisms, and the philosophy
behind the four-file split, see [`REFERENCE.md`](REFERENCE.md).
