# session-continuity

Cross-session memory for Claude Code projects. Two in-repo docs, three slash commands, two hooks.

## Why this exists

LLMs start every session cold. Claude doesn't remember yesterday's debugging, last week's refactor, or the three-hour bug you eventually cornered. The usual fixes reach for clever infrastructure — vector databases, MCP memory servers, auto-generated notes stored in vendor-specific ways that hide the knowledge outside the repo, away from human eyes and tangled with whichever tool happens to be installed.

This skill takes a different route: plain Markdown files, committed to git, alongside the code they describe. Two files hold the memory, three slash commands keep them honest, two hooks nudge when the habit slips. That's the whole system.

The choice buys three properties most AI memory systems lack. Humans and Claude read the same files, so there's no opaque layer between you and what's remembered. Every change is a git commit, so history is auditable and every edit has an author. The storage is plain text, so it's portable — any tool that reads Markdown can use it, including future LLMs that don't exist yet.

There's a second reason, less obvious than the first: **shorter Claude Code sessions are better sessions**. Less accumulated context means lower cost per turn, better accuracy, and — critically — less context rot. Retrieval accuracy at large context sizes varies sharply by model: Sonnet 4.6 degrades earliest, Opus 4.7 is substantially worse than its predecessor at 1M tokens (roughly 32% vs. 78% retrieval accuracy in our testing), and Opus 4.6 holds up best. The practical consequence is that a workflow which lets you end a session and start a fresh one without losing context is not just a nice-to-have — it's how you keep Claude sharp across a long-running project. That's what `docs/SESSION_PRIMER.md` and `docs/LEARNINGS.md` buy you: the ability to close the laptop at any point, come back cold, and have a new Claude session up to speed in two file reads instead of rebuilding context by re-prompting.

## Install

From inside Claude Code, add this repo as a plugin marketplace, then install the single plugin it hosts:

```
/plugin marketplace add talgolan/session-continuity
/plugin install session-continuity@session-continuity
```

Run `/reload-plugins` once the install finishes. Once the plugin is live on the official Anthropic marketplace (`claude-plugins-official`), you'll also be able to discover it via `/plugin` → **Discover**; until then, the two-step sequence above works on any recent Claude Code install.

## What you get

- **`docs/SESSION_PRIMER.md`** — current-state snapshot. Refreshed alongside substantive commits. The fastest path for a fresh session to get productive.
- **`docs/LEARNINGS.md`** — append-only wisdom. Numbered entries for bugs that took 15+ minutes to diagnose. Graveyard of hard-won knowledge.
- **`/session-continuity:primer`** — init / refresh / check the primer. State-dispatching, never commits automatically.
- **`/session-continuity:learning`** — append a new LEARNINGS entry interactively. Computes the next number, inserts at the top of the chosen section.
- **`/session-continuity:end-session`** — close-out ritual. Refreshes the primer, surfaces LEARNINGS candidates from this session's context, and reports a ✓ / ⚠️ checklist of staged / unstaged / untracked / unpushed state with a suggested commit message. Never commits.
- **`SessionStart` hook** — reminds Claude to read the primer on new sessions.
- **`PreToolUse` hook** — non-blocking nudge when `git commit` runs without the primer staged. Scoped via the hook's `if: Bash(git commit *)` field, so the script only fires on actual `git commit` calls and never on unrelated Bash commands.
- **Weekly freshness check** — one GitHub API call per 7 days per machine. Opt-out: `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`.

## Usage

**New project:**

```
/session-continuity:primer
```

Detects no primer exists, copies templates into `docs/`, fills derivable placeholders, asks you for the rest, stages both files.

**Before a commit:**

```
/session-continuity:primer
```

Detects drift, regenerates the `git log --oneline -5` block, prompts for outstanding-items updates, stages the refreshed primer. Commit it alongside your substantive change — **not in a primer-only commit**.

**After a painful bug (15+ min to diagnose):**

```
/session-continuity:learning
```

Prompts for trap / symptom / fix / diagnostic signal. Appends the entry at the top of the section you pick, with the next sequential number.

**Ending a work session:**

```
/session-continuity:end-session
```

Refreshes the primer, asks whether anything from today is worth a LEARNINGS entry (Claude looks at the session's conversation context to propose candidates), and prints a checklist so you know nothing is forgotten before you close the laptop. Stages changes — does not commit.

> **Scope note.** End-session's reflection is bounded by the *current* Claude session — it can only see what was said and done in this conversation. For LEARNINGS worth capturing from prior sessions (a bug you remember from yesterday, or one that lived in a different Claude instance like a subagent or parallel worktree), use `/session-continuity:learning` directly.

**Picking up an existing project:**

The `SessionStart` hook reminds Claude to read `docs/SESSION_PRIMER.md` first. Follow its "First things first" list before touching anything.

## What goes where

| Observation | Where |
|---|---|
| "The latest commit is X" | `docs/SESSION_PRIMER.md` → Current state |
| "We should refactor Y" | `docs/SESSION_PRIMER.md` → Outstanding items |
| "Bun replaces the CA trust store" | `docs/LEARNINGS.md` → new numbered entry |
| "Always use Bun" | `CLAUDE.md` (durable project convention) |
| "Last session tried X and rejected it" | `docs/LEARNINGS.md` → Anti-patterns |

**Do not put in these files:** secrets (ever — use `<redacted>`), information trivially rederivable from code, narrative fluff.

## Philosophy

Primer answers "what is true **right now**?" LEARNINGS answers "what should I know to avoid rediscovering pain?" Two files, two questions, one habit.

## Two files, two questions — why the split matters

Most memory systems lump everything together: notes, decisions, observations, bug reports, all blended in a searchable soup. That fails in a specific way for software projects, because current state and accumulated wisdom have opposite shapes.

The **primer** is high-churn. Yesterday's commit is already out of date; next week's priorities will look different again. It needs to be overwritten freely, refreshed with every substantive change, and short enough to re-read on every session start. A primer that accumulates forever becomes a scroll tomb.

**LEARNINGS** is the exact opposite. Each entry is a bug that took hours to diagnose, the kind of hard-won knowledge that would cost the same hours again if lost. It needs to be append-only, numbered stably so cross-references don't rot, and preserved exactly as written when the author's memory was sharpest. A LEARNINGS file that gets rewritten loses the point.

Blending them forces bad tradeoffs. Either the current-state notes drown the accumulated wisdom, or the wisdom gets edited away when someone trims "stale" entries. This skill keeps them in separate files with separate update contracts — the primer says "what is true right now," LEARNINGS says "what should I know to avoid rediscovering pain," and neither pretends to answer the other's question.

## What it is not

Understanding what this skill deliberately avoids is as useful as understanding what it does.

**Not automatic.** The slash commands require you to invoke them. The hooks nudge, they don't write files themselves. Automatic memory capture sounds appealing but has a predictable failure mode: noise, contradictions, and stale state that Claude confidently believes is current. A memory system is only useful if its contents can be trusted, and trust comes from deliberate capture.

**Not a framework.** There's no extension API, no plugin architecture, no abstraction layer waiting for you to subclass it. The surface is three commands and two hooks, and that's the whole product. PRs that expand the surface will be declined.

**Not a replacement for `CLAUDE.md`, vector search, or MCP memory servers.** Each of those solves a different problem. `CLAUDE.md` is for durable project conventions ("always use Bun, never commit to main"). Vector search is for semantic retrieval across large unstructured corpora. MCP memory servers are for cross-project or cross-session context that needs rich querying. This skill is for *the two specific questions above*, in *a single project's repo*, with *plain text in git* as the storage. When one of the other tools fits your need better, use it instead.

**Not an LLM-only tool.** Every file is human-readable and human-editable. You can open `docs/LEARNINGS.md` in any editor, add an entry by hand, and Claude will see it on the next session. The slash commands are conveniences, not gates.

## Updating

To pick up newer versions, refresh the marketplace and reload:

```
/plugin marketplace update session-continuity
/reload-plugins
```

The weekly freshness check in `SessionStart` will nudge you inside Claude when a new GitHub release ships. Opt out with `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`.

## Platform notes

Hooks are bash scripts and rely on `git` on PATH. On Windows, use Git Bash or WSL. Native PowerShell support is not planned.

## Contributing

Issues and PRs welcome at [github.com/talgolan/session-continuity](https://github.com/talgolan/session-continuity). See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide — scope policy, local development, authoring conventions for commands and hooks, and the release process. TL;DR: this skill ships a two-file pattern, not a framework. PRs that fit the existing shape will move quickly; PRs that expand scope will be declined or redirected.

## Privacy

See [PRIVACY.md](PRIVACY.md). Short version: nothing leaves your machine except one weekly, unauthenticated GitHub API call for version checks, which you can disable with `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`.

## License

MIT — see [LICENSE](LICENSE).
