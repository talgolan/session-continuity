# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.16.0] — 2026-08-22

### Added
- **Real end-to-end timing for `/session-continuity:end-session`.** Each
  step's self-reported timer only covered its own Bash block, not the
  gaps between steps (transcript mining, checklist review) — so the
  multi-minute totals a user actually experiences were invisible to
  `performance.log`. A new final step reads back the invocation's own
  `step-1-fast-path` timestamp and logs one real end-to-end
  `step-4-ritual-complete` duration per invocation. Live-tested against
  a scratch repo via `claude --plugin-dir`.

### Considered and dropped
- A companion self-logged "session start ready" timing for
  `session-start.sh`, mirroring the same pattern via a trailing
  instruction in the injected reminder. Live testing showed Claude
  reliably answers with primer content in text only and never issues
  the trailing self-log Bash call — the mechanism doesn't fire in
  practice. Session-start timing stays hook-only (already logged).

## [0.15.1] — 2026-08-17

### Fixed
- **v0.15.0's performance-logging instrumentation was completely
  non-functional.** All 11 self-reported `perf-log.sh` calls added to
  `commands/primer.md`/`commands/end-session.md` used the unbraced
  `$CLAUDE_PLUGIN_ROOT/...` form inside bash fences. Claude Code's own
  template substitution only resolves the braced `${CLAUDE_PLUGIN_ROOT}`
  form — confirmed live: updating to v0.15.0, reloading, and invoking
  `/session-continuity:primer` failed every timing call with "No such
  file or directory" (`$CLAUDE_PLUGIN_ROOT` is not exported as a real
  shell env var to an agent-run Bash tool call; only Claude Code's text
  templating resolves the braced form, before the model ever sees the
  command content). The manual scratch-repo validations in the original
  implementation (plan tasks 4, 5, 7) didn't catch this because they
  manually `export`ed the variable themselves, masking the gap. Fixed
  by bracing all 11 occurrences. The hook-side mechanism
  (`hooks/hooks.json` → `perf-wrap.sh`) was unaffected — it already used
  the braced form throughout.

## [0.15.0] — 2026-08-17

### Added
- **Per-repo performance logging.** Every shipped hook invocation, and
  the heavier batched-bash-call operations inside
  `/session-continuity:primer` and `/session-continuity:end-session`
  (test-count reruns, outstanding-items verification, transcript
  extraction, git-log gathering), now append a timing line to
  `.session-continuity/performance.log` in the repo where the plugin
  runs. Gitignored automatically. No new command surfaces the data yet
  — read it directly with `jq`/`grep`/`bat`. `/session-continuity:learning`
  is not instrumented (no batched bash operation to time). See
  `meta/superpowers/specs/2026-08-17-performance-logging-design.md`.

## [0.14.4] — 2026-08-15

### Fixed
- **`/session-continuity:end-session` still took 20+ minutes on a real
  session** despite v0.14.2's fast path and gating. Root cause: several
  places in `commands/end-session.md` listed multiple shell commands as
  a sequence without ever saying "in one Bash call" — nothing stopped an
  agent from spending one full model round trip per command instead of
  one round trip for the batch. Fixed four spots to explicitly mandate
  single-Bash-call batching: the Step 1 fast-path check (3 commands),
  the outstanding-items per-item verification (was one call per item),
  Step 2's transcript extraction, and Step 3's final-checklist fact
  gathering (6 commands).
- **Step 2's transcript-extraction jq filter was unverified prose**
  ("adjust the filter to the file's actual JSONL schema") rather than a
  tested incantation, which caused a real syntax-error retry round trip
  in the field. Replaced with a concrete jq filter validated against
  three real Claude Code transcripts (up to 4.3MB / 238 Bash calls,
  runs in <0.05s), handling both transcript schema variants seen in the
  wild (`toolUseResult.{stdout,stderr}` object vs. a bare `content`
  string prefixed `"Exit code N\n..."`). See LEARNINGS #10 for the
  underlying jq gotcha (`split("\n")[0]` returns `null` on `""`, not
  `""`, crashing the next `gsub`).
- **Step 1's test-count drift check always ran the test suite 3×**,
  unconditionally, whenever the primer had a test-counts section and
  drift was detected — regardless of whether anything test-relevant had
  actually changed, or whether the first run already agreed with the
  recorded count. Now: skip the rerun entirely if no file outside
  `.session-continuity/` changed since the last primer touch (reuses
  the commit list already computed elsewhere in Step 1); otherwise run
  once and only escalate to the 3-run majority vote if that first run
  disagrees with the recorded count. Same correctness guarantee (a
  flaky single run still can't produce a false drift alarm), paid for
  only when there's an actual discrepancy to resolve. Applied to both
  `commands/primer.md` Step 5.3 (canonical) and `commands/end-session.md`
  Step 1's restatement — the latter also had a self-contradiction
  (majority-of-3 in one sentence, unanimity-of-3 two sentences later)
  that's fixed as part of this change.

## [0.14.3] — 2026-08-14

### Fixed
- **The "shipped" → "released" primer update kept lagging behind the actual
  tag/push/release.** This repo's own history shows the workaround (e.g.
  commit `c7177b7`): bundle the primer's "released" bullet with a trivial
  unrelated change so it isn't technically a primer-only commit. That
  workaround was never written down, so it kept getting forgotten — v0.14.2
  sat with a stale "(pending release)" bullet after it was already tagged,
  pushed, and released. `skills/session-continuity/SKILL.md`'s primer-only-
  commit exception list now names this explicitly as its own case: record a
  completed tag+push+release the moment `gh release view` confirms it's
  live, don't defer waiting for a "real" change to bundle it with.

## [0.14.2] — 2026-08-14

### Fixed
- **`/session-continuity:end-session` had gotten slow.** Grew from 172 to
  493 lines over its history; the two biggest single additions —
  outstanding-items code verification (v0.12.0) and the four LEARNINGS
  heuristics (v0.6.0) — both pay real per-invocation cost, not just
  instruction-length cost. Three changes to `commands/end-session.md`:
  - Added a fast path at the top of Step 1: if `git status --porcelain` is
    empty and no commits landed since the primer was last touched, skip the
    drift check and outstanding-items verification entirely (nothing in the
    repo changed, so nothing could have resolved).
  - Gated per-item outstanding-items verification behind commit-subject
    token overlap (reusing the existing overlay's tokenizer): only items
    implicated by a commit since the last refresh get the full
    classify/grep/glob treatment; untouched items get a cheap `manual`
    verdict cited "no related commits since last refresh — not re-checked
    this session." Deliberate tradeoff, documented inline: an item resolved
    without a matching commit subject won't be caught until one lands.
  - Merged Step 2's four independent transcript scans (retry-burst, revert,
    error-recurrence, fix-burst) into one combined extraction pass producing
    three shared arrays (`bash_calls`/`commits`/`errors`); all four
    heuristics now read from those instead of re-scanning the transcript
    file each.
  - Also deduped a redundant `git log <last-primer>..HEAD` call that was
    computed once for verification and again for the refresh-flow overlay.
- **Outstanding-items numbering had no explicit floor.** Nothing in
  `hooks/session-start.sh` or `skills/session-continuity/SKILL.md` said
  numbering must start at 1 — hardened both the hook's injected instruction
  text and the SKILL.md standing rule to say so explicitly ("never 0").

## [0.14.1] — 2026-08-13

### Fixed
- **`hooks/session-start.sh` could render outstanding items as unnumbered
  prose.** The injected reminder always contained the primer's numbered list,
  but nothing told Claude to preserve that numbering when paraphrasing it in
  a reply — a real-world session collapsed it to "same question stand: X or
  Y" with no numbers. Added an explicit standing rule to
  `skills/session-continuity/SKILL.md` ("whenever you discuss or echo
  outstanding items to the user... render them as a numbered list") and
  strengthened the hook's own injected instruction text to say so directly,
  not just "ask the user which of these."
- **v0.14.0's `docs/` legacy-fallback removal shipped without re-running the
  existing hermetic smoke suites.** Three suites
  (`2026-08-12-session-start-smoke.zsh`, `2026-06-17-occurrence-gate-smoke.zsh`,
  `2026-07-01-flaky-gate-smoke.zsh`) had fixtures hardcoded to the exact
  legacy-path scope just removed, so 4 assertions were failing silently in
  the repo the whole time — caught only by a user report from a different
  repo running the installed plugin, not by CI (there is none for PRs) or by
  the release process. Fixtures updated to reflect the new single-path scope;
  see LEARNINGS #9 for the process fix (run every smoke suite before tagging,
  not just the one for the hook touched).

## [0.14.0] — 2026-08-13

### Removed
- **Dropped the pre-v0.5.0 `docs/` legacy fallback.** `.session-continuity/`
  is now the only recognized location. Removed the dual-path detection and
  fallback logic from `hooks/session-start.sh`, `hooks/pre-commit-check.sh`,
  `hooks/learnings-surface.sh`, `hooks/occurrence-gate.sh`, `hooks/flaky-gate.sh`,
  `commands/primer.md` (Migrate mode and the dual-location Conflict mode are
  gone; dispatch is now four states: init, split, refresh, check),
  `commands/end-session.md`, `commands/learning.md`,
  `skills/session-continuity/SKILL.md`, and `PRIVACY.md`. Outstanding item
  originally tracked for a "future v1.0.0" is resolved now instead — this
  plugin currently has a single user, so there is no unmigrated install to
  carry the fallback for.

### Fixed
- **Documentation accuracy sweep.** `README.md`, `CONTRIBUTING.md`,
  `PRIVACY.md`, `SECURITY.md`, `CLAUDE.md`, `skills/session-continuity/SKILL.md`,
  and `meta/administrative/marketplace-submission.md` had drifted across
  several unreleased features: the v0.13.0 `PROJECT_CONTEXT.md` split (most
  docs still said "two files"/"two commands", missing the third file and the
  `/session-continuity:spike-check` command entirely), and three of seven
  `PreToolUse` gate hooks (`evidence-gate`, `flaky-gate`, `backend-parity-gate`)
  that were never documented anywhere outside their own source comments.
  Also fixed a broken install path: the marketplace catalog moved to the
  separate `talgolan/claude-plugins` repo in a past release, but `README.md`'s
  `/plugin marketplace add`/`/plugin install`/`/plugin marketplace update`
  commands still pointed at this repo directly — corrected to the catalog's
  actual name (`talgolan`) and repo. `CONTRIBUTING.md`'s release-process steps
  no longer reference bumping a `marketplace.json` that no longer lives here.

## [0.13.0] — 2026-08-13

### Added
- **Split `SESSION_PRIMER.md` into volatile + stable files.** Stable repo
  context (ground rules, repo layout, module table, workflow conventions,
  "where to look for what") now lives in a new
  `.session-continuity/PROJECT_CONTEXT.md`, seeded by Init mode and
  auto-migrated from unsplit primers by a new Split mode in
  `commands/primer.md`. `SESSION_PRIMER.md` keeps only the volatile
  shortlist: current state, the `git log --oneline -5` block, and
  outstanding items. No hook changes needed — `pre-commit-check.sh`'s
  `.session-continuity/` allowlist and `session-start.sh`'s primer-only
  read both already cover the new file for free.
- **LEARNINGS.md gains a Symptoms index and `[[slug]]` cross-references.**
  `/session-continuity:learning` now offers an optional stable slug per
  entry (for `[[slug]]`-style cross-references that survive renumbering)
  and regenerates an alphabetized `## Symptoms index` section at the top of
  the file from every entry's `**Symptom.**` line each time it appends.

## [0.12.3] — 2026-08-12

### Added
- **SessionStart hook surfaces outstanding items.** The `hooks/session-start.sh`
  hook now extracts top-level numbered items from the primer's "Outstanding
  items" section (first line only; sub-bullets dropped) and injects them into
  the SessionStart `<system-reminder>` block, followed by an instruction asking
  the user which (if any) they want to tackle. When the section is empty or
  missing, no block is added and the reminder remains identical to prior output.

### Fixed
- **Spurious output duplication from `grep -c` exit code.** The `status_learnings`
  computation used `grep -cE ... || echo '0'` to count LEARNINGS entries. When
  `grep` finds no matches, it outputs "0" but exits with code 1 (not 0), causing
  the fallback `echo '0'` to also run. The command substitution captured both
  outputs, resulting in "0\n0" being assigned to the variable and later printed
  to the reminder. Fixed by using `|| true` as the fallback and adding explicit
  empty-case handling with `${status_learnings:-0}`.

## [0.12.2] — 2026-08-12

### Fixed
- **Unreadable blocks from `proven-gate` and `smoke-gate`.** Both built their
  deny payload by interpolating the reason into a hand-written JSON string, so
  a reason containing a double quote terminated the string early and the object
  did not parse. `proven-gate` hit this on every block (its reason quotes the
  word `"nothing"`); `smoke-gate` hit it on the weak-word branch added in
  0.12.1, which wraps the matched line in quotes. The gate still blocked, but
  the reason never reached the author, so there was no way to see which field
  was missing or which escape hatch applied. `deny()` now JSON-escapes its
  argument in all six gates — backslash before quote, with every C0 control
  byte (0x00-0x1F, not just tab/newline/CR) folded to a space, since raw
  control characters are illegal inside a JSON string. Gate behaviour (what
  denies, what passes) is unchanged.

### Added
- **`2026-08-12-hook-json-contract-smoke.zsh`.** Pipes every gate's deny output
  through a real JSON parser instead of substring-matching it, which is why the
  defect above shipped green, and fails when a `hooks/*-gate.sh` has no fixture
  so new gates cannot skip the check.

## [0.12.1] — 2026-08-06

### Fixed
- **`smoke-gate.sh` line-level false positive.** The weak-smoke branch treated
  any co-occurrence of `smoke` and a weak-word (`optional`/`deferred`/
  `after-merge`/`nice-to-have`) on one line as a disqualifying "smoke task is
  optional" — even when the weak-word modified something unrelated in the same
  long sentence, or negated it ("smoke is MANDATORY — never deferred"). That
  blocked legitimate plan writes with a message that named no offending line.
  Three-part fix: (1) an explicit `MANDATORY` co-occurring with `smoke` on a
  line now passes the gate unconditionally, checked before the weak-smoke
  branch; (2) a weak-word only disqualifies when it sits adjacent to `smoke`
  (within ~20 non-period chars, either order), so incidental prose no longer
  trips it; (3) the deny reason now echoes the matched line so the trigger is
  diagnosable. Escape hatch (`Smoke: N/A — <reason>`), the no-smoke branch,
  plan-file self-scoping, and the output contract are unchanged.

### Compatibility
- Additive/behavioral bugfix. Plans previously blocked by incidental
  co-occurrence now pass; genuinely optional/deferred smoke tasks are still
  denied. No migration. Upgrading installs gain the fix on next session.

## [0.12.0] — 2026-07-30

### Added
- `/session-continuity:end-session` now verifies the primer's outstanding items
  against actual repo state. Each item is classified code-verifiable or not;
  code items get an evidence-gated `grep`/`glob`/file-exists check with a
  `still-open` / `appears-DONE` / `manual` verdict. `appears-DONE` items surface
  as close-candidates at Step 1's existing combined prompt (when drift fires) or
  as a standing warning in the new Step 3 checklist row (when drift-clean).
  Verdicts never auto-close an item — removal always requires explicit user
  confirmation.

## [0.11.0] — 2026-07-01

### Added
- **`evidence-gate.sh` (Write|Edit, spec/plan files only).** Blocks a spec/plan write that mentions `smoke` and (a) mentions teardown/cleanup without stating the failure diagnostic is captured BEFORE that teardown runs, or (b) mentions a poll/wait loop without stating it watches both a success AND a failure signal. Enforces "never guess; preserve evidence" mechanically — teardown-on-fail and success-only polling both destroy the evidence a diagnosis needs. Override with `Evidence-gate: N/A — <reason>`.
- **`flaky-gate.sh` (Bash `git commit *`, and Write|Edit on `LEARNINGS.md`).** Blocks a commit message or LEARNINGS entry that calls a failure "flaky" / "transient" / a "CDN blip" without also naming the deterministic cause in a `Mechanism:` line. Enforces CLAUDE.md rule 1 — "an intermittent failure has a deterministic cause... never label a failure 'flaky' and move on." Override with `Flaky-gate: N/A — <reason>`.
- **`backend-parity-gate.sh` (Write|Edit, plan files only).** Blocks a plan write that frames its smoke coverage as multi-backend (mentions "backend"/"backends") but names fewer than two concrete backends (from a generic engine-name list: docker, apple, podman, containerd, colima, kata, lima, orbstack). Enforces "smoke must cover BOTH backends" — a runner proven on only one backend has an unverified half. Override with `Backend-parity: N/A — <reason>`.

### Compatibility
- Additive. `evidence-gate`/`backend-parity-gate` only act on `*/specs/*.md` + `*/plans/*.md` writes that already mention the relevant keyword (`smoke` / `backend(s)`); plans that never use those words are unaffected. `flaky-gate` only acts on `git commit` invocations and `LEARNINGS.md` writes that already say "flaky"/"transient"/"CDN blip". No migration. Upgrading installs gain all three gates on next session.

## [0.10.0] — 2026-06-17

### Added
- **`occurrence-gate` PreToolUse hook (change-the-odds #2).** Blocks a `Write`/`Edit` to a `LEARNINGS.md` that records the 2nd-or-later occurrence of a mistake-class (`Occurrence count: N of M`, N ≥ 2) without also naming an end-state `Invariant:` line. Enforces CLAUDE.md rule 4 — a class fixed across 2+ attempts must name its invariant, not ship another trigger-patch. Escape hatch: `Occurrence-gate: N/A — <reason>`.
- **`/session-continuity:spike-check` command (change-the-odds #3c).** Emits a five-question stand-in checklist at spike start so a spike is designed to exercise the real binary + auth/lifecycle/fixed-port path. Proactive complement to the `proven-gate` hook.
- **`/learning` occurrence-count + invariant fields.** The command now offers an `Occurrence count:` field and, when N ≥ 2, requires an `Invariant:` line — so entries are authored gate-compliant by construction.

### Compatibility
- Additive. The occurrence-gate only acts on `LEARNINGS.md` writes under a `.session-continuity/` or `docs/` path; all other files unaffected. Existing entries without an `Occurrence count:` line never trigger it. No migration. Upgrading installs gain the gate and command on next session.

## [0.9.0] — 2026-06-17

### Added
- **`proven-gate.sh` (Write|Edit, spec/plan files only).** Blocks writing a spec or plan that makes a "proven / verified / spike conclusive" claim unless the same content names, in two fields, what was actually tested: `Real path: <production code path that ran>` and `Stubbed: <what stood in — or "nothing">`. The `Stubbed:` field forces a stand-in into the open, where a no-auth stub standing in for the feature under test becomes visible to author and reviewer. Claim-words match on word boundaries (`unproven`/`improven`/`confirmed` do not trigger). Override with `Proven-gate: N/A — <reason>` for quoting, a glossary, or a doc about the gate. Turns the passive "prove the mechanism first" lesson into a mechanical gate.

### Compatibility
- Additive. Only acts on `*/specs/*.md` and `*/plans/*.md` writes; all other files unaffected. No migration. Upgrading installs gain the gate on next session.

## [0.8.0] — 2026-06-15

### Added
- **Fire-before-action PreToolUse gates.** Two new hooks make known guidance surface *before* an action, not after a symptom.
  - **`learnings-surface.sh` (Bash + Write|Edit).** A LEARNINGS entry may carry an optional `Trigger: <tool> /<regex>/` line directly below its `### N.` heading. When the imminent Bash command (or Write/Edit path + content) matches the regex, the hook injects a non-blocking reminder naming the entry, so the relevant hard-won lesson is read before the action runs. Entries with no `Trigger:` line never fire — zero noise.
  - **`smoke-gate.sh` (Write|Edit, plan files only).** Blocks writing a plan that mentions binary/engine/container work but either marks its smoke task optional/deferred/after-merge or has no smoke task at all. Override with an explicit `Smoke: N/A — <reason>` line. Enforces "every engine/binary feature needs a MANDATORY smoke task" mechanically, where a passive note had failed twice.
- **`/session-continuity:learning` optional Trigger field.** The command prompts for an optional trigger and emits the `Trigger:` line when supplied.

### Compatibility
- Additive. Existing LEARNINGS entries without `Trigger:` lines are unaffected; the smoke-gate only acts on plan-file writes. No migration. Upgrading installs gain the gates on next session.

## [0.7.0] — 2026-05-23

### Changed
- **`/session-continuity:end-session` prompt budget bounded.** End-of-session ritual now caps at ≤2 user prompts in the common case (one in Step 1 if drift exists, one in Step 2 if candidates surface). Previous flow could hit 3+N prompts on sessions with N captured learnings, fighting the user's explicit close-out intent.
  - **Step 1 single combined prompt.** The overlay "any close items?" question and the outstanding-items "anything to remove/add?" question are merged into one prompt covering both close-candidates and free-form edits. Same answer space — no information loss, half the round-trips.
  - **Step 2 batch confirm.** Pre-drafted LEARNINGS entries are presented together in one rendered block with one "stage all / revise N / skip N" prompt, replacing the per-candidate confirmation loop.

### Added
- **Step 4 terminal sign-off.** `/session-continuity:end-session` now always emits `✅ Session complete. Safe to close.` (or the `(Warnings above are advisory…)` variant if any ⚠️ appeared in the checklist) as the final line of the ritual. The user invoked an explicit close-out and must not be left ambiguous about whether the ritual is done. Required, non-omittable, never replaced with paraphrased prose.

### Compatibility
- Pure prose-skill changes. No new files, hooks, schemas, or path changes. Existing v0.6.x installs upgrade with no migration.

## [0.6.0] — 2026-05-21

### Added
- **§1 outstanding-items overlay in `/session-continuity:end-session` Step 1.** v0.5.1 surfaces commit subjects since the last primer refresh; v0.6.0 adds an overlay that flags subjects sharing ≥3 token stems with an open outstanding item ("may close item #N"). Stopwords and threshold are documented inline in the skill body so projects can tune them. Strictly a candidate list — never auto-closes.
- **§5 four LEARNINGS-candidate heuristics in `/session-continuity:end-session` Step 2.** Replaces the prose criteria from earlier versions with deterministic detectors:
  - **Heuristic A — retry burst:** ≥3 identical normalized Bash commands (excluding pure-read commands like `cat`/`ls`/`grep`).
  - **Heuristic B — revert / reset:** any of `git reset --hard`, `git checkout -- <path>`, `git revert`, `git restore`, or `rm -rf` against a tracked file.
  - **Heuristic C — error recurrence:** the same normalized error string ≥3 times across ≥15 minutes (timestamps from JSONL; falls back to count-only in context-window mode).
  - **Heuristic D — fix burst:** a `fix(...): ` commit preceded by ≥10 Bash calls within the prior 30 minutes.
- **Transcript-file input source for Step 2 heuristics.** Step 2 now prefers the session transcript at `~/.claude/projects/<url-encoded-cwd>/<session-id>.jsonl` when resolvable, falling back to context-window mode on any failure (missing dir, stale mtime, encoding mismatch). The fallback prints a "session context may be compacted" caveat under the candidate list so the user knows the recall is bounded.

### Changed
- **Step 2 presentation format.** Candidates now carry a `[heuristic-id]` tag and indented evidence bullets. The cap is 5 candidates per invocation — additional triggers print a "+N more not shown" line and ask the user to capture these first and re-run.
- **Privacy guidance.** Step 2's preamble now says explicitly: heuristic evidence paraphrases tool inputs and never quotes raw stdout/stderr beyond the first error line of a failing call.

### Compatibility
- Pure prose-skill addition. No new files, hooks, schemas, or path changes. Existing v0.5.x installs upgrade with no migration. Old primers without an `^## Outstanding items` heading silently skip the §1 overlay; the raw subject list (v0.5.1 behavior) still appears.

## [0.5.1] — 2026-05-21

### Changed
- **Drift detection.** `/session-continuity:primer` no longer uses the primer file's mtime as a freshness signal. Mtime is bumped by formatters, save-on-blur, and even `cat | tee`, so it produced false "fresh" reports on stale primers and false "stale" reports on untouched ones. The `git log --oneline -5` block diff against the primary branch is now the sole drift signal — it's content-based, deterministic, and matches the intent of the check.
- **Refresh mode is more useful.** Two additions to `commands/primer.md` Step 5 (refresh mode), inherited by `/session-continuity:end-session`:
  - **Test-count retry.** When the primer has a test-counts section, refresh now runs the test command up to 3× and pins to the count seen in ≥2 of 3 runs. Pre-0.5.1 a single sample on a flaky suite produced spurious drift alarms (saw 1162 / 1161 / 1162 → reported drift). If all three runs disagree, the spread is surfaced verbatim instead of a silently-picked number.
  - **"Activity since last refresh" candidate list.** Refresh now runs `git log <last-primer-commit>..HEAD --oneline` and presents the subjects to the user, prompting whether any close outstanding items or warrant a new LEARNINGS entry. Strictly a candidate list — the skill never auto-closes items based on subject heuristics.
- **`/session-continuity:learning` numbering is hardened.**
  - **Uniqueness guard.** Before computing the next number, the command scans for duplicate `### N.` headings. If any number appears twice, the command refuses to write and reports the offending pair so the user can fix the file before appending. Previously, manual edits could leave the file with duplicate numbers (#14, #15, #36, #37, #78 from earlier sessions in the wild) and the command would silently write a third entry with the same number.
  - **Max-across-all rather than "next-after-most-recent."** Step 4 now takes the true maximum of all parsed numbers. The previous "find the most recent and add 1" approach failed when an old entry was edited last.
  - **Auto-bumped footer.** The template's `*Last reviewed: <date>...` line is renamed to `*Last entry: <date> (#<N>)...` and updated automatically by the command. The old name implied a manual review pass that nobody actually performed; the new name reflects what the field has always tracked (timestamp of the last change).
- **`SessionStart` hook now emits a 4-line status block** alongside the existing read-the-primer reminder. Lists the current HEAD short-sha, the primer's last-modified timestamp, the count of outstanding items, and the count of LEARNINGS entries. Same information `/session-continuity:primer`'s Check mode reports — surfaced unconditionally on every session start so the user and Claude both see at a glance how fresh the in-repo state is. Best-effort: any probe that fails (shallow clone, missing file) prints `?` rather than aborting.

### Compatibility
- Pure refinements, no schema or path changes. Existing v0.5.0 installs upgrade with no migration step. The renamed footer in `templates/LEARNINGS.md` is regenerated by the next `/session-continuity:learning` invocation; old `Last reviewed:` lines in existing repo files are also recognized and rewritten in place.

## [0.5.0] — 2026-05-12

### Changed
- **Files relocated:** `SESSION_PRIMER.md` and `LEARNINGS.md` now live at `.session-continuity/SESSION_PRIMER.md` and `.session-continuity/LEARNINGS.md` instead of under `docs/`. The dot-prefixed directory signals these are tooling-managed artifacts and frees the project's `docs/` directory for first-class project documentation. Slash commands, hooks, templates, `SKILL.md`, and the public README/CONTRIBUTING/PRIVACY prose are all updated to reflect the new canonical location.
- **`/session-continuity:primer` gains a Migrate mode.** When the command detects files at the legacy `docs/` location and none at `.session-continuity/`, it runs `git mv` on both files (preserving git history), then falls through to refresh mode against the new path. Moves are staged but not committed — bundle them with your next substantive change. A new "Conflict mode" reports cleanly when files exist at both locations and exits without touching them.
- **`/session-continuity:learning`** and **`/session-continuity:end-session`** preflight checks recognize the legacy `docs/` layout and tell the user to run `/session-continuity:primer` first to migrate, rather than failing with an unhelpful "file not found" message.
- **Hooks transparently support both paths.** `hooks/session-start.sh` and `hooks/pre-commit-check.sh` look for the primer at `.session-continuity/` first, then fall back to `docs/`, so unmigrated repos keep getting the read-reminder and the `git commit` nudge while users migrate at their own pace. `pre-commit-check.sh` additionally excludes `.session-continuity/` from "code that warrants a primer-refresh nudge" — same treatment `docs/` already gets.
- **`marketplace-submission.md`** version bumped to 0.5.0 and prose updated to reference the new paths.

### Compatibility
- Existing v0.4 projects do not break on upgrade. The hooks keep working at the legacy location; running `/session-continuity:primer` once is the only action needed to migrate. The `docs/` fallback in hooks is intentional and will be kept for the foreseeable future (a future v1.0.0 can drop it once most users have migrated).

## [0.4.1] — 2026-04-28

### Fixed
- `/session-continuity:primer` init mode could commit literal `{{PLACEHOLDER}}` tokens when the user skipped the "fill in the blanks" step and went straight to `git commit`. Step 5/6 now wait for the user's answer and substitute `TBD` for any remaining `{{...}}` tokens before staging — `grep -n '{{' docs/SESSION_PRIMER.md docs/LEARNINGS.md` must return nothing after init completes. Caught by the v0.4.0 clean-machine acceptance test.
- `/session-continuity:end-session` Step 1 now waits for the user's answer to the "outstanding items — anything to remove or add?" prompt before applying edits. Previous prose let Claude proactively clear items it interpreted as stale.

### Changed
- `docs/LEARNINGS.md` gains entry #4 documenting the placeholder-leakage trap and its fix.

## [0.4.0] — 2026-04-28

### Added
- `.claude-plugin/marketplace.json` — single-plugin marketplace catalog, required for `/plugin marketplace add talgolan/session-continuity` + `/plugin install session-continuity@session-continuity` to work. Previous `claude plugins install github:...` form in the README was incorrect.
- `SECURITY.md` — scope, reporting instructions (GitHub Security Advisories), and design notes relevant to security reviewers.
- Detailed in-file comments across all three hook scripts and the release workflow, explaining the Claude Code hook contract, the JSON-parsing design choices, and the security boundaries.

### Changed
- **`hooks/hooks.json`** — `PreToolUse` hook now uses the per-hook `if: "Bash(git commit *)"` field so the script only spawns on actual `git commit` invocations (previously it fired on every `Bash` tool call). Docs: <https://code.claude.com/docs/en/hooks.md>.
- **`commands/end-session.md` Step 1** — now runs a silent drift check before prompting. If the primer's `git log --oneline -5` block already matches reality, the step is a no-op and the user is not asked about outstanding items. Previously every `/session-continuity:end-session` invocation prompted even on clean repos.
- **`hooks/version-check.sh`** — reads the repository slug from `.claude-plugin/plugin.json`'s `repository` field instead of hardcoding it, so renaming or transferring the repo no longer silently breaks the update check. Defensive regex validation on the parsed slug; hardcoded default is still present as a fallback.
- **`.github/workflows/release.yml`** — validates `GITHUB_REF_NAME` against a strict semver regex before letting it reach `awk`, and switches the awk match from regex (`~`) to `index()` (string-literal) so crafted tag names can never become pattern metacharacters.
- **`skills/session-continuity/SKILL.md` "Quick start"** — now tells Claude to run `/session-continuity:primer` rather than walking through a manual template-copy dance that bit-rotted after the plugin layout refactor.
- **`README.md`** — corrected install instructions (`/plugin marketplace add` + `/plugin install`), clarified the `PreToolUse` hook scope, and updated the Updating section to match.
- **`hooks/*.sh`** — added `set -o pipefail` alongside `set -eu`, and rewrote the headers with full rationale for each design choice (JSON-parsing via `grep`/`sed` vs `jq`, failure-mode contract, security notes).
- Repo layout: `docs/administrative/` and `docs/superpowers/` moved under a new top-level `meta/` directory. `docs/` now contains only the two files the plugin ships (primer + LEARNINGS), matching what users see in their own projects.

### Fixed
- Curly apostrophe (U+2019) in `skills/session-continuity/templates/SESSION_PRIMER.md` replaced with a straight `'` — the template is the canonical text Claude copies into user projects, so it should be free of unicode decoration (per the project's own style guidance).
- `docs/SESSION_PRIMER.md` path reference now correctly shows `.claude-plugin/plugin.json`, not `plugin.json`.

## [0.3.0] — 2026-04-28

### Added
- `/session-continuity:end-session` slash command — zero-arg close-out ritual. Step 1 refreshes the primer (sharing logic with `/session-continuity:primer`'s refresh mode), Step 2 reflects on session context to surface LEARNINGS candidates and appends any the user accepts (delegating to `/session-continuity:learning`'s append flow), and Step 3 emits a ✓ / ⚠️ checklist of staged / unstaged / untracked / unpushed state with a suggested commit message. The checklist enumerates every file from each `git` probe — summaries or "primary file" reductions are explicitly disallowed so nothing gets overlooked before close.

### Changed
- `README.md` lists the new command.
- `SKILL.md` plugin-affordances paragraph mentions the new command.

## [0.2.0] — 2026-04-27

### Added
- `/session-continuity:primer` slash command — init, refresh, or check the primer based on current state.
- `/session-continuity:learning` slash command — append a LEARNINGS entry interactively, with stable N+1 numbering.
- `SessionStart` hook — reminds Claude to read the primer on new sessions when `docs/SESSION_PRIMER.md` is present.
- `PreToolUse` hook on `Bash` — non-blocking nudge when `git commit` runs without primer refresh staged. Uses `hookSpecificOutput.additionalContext` JSON so the reminder reaches Claude's context (plain stdout is ignored for `PreToolUse`).
- Weekly freshness check inside `SessionStart` — one GitHub API call per 7 days per machine, opt-out via `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`.
- Auto-release workflow on tag push (`.github/workflows/release.yml`).
- `CHANGELOG.md`.

### Changed
- Restructured to Claude Code plugin layout. Skill now at `skills/session-continuity/SKILL.md`; templates at `skills/session-continuity/templates/`.
- Tightened `SKILL.md` `description` for marketplace display (~240 chars, down from ~450).
- `README.md` rewritten around plugin installation.
- `plugin.json` bumped to 0.2.0; added `homepage` and `repository` fields.

### Removed
- Empty `.cursor/` directory.
- "Choose a license" section in `README.md` (`LICENSE` already exists).

## [0.1.0] — 2026-04-26

Initial release. Two-file session continuity pattern: `docs/SESSION_PRIMER.md` (current state) + `docs/LEARNINGS.md` (append-only wisdom).
