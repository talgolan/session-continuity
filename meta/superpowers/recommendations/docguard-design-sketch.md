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

## Implemented (2026-09-08)

Built in `~/.githooks` — machine-wide scope, per the "own session, explicit
go-ahead" note below, obtained 2026-09-08. Note: `~/.githooks` turned out
NOT to be its own git repo during implementation — it's a subdirectory of a
personal dotfiles repo rooted at the user's home directory (blanket
`.git/info/exclude` plus per-file `git add -f`). `post-merge` itself had
never been tracked by git before this work force-added it for the first
time. This doesn't change what shipped, but it does mean the branch this
work landed on can't simply be merged to that repo's `main` without an
explicit reconciliation step (git will try to check out a newly-tracked
`post-merge` over the path where the real live hook — untracked — already
sits).

- `~/.githooks/lib/docguard-yaml.sh` — hand-rolled parser (no `yq`
  dependency) for a fixed, flat `.docguard.yml` schema: a list of
  `{doc, claim_pattern, actual_command}` triples.
- `~/.githooks/post-merge` — if a repo's root has a `.docguard.yml`, its
  entries fully replace the old hard-coded primer-pass-count check; repos
  without one see no behavior change.
- Correction to this sketch's original assumption: the check is
  **advisory-only, not a hard block**. Enforcement already lives in
  `post-merge` (moved there from `pre-commit` because PRs merge
  server-side), and git ignores a post-merge hook's exit code — it cannot
  block or undo a merge that already landed.
- Escape hatch unchanged: `DOCGUARD_SKIP_COUNT=1` skips the check, config-
  driven or legacy.
- Plan: `meta/superpowers/plans/2026-09-08-docguard-generalization.md`.
- Closes GitHub issue #38.
