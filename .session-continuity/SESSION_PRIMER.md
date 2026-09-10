# Session Primer — session-continuity

## Boot order
1. `.session-continuity/PROJECT_CONTEXT.md`
2. `.session-continuity/LEARNINGS.md` (grep on surprise)
3. engrim context / recall (required)
4. graphify query when the question is about code structure
5. This file — Mid-flight + Confirm
6. `/session-continuity:backlog` for the deferred queue

## Mid-flight
- Docs pass: README / SKILL / REFERENCE / PRIVACY / ROADMAP / PROJECT_CONTEXT aligned to thin primer + freshness + peers (0.36.x)
- Determinism Phase 6 on #43 — C/E still open (deprioritized); A/B/D shipped in 0.32–0.34
- #38 docguard generalization still open (githooks side unmerged; this-repo design already landed)
- Next backlog candidates: #60 pins, #55 no-count, #53 TSV cp, #45 doctor

## Confirm
```bash
bash hooks/lib/primer-validate.sh .session-continuity/SESSION_PRIMER.md
zsh meta/superpowers/validation/2026-09-09-peer-probes-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-primer-freshness-smoke.zsh
zsh meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-session-start-peers-smoke.zsh
```

## Peers
- engrim: required — ok (probed this close-out)
- graphify: required — `graphify-out/graph.json` (ok)
- backlog: GitHub Issues labeled `backlog`
