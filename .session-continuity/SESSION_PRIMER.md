# Session Primer — session-continuity

## Boot order
1. `.session-continuity/PROJECT_CONTEXT.md`
2. `.session-continuity/LEARNINGS.md` (grep on surprise)
3. engrim context / recall (required)
4. graphify query when the question is about code structure
5. This file — Mid-flight + Confirm
6. `/session-continuity:backlog` for the deferred queue

## Mid-flight
- Releasing **v0.38.0** on `main` — #73 hooks sprawl remediation shipped via PR #74 (squash @ `71f2ea9`): Family A/B split, commit-gate multiplexer, 2 new operator-safety gates. Also carries #68 doctor and #37 primer-scratch smoke.
- #73's own plan doc is intentionally uncommitted at `meta/superpowers/plans/2026-09-14-hooks-sprawl-remediation.md` (preserved, untracked) — committing it hits a real, pre-existing non-determinism bug in `gate_has_escape`/`gate_hatch_class` for large (~64KB) self-referential docs; LEARNINGS #21's `git commit -F-` workaround doesn't clear it. Needs its own investigation before anyone re-tries committing it.
- Next backlog: #36 integration tests, #35 marketplace submission.
- Trap: Cursor parent Shell sandbox blocks smoke `git init` in `/tmp` — run smokes via agent with `all` / unsandboxed

## Confirm
```bash
bash hooks/lib/primer-validate.sh .session-continuity/SESSION_PRIMER.md
test "$(jq -r .version .claude-plugin/plugin.json)" = "0.38.0"
gh release view v0.38.0 --json tagName -q .tagName
zsh meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh
zsh meta/superpowers/validation/2026-09-14-commit-gate-multiplexer-smoke.zsh
```

## Peers
- engrim: required — ok (probed this close-out)
- graphify: required — `graphify-out/graph.json` (ok)
- backlog: GitHub Issues labeled `backlog`
