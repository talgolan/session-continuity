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
   the commit's own changes contain the trigger, and it looks for satisfying
   evidence anywhere in the document. Prose you did not touch can never
   condemn your edit; evidence that lives fifty lines away still counts.
2. **Deleting evidence counts as a change.** Removing a satisfying field while
   leaving the claim in place must re-arm the gate.
3. **A hatch attempt is never silently ignored.** A line a human would read as
   this gate's escape hatch either exempts the file, or the denial names it by
   line number and states the accepted form.
4. **No gate can forget the self-condemnation mask.** It is applied by the
   driver, before any gate sees content.
5. **The verdict is a pure function of the repository.** Not of the user's git
   config, locale, or working tree.

## Decisions (locked)

| Decision | Choice |
|---|---|
| Where the rule lives | `gate_scan_staged` / new helpers in `hooks/lib/gate-common.sh`; no per-gate reimplementation |
| Per-gate change shape | Trigger greps switch to `gate_triggered <ere>`; satisfaction greps untouched |
| Delta definition | Added lines from `git diff --cached`, plus removed lines when matching a satisfaction pattern (invariant 2) |
| Masking | Moved into the driver; the five local `gate_mask_escape` calls are deleted. Each gate sets `GATE_LABEL`; no filename derivation |
| Hatch grammar | Unchanged — em dash or `--`, non-blank reason. Not widened |
| Near-miss hatch | Detected by the shared recognizer, reported in the denial, never changes the verdict on its own |
| `gate_window_around` | Not built. The diff is the exact answer the window approximates |
| Worktree-vs-index divergence | Diagnostic text only; never participates in allow/deny |
| Chained `git add && git commit` | Detected from `GATE_COMMAND`, reported in the denial |
| Release | 0.37.0 — behavior change across all seven gates |

## Architecture

```
gate_scan_staged(in_scope_fn, check_fn)
  for each staged file in scope:
    content = gate_staged_blob(path)          # whole document, as today
    delta   = gate_staged_delta(path)          # added lines (+ removed, see below)
    content = gate_mask_escape(content, GATE_LABEL)  # now central, was per gate
    delta   = gate_mask_escape(delta,   GATE_LABEL)
    GATE_DELTA, GATE_NEAR_MISS set as globals
    check_fn(content, path)                    # signature unchanged
```

`check_fn`'s signature does not change, so the seven gates keep their shape.
What changes inside each is one line:

```bash
# before
printf '%s' "$content" | grep -Eiq 'smoke' || return 0
# after
gate_triggered 'smoke' || return 0
```

`gate_triggered <ere>` reads `GATE_DELTA`. Satisfaction greps continue to read
`$content`. A gate that needs the old whole-file trigger for a documented
reason can still grep `$content` directly — but none currently do.

`gate_mask_escape` moves to the driver, which means the driver needs each
gate's hatch label. Every gate sets `GATE_LABEL` explicitly before calling
`gate_scan_staged`; the label is not derived from the filename. Five of the
seven labels do match their filename, but `smoke-gate.sh` uses `Smoke` and
`backend-parity-gate.sh` uses `Backend-parity`, so derivation would be a rule
with two silent exceptions — and a wrong label masks nothing while still
looking correct.

Central masking is a no-op for the two gates that do not mask today.
`evidence-gate` and `occurrence-gate` will now see masked content, but a
blanked `Evidence-gate: N/A` or `Occurrence-gate: N/A` line carries none of
their trigger or satisfaction patterns, so no verdict changes.

`flaky-gate` checks two things: staged `LEARNINGS.md` content, which follows
the delta rule, and the commit message itself, which has no delta and keeps
whole-text triggering.

### Delta extraction

```
git -c diff.algorithm=myers diff --cached --no-color --no-ext-diff \
    --no-textconv --no-renames -U0 -- <path>
```

Every flag is a determinism pin, not a preference — see below. Added lines are
the `^+` lines with the `^+++` header filtered out. Removed lines (`^-`, minus
`^---`) are scanned only against the gate's satisfaction pattern, to serve
invariant 2.

### Near-miss recognition

One recognizer classifies each line as `accepted`, `near-miss`, or `absent`
for a given label. `accepted` is today's `gate_has_escape` grammar. `near-miss`
is today's wider `gate_mask_escape` shape minus `accepted` — a `Label:` and an
`N/A` without the separator-and-reason. The driver records near-misses in
`GATE_NEAR_MISS` (line number and text); `deny` appends them to its message.

This replaces the current split between a strict matcher and a deliberately
wider masker, which is the structural reason a hatch can be recognized enough
to mask but not enough to exempt.

### Denial diagnostics

`deny` appends, when applicable:

- the near-miss hatch line and the accepted form (invariant 3);
- "this command chained `git add` with `git commit`; the add did not run"
  when `GATE_COMMAND` matches an `add` followed by `&&` or `;` and a `commit`;
- "the working-tree copy of this file contains a hatch that is not staged"
  when the worktree file differs from the blob on that point.

## Determinism

The verdict path contains no model call: delta, trigger, satisfaction, hatch
classification and near-miss detection are all shell and git. That preserves
the determinism program's invariant, which forbids asking a model to compute a
pure function of files, git state, or transcript data.

`git diff` output, however, is a function of the repository **and the user's
git config**. Measured: with `color.diff=always` set, added lines arrive
wrapped in ANSI escapes, `grep '^+'` matches zero lines, the delta reads as
empty, and every gate allows everything with no symptom. `--no-color` fixes
it. `--no-ext-diff` and `--no-textconv` stop a `.gitattributes` diff driver or
`GIT_EXTERNAL_DIFF` from rewriting the content the gate reads.
`-c diff.algorithm=myers` and `--no-renames` remove the remaining config
inputs; the three algorithms agreed on the case measured, but which lines an
edit is attributed to is algorithm-dependent in principle and a verdict must
not depend on a knob. `diff.mnemonicPrefix` was measured harmless: it rewrites
the header to `i/<path>`, which still begins with `+++`.

All gate greps and the masker run under `LC_ALL=C` for byte-stable matching.
The em dash keeps matching as a literal byte sequence; measured identical
under C, POSIX and en_US.UTF-8.

**Fallback, because a pin is a promise and not an enforcement:** if a file is
staged as a modification (`--name-status` `M`) and the extracted delta is
empty, the driver scans the whole document instead. The failure mode becomes
"behaves like today" rather than "silently allows everything." A pure rename
reports `R` and legitimately yields an empty delta; it is allowed.

Two pre-existing determinism caveats stay as they are. Which denial surfaces
first when a file violates two gates depends on the runner's hook execution
order. And `git commit -a` / pathspec commits remain the documented permissive
miss from CHANGELOG `[0.17.0]`.

## Deliverables

1. `hooks/lib/gate-common.sh` — `gate_staged_delta`, `gate_triggered`, the
   unified hatch recognizer, central masking in `gate_scan_staged`, denial
   diagnostics in `deny`.
2. The seven gates — trigger greps switched to `gate_triggered`; the five
   local `gate_mask_escape` calls and their comments deleted; `GATE_LABEL` set
   in all seven.
3. `README.md` — correct the five gate bullets that say `PreToolUse` on
   Write/Edit. All seven fire on `Bash(git commit *)`.
4. `skills/session-continuity/REFERENCE.md` — consumer section: gates read the
   index and not the editor buffer, escapes are file-scoped, satisfying beats
   escaping, and what the new denial diagnostics mean.
5. `skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md` — the
   never-chain-`git add`-with-`git commit` trap, stated as a rule.
6. `CHANGELOG.md` — 0.37.0.

## Testing

Test-first, against the existing per-gate smokes and
`2026-08-27-gate-common-smoke.zsh`.

New cases in `gate-common`:

- Added lines only are returned for an edit; all lines for a new file; empty
  for a pure rename.
- `color.diff=always` in the repo config still yields a correct delta.
- A modification with an empty extracted delta falls back to whole-document.
- Removed lines matching a satisfaction pattern re-arm the trigger.
- The recognizer classifies accepted, near-miss, and absent hatch lines.

Per gate, each of the seven suites gains the same pair: its trigger word
already present in the committed file and an unrelated line added, which must
allow; and its trigger newly added without the satisfying field, which must
deny. Spelled out for `evidence-gate`, the pattern the other six copy:

- The eval's case A (unrelated "smoke" and "poll" already in the file, an
  unrelated paragraph added) now allows.
- The eval's case B (a real smoke section with a success-only poll, newly
  added) still denies.
- Deleting the dual-signal sentence while leaving the poll denies.
- A single-hyphen hatch denies, and the denial names the line.
- Every existing case in all seven suites still passes.

## Out of scope

- `gate_window_around` and any within-file windowing.
- Widening the accepted hatch separators.
- Changing what any gate asks for — no trigger or satisfaction regex changes.
- `git commit -a` / pathspec coverage.
- Anything under `commands/`.

## Success criteria

1. Adding an unrelated paragraph to a document that already contains trigger
   words is allowed by all seven gates.
2. Newly added prose that makes a claim without its field is still denied by
   the gate that owns it, with the same message as today plus diagnostics.
3. Deleting a satisfying field while leaving the claim is denied.
4. A malformed hatch never produces a denial that fails to mention it.
5. No gate contains a local `gate_mask_escape` call.
6. A repository with `color.diff=always` produces the same verdicts as one
   without.
7. Every pre-existing smoke in all seven gate suites passes unchanged.
