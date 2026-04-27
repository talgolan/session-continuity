# session-continuity

Cross-session memory for Claude Code projects. Two in-repo docs, two slash commands, two hooks.

## Install

```bash
claude plugins install github:talgolan/session-continuity
```

Once the plugin is live on the Anthropic marketplace, you can also discover it there. Until then, the command above works from any Claude Code install.

## What you get

- **`docs/SESSION_PRIMER.md`** — current-state snapshot. Refreshed alongside substantive commits. The fastest path for a fresh session to get productive.
- **`docs/LEARNINGS.md`** — append-only wisdom. Numbered entries for bugs that took 15+ minutes to diagnose. Graveyard of hard-won knowledge.
- **`/session-continuity:primer`** — init / refresh / check the primer. State-dispatching, never commits automatically.
- **`/session-continuity:learning`** — append a new LEARNINGS entry interactively. Computes the next number, inserts at the top of the chosen section.
- **`SessionStart` hook** — reminds Claude to read the primer on new sessions.
- **`PreToolUse` hook** — non-blocking nudge when `git commit` runs without the primer staged.
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

## Updating

```bash
/plugin update session-continuity
```

The weekly freshness check in `SessionStart` will nudge you when a new version ships. Opt out with `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`.

## Platform notes

Hooks are bash scripts and rely on `git` on PATH. On Windows, use Git Bash or WSL. Native PowerShell support is not included in v0.2.

## Contributing

Issues and PRs welcome at [github.com/talgolan/session-continuity](https://github.com/talgolan/session-continuity). Please keep the scope tight: this skill ships a two-file pattern, not a framework. PRs that fit the existing shape will move quickly; PRs that expand scope will be declined or redirected.

## License

MIT — see [LICENSE](LICENSE).
