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

If installed as a plugin, four commands are available: `/session-continuity:primer` (init/split/refresh/check the primer), `/session-continuity:learning` (append a new LEARNINGS entry interactively), `/session-continuity:end-session` (close-out ritual — refresh the primer, capture any new learnings from this session, and report a ✓/⚠️ checklist before you close the laptop), and `/session-continuity:spike-check` (force a spike to be designed against the real load-bearing path before it's built).

`hooks/hooks.json` also wires up several non-blocking and blocking hooks:

- **`session-start.sh`** (SessionStart) — reminds Claude to read the primer, and injects the outstanding-items shortlist. **Standing rule: whenever you discuss or echo outstanding items to the user — in this reminder, in `/session-continuity:end-session`'s prompts, or in free-form chat when directly asked — render them as a numbered list matching OUTSTANDING_ITEMS.md's own item numbers, always starting at 1, never 0.** Paraphrasing the list into unnumbered prose (e.g. "same question stand: X or Y") drops the numbering the user relies on to reply with a bare number. This applies even to a one-line summary reply — number it, don't collapse it, and don't zero-index it.
- **`pre-commit-check.sh`** (PreToolUse, before `git commit`) — non-blocking nudge when code is staged without a primer refresh.
- **`learnings-surface.sh`** (PreToolUse, before Bash/Write/Edit) — the retrieval hook: surfaces any LEARNINGS entry carrying a `Trigger: <tool> /<regex>/` line when the imminent action matches, so the lesson lands *before* the mistake instead of after.
The six content gates below all fire at **commit time**, not on save:
each one is a `PreToolUse` hook scoped to `Bash(git commit *)` that
scans the files already staged in the git index, not the `Write`/`Edit`
payload. Iterate on a spec/plan/LEARNINGS file freely — a `Write` or
`Edit` never gets blocked — and the gate only asks its question when
you run `git commit`, naming the offending staged file in its denial.
(`git commit -a` and pathspec commits are a documented, accepted
permissive miss — see CHANGELOG `[0.17.0]` and LEARNINGS.)

- **`smoke-gate.sh`** — blocks a staged plan file that touches binary/engine work but lacks a MANDATORY smoke task.
- **`proven-gate.sh`** — blocks a staged spec/plan's "proven"/"verified" claim unless it also names the real path exercised and what was stubbed.
- **`occurrence-gate.sh`** — blocks a staged LEARNINGS entry recording a 2nd-or-later occurrence of a mistake-class unless it also names the end-state invariant.
- **`evidence-gate.sh`** — blocks a staged spec/plan's smoke design if it tears down before capturing failure evidence, or polls for success only.
- **`flaky-gate.sh`** — blocks a commit message or staged LEARNINGS entry that calls a failure "flaky"/"transient" without naming the deterministic mechanism behind it.
- **`backend-parity-gate.sh`** — blocks a staged plan that frames its smoke coverage as multi-backend but names only one concrete backend.

Every blocking gate has an explicit skip-with-reason escape hatch (e.g.
`Smoke: N/A — <reason>`) documented in that hook's own header comment.
The escape line tolerates markdown decoration — `> **Smoke:** N/A —
<reason>` (blockquote, bold) works exactly like the bare
`Smoke: N/A — <reason>` form; only the `Label:`, `N/A`, and a dash then
a non-blank reason are required, wrapped in any combination of `>`,
`#`, `**`, or `` ` ``.

`proven-gate.sh` specifically: rather than escaping a real
"proven"/"verified" claim, prefer meeting its requirement directly —
add two fields next to the claim, `Real path: <which production code
path actually ran>` and `Stubbed: <what stood in, or "nothing">`. If
the stubbed thing is the feature under test, the claim isn't proven;
say so instead of asserting it.

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

## What goes where — a decision tree

| Observation | Where it goes |
|---|---|
| "The latest commit is X" | `.session-continuity/SESSION_PRIMER.md` → Current state |
| "We should follow up on X" | `.session-continuity/OUTSTANDING_ITEMS.md` → new numbered entry |
| "How is this repo laid out" | `.session-continuity/PROJECT_CONTEXT.md` → Repo layout |
| "What are our workflow conventions" | `.session-continuity/PROJECT_CONTEXT.md` → Workflow conventions |
| "Bun replaces the CA trust store" | `.session-continuity/LEARNINGS.md` → new numbered entry |
| "The CLI uses portless URLs" | `CLAUDE.md` (per-project config) |
| "User prefers Bun to Node" | `CLAUDE.md` (per-project) or user's global `~/.claude/CLAUDE.md` |
| "Last session tried approach X and rejected it" | `.session-continuity/LEARNINGS.md` → Anti-patterns section |
| "API keys leaked in transcript on date Y" | `.session-continuity/LEARNINGS.md` → Security section (names only, never values) |

**Do not put in these files:**

- Secrets. Ever. Even in "Fixed by changing `KEY=abc`" commentary — redact to `KEY=<redacted>`.
- Information that is trivially rederivable from the code (module layout, function signatures — the code itself is the source of truth).
- Narrative fluff ("We spent a long time on this and finally…"). Write recipes, not war stories.

## Customization guidance

Different projects have different shapes, but the core file pattern adapts well:

- **Test counts in the primer.** If you have one package, one line. If you have three packages (like SF_Tunnel: relay, tunnel, web), show three. If counts are unstable (integration tests that depend on external services), drop the exact count and document the green command instead.
- **"Workflow conventions" section.** Replace with whatever this project's disciplines are: commit message format, branch naming, code review process, required CI checks.
- **"Outstanding items" section.** Use your own taxonomy: "blocked", "deferred", "needs decision". Keep it actionable.
- **LEARNINGS section headings.** Replace "Bun", "SvelteKit", etc. with the actual layers of the project. Stack varies, structure is universal.

## For team-wide use

If multiple people are working on the same project and should all benefit from this:

1. All four files are **checked-in** artifacts, not gitignored. Commit them in the project repo under `.session-continuity/`.
2. Copy [`templates/CLAUDE_MD_SNIPPET.md`](templates/CLAUDE_MD_SNIPPET.md) into the project's `CLAUDE.md` verbatim. It covers the read-first pointer, the primer-refresh-alongside-commits rule, the outstanding-item verify-before-close rule, and the gate-chain-commit trap — the things a project otherwise has to rediscover and hand-write for itself (as architect-workbench did before this snippet existed).
3. Document the maintenance rules in the primer itself (last section). Templates include this.
4. Human teammates benefit too — LEARNINGS.md doubles as a living post-mortem log, and the primer is a great onboarding handoff.

## Red flags — when NOT to use

- **One-off scripts or throwaway repos.** Not worth the overhead.
- **Repos where the user explicitly prefers other memory mechanisms** (e.g., a heavily-used wiki, a confluence space). Don't duplicate.
- **Projects whose CLAUDE.md already does this** (some projects keep all session handoff in `CLAUDE.md`). Extend that approach instead of imposing a new structure.

## Complementary mechanisms

- **`CLAUDE.md`** covers "how to work in this repo" — durable, rarely changes. Primer covers "what's true right now" — changes per commit.
- **MemPalace / similar agent-memory systems** cover color that doesn't deserve a commit: user preferences, debugging narratives, session-level observations. Primer/LEARNINGS cover things the team should see.
- **Stop / pre-commit hooks** can enforce the "refresh the primer in the same commit as substantive changes" rule if drift becomes a problem. This skill does not install one — it relies on discipline. Add a hook only if you find yourself forgetting.

## Philosophy

The four files answer four different questions:

- Primer: "What is true about this project **right now**?"
- OUTSTANDING_ITEMS: "What has been **explicitly deferred** (decisions, follow-ups, follow-ons) that we should not forget?"
- PROJECT_CONTEXT: "What is true about this project **generally**, and rarely changes?"
- LEARNINGS: "What should I know to avoid rediscovering something painful?"

Together they compress the cost of session handoff from "re-explain everything" to "read a couple of files." The primer stays short (a shortlist, not a snapshot); OUTSTANDING_ITEMS accumulates deferred work; PROJECT_CONTEXT and LEARNINGS both grow organically but at different rates — one when the project's shape changes, the other with every hard-won bug. All four outlive any single session.
