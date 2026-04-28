# Contributing to session-continuity

Thanks for thinking about contributing. This is a small, opinionated project with a tight scope, so reading this file before starting work will save both of us time.

## Scope first

This skill ships a specific pattern: two in-repo Markdown files (`docs/SESSION_PRIMER.md` and `docs/LEARNINGS.md`) with slash commands and hooks that make the habit of using them cheap. That's the whole scope.

**PRs that fit the existing shape move quickly.** Bug fixes, prose improvements to existing commands, small behavior refinements that sharpen the existing tools — all welcome.

**PRs that expand scope will be declined or redirected.** Examples of scope expansion:
- A third in-repo doc (e.g. `docs/DECISIONS.md`, `docs/ROADMAP.md`). The two-file split is load-bearing; see the README's "Two files, two questions" section.
- Integration with a specific memory server, vector database, or external storage. The point is plain files in git.
- A plugin architecture, extension API, or configuration system. The slash commands and hooks are the interface.
- Auto-commit, auto-push, or "just do it all for me" modes. Deliberate capture is a design choice, not an oversight.

If you're unsure whether your idea fits, open an issue first and describe what you want to build and why. That's cheaper than writing code we then have to decline.

## Before you start

1. Read the [README](README.md) for the user-facing view.
2. Read `docs/SESSION_PRIMER.md` — it's the current-state snapshot for this very repo, maintained by the plugin's own commands.
3. Skim `docs/LEARNINGS.md` — real bugs we've hit, grouped by layer. Useful context for hook/command work.
4. Skim the most recent spec + plan in `docs/superpowers/` to see how changes are shaped before they become code.

## Local development

### Prerequisites

- Claude Code CLI installed (`claude --version` should work).
- `git`, `bash`, and standard Unix tools on PATH. `jq` and `python3` are useful for JSON validation but not required.
- An editor that handles Markdown cleanly.

### Clone and install locally

```bash
git clone https://github.com/talgolan/session-continuity
cd session-continuity
```

There's no build step, no dependencies to install. Everything is Markdown, shell, and JSON.

### Run the plugin against a scratch repo

The `--plugin-dir` flag loads the plugin from your working copy without going through `claude plugins install`, so you can iterate fast:

```bash
mkdir -p /tmp/sc-dev
cd /tmp/sc-dev
git init -b main
echo "# dev test" > README.md
git add README.md
git commit -m "init"
claude --plugin-dir /Users/YOU/path/to/session-continuity
```

Inside Claude, exercise the slash commands (`/session-continuity:primer`, `/session-continuity:learning`, `/session-continuity:end-session`) and check that the hooks fire when expected.

### Hook smoke tests

Hooks can be exercised without Claude by piping the right JSON to stdin:

```bash
# SessionStart hook — expects cwd in stdin JSON
printf '{"cwd":"/tmp/sc-dev"}' | \
  SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1 \
  bash hooks/session-start.sh

# PreToolUse hook — expects cwd + tool_input.command in stdin JSON
printf '{"tool_input":{"command":"git commit -m test"},"cwd":"/tmp/sc-dev"}' | \
  bash hooks/pre-commit-check.sh
```

Hook output validates as JSON (for `pre-commit-check.sh`) or plain text (for `session-start.sh`). See the existing scripts for the expected shape.

## Project structure

```
session-continuity/
├── .claude-plugin/
│   └── plugin.json              # manifest — name, version, keywords
├── skills/
│   └── session-continuity/
│       ├── SKILL.md             # main skill description (shown in marketplace)
│       └── templates/
│           ├── SESSION_PRIMER.md
│           └── LEARNINGS.md
├── commands/
│   ├── primer.md                # /session-continuity:primer
│   ├── learning.md              # /session-continuity:learning
│   └── end-session.md           # /session-continuity:end-session
├── hooks/
│   ├── hooks.json               # hook registration
│   ├── session-start.sh         # SessionStart event
│   ├── pre-commit-check.sh      # PreToolUse event (Bash matcher)
│   └── version-check.sh         # weekly freshness check (invoked by session-start.sh)
├── docs/
│   ├── SESSION_PRIMER.md        # this repo's own primer (yes, we dogfood)
│   ├── LEARNINGS.md             # this repo's own LEARNINGS
│   ├── administrative/          # meta-docs (submission forms, contributor notes)
│   └── superpowers/
│       ├── specs/               # design docs (one per feature)
│       └── plans/               # implementation plans (one per feature)
├── .github/workflows/
│   └── release.yml              # tag-triggered GitHub Release
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md              # you are here
└── LICENSE
```

Files that change together live together. If you're adding a new slash command, you'll likely touch `commands/<name>.md`, the "three commands" paragraph in `skills/session-continuity/SKILL.md`, `README.md`, and `CHANGELOG.md`. If you're modifying a hook, you'll likely only touch `hooks/<name>.sh`.

## Development workflow

### Branching

Work on a feature branch, not `main`:

```bash
git checkout -b feat/clearer-error-messages
```

Naming: `feat/<short>`, `fix/<short>`, `docs/<short>`, `chore/<short>`. Keep branch names under ~30 chars.

### Commits

Conventional commits format. The `type(scope): subject` pattern matches the existing history:

```
feat(end-session): support stash detection in checklist
fix(hooks): handle detached HEAD in pre-commit-check
docs(readme): clarify the marketplace submission status
chore: bump plugin.json to 0.4.0
```

Subject line ≤ 72 chars. Body is optional but encouraged for anything non-obvious — explain the *why*, not the *what* (the diff shows the what).

If you worked with Claude Code on the change, add a `Co-Authored-By` trailer so the AI attribution is in the git record:

```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

### Specs and plans (for non-trivial changes)

Anything larger than a single-file tweak should start with a spec in `docs/superpowers/specs/` and an implementation plan in `docs/superpowers/plans/`. See the existing files for the shape.

This isn't bureaucracy — it's cheaper than writing code that needs to be redone. If the spec reveals the idea doesn't fit the scope, you've saved hours.

For small fixes (a typo, a one-line prose clarification, a hook bug fix), skip the spec and go straight to a PR.

### Testing

There's no automated test suite. Verification is manual:

- **Prose commands:** load the plugin with `--plugin-dir`, invoke the command, check the output against what the command's own prose promises.
- **Hooks:** the shell-level smoke tests in the "Hook smoke tests" section above. Run before and after your change.
- **Templates:** initialize a new scratch repo, run `/session-continuity:primer`, verify the template renders correctly and placeholders fill in.
- **CI:** the GitHub Actions workflow is only triggered by tag pushes. Your PR won't run it — but your branch doesn't need to either.

If you add a new command or hook, add a smoke-test command to `CONTRIBUTING.md` under "Hook smoke tests" so future contributors can exercise it without wiring up Claude.

### Pull requests

Push your branch, open a PR against `main`, and include in the description:

- **What changed.** One sentence, not the full diff narrative.
- **Why.** The motivating problem or user request.
- **How you tested it.** Scratch-repo commands, smoke tests, screenshots if UI-ish.
- **Link to spec/plan** if applicable.

Keep PRs focused. One logical change per PR. If you touched unrelated files while you were in there, split into two PRs or leave those changes for a separate cleanup pass.

### Code review

Expect review feedback. The project has a specific voice and set of conventions, and it takes a couple rounds to internalize. Common review notes:

- "This expands scope." See the scope section at the top.
- "This contradicts LEARNINGS entry #N." The LEARNINGS file captures decisions that came with real cost. Revisiting them needs real justification.
- "The prose tells Claude to summarize — it should enumerate." Slash commands that instruct Claude to produce structured output must say "list every X, do not summarize" explicitly. See LEARNINGS #3.
- "The hook needs JSON output, not plain stdout." `PreToolUse` hooks only inject context via `hookSpecificOutput.additionalContext`. Plain stdout goes to debug logs. See LEARNINGS #1.

## Authoring conventions

### Slash commands (`commands/*.md`)

- One frontmatter block at the top with a single `description:` line. Keep the description under one sentence, marketplace-friendly.
- Structure: brief statement of what the command does, then numbered `## Step N — <name>` sections.
- If a step delegates to another command's step, name that step by section number (e.g. "Step 3 of `commands/primer.md`"). Do not use ranges like "Steps 2-6" — they hide overrides.
- Tell Claude what to enumerate, not what to summarize. "List every file from `git diff --cached --name-only`" is correct. "Report the staged files" leaves room for summarization.
- End with a `## Notes` section for cross-cutting rules (e.g. "never commit automatically", "never invent details").

### Hooks (`hooks/*.sh`)

- `#!/usr/bin/env bash` and `set -eu` at the top. Fail loud in development.
- Read input from stdin JSON, not env vars. Claude Code delivers hook payloads as stdin.
- For `PreToolUse`, emit JSON with `hookSpecificOutput.additionalContext` when you want Claude to see a reminder. Exit 0 always, except for hard errors where blocking is intended.
- For `SessionStart`, plain stdout is injected as additional context. No JSON needed.
- Fail silently on network errors (see `version-check.sh` for the pattern). A crashed hook shouldn't break the session.
- Honor opt-out env vars where it makes sense. `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1` is the existing example.

### Templates (`skills/session-continuity/templates/*.md`)

- Use `{{PLACEHOLDER}}` syntax for fields Claude fills in during `/session-continuity:primer` init mode. Don't get clever with templating engines; it's just string replacement.
- Keep sections short. These templates are read in every new session, so every line has a budget.
- Separate instructions (what to do) from pointers (where to read). The "Ground rules" section is for imperatives; "First things first" is for read-pointers.

### Writing style

The project leans terse and specific. Avoid:

- Abstract framing when a concrete example works.
- Filler adverbs ("simply", "just", "quickly", "quietly").
- "Let me explain…" / "It's worth noting…" / other throat-clearing.
- Em-dash overload. A few per page is fine; twenty is not.
- Bulleted lists where a sentence works.
- Grandiose claims. This is a small tool that does one thing.

## Release process

Only the maintainer tags releases, but the steps are public so PR authors know what happens after merge.

1. Ensure `main` is green and the desired changes are merged.
2. Bump `.claude-plugin/plugin.json` version following semver.
3. Add a new `## [X.Y.Z] — YYYY-MM-DD` section to `CHANGELOG.md` with `### Added`, `### Changed`, `### Removed` subsections as needed. **This section must appear above the previous version's section.** The release workflow extracts the first section matching the tag.
4. Commit with `chore: bump plugin.json to X.Y.Z` and `docs: add [X.Y.Z] to CHANGELOG`.
5. Tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
6. The `.github/workflows/release.yml` workflow extracts the CHANGELOG section and publishes a GitHub Release.

If the release body comes back empty ("No CHANGELOG section for X.Y.Z"), the awk extraction matched the wrong range — see LEARNINGS #2.

## Filing good issues

Before opening an issue, run through this:

- **Is it reproducible?** Include the exact commands, expected output, and actual output.
- **Is it version-specific?** Include `cat .claude-plugin/plugin.json` output.
- **Is it already known?** Search existing issues and `docs/LEARNINGS.md`.
- **Is it in scope?** Re-read the scope section at the top of this file.

A good issue gives the maintainer enough information to reproduce and decide in under five minutes. A vague "it doesn't work" issue is worse than no issue, because it sits unresolved and signals the project has broken tooling when the real problem is missing information.

## License and attribution

This project is MIT-licensed. By submitting a PR, you agree that your contribution will be released under the same license.

Contributors are credited in the git history. There's no separate CONTRIBUTORS file to maintain — `git log` is the canonical record.

If you use Claude Code (or another AI assistant) to draft your PR, include the `Co-Authored-By` trailer in the commit so the attribution is accurate.

## Questions

If something in this guide is unclear, wrong, or could be shorter, open a PR against this file. Clear contributor docs are worth maintaining the same way the code is.
