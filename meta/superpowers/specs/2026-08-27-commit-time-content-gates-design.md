# Design — commit-time content gates + false-trigger reduction

Proven-gate: N/A — design doc about the gates; records no runtime claim, nothing stubbed.

Date: 2026-08-27
Status: approved (brainstorming), pending implementation plan
Scope: session-continuity plugin, `hooks/`

## Problem

The five **content gates** — `proven-gate.sh`, `smoke-gate.sh`,
`evidence-gate.sh`, `backend-parity-gate.sh`, `occurrence-gate.sh` —
fire as `PreToolUse` `Write|Edit` hooks. A `permissionDecision:"deny"`
blocks the tool call, so the file **never reaches disk**. Two harms:

1. **Wasted effort.** A blocked Write means the authored content is
   lost; the model must re-derive and re-emit it. Observed live: a
   grounding scratch file was blocked four times in a row by
   `proven-gate.sh`, each attempt re-writing ~180 lines. Blocking the
   *commit* is legitimate; blocking the *save* is not.
2. **False triggers on throwaway work.** All four blocks hit a
   dot-prefixed `.…-GROUNDING.md` scratch file explicitly marked
   "delete once the plan is written" — a file that was never going to
   be committed. A gate that only ran at commit time would never have
   seen it.

Two secondary false-trigger causes surfaced in the same session:

- The escape line `> **Proven-gate:** N/A — …` was rejected. The
  escape regex requires `Proven-gate:` immediately followed by
  whitespace then `N/A`; the markdown `**` between the colon and the
  value breaks the match. Only a bare, undecorated line cleared it.
- Claim words (`verified`) matched anywhere in body prose, including a
  legitimate provenance sentence ("verified the signature by reading
  the source"), not just an actual proven-class assertion.

## Goal / invariant

**A content gate must never block a file from being saved. It may
block a commit.** Every path that reaches "commit a spec/plan/LEARNINGS
file carrying an unqualified gated claim" is denied at commit time;
no path that merely writes such a file to disk is blocked.

## Decisions (from brainstorming)

- **Scope:** all five content gates move to commit-time (not just
  `proven-gate`).
- **`git commit -a` / pathspec miss:** accepted as a documented
  permissive limitation (see Tradeoffs). Not worth a git-native hook.
- **Shared code:** factor the duplicated logic into a sourced
  `hooks/lib/gate-common.sh` helper rather than copy-paste per gate.

## Approach (selected)

Pure commit-time staged-content scan. Each content gate gains a commit
mode: on `Bash(git commit *)`, it enumerates the staged file set,
filters to its own glob, reads each staged blob from the index, runs
its existing claim/field check, and denies the commit — naming the
offending file — on the first violation. The `Write|Edit` branch is
removed from these gates entirely, so writes always succeed.

Rejected alternatives:

- **Hybrid write-time advisory + commit-time block** — doubles code
  paths per gate; the write-time advisory is noise while iterating.
  YAGNI.
- **Git-native `.git/hooks/pre-commit`** — correct for `-a`/pathspec
  but requires installing and managing git hooks in user repos,
  collides with existing hooks, and `~/.githooks` is already occupied
  by the user's global docs-current setup. Too heavy; noted as future
  escalation only if the permissive miss ever bites.

## Components

### `hooks/lib/gate-common.sh` (new, sourced)

Single home for what the gates duplicate today plus the new commit-scan
primitives:

- `gate_field <key>` — extract a scalar string field from the JSON
  payload (the current `grep -oE … | sed` idiom).
- `gate_decode` — un-escape `\n \t \" \\` from a captured raw value
  (the current `sed -E 's/\\n/\n/g; …'` idiom).
- `json_escape` / `deny` — verbatim from the existing gates (LEARNINGS
  #1 output contract; backslash-then-quote escaping; C0 fold to space).
- `gate_cwd` — pull the payload `cwd` field. Deliberately NOT
  `$CLAUDE_PLUGIN_ROOT`; mirrors `pre-commit-check.sh`'s note that for
  plugin installs the env var points at the plugin dir, not the user
  repo.
- `gate_staged_files` — `git -C "$cwd" diff --cached --name-only`
  (index-only; empty on any git error → silent allow).
- `gate_staged_blob <path>` — `git -C "$cwd" show ":$path"` (the staged
  index version of the file, not the worktree copy).
- `gate_is_scratch <path>` — true when the basename begins with `.`
  (dot-prefixed scratch) → skip.
- `gate_has_escape <text> <Label>` — **normalize then match**: strip
  leading `>`, `#`, and whitespace and inline `*`/`` ` `` around the
  label, then match `Label:[[:space:]]*N/A[[:space:]]*(—|--)[[:space:]]*[^[:space:]]`.
  Fixes the `**Proven-gate:**` decoration break for all gates at once.

Each gate keeps only its distinct logic: its glob, its claim-word
match, and its required-field check.

### Per-gate commit mode

On payload, resolve `tool_name`:

- **`Bash`** — extract the command; require it to match `git commit`;
  `gate_cwd`; `gate_staged_files`; filter to the gate's glob; for each
  matching path, skip if `gate_is_scratch`, else read
  `gate_staged_blob`, run `check_text`. On the first violation, `deny`
  with a reason that **names the staged file**. No violation → silent
  `exit 0`.
- **`Write|Edit`** — removed from the four spec/plan + occurrence
  gates. (See flaky-gate exception below.)

Globs by gate (unchanged semantics, now applied to staged paths):

| Gate | Glob |
|---|---|
| proven / smoke / evidence / backend-parity | `*/specs/*.md`, `*/plans/*.md` |
| occurrence | `LEARNINGS.md` under `*/.session-continuity/*` |

### `flaky-gate.sh` — stays dual

`flaky-gate` is the one gate that also inspects the commit **message**
(a "flaky"/"transient"/"CDN blip" claim in the message text, not a
file). It keeps that message check and, additionally, gains the
staged-`LEARNINGS.md` content scan that replaces its old `Write|Edit`
branch. So its `Bash` branch runs both checks; its `Write|Edit` branch
is removed.

### `hooks/hooks.json` rewire

- **Remove** from the `Write|Edit` matcher: `smoke-gate`,
  `proven-gate`, `occurrence-gate`, `evidence-gate`,
  `backend-parity-gate`, `flaky-gate`. Leave `learnings-surface.sh`
  (non-blocking `additionalContext` surface, not a block — unaffected).
- **Add** to the `Bash(git commit *)` block: `proven-gate`,
  `smoke-gate`, `evidence-gate`, `backend-parity-gate`,
  `occurrence-gate`. `pre-commit-check` and `flaky-gate` are already
  there.
- All continue to route through `hooks/lib/perf-wrap.sh` for timing.

## False-trigger reduction (Problem 2)

1. **Commit-time firing** is itself the dominant fix: scratch/grounding
   files that are written and deleted are never committed, so they are
   never scanned. The observed four-block scenario cannot recur.
2. **Decoration-tolerant escape line** via `gate_has_escape` (above).
3. **Dot-prefixed skip** via `gate_is_scratch` — defense-in-depth for
   the rare case a `.foo.md` is actually staged.
4. **Instruction** — `SKILL.md` documents (a) that content gates now
   enforce at commit time, not on save; (b) the escape hatch and that
   it accepts markdown decoration; (c) the `Real path:` / `Stubbed:`
   convention proven-gate expects — so an author meets the requirement
   before hitting the wall. Each gate's `deny` reason names the file
   and notes the decoration-tolerant escape line.

The gate deliberately does **not** try to distinguish provenance-prose
("verified by reading source") from a proven-class assertion via
smarter regex — that is fragile whack-a-mole. The escape hatch, now
trivial to apply, is the sanctioned override for legitimate non-claim
uses.

## Error handling

- Empty payload, missing `tool_name`, missing `cwd`, `cwd` not a
  directory, non-`git commit` Bash command, git error, empty staged
  set, no matching staged file → silent `exit 0` (allow). The gate errs
  toward allowing; the commit-time position means a miss fails to block
  rather than blocking a save.
- Malformed staged blob content → best-effort scan; the escape hatch is
  the override, so an imperfect read is safe (same posture as the
  current best-effort decode).

## Testing

- Rewrite the six hermetic runners under `meta/superpowers/validation/`
  (`…-{proven,smoke,evidence,flaky,backend-parity,occurrence}-gate-smoke.zsh`)
  to drive the commit-time path: create a temp git repo, stage a
  fixture spec/plan/LEARNINGS file, emit a `Bash git commit` JSON
  payload with `cwd` pointing at the temp repo, run the gate through
  `perf-wrap.sh`, and assert deny/allow. Factor the temp-repo +
  payload-builder setup into a shared test helper.
- New cases per gate: violation staged → deny naming the file; escape
  line (bare **and** decorated) → allow; dot-prefixed staged file with a
  violation → allow (skipped); no matching staged file → allow;
  non-`git commit` Bash → allow.
- Update `…-hook-json-contract-smoke.zsh` for the matcher move (gates
  now assert their deny JSON parses under the `Bash` payload shape).
- `shellcheck` clean on `gate-common.sh` and all five gates.
- Verify `source "$(dirname "$0")/lib/gate-common.sh"` resolves
  correctly when the gate is launched via `perf-wrap.sh <gate>.sh`
  (i.e. `$0` is the gate's real path). This is the one runtime
  unknown — the implementation plan must probe it, not assume it.

## Docs / version

- `plugin.json` → **0.17.0** (behavior change: gates enforce at commit,
  not on save).
- CHANGELOG `[0.17.0]` entry.
- `skills/session-continuity/SKILL.md` — commit-time enforcement, escape
  hatch (decoration-tolerant), `Real path:`/`Stubbed:` convention.
- `.session-continuity/LEARNINGS.md` — entry for the `-a`/pathspec
  permissive miss and the `$0`-under-`perf-wrap` sourcing check.
- Primer refresh (Current state + outstanding items) staged in the same
  commit as the change.

## Tradeoffs (accepted)

- **`git commit -a` / pathspec permissive miss.** `diff --cached` sees
  only the index; `-a` stages tracked mods at commit time (after the
  `PreToolUse` hook fires) and `git commit <path>` bypasses the index.
  A gated claim committed that way is not caught. This is a *permissive*
  failure — it fails to block, never blocks a save — and matches the
  existing `pre-commit-check.sh` limitation. Documented; not mitigated
  in this change.
- **No write-time immediacy.** Authors no longer see the requirement
  the moment they write; they see it at commit. This is the intended
  effect of the goal invariant (saves are never blocked).
