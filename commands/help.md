---
description: Explain what this plugin does, why, and what each `.session-continuity/` file is for. Zero args, read-only, no state mutation.
---

# /session-continuity:help

You are responding to the `/session-continuity:help` slash command.

**Your job: answer "what is this plugin and why should I care" directly, without sending the user to read `SKILL.md` end to end.** Read-only — never edits, stages, or commits anything.

## Step 1 — Get the installed version

```bash
grep -m1 '"version"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null || echo "version unknown (vendored install)"
```

## Step 2 — Report

Print the following, substituting the parsed version into the first line. This is fixed reference text — do not re-derive it from `SKILL.md` per invocation, and do not omit any of the five files or any command.

```
session-continuity v<X.Y.Z>

WHAT THIS IS
Cross-session memory for Claude Code projects, via five in-repo Markdown
docs. A fresh Claude session (or a fresh terminal, or tomorrow) starts
cold — these files are how it gets caught up without you re-explaining
the project.

WHY
Claude doesn't remember yesterday's debugging, last week's refactor, or
the bug you spent three hours cornering. These files are a low-tech fix:
plain Markdown, committed to git alongside the code, readable by humans
and Claude alike. Every change is an auditable commit; no vendor-specific
storage, no opaque memory layer.

THE FIVE FILES
- SESSION_PRIMER.md    — volatile. Current state, latest commits. Refresh
                          alongside every substantive commit.
- PROJECT_CONTEXT.md   — stable. Repo layout, conventions, module table.
                          Changes rarely — only when the project's shape
                          changes.
- BACKLOG.md           — tactical. Explicitly deferred follow-ups and
                          decisions. Permanently numbered; closed items
                          are deleted, never renumbered.
- ROADMAP.md           — strategic. Now/Next/Later direction. Freeform,
                          no numbering, rewritten wholesale as direction
                          changes.
- LEARNINGS.md         — durable wisdom. Append-only, numbered. One entry
                          per bug that took 15+ minutes to diagnose.

COMMANDS
```

Then list every `/session-continuity:*` command by reading each file's own frontmatter `description` field — do not hand-copy descriptions into this command file, since that duplicates a source of truth that will drift. Gather them in one Bash call:

```bash
for f in "${CLAUDE_PLUGIN_ROOT}"/commands/*.md; do
  name="$(basename "$f" .md)"
  desc="$(grep -m1 '^description:' "$f" | sed -E 's/^description:[[:space:]]*//')"
  echo "/session-continuity:$name — $desc"
done
```

Render each line under the `COMMANDS` heading above, one per command, in the order the `for` loop produced them.

## Notes

- **Never mutates anything.** No file writes, no `git add`, no `chmod` — matches `/session-continuity:doctor`'s same rule.
- **Never invent a command description.** If a command file has no `description:` frontmatter line, print `(no description found)` for that line rather than guessing.
