# Session Primer — session-continuity

You are picking up work on session-continuity from a previous session.
This file is the shortest path to what changed recently and what's
outstanding. For stable repo context (layout, conventions, modules), read
`.session-continuity/PROJECT_CONTEXT.md` once per session — it changes
rarely.

## First things first (read these before touching anything)

1. **`.session-continuity/PROJECT_CONTEXT.md`** — stable repo context:
   layout, conventions, where to look for what.
2. **`CLAUDE.md`** at the repo root — project conventions, runtime
   choices, never-commit-secrets rules.
3. **`.session-continuity/LEARNINGS.md`** — graveyard of subtle bugs,
   grouped by layer. If you hit something weird, grep this file first.
4. **Session memory system** (MemPalace, or whatever the user has in
   place) — prior sessions may have left searchable context. Query
   before guessing.

## Current state

- **v0.23.0 shipped this session on branch
  `feat/end-session-step2-cost-attribution`, not yet merged/released.**
  Ships candidate extraction + Heuristics A-D
  (`hooks/lib/candidate-extract.sh`), the `step-4-agent-active` derivation
  (`hooks/lib/agent-active.sh`, retiring `step-4-compute-only`), and
  `LEARNINGS.md`'s duplicate-detection/Symptoms-index regeneration
  (`hooks/lib/learnings-index.sh`) as scripts instead of prose the agent
  re-executed or re-derived by hand each invocation, plus a shared
  `CONTRACT_VERSION` skew guard (`hooks/lib/require-script.sh`).
  `commands/end-session.md` Steps 2 and 4 and `commands/learning.md` Steps
  4 and 6 now delegate to these scripts. Closes BACKLOG item 5. Four new
  hermetic smoke suites (32 assertions: 7 require-script + 8
  candidate-extract + 5 agent-active + 12 learnings-index), all green;
  full validation suite now 16 `2026-*-smoke.zsh` runners. Static checks
  confirmed `step-4-compute-only`/`compute_only` retired with zero
  remaining references in `commands/` or `hooks/`, and all four scripts'
  degenerate-input behavior (`/dev/null`) matches their documented
  contracts. **Residual gap: nobody has yet run
  `/session-continuity:end-session` or `/session-continuity:learning` live
  end-to-end against this branch** — Task 9's validation was static
  (grep + direct script invocation + smoke suites), not a live slash-command
  ritual; do that once after this branch merges, per
  `meta/superpowers/sdd/2026-09-01-end-session-step2-cost-attribution/task-9-report.md`.
  Spec: `meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md`.
- **v0.22.0 released** — renamed OUTSTANDING_ITEMS.md to BACKLOG.md, added
  ROADMAP.md, added /session-continuity:help. PR #23 merged to `main`
  (`d2ff918`), tag `v0.22.0` pushed, GitHub Actions `release.yml` ran
  clean, [GitHub
  Release](https://github.com/talgolan/session-continuity/releases/tag/v0.22.0)
  published 2026-08-31, verified `draft:false`/`prerelease:false` via
  `gh release view`. Feature branch deleted (local + remote) after merge.
- **v0.19.0 released** — commit `460f507` pushed to `main`, tag `v0.19.0`
  pushed, GitHub Actions `release.yml` ran clean (12s), [GitHub
  Release](https://github.com/talgolan/session-continuity/releases/tag/v0.19.0)
  published 2026-08-30, verified `draft:false`/`prerelease:false` and the
  release body via `gh release view`. Full 12-suite smoke run (112
  assertions) rechecked green on the pushed state before tagging.
  Bundles three merged PRs plus a retroactive fix, cut as one release.
  PR #20 (`216a53c`): closed
  item 9 — trimmed `SKILL.md` 248→170 lines, split gate/hook internals,
  the decision tree, customization guidance, team-wide rollout, red
  flags, and philosophy into new `skills/session-continuity/REFERENCE.md`
  (108 lines). PR #21 (`33888d9`): closed item 7 — `gate-common.sh`'s
  `gate_scan_staged` converted its last two `[ -z "$x" ] && continue`
  spots to `if/fi`. PR #22 (`d7a9470`): closed item 8 — new
  `/session-continuity:doctor` command (read-only, five ✓/⚠️ rows: install
  mode, hooks registered, all four `.session-continuity/` files present +
  primer not stale, `CLAUDE_PLUGIN_ROOT` resolves and not a stale cache,
  gate scripts executable); also fixed `PRIVACY.md`/`CONTRIBUTING.md`
  still saying "three files" and missing `REFERENCE.md` from the tree.
  **Also this session:** closed item 6 by tracing it — the Init-mode
  enrichment it described as unreleased was actually already shipped
  inside v0.18.0's code (confirmed via `git merge-base --is-ancestor`
  against `cd23e09`); it just never got a CHANGELOG bullet, added
  retroactively to the `[0.18.0]` section instead of re-releasing
  already-shipped code. **Also fixed: the pushed `v0.18.0` tag/release
  had been orphaned** — PR #20's squash-merge absorbed a local-only
  unpushed commit's diff into `216a53c`, leaving the original commit
  (and the tag pointing at it) unreachable from `main`. Re-pointed the
  tag (local delete/recreate + `git push origin :refs/tags/v0.18.0` then
  a fresh push) to `cd23e09`, the actual ancestor; verified via
  `gh release view` that the GitHub Release re-associated correctly.
  diverged local history. Not yet released — no version bump.
- **In flight this session (committed on branch
  `docs/gate-chain-trap-and-primer-drift-check`, not yet merged/released):
  three doc fixes found by reviewing a consuming project's
  (architect-workbench) CLAUDE.md "Read first" section.** (1) `SKILL.md`
  gained a "Gate mechanics" subsection warning that chaining `git add
  <file> && git commit` in one Bash call gets the whole tool call
  denied — not just the commit — when a gate fires, silently skipping
  the add too, even on retry; fix is two separate Bash calls. (2)
  `SKILL.md`'s maintenance rules and `commands/primer.md` Step 4's
  item-6 (apply-the-edits) now both say explicitly: before marking an
  outstanding item DONE, verify against the actual code (grep/read),
  not memory or a commit-subject match alone — generalizes a rule
  architect-workbench had hand-rolled per-project (their own MANDATORY
  derived-artifact-sync rule, LEARNINGS #14/#15 there) after discovering
  `primer.md`'s refresh flow only checked "touched," not "true."
  `commands/end-session.md` already had this rigor (its
  `appears-DONE`/`still-open`/`manual` evidence-cited classification) —
  only the simpler `primer.md` refresh flow was missing it. (3) New
  `skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md` — a
  verbatim-copy CLAUDE.md section bundling the read-first pointer, the
  primer-refresh rule, and both new rules above, so a project doesn't
  have to hand-roll this the way architect-workbench did; `SKILL.md`'s
  "For team-wide use" section now points at it instead of one inline
  quoted line. Not yet released — no version bump.
- **v0.17.0 released** — commit-time content gates. `proven-gate.sh`,
  `smoke-gate.sh`, `evidence-gate.sh`, `backend-parity-gate.sh`,
  `occurrence-gate.sh`, and `flaky-gate.sh`'s file check all moved from
  `PreToolUse` `Write|Edit` hooks to a `Bash(git commit *)` hook — a
  file always saves now; only a commit that stages a gated claim
  without its required fields (or an escape hatch) gets denied. New
  shared `hooks/lib/gate-common.sh` (payload parsing, staged-content
  access via `git diff --cached`, decoration-tolerant escape check,
  dot-prefixed scratch-file skip). Fixes two false-trigger bugs found
  live: the escape line rejected markdown decoration (`> **Gate:** N/A
  — …` was denied, only the bare form worked), and a dot-prefixed
  scratch file got blocked four times mid-iteration before it was ever
  going to be committed. Full hermetic validation suite green (12
  `2026-*-smoke.zsh` suites under `meta/superpowers/validation/`),
  shellcheck clean on all six gates plus the new lib. Accepted,
  documented limitation:
  `git commit -a`/pathspec bypasses the staged-index scan — see
  LEARNINGS #14. `plugin.json` 0.16.0→0.17.0, CHANGELOG `[0.17.0]`
  entry added. Spec:
  `meta/superpowers/specs/2026-08-27-commit-time-content-gates-design.md`.
  Plan: `meta/superpowers/plans/2026-08-27-commit-time-content-gates.md`.
  Merged via PR #17 (`a168e4a`), tag `v0.17.0` pushed, GitHub Release
  published.
- **In flight this session (staged, uncommitted): Init-mode enrichment in
  `commands/primer.md`.** Three additions to Step 2's fact-gathering +
  derivation so a fresh `/session-continuity:primer` init produces a
  richer first primer instead of leaving fields for the user to hand-fill:
  (1) run the project's test command once during init and seed
  `{{TEST_COMMAND_SUMMARY}}` with the parsed count when the run exits 0
  and has a recognizable count (`N pass`/`N passed`/`test result: ok`),
  else fall back to the bare command string or `TBD` — never invent a
  count; (2) derive `{{MODULES_TABLE}}` from `@module` docblock grep hits
  (one row per file) instead of always `TBD`; (3) draft
  `{{WORKFLOW_CONVENTIONS}}` by quoting relevant `CLAUDE.md` conventions
  under a "Conventions inherited from CLAUDE.md" sub-heading, presented
  for confirmation in Step 6 rather than asked cold. Step 6's ask-list
  narrowed accordingly (workflow-conventions only asked cold when no
  CLAUDE.md draft was produced). Refresh/split/check modes untouched.
  Not yet released — no version bump; stage this primer refresh in the
  same commit as the `commands/primer.md` change (do not primer-commit
  alone).
- **v0.16.0 released** — tag `v0.16.0` pushed, GitHub Release published
  2026-08-22 (verified `draft:false`/`prerelease:false` via `gh release
  view`), merged via PR #16 (`1573de2`), plugin.json bumped
  0.15.1→0.16.0 (`10fc553`). Adds real end-to-end timing for
  `/session-continuity:end-session`: each step's self-reported timer only
  covered its own Bash block, not the gaps between steps (transcript
  mining, checklist review), so the multi-minute totals a user actually
  experiences were invisible to `performance.log`. A new final step reads
  back the invocation's own `step-1-fast-path` timestamp and logs one
  real end-to-end `step-4-ritual-complete` duration per invocation.
  Live-tested against a scratch repo via `claude --plugin-dir`.
  **Considered and dropped:** a companion self-logged "session start
  ready" timing for `session-start.sh` — live testing showed Claude
  answers with primer content in text only and never issues the trailing
  self-log Bash call, so the mechanism doesn't fire; session-start timing
  stays hook-only. See CHANGELOG `[0.16.0]`.
- **v0.15.1 released** — commit `df63267` (squash-merged via PR #15), tag
  `v0.15.1` pushed, GitHub Actions `release.yml` ran clean, [GitHub
  Release](https://github.com/talgolan/session-continuity/releases/tag/v0.15.1)
  published 2026-08-17. Verified via `gh run list` + `gh release view`.
  **v0.15.0's self-reported performance-logging instrumentation was
  completely non-functional as shipped.** All 11 `perf-log.sh` calls
  added to `commands/primer.md`/`commands/end-session.md` used the
  unbraced `$CLAUDE_PLUGIN_ROOT/...` form inside bash fences — Claude
  Code's template substitution only resolves the braced
  `${CLAUDE_PLUGIN_ROOT}` form (confirmed live: real invocation failed
  every call with "No such file or directory"; `$CLAUDE_PLUGIN_ROOT` is
  not exported as a shell env var to an agent-run Bash tool call
  either — only Claude Code's own text templating resolves the braced
  form, before the model ever sees the command content). The manual
  scratch-repo validations during implementation (plan tasks 4, 5, 7)
  didn't catch this because they manually `export`ed the variable
  themselves, masking the gap. Found and fixed within minutes of the
  v0.15.0 release, by actually invoking `/session-continuity:primer`
  for real after updating and reloading. The hook-side mechanism
  (`hooks.json` → `perf-wrap.sh`) was unaffected — already used the
  braced form, and is confirmed working live: real timing entries for
  `session-start.sh`, `pre-commit-check.sh`, `flaky-gate.sh`,
  `proven-gate.sh`, etc. are already accumulating in this repo's own
  `.session-continuity/performance.log` from ordinary use this
  session. See CHANGELOG `[0.15.1]`.
- **v0.15.0 released** — commit `c006b2e` (squash-merged via PR #14), tag
  `v0.15.0` pushed, GitHub Actions `release.yml` ran clean, [GitHub
  Release](https://github.com/talgolan/session-continuity/releases/tag/v0.15.0)
  published 2026-08-17. Verified via `gh run list` + `gh release view`.
  Per-repo performance logging: every shipped hook invocation (via a new
  `hooks/lib/perf-wrap.sh` timing wrapper, routed through `hooks.json`)
  and the heavier batched-bash-call operations inside
  `/session-continuity:primer` (6 units) and `/session-continuity:end-session`
  (5 units) now log timing to `.session-continuity/performance.log`
  (auto-gitignored) via a new shared writer, `hooks/lib/perf-log.sh`.
  `/session-continuity:learning` intentionally not instrumented — no
  batched bash operation to time. Built via brainstorming → spec → plan
  → subagent-driven-development (7 tasks, each independently reviewed;
  one cross-task fix caught by end-to-end validation — a marker file
  that wasn't gitignored, silently defeating `end-session`'s fast path
  after first use; one final whole-branch review caught a stray, never
  actually reverted out-of-scope edit to this very file from an earlier
  fix round). No new command surfaces the log yet — read it directly
  with `jq`/`grep`/`bat`. See CHANGELOG `[0.15.0]` and
  `meta/superpowers/specs/2026-08-17-performance-logging-design.md`.
- **v0.14.4 released** — commit `cf29867` (squash-merged via PR #13), tag
  `v0.14.4` pushed, GitHub Actions `release.yml` ran clean, [GitHub
  Release](https://github.com/talgolan/session-continuity/releases/tag/v0.14.4)
  published 2026-08-15. Verified via `gh run list` + `gh release view`.
  User-reported: `/session-continuity:end-session` took 20+ minutes on a
  real session despite v0.14.2's fast path. Diagnosis: the 20 minutes was
  round-trip latency (one model turn per Bash call), not compute —
  validated the actual jq/grep work on a 4.3MB/238-call transcript at
  <0.05s. Three fixes to `commands/end-session.md` + `commands/primer.md`:
  (1) explicit single-Bash-call batching at 4 spots that previously spent
  one round trip per command/item (fast-path check, outstanding-items
  per-item verification, Step 3's fact-gathering, plus Step 2's transcript
  extraction); (2) Step 2's jq filter went from unverified "adjust to the
  schema" prose to a concrete filter tested against 3 real transcripts,
  fixing a real jq gotcha along the way (`split("\n")[0]` → `null` on
  `""`, not `""` — crashes the next `gsub`; see LEARNINGS #10); (3) Step
  1's test-count drift check ran the suite 3× unconditionally — now skips
  the rerun when no relevant file changed, runs once otherwise, and only
  escalates to the 3-run majority vote on disagreement. Also fixed a
  majority-vs-unanimity self-contradiction in `end-session.md`'s
  restatement of the retry rule. See CHANGELOG `[0.14.4]`.
- **v0.14.3 released** — commit `e197071`, tag `v0.14.3` pushed, GitHub
  Actions `release.yml` ran clean, [GitHub Release](https://github.com/talgolan/session-continuity/releases/tag/v0.14.3)
  published 2026-08-15. Verified via `gh run watch` + `gh release view`,
  and this bullet itself is the first live use of the fix it describes:
  fixes the bug this bullet-pattern kept hitting — the primer's "shipped"
  → "released" update lagged behind the actual tag/push/release, because
  the workaround (bundle the release bullet with a trivial unrelated
  change so it isn't a primer-only commit — see commit `c7177b7`) was
  never written down. Both v0.14.1 and v0.14.2 sat marked "(pending
  release)" after they'd already shipped, corrected in the prior commit.
  `skills/session-continuity/SKILL.md`'s primer-only-commit exception list
  now names "record a completed tag+push+release immediately, don't defer
  it" as its own case. See CHANGELOG `[0.14.3]`.
- **v0.14.2 released** — commit `e1e20c9`, tag `v0.14.2` pushed, GitHub
  Actions `release.yml` ran clean, [GitHub Release](https://github.com/talgolan/session-continuity/releases/tag/v0.14.2)
  published 2026-08-14. Verified via `gh run list` + `gh release view`.
  Two fixes from user-reported friction, not a doc sweep: (1)
  `/session-continuity:end-session` had gotten slow — grew 172→493 lines
  across its history, and the two biggest additions (v0.12.0's
  outstanding-items verification, v0.6.0's four LEARNINGS heuristics) both
  pay real per-invocation runtime cost, not just instruction-length cost.
  Added a fast path (skip Step 1 entirely when nothing changed since last
  close-out), gated per-item verification behind commit-subject token
  overlap (untouched items get a cheap `manual` verdict instead of a full
  grep/glob check — documented tradeoff: an item resolved without a
  matching commit won't be caught until one lands), and merged Step 2's
  four separate transcript scans into one combined extraction pass. (2)
  Outstanding-items numbering had no explicit "start at 1, never 0" rule
  anywhere — hardened both `hooks/session-start.sh`'s injected instruction
  and `SKILL.md`'s standing rule to say so directly. See CHANGELOG
  `[0.14.2]` for the full list.
- **v0.14.1 released** — commit `9d8df5f`, tag `v0.14.1` pushed, GitHub
  Actions `release.yml` ran clean, [GitHub Release](https://github.com/talgolan/session-continuity/releases/tag/v0.14.1)
  published 2026-08-13. Verified via `gh release view`, not assumed. Fixes
  a real-world regression reported
  from a different repo running the installed v0.14.0 plugin: outstanding
  items could render as unnumbered prose in chat, because the "always
  render as ordered list" rule only ever covered two mechanical code paths
  (`session-start.sh`'s raw output, `end-session.md`'s overlay), never a
  general behavioral rule. Added one to `SKILL.md` + strengthened the
  hook's own injected text. Also fixed: v0.14.0's `docs/` legacy-fallback
  removal shipped without re-running the existing hermetic smoke suites —
  3 suites / 4 assertions were failing the whole time on stale
  legacy-path fixtures, caught only by the user report, not by the
  release process. All 9 smoke suites (112 assertions) now pass. See
  LEARNINGS #9 for the process fix.
- **v0.14.0 released** — commit `5a2f3d6`, tag `v0.14.0` pushed, GitHub
  Actions `release.yml` ran clean, [GitHub Release](https://github.com/talgolan/session-continuity/releases/tag/v0.14.0)
  published with the real CHANGELOG body (not the LEARNINGS #2
  empty-extraction failure). Verified via `gh run list` + `gh release view`,
  not assumed.
- **v0.14.0 shipped** — dropped the pre-v0.5.0 `docs/` legacy fallback
  entirely (sole current user, no unmigrated install to carry it for).
  Removed dual-path detection/fallback from `hooks/session-start.sh`,
  `hooks/pre-commit-check.sh`, `hooks/learnings-surface.sh`,
  `hooks/occurrence-gate.sh`, `hooks/flaky-gate.sh` (these two were missed
  in the first pass — caught by a follow-up compliance check),
  `commands/primer.md` (Migrate mode
  and Conflict mode deleted; dispatch is now init/split/refresh/check),
  `commands/end-session.md`, `commands/learning.md`,
  `skills/session-continuity/SKILL.md`, and `PRIVACY.md`. `git grep` for
  `docs/SESSION_PRIMER\.md\|docs/LEARNINGS\.md` across `hooks/`,
  `commands/`, `skills/` returns zero hits. Resolves the outstanding item
  that had this deferred to "a future v1.0.0." Also: full documentation
  accuracy sweep across `README.md`, `CONTRIBUTING.md`, `PRIVACY.md`,
  `SECURITY.md`, `CLAUDE.md`, `SKILL.md`, and
  `meta/administrative/marketplace-submission.md` — these had drifted
  since the v0.13.0 `PROJECT_CONTEXT.md` split (undercounted files/commands,
  3 of 7 gate hooks undocumented) and since the marketplace catalog moved
  to `talgolan/claude-plugins` (README's install/update commands were
  pointing at the wrong repo/name — a real broken-install bug, not just
  prose drift). See CHANGELOG `[0.14.0]`'s Fixed section for the full list.
  Confirmed no automated doc-accuracy checking exists anywhere on this
  machine at the repo level — it does exist globally (`~/.githooks/pre-commit`
  + a global Claude Code `Stop` hook) but only checks "was a doc file
  touched," never prose accuracy; verified against the real files, not
  from memory.
- **v0.13.0 shipped** — split `.session-continuity/SESSION_PRIMER.md` into
  volatile (`SESSION_PRIMER.md`) and stable (`PROJECT_CONTEXT.md`) halves,
  overriding the prior §6 rejection on explicit request 2026-08-13. Also
  shipped this session: LEARNINGS.md gained an auto-generated Symptoms
  index and `[[slug]]` cross-references (§4.2/§4.3, same override). Spec:
  `meta/superpowers/specs/2026-08-13-primer-volatile-stable-split-design.md`.
  Plan: `meta/superpowers/plans/2026-08-13-primer-volatile-stable-split.md`.
- **v0.12.3 shipped** (branch `session-start-outstanding-items`, commit pushed,
  tag `v0.12.3` pending). SessionStart hook now surfaces outstanding items from
  the primer: extracts the "Outstanding items" section, lists the first line of
  each numbered item (sub-bullets dropped), and injects into the SessionStart
  reminder with an instruction asking which to tackle. When the section is empty
  or missing, no block is added — the output remains identical to prior versions.
  New hermetic smoke runner
  `meta/superpowers/validation/2026-08-12-session-start-smoke.zsh` validates 11
  test cases covering both paths (`.session-continuity/` and legacy `docs/`),
  multi-line items, empty sections, and missing sections; all pass. Shellcheck
  clean on the modified hook script. Also fixes a pre-existing `grep -c` exit-code
  bug: `grep -c` exits 1 when no matches are found (even though it outputs "0"),
  so a fallback `|| echo '0'` would output both the grep "0" and the fallback "0",
  causing spurious output duplication in the status line. Fixed by using `|| true`
  as the fallback and explicit empty-case handling. `plugin.json` 0.12.2→0.12.3,
  CHANGELOG entry added.
- **v0.12.2 shipped** (branch `fix/hook-json-escaping`, PR #11, tag `v0.12.2`
  pushed, GitHub Release published, live plugin install refreshed and
  verified). Fixes `proven-gate.sh` and `smoke-gate.sh` emitting malformed
  JSON on deny: a reason string containing a literal `"` broke their
  hand-built `printf` JSON, so the block worked but the reason never
  parsed — undiagnosable rather than unsafe. Root cause: every existing
  per-gate runner asserted with a substring match on `deny`, which passes on
  malformed JSON too, so this shipped green. Fix, in order:
  1. New hermetic runner
     `meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh`
     parses each gate's deny output with a real JSON parser (`python3 -m
     json`) instead of substring-matching it, and fails if any
     `hooks/*-gate.sh` has no fixture — so a future gate can't skip the
     check. Red on landing (4 failures: `proven-gate` + 3 `smoke-gate`
     cases), 16/16 green after the fix.
  2. All six gates' `deny()` (not just the two broken ones) now route the
     reason through a `json_escape()` helper: backslash-then-quote
     escaping, full C0 control-byte range (`0x00`-`0x1F`, not just
     `\n\t\r`) folded to a space. `smoke-gate.sh`'s now-redundant
     `offender_esc` pre-escape removed.
  3. `.session-continuity/LEARNINGS.md` entry #1 gained a "Second trap"
     addendum: a well-formed JSON *shape* isn't the same as parseable
     JSON, and a substring assert can't tell the difference.
  4. `plugin.json` 0.12.1→0.12.2, CHANGELOG entry added.
  Full validation suite 8 runners / 101 checks green; shellcheck clean on
  all six gates. Built via `superpowers:subagent-driven-development`
  (fresh implementer + reviewer per task, final whole-branch review on the
  most capable model — 1 Minor finding, non-blocking: the new runner's
  coverage check verifies gate-name list membership, not fixture
  existence, so CHANGELOG/LEARNINGS phrasing slightly overstates what's
  machine-enforced). Plan:
  `meta/superpowers/plans/2026-08-12-hook-json-escaping-fix.md`.
- **v0.12.1 shipped** (branch `fix/smoke-gate-false-positive`). Fixes a
  line-level false positive in `hooks/smoke-gate.sh`: the weak-smoke branch
  denied any line where `smoke` co-occurred with a weak-word
  (`optional`/`deferred`/`after-merge`/`nice-to-have`), even when the weak-word
  modified something unrelated in the same sentence or negated it ("smoke is
  MANDATORY — never deferred"). Three-part fix: (1) explicit `MANDATORY`
  co-occurring with `smoke` on a line passes unconditionally, checked before the
  weak-smoke branch; (2) weak-word only disqualifies when adjacent to `smoke`
  (`smoke[^.]{0,20}(weak)` or reverse); (3) deny reason echoes the matched line.
  Escape hatch, no-smoke branch, plan self-scoping, output contract all
  preserved. New hermetic runner
  `meta/superpowers/validation/2026-08-06-smoke-gate-smoke.zsh` 13/13; full
  validation suite 85/85 green. Diagnosis report lived in the sibling
  smoke-test-plugin (`SMOKE_GATE_FALSE_POSITIVE.md`). `plugin.json` 0.12.0→0.12.1.
- **v0.12.0 shipped** (branch `feat/outstanding-items-verification`, commits
  `dd59d4a` + `986b22a`). Adds outstanding-items verification to
  `/session-continuity:end-session`: Step 1 now verifies each primer outstanding
  item against actual repo state (grep/glob/file-exists checks) before the drift
  check runs, computing a verdict (`still-open` / `appears-DONE` / `manual`) with
  cited evidence. `appears-DONE` candidates route to the existing combined prompt
  when drift exists (Case A), or surface as a standing ⚠️ in the Step 3 checklist
  when drift-clean (Case D). Removal always requires explicit user confirmation —
  a verdict never mutates the primer on its own. Step 3's Outstanding-items row
  re-derives post-edit and reports per-item verdicts with inline evidence.
  Validation matrix: `meta/superpowers/validation/2026-07-30-outstanding-items-verification.md`
  (8 scenarios covering Cases A–D, never-auto-close invariant, edge cases). Pure
  prose-skill change; no new files, hooks, or schemas.
- **v0.11.0 shipped** (squash-merged to `main` as `3941f55`, PR #8). Adds 3 more
  executable gates, closing the remaining gap the user identified when asked "what
  must never be ignored" beyond CLAUDE.md's 4 core rules — 5 memory-logged feedback
  rules also demanded gates; 2 (`proven-gate`, `smoke-gate`) already existed,
  these 3 close the rest:
  - `hooks/evidence-gate.sh` (Write|Edit, spec/plan) — blocks a smoke-mentioning
    plan that describes teardown/cleanup without a preserve-before-teardown
    safeguard, or a poll/wait loop without a dual-signal (success+failure)
    safeguard. Enforces feedback_never_guess_preserve_evidence.
  - `hooks/flaky-gate.sh` (Bash `git commit *` + Write|Edit `LEARNINGS.md`) —
    blocks calling a failure "flaky"/"transient"/"CDN blip" without a
    `Mechanism:` line naming the deterministic cause. Enforces CLAUDE.md rule 1.
  - `hooks/backend-parity-gate.sh` (Write|Edit, plan) — blocks a plan that
    frames smoke as multi-backend but names fewer than 2 concrete backends
    (docker/apple/podman/containerd/colima/kata/lima/orbstack list). Enforces
    feedback_smoke_backend_parity.
  All 3 follow the proven-gate/occurrence-gate/smoke-gate skeleton exactly:
  self-scoped by path, escape hatch `X-gate: N/A — <reason>`, bounded
  best-effort JSON decode, `deny()`/silent-allow output contract. Hermetic
  smoke runners (`meta/superpowers/validation/2026-07-01-{evidence,flaky,
  backend-parity}-gate-smoke.zsh`) 12/13/11 = 36/36 pass; shellcheck clean on
  all 3 hook scripts. Wired into `hooks/hooks.json` (evidence-gate +
  flaky-gate + backend-parity-gate appended to the Write|Edit block;
  flaky-gate also appended to the Bash `git commit *` block alongside
  pre-commit-check.sh). `plugin.json` bumped 0.10.0→0.11.0; CHANGELOG.md
  entry added. Manual install-and-fire validation of the 3 new hooks completed
  before merge. **Deliberately NOT gated by this batch** (per the reinstall-
  PATH-binary memory's own admission): a "PATH binary reinstalled" claim —
  hooks fire on tool-call payloads (Write/Edit/Bash), not on prose sentences
  in Claude's response, so there's no artifact to grep for that claim itself;
  would need a different mechanism (e.g. gating on `git commit`/`gh pr merge`
  checking a hash match, proposed but not built).
- v0.10.0 shipped, squash-merged to `main` on `feat/change-the-odds-2-3c` (change-the-odds #2 + #3c, one PR). Adds `hooks/occurrence-gate.sh`: a `PreToolUse` Write|Edit gate scoped to `LEARNINGS.md` under `*/.session-continuity/*` or `*/docs/*` that denies an entry recording `Occurrence count: N of M` (N≥2) unless the same content names a non-empty `Invariant:` line (CLAUDE.md rule 4 → executable gate). Escape hatch `Occurrence-gate: N/A — <reason>`. Largest-N-wins coarse scan. Wired as 4th entry in `hooks.json` Write|Edit block. Mirrors `proven-gate.sh` skeleton — sole deviation from the literal plan code: `deny()` is called inside an `if` (not unconditionally) so the trailing `exit 0` stays reachable / shellcheck-clean (matches proven-gate). Hermetic runner `meta/superpowers/validation/2026-06-17-occurrence-gate-smoke.zsh` 12/12; shellcheck clean. Also: `/learning` gains optional `Occurrence count:` + (N≥2) `Invariant:` fields (gate-compliant by construction); new `/session-continuity:spike-check` command (5-question stand-in checklist, proactive complement to proven-gate). Spec + plan: `meta/superpowers/{specs,plans}/2026-06-17-occurrence-counter-and-spike-check*`.
- v0.9.0 shipped (squash-merged to `main` as `9de77fb`, PR #6 closed, tag `v0.9.0` pushed). Adds `hooks/proven-gate.sh`: a `PreToolUse` Write|Edit gate scoped to `*/specs/*.md` + `*/plans/*.md` that denies a "proven/verified/spike conclusive" claim unless the same content carries adjacent `Real path:` + `Stubbed:` fields. Whole-word claim match (`unproven`/`improven`/`confirmed` do not trigger). Escape hatch `Proven-gate: N/A — <reason>`. Hermetic fixture runner (`meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh`) 12/12; shellcheck clean. Wired as 3rd entry in `hooks.json` Write|Edit block. Mirrors `smoke-gate.sh` skeleton; sole deviation is the word-boundary match. Spec + plan: `meta/superpowers/{specs,plans}/2026-06-17-proven-gate*`.
- v0.8.0 shipped: two fire-before-action gates (`learnings-surface.sh`, `smoke-gate.sh`) + `/learning` optional Trigger field.
- v0.7.0 shipped (commit `9172667` on `main`, tag `v0.7.0` pushed). Bounds `/session-continuity:end-session` prompt count to ≤2 in the common case: merges Step 1's overlay+outstanding-items prompts into a single combined ask, batches Step 2 candidate confirmation into one prompt instead of looping per-candidate. Adds Step 4 terminal sign-off (`✅ Session complete. Safe to close.`) so the user is never left ambiguous after invoking an explicit close-out. Pure prose-skill change; no new files, hooks, or schemas. See v0.7.0 CHANGELOG entry.
- v0.6.0 shipped (merged to `main` as `7bc25c3`, tag `v0.6.0` pushed; PR #1 closed). Adds the §1 outstanding-items overlay and §5 four-heuristic LEARNINGS candidate surfacing to `/session-continuity:end-session`. Pure prose-skill addition; no new files, hooks, or schemas. See the v0.6.0 CHANGELOG entry for the full diff.
- New project-local `CLAUDE.md` redirects superpowers skills' default `docs/superpowers/{specs,plans}/` paths to `meta/superpowers/`, matching the v0.3 layout. Added after the brainstorming-skill default re-introduced the duplicate `docs/superpowers/` directory.
- v0.5.1 (commit `f5013e1`) shipped quick-win refinements: drop the mtime drift check, 3× test-flake retry, `git log <last-primer>..HEAD` candidate surfacing, hardened `learning` numbering, and a 4-line `SessionStart` status block.
- v0.5.0 (commit `aff74c3`) relocated the two files from `docs/` to `.session-continuity/` with auto-migration support.
- Three slash commands are stable (`primer`, `learning`, `end-session`).
- `hooks/hooks.json` uses `if: "Bash(git commit *)"` to scope the `PreToolUse` hook; it does not fire on every Bash call.
- `.claude-plugin/marketplace.json` present so the repo is installable via `/plugin marketplace add talgolan/session-continuity`.
- `.session-continuity/` holds `SESSION_PRIMER.md`, `PROJECT_CONTEXT.md` (new in v0.13.0), `BACKLOG.md` (new in v0.18.0 as `OUTSTANDING_ITEMS.md`, renamed in v0.22.0), `ROADMAP.md` (new in v0.22.0), and `LEARNINGS.md`. Dev artifacts (marketplace-submission notes, specs, plans, recommendation docs) live under `meta/`.
- No known open bugs; outstanding items are feature-level.

**Current `git log --oneline -5` (primary branch):**

```
d2ff918 Merge pull request #23 from talgolan/feature/backlog-roadmap-help
3dba137 docs: fix stale file-count references found in final review
e0c0ab0 docs: migrate this repo's own OUTSTANDING_ITEMS.md to BACKLOG.md, add ROADMAP.md
db15d1a docs: README documents BACKLOG.md, ROADMAP.md, and /help
70600f6 chore: bump to 0.22.0 — BACKLOG.md rename, ROADMAP.md, /help command
```

Regenerate this block whenever you commit — see
`.session-continuity/PROJECT_CONTEXT.md`'s "Maintenance" section.
