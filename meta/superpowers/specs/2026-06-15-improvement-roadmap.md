# Improvement Roadmap — session-continuity

**Date:** 2026-06-15
**Status:** proposed
**Baseline:** v0.8.0

## Purpose

A prioritized backlog of improvements across four axes — capability,
performance, scalability, security — derived from a full read of the
v0.8.0 implementation plus the 2026-05-21 usage-feedback doc
(`meta/superpowers/recommendations/improvements_20260521.md`). Several
items from that earlier doc already shipped (3× flaky-test retry, the
duplicate-number guard, the four end-session heuristics with transcript
mining, the outstanding-items overlay, the "Last entry" auto-bump, the
session-start status line) and are excluded here.

Items are ordered by leverage: effort-to-value, with prerequisites
before the work that depends on them. Each carries an explicit
acceptance criterion so a future session can verify completion rather
than assert it.

## Constraints (inherited, non-negotiable)

- **No new runtime dependency.** Hooks parse stdin with `grep`/`sed`,
  not `jq`. Every item below preserves this.
- **Commands stage, never commit. Hooks remind or gate, never write
  the user's files.** Automatic capture stays out — trust comes from
  deliberate capture.
- **Surface stays small.** One skill, three commands, a handful of
  hooks. New gates are allowed (they fit the "gate, don't advise"
  shape); new abstraction layers are not.
- **Plain text in git remains the only storage.**

---

## P0 — Quick wins (low risk, ship together)

### 1. `learnings-surface` early-exit when no triggers exist

**Axis:** performance.

**Problem.** `hooks/learnings-surface.sh` fires on every Bash, Write,
and Edit tool call. On each invocation it re-reads and re-parses the
entire LEARNINGS file with an `awk` pass before deciding there is
nothing to do. The overwhelmingly common case is a repo that has
authored zero `Trigger:` lines, yet that repo still pays the full
`cat` + two `grep`/`sed` extractions + `awk` pass on every action.

**Change.** After the `[ -f "$learnings" ]` guard, add a single cheap
short-circuit before the `awk` pass:

```bash
grep -q '^Trigger:' "$learnings" 2>/dev/null || exit 0
```

**Effort.** One line.

**Risk.** None. The `awk` already emits nothing when no triggers
exist; this only skips the work sooner. Covered by the existing
hermetic hook tests.

**Acceptance.** A repo whose LEARNINGS contains no `Trigger:` line
spawns no `awk` process from this hook (verify by tracing, or by a
unit test asserting early exit). A repo with at least one `Trigger:`
line behaves exactly as before.

### 2. `version-check` validates the release tag before echoing it

**Axis:** security.

**Problem.** `hooks/version-check.sh` interpolates `$latest` (a GitHub
release tag pulled from the API) directly into a `<system-reminder>`
block that lands in Claude's context. The extracting regex stops at the
next quote, so string-breakout is hard, but a compromised or
mischievous upstream tag still reaches the model's context unsanitized.
The release workflow already validates tags against a strict semver
regex; the consumer side does not.

**Change.** Before emitting the reminder, validate `$latest` against
the same semver pattern the release workflow uses
(`^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?(\+[A-Za-z0-9.-]+)?$`). On
mismatch, exit 0 silently — a malformed tag is treated as "no update."

**Effort.** ~5 lines.

**Risk.** Low. A legitimate non-semver tag would stop producing a
nudge, but the plugin's own tags are always semver.

**Acceptance.** A crafted tag containing reminder-breaking characters
produces no output. A normal `vX.Y.Z` tag still nudges.

### 3. Bound the trigger-matching loop against pathological regexes

**Axis:** security.

**Problem.** `learnings-surface.sh` runs `grep -Eq -- "$tre"` where
`$tre` is a regex taken from the cloned repo's LEARNINGS.md, matched
against the full JSON payload, automatically, on the first tool call
after the repo is opened. The trust model ("you trust the repo as much
as its code") is defensible, but a pathological regex against a large
payload can hang the hook (ReDoS / denial of service).

**Change.** Cap the bytes piped into `grep` (e.g. `head -c 65536` on
`$match_text`) and wrap the per-trigger match in a short `timeout`
(e.g. `timeout 1s grep -Eq ...`) where `timeout` is available, falling
back to the bare call when it is not. Document the repo-trust
assumption explicitly in SECURITY.md (see item 12).

**Effort.** Small.

**Risk.** Truncating the payload could miss a match in a very large
command. Acceptable: triggers are authored to fire on short,
characteristic substrings near the front of a command.

**Acceptance.** A LEARNINGS entry with a catastrophic-backtracking
trigger regex and a large synthetic payload does not hang the hook
beyond the timeout.

---

## P1 — High-value features

### 4. `SessionEnd` nudge toward the close-out ritual

**Axis:** capability.

**Problem.** `/session-continuity:end-session` is the highest-value
command and the only one that mines a session for learnings, yet it
fires only on manual invocation. The 2026-05-21 field note records a
six-hour session where it never fired. There is no "session is ending"
prompt anywhere in the workflow.

**Change.** Add a `SessionEnd` (or `Stop`) hook that runs a cheap
subset of the Step-2 heuristics over the transcript and, when one or
more candidates surface, injects a non-blocking reminder: "N events
this session look LEARNINGS-worthy — run `/session-continuity:end-session`
to review before you close." The hook must not write files and must not
auto-capture; it only nudges, preserving the "not automatic" principle.
If the transcript is unreachable, it stays silent.

**Effort.** Medium. Reuses the transcript-resolution logic already
specified in `commands/end-session.md` Step 2.

**Risk.** Noise if it fires on every session. Gate it on at least one
heuristic actually triggering, and respect a
`SESSION_CONTINUITY_SKIP_ENDSESSION_NUDGE=1` opt-out for parity with
the update-check opt-out.

**Acceptance.** A session containing a retry burst or a `fix:` commit
after a long investigation produces the nudge at session end; a quiet
session produces nothing.

### 5. Secret-write gate on `.session-continuity/*`

**Axis:** security + capability.

**Problem.** The plugin's design philosophy is "gate mechanically,
don't just advise," yet "never put secrets in these files" is enforced
by prose alone. Both files are git-committed, so a leaked credential is
public the moment it lands.

**Change.** Add a `PreToolUse` Write/Edit hook scoped to
`.session-continuity/*` that blocks writes whose content matches
obvious secret shapes (`-----BEGIN [A-Z ]+PRIVATE KEY-----`,
AWS-access-key pattern `AKIA[0-9A-Z]{16}`, `xox[baprs]-` Slack tokens,
long high-entropy base64/hex runs). Provide an explicit override hatch
matching the `smoke-gate` precedent: a line like
`Secret-OK: <reason>` passes the gate. Deny with a clear reason naming
the matched pattern (never echo the matched value).

**Effort.** Medium. Mirrors `smoke-gate.sh` structure (self-scope by
path, decode content, deny-with-reason, escape hatch).

**Risk.** False positives on entries that legitimately discuss a
redacted key. The override hatch and pattern-not-value reporting keep
this manageable.

**Acceptance.** Writing a fake AWS key into `SESSION_PRIMER.md` is
denied; the same write with a `Secret-OK:` line passes; ordinary prose
is unaffected. The denial message never contains the secret.

### 6. `/session-continuity:doctor` integrity command

**Axis:** capability + scalability.

**Problem.** The duplicate-number guard only runs inside
`/session-continuity:learning`. The README now advertises hand-editing
as a supported workflow, but a hand-edited file is never validated
until the next append. The author's real LEARNINGS file accumulated
five duplicate-number sets this way.

**Change.** Add a read-only `/session-continuity:doctor` command that
reports (and never auto-fixes):

- Duplicate `### N.` entry numbers, with line numbers.
- Leftover `{{...}}` placeholder tokens in either file.
- A stale `git log --oneline -5` block in the primer.
- `Trigger:` regexes that fail to compile (`grep -E` returns a usage
  error) or that match nothing across recent `git log` subjects.
- `see #N` cross-references pointing at a number no entry carries.

**Effort.** Medium (prose command + a small validation helper script,
or inline bash in the command body).

**Risk.** Low — read-only by contract.

**Acceptance.** Running `doctor` against a file with a known duplicate,
a leftover placeholder, and a dangling cross-ref reports all three and
changes nothing on disk.

### 7. Auto-generated "Symptoms index" in LEARNINGS

**Axis:** scalability.

**Problem.** Retrieval, not storage, is the LEARNINGS ceiling. The
author's project reached 71 entries across 9 sections with no index.
Lookup-by-symptom depends on guessing the right grep term; a newcomer
hitting "container can't reach archive.ubuntu.com" won't think to grep
"DNS."

**Change.** Have `/session-continuity:learning` (and `doctor`)
regenerate a "Symptoms index" block at the top of LEARNINGS by
extracting the `**Symptom.**` line every entry already carries, sorted,
each linking to its entry number. Mark the block with HTML-comment
fences so regeneration is idempotent and never clobbers hand-written
content.

**Effort.** Medium.

**Risk.** The index can drift if entries are hand-edited without
re-running a command; `doctor` flags drift as a mitigation.

**Acceptance.** After appending an entry, the Symptoms index contains a
sorted line for its symptom pointing at the new number; regenerating
twice produces no diff.

---

## P2 — Structural (largest payoff, larger change)

### 8. Split the primer into volatile and stable halves

**Axis:** performance + scalability.

**Problem.** `SESSION_PRIMER.md` loads in full at every session start.
The 2026-05-21 measurement put a 320-line primer near ~25K tokens per
turn. The file mixes content that rotates every commit (current state,
`git log` block, outstanding items, test counts) with content that
changes monthly at most (ground rules, repo layout, modules table,
conventions, "where to look").

**Change.** Keep `SESSION_PRIMER.md` as the small volatile shortlist
(target ≤80 lines). Move the stable content to a sibling
`.session-continuity/PROJECT_CONTEXT.md`, linked from the primer's
"First things first." Both still load at session start, but
`PROJECT_CONTEXT.md` is cache-eligible while the primer rotates. Update
the templates, `commands/primer.md` (init + refresh), and the
session-start reminder to know about both files.

**Effort.** Large. Touches templates, the primer command, hooks, and
the README. Needs a migration story for existing single-file primers
(detect a primer with stable sections present and offer to split).

**Risk.** This is a second file-layout change; LEARNINGS #6 warns that
path migrations leave stale references behind. Budget a
`git grep` sweep for every reference and a doctor check.

**Acceptance.** A fresh init produces both files; a refresh updates
only the volatile file's rotating sections; `git grep` finds no
single-file assumptions left in commands or hooks.

### 9. Archive closed outstanding items on refresh

**Axis:** scalability. Depends on item 8.

**Problem.** Closed outstanding items accumulate in the primer and are
re-read every session (the author saw 8 of 15 struck-through). The
trail of *why* something closed has value, but not in the hot path.

**Change.** During refresh, move items closed more than ~30 days ago
into a "Resolved decisions" appendix in `PROJECT_CONTEXT.md`,
preserving the close reason. The active outstanding list stays short.

**Effort.** Medium, but cleanest once item 8 exists (the appendix lives
in the stable file).

**Risk.** Deciding "closed" reliably needs an explicit status marker —
see item 10.

**Acceptance.** An item marked done with a date >30 days back is moved
to the appendix on the next refresh; recently-closed items stay
visible.

### 10. Conflict-resistant LEARNINGS identifiers and durable cross-refs

**Axis:** scalability.

**Problem.** Global `max + 1` numbering collides when two branches each
add an entry — exactly the duplicate-number sets the author hit. The
guard detects the collision but resolution is manual. Separately,
`see #N` cross-references rot when an entry is renumbered.

**Change.** Two related moves, sequenceable independently:

- **Identifiers that don't collide on parallel creation.** Offer an
  ID scheme that is unique without coordination — a date-plus-suffix
  (`2026-06-15a`) or a short slug — while keeping human-readable
  ordering. Preserve backward compatibility: existing numeric entries
  keep their numbers.
- **Slug-based cross-references.** Introduce `[[slug]]` links that
  resolve to whichever entry owns that slug, with a slug→id index in a
  comment block. Matches the `[[name]]` convention the auto-memory
  store already uses.

**Effort.** Large, and partly a policy decision (numeric IDs are
load-bearing in cross-refs and in the existing entries). Could ship as
"new entries may use slugs; numbers stay valid."

**Risk.** Churn in a file whose stability is the whole point. Stage
carefully; never renumber existing entries.

**Acceptance.** Two branches each adding an entry merge without an ID
collision; a `[[slug]]` reference still resolves after the target
entry's position changes.

---

## P3 — Maintainability and hardening

### 11. Remove the legacy `docs/` path support (v1.0)

**Axis:** maintainability + security surface.

**Problem.** The v0.5.0 migration is years past at v0.8.0, but the
`docs/` fallback still branches through `session-start.sh`,
`pre-commit-check.sh`, `learnings-surface.sh`, `commands/primer.md`
(Migrate + Conflict modes), `commands/learning.md`, and
`commands/end-session.md`. LEARNINGS #6 is literally about stale
`docs/` references surviving a migration. The README migration content
was already removed.

**Change.** Add a deprecation note in a v0.9 release ("`docs/` support
will be removed in v1.0; run `/session-continuity:primer` once to
migrate"), then in v1.0 delete every `docs/` fallback branch and the
Migrate/Conflict modes. Keep a single clear error directing any
remaining legacy user to a one-time manual `git mv`.

**Effort.** Medium, mostly deletion. Pair with a `git grep docs/` sweep
and a doctor check.

**Risk.** A user who never migrated loses automatic handling. Mitigated
by the v0.9 deprecation window and a clear error message.

**Acceptance.** Post-removal, `git grep -n 'docs/SESSION_PRIMER\|docs/LEARNINGS'`
returns nothing outside CHANGELOG history; a legacy repo gets a clear
one-line migration instruction rather than silent handling.

### 12. Document the repo-trust model in SECURITY.md

**Axis:** security (documentation).

**Problem.** Opening a cloned repo and starting a session runs that
repo's `Trigger:` regexes automatically on the first tool call. This is
the same trust level as running the repo's code, but it is not stated
anywhere a user would look.

**Change.** Add a short SECURITY.md section: the hooks execute
repo-controlled regexes and read repo-controlled plan/LEARNINGS
content; treat an untrusted repo's session-continuity files with the
same caution as its build scripts. Cross-reference items 3 (timeout)
and the existing no-`eval` guarantees.

**Effort.** Small (docs).

**Risk.** None.

**Acceptance.** SECURITY.md names the repo-trust assumption and the
automatic-execution surface of `learnings-surface`.

### 13. Trigger authoring aids

**Axis:** capability.

**Problem.** A `Trigger:` line is a hand-written regex with no way to
test whether it fires or what it matches. Authoring is error-prone and
silent failures (a trigger that never fires) are invisible.

**Change.** Add a dry-run mode to `learnings-surface.sh`
(`--explain "<sample command or path>"`) that prints which entries
would fire and why, usable from the command line and from the `doctor`
check. Optionally surface "this trigger has never matched recent
history" as a `doctor` warning (overlaps item 6).

**Effort.** Small-to-medium.

**Risk.** Low — additive, off the hot path.

**Acceptance.** Running the dry-run against a sample string reports the
matching entries; a deliberately non-matching trigger is flagged.

### 14. Generalize the version-sync pre-commit guard

**Axis:** scalability + maintainability.

**Problem.** `.githooks/pre-commit` extracts the *first* `"version"`
field from `marketplace.json`. A second plugin entry would silently
break the check. Documented as a known limitation in the script's own
comments.

**Change.** When/if a second plugin is added, parse the version of the
entry whose `name` matches `plugin.json`'s `name`, rather than the
first match. Until then, leave a TODO referencing this item so the
assumption is not rediscovered.

**Effort.** Small, deferred until a second plugin actually exists.

**Risk.** None today.

**Acceptance.** With two plugin entries, the guard compares the correct
one against `plugin.json`.

---

## Suggested release grouping

- **v0.8.x patch:** items 1, 2, 3 (P0 — pure hardening, no behavior
  change for users).
- **v0.9.0 minor:** items 4, 5, 6, 7 (P1 — new gates and commands,
  additive), plus the item 11 deprecation *notice*.
- **v0.10.0 / structural:** items 8, 9, 10 (P2 — primer split and
  LEARNINGS identifier work; sequence 8 before 9).
- **v1.0.0:** item 11 removal, items 12–14 cleanup.

## Open questions

1. Item 8's primer split is the largest single token-cost win but also
   the largest blast radius. Confirm the appetite for a second
   file-layout change before scheduling it.
2. Item 10's identifier change touches the one file whose stability is
   the product's core promise. Decide whether to adopt slugs additively
   (numbers stay) or commit to a full scheme change.
3. Item 5's secret-pattern list needs a maintained source. Decide
   whether to inline a small pattern set or depend on an external
   ruleset (the latter risks the no-dependency constraint).
