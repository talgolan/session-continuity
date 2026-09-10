# Session Primer — session-continuity

## Boot order
1. `.session-continuity/PROJECT_CONTEXT.md`
2. `.session-continuity/LEARNINGS.md` (grep on surprise)
3. engrim context / recall (required)
4. graphify query when the question is about code structure
5. This file — Mid-flight + Confirm
6. `/session-continuity:backlog` for the deferred queue

## Mid-flight
- Released **v0.37.1** on `main` @ `84be9eb` — scratch→real R100 gate fix (#72); https://github.com/talgolan/session-continuity/releases/tag/v0.37.1
- Primer-detect freshness plan still open: `meta/superpowers/plans/2026-09-10-primer-detect-freshness.md`
- Next backlog candidates: #36 integration, #35 marketplace
- Trap: Cursor parent Shell sandbox blocks smoke `git init` in `/tmp` — run smokes via agent with `all` / unsandboxed

## Confirm
```bash
bash hooks/lib/primer-validate.sh .session-continuity/SESSION_PRIMER.md
test "$(jq -r .version .claude-plugin/plugin.json)" = "0.37.1"
gh release view v0.37.1 --json tagName -q .tagName
zsh meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh
zsh meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh
```

## Peers
- engrim: required — ok (probed this close-out)
- graphify: required — `graphify-out/graph.json` (ok)
- backlog: GitHub Issues labeled `backlog`
