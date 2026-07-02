# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
