# Roadmap — session-continuity

Strategic direction — where this project is headed, not the tactical
queue (that's `.session-continuity/BACKLOG.md`). Freeform: no numbering,
no permanence rules, no length cap. Rewrite sections wholesale as
direction changes; this file's history lives in git, not in careful
edits.

## Now

**The determinism program.** The plugin should spend model turns only on
irreducible judgment. Invariant: no command prompt asks a model to compute a
value that is a pure function of files, git state, or transcript data. Eight
phases, each independently shippable and independently useful, each filed as
its own backlog item. Scope and design:
`meta/superpowers/specs/2026-09-02-determinism-program-design.md`.

Backlog positions are recomputed 1..N on every render, so the phase ordering
lives here and nowhere else. Three phases are unblocked today:

- Phase 0 `[3b71]` — fresh-install count defects. Two reproduced bugs hitting
  every new project; smallest unit, patch release, and it closes item `6258`.
- Phase 1 `[5c2d]` — zero-turn read-only lists. Opens with a measurement gate,
  so if the four unprobed hook behaviors don't hold, the approach changes
  before any code lands.
- Phase 2 `[8e4a]` — `end-session` Step 2 rendering and reference relocation.
  Largest single token reduction available.

## Next

Phase 3 `[a17f]`, the shared mechanics library, comes first: it unblocks two
later phases and forces the `/doctor` question filed as `[4a9d]`. Then Phase 4
`[b93c]`, `end-session` Step 3 checklist assembly, which needs Phase 3's
`perf-log.sh since`. Phase 5 `[c60e]`, backlog mechanics and the commit-overlap
gate, depends on nothing but must close item `c9a4` on its way through — it
lifts the same `overlap()` that item documents as broken.

## Later

Phase 6 `[d24b]` rewrites `commands/primer.md`'s detect, migrate, init, and
drift paths. Largest phase, lowest invocation frequency, highest blast radius:
it performs a destructive `git mv` and rewrites five files, so it waits until
the shared library underneath it has settled.

Phase 7 `[f58a]` ships last by design. It is the commit-time content gate that
keeps the invariant true, and its pattern list should be written from what the
earlier phases actually removed rather than guessed up front. Every phase
before it is a one-time cleanup that decays the first time someone adds a step
saying "count the entries."
