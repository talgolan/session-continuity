# Occurrence-counter gate + spike-check command — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship change-the-odds deliverables #2 (a PreToolUse gate that blocks a 2nd-occurrence LEARNINGS entry lacking an end-state `Invariant:` line) and #3c (a `/spike-check` slash command emitting the stand-in checklist at spike start), in one PR.

**Architecture:** #2 reuses the `hooks/proven-gate.sh` skeleton verbatim — read payload, extract `file_path`, self-scope, decode content, escape-hatch-first, detect-trigger, require-field, `deny` via `hookSpecificOutput` JSON. New `hooks/occurrence-gate.sh` wired as a 4th PreToolUse `Write|Edit` entry; hermetic `.zsh` fixture runner. `/learning` gains two optional fields so the command authors compliant entries by construction. #3c is a prose-only command file, auto-discovered from `commands/`.

**Tech Stack:** Bash (hooks), zsh (smoke runners), Markdown (commands/specs/plans). No new dependencies.

## Global Constraints

- **Repo:** `~/active_development/TG/session-continuity-plugin`. Branch `feat/change-the-odds-2-3c` (already created, spec committed at `6506e4c`).
- **Agent meta-artifacts** go under `meta/superpowers/`, NEVER `docs/superpowers/` (project CLAUDE.md; LEARNINGS #5).
- **Output contract (LEARNINGS #1):** PreToolUse `deny` emits `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"…"}}` then `exit 0`. Silent allow = bare `exit 0`, no stdout.
- **Self-reference (LEARNINGS #7):** verify the gate ONLY via the hermetic fixture runner. Never self-scan a real LEARNINGS.md. Do NOT tighten the escape hatch to line-start anchoring.
- **Security:** `$file_path` / `$content` used only in path tests + greps, never `eval`'d. No network, no writes, no subprocess beyond `grep`/`sed`/`awk`.
- **Version:** `plugin.json` `0.9.0` → `0.10.0`. plugin.json is the single version source (marketplace.json removed in `12a463d`; `.githooks/pre-commit` no-ops).
- **Commit style:** Conventional Commits. No `Co-Authored-By` unless requested.

---

### Task 1: occurrence-gate hook + smoke runner

**Files:**
- Create: `hooks/occurrence-gate.sh`
- Create: `meta/superpowers/validation/2026-06-17-occurrence-gate-smoke.zsh`
- Modify: `hooks/hooks.json` (add 4th PreToolUse Write|Edit entry)

**Interfaces:**
- Consumes: the PreToolUse JSON payload on stdin (`file_path`, `tool_name`, `tool_input.content` for Write / `tool_input.new_string` for Edit).
- Produces: a `deny` JSON object on stdout (block) or silence (allow). No exported functions.

- [ ] **Step 1: Write the smoke runner (the failing test)**

Create `meta/superpowers/validation/2026-06-17-occurrence-gate-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# Smoke runner for the occurrence-gate hook. Hermetic: pipes synthetic
# PreToolUse payloads into hooks/occurrence-gate.sh, asserts JSON (or silence).
# See LEARNINGS #7 — the ONLY correct way to verify the gate; never self-scan a
# real LEARNINGS.md.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
og_hook="$repo/hooks/occurrence-gate.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

# assert <desc> <expected-substr-or-EMPTY> <actual>
assert() {
  local desc="$1" exp="$2" act="$3"
  if [[ "$exp" == "EMPTY" ]]; then
    [[ -z "$act" ]] && ok "$desc" || bad "$desc (expected empty, got: $act)"
  else
    [[ "$act" == *"$exp"* ]] && ok "$desc" || bad "$desc (expected '*$exp*', got: $act)"
  fi
}

# learn <content> -> Write payload to a canonical LEARNINGS.md path
learn() { printf '{"file_path":"/x/.session-continuity/LEARNINGS.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }

# Case 1: occurrence 2 + invariant -> silent (allow)
out="$(learn 'Occurrence count: 2 of 2\nInvariant: host-global port implies host-global secret.' | bash "$og_hook")"
assert "1 occ2 + invariant -> silent" EMPTY "$out"

# Case 2: occurrence 2, no invariant -> deny
out="$(learn 'Occurrence count: 2 of 2\nFix: reaped the stale port again.' | bash "$og_hook")"
assert "2 occ2, no invariant -> deny" 'deny' "$out"

# Case 3: occurrence 1, no invariant -> silent (nothing owed)
out="$(learn 'Occurrence count: 1 of 2\nFirst time we hit this.' | bash "$og_hook")"
assert "3 occ1 -> silent" EMPTY "$out"

# Case 4: no occurrence line -> silent (ordinary entry)
out="$(learn 'A normal learning with a Fix and a Symptom.' | bash "$og_hook")"
assert "4 no occurrence line -> silent" EMPTY "$out"

# Case 5: occurrence 3 of 5, no invariant -> deny (N>=2)
out="$(learn 'Occurrence count: 3 of 5\nYet another trigger patch.' | bash "$og_hook")"
assert "5 occ3, no invariant -> deny" 'deny' "$out"

# Case 6: escape hatch overrides -> silent
out="$(learn 'Occurrence count: 2 of 2\nOccurrence-gate: N/A — quoting #149 in a glossary.' | bash "$og_hook")"
assert "6 escape hatch -> silent" EMPTY "$out"

# Case 7: non-LEARNINGS path -> silent (out of scope)
out="$(printf '{"file_path":"/x/specs/s.md","tool_name":"Write","tool_input":{"content":"Occurrence count: 2 of 2\\nno invariant"}}' | bash "$og_hook")"
assert "7 non-LEARNINGS path -> silent" EMPTY "$out"

# Case 8: Edit new_string on a LEARNINGS path -> deny
out="$(printf '{"file_path":"/x/.session-continuity/LEARNINGS.md","tool_name":"Edit","tool_input":{"new_string":"Occurrence count: 2 of 2\\nFix only, no invariant"}}' | bash "$og_hook")"
assert "8 Edit new_string occ2, no invariant -> deny" 'deny' "$out"

# Case 9: deny payload is valid hook JSON (LEARNINGS #1 contract)
out="$(learn 'Occurrence count: 2 of 2\nno invariant here.' | bash "$og_hook")"
assert "9 deny carries hookSpecificOutput" 'hookSpecificOutput' "$out"
assert "9 deny names permissionDecision" 'permissionDecision' "$out"

# Case 10: Invariant label present but value EMPTY -> deny
out="$(learn 'Occurrence count: 2 of 2\nInvariant: \nFix: patched it.' | bash "$og_hook")"
assert "10 empty Invariant value -> deny" 'deny' "$out"

# Case 11: legacy docs/LEARNINGS.md path -> deny (dual-path scope)
out="$(printf '{"file_path":"/x/docs/LEARNINGS.md","tool_name":"Write","tool_input":{"content":"Occurrence count: 2 of 2\\nno invariant"}}' | bash "$og_hook")"
assert "11 legacy docs path occ2, no invariant -> deny" 'deny' "$out"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run the smoke to verify it fails**

Run: `zsh meta/superpowers/validation/2026-06-17-occurrence-gate-smoke.zsh`
Expected: FAIL — `hooks/occurrence-gate.sh` does not exist yet (`bash: …/occurrence-gate.sh: No such file or directory`), assertions for silent cases may spuriously "pass" on empty output but the deny cases (2,5,6,8,9,10,11) fail.

- [ ] **Step 3: Write `hooks/occurrence-gate.sh`**

Create `hooks/occurrence-gate.sh` (mirrors `proven-gate.sh` structure):

```bash
#!/usr/bin/env bash
#
# occurrence-gate.sh — PreToolUse hook (session-continuity plugin).
#
# Fires before Write / Edit. Self-scopes to a LEARNINGS.md under a
# .session-continuity/ or docs/ path. BLOCKS the write when the content records
# the 2nd-or-later occurrence of a mistake-class —
#
#   Occurrence count: N of M     (N >= 2)
#
# — but does NOT also carry a non-empty end-state invariant —
#
#   Invariant: <what must hold on EVERY path, enforced at the reconciler/gate>
#
# Rationale (CLAUDE.md rule 4 / change-the-odds #2): a class fixed across 2+
# attempts must name its end-state invariant, not ship another trigger-patch.
# Noticing the recurrence is the step that fails unaided — so a gate enforces it.
# See meta/superpowers/specs/2026-06-17-occurrence-counter-and-spike-check-design.md.
#
# Escape hatch (explicit skip-with-reason): a line matching
#   Occurrence-gate: N/A — <reason>   (em-dash or --, non-empty reason)
# passes the gate unconditionally (quoting another entry, glossary, a spec about
# the gate).
#
# Output contract (LEARNINGS #1): permissionDecision:"deny" blocks and shows the
# reason. Silent exit 0 allows. PreToolUse does NOT inject plain stdout.
#
# Self-reference (LEARNINGS #7): verify ONLY via the hermetic fixture runner,
# never by self-scanning a real LEARNINGS.md. The loose hatch is intentional.
#
# Security: $file_path / $content used only in path tests + grep; never eval'd.

set -euo pipefail

payload="$(cat || true)"
[ -z "${payload:-}" ] && exit 0

file_path="$(printf '%s' "$payload" \
  | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 \
  | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' \
  || true)"
[ -z "${file_path:-}" ] && exit 0

# Self-scope: basename LEARNINGS.md AND under a .session-continuity/ or docs/ dir.
base="${file_path##*/}"
[ "$base" = "LEARNINGS.md" ] || exit 0
case "$file_path" in
  */.session-continuity/*|*/docs/*) : ;;
  *) exit 0 ;;
esac

# Decode written content. Write -> content; Edit -> new_string. Same bounded
# best-effort decode as proven-gate.sh; the gate errs toward blocking and the
# escape hatch is the override, so an imperfect decode is safe.
raw="$(printf '%s' "$payload" \
  | sed -nE 's/.*"content"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
  | head -1)"
[ -z "$raw" ] && raw="$(printf '%s' "$payload" \
  | sed -nE 's/.*"new_string"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
  | head -1)"
[ -z "$raw" ] && exit 0

content="$(printf '%s' "$raw" \
  | sed -E 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g; s/\\\\/\\/g')"

# Escape hatch first.
if printf '%s' "$content" | grep -Eiq 'Occurrence-gate:[[:space:]]*N/A[[:space:]]*(—|--)[[:space:]]*[^[:space:]]'; then
  exit 0
fi

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Occurrence trigger: largest N in any "Occurrence count: N of M" line. No match
# or N < 2 -> silent allow.
max_n=0
while IFS= read -r n; do
  [ -z "$n" ] && continue
  if [ "$n" -gt "$max_n" ] 2>/dev/null; then max_n="$n"; fi
done <<EOF
$(printf '%s' "$content" \
  | grep -oiE 'Occurrence count:[[:space:]]*[0-9]+[[:space:]]+of[[:space:]]+[0-9]+' \
  | grep -oiE '[0-9]+[[:space:]]+of' \
  | grep -oE '^[0-9]+')
EOF

[ "$max_n" -ge 2 ] || exit 0

# Require a non-empty Invariant: line.
if printf '%s' "$content" | grep -Eiq 'Invariant:[[:space:]]*[^[:space:]]'; then
  exit 0
fi

deny "This LEARNINGS entry records occurrence #${max_n} of a mistake-class but does not name an end-state invariant. CLAUDE.md rule 4: a class fixed across 2+ attempts needs an 'Invariant: <what must hold on EVERY path, enforced at the reconciler/entry gate>' line — not another trigger-patch. Add it next to the 'Occurrence count:' line. Or add: Occurrence-gate: N/A — <reason> for a non-escalation use (quoting, glossary, a doc about the gate)."

exit 0
```

- [ ] **Step 4: `chmod +x` the hook**

Run: `chmod +x hooks/occurrence-gate.sh`

- [ ] **Step 5: Run the smoke to verify it passes**

Run: `zsh meta/superpowers/validation/2026-06-17-occurrence-gate-smoke.zsh`
Expected: `Result: 13 passed, 0 failed` (11 cases, case 9 has 2 asserts → 12 asserts; recount: cases 1-8,10,11 = 10 asserts + case 9 = 2 → 12). Accept whatever the runner prints as long as `0 failed`.

- [ ] **Step 6: shellcheck + zsh -n clean**

Run: `shellcheck hooks/occurrence-gate.sh && zsh -n meta/superpowers/validation/2026-06-17-occurrence-gate-smoke.zsh && echo CLEAN`
Expected: `CLEAN` (no shellcheck warnings, no zsh parse errors).

- [ ] **Step 7: Wire into hooks.json**

Modify `hooks/hooks.json` — in the `PreToolUse` array's `"matcher": "Write|Edit"` block, append a 4th entry after the `proven-gate.sh` entry:

```json
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/proven-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/occurrence-gate.sh"
          }
```

- [ ] **Step 8: Validate hooks.json parses**

Run: `bash -c 'command -v jq >/dev/null && jq . hooks/hooks.json >/dev/null && echo VALID || python3 -c "import json,sys; json.load(open(\"hooks/hooks.json\")); print(\"VALID\")"'`
Expected: `VALID`

- [ ] **Step 9: Commit**

```bash
git add hooks/occurrence-gate.sh hooks/hooks.json meta/superpowers/validation/2026-06-17-occurrence-gate-smoke.zsh
git commit -m "feat(occurrence-gate): block 2nd-occurrence LEARNINGS entries lacking an invariant (change-the-odds #2)"
```

---

### Task 2: extend `/learning` with occurrence-count + invariant fields

**Files:**
- Modify: `commands/learning.md` (Step 2 gather, Step 5 compose)

**Interfaces:**
- Consumes: nothing from Task 1 at runtime (the command authors text; the gate validates it independently).
- Produces: LEARNINGS entries that, when occurrence N≥2, carry both `Occurrence count:` and `Invariant:` lines — i.e. compliant-by-construction so the gate fires only on raw hand-edits.

- [ ] **Step 1: Add the two fields to Step 2 (Gather the recipe)**

In `commands/learning.md`, the Step 2 numbered list currently ends at item 6 (`Trigger`). Append items 7 and 8:

```markdown
7. **Occurrence count** (optional — recurrence tracking): Is this the Nth time this *class* of bug has bitten? Enter `N of M` (e.g. `2 of 2`). Skip for a first-occurrence entry. If the user enters N ≥ 2, item 8 below becomes REQUIRED.
8. **Invariant** (REQUIRED when occurrence N ≥ 2; otherwise skip): the END-STATE that, enforced at the reconciler/entry gate, makes the whole class impossible on EVERY path — not another trigger-patch. CLAUDE.md rule 4. E.g. "a host-global port implies a host-global secret." The `occurrence-gate` hook will block a 2nd-occurrence entry that lacks this line.
```

- [ ] **Step 2: Add the lines to Step 5 (compose the entry)**

In `commands/learning.md` Step 5, the entry template currently places `Trigger:` directly under the `### N. Title`. Add the two new lines after `Trigger:` and before the blank line preceding `**The trap.**`:

```markdown
### <N>. <Title>
Trigger: <tool> /<regex>/      ← include ONLY if the user supplied a trigger; omit the whole line otherwise
Occurrence count: <N of M>     ← include ONLY if supplied; omit otherwise
Invariant: <end-state>          ← include ONLY when occurrence N >= 2; omit otherwise
```

Then add a sentence after the existing "The `Trigger:` line, when present, must sit on the line directly below the `### N.` heading…" paragraph:

```markdown
When present, `Occurrence count:` and `Invariant:` sit on their own lines in the metadata block directly under the heading (after `Trigger:` if it exists), each before the blank line that precedes `**The trap.**`. Omit any of the three metadata lines that has no value — never write an empty label.
```

- [ ] **Step 3: Verify no legacy path references introduced (LEARNINGS #6)**

Run: `git grep -n 'docs/SESSION_PRIMER\|docs/LEARNINGS' commands/ | grep -v 'primer.md'`
Expected: no output (empty) — the only legacy-path mentions allowed are in `commands/primer.md`'s Migrate mode.

- [ ] **Step 4: Commit**

```bash
git add commands/learning.md
git commit -m "feat(learning): offer occurrence-count + invariant fields so /learning authors gate-compliant entries"
```

---

### Task 3: `/spike-check` command

**Files:**
- Create: `commands/spike-check.md`

**Interfaces:**
- Consumes: optional `$ARGUMENTS` (a one-line spike description to prefill framing).
- Produces: the five-question stand-in checklist presented to the user/agent at spike start. Answers 2 + 5 map to proven-gate's `Real path:` + `Stubbed:` fields at claim-time.

- [ ] **Step 1: Create `commands/spike-check.md`**

```markdown
---
description: Emit the stand-in spike checklist BEFORE a spike, so it's designed to hit the real binary + auth/lifecycle/fixed-port path (change-the-odds #3c).
---

# /session-continuity:spike-check $ARGUMENTS

You are responding to the `/session-continuity:spike-check` slash command.

**Your job: before any spike code is written, force the spike to be designed against the real load-bearing path** — not a stand-in that passes cleanly and proves nothing. This is the proactive complement to the `proven-gate` hook, which catches a stand-in only later, at claim-time.

If `$ARGUMENTS` is non-empty, treat it as the one-line description of the spike being planned and frame each question against it.

Present the following checklist and require an explicit answer to each item **before** the spike is built. Do not let the spike proceed on a hand-wave.

## The stand-in spike checklist

1. **What is the load-bearing behavior?** Name the one thing that, if it breaks in the real smoke later, means this spike's conclusion was wrong. (Example: for an egress proxy, that is `Proxy-Authorization` + the helper start/stop/reap lifecycle — NOT "bytes flow through a proxy".)

2. **Real binary?** Does the spike run the actual production binary / code path, or a hand-rolled stand-in? If it uses a stand-in, does that stand-in replace the load-bearing behavior from question 1? If yes, the spike **cannot** prove the claim — redesign it to exercise the real path.

3. **Real auth / lifecycle / fixed-port path?** Does the spike exercise the real authentication, the real start/stop/reap lifecycle, and the real fixed-port contention — or does it shortcut them (no-auth, always-fresh, free-port)? Each dimension you skip is a hole the real smoke will find. List which of the three are exercised for real and which are shortcut.

4. **Hermetic vs real-egress trade-off named?** If the spike needs the network, DNS, or a corp-locked box, state that dependency and confirm it matches the target environment. A "fast-fail" stand-in that actually hangs on the real path is the LEARNINGS #152 class — name the failure mode you are assuming away.

5. **What will the real smoke still have to prove that this spike does NOT?** Name it explicitly. This list is the spike's honest residual risk.

## Closing

Remind the user/agent:

> If any answer reveals the spike stands in for the load-bearing behavior, the spike is **not conclusive** no matter how cleanly it runs — redesign before claiming. When you later write up the result in a spec or plan, the `proven-gate` hook will require `Real path:` and `Stubbed:` fields — your answers to questions 2 and 5 here ARE those fields. Write them down now while the design is fresh.
```

- [ ] **Step 2: Verify the command is well-formed**

Run: `head -4 commands/spike-check.md && echo "---" && git grep -n 'docs/SESSION_PRIMER\|docs/LEARNINGS' commands/spike-check.md; echo "rc=$?"`
Expected: front-matter with `description:` shows; the grep returns no matches (`rc=1` = no legacy paths).

- [ ] **Step 3: Commit**

```bash
git add commands/spike-check.md
git commit -m "feat(spike-check): add /spike-check stand-in checklist command (change-the-odds #3c)"
```

---

### Task 4: version bump, README, CHANGELOG, final smoke

**Files:**
- Modify: `.claude-plugin/plugin.json` (version)
- Modify: `README.md` (command table + hook coverage)
- Modify: `CHANGELOG.md` (new 0.10.0 heading)

**Interfaces:**
- Consumes: the three shipped artifacts from Tasks 1-3.
- Produces: a release-ready branch.

- [ ] **Step 1: Bump plugin.json version**

In `.claude-plugin/plugin.json`, change `"version": "0.9.0"` → `"version": "0.10.0"`.

- [ ] **Step 2: Add a CHANGELOG 0.10.0 entry**

Prepend under the top of `CHANGELOG.md` (follow the existing heading format — check the 0.9.0 entry for the exact style):

```markdown
## [0.10.0] - 2026-06-17

### Added
- **`occurrence-gate` PreToolUse hook (change-the-odds #2).** Blocks a `Write`/`Edit` to a `LEARNINGS.md` that records the 2nd-or-later occurrence of a mistake-class (`Occurrence count: N of M`, N ≥ 2) without also naming an end-state `Invariant:` line. Enforces CLAUDE.md rule 4 — a class fixed across 2+ attempts must name its invariant, not ship another trigger-patch. Escape hatch: `Occurrence-gate: N/A — <reason>`.
- **`/session-continuity:spike-check` command (change-the-odds #3c).** Emits a five-question stand-in checklist at spike start so a spike is designed to exercise the real binary + auth/lifecycle/fixed-port path. Proactive complement to the `proven-gate` hook.
- **`/learning` occurrence-count + invariant fields.** The command now offers an `Occurrence count:` field and, when N ≥ 2, requires an `Invariant:` line — so entries are authored gate-compliant by construction.
```

- [ ] **Step 3: Update README**

In `README.md`: (a) add `spike-check` to the slash-command table/list alongside `learning`, `primer`, `end-session`; (b) add `occurrence-gate.sh` to the hooks coverage section alongside `proven-gate.sh` / `smoke-gate.sh` / `learnings-surface.sh`. Match the existing row/bullet format exactly. Locate the spots:

Run: `grep -n 'proven-gate\|end-session\|smoke-gate' README.md | head`
Then edit the matching table rows / bullet lists to include the two new artifacts.

- [ ] **Step 4: Re-run the occurrence-gate smoke (regression)**

Run: `zsh meta/superpowers/validation/2026-06-17-occurrence-gate-smoke.zsh`
Expected: `0 failed`.

- [ ] **Step 5: Re-run the proven-gate smoke (no-regression on the sibling gate)**

Run: `zsh meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh`
Expected: `0 failed` (untouched, but confirm the hooks.json edit didn't break anything adjacent).

- [ ] **Step 6: Final shellcheck sweep**

Run: `shellcheck hooks/occurrence-gate.sh && echo CLEAN`
Expected: `CLEAN`.

- [ ] **Step 7: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md README.md
git commit -m "chore(release): v0.10.0 — occurrence-gate + spike-check + learning fields"
```

- [ ] **Step 8: Open the PR**

```bash
git push -u origin feat/change-the-odds-2-3c
gh pr create --title "feat: occurrence-gate + spike-check (change-the-odds #2 + #3c)" --body "$(cat <<'EOF'
## Summary
Ships change-the-odds deliverables #2 and #3c (one PR, per the workstream sequencing now that both are small):

- **#2 occurrence-gate hook** — PreToolUse gate blocking a 2nd-occurrence LEARNINGS entry that lacks an end-state `Invariant:` line (CLAUDE.md rule 4 → executable gate). Escape hatch `Occurrence-gate: N/A — <reason>`.
- **#3c `/spike-check` command** — five-question stand-in checklist at spike start; proactive complement to the `proven-gate` hook.
- **`/learning` extension** — offers `Occurrence count:` + (when N≥2) requires `Invariant:`, so entries are gate-compliant by construction.

## Testing
- Hermetic fixture runner `meta/superpowers/validation/2026-06-17-occurrence-gate-smoke.zsh` — 11 cases, 0 failed.
- proven-gate smoke re-run green (no sibling regression).
- shellcheck + `zsh -n` clean.

## Notes
- Spec: `meta/superpowers/specs/2026-06-17-occurrence-counter-and-spike-check-design.md`.
- Plan: `meta/superpowers/plans/2026-06-17-occurrence-counter-and-spike-check.md`.
- Reuses the `proven-gate.sh` skeleton (#1) verbatim. Hooks register at SessionStart → live next session after marketplace update + reinstall.
EOF
)"
```

---

## Self-Review

**Spec coverage:**
- #2 hook (scope, detection N≥2, invariant-required, escape hatch, output contract, security) → Task 1. ✓
- #2 `/learning` extension → Task 2. ✓
- #2 smoke table (11 cases) → Task 1 Step 1. ✓
- #3c `/spike-check` command (5 questions, front-matter, closing) → Task 3. ✓
- Version 0.9.0→0.10.0, CHANGELOG, README → Task 4. ✓
- Self-reference trap / LEARNINGS #1+#7 → Global Constraints + hook header comment. ✓

**Placeholder scan:** none — all hook code, smoke code, command body, CHANGELOG copy are literal.

**Type/name consistency:** hook filename `occurrence-gate.sh`, smoke `2026-06-17-occurrence-gate-smoke.zsh`, escape hatch `Occurrence-gate: N/A`, field labels `Occurrence count:` / `Invariant:` — used identically across spec, hook, smoke, `/learning`, CHANGELOG. ✓

**Note on Task 1 Step 5 count:** the smoke has 11 cases; case 9 carries 2 asserts → 12 assert lines total. The gate is `0 failed`, not a fixed pass count — don't hardcode.
