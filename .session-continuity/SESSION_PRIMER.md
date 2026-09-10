# Session Primer — session-continuity

## Boot order
1. `.session-continuity/PROJECT_CONTEXT.md`
2. `.session-continuity/LEARNINGS.md` (grep on surprise)
3. engrim context / recall (required)
4. graphify query when the question is about code structure
5. This file — Mid-flight + Confirm
6. `/session-continuity:backlog` for the deferred queue

## Mid-flight
- #45 done → concrete doctor retrofit filed as #68 (zero-turn `doctor-report.sh`)
- Determinism Phase 6 on #43 — A/B/D shipped; C/E deprioritized (issue closed)
- Next backlog candidates: #68 doctor zero-turn, #37 scratch-smoke, #36 integration, #35 marketplace
- Patch release deferred (Unreleased: #60/#55/#53 + graphify ignore)

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
