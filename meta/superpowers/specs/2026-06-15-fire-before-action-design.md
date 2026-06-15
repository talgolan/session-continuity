# Fire Before the Action — session-continuity v0.8.0

## Problem

The plugin's two memory artifacts are **read-after-symptom cures**, not
**read-before-action gates**:

- `LEARNINGS.md` is indexed by symptom. An entry is only greppable once you
  already *have* the symptom — i.e. after you've hit the rake. The 2026-06-12
  itb session repeated two already-documented mistakes (#124: smoke SUT
  `dist/itb` ≠ dev `~/.local/bin/itb`; #106/#115: piped `grep` inside `verify`'s
  `eval` mangles patterns) because nothing forced reading the relevant entry at
  decision time.
- The "every engine/binary feature needs a MANDATORY smoke task" rule lives in a
  passive memory note. The 2026-06-15 itb plan marked its smoke runner "Task 7
  (optional, after merge)" — the **second** session to do so. A passive note has
  now failed twice.

Both failures share one root, identical to CLAUDE.md rule 4: **a cure on the
happy path doesn't hold the invariant on every path.** Knowing a rule ≠
executing it. The fix is not a better-written note (writing entry #142 didn't
prevent the repeat) — it is a **mechanical gate that runs every time the action
is taken.**

The plugin already owns the right seam: `hooks/pre-commit-check.sh` is a
PreToolUse hook that fires before `git commit`. Both fixes are new PreToolUse
hooks built on the same JSON contract.

## Goals

1. **Retrieval/enforcement (outcome 1).** A known LEARNINGS entry surfaces keyed
   on the *action about to be taken*, before the artifact is produced — not only
   greppable once you have a symptom.
2. **Mandatory-smoke gate (outcome 2).** The plan-authoring flow REFUSES a plan
   for an engine/binary-touching feature unless it carries a smoke task marked
   MANDATORY (never optional/deferred/after-merge).

Both are mechanical PreToolUse gates. Neither relies on the model remembering.

## Non-goals

- No semantic understanding of "is this feature engine-touching" — a shell hook
  cannot judge that. Outcome 2 keys on **mechanical, greppable** signals that
  catch the exact failure that recurred, plus a keyword heuristic.
- No edits to the third-party `writing-plans` superpowers skill (cache dir,
  overwritten on update). Enforcement lives in *this* plugin's hook, which fires
  whenever a plan file is written — plugin-native, durable.
- No new runtime dependency (no `jq`). Existing hooks parse stdin with `grep`/
  `sed`; we keep that.

## Component A — LEARNINGS retrieval hook

### Entry trigger syntax

Any LEARNINGS entry MAY carry an optional machine-matchable line, placed
immediately under the `### N. Title` heading:

```
### 124. smoke SUT dist/itb != ~/.local/bin/itb
Trigger: Bash /smoke|SUT_BIN|run\.zsh/
**The trap.** ...
```

- Form: `Trigger: <tool> /<pattern>/` where
  - `<tool>` ∈ `Bash` | `Write` | `Edit` | `*` (any).
  - `<pattern>` is an extended-regex (`grep -E`) tested against the action's
    match-text.
- Match-text per tool:
  - **Bash** → the `command` string.
  - **Write / Edit** → `file_path` + the written/new content concatenated.
- An entry with no `Trigger:` line never fires (zero noise from un-tagged
  entries). Multiple entries may match one action; all matches surface.

### `hooks/learnings-surface.sh`

PreToolUse hook registered on `Bash` and on `Write|Edit`.

1. Read stdin payload. Extract `cwd` (same minimal regex as existing hooks).
2. Resolve LEARNINGS path: `$cwd/.session-continuity/LEARNINGS.md`, legacy
   `$cwd/docs/LEARNINGS.md` fallback. Absent → silent `exit 0`.
3. Extract the imminent action's tool name + match-text from the payload
   (`tool_name`, and `tool_input.command` for Bash / `tool_input.file_path` +
   `tool_input.content` | `tool_input.new_string` for Write/Edit).
4. For each `### N.` entry that has a `Trigger:` line: if the trigger's tool
   matches (or is `*`) AND the pattern matches the match-text, collect
   `(N, title, fix-line)`.
5. No matches → silent `exit 0`. Matches → emit one JSON object,
   `permissionDecision: "allow"` (non-blocking), `additionalContext` listing
   each matched entry: `"⚠️ LEARNINGS #N may apply: <title>. Read the full entry
   before proceeding."`

Cheap: one pass over a few-hundred-line file, only on `Bash`/`Write`/`Edit`.
Non-blocking by design — surfacing, not vetoing; the model decides.

### `/learning` command change

Step 2 (gather recipe) gains an optional **Trigger** field:

> "Trigger *(optional)* — a regex over the command or file-path that should
> resurface this entry before such an action runs. E.g. `Bash /smoke|run\.zsh/`.
> Skip if none applies."

Step 5 (compose entry) emits the `Trigger:` line immediately under the heading
when supplied; omits it otherwise. The line is plain text, no effect on the
numbering/uniqueness logic.

### Template change

`skills/session-continuity/templates/LEARNINGS.md` entry #1 gains a commented
example `Trigger:` line so new projects discover the syntax.

## Component B — smoke-gate hook

### `hooks/smoke-gate.sh`

PreToolUse hook registered on `Write|Edit`, self-scoped to **plan files**:
proceed only when `file_path` matches `*/plans/*.md` OR basename matches
`*plan*.md`. Any other path → silent `exit 0`.

Reads the content being written (`tool_input.content` for Write,
`tool_input.new_string` for Edit). Two block conditions (both enforced):

1. **weak-smoke** — content mentions `smoke` (case-insensitive) AND any line
   containing `smoke` also matches `/optional|deferred|after.?merge|nice.to.have/i`.
   Catches the exact recurring failure ("Task 7 — smoke (optional, after merge)").
2. **engine-keyword, no-smoke** — content matches
   `/binary|engine|container|daemon|--compile|bun build/i` AND contains no
   `/smoke/i` mention at all.

On either condition → emit JSON `permissionDecision: "deny"` with a reason that
names the rule and the fix:

- weak-smoke → `"Smoke task is marked optional/deferred. Engine/binary features
  need a MANDATORY smoke task — part of done, never deferred. Re-mark it
  MANDATORY (or declare 'Smoke: N/A — <reason>' if this plan genuinely touches
  no binary/engine)."`
- no-smoke → `"This plan mentions binary/engine/container work but has no smoke
  task. Add a MANDATORY smoke task to the plan (or declare 'Smoke: N/A —
  <reason>' if it genuinely touches no binary/engine)."`

### Escape hatch

Per CLAUDE.md "explicit skip-with-reason": the gate passes (silent `exit 0`,
before evaluating either block condition) if the content contains a line
matching `Smoke: N/A — <reason>` (em-dash or `--`, followed by non-empty text).
Forces an explicit, recorded justification rather than silent omission. A bare
`Smoke: N/A` with no reason does NOT satisfy the hatch.

### Hook ordering

`smoke-gate.sh` (can `deny`) and `learnings-surface.sh` (only `allow`) both match
`Write|Edit`. Claude Code runs all matching PreToolUse hooks; a single `deny`
blocks. A weak-smoke plan write is denied even though the learnings hook would
allow — correct: the hard gate wins.

## Cross-cutting

- **Version** `0.7.0 → 0.8.0`. Bump `.claude-plugin/plugin.json` +
  `marketplace.json` (version-sync pre-commit guard enforces parity). CHANGELOG
  entry.
- **`hooks/hooks.json`** gains two PreToolUse registrations (Bash + Write|Edit
  for learnings-surface; Write|Edit for smoke-gate). The existing `git commit`
  filter is untouched.
- **SKILL.md** documents the `Trigger:` syntax and the smoke-gate (what it
  blocks, the `Smoke: N/A — <reason>` hatch).
- **README** mentions the two new gates under the hooks section.

## Testing (this plugin smokes itself)

The smoke rule applies recursively — this change touches the plugin's executable
hooks, so it gets a MANDATORY smoke runner. A `.zsh` runner under
`meta/superpowers/validation/` drives each hook script with crafted stdin
payloads:

- **learnings-surface**: (a) Bash command matching a `Trigger:` → JSON
  `additionalContext` cites the entry; (b) command with no match → empty stdout,
  `exit 0`; (c) Write content matching a `Write` trigger → fires; (d)
  un-tagged-only LEARNINGS → silent.
- **smoke-gate**: (a) plan with "smoke (optional)" → `deny`; (b) plan with
  engine keyword + no smoke → `deny`; (c) plan with MANDATORY smoke task →
  silent allow; (d) plan with `Smoke: N/A — pure-docs change` → silent allow;
  (e) non-plan path (e.g. `src/foo.ts`) with weak content → silent (out of
  scope).

Hooks are pure stdin→stdout shell scripts, so the smoke runner is a fast,
hermetic, no-container harness — payloads in, JSON asserted out.

This plan's own spec names a smoke check (this section), so the change satisfies
its own smoke-gate.
