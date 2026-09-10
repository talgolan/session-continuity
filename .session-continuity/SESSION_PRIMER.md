# Session Primer — session-continuity

## Boot order
1. `.session-continuity/PROJECT_CONTEXT.md`
2. `.session-continuity/LEARNINGS.md` (grep on surprise)
3. engrim context / recall (required)
4. graphify query when the question is about code structure
5. This file — Mid-flight + Confirm
6. `/session-continuity:backlog` for the deferred queue

## Mid-flight
- Branch `eval/gate-escape-smoke-scope`: gate eval spec written, no hook code touched — awaiting implement-vs-park call
- #68+#37 unreleased: zero-turn doctor-report.sh; scratch primer init/split smoke
- Determinism Phase 6 on #43 — A/B/D shipped; C/E deprioritized (issue closed)
- Next backlog candidates: #36 integration, #35 marketplace
- Patch release deferred (also ships prior Unreleased: #60/#55/#53 + graphify ignore)

## Confirm
```bash
bash hooks/lib/primer-validate.sh .session-continuity/SESSION_PRIMER.md
zsh meta/superpowers/validation/2026-09-10-doctor-report-smoke.zsh
zsh meta/superpowers/validation/2026-09-10-primer-scratch-smoke.zsh
zsh meta/superpowers/validation/2026-09-02-prompt-intercept-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-test-count-rerun-smoke.zsh
```

## Peers
- engrim: required — ok (probed this close-out)
- graphify: required — `graphify-out/graph.json` (ok)
- backlog: GitHub Issues labeled `backlog`
