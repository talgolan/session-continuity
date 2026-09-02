# Fresh-install count defects — Implementation Plan (Phase 0)

Proven-gate: N/A — this is an unexecuted implementation plan. Every task's
checkboxes are unchecked. The two reproductions below describe a prior
investigation's evidence for why the tasks are needed, not a claim that any
change in this plan works.

Real path: the plugin's own counting expression, `grep -cE '^### [0-9]+\.'`,
run against the five shipped files in
`skills/session-continuity/templates/` and against a no-match fixture, on this
machine.
Stubbed: nothing.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a freshly initialized project reports zero backlog items and zero
learnings, and the entry count it reports comes from one place rather than
three divergent expressions.

**Architecture:** One new helper, `hooks/lib/count-entries.sh`, becomes the
single definition of "how many entries does this file have" — comment-aware and
fence-aware, printing one integer, printing `0` for a missing file. Its two
current callers, `hooks/session-start.sh` and `commands/primer.md`'s check
mode, are rewritten to call it. The two shipped templates stop carrying
headings that match the count pattern.

**Tech Stack:** bash, POSIX awk, zsh for the smoke runners.

**Spec:** `meta/superpowers/specs/2026-09-02-determinism-program-design.md`
(Phase 0). This plan is independent of every other phase and can ship alone.

## The two reproductions

**R1 — the shipped templates already contain countable entries.**
`templates/LEARNINGS.md:31` and `:60` are live exemplar headings
(`### 1. {{ENTRY_TITLE}}`, `### 2. {{ENTRY_TITLE}}`), and
`templates/BACKLOG.md:31` is `### 1. [a3f9] …` inside an `<!-- Example: -->`
block, which the count expression matches regardless. Counts measured against
the shipped files: LEARNINGS = 2, BACKLOG = 1. `commands/primer.md:127` then
sweeps `{{…}}` to `TBD`, leaving `### 1. TBD` and `### 2. TBD` — still
countable. A fresh project therefore reports "Backlog: 1, Learnings: 2" for
zero real entries, from both `primer.md` check mode and the SessionStart
banner that every session prints.

**R2 — `grep -c … || echo 0` emits two values at zero count.**
`grep -c` prints `0` and exits 1 when nothing matches, so the `||` branch also
fires. Measured on a no-match fixture, the substitution yields two lines, both
`0`, and the model reading `primer.md:330-331` picks one. `session-start.sh:68-69`
and `:77-78` already avoid this correctly with `|| true` plus a `${var:-0}`
default — the fix exists three files away and was not applied to the command.

A third, read-only finding rides along: `primer.md:186-187` tells Step 3b it
may write into "the existing empty-skeleton file from Init mode if one was just
created by Step 2/Step 3 above," but Init mode (64-69) creates `BACKLOG.md`
and has never created `OUTSTANDING_ITEMS.md`. The referenced file cannot exist.

## Why a shared helper rather than editing the templates alone

Changing `### 1.` to `### N.` in the two templates fixes today's count and
leaves the class intact: the next example entry written with a real digit, in
a comment or a fenced block, reintroduces it. Per CLAUDE.md rule 2 the minimum
change is the one that holds the invariant going forward, so the counting rule
moves into one comment-and-fence-aware helper that every caller uses. The
templates are fixed as well, because a shipped template that miscounts is its
own defect regardless of who counts it.

**Invariant:** an entry count reported to the user counts only headings that
are live document content — never a heading inside an HTML comment or a fenced
code block — and it is computed by exactly one expression in the codebase.

This pulls one piece of the spec's Phase 3 (a status function shared by
`session-start.sh`, `primer.md`, and `doctor.md`) forward on purpose. Phase 3
keeps the rest: the mtime, SHA, and report assembly.

## Global Constraints

- `count-entries.sh` carries `# CONTRACT_VERSION=1` and follows
  `hooks/lib/learnings-index.sh`'s conventions: a missing or unreadable file
  prints `0` and exits 0 (bad input is not an error), and it never writes.
- No new runtime dependency: bash and POSIX awk only.
- `session-start.sh` must keep its existing fail-soft behavior. It runs on
  every session start, and a hook that errors is worse than a hook that
  reports `?`.
- The helper prints an integer and nothing else — no label, no newline
  decoration — so callers can substitute it directly.

---

### Task 1: `count-entries.sh`

**Files:**
- Create: `hooks/lib/count-entries.sh`
- Test: `meta/superpowers/validation/2026-09-02-count-entries-smoke.zsh`

**Interfaces:**
- Produces: `count-entries.sh <file>` → one integer on stdout, exit 0.
  Consumed by Tasks 2 and 3.

- [ ] **Step 1: Write the failing test first**

Fixtures, each asserting an exact integer:

- This repo's real `.session-continuity/LEARNINGS.md` → `15`, and
  `.session-continuity/BACKLOG.md` → `7`. These are the regression anchors:
  the helper must agree with the current correct answer on real files.
- Each shipped template → `0`. This assertion fails before Task 4 and passes
  after; it is the point of the task.
- A heading inside an `<!-- … -->` block → not counted.
- A heading inside a ``` fence → not counted.
- A heading inside a fence that is itself inside a comment → not counted.
- An unterminated comment or fence at end of file → everything after the
  opener is not counted, and the helper still exits 0.
- A missing file, an unreadable file, and an empty file → `0`.

Preserve the failing diagnostic in the run log before teardown, and have every
failure message carry the expected and actual integers.

- [ ] **Step 2: Implement**

An awk pass tracking two independent states — inside-comment and inside-fence —
counting `^### [0-9]+\.` only when both are false. Handle a comment that opens
and closes on one line. `grep` cannot do this, which is why the expression it
replaces is wrong.

---

### Task 2: Rewrite `session-start.sh`'s two call sites

**Files:**
- Modify: `hooks/session-start.sh` (the learnings count at 68-69, the backlog
  count at 77-78)
- Test: `meta/superpowers/validation/2026-08-12-session-start-smoke.zsh`

- [ ] **Step 1: Clear the blocked suite first**

`2026-08-12-session-start-smoke.zsh` currently fails 7 of 17 assertions on a
clean tree, against a pre-v0.22.0 contract — this is BACKLOG item 6 `[6258]`,
already investigated and filed. It is not possible to confirm this task
without a green suite, so fixing it is part of this task rather than a
prerequisite someone else does later: rewrite the stale fixtures to use
`BACKLOG.md`, matching the hook's actual current behavior of always emitting
the migration nudge when `OUTSTANDING_ITEMS.md` is present. Close item `[6258]`
in Task 5.

- [ ] **Step 2: Substitute the helper**

Resolve the helper next to the hook (`$(dirname "$0")/lib/count-entries.sh`),
not through `CLAUDE_PLUGIN_ROOT`, so the hook keeps working when run directly
by the test harness. If the helper is missing, fall back to the current `?`
placeholder rather than failing the hook.

- [ ] **Step 3: Add assertions for the fresh-install case**

A fixture whose `.session-continuity/` holds the two shipped templates
verbatim must produce `Backlog: 0` and `Learnings: 0` in the emitted
`<system-reminder>`, and must not emit the backlog shortlist block at all —
the block is conditional on non-empty output from the heading grep at
`session-start.sh:79`, which Task 4 changes the input to.

---

### Task 3: Rewrite `primer.md` check mode

**Files:**
- Modify: `commands/primer.md` (lines 322-346, and the stale reference at
  186-187)

- [ ] **Step 1: Replace the two grep lines**

Lines 330-331 become two `count-entries.sh` calls, which removes the
double-zero at zero count and the ERE/BRE inconsistency between them in one
edit. Guard the call with `require-script.sh`, matching how `learning.md`
Step 4 already calls `learnings-index.sh`.

- [ ] **Step 2: Fix the stale cross-reference**

Lines 186-187 reference an `OUTSTANDING_ITEMS.md` skeleton Init mode never
creates. Delete the clause. Do not "fix" it by making Init mode create the
file — the file is the format this repo migrated away from in v0.22.0.

---

### Task 4: Fix the two templates

**Files:**
- Modify: `skills/session-continuity/templates/LEARNINGS.md` (lines 31, 60)
- Modify: `skills/session-continuity/templates/BACKLOG.md` (line 31)

- [ ] **Step 1: Make the exemplar headings uncountable at the source**

The helper from Task 1 already excludes `BACKLOG.md:31`, since it sits inside
an `<!-- Example: -->` block. `LEARNINGS.md:31` and `:60` are live content,
so they need a change: either move the exemplar entry inside a comment block
like `BACKLOG.md`'s, or renumber the headings to a non-digit placeholder. Both
satisfy the helper; choose based on which reads better as guidance to someone
filling the template in, and apply the same shape to both files so they stop
differing for no reason.

Confirm afterwards that `count-entries.sh` returns `0` for all five templates,
which is the Task 1 assertion that was failing.

---

### Task 5: Release bookkeeping

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json` (`0.25.1` → `0.25.2`)
- Modify: `.session-continuity/BACKLOG.md` (close item 6 `[6258]`)
- Modify: `.session-continuity/SESSION_PRIMER.md`

- [ ] **Step 1: Changelog and patch bump**

A patch release: two user-visible bug fixes and one new internal helper, no
behavior change to any command's contract.

- [ ] **Step 2: Close item `[6258]`, and grep before deleting**

Item 6 `[6258]` is resolved by Task 2 Step 1. Per `BACKLOG.md`'s own rule,
grep the repo for the tag before deleting the item; a hit means fix the
referencing text or leave a one-line closed stub. This plan is itself such a
reference, so expect at least one hit and leave the stub.

- [ ] **Step 3: Refresh the primer in the same commit**

Per the plugin's own rule, the primer refresh rides along with the
substantive change rather than landing as its own commit.

## Smoke coverage (MANDATORY)

Two runners, both required green before the release: the new
`2026-09-02-count-entries-smoke.zsh` from Task 1, and the repaired
`2026-08-12-session-start-smoke.zsh` from Task 2, which must go from 7 failing
assertions to zero. A count fix that cannot be confirmed on the hook path that
prints the count to the user every session is not confirmed at all.

## Out of scope

- The shared status assembly (mtime, SHA, report rendering) that
  `session-start.sh`, `primer.md` check mode, and `doctor.md` each implement
  separately. That is the spec's Phase 3.
- `doctor.md`, which reports file existence but no entry counts, and so is
  untouched by either reproduction.
