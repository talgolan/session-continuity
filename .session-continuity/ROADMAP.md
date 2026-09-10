# Roadmap — session-continuity

Strategic direction — where this project is headed, not the tactical
queue (that's GitHub Issues labeled `backlog`). Freeform: no numbering,
no permanence rules, no length cap. Rewrite sections wholesale as
direction changes; this file's history lives in git, not in careful
edits.

## Now

**Thin hard-template + peers are the boot contract (0.36.x).** Primer is
Boot order / Mid-flight / Confirm / Peers; freshness is
`primer-freshness.sh`; detect's `LOG_DRIFT` maps from that probe (0.36.1 /
#64). SessionStart/doctor hard-incomplete without local engrim and a
committed `graphify-out/graph.json`.

**Determinism program — mostly shipped.** Phases 0–5, 6-A/B/D, and 7
(`derived-value-gate`) landed through 0.35–0.36. Invariant still holds:
no command prompt asks a model to compute a pure function of files, git
state, or transcript data. Remaining Phase 6 sub-projects C/E stay
deprioritized (see #43). Design spine:
`meta/superpowers/specs/2026-09-02-determinism-program-design.md`.

**Near-term backlog (GitHub `#N`):** #68 zero-turn `/doctor` retrofit
(post-`4a9d` / closes placeholder #45), #37 scratch-project primer-split
smoke, #36 automated integration tests, #35 Anthropic marketplace.

## Next

Marketplace submission (#35) and broader automated integration coverage
(#36 / #37) once the dogfood loop stays green on the thin primer + peers
path. Prefer small patches that keep Confirm/smokes hermetic over new
surface area.

## Later

Anything that expands beyond four in-repo files + GitHub Issues backlog,
or that reintroduces embedded git-log / fat-primer shapes, stays out of
scope unless a concrete failure mode forces it (see CONTRIBUTING).
