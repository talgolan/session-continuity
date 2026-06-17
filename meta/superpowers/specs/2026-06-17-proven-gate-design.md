# Proven-gate — make "proven" a checkable claim, not a feeling

**Date:** 2026-06-17
**Status:** designed (brainstorm complete, awaiting plan)

Proven-gate: N/A — this spec documents the gate's own syntax (meta-document; see "Self-reference trap" below).

**Workstream:** change-the-odds deliverable #1 of 4 (the highest-leverage one).
See `~/active_development/TG/itb/docs/superpowers/specs/2026-06-17-change-the-odds-process-design.md`
for the parent workstream and `project-change-the-odds` memory.

## The problem this gate exists to stop

On 2026-06-17 (itb build-egress session) a feature was declared "spike
conclusive, proven, Option A" on the strength of a hand-rolled `/tmp` no-auth
proxy that never exercised `Proxy-Authorization` or the helper lifecycle — the
two things that actually broke later in the real smoke. The relevant memory
(`feedback-prove-mechanism-first`) was IN CONTEXT and did not fire. Recall lost
to confidence at the decision point.

The change-the-odds finding: **a note changes behavior only when it becomes a
check that EXECUTES at the decision point and returns a verdict.** This gate
converts `feedback-prove-mechanism-first` from prose into a required, checkable
field pair attached to every forward "proven" claim.

## What it does (one sentence)

A PreToolUse hook that, when the agent writes a "proven"-class claim into a
spec or plan file, BLOCKS the write unless the same content also names — in two
explicit fields — the real production path that was exercised and what was
stubbed.

## Scope (decided)

- **Fires on:** `Write` / `Edit` to `*.md` files whose path is under a
  `*/specs/` or `*/plans/` directory. These are the *forward-claim* surfaces —
  where "proven" is a prediction the agent is about to act on.
- **Does NOT fire on:** SESSION_PRIMER.md, LEARNINGS.md, READMEs, code, or any
  other path. Those are historical / narrative surfaces where "Proven on the
  real path…" describes already-merged work; forcing structured fields there is
  pure false-positive noise. (This is why the gate is narrower than the
  smoke-gate's plan-only scope is wide — different surface, different risk.)

## Detection rule

**Claim-words** (case-insensitive, matched as whole words / phrases):

- `proven`
- `verified`
- `spike conclusive`

(`confirmed` was considered and DROPPED — too common in benign prose
["confirmed the user's choice"] to be worth the false-block rate.)

When the written content contains ANY claim-word, it MUST also contain BOTH of
these fields (case-insensitive label, non-empty value after the colon):

```
Real path: <which production code path actually ran>
Stubbed: <what stood in — or the literal word "nothing">
```

- Missing **either** field → `deny`.
- `Stubbed:` is the load-bearing field. It is where "used a no-auth proxy"
  gets written down and the self-deception becomes visible to the author. The
  gate does NOT try to judge whether the stub invalidates the claim (it can't
  reliably) — it forces the author to WRITE the stub down, which is what makes
  the bad claim visible to a human reviewer and to the author's own next read.

## Escape hatch (explicit skip-with-reason)

A line matching (em-dash or `--`, non-empty reason):

```
Proven-gate: N/A — <reason>
```

passes the gate unconditionally. For legitimate claim-word uses that genuinely
need no field block: quoting someone else's "proven" claim, a glossary entry
defining the term, a spec (like this one) that documents the gate itself. Same
idiom as smoke-gate's `Smoke: N/A — <reason>`. (Identifiers like `proven_flow`
do not need the hatch — whole-word matching already lets them through, per the
detection rule.)

## Mechanics (reuse smoke-gate.sh exactly)

New file `hooks/proven-gate.sh`. It mirrors `hooks/smoke-gate.sh` line-for-line
in structure — this is deliberate reuse of a proven hook skeleton, not a new
pattern:

1. `set -euo pipefail`; read payload from stdin; empty → `exit 0`.
2. Extract `file_path`; empty → `exit 0`.
3. **Self-scope:** path must be `*/specs/*` or `*/plans/*` AND basename `*.md`,
   else `exit 0`.
4. Decode the written content: `content` (Write) or `new_string` (Edit), then
   un-escape `\n` `\t` `\"` `\\` so line-oriented greps work. Empty → `exit 0`.
   Bounded best-effort decode; the gate errs toward blocking and the escape
   hatch is the override, so an imperfect decode is safe.
5. **Escape hatch first:** `Proven-gate:\s*N/A\s*(—|--)\s*<non-empty>` → `exit 0`.
6. No claim-word present → `exit 0` (silent allow). **NOTE the one deliberate
   deviation from the smoke-gate skeleton:** smoke-gate matches its keyword as a
   substring (`grep -ci 'smoke'`); proven-gate MUST match claim-words on word
   boundaries (`grep -iwE 'proven|verified'` plus the `spike conclusive` phrase)
   so `improven` / `unproven` / `proven_flow` do not false-trigger (test case 8).
7. Claim-word present → require both fields. Missing either → `deny` with a
   reason naming both fields and pointing at the escape hatch.

**Output contract** (identical to smoke-gate): `deny` emits
`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"…"}}`
and `exit 0`; allow is silent `exit 0`.

**Security:** `$file_path` / `$content` are used only in path tests and greps,
never `eval`'d. No network, no writes, no spawned subprocesses beyond `grep`/`sed`.

### Wiring

`hooks/hooks.json` PreToolUse `Write|Edit` block gains a third entry after
`smoke-gate.sh`:

```json
{ "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/proven-gate.sh" }
```

The two gates are independent and compose: a plan file can be denied by
smoke-gate (missing smoke task) and/or proven-gate (bare "proven"); each emits
its own deny. Order does not matter — Claude sees the first deny and fixes it,
the re-write re-runs both.

## Testing (hermetic, no containers)

New runner `meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh`,
cloning the shape of `2026-06-15-fire-before-action-smoke.zsh`: synthetic
PreToolUse payloads piped to `hooks/proven-gate.sh`, assert the stdout JSON (or
silence). Cases:

| # | Input (spec/plan file content) | Expect |
|---|---|---|
| 1 | "proven" + `Real path:` + `Stubbed:` both filled | silent (allow) |
| 2 | "proven", no fields | deny |
| 3 | "verified" + `Real path:` only (no `Stubbed:`) | deny |
| 4 | "spike conclusive" + `Stubbed:` only (no `Real path:`) | deny |
| 5 | claim-word + `Proven-gate: N/A — quoting upstream` | silent |
| 6 | non-spec path (`*/src/foo.ts`) with "proven", no fields | silent (out of scope) |
| 7 | spec file, NO claim-word ("renamed a variable") | silent |
| 8 | claim-word phrase boundary: "improven" / "unproven" should NOT match `proven` whole-word | silent (no false trigger) — *guard the regex* |
| 9 | `confirmed` present, no fields | silent (dropped word, must NOT deny) |

Case 8 + 9 are the regression guards for the two tuning decisions (whole-word
match; `confirmed` excluded).

## Self-reference trap (LEARNINGS #7 + #1 — read before implementing)

This gate has the same self-reference hazard the smoke-gate hit (LEARNINGS #7):
a spec or plan that *documents* proven-gate contains its own claim-words AND its
own `Proven-gate: N/A — …` hatch string. Consequences, baked into this design:

- **Never verify the gate by self-scanning this spec or its plan.** A
  self-referential check passes "for free" via the incidental hatch match, not
  via the logic under test — a green that means the opposite of what it looks
  like. Verify ONLY with the hermetic fixture runner below.
- **Do NOT tighten the hatch to line-start anchoring to "fix" the self-match.**
  That flips the gate to false-positive denies on legit meta-docs. The loose
  hatch is the correct trade: an accidental opt-out requires writing the literal
  declaration string, which does not happen outside documents about the gate.
- This spec carries its own `Proven-gate: N/A — …` line at the top precisely so
  that, once the gate is live, editing this very file is not blocked by the
  claim-words it must quote.
- **JSON contract (LEARNINGS #1):** `PreToolUse` does NOT inject plain stdout.
  The `deny` path MUST emit the `hookSpecificOutput` JSON object (it does —
  copied verbatim from smoke-gate, which is proven live). Silent-allow is a bare
  `exit 0` with no stdout. Do not "improve" allow to print a reminder unless it
  uses the `permissionDecision:"allow"` + `additionalContext` JSON shape.

## Versioning / ship

- `plugin.json` `0.8.0` → `0.9.0` (new user-facing hook behavior).
- CHANGELOG entry under a new `0.9.0` heading.
- `.githooks/pre-commit` version-sync guard already enforces plugin.json is the
  single version source (no marketplace.json in this repo since `12a463d`).
- Branch `feat/proven-gate` off `main`; own PR; squash-merge.
- Hooks register at SessionStart, so the gate goes live the NEXT session after
  the marketplace update + reinstall.

## Success criterion (the invariant)

After this ships, the agent cannot write `proven` / `verified` / `spike
conclusive` into a spec or plan without — in the same write — naming the real
path exercised and what was stubbed, OR explicitly opting out with a reason. A
future "spike conclusive, Option A" claim physically cannot land on confidence
alone; the `Stubbed:` field forces the stand-in into the open where author and
reviewer both see it.

## Out of scope (other change-the-odds deliverables, sequenced after this)

- #3 stale-binary + fixed-port-helper preflight scripts (itb repo-local).
- #2 rule-4 occurrence counter on LEARNINGS classes.
- #4 prune decorative prose once enforced by a check.

Each gets its own brainstorm → spec → plan → implement → smoke → PR.
