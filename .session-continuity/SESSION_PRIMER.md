# Session Primer — session-continuity

## Boot order
1. `.session-continuity/PROJECT_CONTEXT.md`
2. `.session-continuity/LEARNINGS.md` (grep on surprise)
3. engrim context / recall (required)
4. graphify query when the question is about code structure
5. This file — Mid-flight + Confirm
6. `/session-continuity:backlog` for the deferred queue

## Mid-flight
- Finish/merge #62 thin hard-template SESSION_PRIMER (this branch `feat/primer-thin-hard-template`) — plan `meta/superpowers/plans/2026-09-09-primer-thin-hard-template.md`
- Determinism Phase 6 on #43 — C/E still open (deprioritized); A/B/D shipped in 0.32–0.34
- #38 docguard generalization still open (githooks side unmerged; this-repo design already landed)

## Confirm
```bash
bash hooks/lib/primer-validate.sh .session-continuity/SESSION_PRIMER.md
zsh meta/superpowers/validation/2026-09-09-peer-probes-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-primer-validate-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-primer-freshness-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-session-start-peers-smoke.zsh
```

## Peers
- engrim: required — status unknown until probed
- graphify: required — `graphify-out/graph.json`
- backlog: GitHub Issues labeled `backlog`
