# Per-repo performance logging — design

Date: 2026-08-17
Status: approved (pending user spec review)

Proven-gate: N/A — this spec names `proven-gate.sh` as a test target in
the Testing section below; it makes no proven/verified claim about the
performance-logging feature itself (nothing here is implemented yet).

## Problem

The plugin has no record of how long its own operations take. When a
session feels slow, there's no data to say whether it's the shipped
hooks (`hooks/*.sh`), or a slash command's heavier steps (test-count
reruns in `primer.md`/`end-session.md`, outstanding-item verification
loops in `end-session.md`). "Improve performance" first needs "measure
performance" — this spec covers only the logging mechanism, not any
analysis/reporting on top of it.

## Scope

- **In scope:** time (and, for slash commands, retry/rerun and
  item-count fields) per shipped hook invocation and per named
  batched-bash-call unit within `primer.md`/`end-session.md` (see
  Mechanism 2 for the exact list — not every `## Step N` heading gets
  one), written to a per-repo log.
- **Out of scope (deferred):** token accounting (input/output/cache
  tokens per operation) — feasible via the session transcript's
  `usage` blocks, but only at per-command-invocation granularity, not
  per-step (transcript turns don't align 1:1 with markdown steps). No
  summary/report command — reading the raw log (`bat`/`jq`/`grep`) is
  the only consumer for now.

## Storage

`.session-continuity/performance.log` in the target repo (the repo
where the plugin is running, not this plugin's own repo). Append-only
JSONL, one event per line. Gitignored — this is local operational
telemetry, not the project documentation this plugin otherwise commits
(`SESSION_PRIMER.md`, `LEARNINGS.md`, `PROJECT_CONTEXT.md` stay
committed; this file doesn't).

The writer ensures a `.gitignore` entry exists in the target repo,
checked cheaply on every write without shelling out to `git
check-ignore` each time:
- On each `record` call, first check for a marker file
  `.session-continuity/.gitignore-ensured`. If present, skip the
  gitignore step entirely (no subprocess).
- If absent: append the literal line
  `.session-continuity/performance.log` to the target repo's
  `.gitignore` (create the file if absent; skip the append if the
  exact line is already there via a plain string check, not `git
  check-ignore`), then create the marker file so every subsequent
  write short-circuits.
- This keeps the steady-state cost of every log line at one `mkdir -p`
  + one `[ -f marker ]` check + one append — no per-write git
  subprocess, which would otherwise cut against the very
  hook-overhead reduction this session already did earlier (moving
  docs-current checks from pre-commit to post-merge).
- Only the specific file is ignored, not the whole
  `.session-continuity/` directory, since that directory also holds
  files meant to be committed.

No retention/rotation. JSONL lines are small (~100-200 bytes); left
unbounded per explicit decision — revisit only if it becomes a real
problem.

## Schema

One JSON object per line:

```json
{"ts":"2026-08-17T18:32:10Z","source":"hook","name":"session-start.sh","duration_s":0.42,"exit":0}
{"ts":"2026-08-17T18:41:10Z","source":"command","name":"end-session","step":"step-1-refresh-the-primer","duration_s":38.1,"retries":2,"items":5}
```

Fields:
- `ts` — ISO 8601 UTC timestamp, written at event completion.
- `source` — `"hook"` or `"command"`.
- `name` — hook script filename (e.g. `session-start.sh`) for
  `source: hook`; command slug (`primer` / `end-session` / `learning`)
  for `source: command`.
- `duration_s` — wall-clock seconds, always present.
- `exit` — hook exit code. Present only for `source: hook`.
- `step` — a slug naming the specific batched-bash-call unit within a
  command (NOT simply the `## Step N` heading it lives under — see
  Mechanism 2 for why, and the exact list of named units per command).
  E.g. `step-1-outstanding-items-verification`,
  `step-4-test-count-rerun`. Present only for `source: command`.
- `retries` — integer count of a retry/rerun loop the step performed.
  Applies to exactly one loop per command: the test-count flakiness
  recheck (capped at 3 tries) in `primer.md` Step 4 and
  `end-session.md` Step 1. Omitted (not zeroed) on every other step.
- `items` — integer count of outstanding items evaluated during
  `end-session.md` Step 1's outstanding-items verification loop
  (the per-item still-open/appears-DONE/manual classification pass —
  distinct from the `retries` loop above; both can appear on the same
  Step 1 log line since Step 1 contains both loops). Present only on
  that one step, everywhere else omitted. Reuses the existing item
  counter that loop already tracks — no new bookkeeping.

## Mechanism 1 — shipped hooks (wrapper, not inline)

New `hooks/lib/perf-wrap.sh <script-name> [args...]`:

1. Resolve `$CLAUDE_PLUGIN_ROOT/hooks/<script-name>`.
2. Record start time as `START_S=$(date +%s.%N)`. If `date +%s.%N`
   isn't available (no GNU date), fall back to whole-second
   resolution: `START_S=$SECONDS` (bash's built-in elapsed-seconds
   counter, reset to 0 at shell start) and compute duration at the end
   as `$SECONDS - $START_S` (integer seconds) instead of the
   floating-point subtraction used in the `date` path. Both paths
   produce a plain decimal `duration_s`; only the precision differs.
3. Exec the real script with the same args, stdin, and stdout/stderr —
   no capturing, no modification. The wrapper does not read or alter
   the hook's own output (`hookSpecificOutput` JSON, exit-code
   semantics for gates such as `proven-gate.sh` must pass through
   untouched).
4. On return, compute duration per the method chosen in step 2, call
   `hooks/lib/perf-log.sh record --source=hook --name=<script-name>
   --duration=<n> --exit=<real-exit-code>`.
5. Re-exit with the real script's exit code (the wrapper must not
   change gate/block behavior).

`hooks/hooks.json` changes from:
```json
{ "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh" }
```
to:
```json
{ "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh session-start.sh" }
```
for every entry (all 10 shipped hooks: `backend-parity-gate.sh`,
`evidence-gate.sh`, `flaky-gate.sh`, `learnings-surface.sh`,
`occurrence-gate.sh`, `pre-commit-check.sh`, `proven-gate.sh`,
`session-start.sh`, `smoke-gate.sh`, `version-check.sh`). Uniform
across all of them — no hand-picked subset, since the marginal cost of
timing a cheap hook is near-zero and hand-picking is exactly the kind
of special-casing this plugin's own outstanding-items list already
flags as a defect elsewhere (global docs-current hooks, item 5).

No changes to the 10 hook scripts themselves.

## Mechanism 2 — slash commands (self-reported)

**Correction from the first draft of this section:** timing cannot
bracket a `## Step N — <Title>` heading uniformly. The Bash tool's
shell state does not persist across separate tool calls (only cwd
does — confirmed against this harness's own tool description), and a
`## Step N` heading routinely spans several independent Bash calls
plus Read/Write calls plus, in several steps, a prompt that blocks on
a human reply. A `STEP_START` variable set in one Bash call is gone by
the next Bash call; bracketing a step that includes a user-wait would
also count human reply time as "operation time," which contradicts
the point of this feature (finding slow *operations*).

**Corrected mechanism:** timing brackets exactly the units that are
already, or become, a single Bash tool call doing real batched work —
matching this repo's own existing convention (see the v0.14.4
CHANGELOG entry mandating single-Bash-call batching for exactly this
reason). The timer start, the real work, and the `perf-log.sh record`
call all live inside the *same* Bash code fence, so there is no
cross-call variable to lose. Steps that are pure Read/Write/user-prompt
— nothing bash executes — are not instrumented at all: there is no
operation there to time, only model or human latency, which is out of
scope the same way token accounting was deferred earlier in this spec.

This does NOT instrument every `## Step N` heading uniformly. It
instruments every existing (or newly-batched) single-Bash-call
operation, named after the sub-flow it belongs to. Concretely, per
command file:

**`primer.md`:**
- `step-1-detect-state` — Step 1's three checks, batched into one Bash
  call.
- `step-2-init-derive-placeholders` — Step 2.5's derived-placeholder
  lookups (git log, pwd, package.json read), batched into one Bash
  call. The rest of Step 2 (template copies, user prompt, staging) is
  not instrumented.
- `step-4-git-log-refresh` — Step 4.2's git-log block regeneration,
  its own Bash call.
- `step-4-test-count-rerun` — Step 4.3's test-count check, with
  `--retries=<n>` (the flakiness recheck, 0-2), its own Bash call.
- `step-4-activity-surface` — Step 4.4's activity-since-last-refresh
  query, its own Bash call. Three separate units, not one merged
  call, because items 4.2/4.3/4.4 are three separate numbered steps in
  the source file — item 4.3 sits between 4.2 and 4.4, so a variable
  set in 4.2's Bash call would not survive to 4.4's (shell state
  doesn't persist across separate tool calls). Each unit recomputes
  whatever it needs itself rather than relying on a sibling unit's
  output.
- `step-5-check-mode` — Step 5's report-gathering commands, batched
  into one Bash call.
- Step 3 (Split mode) is NOT instrumented — it's a Read/sort/Write
  content move with no real bash batch worth timing.

**`end-session.md`:**
- `step-1-fast-path` — the existing 3-command batch (already shown as
  one Bash call in the file).
- `step-1-outstanding-items-verification` — the existing "batch every
  item's check into one Bash call" verification pass, with
  `--items=<n>` (count of outstanding items classified — reuses the
  count that loop already produces).
- `step-1-drift-test-rerun` — the drift check's git-log diff plus the
  test-count rerun, with `--retries=<n>` (same scope as primer's
  equivalent).
- `step-2-transcript-extraction` — the transcript-file-mode combined
  extraction pass (the jq-based parse the v0.14.4 CHANGELOG entry
  describes handling up to 4.3MB / 238 Bash calls in the transcript).
  Likely candidate for real slowness given this session's stated
  intent — this is the heaviest single operation in the plugin.
- `step-3-gather-facts` — Step 3's "Gather the facts" batched command.
- Step 0, the refresh flow's interactive prompt/staging, and Step 4
  are NOT instrumented — no real bash batch, or dominated by
  user-wait.

**`learning.md`:** NOT instrumented. Every step is Read/Edit/prompt
driven; there is no batched bash operation to time (Step 8's `git add`
is a single sub-second command, not worth a log line). Adding brackets
around Read/Edit calls would log wall-clock time that's actually model
or human latency, misrepresenting it as plugin operation cost.

**Shape of the instrumentation**, added directly inside the existing
(or newly-introduced) Bash code fence for each named unit above:
```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
# ... the unit's existing real work runs here, unchanged ...
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command \
  --name=<command-slug> --step=<step-slug> --duration="$_PERF_DURATION" \
  [--retries=<n>] [--items=<n>]
```
`awk` is used for the float subtraction (already used elsewhere in
this repo's hooks; no `bc` dependency). When `--retries`/`--items` are
included, the value comes from a counter the unit's own existing logic
already computes in that same script — no new bookkeeping.

This is genuinely self-reported: correctness depends on the agent
including these exact lines in the Bash call it runs for that unit. No
enforcement mechanism beyond that exists in this spec (same trust
level the primer/end-session instructions already place on the agent
for everything else they do).

## Mechanism 3 — shared writer

`hooks/lib/perf-log.sh` — single script, one `record` subcommand, used
by both the wrapper and the command instructions:

- Resolves the target repo root (`git rev-parse --show-toplevel`);
  no-ops silently if not in a git repo (matches the existing hooks'
  pattern of silent no-op outside a repo).
- `mkdir -p .session-continuity` if absent.
- Ensures the `.gitignore` entry via the marker-file check described
  in the Storage section (no per-write `git check-ignore` subprocess).
- Appends one JSONL line built from its flags to
  `.session-continuity/performance.log`.
- Never fails loud: a logging failure (disk full, permissions) prints
  to stderr and returns 0 — this must never be the reason a hook
  blocks a commit or a command errors out. Performance logging is
  observability, not a gate.

## Testing plan (not yet executed — nothing in this spec is implemented)

- Run `perf-wrap.sh` against a trivial stub script with known exit
  codes (0, 1, 2) and check the wrapper's own exit code and
  stdout/stderr pass through unchanged, and that a log line with
  matching `exit` and plausible `duration_s` gets appended.
- Run `perf-wrap.sh` wrapping `proven-gate.sh` against a fixture that
  should block, and check the block still happens (exit code
  preserved) — this is the one regression risk in this whole design
  (wrapper accidentally swallowing or altering exit codes) and needs
  explicit coverage.
- `perf-log.sh record` directly: check JSONL append, gitignore
  marker-file idempotency (run twice, one line added to `.gitignore`
  and one marker file created, not duplicated), and silent no-op
  outside a git repo.
- Manual: run `/session-continuity:primer` and
  `/session-continuity:end-session` in a scratch repo, check the named
  units from Mechanism 2 appear with plausible durations, that
  `retries` appears only on `step-4-test-count-rerun` /
  `step-1-drift-test-rerun`, and that `items` appears only on
  `step-1-outstanding-items-verification` with a count matching the
  primer's actual outstanding-items list length. Confirm `learning.md`
  produces no log lines at all.

This plugin doesn't yet have a fixture-repo test harness (outstanding
item 3, `meta/superpowers/recommendations/`) — this feature's tests
are added as more manual/scripted checks in the same vein as existing
validation, not blocked on that harness landing first.
