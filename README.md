# session-continuity

A Claude Code skill that establishes and maintains cross-session memory
for a software project via two in-repo documents:

- **`docs/SESSION_PRIMER.md`** — current-state snapshot. Refreshed on
  every commit so the next Claude session sees the truth immediately.
- **`docs/LEARNINGS.md`** — accumulated wisdom. Append-only log of bugs
  that took 15+ minutes to diagnose, written as recipes so nobody has
  to rediscover them.

## Why

Claude sessions are stateless. A session that solved a painful bug
ends, and the next session starts fresh. Without deliberate handoff,
the next session retraces the same dead ends. This skill encodes a
lightweight, committed, version-controlled handoff format that:

- **Travels with the repo** (unlike memory systems keyed by client).
- **Benefits humans too** (teammates onboarding, post-mortem history).
- **Compounds over time** (LEARNINGS grows; each bug is paid for once).
- **Does not require infrastructure** (no extra services, hooks, or
  APIs — just two Markdown files and a maintenance habit).

## Installation

### Option 1 — personal use (user-level skill)

```bash
# From this directory:
mkdir -p ~/.claude/skills/
cp -R session-continuity ~/.claude/skills/
```

Next Claude Code session will see it.

### Option 2 — team / plugin distribution (Claude Code plugin)

The repo is already plugin-manifest-ready. To publish as a Claude Code
plugin, restructure so the skill lives under `skills/<name>/`:

```
session-continuity/
├── .claude-plugin/
│   └── plugin.json        (already present)
├── LICENSE                (already present)
├── README.md              (already present)
└── skills/
    └── session-continuity/
        ├── SKILL.md
        └── templates/
            ├── SESSION_PRIMER.md
            └── LEARNINGS.md
```

Concretely from this directory:

```bash
mkdir -p skills/session-continuity
git mv SKILL.md templates skills/session-continuity/
git add .claude-plugin LICENSE README.md skills
git commit -m "Prepare for plugin distribution"
```

Publish the resulting repo as the plugin source (marketplace entry or
direct install). Installers run `claude plugins install <repo>` and
the skill becomes available under the plugin's namespace
(`session-continuity:session-continuity`).

The current layout (skill at top level) works as a user-level install
(`~/.claude/skills/session-continuity/`) but will not register as a
plugin until restructured as above.

## Usage

Say any of:

- "Create a session primer for this project"
- "Add this bug to LEARNINGS"
- "I'm about to commit — update the primer"
- "/session-continuity" (if surfaced as a slash command)
- "Help me preserve session memory"

Or invoke the skill explicitly when starting work on an unfamiliar
project — the skill's body tells Claude to read `docs/SESSION_PRIMER.md`
first and orient from there.

## What the skill contains

| File | Purpose |
|---|---|
| `SKILL.md` | The skill definition Claude loads. Explains when to use, maintenance rules, customization guidance, and the decision tree for "what goes where". |
| `templates/SESSION_PRIMER.md` | Starter template with `{{PLACEHOLDERS}}` for project-specific content. Copy into `docs/` of any project and fill in. |
| `templates/LEARNINGS.md` | Starter template for the learnings log. Standard section scaffolding + the numbering convention. |
| `README.md` | This file — for humans evaluating whether to install the skill. |

## Maintenance rules the skill enforces

1. **Every commit** → refresh `docs/SESSION_PRIMER.md`:
   - Latest commits block (regenerate `git log --oneline -5`).
   - Outstanding items (remove finished, add newly-flagged).
   - Test counts (bump to match actual `<test command>` output).
2. **Every hard-won bug** → append to `docs/LEARNINGS.md`:
   - The trap, the symptom, the fix, the diagnostic signal.
   - New entries go at the top of their section but take the next
     available number so back-references stay valid.

The rules live inside the templates too — even a fresh Claude that
doesn't load this skill will see them in the project.

## Complementary pieces

- **`CLAUDE.md`** covers durable project conventions ("use Bun",
  "never commit .env"). Primer covers volatile current state.
- **Agent memory systems** (MemPalace, etc.) cover color that doesn't
  deserve a commit — user preferences, debugging narratives. Primer
  and LEARNINGS cover things the team should see.
- **Stop hooks** can enforce the "update primer on every commit" rule
  programmatically. This skill relies on discipline; add a hook only
  if drift becomes a problem.

## Philosophy

Primer answers "what is true **right now**?"
LEARNINGS answers "what should I know to avoid rediscovering pain?"

Two files, two questions, one habit: update the right one at the right
moment. That is all this skill is.

## License

Choose a license appropriate to your distribution channel before
sharing. Suggested: MIT, matching most skill-ecosystem defaults.
