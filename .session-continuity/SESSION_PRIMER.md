# Session Primer — session-continuity

You are picking up work on session-continuity from a previous session.
This file is the shortest path to productive context. Read it in order.

## Ground rules (how to work here)

1. Don't assume. Don't hide confusion. Surface tradeoffs.
2. Minimum code that solves the problem. Nothing speculative.
3. Touch only what you must. Clean up only your own mess.
4. Define success criteria. Loop until verified.

## First things first (read these before touching anything)

1. **`CLAUDE.md`** at the repo root — project conventions, runtime
   choices, never-commit-secrets rules.
2. **`.session-continuity/LEARNINGS.md`** — graveyard of subtle bugs,
   grouped by layer. If you hit something weird, grep this file first.
3. **Session memory system** (MemPalace, or whatever the user has in
   place) — prior sessions may have left searchable context. Query
   before guessing.

## Repo layout

Claude Code plugin. Key paths:

- `.claude-plugin/plugin.json` — plugin manifest (name, version, homepage, repository)
- `.claude-plugin/marketplace.json` — single-plugin marketplace catalog (what `/plugin marketplace add` reads)
- `skills/session-continuity/SKILL.md` — main skill description shown in marketplace
- `skills/session-continuity/templates/` — `SESSION_PRIMER.md` and `LEARNINGS.md` starter templates
- `commands/` — slash command skill files (`primer.md`, `learning.md`, `end-session.md`)
- `hooks/` — `SessionStart` and `PreToolUse` hook scripts
- `.session-continuity/` — this primer and LEARNINGS (the canonical location as of v0.5.0; was `docs/` in v0.4 and earlier)

No build step. Everything is Markdown and shell scripts. Install via (from inside Claude Code):
```
/plugin marketplace add talgolan/session-continuity
/plugin install session-continuity@session-continuity
/reload-plugins
```

## Working directory

```
/Users/tal.golan/active_development/TG/session-continuity-plugin
```

The repo also lives at `/Users/tal.golan/.claude/skills/session-continuity` as a symlink → `~/active_development/TG/session-continuity-plugin`. The symlink keeps the dev plugin auto-loaded by Claude Code while source-of-truth lives in the active_development tree. Edit either path; they resolve to the same files.

## The packages / modules

| Component | Purpose | Notes |
|---|---|---|
| `skills/session-continuity/SKILL.md` | Main skill (session-continuity) | Invoked at session start |
| `commands/primer.md` | `/session-continuity:primer` | Init / refresh / check state machine |
| `commands/learning.md` | `/session-continuity:learning` | Append a LEARNINGS entry interactively |
| `commands/end-session.md` | `/session-continuity:end-session` | Close-out ritual: refresh + LEARNINGS candidates + git checklist |
| `hooks/` | SessionStart + PreToolUse | Remind Claude to read primer; nudge on git commit without primer staged |

## Test expectations — these must stay green

No automated test suite. Validation is manual: install the plugin in a test project and exercise each slash command.

## End-to-end check (real integration)

```bash
# Install in a scratch project and run all three commands:
/session-continuity:primer    # init → fill → stage
/session-continuity:learning  # append entry → stage
/session-continuity:end-session  # refresh + checklist
```

No external credentials or costs.

## Current state

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
- `.session-continuity/` holds only `SESSION_PRIMER.md` and `LEARNINGS.md` (v0.5.0 moved them from `docs/`). Dev artifacts (marketplace-submission notes, specs, plans, recommendation docs) live under `meta/`.
- No known open bugs; outstanding items are feature-level.

**Current `git log --oneline -5` (primary branch):**

```
b75af34 feat(learnings): backfill Trigger lines, require them going forward
8f05d0e fix(hooks): JSON-escape deny reasons (v0.12.2) (#11)
4eb8d5c fix(hooks): scope smoke-gate weak-word to adjacency + honor MANDATORY (v0.12.1) (#10)
5e3426c feat: outstanding-items code verification in end-session (v0.12.0) (#9)
3941f55 feat: evidence, flaky, and backend-parity gates (v0.11.0) (#8)
```

Regenerate this block whenever you commit — see "Primer maintenance" below.

## Outstanding items (explicitly deferred — not bugs, decisions)

1. **Submit to the Anthropic marketplace.** Form answers in `meta/administrative/marketplace-submission.md` (version field synced to 0.6.0 in the docs sweep on 2026-05-22).

2. **Deferred recommendations from `meta/superpowers/recommendations/improvements_20260521.md`** (rejected or not-yet-prioritized — v0.5.1 + v0.6.0 shipped the items deemed high-value):
   - §2 branch-aware primer-only rule (rejected: edge case, current escape hatch sufficient).
   - §3 init-mode auto-derivation (deferred — friction is real but bounded).
   - §4.2 slug-based cross-refs `[[name]]` in LEARNINGS (defer until cross-ref count >20).
   - §4.3 auto-generated symptoms index at top of LEARNINGS (defer; symptom grep already works).
   - §6 split primer into volatile/stable halves (rejected: doubles maintenance, "one file = one mental model").
   - §7 JSON sidecar lock for primer fields (rejected: kills `vim docs/SESSION_PRIMER.md` flow).
   - §8 caveman/cavecrew cross-plugin integration (skip; presumes §6).
   - §9.1 merge primer with auto-memory `MEMORY.md` (deferred — separate-systems boundary worth keeping).
   - §9.5 outstanding-items as YAML (deferred — markdown sub-bullets work today).
   - §9.6 dev-mode plugin install template-path fallback (low priority bug, one-line fix when it bites).

3. **Automated integration tests.** Manual validation only right now. Consider a bats or similar shell test harness to exercise the slash commands against a fixture repo. The auto-migration code path in primer's Migrate mode and the new `learning`-skill duplicate-detection guard are good candidates.

4. **Plan to drop the `docs/` fallback in hooks.** v0.5.0 keeps dual-path support indefinitely. A future v1.0.0 can remove the fallback once the auto-migration has had time to land in every user's repo.

5. **SessionStart should restate outstanding items and ask which to work on.** Right now `hooks/session-start.sh` only nudges Claude to read the primer; it doesn't surface the `## Outstanding items` list itself or prompt the user to pick one. Add that as a final step of session start — after the primer/LEARNINGS reminder, list the current outstanding items and ask the user which (if any) they want to tackle this session.

## Workflow conventions

- **Bun is the runtime** for any JS/TS tooling added to this repo.
- Semantic versioning: bump `plugin.json` + add a `CHANGELOG.md` `[X.Y.Z]` block in the same commit as the feature.
- Commit messages: conventional commits (`feat:`, `fix:`, `docs:`, `chore:`). No trailing co-author line needed unless explicitly requested.
- **Never commit the primer alone** — stage it alongside a substantive change. Primer-only commits are allowed only as a one-shot catch-up.
- **Read `.session-continuity/LEARNINGS.md` before blaming the code.** Half the bugs you hit are already documented there.

## Where to look for what

| Question | File |
|---|---|
| "Why does X work this way?" | `.session-continuity/LEARNINGS.md`, `CHANGELOG.md` |
| "What did the last session do?" | `git log`, this primer |
| "How do I configure the plugin?" | `plugin.json`, `skills/session-continuity/SKILL.md` |
| "How do the slash commands work?" | `commands/primer.md`, `commands/learning.md`, `commands/end-session.md` |
| "What hooks are installed?" | `hooks/` |
| "Who is the user?" | Global `~/.claude/CLAUDE.md` for cross-project context |

## If you get stuck

In order of cost:

1. Grep `.session-continuity/LEARNINGS.md` for your symptom.
2. Query the session memory system with your symptom.
3. Check for stale state (processes, caches, lockfiles) before
   assuming a code bug.
4. Ask the user.

## Primer maintenance (your responsibility)

Refresh this file **alongside substantive commits**, not as a standalone
follow-up. Two sections are the usual targets:

- **Current state** — regenerate the `git log --oneline -5` block so
  a future session sees the real latest commits.
- **Outstanding items** — if you finished one, remove it. If a code
  review flagged a new follow-up, add it.

**When to update** — stage primer edits in the same commit as the
real change that made them necessary.

**When NOT to update** — do NOT commit the primer by itself just to
record the previous primer refresh.

When a bug takes more than 15 minutes to diagnose, update
`.session-continuity/LEARNINGS.md` too (see that file's footer for numbering rules).
