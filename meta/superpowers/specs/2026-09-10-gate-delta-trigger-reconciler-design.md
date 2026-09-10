# Design — Gates trigger on the commit's delta, satisfy against the document

**Supersedes the fix half of:**
[`meta/superpowers/plans/2026-09-10-gate-escape-hatch-and-smoke-scope-fix.md`](../plans/2026-09-10-gate-escape-hatch-and-smoke-scope-fix.md)
**Builds on:** [`2026-09-10-gate-escape-hatch-and-smoke-scope-eval.md`](2026-09-10-gate-escape-hatch-and-smoke-scope-eval.md)
**Amends:** [`2026-08-27-commit-time-content-gates-design.md`](2026-08-27-commit-time-content-gates-design.md)

Real path: every behavior claimed below was measured against the shipped
hooks at `14d5f17` — the real `gate_load` / `gate_scan_staged` driver, real
`git init` repos, real staged blobs, real PreToolUse payloads, and real
`git diff --cached` output under varied git config.
Stubbed: the Claude Code hook runner (payloads built by
`meta/superpowers/validation/lib/gate-test-common.zsh` rather than emitted by
Claude Code), and the original architect-workbench document (a fixture of the
same shape stood in).

Evidence-gate: N/A — this document is about the gates; its "smoke", "poll" and
"teardown" mentions are quoted regexes and test-case names, not a smoke design.

## Context

Seven commit-time content gates share one driver. Each `gate_check` receives
the whole staged blob and greps it twice: once for a trigger word that stands
in for "this document makes claim X," once for the field that would satisfy
the claim. Both greps scan the entire file.

Two consequences, both reproduced:

- A document is re-litigated in full on every commit that touches it. The
  original architect-workbench report was an unrelated one-paragraph addition
  denied for prose that was already in the file and had already passed.
- Word presence is a proxy for a semantic claim, so "smoke" in one sentence and
  `pollRoute.test.ts` in a table row, thirty lines apart, reads as a
  success-only poll in a smoke design.

The same shape sits in all seven gates. `backend-parity-gate` fires on one
occurrence of "backend" anywhere; `proven-gate` on one occurrence of "proven."

Five of the seven also carry a near-identical local patch — `gate_mask_escape`
plus a comment explaining that the gate's own hatch label matches its own
trigger regex. Five independent rediscoveries of one bug.
`evidence-gate.sh` never got the patch and does not currently need it, only
because "Evidence-gate" contains none of its trigger words.

`occurrence-gate`'s own denial text quotes CLAUDE.md rule 4 at the author: a
class fixed across two or more attempts needs an invariant enforced at the
reconciler, not another trigger-patch. This design applies that rule to the
gates themselves.

## Problem

Every fix so far has been applied per gate, at the trigger. There is no place
where the rule "what may a gate fire on" is enforced once for all of them.

## Invariants

1. **Trigger on the delta, satisfy on the document.** A gate fires only when
   the commit's own changes contain a trigger, and it looks for satisfying
   evidence anywhere in the document. Prose you did not touch can never
   condemn your edit; evidence that lives fifty lines away still counts.
2. **Deleting evidence counts as a change.** Removing a satisfying field while
   leaving the claim in place must re-arm the gate.
3. **On a denial, a hatch attempt is never silent.** If the gate denies and a
   near-miss hatch line exists in the staged blob, the denial names that line
   and states the accepted form. Near-miss alone never flips allow → deny
   (and never produces a denial when the gate would otherwise allow).
4. **No gate can forget the self-condemnation mask.** It is applied by the
   driver, before any gate's claim scan sees content. Accepted hatches are
   short-circuited by the driver before `check_fn` runs.
5. **The allow/deny verdict is a pure function of the repository.** Not of the
   user's git config, locale, or working tree. Worktree / chained-command
   text in denials is best-effort diagnostic only and never participates in
   the verdict.

## Decisions (locked)

| Decision | Choice |
|---|---|
| Where the rule lives | `gate_scan_staged` / new helpers in `hooks/lib/gate-common.sh`; no per-gate reimplementation of delta or masking |
| Trigger API | `gate_triggered [-w] TRIGGER_ERE [SAT_ERE…]` — true if added lines match `TRIGGER_ERE` (`-w` ⇒ `grep -Eiqw`, for proven), **or** removed lines match any `SAT_ERE` (invariant 2) |
| Satisfaction greps | Still scan the whole staged document (`$content` after mask) |
| Pattern strings | Unchanged; only evaluation *scope* changes (delta vs whole file) |
| Escape order | Driver: classify hatch on **unmasked** blob → accepted ⇒ skip `check_fn`; then mask content+delta; then `check_fn`. Gates delete local `gate_has_escape` / `gate_mask_escape` in the **same** change as short-circuit (no masked+local-escape window) |
| Masking | Central in the driver. Each gate sets `GATE_LABEL`; no filename derivation |
| Hatch grammar | Unchanged — em dash or `--`, non-blank reason. Not widened |
| Near-miss hatch | Recorded for `deny` append only; never changes the verdict alone |
| `gate_window_around` | Not built |
| Worktree-vs-index | Best-effort diagnostic text only; never allow/deny |
| Chained `git add` + `git commit` | Best-effort diagnostic; fixed matcher below |
| Rename status vs content pins | **Split:** content delta keeps `--no-renames` (determinism). The driver reads `git diff --cached --name-status -M` once per scan **without** `--no-renames`, so a pure rename reports exact `R100`. Only `R100` whose source **would itself be scanned** (`in_scope` and not scratch) skips `check_fn` (allow); a rename into scope, a scratch→real promotion, and rename+edit reported as low-score `R` are evaluated. It may instead appear as `D`+`A` — document + smoke |
| Empty `M` delta fallback | Whole-document scan when status is `M` and added+removed text is empty (mode-only / empty blob / pin failure) |
| Release | 0.37.0 — behavior change across all seven gates |

## Architecture

```
gate_scan_staged(in_scope_fn, check_fn)
  entries = gate_staged_entries()              # one name-status -M call
  for each (status, path) staged entry in scope:
    raw = gate_staged_blob(path)               # unmasked staged blob
    class = gate_hatch_class(raw, GATE_LABEL)  # accepted | near-miss | absent
    if class == accepted: continue             # short-circuit; never call check_fn
    GATE_NEAR_MISS = near-miss details or empty
    if status == R100 and gate_would_scan(source):
      continue                                 # already-evaluated pure rename → allow
    added, removed = gate_staged_delta(path)   # content pins: --no-renames
    if status==M and added and removed empty:
      added = raw                              # fallback: behave like today
    content = gate_mask_escape(raw, GATE_LABEL)
    GATE_DELTA_ADDED = gate_mask_escape(added, GATE_LABEL)
    GATE_DELTA_REMOVED = gate_mask_escape(removed, GATE_LABEL)
    check_fn(content, path)                    # signature unchanged
```

**Escape short-circuit is mandatory.** Masking blanks accepted hatch lines. If
`check_fn` still called `gate_has_escape` on masked `$content`, every hatch
would stop exempting. Classification and short-circuit happen on `raw`
before mask; gates must not re-call `gate_has_escape` / `gate_mask_escape`.

### Trigger API

```bash
gate_triggered [-w] TRIGGER_ERE [SAT_ERE…]
# return 0 (fire) iff:
#   GATE_DELTA_ADDED matches TRIGGER_ERE (-w ⇒ grep -Eiqw), OR
#   any SAT_ERE is provided and GATE_DELTA_REMOVED matches that SAT_ERE
# return 1 (do not fire) otherwise
```

`proven-gate` uses `-w` so `unproven` does not fire. Callers that only care
about new claims pass one argument. Callers that implement invariant 2 pass
the same satisfaction EREs they already use in whole-document greps as
optional trailing args — one shared list, two uses (re-arm on delete;
satisfy on document).

### Per-gate migration (not a one-line swap)

| Gate | Trigger(s) via `gate_triggered` | Satisfy on whole `$content` |
|---|---|---|
| `evidence-gate` | Two fire paths, both require `smoke` somewhere in the **document** before any teardown/poll check (same as today). (1) `gate_triggered 'smoke' …` → then run teardown/poll SAT checks on whole `$content`. (2) Else if `$content` already has `smoke` and `gate_triggered` on `teardown\|…` or `poll\|…` (with that path's SAT) → same SAT checks. Adding only `poll` next to existing `smoke` **fires**. Adding only unrelated text when smoke+poll already present **does not**. Adding `poll` with **no** smoke in the document **does not**. | Existing preserve-before-teardown / dual-signal greps |
| `proven-gate` | `gate_triggered -w 'proven\|verified'` and `gate_triggered 'spike[[:space:]]+conclusive'` (with SAT list) | `Real path:` + `Stubbed:` |
| `backend-parity-gate` | `backends?\b` | ≥2 named backends (existing loop) |
| `flaky-gate` (LEARNINGS) | flaky/transient/CDN | `Mechanism:` |
| `flaky-gate` (commit message) | **Whole `GATE_COMMAND` text** — no delta; keep today's scan | same |
| `occurrence-gate` | delta must contain an `Occurrence count:` line with N≥2 (parse added lines; not a naive word grep) | `Invariant:` |
| `smoke-gate` | Weak-smoke path: `smoke` (+ weak adjacency) on added; binary/engine path: `binary\|engine\|…` on added when no smoke satisfaction in document | `MANDATORY` smoke / hatch (driver) |
| `derived-value-gate` | Each `_dvg_check_*` greps **`GATE_DELTA_ADDED`** (and re-arms if a future SAT is defined; today denial-is-the-trigger, no SAT) | N/A — hit is the defect |

`smoke-gate`, `occurrence-gate`, and `derived-value-gate` get dedicated plan
tasks; they are not "replace one `grep` with `gate_triggered`."

Central masking is a no-op for verdict on `evidence-gate` / `occurrence-gate`
today (their hatch labels do not match their trigger/SAT patterns). Still
required for invariant 4.

### Delta extraction

Content (pinned):

```
git -c diff.algorithm=myers diff --cached --no-color --no-ext-diff \
    --no-textconv --no-renames -U0 -- <path>
```

Status (rename-aware, separate call — **do not path-filter**):

```
git diff --cached --name-status -M --no-color
# collect once per scan; pair each status with its staged path
# path-filtering collapses rename status to A/D
```

Pins on the content call are load-bearing (see Determinism). Added = `^+`
minus `^+++`. Removed = `^-` minus `^---`.

**Pure rename:** exact status `R100` skips `check_fn` only when its source
would itself be scanned (`gate_would_scan` = in scope and not
`gate_is_scratch`). A rename into scope, or a pure rename that promotes a
dot-prefixed scratch file into a real scoped doc, is evaluated like an add.
Measured: with `--no-renames` on status, the same rename is `D`+`A` and content
delta for the new path is the full body — that is why status must not use
`--no-renames`. Path-filtering `name-status -- <dest>` also collapses pure
`git mv` to `A` (verified Task 1).

**Rename+edit tradeoff:** may still appear as `D`+`A` (whole-file add) or a
low-score `R`. Both are evaluated; content extraction still uses `--no-renames`.
A driver-level smoke covers a measured low-score rename+edit that adds a
violating claim and must deny.

### Near-miss recognition

One recognizer classifies each line as `accepted`, `near-miss`, or `absent`
for `GATE_LABEL`. `accepted` = today's `gate_has_escape` grammar. `near-miss`
= today's wider `gate_mask_escape` shape minus `accepted`. Driver records
near-misses in `GATE_NEAR_MISS`; `deny` appends them when a denial fires.

### Denial diagnostics (best-effort; not part of the verdict)

`deny` may append:

1. Near-miss hatch line + accepted form (invariant 3), when `GATE_NEAR_MISS`
   is set for this file.
2. Chained add+commit, when `GATE_COMMAND` matches this fixed shape (after
   normalizing newlines to spaces):  
   `git[[:space:]]+add\b` … then `(&&|;|\|\|)` … then `git[[:space:]]+commit\b`  
   within the same command string. No attempt to parse `git add -p` interactivity;
   false negatives OK. Message: the add did not run; stage and commit as two
   tool calls.
3. Worktree hatch not in index: compare `gate_hatch_class` on worktree file vs
   staged blob. Race with the editor is acceptable; omit the clause if the
   worktree path is unreadable. Never flips the verdict.

## Determinism

The verdict path contains no model call: delta, trigger, satisfaction, hatch
classification and near-miss detection are all shell and git. That preserves
the determinism program's invariant.

`git diff` output is a function of the repository **and** the user's git
config. Measured: with `color.diff=always`, added lines are ANSI-wrapped,
`grep '^+'` matches zero lines, delta empties, every gate would allow with no
symptom. `--no-color` fixes it. `--no-ext-diff` / `--no-textconv` stop external
diff drivers. `-c diff.algorithm=myers` and `--no-renames` remove remaining
config inputs. `diff.mnemonicPrefix` measured harmless (`+++` still prefixes
the header).

All gate greps and the masker run under `LC_ALL=C`. Em dash measured identical
under C, POSIX, and en_US.UTF-8.

**Empty `M` fallback:** status `M` with empty added and removed text can happen
for mode-only changes, some empty/binary edge paths, or a pin failure mode we
have not listed. Fallback scans the whole document ("behaves like today").
Pure `R` with empty text allows without fallback.

Pre-existing caveats unchanged: multi-gate denial order depends on the runner;
`git commit -a` / pathspec commits remain the documented permissive miss from
CHANGELOG `[0.17.0]`.

## Deliverables

1. `hooks/lib/gate-common.sh` — delta helpers, `gate_triggered`, hatch
   classifier, driver short-circuit + central mask, `deny` diagnostics.
2. All seven gates — delete local escape/mask; set `GATE_LABEL`; migrate
   triggers per the table above.
3. `README.md` — fix Write/Edit bullets; all seven are `Bash(git commit *)`.
4. `skills/session-continuity/REFERENCE.md` — consumer section (index vs
   editor, file-scoped escapes, satisfy-before-escape, denial diagnostics).
5. `skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md` — never chain
   `git add` with `git commit`.
6. `CHANGELOG.md` — 0.37.0.

## Testing

Test-first against existing per-gate smokes and
`2026-08-27-gate-common-smoke.zsh`.

`gate-common`:

- Edit → added lines only; new file → all lines; pure rename → empty.
- `color.diff=always` still yields a correct delta.
- `M` + empty text delta → whole-document fallback.
- `gate_triggered TRIGGER SAT` returns true when only removed lines match SAT.
- Classifier: accepted / near-miss / absent.
- Accepted hatch → `check_fn` never invoked (spy / counter in smoke).
- Rename+edit → a low-score `R` that adds a violating claim is denied.

Per gate (LEARNINGS path for flaky; **not** the commit-message path for the
"unrelated line" pair):

- Trigger already in HEAD, unrelated line added → allow.
- Trigger newly added without satisfaction → deny.
- Satisfaction deleted, claim left → deny (where the gate has a SAT ERE).

`evidence-gate` extras: eval case A allow; case B deny; add-only-`poll` beside
existing `smoke` deny; single-hyphen hatch on a denying commit names the line.

`flaky-gate` commit-message path: one smoke that a message containing `flaky`
without `Mechanism:` still denies (whole-text, unchanged).

All pre-existing cases in all seven suites still pass.

## Out of scope

- `gate_window_around` / within-file windowing.
- Widening accepted hatch separators.
- Changing trigger or satisfaction *pattern strings* (scope only).
- `git commit -a` / pathspec coverage.
- Anything under `commands/`.
- Warning on near-miss when the gate would allow (invariant 3 is denial-only).

## Success criteria

1. Unrelated paragraph on a file whose triggers already exist in HEAD → allow
   on all seven file-scoped paths (flaky LEARNINGS; not commit message).
2. Newly added claim without its field → deny with today's message plus any
   applicable diagnostics.
3. Deleting a satisfying field while leaving the claim → deny (gates with SAT).
4. On every denial that has a near-miss hatch in the staged blob, the denial
   names that hatch.
5. No gate file contains `gate_mask_escape` or `gate_has_escape`.
6. `color.diff=always` verdicts match a clean config.
7. Every pre-existing smoke in all seven gate suites passes unchanged.
8. Accepted hatch still exempts (driver short-circuit smoke).
