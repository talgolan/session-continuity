# Hook JSON-escaping fix — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development or superpowers:executing-plans to work this task-by-task. Steps use checkbox (`- [ ]`) syntax.

Proven-gate: N/A — this document is about the gates themselves. Every occurrence of "proven" and "verified" below is either a gate's own trigger vocabulary or quoted hook source, not a claim about untested work.

Evidence-gate: N/A — the words "cleanup" and "teardown" appear only inside quoted test fixtures that exist to trip `evidence-gate`. This plan's own runner starts no service and tears nothing down; it pipes strings into hooks and reads stdout.

Backend-parity: N/A — same reason. "backend parity" appears only as the literal fixture string used to trip `backend-parity-gate`. This plan has one target: the hooks in this repo.

MANDATORY smoke: `meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh`, created in Task 1 and re-run in Task 4. No task in this plan is complete while that runner is red.

**Goal:** Two shipped gates emit malformed JSON when they block a write, so the author sees a parse error instead of the reason and cannot comply. Fix the escaping, and add the one assertion that would have caught it — parsing the output instead of substring-matching it.

**Tech stack:** Bash (hooks), zsh (runner), `python3 -m json.tool` / `json.load` as the parser. No new dependencies.

**Version:** `0.12.1` → `0.12.2` (patch — behavior of the gates is unchanged; only their output encoding is).

---

## The defect

`hooks/proven-gate.sh` and `hooks/smoke-gate.sh` interpolate a reason string containing raw `"` characters into a hand-built JSON object:

```bash
deny() {
  printf '{"hookSpecificOutput":{…,"permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}
```

`proven-gate.sh:89` passes a reason ending in `Stubbed: <what stood in, or \"nothing\">`. The `\"` is a shell escape, so a literal `"` reaches the JSON string and terminates it early.

`smoke-gate.sh:102` has the same flaw from the other direction. It escapes the *captured line* into `offender_esc`, then wraps that value in `\"…\"` — two unescaped quotes, added by the fix that was supposed to make denials diagnosable (see the `[0.12.1]` CHANGELOG entry).

Reproduced on the current `main` (`4eb8d5c`) by feeding each gate a deny-triggering payload and parsing stdout:

- `proven-gate` (`/x/specs/s.md`, content `Approach is proven, option A.`) → `Expecting ',' delimiter: line 1 column 333`
- `smoke-gate` weak-word branch (`/x/plans/p.md`, content `The smoke test is optional for this change.`) → `Expecting ',' delimiter: line 1 column 155`
- `smoke-gate` no-smoke branch, `evidence-gate` (both branches), `flaky-gate`, `backend-parity-gate` → parse cleanly today

**Impact.** The gate still blocks, so nothing unsafe gets written, but the block is undiagnosable: the reason never renders, and the author has no way to learn which field to add or which escape hatch applies. In practice this reads as the tool being broken rather than the write being rejected.

### Why the runners are green

Every runner asserts the deny path with a substring test:

```zsh
assert "2 proven, no fields -> deny" 'deny' "$out"
```

The literal `deny` appears in malformed output just as readily as in valid output, so `2026-06-17-proven-gate-smoke.zsh` reports 12/12 against a hook that emits unparseable JSON. The test measures a proxy (a substring) rather than the invariant (the payload parses). That is the actual root cause; the escaping is only the symptom.

### End-state invariant

Every JSON object any hook in this plugin writes to stdout parses as JSON, for every reason string, including ones carrying quotes, backslashes, or control characters — enforced by a parser in the validation suite, never by substring match.

---

## Global constraints

- **Artifact paths:** validation → `meta/superpowers/validation/`, plans → `meta/superpowers/plans/` (CLAUDE.md). Not `docs/`.
- **Output contract (LEARNINGS #1):** deny is `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"…"}}` + `exit 0`. Silent allow is bare `exit 0`. This plan does not change the contract, only the encoding of the reason.
- **Escape order matters:** backslash first, then double-quote. Reversing it re-escapes the backslashes the quote rule just inserted.
- **Control characters:** any raw C0 control byte (`0x00`–`0x1F` — tab, newline, CR, and the rest) is illegal inside a JSON string (RFC 8259) and `json.load` rejects it. `smoke-gate` interpolates a line captured by `grep`, which can carry a tab; fold the whole C0 range, not just `\n\t\r`, so the invariant holds for any control byte a future capture might carry, not only the three seen so far.
- **Self-reference trap (LEARNINGS #7):** verify only through the fixture runner. Never self-scan a real spec or plan to check a gate.
- **Sandbox artifact, not a repo bug:** `learnings-surface.sh:87` (`done <<< "$entries"`) and `occurrence-gate.sh:83` (`done <<EOF`) need a temp file for the here-document. Under a restricted sandbox that write is denied, and `2026-06-15-fire-before-action-smoke.zsh` reports 9/3 and `2026-06-17-occurrence-gate-smoke.zsh` reports 5/7 for that reason alone. Run the suite in a normal shell, where all seven runners are expected green before you start. If they are not, stop — that is a different problem than this one.
- **Working tree:** `main` currently carries an unstaged `.session-continuity/SESSION_PRIMER.md` and an untracked `.itb.json`. Neither belongs to this fix. Branch off, and stage files by explicit path — never `git add -A`.
- **Branch:** `fix/hook-json-escaping`, PR into `main` at `github.com/talgolan/session-continuity`.

---

## Task 1: The contract runner (write it first, watch it fail)

**Files:** create `meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh`

This runner is the mechanism that keeps the invariant true for gates that do not exist yet. It does two things the per-gate runners do not: it parses, and it fails when a gate has no fixture at all.

- [ ] **Step 1: Create the runner**

```zsh
#!/usr/bin/env zsh
# Hook JSON output-contract runner. Hermetic: synthetic payloads in, stdout out.
#
# Invariant: every JSON object a hook writes to stdout PARSES. Asserted with a
# real parser, never with a substring match — a substring assert on 'deny'
# passes against malformed JSON, which is precisely how the proven-gate and
# smoke-gate defects shipped green (see 2026-08-12-hook-json-escaping-fix.md).
#
# The per-gate runners still own behaviour (which input denies, which allows).
# This runner owns encoding only, for every gate at once.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
hooks="$repo/hooks"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

# parses <desc> <hook-basename> <payload>
# Requires BOTH that the hook emitted something and that it parses. A gate that
# stays silent here means the fixture stopped triggering it — also a failure,
# because then this runner is asserting nothing.
parses() {
  local desc="$1" hook="$2" payload="$3" out
  out="$(printf '%s' "$payload" | bash "$hooks/$hook" 2>/dev/null)"
  if [[ -z "$out" ]]; then
    bad "$desc (expected a JSON object, got silence — fixture no longer triggers)"
    return 0
  fi
  if printf '%s' "$out" | python3 -c 'import sys, json; json.load(sys.stdin)' 2>/dev/null; then
    ok "$desc"
  else
    bad "$desc — stdout is not valid JSON: $out"
  fi
}

spec_payload()  { printf '{"file_path":"/x/specs/s.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }
plan_payload()  { printf '{"file_path":"/x/plans/p.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }
learn_payload() { printf '{"file_path":"/x/.session-continuity/LEARNINGS.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }

# One deny fixture per gate. Keep in sync with the completeness check below.
parses "proven-gate: claim, no fields" \
  proven-gate.sh "$(spec_payload 'Approach is proven, option A.')"
parses "smoke-gate: weak word beside smoke" \
  smoke-gate.sh "$(plan_payload 'The smoke test is optional for this change.')"
parses "smoke-gate: engine keyword, no smoke task" \
  smoke-gate.sh "$(plan_payload 'This plan rebuilds the binary and restarts the daemon.')"
parses "evidence-gate: first branch" \
  evidence-gate.sh "$(spec_payload 'Smoke section 01: runs the container then does cleanup at the end.')"
parses "evidence-gate: second branch" \
  evidence-gate.sh "$(spec_payload 'Smoke section 02: wait_for the service to come up, timeout 60s.')"
parses "flaky-gate: transient, no cause named" \
  flaky-gate.sh "$(learn_payload 'The build failed again, looks transient.')"
parses "backend-parity-gate: one named only" \
  backend-parity-gate.sh "$(plan_payload 'This plan needs full backend parity coverage in smoke.')"
parses "occurrence-gate: repeat, no invariant" \
  occurrence-gate.sh "$(learn_payload 'Occurrence count: 3 of 5\nYet another trigger patch.')"

# Adversarial reasons: a captured line carrying the characters that break a
# hand-built JSON string. smoke-gate echoes the matched line into its reason,
# so these exercise the interpolation path end to end.
#
# Both fixture strings are pre-encoded as if they were already valid JSON
# content (this repo's hooks read tool_input off the raw JSON text, so a
# real payload always arrives properly escaped). `\\\"` (JSON-decodes to one
# literal backslash + one literal quote) puts an actual `"` next to "old" in
# the decoded content, so the captured offender line itself carries a quote.
# `\\\\` (JSON-decodes to two literal backslashes) puts two literal `\`
# bytes in the decoded path text — more than the single backslash a real
# Windows-style path would carry, but it still exercises backslash-doubling
# in json_escape() the same way one would.
parses "smoke-gate: offender line with quotes" \
  smoke-gate.sh "$(plan_payload 'The smoke test is optional per the \\\"old\\\" policy.')"
parses "smoke-gate: offender line with backslashes" \
  smoke-gate.sh "$(plan_payload 'The smoke test is optional, see C:\\\\tmp\\\\notes.')"

# Completeness: every gate must own at least one fixture above. A newly added
# gate fails this runner until someone adds one — that is the point.
covered=(proven-gate.sh smoke-gate.sh evidence-gate.sh flaky-gate.sh backend-parity-gate.sh occurrence-gate.sh)
for f in "$hooks"/*-gate.sh; do
  b="${f:t}"
  if (( ${covered[(Ie)$b]} )); then
    ok "coverage: $b has a fixture"
  else
    bad "coverage: $b has NO fixture in this runner — add one"
  fi
done

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: `chmod +x meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh`**

- [ ] **Step 3: Run it and confirm it fails for the right reasons**

Run: `zsh meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh`

Expect red, with the failures naming `proven-gate: claim, no fields` and the three `smoke-gate` weak-word cases as "not valid JSON". The `evidence-gate`, `flaky-gate`, `backend-parity-gate`, `occurrence-gate`, and `smoke-gate: engine keyword` cases and all six coverage checks should pass already. A different failure shape means the fixtures drifted from the gates — reconcile before continuing.

- [ ] **Step 4: Commit the red runner**

```bash
git add meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh
git commit -m "test(hooks): JSON output-contract runner (currently red)

Parses every gate's deny output instead of substring-matching it. Red on
proven-gate and smoke-gate's weak-word branch, which emit unescaped quotes.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Escape the reason at the point of emission

**Files:** modify `hooks/proven-gate.sh`, `hooks/smoke-gate.sh`, `hooks/evidence-gate.sh`, `hooks/flaky-gate.sh`, `hooks/backend-parity-gate.sh`, `hooks/occurrence-gate.sh`

All six carry a byte-identical `deny()`. Fixing only the two that are broken today leaves four one bad reason string away from the same defect, so all six get the same change. The escape lives inside `deny()` rather than at each call site: a call site that forgets is how this happened.

Each gate stays standalone. A shared sourced library would be less duplication, but a sourcing failure under `set -euo pipefail` would take out every gate at once and degrade them to silently off — worse than four copies of four lines. The contract runner is what keeps the copies honest.

- [ ] **Step 1: Replace `deny()` in each of the six gates**

Existing block (identical in all six, near the top of the decision section):

```bash
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}
```

Replacement:

```bash
# Escape a value for embedding in a JSON string literal. Backslash first, then
# double-quote — the reverse order re-escapes the backslashes the quote rule
# just inserted. Raw control characters are illegal inside a JSON string
# (RFC 8259) and make the payload unparseable, so every C0 byte (0x00-0x1F —
# tab and newline are the ones a grep capture is likely to carry, but the
# fold covers the whole range, not just those) collapses to a space.
json_escape() {
  printf '%s' "$1" | sed -E 's/\\/\\\\/g; s/"/\\"/g' | tr '\000-\037' ' '
}

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(json_escape "$1")"
  exit 0
}
```

- [ ] **Step 2: Drop `smoke-gate`'s now-redundant pre-escape**

`hooks/smoke-gate.sh` lines 100–102 currently read:

```bash
    # JSON-escape the captured line: backslash first, then double-quote.
    offender_esc="$(printf '%s' "$offender" | sed -E 's/\\/\\\\/g; s/"/\\"/g')"
    deny "Smoke task looks optional/deferred (matched: \"${offender_esc}\"). If this is …"
```

Delete the comment and the `offender_esc` assignment, and pass the raw capture:

```bash
    deny "Smoke task looks optional/deferred (matched: \"${offender}\"). If this is …"
```

Leaving the pre-escape in place would double-escape, rendering the reason with literal `\"` around the matched line. The `\"` wrapping in the reason string stays as it is: those are shell escapes producing real quote characters, which `json_escape` then encodes correctly, so the author sees the matched line in ordinary quotes.

- [ ] **Step 3: Leave every reason string otherwise untouched**

Including `proven-gate.sh:89`'s `or \"nothing\"`. The whole point is that a reason may now contain quotes. Rewording it to dodge the encoding would fix the one string and leave the defect.

- [ ] **Step 4: Run the contract runner — expect green**

Run: `zsh meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh`
Expect: `Result: 16 passed, 0 failed` (10 fixtures + 6 coverage checks), exit 0.

- [ ] **Step 5: Run the full validation suite — no behavior regressed**

```bash
for r in meta/superpowers/validation/*.zsh; do echo "== $r"; zsh "$r" | tail -1; done
```

Expect all eight green. The per-gate runners assert which inputs deny; this change alters only how the reason is encoded, so any behavior failure here means the edit went wider than intended.

- [ ] **Step 6: shellcheck**

Run: `shellcheck hooks/*.sh`
Expect: no output, exit 0.

- [ ] **Step 7: Confirm the reason is now readable, not merely parseable**

```bash
printf '{"file_path":"/x/specs/s.md","tool_name":"Write","tool_input":{"content":"Approach is proven, option A."}}' \
  | bash hooks/proven-gate.sh \
  | python3 -c 'import sys, json; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])'
```

Expect the full sentence, ending with `Proven-gate: N/A — <reason> for a non-claim use (quoting, glossary, a doc about the gate).`, with `"nothing"` in real quotes. A parse error, or a visible `\"`, means Step 2 was applied wrong.

- [ ] **Step 8: Commit**

```bash
git add hooks/proven-gate.sh hooks/smoke-gate.sh hooks/evidence-gate.sh \
        hooks/flaky-gate.sh hooks/backend-parity-gate.sh hooks/occurrence-gate.sh
git commit -m "fix(hooks): JSON-escape deny reasons so blocks are readable

proven-gate and smoke-gate emitted unparseable JSON whenever the reason
carried a quote, so the author saw a parse error instead of the reason and
could not act on it. Escape inside deny() in all six gates, not at the call
sites, and drop smoke-gate's pre-escape that now double-escapes.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Record why the tests missed it

**Files:** modify `.session-continuity/LEARNINGS.md`

LEARNINGS #1 already covers the shape of the hook contract. What it does not cover is that a well-formed shape can still be unparseable, and that a substring assert cannot tell the difference. Extend it rather than opening a near-duplicate entry.

- [ ] **Step 1: Append to entry #1, under "Hook scripting (SessionStart / PreToolUse)"**

Add after the existing Fix block:

```markdown
**Second trap — valid shape, invalid JSON (2026-08-12).** Emitting the right
keys is not the same as emitting parseable JSON. `proven-gate` and `smoke-gate`
built the object with `printf` and interpolated a reason containing a literal
`"` — `Stubbed: <what stood in, or \"nothing\">` in one, a `\"${offender}\"`
wrapper around a captured line in the other. The string terminates early, the
payload does not parse, and the author sees a parse error where the reason
should be. The gate still blocks, so nothing unsafe is written; it is
undiagnosable, which reads as a broken tool.

Both hooks' runners were green throughout, because they assert with
`[[ "$out" == *deny* ]]`. The substring `deny` is present in malformed output
too, so the assert measures a proxy, not the invariant. The smoke-gate case
arrived in v0.12.1 — in the change whose stated purpose was to make denials
diagnosable by echoing the matched line.

**Invariant:** every JSON object a hook writes parses. Enforced in
`meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh`, which
pipes each gate's deny output through a real parser and fails when a
`hooks/*-gate.sh` has no fixture. When you add a gate, add a fixture. Assert on
parsed structure, never on a substring of serialized output.
```

- [ ] **Step 2: Commit**

```bash
git add .session-continuity/LEARNINGS.md
git commit -m "docs(learnings): substring asserts hide malformed hook JSON

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Release 0.12.2

**Files:** modify `.claude-plugin/plugin.json`, `CHANGELOG.md`

No README change: the gates' user-visible behavior is unchanged, and the README does not document the wire format.

- [ ] **Step 1: Bump `.claude-plugin/plugin.json` `"version"` from `0.12.1` to `0.12.2`**

- [ ] **Step 2: Add the CHANGELOG section above `## [0.12.1] — 2026-08-06`**

```markdown
## [0.12.2] — 2026-08-12

### Fixed
- **Unreadable blocks from `proven-gate` and `smoke-gate`.** Both built their
  deny payload by interpolating the reason into a hand-written JSON string, so
  a reason containing a double quote terminated the string early and the object
  did not parse. `proven-gate` hit this on every block (its reason quotes the
  word `"nothing"`); `smoke-gate` hit it on the weak-word branch added in
  0.12.1, which wraps the matched line in quotes. The gate still blocked, but
  the reason never reached the author, so there was no way to see which field
  was missing or which escape hatch applied. `deny()` now JSON-escapes its
  argument in all six gates — backslash before quote, with every C0 control
  byte (0x00-0x1F, not just tab/newline/CR) folded to a space, since raw
  control characters are illegal inside a JSON string. Gate behaviour (what
  denies, what passes) is unchanged.

### Added
- **`2026-08-12-hook-json-contract-smoke.zsh`.** Pipes every gate's deny output
  through a real JSON parser instead of substring-matching it, which is why the
  defect above shipped green, and fails when a `hooks/*-gate.sh` has no fixture
  so new gates cannot skip the check.
```

- [ ] **Step 3: Verify the version guard and the JSON**

```bash
python3 -m json.tool .claude-plugin/plugin.json >/dev/null && echo "plugin.json OK"
bash .githooks/pre-commit; echo "rc=$?"
```

Expect `plugin.json OK` and `rc=0`.

- [ ] **Step 4: Full suite once more, then commit**

```bash
for r in meta/superpowers/validation/*.zsh; do echo "== $r"; zsh "$r" | tail -1; done
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore(release): 0.12.2 — readable gate denials

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin fix/hook-json-escaping
gh pr create --title "fix(hooks): JSON-escape deny reasons (v0.12.2)" --body "…"
```

Body should carry: the reproduction, the note that the runners were green against broken output, and the parsed-reason output from Task 2 Step 7 as evidence.

- [ ] **Step 6: Reinstall the plugin and confirm the live path**

The installed copy under `~/.claude/plugins/cache/talgolan/session-continuity/` is what actually runs; the fix does nothing for a live session until it is refreshed. After reinstalling, attempt a write that trips `proven-gate` and confirm the block now shows its reason as prose. The hermetic runner proves the encoding; only this proves the path a user hits.

---

## Deferred, with reasons

- **`learnings-surface.sh:92` and `pre-commit-check.sh:101`** interpolate into `additionalContext` in the same hand-built style. `learnings-surface` escapes backslash and quote inline but not control characters; its titles come from a tab-separated table, so a tab cannot reach the value and no failure was observed. `pre-commit-check.sh:101` interpolates `$primer_rel` (the primer's repo-relative path, e.g. `.session-continuity/SESSION_PRIMER.md`) with **no** escaping at all, not even the inline backslash/quote pass `learnings-surface` has — safe only because that path is derived from the repo's own layout, never from file content or user input, so it cannot carry a quote or backslash in practice. Same class, no reproduction in either case — worth folding into the shared treatment later, out of scope for a fix whose value is that it is narrow and verifiable.
- **The other runners' substring asserts** stay as they are. They own behavior, and the contract runner now owns encoding for all of them. Rewriting six runners to duplicate the parse check would spread the invariant instead of centralizing it.

## Self-review

- Both reproduced defects fixed → Task 2 Steps 1–2, asserted by Task 1's fixtures.
- Four unaffected gates hardened against the same defect → Task 2 Step 1 (all six), guarded by the coverage check.
- Root cause (assert on a proxy, not the invariant) fixed → Task 1's parser, plus the coverage check that extends it to gates not yet written.
- Recurrence recorded where the next author will read it → Task 3.
- Fixture count consistent between Task 1 Step 3 and Task 2 Step 4: 10 fixtures + 6 coverage checks = 16.
- No placeholders. The one `--body "…"` is deliberate: its content depends on Task 2 Step 7's actual output.
