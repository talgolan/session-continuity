# Gate delta-trigger reconciler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all seven commit-time content gates fire on the commit's staged
delta and satisfy against the whole document, with escape short-circuit and
masking owned by the shared driver.

**Architecture:** Extend `hooks/lib/gate-common.sh` with pinned content
`gate_staged_delta`, rename-aware `gate_staged_status`, `gate_hatch_class`,
`gate_triggered [-w] TRIGGER [SAT…]`, driver short-circuit on accepted hatch
and on `R*` renames, central mask, and best-effort `deny` diagnostics. Each
gate sets `GATE_LABEL`, deletes local escape/mask in Task 2, and migrates
triggers per
[`meta/superpowers/specs/2026-09-10-gate-delta-trigger-reconciler-design.md`](../specs/2026-09-10-gate-delta-trigger-reconciler-design.md).

**Tech Stack:** bash (`set -euo pipefail`), git, zsh hermetic smokes under
`meta/superpowers/validation/`, existing `gate-test-common.zsh`.

**Spec:** `meta/superpowers/specs/2026-09-10-gate-delta-trigger-reconciler-design.md`

Proven-gate: N/A — this plan describes work to do; it is not a live-path claim.
Evidence-gate: N/A — "smoke"/"poll"/"teardown" below are quoted gate patterns
and fixture text, not a smoke design for this document.
Smoke: N/A — this plan changes shell gate drivers only; no binary/engine/SUT.

## Global Constraints

- Spec decisions locked: trigger-on-delta / satisfy-on-document; hatch grammar
  unchanged; no `gate_window_around`; no widening separators; pattern *strings*
  unchanged (scope only).
- Content diff pins (verbatim):
  `git -c diff.algorithm=myers diff --cached --no-color --no-ext-diff --no-textconv --no-renames -U0 -- <path>`
- Status probe (rename-aware, **no** `--no-renames`):
  `git diff --cached --name-status -M --no-color -- <path>`
- On status matching `R*`: skip `check_fn` (pure rename → allow).
- Greps/masker: `LC_ALL=C`.
- Escape order: classify unmasked blob → accepted skips `check_fn` → mask →
  `check_fn`. Delete local `gate_has_escape` / `gate_mask_escape` from all
  seven gates in **Task 2** (same change as short-circuit).
- `gate_triggered [-w] TRIGGER [SAT…]` — `-w` uses `grep -Eiqw` (proven).
- `GATE_LABEL` set before `gate_scan_staged` (and before flaky message path).
- Diagnostics best-effort on `deny` only — never flip allow/deny.
- Under `set -e`: use `if …; then continue; fi`, never `cmd && continue`.
- Release: **0.37.0**.
- Spec/plan under `meta/superpowers/`, not `docs/`.
- Do not commit unless the user asked; Commit steps are optional gates.
- Smokes need unsandboxed `git init`.
- Never chain `git add` && `git commit` in one Bash tool call when gates can
  deny.

## File map

| File | Role |
|---|---|
| `hooks/lib/gate-common.sh` | Delta, status, hatch class, `gate_triggered`, driver, `deny` |
| `hooks/*-gate.sh` (seven) | `GATE_LABEL`; delete local escape Task 2; delta triggers later |
| `meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh` | Driver/API cases |
| `meta/superpowers/validation/2026-*-*gate*smoke.zsh` | Per-gate delta cases |
| `README.md` / `REFERENCE.md` / `CHANGELOG.md` / `plugin.json` | Docs + 0.37.0 |

---

### Task 1: `gate_staged_delta` + rename-aware status (TDD)

**Files:**
- Modify: `hooks/lib/gate-common.sh`
- Modify: `meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh`

**Interfaces:**
- Produces: `gate_staged_delta <relpath>` → globals `GATE_DELTA_ADDED` /
  `GATE_DELTA_REMOVED`; `gate_staged_status <relpath>` → status token (`A`,
  `M`, `D`, `R100`, …) from rename-aware `name-status -M`.

- [ ] **Step 1: Append failing smoke cases** (before final `---` in
  `2026-08-27-gate-common-smoke.zsh`):

```zsh
delta_added() {
  local repo="$1" path="$2"
  bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_CWD="'"$repo"'"; gate_staged_delta "'"$path"'"; printf "%s" "$GATE_DELTA_ADDED"'
}
delta_status() {
  local repo="$1" path="$2"
  bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_CWD="'"$repo"'"; gate_staged_status "'"$path'"'
}

repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/d.md" $'keep\nsmoke here\n'
git -C "$repo" commit -qm base
print -rn -- $'keep\nsmoke here\nnew line\n' > "$repo/meta/plans/d.md"
git -C "$repo" add "meta/plans/d.md"
out="$(delta_added "$repo" "meta/plans/d.md")"
check "edit delta is added lines only" "new line" "$out"
gt_cleanup "$repo"

repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/n.md" $'a\nb\n'
out="$(delta_added "$repo" "meta/plans/n.md" | tr '\n' '|')"
check "new file delta is all lines" "a|b|" "$out"
gt_cleanup "$repo"

repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/r.md" $'body\n'
git -C "$repo" commit -qm base
git -C "$repo" mv meta/plans/r.md meta/plans/s.md
st="$(delta_status "$repo" "meta/plans/s.md")"
case "$st" in R*) st_ok=yes ;; *) st_ok="no:$st" ;; esac
check "pure rename status is R*" "yes" "$st_ok"
gt_cleanup "$repo"

repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/c.md" $'a\n'
git -C "$repo" commit -qm base
print -rn -- $'a\ncolor line\n' > "$repo/meta/plans/c.md"
git -C "$repo" add "meta/plans/c.md"
git -C "$repo" config color.diff always
out="$(delta_added "$repo" "meta/plans/c.md")"
check "color.diff=always still yields plain added line" "color line" "$out"
gt_cleanup "$repo"
```

- [ ] **Step 2: Run — expect FAIL** (`gate_staged_delta` missing).

```bash
zsh meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh
```

- [ ] **Step 3: Implement**

```bash
gate_staged_status() {  # <relpath> -> A|M|D|R100|... or empty
  local path="$1" line
  [ -n "${GATE_CWD:-}" ] || { printf ''; return 0; }
  # Rename-aware on purpose — do NOT pass --no-renames here.
  line="$(git -C "$GATE_CWD" diff --cached --name-status -M --no-color -- "$path" 2>/dev/null | head -1 || true)"
  # R100\told\tnew  or  A\tpath  or  M\tpath
  printf '%s' "${line%%$'\t'*}"
}

gate_staged_delta() {  # <relpath> -> sets GATE_DELTA_ADDED, GATE_DELTA_REMOVED
  local path="$1" raw
  GATE_DELTA_ADDED=""
  GATE_DELTA_REMOVED=""
  [ -n "${GATE_CWD:-}" ] || return 0
  [ -d "$GATE_CWD" ] || return 0
  raw="$(git -C "$GATE_CWD" -c diff.algorithm=myers diff --cached --no-color \
    --no-ext-diff --no-textconv --no-renames -U0 -- "$path" 2>/dev/null || true)"
  GATE_DELTA_ADDED="$(printf '%s\n' "$raw" | grep -E '^\+' | grep -Ev '^\+\+\+' | sed 's/^+//' || true)"
  GATE_DELTA_REMOVED="$(printf '%s\n' "$raw" | grep -E '^-' | grep -Ev '^---' | sed 's/^-//' || true)"
}
```

- [ ] **Step 4: Re-run — PASS.**

- [ ] **Step 5: Optional commit.**

---

### Task 2: Hatch class + short-circuit + delete local escape (TDD)

**Files:**
- Modify: `hooks/lib/gate-common.sh`
- Modify: all seven `hooks/*-gate.sh` — set `GATE_LABEL`; **delete** every
  `gate_has_escape` / `gate_mask_escape` call (driver owns both)
- Modify: `2026-08-27-gate-common-smoke.zsh`
- Modify: `2026-06-17-proven-gate-smoke.zsh` — one case: accepted hatch still
  exempts via real `proven-gate.sh` after driver short-circuit

**Interfaces:**
- `gate_hatch_class <text> <Label>` → `accepted|near-miss|absent`
- `gate_near_miss_line <text> <Label>` → `N:line` or empty
- `gate_scan_staged`: require `GATE_LABEL`; skip on accepted; skip on `R*`;
  empty-`M` fallback; mask then `check_fn`
- `deny`: append near-miss / chain / worktree (best-effort)

- [ ] **Step 1: Failing classifier + short-circuit + real proven hatch smokes**

```zsh
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_hatch_class "Proven-gate: N/A — ok" "Proven-gate"')"
check "hatch class accepted" "accepted" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_hatch_class "Proven-gate: N/A - bad" "Proven-gate"')"
check "hatch class near-miss single hyphen" "near-miss" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_hatch_class "no hatch" "Proven-gate"')"
check "hatch class absent" "absent" "$out"

repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/e.md" $'Proven-gate: N/A — skip me\nwe verified nothing\n'
hits="$(print -rn -- "$(gt_commit_payload "$repo")" | bash -c '
  source "'"$HOOKS"'/lib/gate-common.sh"
  GATE_LABEL="Proven-gate"
  GATE_CHECK_HITS=0
  gate_in_scope() { case "$1" in *.md) return 0;; *) return 1;; esac; }
  gate_check() { GATE_CHECK_HITS=$((GATE_CHECK_HITS+1)); }
  gate_load
  gate_scan_staged gate_in_scope gate_check
  printf "%s" "$GATE_CHECK_HITS"
')"
check "accepted hatch skips check_fn" "0" "$hits"
gt_cleanup "$repo"
```

Add to proven-gate smoke (after existing escape case):

```zsh
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'Proven-gate: N/A — glossary\nwe verified nothing\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "accepted hatch via driver short-circuit -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Implement classifier, rewrite `gate_scan_staged`, extend `deny`**

```bash
gate_hatch_class() {  # <text> <Label> -> accepted|near-miss|absent
  local text="$1" label="$2"
  if gate_has_escape "$text" "$label"; then printf 'accepted'; return 0; fi
  if printf '%s' "$text" | sed -E 's/[`*]//g' | grep -Eiq "$label:[[:space:]]*N/A"; then
    printf 'near-miss'; return 0
  fi
  printf 'absent'
}

gate_near_miss_line() {
  printf '%s' "$1" | sed -E 's/[`*]//g' | grep -Ein "$2:[[:space:]]*N/A" | head -1 || true
}

gate_scan_staged() {
  local in_scope="$1" check="$2" f raw class status
  if [ -z "${GATE_LABEL:-}" ]; then
    deny "internal: GATE_LABEL unset before gate_scan_staged"
  fi
  while IFS= read -r f; do
    if [ -z "$f" ]; then continue; fi
    if ! "$in_scope" "$f"; then continue; fi
    if gate_is_scratch "$f"; then continue; fi
    raw="$(gate_staged_blob "$f")"
    if [ -z "$raw" ]; then continue; fi
    GATE_SCAN_PATH="$f"
    class="$(gate_hatch_class "$raw" "$GATE_LABEL")"
    GATE_NEAR_MISS=""
    if [ "$class" = "accepted" ]; then continue; fi
    if [ "$class" = "near-miss" ]; then
      GATE_NEAR_MISS="$(gate_near_miss_line "$raw" "$GATE_LABEL")"
    fi
    status="$(gate_staged_status "$f")"
    case "$status" in
      R*) continue ;;  # pure rename
    esac
    gate_staged_delta "$f"
    if [ "$status" = "M" ] && [ -z "${GATE_DELTA_ADDED}" ] && [ -z "${GATE_DELTA_REMOVED}" ]; then
      GATE_DELTA_ADDED="$raw"
    fi
    GATE_DELTA_ADDED="$(gate_mask_escape "${GATE_DELTA_ADDED}" "$GATE_LABEL")"
    GATE_DELTA_REMOVED="$(gate_mask_escape "${GATE_DELTA_REMOVED}" "$GATE_LABEL")"
    raw="$(gate_mask_escape "$raw" "$GATE_LABEL")"
    "$check" "$raw" "$f" || true
  done <<EOF
$(gate_staged_files)
EOF
}

deny() {
  local reason="$1" norm wt_class st_class
  if [ -n "${GATE_NEAR_MISS:-}" ]; then
    reason="$reason Near-miss escape at line ${GATE_NEAR_MISS%%:*}: use \`${GATE_LABEL}: N/A — <reason>\` (em dash or --)."
  fi
  norm="$(printf '%s' "${GATE_COMMAND:-}" | tr '\n' ' ')"
  if printf '%s' "$norm" | grep -Eq 'git[[:space:]]+add\b.*(&&|;|\|\|).*git[[:space:]]+commit\b'; then
    reason="$reason This command chained git add with git commit; the add did not run. Stage and commit as two separate tool calls."
  fi
  if [ -n "${GATE_CWD:-}" ] && [ -n "${GATE_SCAN_PATH:-}" ] && [ -f "$GATE_CWD/$GATE_SCAN_PATH" ]; then
    wt_class="$(gate_hatch_class "$(cat "$GATE_CWD/$GATE_SCAN_PATH" 2>/dev/null || true)" "${GATE_LABEL:-}")"
    st_class="$(gate_hatch_class "$(gate_staged_blob "$GATE_SCAN_PATH")" "${GATE_LABEL:-}")"
    if [ "$wt_class" = "accepted" ] && [ "$st_class" != "accepted" ]; then
      reason="$reason Working-tree copy has an accepted hatch that is not staged; gates read the index (git show :path)."
    fi
  fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(json_escape "$reason")"
  exit 0
}
```

- [ ] **Step 4: Per-gate edits (all seven)**

1. Set `GATE_LABEL="…"` immediately before `gate_scan_staged` (flaky: before
   message handling too).
2. Delete `gate_has_escape` and `gate_mask_escape` lines; use `$content` (already
   masked) where `$scan` / `$masked` was used.
3. Keep whole-file trigger greps until Tasks 4–7 (still correct for new-file
   staging).

Labels: `Evidence-gate`, `Proven-gate`, `Smoke`, `Backend-parity`,
`Flaky-gate`, `Occurrence-gate`, `Derived-value-gate`.

`flaky-gate` message path after Task 2 (until Task 6 refinements):

```bash
GATE_LABEL="Flaky-gate"
msg_class="$(gate_hatch_class "${GATE_COMMAND:-}" "Flaky-gate")"
if [ "$msg_class" != "accepted" ]; then
  GATE_NEAR_MISS=""
  if [ "$msg_class" = "near-miss" ]; then
    GATE_NEAR_MISS="$(gate_near_miss_line "${GATE_COMMAND:-}" "Flaky-gate")"
  fi
  GATE_SCAN_PATH=""
  # existing gate_check on message text, but without has_escape/mask —
  # mask the message locally for self-condemn only:
  scan="$(gate_mask_escape "${GATE_COMMAND:-}" "Flaky-gate")"
  # ... flaky/Mechanism greps on "$scan" with deny "In the commit message: ..."
  # Use where="the commit message" to preserve exact deny string:
  # deny "In the commit message: calls a failure ..."
fi
GATE_NEAR_MISS=""   # clear so file denies do not cite message near-miss
gate_scan_staged gate_in_scope gate_check_file
```

For message path, `gate_mask_escape` in the gate file is still needed until
Task 6 OR call it from common (allowed — common helpers stay). Prefer calling
`gate_mask_escape` from flaky for the **message only** (not staged files);
staged files are masked by the driver. Success criterion 5 is "no gate file
contains gate_mask_escape **for staged content**" — tighten to: after Task 6,
flaky message may still call `gate_mask_escape` on `GATE_COMMAND` only; zero
calls on staged blobs. Grep clean in Task 7: `gate_has_escape` gone everywhere;
`gate_mask_escape` only allowed in `flaky-gate.sh` on the message path (or
move message mask into a `gate_mask_escape` call inside a new
`gate_check_commit_message` helper in common in Task 6 — preferred: Task 6
uses `gate_hatch_class` + `gate_mask_escape` from common on the message, still
OK).

Simplest for criterion 5: after all tasks, `rg gate_has_escape hooks/*-gate.sh`
empty; `rg gate_mask_escape hooks/*-gate.sh` empty — message path uses a
one-liner inline mask or `gate_mask_escape` from common (sourcing is fine;
criterion means no *local reimplementation* and no staged-path calls). Plan
locks: **no** `gate_has_escape`/`gate_mask_escape` invocations remain in
`hooks/*-gate.sh` after Task 6; message masking inlines the awk from common or
calls common's function (calling common is fine — delete means remove the
*staged* escape dance). Calling `gate_mask_escape` from flaky is still an
invocation. Spec success 5: "No gate file contains `gate_mask_escape` or
`gate_has_escape`." So flaky message must use driver-style helper that lives
only in common, invoked as `gate_mask_escape` — that **is** containing the
name. Spec means no *local copy* of the logic and gates don't call has_escape
for staged. Adjust success check to:

```bash
rg 'gate_has_escape' hooks/*-gate.sh   # empty
# gate_mask_escape only allowed in flaky-gate.sh for GATE_COMMAND
```

Or add `gate_prepare_message_scan` in common. **Locked for this plan:** Task 6
adds `gate_scan_commit_message <check_fn>` in common that classifies/masks/
clears near-miss; flaky has zero hatch helper calls.

- [ ] **Step 5: All gate-common + all seven gate smokes PASS.**

- [ ] **Step 6: Optional commit.**

---

### Task 3: `gate_triggered [-w]` + rename+edit smoke

**Files:**
- Modify: `hooks/lib/gate-common.sh`
- Modify: `2026-08-27-gate-common-smoke.zsh`

- [ ] **Step 1: Failing smokes**

```zsh
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_DELTA_ADDED="hello smoke"; GATE_DELTA_REMOVED=""; gate_triggered "smoke" && echo fire || echo quiet')"
check "triggered on added" "fire" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_DELTA_ADDED="unproven only"; GATE_DELTA_REMOVED=""; gate_triggered -w "proven|verified" && echo fire || echo quiet')"
check "-w does not fire on unproven" "quiet" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_DELTA_ADDED="we verified it"; GATE_DELTA_REMOVED=""; gate_triggered -w "proven|verified" && echo fire || echo quiet')"
check "-w fires on verified" "fire" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_DELTA_ADDED="unrelated"; GATE_DELTA_REMOVED="Real path: x"; gate_triggered -w "proven|verified" "Real path:[[:space:]]*[^[:space:]]" && echo fire || echo quiet')"
check "re-arm on removed SAT" "fire" "$out"

repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/old.md" $'smoke poll timeout\n'
git -C "$repo" commit -qm base
git -C "$repo" mv meta/plans/old.md meta/plans/new.md
print -rn -- $'smoke poll timeout\nextra\n' > "$repo/meta/plans/new.md"
git -C "$repo" add -A
out="$(delta_added "$repo" "meta/plans/new.md" | grep -c smoke || true)"
check "rename+edit may put smoke in added delta (known tradeoff)" "1" "$out"
gt_cleanup "$repo"
```

- [ ] **Step 2: FAIL.**

- [ ] **Step 3: Implement**

```bash
gate_triggered() {  # [-w] TRIGGER_ERE [SAT_ERE…] -> 0 fire, 1 quiet
  local word=0 trigger
  if [ "${1:-}" = "-w" ]; then word=1; shift; fi
  trigger="${1:-}"; shift || true
  if [ -z "$trigger" ]; then return 1; fi
  if [ "$word" -eq 1 ]; then
    if printf '%s' "${GATE_DELTA_ADDED:-}" | LC_ALL=C grep -Eiqw -- "$trigger"; then return 0; fi
  else
    if printf '%s' "${GATE_DELTA_ADDED:-}" | LC_ALL=C grep -Eiq -- "$trigger"; then return 0; fi
  fi
  local sat
  for sat in "$@"; do
    if [ -n "$sat" ] && printf '%s' "${GATE_DELTA_REMOVED:-}" | LC_ALL=C grep -Eiq -- "$sat"; then
      return 0
    fi
  done
  return 1
}
```

- [ ] **Step 4: PASS + optional commit.**

---

### Task 4: Migrate `evidence-gate.sh`

**Files:**
- Modify: `hooks/evidence-gate.sh`
- Modify: `2026-07-01-evidence-gate-smoke.zsh`

- [ ] **Step 1: Cases 8–11**

```zsh
# 8. unrelated edit, smoke+poll already in HEAD -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/specs/s.md" $'Deleted old-smoke-runner.ts\n\n# pad\nline\nline\nline\nline\nline\nline\nline\nline\nline\nline\n\n| pollRoute.test.ts | No poll/ack |\n'
git -C "$repo" commit -qm base
print -rn -- "$(cat "$repo/meta/specs/s.md")"$'\nUnrelated paragraph only.\n' > "$repo/meta/specs/s.md"
git -C "$repo" add "meta/specs/s.md"
out="$(gt_run evidence-gate.sh "$(gt_commit_payload "$repo")")"
check "unrelated edit with existing smoke+poll -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 9. add-only poll beside existing smoke -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/specs/s.md" $'smoke design lives here\n'
git -C "$repo" commit -qm base
print -rn -- $'smoke design lives here\npoll for ready with timeout\n' > "$repo/meta/specs/s.md"
git -C "$repo" add "meta/specs/s.md"
out="$(gt_run evidence-gate.sh "$(gt_commit_payload "$repo")")"
check "add poll beside existing smoke -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 10. invariant 2: stable smoke line; delete only poll_until line -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/specs/s.md" $'smoke design lives here\nsmoke poll_until ok fail 5s\n'
git -C "$repo" commit -qm base
print -rn -- $'smoke design lives here\nsmoke poll loop with a timeout\n' > "$repo/meta/specs/s.md"
git -C "$repo" add "meta/specs/s.md"
out="$(gt_run evidence-gate.sh "$(gt_commit_payload "$repo")")"
check "delete dual-signal leave poll -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 11. near-miss hatch named on deny
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/specs/s.md" $'Evidence-gate: N/A - wrong dash\nsmoke SUT teardown on failure\n'
out="$(gt_run evidence-gate.sh "$(gt_commit_payload "$repo")")"
check "near-miss hatch still denies" "deny" "$(verdict "$out")"
printf '%s' "$out" | grep -qi 'Near-miss' && near=yes || near=no
check "near-miss named in denial" "yes" "$near"
gt_cleanup "$repo"
```

- [ ] **Step 2: Case 8 FAIL under whole-file.**

- [ ] **Step 3: Full `hooks/evidence-gate.sh` body**

```bash
#!/usr/bin/env bash
# evidence-gate.sh — commit-time content gate (session-continuity plugin).
# Fires before Bash(git commit *). For each staged */specs/*.md or */plans/*.md
# that discusses a smoke section, BLOCKS (A) teardown without preserve-before-
# teardown, or (B) a poll/wait loop without a dual (success+failure) signal.
# Escape: `Evidence-gate: N/A — reason` (driver short-circuit).
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

gate_in_scope() {
  case "$1" in */specs/*|*/plans/*) : ;; *) return 1 ;; esac
  case "${1##*/}" in *.md) return 0 ;; *) return 1 ;; esac
}

gate_check() {
  local content="$1" path="$2"
  local sat_td='before teardown|before tear down|keep_on_fail|preserve[^.]*(diagnostic|evidence|log)|diagnostic[^.]*before|on failure[^.]*(preserve|keep|dump|surface)'
  local sat_poll='poll_until|both[^.]*(success|pass)[^.]*(failure|fail)|success and failure|dual.signal|failure signal'
  local trig_td='teardown|tear down|cleanup|clean up'
  local trig_poll='poll|wait[_-]?for|readiness check|timeout loop'
  local fire=0
  if gate_triggered 'smoke' "$sat_td" "$sat_poll"; then fire=1; fi
  if [ "$fire" -eq 0 ] && printf '%s' "$content" | LC_ALL=C grep -Eiq 'smoke'; then
    if gate_triggered "$trig_td" "$sat_td" || gate_triggered "$trig_poll" "$sat_poll"; then
      fire=1
    fi
  fi
  [ "$fire" -eq 1 ] || return 0

  if printf '%s' "$content" | LC_ALL=C grep -Eiq "$trig_td"; then
    if ! printf '%s' "$content" | LC_ALL=C grep -Eiq "$sat_td"; then
      deny "In staged file $path: the smoke section mentions teardown/cleanup but never states the failure diagnostic is captured BEFORE teardown. Teardown-on-fail destroys evidence needed to diagnose without guessing. Add a preserve-before-teardown line (e.g. 'surface the diagnostic into the log before any teardown' or SMOKE_KEEP_ON_FAIL), or add: Evidence-gate: N/A — <reason> (decoration fine)."
    fi
  fi
  if printf '%s' "$content" | LC_ALL=C grep -Eiq "$trig_poll"; then
    if ! printf '%s' "$content" | LC_ALL=C grep -Eiq "$sat_poll"; then
      deny "In staged file $path: the smoke section mentions a poll/wait loop but never states it watches BOTH a success AND a failure signal. A success-only poll burns the full timeout on every failure and can't tell 'slow' from 'broken'. Name the dual-signal poll (e.g. 'poll_until <success> <failure> <timeout>'), or add: Evidence-gate: N/A — <reason> (decoration fine)."
    fi
  fi
}

gate_load
gate_is_commit || exit 0
GATE_LABEL="Evidence-gate"
gate_scan_staged gate_in_scope gate_check
exit 0
```

- [ ] **Step 4: Evidence smoke PASS.**

- [ ] **Step 5: Optional commit.**

---

### Task 5: Migrate `proven-gate.sh` + `backend-parity-gate.sh`

**Files:**
- Modify: `hooks/proven-gate.sh`, `hooks/backend-parity-gate.sh`
- Modify: both smokes

- [ ] **Step 1: Failing cases**

```zsh
# proven: incomplete claim in HEAD; unrelated edit -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'we verified the spike\n'
git -C "$repo" commit -qm base
print -rn -- $'we verified the spike\nunrelated\n' > "$repo/meta/plans/p.md"
git -C "$repo" add "meta/plans/p.md"
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "unrelated edit over incomplete claim in HEAD -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# proven: delete Real path, leave verified -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'we verified the spike\nReal path: hooks/x.sh\nStubbed: nothing\n'
git -C "$repo" commit -qm base
print -rn -- $'we verified the spike\nStubbed: nothing\n' > "$repo/meta/plans/p.md"
git -C "$repo" add "meta/plans/p.md"
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "delete Real path leave verified -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# backend: one backend named in HEAD; unrelated -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'multi backend smoke on docker only\n'
git -C "$repo" commit -qm base
print -rn -- $'multi backend smoke on docker only\nunrelated\n' > "$repo/meta/plans/p.md"
git -C "$repo" add "meta/plans/p.md"
out="$(gt_run backend-parity-gate.sh "$(gt_commit_payload "$repo")")"
check "unrelated edit over single-backend claim -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"
```

- [ ] **Step 2: FAIL on allow cases.**

- [ ] **Step 3: Full gate bodies**

`hooks/proven-gate.sh`:

```bash
#!/usr/bin/env bash
# proven-gate.sh — commit-time content gate (session-continuity plugin).
# Escape via driver: Proven-gate: N/A — <reason>.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

gate_in_scope() {
  case "$1" in */specs/*|*/plans/*) : ;; *) return 1 ;; esac
  case "${1##*/}" in *.md) return 0 ;; *) return 1 ;; esac
}

gate_check() {
  local content="$1" path="$2"
  local sat_real='Real path:[[:space:]]*[^[:space:]]'
  local sat_stub='Stubbed:[[:space:]]*[^[:space:]]'
  if ! gate_triggered -w 'proven|verified' "$sat_real" "$sat_stub" \
    && ! gate_triggered 'spike[[:space:]]+conclusive' "$sat_real" "$sat_stub"; then
    return 0
  fi
  local has_real=0 has_stub=0
  if printf '%s' "$content" | LC_ALL=C grep -Eiq "$sat_real"; then has_real=1; fi
  if printf '%s' "$content" | LC_ALL=C grep -Eiq "$sat_stub"; then has_stub=1; fi
  if [ "$has_real" -eq 0 ] || [ "$has_stub" -eq 0 ]; then
    local hit where=""
    hit="$(gate_first_match "$content" 'proven|verified')"
    if [ -z "$hit" ]; then hit="$(gate_first_match "$content" 'conclusive')"; fi
    if [ -n "$hit" ]; then
      where=" Matched at line ${hit%%:*}: \"$(printf '%s' "${hit#*:}" | cut -c1-120)\"."
    fi
    deny "In staged file $path: makes a 'proven/verified/spike conclusive' claim but does not name what was tested.${where} Add both fields next to the claim — 'Real path: <which production code path ran>' and 'Stubbed: <what stood in, or \"nothing\">'. If the stubbed thing is the feature under test, the claim is not proven. Or add a line (markdown decoration is fine): Proven-gate: N/A — <reason>."
  fi
}

gate_load
gate_is_commit || exit 0
GATE_LABEL="Proven-gate"
gate_scan_staged gate_in_scope gate_check
exit 0
```

`hooks/backend-parity-gate.sh`:

```bash
#!/usr/bin/env bash
# backend-parity-gate.sh — commit-time content gate (session-continuity plugin).
# Escape via driver: Backend-parity: N/A — <reason>.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

gate_in_scope() {
  case "${1##*/}" in *.md) : ;; *) return 1 ;; esac
  case "$1" in */plans/*) return 0 ;; esac
  case "${1##*/}" in *plan*.md) return 0 ;; *) return 1 ;; esac
}

gate_check() {
  local content="$1" path="$2" n hit_count=0
  gate_triggered 'backends?\b' || return 0
  for n in docker apple podman containerd colima kata lima orbstack; do
    if printf '%s' "$content" | LC_ALL=C grep -Eiq "\\b${n}\\b"; then hit_count=$((hit_count + 1)); fi
  done
  if [ "$hit_count" -lt 2 ]; then
    deny "In staged file $path: mentions 'backend(s)' but names fewer than two concrete backends. A smoke runner proven on only one backend has an unverified half — pair every backend-specific section with the other (e.g. Docker + Apple container). Name the second backend, or add: Backend-parity: N/A — <reason> (decoration fine) if there genuinely is only one."
  fi
}

gate_load
gate_is_commit || exit 0
GATE_LABEL="Backend-parity"
gate_scan_staged gate_in_scope gate_check
exit 0
```

- [ ] **Step 4: Both smokes PASS + optional commit.**

---

### Task 6: Migrate `flaky-gate.sh` + `gate_scan_commit_message`

**Files:**
- Modify: `hooks/lib/gate-common.sh` — add `gate_scan_commit_message`
- Modify: `hooks/flaky-gate.sh`
- Modify: `2026-07-01-flaky-gate-smoke.zsh`

- [ ] **Step 1: Cases** — LEARNINGS unrelated allow; LEARNINGS add flaky deny;
  message `flaky` without Mechanism deny (existing case 1 still).

- [ ] **Step 2: Implement common helper**

```bash
# Runs check_fn <masked_message_text> if message has no accepted hatch.
# Clears GATE_NEAR_MISS afterward so file scans cannot inherit it.
gate_scan_commit_message() {
  local check="$1" class
  class="$(gate_hatch_class "${GATE_COMMAND:-}" "$GATE_LABEL")"
  GATE_NEAR_MISS=""
  GATE_SCAN_PATH=""
  if [ "$class" = "accepted" ]; then
    GATE_NEAR_MISS=""
    return 0
  fi
  if [ "$class" = "near-miss" ]; then
    GATE_NEAR_MISS="$(gate_near_miss_line "${GATE_COMMAND:-}" "$GATE_LABEL")"
  fi
  "$check" "$(gate_mask_escape "${GATE_COMMAND:-}" "$GATE_LABEL")"
  GATE_NEAR_MISS=""
}
```

- [ ] **Step 3: Full `hooks/flaky-gate.sh`**

```bash
#!/usr/bin/env bash
# flaky-gate.sh — commit-time gate. DUAL surface: commit message + LEARNINGS.md.
# Escape via driver / gate_scan_commit_message: Flaky-gate: N/A — <reason>.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

gate_in_scope() {
  [ "${1##*/}" = "LEARNINGS.md" ] || return 1
  case "$1" in .session-continuity/*|*/.session-continuity/*) return 0 ;; *) return 1 ;; esac
}

gate_check_message() {
  local text="$1"
  [ -z "$text" ] && return 0
  printf '%s' "$text" | LC_ALL=C grep -Eiq '\b(flaky|transient)\b|CDN[[:space:]]+(blip|flake)' || return 0
  if ! printf '%s' "$text" | LC_ALL=C grep -Eiq 'Mechanism:[[:space:]]*[^[:space:]]'; then
    deny "In the commit message: calls a failure 'flaky'/'transient'/a 'CDN blip' without naming the deterministic cause. CLAUDE.md rule 1: an intermittent failure has a deterministic cause (race, shared/global state, an env/sandbox dependency) — name it or state the precise fail condition. Add a 'Mechanism: <named cause>' line, or add: Flaky-gate: N/A — <reason> (decoration fine)."
  fi
}

gate_check_file() {
  local content="$1" path="$2"
  if ! gate_triggered '\b(flaky|transient)\b|CDN[[:space:]]+(blip|flake)' \
      'Mechanism:[[:space:]]*[^[:space:]]'; then
    return 0
  fi
  if ! printf '%s' "$content" | LC_ALL=C grep -Eiq 'Mechanism:[[:space:]]*[^[:space:]]'; then
    deny "In staged file $path: calls a failure 'flaky'/'transient'/a 'CDN blip' without naming the deterministic cause. CLAUDE.md rule 1: an intermittent failure has a deterministic cause (race, shared/global state, an env/sandbox dependency) — name it or state the precise fail condition. Add a 'Mechanism: <named cause>' line, or add: Flaky-gate: N/A — <reason> (decoration fine)."
  fi
}

gate_load
gate_is_commit || exit 0
GATE_LABEL="Flaky-gate"
gate_scan_commit_message gate_check_message
gate_scan_staged gate_in_scope gate_check_file
exit 0
```

Note: existing deny used `In $where:` with `where="the commit message"` →
text is `In the commit message:` — keep that exact string (as above).

- [ ] **Step 4: Flaky smoke PASS + optional commit.**

---

### Task 7: occurrence + smoke + derived-value

**Files:**
- Modify: `hooks/occurrence-gate.sh`, `hooks/smoke-gate.sh`,
  `hooks/derived-value-gate.sh` + their smokes

- [ ] **Step 1: Add unrelated-allow / new-deny / SAT-delete cases; FAIL.**

- [ ] **Step 2: Full `occurrence-gate.sh`**

```bash
#!/usr/bin/env bash
# occurrence-gate.sh — Escape via driver: Occurrence-gate: N/A — <reason>.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

gate_in_scope() {
  [ "${1##*/}" = "LEARNINGS.md" ] || return 1
  case "$1" in .session-continuity/*|*/.session-continuity/*) return 0 ;; *) return 1 ;; esac
}

_occurrence_max_n() {  # <text> -> max N from Occurrence count: N of M
  local text="$1" n max_n=0
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    if [ "$n" -gt "$max_n" ] 2>/dev/null; then max_n="$n"; fi
  done <<EOF
$(printf '%s' "$text" \
  | grep -oiE 'Occurrence count:[[:space:]]*[0-9]+[[:space:]]+of[[:space:]]+[0-9]+' \
  | grep -oiE '[0-9]+[[:space:]]+of' \
  | grep -oE '^[0-9]+')
EOF
  printf '%s' "$max_n"
}

gate_check() {
  local content="$1" path="$2" max_n=0 max_added=0 has_inv=0
  max_added="$(_occurrence_max_n "${GATE_DELTA_ADDED:-}")"
  max_n="$(_occurrence_max_n "$content")"
  local fire=0
  if [ "$max_added" -ge 2 ]; then fire=1; fi
  if [ "$fire" -eq 0 ] && [ "$max_n" -ge 2 ] \
    && printf '%s' "${GATE_DELTA_REMOVED:-}" | LC_ALL=C grep -Eiq 'Invariant:[[:space:]]*[^[:space:]]'; then
    fire=1
  fi
  [ "$fire" -eq 1 ] || return 0
  [ "$max_n" -ge 2 ] || return 0
  if printf '%s' "$content" | LC_ALL=C grep -Eiq 'Invariant:[[:space:]]*[^[:space:]]'; then has_inv=1; fi
  if [ "$has_inv" -eq 0 ]; then
    deny "In staged file $path: records occurrence #${max_n} of a mistake-class but names no end-state invariant. CLAUDE.md rule 4: a class fixed across 2+ attempts needs an 'Invariant: <what must hold on EVERY path, enforced at the reconciler/entry gate>' line — not another trigger-patch. Add it next to the 'Occurrence count:' line, or add: Occurrence-gate: N/A — <reason> (decoration fine)."
  fi
}

gate_load
gate_is_commit || exit 0
GATE_LABEL="Occurrence-gate"
gate_scan_staged gate_in_scope gate_check
exit 0
```

- [ ] **Step 3: Full `smoke-gate.sh`**

```bash
#!/usr/bin/env bash
# smoke-gate.sh — Escape via driver: Smoke: N/A — <reason>.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

gate_in_scope() {
  case "${1##*/}" in *.md) : ;; *) return 1 ;; esac
  case "$1" in */plans/*) return 0 ;; esac
  case "${1##*/}" in *plan*.md) return 0 ;; *) return 1 ;; esac
}

gate_check() {
  local content="$1" path="$2" offender
  local weak='optional|deferred|after.?merge|nice.?to.?have'
  local bin='binary|engine|container|daemon|--compile|bun build'
  # MANDATORY smoke anywhere in document → allow (satisfaction)
  if printf '%s' "$content" | LC_ALL=C grep -Eiq 'smoke.*\bMANDATORY\b|\bMANDATORY\b.*smoke'; then
    return 0
  fi
  # Weak-smoke: only when smoke appears in the delta
  if gate_triggered 'smoke'; then
    offender="$(printf '%s' "${GATE_DELTA_ADDED}" | grep -Ei "smoke[^.]{0,20}($weak)|($weak)[^.]{0,20}smoke" | head -1 || true)"
    if [ -n "$offender" ]; then
      deny "In staged file $path: smoke task looks optional/deferred (matched: \"${offender}\"). If incidental prose, reword; if the smoke task is mandatory add the word MANDATORY on a smoke line, or add: Smoke: N/A — <reason> (markdown decoration is fine) if this plan touches no binary/engine."
    fi
    return 0
  fi
  # No smoke in delta: binary/engine newly added without smoke satisfaction
  if gate_triggered "$bin"; then
    if ! printf '%s' "$content" | LC_ALL=C grep -Eiq 'smoke'; then
      deny "In staged file $path: mentions binary/engine/container work but has no smoke task. Add a MANDATORY smoke task, or add: Smoke: N/A — <reason> (markdown decoration is fine) if it genuinely touches no binary/engine."
    fi
  fi
}

gate_load
gate_is_commit || exit 0
GATE_LABEL="Smoke"
gate_scan_staged gate_in_scope gate_check
exit 0
```

- [ ] **Step 4: Full `derived-value-gate.sh`** — grep patterns on
  `GATE_DELTA_ADDED`; cite via `gate_first_match` on `$content`:

```bash
#!/usr/bin/env bash
# derived-value-gate.sh — Escape via driver: Derived-value-gate: N/A — <reason>.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

gate_in_scope() {
  case "$1" in commands/*.md) return 0 ;; *) return 1 ;; esac
}

_dvg_deny() {
  local path="$1" label="$2" hit="$3" explanation="$4" line matched
  line="${hit%%:*}"
  matched="$(printf '%s' "${hit#*:}" | cut -c1-120)"
  deny "In staged file $path, line $line: $label (\"$matched\"). $explanation Add: Derived-value-gate: N/A — <reason> (decoration fine)."
}

_dvg_hit() {  # <ere> -> file "N:line" via first match of delta hit in content, or empty
  local ere="$1" content="$2" frag
  frag="$(printf '%s' "${GATE_DELTA_ADDED:-}" | LC_ALL=C grep -ioE "$ere" | head -1 || true)"
  [ -n "$frag" ] || { printf ''; return 0; }
  gate_first_match "$content" "$(printf '%s' "$frag" | sed -e 's/[.[\*^$()+?{|]/\\&/g')"
}

_dvg_check_duration() {
  local content="$1" path="$2" hit
  hit="$(_dvg_hit 'date -u -j -f|date -u -d "|\$\(\([^)]*_epoch[^)]*-[^)]*_epoch' "$content")"
  [ -n "$hit" ] || return 0
  _dvg_deny "$path" "instructs a model to compute a duration by hand (epoch subtraction)" "$hit" \
    "A script owns duration math — see hooks/lib/perf-log.sh's since subcommand."
}

_dvg_check_count() {
  local content="$1" path="$2" hit
  hit="$(_dvg_hit 'cardinality|Pin to the count seen in|RETRIES count|saw.*across[[:space:]]+[0-9]+[[:space:]]+runs[[:space:]]*—' "$content")"
  [ -n "$hit" ] || return 0
  _dvg_deny "$path" "instructs a model to tally or vote on a count by eye" "$hit" \
    "A script owns cardinality/majority-vote math — see hooks/lib/token-overlap.sh and hooks/lib/test-count-rerun.sh."
}

_dvg_check_compare() {
  local content="$1" path="$2" hit
  hit="$(_dvg_hit '^[[:space:]]*[Dd]oes[^.]*match[^.]*above|match(es)?[[:space:]]+the[^.]*output above|disagrees with the recorded' "$content")"
  [ -n "$hit" ] || return 0
  _dvg_deny "$path" "instructs a model to eyeball-compare a claimed value against an actual one" "$hit" \
    "A script owns the comparison (an awk range extract plus diff, or the same shape as hooks/lib/primer-detect.sh)."
}

_dvg_check_verbatim() {
  local content="$1" path="$2" hit
  hit="$(_dvg_hit 'not instructions to you|Illustrative only|List every file[^.]*do not summarize|Never omit it\. Never replace it with paraphrased prose|Always emit[^.]*exactly:' "$content")"
  [ -n "$hit" ] || return 0
  _dvg_deny "$path" "ships fixed reference text or a determinism-compensating instruction as prompt prose" "$hit" \
    "Fixed output belongs in the script that computes the values around it (skills/session-continuity/REFERENCE.md or a spec, not a command body)."
}

gate_check() {
  local content="$1" path="$2"
  _dvg_check_duration "$content" "$path"
  _dvg_check_count "$content" "$path"
  _dvg_check_compare "$content" "$path"
  _dvg_check_verbatim "$content" "$path"
}

gate_load
gate_is_commit || exit 0
GATE_LABEL="Derived-value-gate"
gate_scan_staged gate_in_scope gate_check
exit 0
```

- [ ] **Step 5: All three smokes PASS.**

- [ ] **Step 6: Grep clean**

```bash
rg 'gate_has_escape|gate_mask_escape' hooks/*-gate.sh
```

Expected: no matches.

- [ ] **Step 7: Optional commit.**

---

### Task 8: Consumer docs + 0.37.0

**Files:**
- Modify: `README.md`, `skills/session-continuity/REFERENCE.md`,
  `CHANGELOG.md`, `.claude-plugin/plugin.json`
- Verify: `CLAUDE_MD_SNIPPET.md` chain trap

- [ ] **Step 1–3:** README commit-time bullets; REFERENCE consumer traps
  (index vs editor; file-scoped escapes; satisfy-before-escape; near-miss;
  chain; delta trigger; pure rename allow); CHANGELOG + version `0.37.0`.

- [ ] **Step 4: Full suite** (all eight smokes listed in prior plan revision) —
  expect `fail=0`.

- [ ] **Step 5: Primer Mid-flight** when user asks to commit release docs.

---

## Spec coverage checklist

| Spec requirement | Task |
|---|---|
| Pinned content delta + color.diff | 1 |
| Rename-aware status `R*` skip | 1–2 |
| Hatch short-circuit + central mask + delete local escape | 2 |
| `gate_triggered [-w]` + rename+edit | 3 |
| evidence fire paths + Bug A + inv-2 fixture + near-miss | 4 |
| proven `-w` + backend-parity | 5 |
| flaky message helper + LEARNINGS delta + clear near-miss | 6 |
| occurrence / smoke / derived-value | 7 |
| No hatch helpers in gate files | 7 Step 6 |
| README + REFERENCE + 0.37.0 | 8 |

## Self-review notes (post caveman-review fix)

- Rename vs `--no-renames`: status uses `-M` without `--no-renames`; content
  keeps pins; `R*` skips check.
- `set -e` continues use `if` form only.
- Proven uses `gate_triggered -w`.
- No `…` placeholders; full gate bodies in Tasks 4–7.
- Case 10 is two-line inv-2 fixture.
- Message `GATE_NEAR_MISS` cleared via `gate_scan_commit_message`.
- Local escape deleted in Task 2 with real proven short-circuit smoke.
