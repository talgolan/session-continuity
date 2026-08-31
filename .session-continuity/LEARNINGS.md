# Learnings — session-continuity

This is a graveyard of subtle, painful bugs we've hit while building
session-continuity. Each entry is a recipe for a future engineer (or
future Claude) to avoid re-discovering what was expensive to discover
the first time. Entries are grouped by layer, most-painful-first
within each group.

---

## Symptoms index

<!--
  Fully derived — never hand-edit. The /session-continuity:learning
  command regenerates this list from every entry's **Symptom.** line
  each time it appends a new entry.
-->

- After GitHub squash-merged PR #20, `git merge --ff-only origin/main` failed with… — #15
- Clean-machine acceptance test for v0.4.0. `/session-continuity:primer` ran init mode cleanly, asked for… — #4
- Denied again, on the same file, despite the escape hatch already being… — #13
- Discovered when `/session-continuity:end-session` was invoked on this v0.6.0 session. The system-reminder injected… — #6
- Discovered while hardening the Step 2 transcript-extraction jq filter after a user… — #10
- Documented as an accepted tradeoff while designing the commit-time gates… — #14
- Every run of that one check silently wrote a real entry into… — #12
- In a live Claude session, the hook runs (verified via debug logs)… — #1
- Real invocation of `/session-continuity:primer` after installing the change failed every one of… — #11
- The `/session-continuity:end-session` smoke test had two staged files (primer + `src/foo.js`). The… — #3
- The Bash call is refused outright: "This session is isolated in the… — #8
- The first v0.2.0 release fired the workflow, created the GitHub Release, but… — #2
- The self-gate check returned rc=0 (allowed) — but via the escape hatch… — #7
- This repo moved everything to `meta/superpowers/` in v0.3 (per CHANGELOG: "Repo layout:… — #5
- Three hermetic smoke suites under `meta/superpowers/validation/` had fixtures hardcoded to the exact… — #9

---

## Claude Code plugin mechanics

### 11. `$CLAUDE_PLUGIN_ROOT` inside a bash fence in a skill/command file is never resolved — only the braced `${CLAUDE_PLUGIN_ROOT}` form is
Slug: plugin-root-brace-required
Trigger: Write|Edit /\$CLAUDE_PLUGIN_ROOT\//

**The trap.** `commands/primer.md` already used `${CLAUDE_PLUGIN_ROOT}/skills/...` (braced) in plain prose to reference a template file path, and that worked — Claude Code's own text templating resolves it to a literal absolute cache path before the model ever sees the command content. Natural assumption when adding NEW bash code that needs the same path: write `$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh` (unbraced, the way you'd reference any other shell variable inside a bash fence meant to run via the Bash tool) and expect the shell to expand it as an environment variable at execution time.

**Symptom.** Real invocation of `/session-continuity:primer` after installing the change failed every one of 11 `perf-log.sh` calls with `bash: /hooks/lib/perf-log.sh: No such file or directory` — the variable expanded to an empty string. `env | grep -i claude_plugin` inside the same Bash tool call confirmed the var is not exported to an agent-run Bash tool call at all.

**Fix.** Claude Code's template substitution only matches the exact `${VAR}` (braced) pattern in skill/command markdown, and it runs as a text-substitution pass over the file content — independent of, and not to be confused with, real shell variable expansion at execution time. `$CLAUDE_PLUGIN_ROOT` (unbraced) inside a bash fence is left as literal text for the shell to expand, and the shell never has it in its environment. Always use the braced form — `${CLAUDE_PLUGIN_ROOT}/...` — for any reference to the plugin root inside a skill or command file, whether in prose or inside a bash fence. A manual scratch-repo test that `export`s the variable yourself before running the block will pass even with the unbraced (broken) form — that masks the bug rather than catching it; the only way to catch this for real is to actually invoke the live slash command after updating/reloading the plugin.

**Diagnostic signal** *(optional)*. "No such file or directory" for a path that starts with `/` where you expected a variable to expand — check whether the reference used `$VAR` or `${VAR}` inside a skill/command markdown file specifically; the two are not interchangeable there the way they are in an ordinary shell script.

---

### 8. `git -C` and compound commands blocked inside a worktree-isolated session
Slug: worktree-compound-commands-blocked
Trigger: Bash /git\s+-C\s/

**The trap.** Once EnterWorktree switches a session into a worktree, it feels natural to keep using `git -C <other-path>` to peek at another checkout, or to chain several `cd`/`git` statements into one Bash call, the way you would outside a worktree.

**Symptom.** The Bash call is refused outright: "This session is isolated in the worktree <path>, but this command is too complex to verify that it stays inside the worktree; break it into plain, separate commands. Refusing to run it." Recurred 3 times over ~56 minutes this session, and the same constraint forced 7 separate single-line `cd <worktree-path>` prefixes elsewhere in the session to work around it.

**Fix.** Inside a worktree-isolated session, run every git/file command as a single plain statement operating on the current directory — no `-C` pointing elsewhere, no `&&`/`;`/multi-line chains the sandbox can't statically verify stay inside the worktree path. When a fresh shell context is needed, put a literal `cd <worktree-path>` on its own line as one Bash call, then issue the next command as a separate call.

**Diagnostic signal** *(optional)*. Bash error text containing "too complex to verify that it stays inside the worktree".

---

### 2. awk CHANGELOG range collapses on single-version files
Slug: changelog-awk-range-collapse
Trigger: * /release\.yml/

**The trap.** In the release workflow, extracting one version's CHANGELOG section with `awk "/^## \[${version}\]/,/^## \[/"` looks right — "print from the version header to the next version header." It works fine on multi-version files, so it's easy to ship.

**Symptom.** The first v0.2.0 release fired the workflow, created the GitHub Release, but the release body was "No CHANGELOG section for 0.2.0." The extraction had produced exactly one line (the header) which `sed '$d'` then stripped. CI logs looked green.

**Fix.** Use a state-machine awk that skips the header, copies lines until the next `## [` heading, then exits. Portable across gawk and BSD awk:

```bash
awk -v ver="$version" '
  $0 ~ "^## \\[" ver "\\]" { in_section=1; next }
  in_section && /^## \[/   { exit }
  in_section                { print }
' CHANGELOG.md
```

The original awk range fails because the same pattern matches both the start and end of the range when only one versioned section exists — the range collapses to a single line (the header), which `sed '$d'` then deletes.

**Diagnostic signal.** If your release body says "No CHANGELOG section for X.Y.Z" but the CHANGELOG clearly has that section, suspect the extraction before the CHANGELOG. Test locally by running the exact awk command against the real file before tagging.

---

<!-- Add entries here as they surface -->

---

## Slash command skill authoring

### 10. jq's `split("\n")[0]` returns `null` on an empty string — crashes the next `gsub` in a chain
Slug: jq-split-empty-string-null
Trigger: * /split\("\n"\)\[0\]/

**The trap.** `commands/end-session.md`'s Step 2 combined-extraction pass told Claude to write a `jq` filter that "adjusts to the file's actual JSONL schema" — prose, not a tested incantation. A user reported `/session-continuity:end-session` taking 20+ minutes; while diagnosing it, one contributing cause turned out to be a jq syntax-error retry: the natural way to grab an error's first line, `text | split("\n")[0] | gsub(...)`, throws `null (null) cannot be matched, as it is not a string` the moment `text` is empty. jq's `split` on `""` returns `[]`, not `[""]`, so `[0]` yields `null`, and the next `gsub`/`test`/`match` in the pipe crashes on it. Most tool_result entries in a real transcript have empty stderr, so this isn't a rare edge case — it's the common case.

**Symptom.** Discovered while hardening the Step 2 transcript-extraction jq filter after a user reported the slow close-out. Validated a combined `bash_calls`/`commits`/`errors` extraction against three real transcripts (2.9MB/173 calls up to 4.3MB/238 calls) and hit `jq: error (at <file>:N): null (null) cannot be matched, as it is not a string` on the very first real transcript tried — `N` was the last line of the file, jq's error location reports where input was exhausted, not the offending expression, so the message alone didn't point at the bug.

**Fix.** Guard empty/null before entering any `gsub`/`test`/`match` chain: `if (. == null or . == "") then "" else <chain> end`. More generally: never ship "adjust the filter to the schema" as unverified prose in a slash command that an agent will execute live — test the incantation against a real transcript file first and bake in the working version (now embedded verbatim in `commands/end-session.md`). Separately, the transcript JSONL schema itself varies across Claude Code versions — some tool_result lines carry a `toolUseResult.{stdout,stderr}` object, others carry only a `content` string prefixed `"Exit code N\n..."` with no `stderr` field at all — a filter that assumes one shape silently misses errors under the other rather than crashing, which is a worse failure mode.

**Diagnostic signal.** `jq -n '"" | split("\n")[0]'` returns `null`, not `""`. Any `gsub`/`test`/`match` fed from an unguarded `split(...)[0]` will crash with "null (null) cannot be matched, as it is not a string" on the first empty input it sees.

---

### 6. Stale path references in slash-command bodies survive plugin path migrations
Slug: stale-path-refs-survive-migration
Trigger: * /docs\/SESSION_PRIMER\.md|docs\/LEARNINGS\.md/

**The trap.** v0.5.0 relocated `docs/SESSION_PRIMER.md` + `docs/LEARNINGS.md` to `.session-continuity/`. The hooks (`session-start.sh`, `pre-commit-check.sh`), templates, top-level `SKILL.md`, and `commands/primer.md` were all updated. `commands/end-session.md` was *partly* updated — but its first paragraph still introduces the command as refreshing "`docs/SESSION_PRIMER.md`," its Step 0 preflight checks `docs/LEARNINGS.md`, its Step 1.5 stages `docs/SESSION_PRIMER.md`, its Step 2 capture flow stages `docs/LEARNINGS.md`, and its Suggested-commit pattern still says "Only `docs/` staged →." The slash command kept working because Claude reads the *actual* file via the `.session-continuity/` Step-0 heuristic added later — but the body's prose is misleading and the suggested-commit path rule is wrong for any v0.5.0+ install.

**Symptom.** Discovered when `/session-continuity:end-session` was invoked on this v0.6.0 session. The system-reminder injected by the slash-command hook contained the original (pre-v0.5.0) prose verbatim — `"Your job: run a close-out ritual that (1) refreshes docs/SESSION_PRIMER.md..."` — even though the on-disk `commands/end-session.md` was supposedly updated. Investigating revealed the v0.5.0 migration patched the *Step* references but not the introduction, summary, or path-pattern rules.

**Fix.** Grep every command-body file for the legacy path *as a substring*, not just the file references that look like file references. `git grep -n 'docs/SESSION_PRIMER\\|docs/LEARNINGS' commands/` should return zero matches in a fully-migrated repo. Update all hits to `.session-continuity/SESSION_PRIMER.md` / `.session-continuity/LEARNINGS.md`. The pre-v0.5.0 fallback for migration-detection lives only in `commands/primer.md` (Migrate mode) — every other reference should be canonical.

**Diagnostic signal.** Run `git grep -n 'docs/SESSION_PRIMER\\|docs/LEARNINGS' commands/`. If it returns hits outside `commands/primer.md`'s Step 2 (Migrate mode), the migration is incomplete.

---

### 5. Superpowers-style upstream skills hardcode `docs/superpowers/{specs,plans}/` and silently re-create deleted directories
Slug: superpowers-hardcoded-docs-path
Trigger: Write /docs\/superpowers\//

**The trap.** The `superpowers:brainstorming` and `superpowers:writing-plans` skills both default their output paths to `docs/superpowers/specs/YYYY-MM-DD-*.md` and `docs/superpowers/plans/YYYY-MM-DD-*.md`. Their skill bodies say "User preferences for spec location override this default" — but that override has to live somewhere Claude actually reads at every brainstorming invocation. A project that *moved* its agent meta-artifacts (e.g., to `meta/superpowers/`) and deleted the `docs/superpowers/` directory will have it silently re-created by the next brainstorming session, producing a duplicate-tree pair.

**Symptom.** This repo moved everything to `meta/superpowers/` in v0.3 (per CHANGELOG: "Repo layout: `docs/administrative/` and `docs/superpowers/` moved under a new top-level `meta/` directory"). Today's session ran `superpowers:brainstorming` followed by `superpowers:writing-plans`. Both wrote their artifacts to `docs/superpowers/specs/` and `docs/superpowers/plans/` — re-creating the deleted directory tree. Discovered when the user asked "why do we have 2 superpowers directories?" mid-PR-review.

**Fix.** Add a project-local `CLAUDE.md` at the repo root with an explicit override section. Example: a "Project conventions" section that lists the canonical paths (`meta/superpowers/specs/`, `meta/superpowers/plans/`, etc.) and tells Claude to redirect any `docs/superpowers/<x>/` suggestion to `meta/superpowers/<x>/` before creating the file. CLAUDE.md is loaded into context every session, so the redirect happens *before* the brainstorming/writing-plans skill defaults take effect.

**Diagnostic signal.** `find . -type d -name superpowers -not -path './node_modules/*'` should return exactly one path on a clean repo. Two paths means a brainstorming/writing-plans invocation defaulted past the project's CLAUDE.md override.

---

### 4. Init-mode commits can leak `{{PLACEHOLDER}}` tokens when the user skips ahead
Slug: init-mode-placeholder-leak
Trigger: Bash /git commit/

**The trap.** The primer command's init mode copies templates, fills in derivable fields, and "asks the user for the blanks." Reads fine. But the command prose doesn't say what Claude should do if the user *never answers* — pastes a `git commit` command or says "commit it" before filling in the blanks. Claude's default is to stage and proceed with the placeholders still present, so the committed file ends up containing literal `{{PACKAGE_1}}`, `{{ITEM_1_BODY}}`, etc.

**Symptom.** Clean-machine acceptance test for v0.4.0. `/session-continuity:primer` ran init mode cleanly, asked for the seven blanks, the user said `git commit -m "docs: init session continuity"` without answering. The commit landed (`a37b00c` in `/tmp/sc-accept`) with a primer full of `{{PLACEHOLDER}}` tokens — visible to anyone who later reads the file. No error, no warning, just a fresh user's first commit looking broken.

**Fix.** Tighten `commands/primer.md` Step 4/5 with an explicit fallback rule: *"For any `{{PLACEHOLDER}}` the user declines to fill in or hasn't answered, replace the token with `TBD` before staging. Never leave `{{...}}` syntax in a staged file."* The general lesson: any command that asks the user to supply values must define the fallback when the user skips — silence is a valid user response and the command needs to specify the resulting file state.

**Diagnostic signal.** After init mode runs to completion, `grep -n '{{' .session-continuity/SESSION_PRIMER.md .session-continuity/LEARNINGS.md` should return nothing. (On pre-v0.5.0 projects, the files live under `docs/`.) If it does, the init-mode prose missed a fallback path.

---

### 3. Checklist-style prose needs an explicit "enumerate, don't summarize" rule
Slug: checklist-enumerate-dont-summarize
Trigger: Write /commands\/.*\.md/

**The trap.** A slash command that instructs Claude to "emit a ✓ / ⚠️ checklist of the staged files from `git diff --cached --name-only`" reads like a complete instruction. It isn't. Claude's default is to *summarize* tool output when embedding it in a response — so if `git diff --cached` returns two files, the checklist row might still list only the "most relevant" one.

**Symptom.** The `/session-continuity:end-session` smoke test had two staged files (primer + `src/foo.js`). The bash probe output clearly showed both. The checklist row said `✓ Staged: docs/SESSION_PRIMER.md` — one file missing. No error, no warning, just silently elided.

**Fix.** Add an explicit anti-summarization directive at the start of the section that emits the structured output:

> "**List every file enumerated by the git commands — do not summarize, filter, or pick a 'primary' one.** If `git diff --cached --name-only` returns three files, the row lists all three."

Applies generally: any time command prose tells Claude to produce an inventory from tool output, the prose must say "every item" explicitly. Claude's implicit move is to pick a representative and move on.

**Diagnostic signal.** If your structured output has rows that look "summary-like" when the underlying data has multiple items, the instruction needs tightening. Stage more than one file during smoke tests to flush these out.

---

<!-- Add entries here as they surface -->

---

## Hook scripting (SessionStart / PreToolUse)

### 14. Commit-time content gates only see the git index — `git commit -a` / pathspec bypasses the scan
Slug: gate-index-only-staging-miss
Trigger: Bash /git commit (-a|--all)/
Flaky-gate: N/A — this entry names `flaky-gate.sh` as one of six hook script filenames sharing `gate-common.sh`, not as an unexplained-failure claim.

**The trap.** `hooks/lib/gate-common.sh`'s `gate_staged_files` (used by every commit-time content gate — `proven-gate.sh`, `smoke-gate.sh`, `evidence-gate.sh`, `backend-parity-gate.sh`, `occurrence-gate.sh`, and the sixth sharing this lib) reads `git diff --cached --name-only` — the index exactly as it stands the moment the `PreToolUse` hook fires. Typing `git commit -a` or `git commit <path/to/file.md>` looks, from the keyboard, exactly like committing that file — nothing visibly distinguishes it from a `git add <file> && git commit` the gate can actually see.

**Symptom.** Documented as an accepted tradeoff while designing the commit-time gates (`meta/superpowers/specs/2026-08-27-commit-time-content-gates-design.md`'s Tradeoffs section), not caught as a live false-negative in this repo: a staged spec/plan/LEARNINGS file carrying an unqualified gated claim (e.g. a bare "proven"/"verified" line lacking `Real path:`/`Stubbed:`) committed via `git commit -a` — which stages tracked modifications as part of the commit itself, after the hook already read the index — or via `git commit <pathspec>` — which commits that path without the gate's `--cached` name-only scan ever covering it — reaches the repo with zero gate scan. `pre-commit-check.sh`'s existing non-blocking nudge has the identical index-only blind spot; this isn't a new failure mode, just a new hook family that inherits it.

**Fix.** Accepted as a documented permissive limitation rather than fixed: every gate already errs toward allowing on any ambiguity (miss, never a false block on a save), so a `-a`/pathspec miss is consistent with the whole design's error-handling posture, not an oversight. Mitigation considered and rejected: a git-native `.git/hooks/pre-commit` would see the real final commit contents regardless of how staging happened, but it requires installing/managing a git hook per user repo, risks colliding with hooks already present there, and this machine's `~/.githooks` slot is already occupied by a separate global docs-current setup — too heavy for a limitation that hasn't caused a real incident yet. Prefer `git add <file>` followed by a plain `git commit` (no `-a`, no pathspec) when staging a file one of these gates cares about, until the miss actually bites hard enough to justify the heavier fix.

**Related check, same change (verified, not a second incident).** Each gate sources `hooks/lib/gate-common.sh` via `source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"`, and `hooks/lib/perf-wrap.sh` launches each gate as `bash "$HOOKS_DIR/<gate>.sh"` — a real file invocation, not a second `source`. So `${BASH_SOURCE[0]}` inside the gate script correctly resolves to the gate's own path (not `perf-wrap.sh`'s) whether the gate runs directly or through the timing wrapper, and the relative `lib/gate-common.sh` lookup holds in both cases. Confirmed by reading `perf-wrap.sh`'s invocation and by the full hermetic suite passing gate-by-gate when run through the wrapper.

**Diagnostic signal** *(optional)*. A content-gate violation lands in a commit despite the gate script itself being correct and its hermetic tests green — before doubting the gate logic, check whether the commit used `-a`/`--all` or a bare pathspec instead of committing an already-`git add`-staged tree.

---

### 12. A smoke test's own hermeticity bug recurred twice, in two unrelated tasks, even after being caught and fixed once
Slug: smoke-hermeticity-recurs-across-tasks
Trigger: Write /validation\/.*smoke.*\.zsh/

**The trap.** A smoke test's "real-gate regression check" (invoking a wrapper against an actual gate hook, to prove wrapping doesn't change block/allow behavior) gets written as a plain `bash "$wrap" "$gate_hook"` call, without first `cd`-ing into the test's own hermetic temp repo — because the stub-script loop two lines above it already does `cd "$work" && bash "$wrap" ...`, and it's easy to assume the surrounding function/script context still applies to a later call in the same file.

**Symptom.** Every run of that one check silently wrote a real entry into the actual project repo's own `.session-continuity/performance.log`, modified the real `.gitignore`, and created a real marker file — none of it inside the temp dir, none of it caught by the test's own "hermetic" self-description in its header comment. This happened twice: once when the check was first written (caught in task review, fixed with a `cd "$work" &&` wrapper), and again — independently, in a different, later fix to the same underlying script — when a controller ran a manual verification step outside the hermetic harness entirely.

**Fix.** Hermeticity isn't a property you fix once and trust forever in a file with more than one place that shells out to the thing under test — every single invocation of the wrapped command, anywhere in the test file (or in ad-hoc manual verification during a later fix), needs its own explicit `cd "$work" &&` (or equivalent), not just the first one written. When reviewing or re-reviewing a "hermetic" smoke test, check every invocation individually rather than trusting the file's header comment or the fact that one earlier block does it correctly. After running any manual verification step against a real checkout, always `git status --short` before moving on — don't just check `rc=0`.

**Diagnostic signal** *(optional)*. `git status --short` shows changes to files a task's diff never touched, right after running "hermetic" tests or manual verification — that's stray real-repo pollution from a test/verification step that forgot to `cd` into its own temp dir.

---

### 13. `proven-gate.sh` (and similar word-boundary content gates) re-fire on an `Edit` even when a valid escape-hatch line already exists elsewhere in the same file
Slug: edit-scope-misses-escape-hatch
Trigger: Edit /specs\/.*\.md|plans\/.*\.md/

**The trap.** A spec/plan file already has a `Proven-gate: N/A — <reason>` escape-hatch line near the top (added once, after the first denial). Later in the same session, an incremental `Edit` to a different part of the same file mentions the hook by name again (e.g. `proven-gate.sh`) — reasonable to expect the existing escape hatch still covers the whole document.

**Symptom.** Denied again, on the same file, despite the escape hatch already being present — 4 times across one session, on both `Write` and `Edit` calls to the same two files.

**Fix.** `proven-gate.sh` (like other `PreToolUse` content gates in this plugin) reads its payload's `content` field for a `Write`, but its `new_string` field for an `Edit` — an `Edit`'s payload never contains the rest of the file, so an escape-hatch line written earlier is invisible to the gate on a later incremental edit to the same file. `Write` (which sends the full file content) stays covered once the hatch line exists anywhere in the document; `Edit` does not. When an incremental `Edit` to an already-hatched file re-triggers the same gate, either (a) rewrite that specific chunk to avoid the trigger word/phrase, or (b) fall back to a full-file `Write` for that change so the existing hatch line is back in scope. See also [[self-referential-gate-check]] — a related but distinct failure mode in the same family of content gates (that one is about a hatch string matching *by accident*; this one is about a real hatch line being *invisible* to a scoped edit).

**Diagnostic signal** *(optional)*. The same file gets denied by the same gate more than once in one session despite an escape-hatch line already being present — check whether the denied write was an `Edit` (scoped) rather than a `Write` (whole-file).

---

### 9. Removing a hook's legacy-path scope breaks hermetic smoke fixtures hardcoded to that path — and a release shipped before anyone re-ran them
Slug: legacy-scope-removal-breaks-smoke-fixtures
Trigger: Bash /git tag v[0-9]/
Flaky-gate: N/A — this entry names the occurrence-gate and flaky-gate hook scripts as filenames touched by the underlying bug, not as an unexplained-failure claim.

**The trap.** v0.14.0 dropped the pre-v0.5.0 `docs/` legacy fallback from `hooks/session-start.sh` and two of the PreToolUse gate hooks. Each change was verified with `bash -n`, shellcheck, and a targeted manual grep against a scratch fixture — all clean. That felt like enough, so the release was tagged and pushed on that basis.

**Symptom.** Three hermetic smoke suites under `meta/superpowers/validation/` had fixtures hardcoded to the exact legacy-path scope just removed. Four assertions across those suites failed with `(expected '*deny*'/'*Ask the user*', got: )`. Not caught by the release process; caught only when a user reported a real behavioral regression (SessionStart's outstanding-items list collapsing to unnumbered prose) in a *different* repo running the already-installed plugin.

**Fix.** `bash -n` + shellcheck + one manual scratch test verify syntax and one happy path — they do not verify the full behavior contract a hermetic suite already encodes. After changing any hook's scope or matching logic, run **every** smoke `.zsh` file under `meta/superpowers/validation/`, not just the one for the hook touched — a scope change in one hook's path convention is exactly the kind of change whose blast radius crosses files. Run the full set, confirm every suite reports zero failures, *then* tag.

**Diagnostic signal** *(optional)*. A hermetic assertion failing with `(expected '*X*', got: )` — an empty actual — right after a scope-narrowing change is the signature: the fixture is now outside the hook's new scope and needs its own update (or an explicit new "now out of scope" case), not a real regression in the new code.

---

### 7. A grep-based gate cannot reliably scan a plan that documents the gate's own syntax
Slug: self-referential-gate-check
Trigger: Write /smoke-gate|plans/.*\.md/

**The trap.** The `smoke-gate` hook blocks plan writes whose smoke task is tagged optional/deferred, and offers a `Smoke: N/A — <reason>` escape hatch. Natural assumption: run the gate against this very plan as a dogfood check and expect a clean MANDATORY-smoke pass. But a plan that *documents the gate* contains the gate's own trigger strings — both the weak-smoke fixtures (`smoke runner (optional, after merge)`) and the literal `Smoke: N/A — <reason>` hatch text appear in the prose.

**Symptom.** The self-gate check returned rc=0 (allowed) — but via the escape hatch matching the documented `Smoke: N/A — <reason>` string, NOT via the plan's MANDATORY marker. Absent that incidental hatch match, the same plan would have been DENIED on its documented weak-smoke fixtures. A green result that means the opposite of what it looks like.

**Fix.** Accept that grep gates are fooled only by meta-documents (plans *about* the gate). Real engine/feature plans contain neither weak-smoke fixtures nor hatch-prose, so the gate is correct there (proven by the hermetic runner, 12/12). Do NOT tighten the hatch to line-start anchoring to "fix" the meta-plan — that flips it to a false-positive deny, blocking legit work over documentation noise. The loose hatch is the right trade: an accidental opt-out requires writing the literal declaration string, which doesn't happen outside meta-docs. Verify gate behavior with the hermetic fixture runner, not by self-scanning a plan that quotes the gate.

**Diagnostic signal** *(optional)*. A self-referential gate check passes "for free" — re-read WHY it passed (which branch fired), don't trust the rc.

---

### 1. PreToolUse hooks must emit JSON to reach Claude's context
Slug: pretooluse-json-contract
Trigger: Write /hooks/.*\.sh|hooks\.json/

**The trap.** `SessionStart` hooks inject plain stdout into Claude's context — that's documented, straightforward, and works on the first try. When writing a `PreToolUse` hook, it's natural to reach for the same pattern: print a `<system-reminder>` block to stdout, exit 0. Bash-level smoke tests show the reminder firing. Looks done.

**Symptom.** In a live Claude session, the hook runs (verified via debug logs) but Claude never sees the reminder. `git commit` proceeds silently without Claude surfacing the nudge at all. No error, no skipped-hook warning — the output just goes to `/dev/null` from Claude's perspective.

**Fix.** `PreToolUse` (unlike `SessionStart`) does NOT treat plain stdout as additional context. You must emit a JSON object with `hookSpecificOutput.additionalContext`, with exit code 0, and `permissionDecision: "allow"` to remain non-blocking:

```bash
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"⚠️ ..."}}
EOF
exit 0
```

Plain stdout from `PreToolUse` is written only to debug logs, never injected. Source: https://code.claude.com/docs/en/hooks.md (sections "stdout Context Injection" and "Decision Control with JSON Output").

**Second trap — valid shape, invalid JSON (2026-08-12).** Emitting the right
keys is not the same as emitting parseable JSON. `proven-gate` and `smoke-gate`
built the object with `printf` and interpolated a reason containing a literal
`"` — `Stubbed: <what stood in, or \"nothing\">` in one, a `\"${offender}\"`
wrapper around a captured line in the other. The string terminates early, the
payload does not parse, and the author sees a parse error where the reason
should be. The gate still blocks, so nothing unsafe is written; it is
undiagnosable, which reads as a broken tool.

Both hooks' runners were green throughout, because they assert with
`[[ "$out" == *deny* ]]`. The substring `deny` is present in malformed output
too, so the assert measures a proxy, not the invariant. The smoke-gate case
arrived in v0.12.1 — in the change whose stated purpose was to make denials
diagnosable by echoing the matched line.

**Invariant:** every JSON object a hook writes parses. Enforced in
`meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh`, which
pipes each gate's deny output through a real parser and fails when a
`hooks/*-gate.sh` has no fixture. When you add a gate, add a fixture. Assert on
parsed structure, never on a substring of serialized output.

**Diagnostic signal.** If a hook's bash smoke tests emit text correctly but Claude ignores it in a live session, the hook's event type probably has a different contract than `SessionStart`. Check the hooks.md matrix before assuming plain stdout works.

---

<!-- Add entries here as they surface -->

---

## Git / release mechanics

### 15. Squash-merging a branch descended from an unpushed local commit orphans that commit — and any tag pointing at it
Trigger: Bash /gh pr merge.*--squash/
Slug: squash-merge-orphans-unpushed-tag

**The trap.** Squash-merging a PR whose branch descends from a local-only
commit that was never pushed looks safe — GitHub computes the diff
against the PR branch's actual tip, so nothing appears to go missing.
It doesn't account for a tag created earlier pointing directly at that
unpushed commit.

**Symptom.** After GitHub squash-merged PR #20, `git merge --ff-only
origin/main` failed with "not possible to fast-forward" even though
`git status --short` was empty and there was no other local branch in
play. Tracing it: the squash commit's diff (computed against
`origin/main`'s base) silently absorbed an unpushed local commit's
changes, since that commit wasn't part of `origin/main`'s history yet
— orphaning the commit itself, and the `v0.18.0` git tag that had been
pointing at it.

**Fix.** `git reset --hard origin/main` to resync local `main` (safe
once `git status --short` confirms nothing uncommitted). To repair an
orphaned tag: delete and recreate it against the correct ancestor
(`git tag -d vX.Y.Z && git tag -a vX.Y.Z <correct-sha> -m "..."`),
force-push (`git push origin :refs/tags/vX.Y.Z && git push origin
vX.Y.Z`), and verify via `gh release view vX.Y.Z` that the GitHub
Release re-associates. To prevent it: push every local commit before
merging any PR whose branch might descend from it.

**Diagnostic signal** *(optional)*. `git merge --ff-only origin/<branch>`
fails with "not possible to fast-forward" immediately after a
squash-merge despite a clean working tree — check `git merge-base
--is-ancestor <suspect-commit> origin/main` to confirm orphaning.

---

## Security incidents

<!-- Log security-adjacent events here: leaked credentials (names only,
NEVER values), access control mistakes. Never record actual secret values. -->

---

## Anti-patterns we were tempted by (and rejected)

<!-- This section is for "we thought X would work, we tried X, here is
why X is wrong." Each entry names the anti-pattern, explains the appeal,
and explains why it loses. -->

---

## Checklist for a fresh dev-env setup

1. `claude plugins install github:talgolan/session-continuity`
2. Open a scratch project and run `/session-continuity:primer` to verify init mode.
3. Make a small change and run `/session-continuity:end-session` to verify close-out.

---

*Last entry: 2026-08-30 (#15). Add new entries at the top of each section
as they surface. The `/session-continuity:learning` command bumps this
line automatically (v0.5.1+). Rule of thumb: if a bug takes more than
15 minutes to diagnose, it goes here.*

*Numbering note: new entries take the next available number (N+1) and
are placed at the top of their section. Old entries keep their numbers
so historical references ("see #7 above") stay valid even when the
visual order no longer matches numeric order.*
