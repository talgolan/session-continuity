# Proven-gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a PreToolUse hook that blocks writing a "proven"-class claim into a spec or plan file unless the same content names the real path exercised and what was stubbed.

**Architecture:** A single new bash hook (`hooks/proven-gate.sh`) reusing the existing `hooks/smoke-gate.sh` skeleton (same stdin-payload decode, same `deny`/silent-allow JSON contract), wired as a third entry in the `hooks.json` PreToolUse `Write|Edit` block. NOTE its self-scope arm DIFFERS from smoke-gate: proven-gate fires on `*/specs/*` OR `*/plans/*` `.md` only, with NO `*plan*.md` basename fallback (smoke-gate has one). Do not copy smoke-gate's basename fallback. Verified by a hermetic zsh fixture runner that pipes synthetic payloads to the hook and asserts stdout — no live session, no containers. Spec: `meta/superpowers/specs/2026-06-17-proven-gate-design.md`.

**Tech Stack:** Bash (hook), zsh (test runner), JSON hook contract. No new dependencies.

## Global Constraints

- **Repo artifact paths:** specs → `meta/superpowers/specs/`, plans → `meta/superpowers/plans/`, validation → `meta/superpowers/validation/`. NOT `docs/` (CLAUDE.md).
- **Hook output contract (LEARNINGS #1):** `PreToolUse` does NOT inject plain stdout. `deny` MUST emit `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"…"}}` and `exit 0`. Silent-allow is bare `exit 0`, no stdout.
- **Security:** `$file_path` / `$content` used only in path tests + greps, never `eval`'d. No network, no writes, no subprocesses beyond `grep`/`sed`.
- **Self-reference trap (LEARNINGS #7):** verify ONLY with the hermetic fixture runner. NEVER self-scan this plan or the spec to "check" the gate — a self-referential pass fires via the incidental escape-hatch match, not the logic under test. Do NOT anchor the hatch to line-start to fix a self-match.
- **Claim-words:** `proven`, `verified`, `spike conclusive` — matched on WORD BOUNDARIES (the one deliberate deviation from smoke-gate's substring match). `confirmed` is excluded.
- **Version source:** `.claude-plugin/plugin.json` is the single version source (marketplace.json removed at `12a463d`; the version-sync pre-commit guard is now a no-op).
- **Branch:** `feat/proven-gate` (already created, spec already committed as `449b832`).

---

### Task 1: The proven-gate hook + hermetic smoke

**Files:**
- Create: `hooks/proven-gate.sh`
- Create: `meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh`
- Reference (do not modify): `hooks/smoke-gate.sh` (skeleton to copy), `meta/superpowers/validation/2026-06-15-fire-before-action-smoke.zsh` (runner shape)

**Interfaces:**
- Consumes: a PreToolUse JSON payload on stdin with `file_path` and either `tool_input.content` (Write) or `tool_input.new_string` (Edit). (Note: smoke-gate reads top-level `"content"`/`"new_string"` via a greedy `sed` that tolerates either nesting — copy that decode verbatim.)
- Produces: on stdout, either nothing (`exit 0`, allow) or one `hookSpecificOutput` JSON object with `permissionDecision:"deny"`.

- [ ] **Step 1: Write the failing smoke runner**

Create `meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# Smoke runner for the proven-gate hook. Hermetic: pipes synthetic PreToolUse
# payloads into hooks/proven-gate.sh, asserts the JSON (or silence) on stdout.
# No containers, no live session. See LEARNINGS #7 — this is the ONLY correct
# way to verify the gate; never self-scan a real spec/plan.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
pg_hook="$repo/hooks/proven-gate.sh"

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

# spec <content> -> a Write payload to a */specs/*.md path
spec() { printf '{"file_path":"/x/specs/s.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }

# Case 1: claim-word + both fields filled -> silent (allow)
out="$(spec 'Approach is proven. Real path: ran src/egressProxy.ts CONNECT auth. Stubbed: nothing.' | bash "$pg_hook")"
assert "1 proven + both fields -> silent" EMPTY "$out"

# Case 2: claim-word, no fields -> deny
out="$(spec 'Approach is proven, option A.' | bash "$pg_hook")"
assert "2 proven, no fields -> deny" 'deny' "$out"

# Case 3: verified + Real path only (no Stubbed) -> deny
out="$(spec 'Verified end to end. Real path: ran the real binary.' | bash "$pg_hook")"
assert "3 verified, Real path only -> deny" 'deny' "$out"

# Case 4: spike conclusive + Stubbed only (no Real path) -> deny
out="$(spec 'Spike conclusive. Stubbed: a no-auth /tmp proxy.' | bash "$pg_hook")"
assert "4 spike conclusive, Stubbed only -> deny" 'deny' "$out"

# Case 5: claim-word + escape hatch -> silent
out="$(spec 'This is proven upstream. Proven-gate: N/A — quoting the vendor doc.' | bash "$pg_hook")"
assert "5 escape hatch overrides -> silent" EMPTY "$out"

# Case 6: non-spec path with claim-word, no fields -> silent (out of scope)
out="$(printf '{"file_path":"/x/src/foo.ts","tool_name":"Write","tool_input":{"content":"this is proven, no fields"}}' | bash "$pg_hook")"
assert "6 non-spec path -> silent" EMPTY "$out"

# Case 7: spec file, no claim-word -> silent
out="$(spec 'Renamed a variable in the parser.' | bash "$pg_hook")"
assert "7 no claim-word -> silent" EMPTY "$out"

# Case 8: word-boundary guard — improven / unproven must NOT trigger
out="$(spec 'The approach is unproven and improven, needs work.' | bash "$pg_hook")"
assert "8 substring improven/unproven -> silent" EMPTY "$out"

# Case 9: dropped word — confirmed must NOT trigger
out="$(spec 'Confirmed the user choice in the meeting.' | bash "$pg_hook")"
assert "9 confirmed -> silent" EMPTY "$out"

# Case 10: deny payload is valid hook JSON (LEARNINGS #1 contract)
out="$(spec 'Approach is proven.' | bash "$pg_hook")"
assert "10 deny carries hookSpecificOutput" 'hookSpecificOutput' "$out"
assert "10 deny names permissionDecision" 'permissionDecision' "$out"

# Case 11: Edit tool (new_string) path also gated
out="$(printf '{"file_path":"/x/plans/p.md","tool_name":"Edit","tool_input":{"new_string":"now proven, option A"}}' | bash "$pg_hook")"
assert "11 Edit new_string on plan path -> deny" 'deny' "$out"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run the runner to verify it fails (hook absent)**

Run: `zsh meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh`
Expected: FAIL — `hooks/proven-gate.sh` does not exist yet, so `bash "$pg_hook"` errors; assertions report failures, final line non-zero exit.

- [ ] **Step 3: Write the hook**

Create `hooks/proven-gate.sh` (mirrors `smoke-gate.sh`; the ONE deviation is the word-boundary claim match in the detection step):

```bash
#!/usr/bin/env bash
#
# proven-gate.sh — PreToolUse hook (session-continuity plugin).
#
# Fires before Write / Edit. Self-scopes to spec/plan files (path under a
# */specs/ or */plans/ dir, *.md). BLOCKS the write when the content makes a
# "proven"-class claim (proven | verified | spike conclusive, matched on word
# boundaries) but does NOT also carry both fields:
#
#   Real path: <which production code path actually ran>
#   Stubbed:   <what stood in — or "nothing">
#
# Rationale: a forward "proven" claim is only meaningful if it names the real
# path exercised and what was stubbed. The Stubbed: field forces a stand-in
# into the open. See meta/superpowers/specs/2026-06-17-proven-gate-design.md
# and the project-change-the-odds workstream.
#
# Escape hatch (explicit skip-with-reason): a line matching
#   Proven-gate: N/A — <reason>   (em-dash or --, non-empty reason)
# passes the gate unconditionally (quoting, glossary, a spec about the gate).
#
# Output contract (LEARNINGS #1): permissionDecision:"deny" blocks and shows
# the reason. Silent exit 0 allows. PreToolUse does NOT inject plain stdout.
#
# Self-reference (LEARNINGS #7): verify ONLY via the hermetic fixture runner,
# never by self-scanning a real spec/plan. The loose hatch is intentional.
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

# Self-scope: only spec/plan markdown. */specs/*.md OR */plans/*.md
base="${file_path##*/}"
case "$file_path" in
  */specs/*|*/plans/*) : ;;
  *) exit 0 ;;
esac
case "$base" in *.md) : ;; *) exit 0 ;; esac

# Pull the written content. Write -> content; Edit -> new_string. Extract
# everything after the key's opening quote to end of payload, then un-escape
# \n \t \" \\ so line-oriented greps work. Bounded best-effort decode; the
# gate errs toward blocking and the escape hatch is the override, so an
# imperfect decode is safe.
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
if printf '%s' "$content" | grep -Eiq 'Proven-gate:[[:space:]]*N/A[[:space:]]*(—|--)[[:space:]]*[^[:space:]]'; then
  exit 0
fi

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Claim-word detection — WORD BOUNDARIES (deviation from smoke-gate substring).
# "proven"/"verified" as whole words; "spike conclusive" as a phrase.
has_claim=0
if printf '%s' "$content" | grep -Eiqw 'proven|verified'; then has_claim=1; fi
if printf '%s' "$content" | grep -Eiq 'spike[[:space:]]+conclusive'; then has_claim=1; fi
[ "$has_claim" -eq 0 ] && exit 0

# Require BOTH fields (label case-insensitive, non-empty value after colon).
has_real=0; has_stub=0
if printf '%s' "$content" | grep -Eiq 'Real path:[[:space:]]*[^[:space:]]'; then has_real=1; fi
if printf '%s' "$content" | grep -Eiq 'Stubbed:[[:space:]]*[^[:space:]]'; then has_stub=1; fi

if [ "$has_real" -eq 0 ] || [ "$has_stub" -eq 0 ]; then
  deny "This spec/plan makes a 'proven/verified/spike conclusive' claim but does not name what was actually tested. Add both fields next to the claim — 'Real path: <which production code path ran>' and 'Stubbed: <what stood in, or \"nothing\">'. If the stubbed thing is the feature under test, the claim is not proven. Or add a line: Proven-gate: N/A — <reason> for a non-claim use (quoting, glossary, a doc about the gate)."
fi

exit 0
```

- [ ] **Step 4: Make both scripts executable**

Run: `chmod +x hooks/proven-gate.sh meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh`
Expected: no output, exit 0. (smoke-gate.sh and the existing runner are both executable — match the repo.)

- [ ] **Step 5: Run the runner to verify all cases pass**

Run: `zsh meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh`
Expected: `Result: 12 passed, 0 failed` (11 cases; case 10 has 2 asserts → 12 asserts total), exit 0.

- [ ] **Step 6: shellcheck the hook**

Run: `shellcheck hooks/proven-gate.sh`
Expected: no output, exit 0. (Matches the clean-shellcheck bar the other hooks meet.)

- [ ] **Step 7: Commit**

```bash
git add hooks/proven-gate.sh meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh
git commit -m "feat(proven-gate): hook + hermetic smoke (change-the-odds #1)

PreToolUse Write|Edit gate on */specs/ + */plans/ *.md: a
proven/verified/spike-conclusive claim must carry adjacent
'Real path:' + 'Stubbed:' fields, else deny. Mirrors smoke-gate.sh;
sole deviation = whole-word claim match (improven/unproven/confirmed
do not trigger). Escape hatch: 'Proven-gate: N/A — <reason>'.
Hermetic fixture runner 12/12; shellcheck clean.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Wire the hook into hooks.json

**Files:**
- Modify: `hooks/hooks.json` (the PreToolUse `Write|Edit` matcher block)

**Interfaces:**
- Consumes: nothing new.
- Produces: the gate runs live on every Write|Edit once the plugin is reinstalled.

- [ ] **Step 1: Add the proven-gate entry**

In `hooks/hooks.json`, the `PreToolUse` array's second element has `"matcher": "Write|Edit"` with a `hooks` array currently holding `learnings-surface.sh` then `smoke-gate.sh`. Append a third entry after `smoke-gate.sh`:

```json
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/smoke-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/proven-gate.sh"
          }
```

(Show the smoke-gate entry above it only to anchor the edit; add the proven-gate object, keeping valid JSON — comma after the smoke-gate object, none after the new last object.)

- [ ] **Step 2: Validate the JSON**

Run: `bash -c 'python3 -m json.tool hooks/hooks.json >/dev/null && echo OK'`
Expected: `OK` (exit 0). Malformed JSON would print a parse error.

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat(proven-gate): wire hook into PreToolUse Write|Edit

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Version bump + CHANGELOG + README

**Files:**
- Modify: `.claude-plugin/plugin.json` (version `0.8.0` → `0.9.0`)
- Modify: `CHANGELOG.md` (new `[0.9.0]` section at top)
- Modify: `README.md` (mention the new gate alongside the two existing fire-before-action hooks)

**Interfaces:**
- Consumes: nothing.
- Produces: a shippable version with release notes.

- [ ] **Step 1: Bump plugin.json version**

In `.claude-plugin/plugin.json` change `"version": "0.8.0"` to `"version": "0.9.0"`.

- [ ] **Step 2: Add CHANGELOG section**

Insert directly under the `## [0.8.0] — 2026-06-15` line's section (i.e. as the new top entry, above 0.8.0):

```markdown
## [0.9.0] — 2026-06-17

### Added
- **`proven-gate.sh` (Write|Edit, spec/plan files only).** Blocks writing a spec or plan that makes a "proven / verified / spike conclusive" claim unless the same content names, in two fields, what was actually tested: `Real path: <production code path that ran>` and `Stubbed: <what stood in — or "nothing">`. The `Stubbed:` field forces a stand-in into the open, where a no-auth stub standing in for the feature under test becomes visible to author and reviewer. Claim-words match on word boundaries (`unproven`/`improven`/`confirmed` do not trigger). Override with `Proven-gate: N/A — <reason>` for quoting, a glossary, or a doc about the gate. Turns the passive "prove the mechanism first" lesson into a mechanical gate.

### Compatibility
- Additive. Only acts on `*/specs/*.md` and `*/plans/*.md` writes; all other files unaffected. No migration. Upgrading installs gain the gate on next session.
```

- [ ] **Step 3: Update README**

Find the README section describing the fire-before-action / PreToolUse hooks (search for `smoke-gate`). Add a parallel bullet for the proven-gate, matching the surrounding style. Example bullet to adapt to the local phrasing:

```markdown
- **`proven-gate`** — before writing a spec or plan, a "proven / verified / spike conclusive" claim must carry `Real path:` + `Stubbed:` fields naming what actually ran vs what was a stand-in, else the write is blocked. Override with `Proven-gate: N/A — <reason>`.
```

Run first to locate the exact spot: `grep -n 'smoke-gate\|fire-before-action\|PreToolUse' README.md`

- [ ] **Step 4: Verify version-sync guard passes**

Run: `bash .githooks/pre-commit; echo "rc=$?"`
Expected: `rc=0`. (marketplace.json was removed at `12a463d`, so the guard short-circuits to exit 0; this just confirms no regression.)

- [ ] **Step 5: Re-run the smoke runner (nothing regressed)**

Run: `zsh meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh`
Expected: `Result: 12 passed, 0 failed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md README.md
git commit -m "chore(release): proven-gate v0.9.0 — changelog + readme

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:**
- Scope (specs/plans only, *.md) → Task 1 hook self-scope step + Task 1 cases 6/7. ✓
- Claim-words proven/verified/spike-conclusive, whole-word, confirmed dropped → Task 1 detection step + cases 8/9. ✓
- Real path + Stubbed both required, deny on missing either → Task 1 cases 2/3/4. ✓
- Escape hatch → Task 1 case 5. ✓
- Reuse smoke-gate skeleton + JSON contract → Task 1 hook body + case 10. ✓
- Wiring → Task 2. ✓
- Self-reference trap handled (verify via fixtures only) → Global Constraints + Task 1 runner header. ✓
- Versioning/ship (0.9.0, CHANGELOG, branch, PR) → Task 3 + Execution Handoff. ✓
- Edit-path (new_string) coverage → Task 1 case 11. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases". README step says "adapt to local phrasing" but gives the exact bullet + a grep to locate the spot — acceptable (existing README wording is the only unknown, resolved at execution by the grep). ✓

**3. Type consistency:** Hook file name `hooks/proven-gate.sh`, runner `2026-06-17-proven-gate-smoke.zsh`, escape-hatch token `Proven-gate: N/A —`, field labels `Real path:` / `Stubbed:`, version `0.9.0` — all consistent across tasks. Pass count 12 (11 cases: cases 1–9 + 11 = 10 single asserts, case 10 = 2 asserts → 12 total) consistent between Task 1 Step 5 and Task 3 Step 5. ✓

## Execution Handoff

Plan complete. Two execution options — subagent-driven (fresh subagent per task, two-stage review) or inline (executing-plans, batch with checkpoints).
