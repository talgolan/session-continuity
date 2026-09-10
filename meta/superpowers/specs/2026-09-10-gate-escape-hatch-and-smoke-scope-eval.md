# Eval: gate escape-hatch + evidence-gate scope — what is real, what is not, and what consuming projects should do today

Evaluation of
[`meta/superpowers/plans/2026-09-10-gate-escape-hatch-and-smoke-scope-fix.md`](../plans/2026-09-10-gate-escape-hatch-and-smoke-scope-fix.md),
written after reproducing every claim against the live hooks in this repo.
No hook code changed on this branch.

Real path: `hooks/evidence-gate.sh` and `hooks/lib/gate-common.sh` as shipped
at `5f3b024`, driven through the real `gate_load` / `gate_scan_staged` path by
`meta/superpowers/validation/lib/gate-test-common.zsh` — real `git init`
repos, real staged blobs, real PreToolUse stdin payloads, real deny JSON.
Stubbed: the Claude Code hook runner itself (payloads were constructed by the
harness rather than emitted by Claude Code), and the original
architect-workbench document (a synthetic fixture of the same shape stood in).

Evidence-gate: N/A — this document is about the gate; its "smoke", "poll" and
"teardown" mentions are quoted regexes and test-case names, not a smoke design.

## Verdict

The plan found a real bug and misdiagnosed a second one.

Bug A (evidence-gate scope) is real, reproduces on demand, and Tasks 1–2 are
the right shape of fix — with two corrections noted below, one of which would
introduce a new false positive if the plan were executed literally.

Task 3 should not be executed as written. It proposes a debug-logging
expedition to find a divergence in `gate_has_escape` between the live hook and
an isolated call. There is no such divergence. `gate_has_escape` behaves
identically in both, and both symptoms it chases have concrete, already-
reproduced causes that need no investigation:

- Symptom A is escape-line grammar. The separator between `N/A` and the reason
  must be an em dash (U+2014) or a double hyphen. A single hyphen, an en dash,
  or a colon fails silently and the denial persists — exactly the reported
  experience.
- Symptom B is already mitigated. `gate_mask_escape` was added for it,
  `proven-gate.sh:27` calls it, and the two regression cases the plan asks for
  already exist and pass.

The escape-hatch grammar is also the largest of the consumer-facing traps,
and it is not documented anywhere a consuming project would find it.

## What was measured

### Escape-hatch grammar (`gate_has_escape`, label `Evidence-gate`)

| Escape line as written | Result |
|---|---|
| `Evidence-gate: N/A — reason` (em dash U+2014) | accepted |
| `Evidence-gate: N/A -- reason` (double hyphen) | accepted |
| `Evidence-gate: N/A - reason` (single hyphen) | **silently ignored** |
| `Evidence-gate: N/A – reason` (en dash U+2013) | **silently ignored** |
| `Evidence-gate: N/A: reason` | **silently ignored** |
| `Evidence-gate: N/A (reason)` | **silently ignored** |
| `Evidence-gate: N/A` (no reason) | **silently ignored** |
| `Evidence gate: N/A — reason` (space in label) | **silently ignored** |
| `Evidence-gate : N/A — reason` (space before colon) | **silently ignored** |
| `evidence-gate: n/a — reason` | accepted |
| `> **Evidence-gate:** N/A — reason` | accepted |
| `Evidence-gate:N/A — reason` | accepted |

Locale is not a factor: the em-dash form matches identically under `LC_ALL=C`,
`POSIX`, and `en_US.UTF-8`.

The failure mode is what makes this expensive. A rejected escape line produces
no warning, no near-miss hint, and no change in the denial text — the denial
reads exactly as it did before the line was added, so the natural next move is
to rewrite the *reason* rather than the *dash*.

### Evidence-gate behavior (real gate, real staged blobs)

| Case | Today | Should be |
|---|---|---|
| A: "smoke" and "poll" 30+ lines apart, unrelated (the architect-workbench shape) | deny | allow |
| B: real smoke section, success-only poll | deny | deny |
| C: case A plus an em-dash escape line | allow | allow |
| D: case A plus a single-hyphen escape line | deny | allow |
| E: case A plus an en-dash escape line | deny | allow |
| F: escape line written to the working tree but never re-staged | deny | deny |
| G: `git commit` invoked from a subdirectory, real violation staged | deny | deny |

Case A is Bug A. Cases D and E are the grammar trap. Case F is the index/
working-tree gap: gates read `git show :<path>`, never the editor buffer.

Case G rules out a dead end worth recording. `gate_staged_files` emits
repo-root-relative paths while `gate_staged_blob` runs `git -C "$GATE_CWD"
show ":$path"`, which looked like it should mis-resolve when `GATE_CWD` is a
subdirectory and skip the file. It does not; git resolves the `:path` form
against the repository root. Subdirectory invocation is not a failure mode and
needs no fix.

### Existing coverage is green

`2026-06-17-proven-gate-smoke.zsh` (10 pass), `2026-08-27-gate-common-smoke.zsh`
(18 pass), `2026-07-01-evidence-gate-smoke.zsh` (7 pass). The proven-gate suite
already contains `malformed own hatch is not a claim -> allow` and `real claim
beside malformed hatch -> deny` — the two cases Task 3 lists under "Done when".

## Disposition of the plan, task by task

**Task 1 (`gate_window_around` in `gate-common.sh`) — keep, simplify.** Landing
the helper in the shared library is right; `proven-gate.sh` and `smoke-gate.sh`
have the same whole-file shape. Drop the "narrow to the enclosing markdown
section when it is smaller than the window" refinement. It adds heading-level
parsing for a benefit no reproduced case demonstrates. Ship the fixed window
first.

**Task 2 (rewire `evidence-gate.sh`) — keep, but fix one instruction.** The
plan says to replace `$content` with `$scoped` in "both trigger checks". Each
check is a pair: a trigger grep and a negated satisfaction grep, both inside
the same `if`. Scoping the satisfaction grep to the window as well creates a
new false positive — a document whose smoke section polls, and which states
its dual-signal convention in a shared section 50 lines away, would newly be
denied. Scope the trigger greps to the window; leave the satisfaction greps
scanning the whole file, so the gate keeps failing open on evidence that
exists anywhere in the document. This needs a regression case of its own.

**Task 3 (`gate_has_escape` investigation) — do not execute; replace.** No
divergence exists to find, so `GATE_DEBUG` instrumentation would be built to
chase nothing. The class is real, but the cause is grammar strictness, and the
fix is small and forward-looking rather than investigative:

- Accept the separators people actually type — single hyphen, en dash, and
  colon — alongside the em dash and double hyphen already accepted. Keep
  requiring a non-blank reason, which is the part that carries the value. The
  counterargument, that a strict grammar is deliberate friction against casual
  escaping, does not survive the evidence: the friction lands as an unexplained
  repeat denial, not as a second thought about whether to escape.
- When a line matches the wide `Label:` + `N/A` shape but not the accepted
  grammar, say so in the denial: name the line number and the accepted forms.
  A near-miss should never be indistinguishable from an absent hatch.
- `gate_mask_escape` already recognizes the wide shape, so the two functions
  would converge rather than diverge further.

**Cross-reference note in the plan's closing section — keep.** The
architect-workbench `COMMIT_HOOKS.md` §4 note should point here rather than at
Task 3.

## Consumer guidance outline

For a project that installs this plugin and starts hitting denials. This is
the outline; where it ships is the open decision in the next section.

1. **Satisfy the gate before escaping it.** Every gate asks for one concrete
   field. `proven-gate` wants `Real path:` and `Stubbed:` beside the claim.
   `evidence-gate` wants a preserve-before-teardown sentence, or a poll that
   names both a success and a failure signal. Adding the field is usually
   shorter than the escape line and leaves the document better.

2. **If you do escape, the grammar is exact.** `Label: N/A — reason`, with an
   em dash or a double hyphen, and a non-blank reason. A single hyphen, an en
   dash, a colon, or a bare `N/A` is ignored without comment. Markdown
   decoration is fine: `> **Label:** N/A — reason` works. The label is the
   gate's own name, hyphenated, exactly as it appears in the denial text.

3. **The gate reads the index, not your editor.** Escape lines and fixes only
   count once staged. Confirm with `git show :path/to/file.md | grep -i
   'gate:'` before assuming the hatch is broken.

4. **Never chain `git add` with `git commit`.** All seven gates match against
   the whole command string. If the string is `git add f.md && git commit -m
   ...` and a gate denies, the `add` never ran either, and retrying the same
   string denies again against the same stale blob. Stage and commit as two
   separate calls. This is the single most common way a correct fix looks like
   a broken gate.

5. **Gates fire at commit time, not on save.** `Write` and `Edit` are never
   blocked; iterate freely. (README currently describes five of the gates as
   `PreToolUse` on Write/Edit. That is wrong — `hooks/hooks.json` wires all
   seven on `Bash(git commit *)`, and `REFERENCE.md` says so correctly. The
   README lines need a correction.)

6. **Escapes are file-scoped, not entry-scoped.** One `Label: N/A` line
   whitelists the whole file for that gate. In a long LEARNINGS.md that is a
   bigger exemption than it looks.

7. **When a denial does not match the document, read it literally.** The
   denial names the staged path. Until Bug A ships, `evidence-gate` can fire
   on a document with no smoke design at all, when the word "smoke" appears in
   one place and "poll", "wait for", "teardown" or "cleanup" appears in
   another, however far apart. A filename like `pollRoute.test.ts` counts. The
   file-scoped escape line is the correct response in that case, and the
   reason should say the document has no smoke design.

## Recommended next step

Ship the Bug A fix (plan Tasks 1–2 with the two corrections above) and the
Task 3 replacement (widen the separator set, add the near-miss hint) as one
change against `hooks/lib/gate-common.sh` and `hooks/evidence-gate.sh`, then
correct the README gate-trigger lines and add the consumer guidance to
`skills/session-continuity/REFERENCE.md` in the same release. The guidance is
worth less on its own: four of its seven items describe behavior the fix
removes or improves, and shipping the documentation first would date it within
a release.

If the fix is deferred instead, items 2, 3, 4 and 7 are the ones that pay for
themselves immediately and should go into `REFERENCE.md` on their own.
