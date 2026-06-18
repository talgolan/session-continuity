# session-continuity

Cross-session memory for Claude Code projects. A skill Claude loads on its own, two plain-Markdown docs committed to your repo, three slash commands, and a set of session hooks that surface the right knowledge at the right moment.

## Why this exists

LLMs start every session cold. Claude doesn't remember yesterday's debugging, last week's refactor, or the three-hour bug you eventually cornered. The usual fixes reach for clever infrastructure: vector databases, MCP memory servers, auto-generated notes stored in vendor-specific ways that hide the knowledge outside the repo, away from human eyes and tangled with whichever tool happens to be installed.

This plugin takes a different route: plain Markdown files, committed to git, alongside the code they describe. Two files hold the memory, three slash commands keep them honest, and a handful of hooks nudge or gate when the habit slips. That's the whole system.

The choice buys three properties most AI memory systems lack. Humans and Claude read the same files, so there's no opaque layer between you and what's remembered. Every change is a git commit, so history is auditable and every edit has an author. The storage is plain text, so it's portable: any tool that reads Markdown can use it, including future LLMs that don't exist yet.

There's a second reason, less obvious than the first: **shorter Claude Code sessions are better sessions**. Less accumulated context means lower cost per turn, better accuracy, and less context rot. Retrieval accuracy at large context sizes varies sharply by model, and every model degrades as the window fills. A workflow that lets you end a session and start a fresh one without losing context isn't just convenient; it's how you keep Claude sharp across a long-running project. That's what `.session-continuity/SESSION_PRIMER.md` and `.session-continuity/LEARNINGS.md` buy you: the ability to close the laptop at any point, come back cold, and have a new session up to speed in two file reads instead of rebuilding context by re-prompting.

## What's in the box

| Component | What it does |
|---|---|
| **`session-continuity` skill** | Claude loads it automatically based on the task. It teaches Claude the two-file pattern, the maintenance rules, and the decision tree for what belongs where, even before you run any command. |
| **`.session-continuity/SESSION_PRIMER.md`** | The current-state snapshot. What's true about the project right now. |
| **`.session-continuity/LEARNINGS.md`** | Append-only wisdom. A numbered graveyard of bugs that were painful enough to never want to rediscover. |
| **`/session-continuity:primer`** | Init, refresh, or check the primer. State-dispatching. |
| **`/session-continuity:learning`** | Append a new LEARNINGS entry interactively, with stable numbering. |
| **`/session-continuity:end-session`** | Close-out ritual: refresh the primer, mine this session for new learnings, and print a state checklist. |
| **`/session-continuity:spike-check`** | Emit the stand-in spike checklist before a spike, so it's designed to hit the real binary + auth/lifecycle/fixed-port path. |
| **Session hooks** | A SessionStart reminder, a non-blocking commit nudge, an action-keyed retrieval gate, a smoke-task gate for plan files, a proven-claim gate for specs/plans, an occurrence-counter gate for LEARNINGS, and a weekly freshness check. |

Nothing here writes a file behind your back. Commands stage, they never commit. Hooks remind or gate, they never edit your files.

## Install

From inside Claude Code, add this repo as a plugin marketplace, then install the single plugin it hosts:

```
/plugin marketplace add talgolan/session-continuity
/plugin install session-continuity@session-continuity
```

Run `/reload-plugins` once the install finishes. Once the plugin is live on the official Anthropic marketplace (`claude-plugins-official`), you'll also be able to discover it via `/plugin` → **Discover**; until then, the two-step sequence above works on any recent Claude Code install.

## The two files

Everything else is machinery around these two documents. They have opposite shapes on purpose.

**`.session-continuity/SESSION_PRIMER.md`** is the high-churn current-state snapshot: latest commits, outstanding items, test counts, working directory, workflow conventions. It's the fastest path for a fresh session to get productive. Refresh it alongside substantive commits so it always reflects what's true right now. It's meant to be overwritten freely and short enough to re-read on every session start.

**`.session-continuity/LEARNINGS.md`** is the opposite: append-only, numbered, preserved. Each entry is a bug that took 15+ minutes to diagnose, written as a recipe (the trap, the symptom, the fix, an optional diagnostic signal). Numbers are stable so cross-references never rot. New entries go to the top of their section but take the next available number.

Both files ship as templates, so you start from a real structure instead of a blank page.

## The commands

### `/session-continuity:primer`

One command, five behaviors, dispatched on the repo's current state:

- **No primer yet** → copies the templates into `.session-continuity/`, fills every placeholder it can derive (project name, latest commits, working directory, test command), asks you for the rest, and stages both files. Any field you skip becomes `TBD` rather than a leftover `{{PLACEHOLDER}}`.
- **Primer exists but drifted** → regenerates the `git log --oneline -5` block, re-runs the primer's test commands (retrying flaky suites up to three times so a single bad sample doesn't cry wolf), surfaces every commit since the last refresh as a candidate, and prompts you for outstanding-items changes before staging.
- **Primer current** → reports a four-line status (HEAD, last refresh, outstanding-item count, learnings count) and exits without touching anything.

Drift is detected by diffing the stored `git log` block against reality, not by file mtime, because formatters and save-on-blur bump mtime without changing content.

### `/session-continuity:learning`

Appends a properly formatted entry. It prompts for the recipe fields, lets you pick or create a section, and computes the next number by taking the true maximum across all existing entries (not "one after the most recent," which breaks when an old entry was edited last). Before writing, it scans for duplicate numbers and refuses to append on top of a corrupt file. Entries can carry an optional `Trigger:` line that makes them fire before a matching action later (see hooks below).

### `/session-continuity:end-session`

The close-out ritual, bounded to at most two prompts in the common case:

1. **Refresh the primer**, but only if it actually drifted. If the `git log` block already matches reality, this step is a silent no-op.
2. **Mine the session for learnings.** It reads the session transcript (falling back to the live context window when the transcript isn't reachable) and runs four deterministic detectors: a *retry burst* (the same command run three or more times), a *revert/reset* (hard reset, checkout, revert, or `rm -rf` on a tracked file), an *error recurrence* (the same normalized error three or more times across 15+ minutes), and a *fix burst* (a `fix:` commit preceded by a long investigation). Candidates are pre-drafted into full LEARNINGS entries and presented in one batch for a single confirm.
3. **Print a state checklist.** Staged, unstaged, untracked, and unpushed are each enumerated file by file, with a suggested commit message and a terminal sign-off so you know the ritual is done.

It never commits and never pushes. The checklist flags what's outstanding; you decide.

### `/session-continuity:spike-check`

Emits a five-question stand-in checklist *before* a spike is built, so the spike is designed to exercise the real binary and the real auth/lifecycle/fixed-port path rather than a hand-rolled stand-in that passes cleanly and proves nothing. It is the proactive complement to the proven gate: answers 2 and 5 become the `Real path:` and `Stubbed:` fields the proven gate requires at claim-time. Pass an optional one-line spike description to frame each question.

## The hooks

The hooks are bash scripts wired through `hooks/hooks.json`. They split into two philosophies.

**React after the fact:**

- **SessionStart reminder** points a fresh session at the primer before it touches anything, and prints a quick freshness status line.
- **Commit nudge** (`PreToolUse`, scoped to `Bash(git commit *)`) fires only on real `git commit` calls. If code is staged but the primer isn't, it injects a non-blocking reminder to consider refreshing the primer in the same commit.

**Fire before the action:**

- **Action-keyed retrieval** (`learnings-surface`, `PreToolUse` on Bash/Write/Edit) is the mechanism that turns LEARNINGS from a read-after-symptom file into a read-before-action gate. When a LEARNINGS entry carries a `Trigger: <tool> /<regex>/` line and the command you're about to run (or the file you're about to write) matches that regex, the hook names the relevant entry so you read it *before* repeating the mistake. Entries without a trigger never fire, so there's zero cost to omitting one.
- **Smoke gate** (`smoke-gate`, `PreToolUse` on Write/Edit, plan files only) blocks writing a plan that touches binary/engine/container work but marks its smoke task optional or omits it entirely. Override with an explicit `Smoke: N/A — <reason>` line. It enforces mechanically what a passive note kept failing to enforce.
- **Proven gate** (`proven-gate`, `PreToolUse` on Write/Edit, spec/plan files only) blocks writing a spec or plan that makes a "proven / verified / spike conclusive" claim unless the same content carries `Real path:` + `Stubbed:` fields naming what actually ran versus what was a stand-in. Claim-words match on word boundaries (`unproven`/`improven`/`confirmed` do not trigger). Override with `Proven-gate: N/A — <reason>` for quoting, a glossary, or a doc about the gate.
- **Occurrence gate** (`occurrence-gate`, `PreToolUse` on Write/Edit, `LEARNINGS.md` only) blocks a LEARNINGS entry that records the 2nd-or-later occurrence of a mistake-class (`Occurrence count: N of M`, N ≥ 2) unless the same content names an end-state `Invariant:` line — the thing that, enforced at the reconciler/entry gate, makes the whole class impossible rather than patching one more trigger. A first occurrence (or no count) never fires. Override with `Occurrence-gate: N/A — <reason>`.

**Stay fresh:**

- **Weekly version check** makes one unauthenticated GitHub API call per machine per seven days and nudges you inside Claude when a new release ships. Opt out with `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`.

## Usage

**New project:**

```
/session-continuity:primer
```

Detects no primer exists, copies templates into `.session-continuity/`, fills derivable placeholders, asks you for the rest, and stages both files.

**Before a commit:**

```
/session-continuity:primer
```

Detects drift, regenerates the `git log` block, prompts for outstanding-items updates, and stages the refreshed primer. Commit it alongside your substantive change, not in a primer-only commit.

**After a painful bug (15+ min to diagnose):**

```
/session-continuity:learning
```

Prompts for trap, symptom, fix, and diagnostic signal. Appends the entry at the top of the section you pick with the next sequential number.

**Ending a work session:**

```
/session-continuity:end-session
```

Refreshes the primer, proposes LEARNINGS candidates drawn from this session, and prints a checklist so nothing is forgotten before you close the laptop. Stages changes; does not commit.

> **Scope note.** End-session's reflection sees only the *current* session. For a bug you remember from yesterday or one that lived in a different Claude instance (a subagent or parallel worktree), use `/session-continuity:learning` directly.

**Picking up an existing project:**

The SessionStart hook reminds Claude to read `.session-continuity/SESSION_PRIMER.md` first. Follow its "First things first" list before touching anything.

## What goes where

| Observation | Where |
|---|---|
| "The latest commit is X" | `.session-continuity/SESSION_PRIMER.md` → Current state |
| "We should refactor Y" | `.session-continuity/SESSION_PRIMER.md` → Outstanding items |
| "Bun replaces the CA trust store" | `.session-continuity/LEARNINGS.md` → new numbered entry |
| "Always use Bun" | `CLAUDE.md` (durable project convention) |
| "Last session tried X and rejected it" | `.session-continuity/LEARNINGS.md` → Anti-patterns |

**Do not put in these files:** secrets (ever — use `<redacted>`), information trivially rederivable from code, narrative fluff.

## Why two files

Most memory systems lump everything together: notes, decisions, observations, bug reports, all blended in a searchable soup. That fails in a specific way for software projects, because current state and accumulated wisdom have opposite shapes.

The **primer** is high-churn. Yesterday's commit is already out of date; next week's priorities will look different again. It needs to be overwritten freely, refreshed with every substantive change, and short enough to re-read on every session start. A primer that accumulates forever becomes a scroll tomb.

**LEARNINGS** is the exact opposite. Each entry is hard-won knowledge that would cost the same hours again if lost. It needs to be append-only, numbered stably so cross-references don't rot, and preserved exactly as written when the author's memory was sharpest. A LEARNINGS file that gets rewritten loses the point.

Blending them forces bad tradeoffs. Either the current-state notes drown the accumulated wisdom, or the wisdom gets edited away when someone trims "stale" entries. Keeping them in separate files with separate update contracts means the primer answers "what is true right now" and LEARNINGS answers "what should I know to avoid rediscovering pain," and neither pretends to answer the other's question.

## What it is not

Understanding what this plugin deliberately avoids is as useful as understanding what it does.

**Not automatic.** The slash commands require you to invoke them. The hooks nudge or gate; they don't write files themselves. Automatic memory capture sounds appealing but has a predictable failure mode: noise, contradictions, and stale state that Claude confidently believes is current. A memory system is only useful if its contents can be trusted, and trust comes from deliberate capture.

**Not a framework.** There's no extension API, no plugin architecture, no abstraction layer waiting for you to subclass it. The surface is one skill, three commands, and a handful of hooks, and that's the whole product. PRs that expand the surface will be declined.

**Not a replacement for `CLAUDE.md`, vector search, or MCP memory servers.** Each solves a different problem. `CLAUDE.md` is for durable project conventions ("always use Bun, never commit to main"). Vector search is for semantic retrieval across large unstructured corpora. MCP memory servers are for cross-project context that needs rich querying. This plugin is for *the two specific questions above*, in *a single project's repo*, with *plain text in git* as the storage. When one of the other tools fits your need better, use it instead.

**Not an LLM-only tool.** Every file is human-readable and human-editable. You can open `.session-continuity/LEARNINGS.md` in any editor, add an entry by hand, and Claude will see it on the next session. The slash commands are conveniences, not gates.

## Team-wide use

Both files are checked-in artifacts, not gitignored. Commit them under `.session-continuity/` and the whole team benefits:

- Add a line to the project's `CLAUDE.md` pointing every session at the primer and the maintenance rules.
- LEARNINGS doubles as a living post-mortem log for human teammates, not just Claude.
- The primer is a ready-made onboarding handoff for anyone joining the project.

## Platform notes

Hooks are bash scripts and rely on `git` on PATH. On Windows, use Git Bash or WSL. Native PowerShell support is not planned.

## Updating

To pick up newer versions, refresh the marketplace and reload:

```
/plugin marketplace update session-continuity
/reload-plugins
```

The weekly freshness check in SessionStart will nudge you inside Claude when a new GitHub release ships. Opt out with `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`.

## Contributing

Issues and PRs welcome at [github.com/talgolan/session-continuity](https://github.com/talgolan/session-continuity). See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide: scope policy, local development, authoring conventions for commands and hooks, and the release process. TL;DR: this plugin ships a two-file pattern, not a framework. PRs that fit the existing shape will move quickly; PRs that expand scope will be declined or redirected.

## Privacy

See [PRIVACY.md](PRIVACY.md). Short version: nothing leaves your machine except one weekly, unauthenticated GitHub API call for version checks, which you can disable with `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`.

## License

MIT — see [LICENSE](LICENSE).
