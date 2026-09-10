---
name: session-continuity
description: Establish and maintain cross-session memory for a project via four in-repo docs — .session-continuity/SESSION_PRIMER.md (current state, refreshed alongside substantive commits), .session-continuity/ROADMAP.md (strategic direction), .session-continuity/PROJECT_CONTEXT.md (stable repo context, changes rarely), and .session-continuity/LEARNINGS.md (append-only wisdom for 15+ min bugs) — plus GitHub Issues labeled backlog for the work queue. Use when starting, before commits, or after hard-won bugs.
---

# Session Continuity

Four in-repo files plus GitHub Issues act as a handoff between Claude sessions on the same project:

- **`.session-continuity/SESSION_PRIMER.md`** — thin hard-template snapshot (Boot order, Mid-flight, Confirm, Peers). **Refresh Mid-flight + Confirm alongside substantive commits** (stage the update in the same commit as the real change). Never embed a `git log` dump — freshness is `primer-freshness.sh`.
- **GitHub Issues labeled `backlog`** — explicitly deferred follow-ups and decisions (not current state). Identity is `#N`. Title + 1-3 sentence length cap per issue — anything longer moves to a linked file under `meta/superpowers/`. Close with `gh issue close N --reason completed` once the code shows it shipped.
- **`.session-continuity/ROADMAP.md`** — strategic direction: Now/Next/Later. Freeform — no numbering, no permanence rules, no length cap. Rewritten wholesale as direction changes.
- **`.session-continuity/PROJECT_CONTEXT.md`** — stable repo context (layout, module table, workflow conventions, test expectations, "where to look for what"). Changes rarely — only when the project's shape itself changes.
- **`.session-continuity/LEARNINGS.md`** — accumulated wisdom (numbered entries, grouped by layer). Append-only log of bugs that were painful enough to not want to rediscover. **Update when a bug takes 15+ minutes to diagnose.**

These are complementary: primer is volatile current-state, GitHub Issues capture explicitly deferred work, ROADMAP captures strategic direction, PROJECT_CONTEXT is stable reference, LEARNINGS is durable wisdom. A fresh session reads the primer first to get oriented, skims PROJECT_CONTEXT once per session for the shape of the repo, consults `/session-continuity:backlog` for the decision queue, then consults LEARNINGS when something surprising happens.

If installed as a plugin, nine commands are available: `/session-continuity:primer` (init/split/refresh/check the primer), `/session-continuity:learning` (append a new LEARNINGS entry interactively), `/session-continuity:end-session` (close-out ritual — refresh the primer, capture any new learnings from this session, and report a ✓/⚠️ checklist before you close the laptop), `/session-continuity:spike-check` (force a spike to be designed against the real load-bearing path before it's built), `/session-continuity:doctor` (read-only diagnostic — is the install actually wired up: hooks registered, four files present and not stale, GitHub backlog reachable, plugin root resolved and not a stale cache, gate scripts executable — zero-turn via `doctor-report.sh` when the hook fires), `/session-continuity:backlog` (render open GitHub Issues labeled `backlog` — zero-turn when the hook fires, one model call as fallback), `/session-continuity:learnings` (render LEARNINGS.md's entries — zero-turn when the hook fires, one model call as fallback), `/session-continuity:update` (print the commands to pull and activate the plugin's latest published version), and `/session-continuity:help` (explain what the plugin does and what each file is for).

`hooks/hooks.json` also wires up several non-blocking and blocking hooks
— a SessionStart reminder that injects the backlog shortlist and peer/
freshness status, a non-blocking pre-commit nudge, a retrieval hook that
surfaces relevant LEARNINGS entries before you act, and seven commit-time
content gates (`smoke-gate.sh`, `proven-gate.sh`, `occurrence-gate.sh`,
`evidence-gate.sh`, `flaky-gate.sh`, `backend-parity-gate.sh`,
`derived-value-gate.sh`) that block a `git commit` staging a
spec/plan/LEARNINGS/commands claim missing its required fields. Each has
a skip-with-reason escape hatch. **See [`REFERENCE.md`](REFERENCE.md) for
what each hook/gate checks and the exact escape-hatch syntax** — the one
thing to know day-to-day is the chaining trap below.

### Gate mechanics — never chain `git add` and `git commit` in one call

All seven gates above are `PreToolUse` hooks matched on `Bash(git commit
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
- About to commit code changes — refresh the primer's Mid-flight + Confirm sections and close or file GitHub Issues labeled `backlog` so the next session sees the truth.
- A bug has just been resolved after significant effort (15+ min, or required reading unfamiliar code, or surprised you) — add a LEARNINGS entry.
- The user says something like "help me preserve session memory," "how do I hand this off to the next session," "create a primer," or "add this to learnings."
- Picking up work on a project that already has these files — read them as the first step, before touching anything else.

## Quick start (new project)

Run `/session-continuity:primer`. The command detects that no primer exists, copies four templates from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/` into the project's `.session-continuity/`, fills in every placeholder it can derive automatically (project name, working directory, test command summary, and related fields via `primer-init-derive.sh`), prompts for Mid-flight bullets and Confirm commands, files any named follow-ups as GitHub Issues labeled `backlog` when `gh` is authenticated for the origin's host (github.com or a GitHub Enterprise Server instance), and stages all four files. It does not commit.

After the user commits, remind them of the two maintenance rules: refresh the primer alongside substantive commits (stage the refresh in the same commit as the real change — do not commit the primer by itself), and add a LEARNINGS entry for every bug that took 15+ minutes to diagnose.

If the `/session-continuity:primer` command is not installed (e.g. this skill was vendored manually, not installed as a plugin), fall back to copying the templates by hand from [`templates/SESSION_PRIMER.md`](templates/SESSION_PRIMER.md), [`templates/ROADMAP.md`](templates/ROADMAP.md), [`templates/PROJECT_CONTEXT.md`](templates/PROJECT_CONTEXT.md), and [`templates/LEARNINGS.md`](templates/LEARNINGS.md) into the project's `.session-continuity/`, filling placeholders, and committing the set. File the backlog as GitHub Issues labeled `backlog`.

## Quick start (existing project with these files)

1. Read `.session-continuity/SESSION_PRIMER.md` end-to-end. It is designed for this exact moment.
2. Read `.session-continuity/PROJECT_CONTEXT.md` once per session — it changes rarely, so a stale read is unlikely, but skim it if anything about the repo's shape surprises you.
3. Follow the primer's **Boot order** (and hard-stop if peers are incomplete).
4. Before doing ANY work, verify claimed state is still current (the primer can be stale — run Confirm commands, check `primer-freshness.sh` / peers, etc.).
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

Refresh **Mid-flight** and **Confirm** only (thin hard-template). Do
**not** embed or regenerate a `git log` dump — that shape is banlisted;
freshness is `primer-freshness.sh`, peers are `peer-probes.sh`. Keep
Mid-flight ≤5 bullets and Confirm ≤5 counted commands, then run
`primer-validate.sh` before staging.

Stable material (layout, packages, conventions) lives in
`PROJECT_CONTEXT.md` and drifts slowly — touch it only when the repo
shape actually changed.

Alongside the primer, also update the GitHub backlog: close issues you just
finished (`gh issue close N --reason completed`), file newly-flagged
follow-ups (`gh issue create --label backlog --title "..." --body "..."`).
**Before closing any issue, check it against the actual
code** — one grep or read per load-bearing claim, not against memory
and not against a commit subject line alone. A commit whose subject
mentions an issue's keywords does not mean the item shipped; a fix
landing inside an unrelated commit can leave an issue open when
it already shipped. Both directions are real drift.

**Identity convention for the backlog — differs from LEARNINGS.**
Each item is GitHub issue `#N`. Cross-references ("see #12") use that
number. When naming an item to the user, show `#N` plus the title, e.g.
`#12 Submit to the Anthropic marketplace`. (LEARNINGS.md keeps its own
separate, permanent, gapless numbering — unaffected by this.)

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
behind the four-file-plus-GitHub-Issues split, see [`REFERENCE.md`](REFERENCE.md).
