# Occurrence-counter gate + spike-check command — change-the-odds #2 + #3c

**Date:** 2026-06-17
**Status:** designed (brainstorm complete, awaiting plan)

Proven-gate: N/A — this spec quotes claim-words while documenting two new gates; no forward "proven" claim is made.

**Workstream:** change-the-odds deliverables #2 (rule-4 occurrence counter) and
#3c (stand-in spike checklist), shipped together in one PR. Parent workstream:
`~/active_development/TG/itb/docs/superpowers/specs/2026-06-17-change-the-odds-process-design.md`;
memory `project-change-the-odds`. Sibling already shipped: #1 proven-gate
(`hooks/proven-gate.sh`, v0.9.0). This pair reuses the proven-gate skeleton
exactly — same hook shape, same hermetic `.zsh` smoke shape, same escape-hatch
idiom.

## The two problems

**#2 — trigger-patch over invariant.** The #149→#150 class (itb) recurred
because #149 was fixed by reaping "the current home's stale port" without naming
the end-state invariant (host-global port ⇒ host-global secret). The second
variant walked straight through. CLAUDE.md rule 4 ("a command broken across 2+
fixes → name the invariant") was in context and did not fire. Recall lost to
confidence. The fix: when a LEARNINGS entry records the **2nd occurrence** of a
class, it must carry an explicit end-state **`Invariant:`** line — not another
trigger-patch — and a gate must enforce that, because noticing the recurrence is
exactly the step that fails unaided.

**#3c — stand-in spike declared conclusive.** A spike used a hand-rolled no-auth
proxy that never exercised the auth/lifecycle path that actually broke. The
proven-gate (#1) catches this *reactively* at claim-time (the `Stubbed:` field
forces the stand-in into the open). #3c adds the *proactive* half: a checklist
the agent emits at **spike start** so the spike is designed to hit the real
binary + real auth/lifecycle/fixed-port path in the first place, rather than
discovering at claim-time that it didn't.

## Deliverable #2 — occurrence-gate hook

### What it does (one sentence)

A PreToolUse hook that, when the agent writes a LEARNINGS entry recording the
2nd-or-later occurrence of a mistake-class, BLOCKS the write unless the same
content also names an end-state `Invariant:` line.

### Scope (decided)

- **Fires on:** `Write` / `Edit` whose `file_path` basename is `LEARNINGS.md`
  AND under a `*/.session-continuity/*` or `*/docs/*` path (the two canonical
  primer locations — same dual-path logic as `learnings-surface.sh`).
- **Does NOT fire on:** specs, plans, primers, code, READMEs, or any other path.
  LEARNINGS.md is the only surface where occurrence counts live.

### Detection rule

The written content is scanned (coarse, content-level — NOT per-entry parsed,
matching proven-gate's "force the author to write it down" philosophy rather
than attempting reliable structural parsing):

1. **Occurrence trigger.** An `Occurrence count: N of M` line (case-insensitive
   label, `N` and `M` integers) with **N ≥ 2**.
   - N = 1 (or absent) → silent allow. First occurrence is a normal LEARNINGS
     entry; no invariant demanded yet.
2. **Required when triggered.** The content must also contain a non-empty
   `Invariant:` line (case-insensitive label, non-empty value after the colon).
   - Missing → `deny`.

The `Invariant:` field is load-bearing: it is where "host-global port ⇒
host-global secret" gets written down. The gate does not judge whether the named
invariant is *correct* (it can't) — it forces the author to state an end-state
rather than ship a 2nd trigger-patch, making the escalation visible to author
and reviewer.

### Escape hatch (explicit skip-with-reason)

A line matching (em-dash or `--`, non-empty reason):

```
Occurrence-gate: N/A — <reason>
```

passes unconditionally. For legit claim-word uses with no escalation owed:
quoting another entry's occurrence line, a glossary, or a spec (like this one)
documenting the gate. Same idiom as `Proven-gate:` / `Smoke:`.

### `/learning` command extension

`commands/learning.md` Step 2 (gather the recipe) gains two **optional** fields,
prompted after "Diagnostic signal":

- **Occurrence count** — "Is this the Nth time this CLASS of bug has bitten?
  Enter `N of M` (e.g. `2 of 2`), or skip for a first-occurrence entry."
- **Invariant** (prompted ONLY when occurrence N ≥ 2) — "This is occurrence ≥2.
  Name the END-STATE invariant that, if enforced at the reconciler/entry gate,
  makes the whole class impossible — not another trigger-patch. (CLAUDE.md rule
  4.)"

Step 5 (compose) emits, directly under the `### N. Title` (and `Trigger:` line
if present):

```
Occurrence count: <N of M>     ← only if supplied
Invariant: <end-state>          ← only if N >= 2
```

This makes the gate *usable*: the command authors compliant entries by
construction, so the gate fires only on hand-edits that skip the invariant.

### Mechanics (reuse proven-gate.sh skeleton)

New `hooks/occurrence-gate.sh`, mirroring `hooks/proven-gate.sh` structure:

1. `set -euo pipefail`; read payload; empty → `exit 0`.
2. Extract `file_path`; empty → `exit 0`.
3. **Self-scope:** basename `LEARNINGS.md` AND path contains `/.session-continuity/`
   or `/docs/`, else `exit 0`.
4. Decode content (`content` for Write, `new_string` for Edit); un-escape
   `\n \t \" \\`; empty → `exit 0`.
5. **Escape hatch first:** `Occurrence-gate:\s*N/A\s*(—|--)\s*<non-empty>` → `exit 0`.
6. **Occurrence trigger:** grep for `Occurrence count:\s*([0-9]+)\s+of\s+[0-9]+`,
   capture N. No match OR N < 2 → `exit 0` (silent allow).
7. **Require invariant:** `Invariant:\s*<non-empty>` present? Missing → `deny`
   with a reason naming the `Invariant:` field, citing rule 4, and pointing at
   the escape hatch.

**Output contract** (identical to proven-gate, LEARNINGS #1): `deny` emits
`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"…"}}`
then `exit 0`; allow is silent `exit 0`.

**N-extraction note:** the largest N in the content wins (an Edit may touch one
entry but the decoded `new_string` could contain several). Coarse by design —
if any escalated entry in the write lacks an invariant, block. The escape hatch
covers the rare quote-an-occurrence-line case.

**Security:** `$file_path` / `$content` used only in path tests + greps, never
`eval`'d. No network, no writes, no subprocesses beyond `grep`/`sed`/`awk`.

### Wiring

`hooks/hooks.json` PreToolUse `Write|Edit` block gains a fourth entry after
`proven-gate.sh`:

```json
{ "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/occurrence-gate.sh" }
```

The gates compose independently — a LEARNINGS edit is out of proven-gate's
`*/specs/*|*/plans/*` scope, so only occurrence-gate fires on it. No ordering
dependency.

### Self-reference trap (LEARNINGS #7 + #1)

This spec quotes `Occurrence count:` and the `Occurrence-gate: N/A` hatch. The
spec lives under `*/specs/*`, NOT a `LEARNINGS.md` path, so the gate never fires
on it — no self-scan hazard for the gate itself. Verify ONLY via the hermetic
fixture runner; never by editing a real LEARNINGS.md. Do NOT tighten the hatch
to line-start anchoring (flips to false-positive denies on legit meta-docs).

### Testing (hermetic, no containers)

New `meta/superpowers/validation/2026-06-17-occurrence-gate-smoke.zsh`, cloning
`2026-06-17-proven-gate-smoke.zsh`. A `learn()` helper builds a Write payload to
`/x/.session-continuity/LEARNINGS.md`. Cases:

| # | Input (LEARNINGS content) | Expect |
|---|---|---|
| 1 | `Occurrence count: 2 of 2` + `Invariant: host-global port ⇒ host-global secret` | silent (allow) |
| 2 | `Occurrence count: 2 of 2`, no `Invariant:` | deny |
| 3 | `Occurrence count: 1 of 2`, no `Invariant:` | silent (1st occurrence, nothing owed) |
| 4 | no occurrence line at all (ordinary entry) | silent |
| 5 | `Occurrence count: 3 of 5`, no `Invariant:` | deny (N≥2) |
| 6 | `Occurrence count: 2 of 2` + escape hatch `Occurrence-gate: N/A — quoting #149` | silent |
| 7 | non-LEARNINGS path (`*/specs/s.md`) with `Occurrence count: 2 of 2`, no invariant | silent (out of scope) |
| 8 | Edit `new_string` on a LEARNINGS path, `Occurrence count: 2 of 2`, no invariant | deny |
| 9 | deny payload carries `hookSpecificOutput` + `permissionDecision` (contract) | both present |
| 10 | `Invariant:` present but EMPTY (label, blank value), `Occurrence count: 2 of 2` | deny (non-empty value required) |
| 11 | legacy `docs/LEARNINGS.md` path, `Occurrence count: 2 of 2`, no invariant | deny (dual-path scope) |

Cases 3 + 7 are the regression guards for the two scoping decisions (N≥2
threshold; LEARNINGS-only path).

## Deliverable #3c — /spike-check command

### What it does (one sentence)

A slash command that, at **spike start**, emits the stand-in checklist the spike
must satisfy — forcing the spike to be designed to exercise the real binary +
real auth/lifecycle/fixed-port path, the proactive complement to proven-gate's
reactive `Stubbed:` field.

### Why a command, not a hook

A spike's "start" has no mechanical file/command signature a PreToolUse hook can
reliably catch without a high false-positive rate (the hook-injected option was
rejected). A slash command is the clean action surface: the agent (or user)
invokes `/spike-check` when planning a spike, gets the checklist, and answers it
*before* writing any spike code. Pairs with proven-gate end-to-end: #3c at the
start (design the spike right), #1 at the claim (the `Stubbed:` field is the
receipt).

### Form

`commands/spike-check.md` — a checklist-emitting command (no `$ARGUMENTS`
required; optional one-line spike description prefills the framing). It instructs
Claude to present, and require the user/itself to answer, this checklist:

1. **What is the load-bearing behavior?** The one thing that, if it breaks in
   the real smoke, the spike's conclusion was wrong. (Egress-proxy example:
   Proxy-Authorization + helper lifecycle — NOT "bytes flow through a proxy".)
2. **Real binary?** Does the spike run the actual production binary / code path,
   or a hand-rolled stand-in? If stand-in: does it stand in for the
   load-bearing behavior from (1)? If yes → the spike cannot prove the claim;
   redesign it.
3. **Real auth / lifecycle / fixed-port path?** Does the spike exercise the real
   authentication, the real start/stop/reap lifecycle, and the real fixed-port
   contention — or does it skip them with a no-auth / always-fresh / free-port
   shortcut? Each skipped dimension is a hole the real smoke will find.
4. **Hermetic vs real-egress trade-off named?** If the spike needs the network /
   DNS / a corp-locked box, is that dependency stated, and does it match the
   target environment? (LEARNINGS #152 class — a "fast-fail" stand-in that hangs
   on the real path.)
5. **What will the real smoke still have to prove that this spike does NOT?**
   Name it explicitly. That list is the spike's honest residual risk and feeds
   directly into the proven-gate `Stubbed:` field at claim-time.

The command closes by reminding: "If any answer reveals the spike stands in for
the load-bearing behavior, the spike is not conclusive no matter how clean it
runs. Redesign before claiming. When you later write the result, proven-gate
will require `Real path:` + `Stubbed:` — answers 2 + 5 here are those fields."

### Front-matter & registration

```yaml
---
description: Emit the stand-in spike checklist BEFORE a spike, so it's designed to hit the real binary + auth/lifecycle/fixed-port path (change-the-odds #3c).
---
```

Commands are auto-discovered from `commands/` (like `learning.md`,
`primer.md`, `end-session.md`) — no extra wiring. It surfaces as
`/session-continuity:spike-check`.

### Testing

A command body is prose, not an executable hook, so it has no fixture runner.
Validation = the existing command-body discipline:
- `git grep -n 'docs/SESSION_PRIMER\|docs/LEARNINGS' commands/` stays clean
  (LEARNINGS #6 — no stale legacy paths).
- The new command file is listed in README's command table + CHANGELOG.
- Manual read-through: the checklist's five questions map 1:1 to the change-the-
  odds #3c bullets and to proven-gate's two fields (answers 2 + 5).

## Versioning / ship

- `plugin.json` `0.9.0` → `0.10.0` (new hook behavior + new command).
- CHANGELOG entry under a new `0.10.0` heading covering both deliverables.
- `.githooks/pre-commit` version-sync guard no-ops (marketplace.json removed in
  `12a463d`); plugin.json is the single version source.
- Branch `feat/change-the-odds-2-3c` off `main`; one PR; squash-merge.
- Hooks/commands register at SessionStart → live the NEXT session after the
  marketplace update + reinstall.

## Success criteria (the invariants for this workstream)

- **#2:** A future session cannot record a 2nd-occurrence LEARNINGS entry
  without — in the same write — naming the end-state invariant, OR explicitly
  opting out with a reason. Rule 4 becomes a gate, not a hope.
- **#3c:** A spike has a one-command checklist that forces it to be designed
  against the real load-bearing path before any "conclusive" claim, closing the
  gap proven-gate only catches at claim-time.

## Out of scope

- #4 (prune decorative prose → one-line pointers) — lands in the itb memory dir
  + itb LEARNINGS, a separate change after these gates ship.
- No changes to proven-gate, smoke-gate, learnings-surface, or pre-commit-check.
