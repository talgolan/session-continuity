# Design sketch: generalized docs-current gate

Extracted from `.session-continuity/OUTSTANDING_ITEMS.md` item 4 during
the 2026-08-30 outstanding-items-file migration — this is the design
detail that exceeded the new file's length cap, not new content.

## The gap

Neither `~/.githooks/pre-commit` nor the global Claude Code `Stop` hook
(`~/.claude/hooks/docs-current-check.sh`) verifies that a doc's claims
stay true — both only check whether *a* doc file was touched. The one
exception is `pre-commit`'s hard block when a primer's `"NN pass"` line
disagrees with the real `bun test` count — a single hard-coded special
case, not a generalizable check. Every drift found in the 2026-08-13 docs
sweep (file counts, command counts, hook counts, a stale marketplace repo
name) is a claim-vs-reality mismatch neither hook would have caught.

**Invariant (per CLAUDE.md rule 4):** every count or named-entity-list
claim in a repo's shipped docs must match the actual repo state at commit
time — enforced at the gate that runs on every commit, not left to
whoever's authoring the next PR to remember.

## Design sketch (not built — lives outside any git repo)

Generalize the existing `"NN pass"` special case into a declarative
per-repo config (e.g. `.docguard.yml`): a list of `{doc: <glob>,
claim_pattern: <regex w/ capture>, actual_command: <shell>}` entries. On
each staged doc file matching an entry, extract the claimed value, run
the command, hard-block on mismatch — reusing the same code path and
escape-hatch pattern (`DOCGUARD_SKIP_COUNT=1`, generalized) the pass-count
check already has, rather than inventing a second mechanism.

## Why not build it now

Touches `~/.githooks` and `~/.claude/hooks`, not this repo — changes
behavior for every git commit on the machine, not just this project.
Bigger blast radius, deserves its own session and explicit go-ahead.
