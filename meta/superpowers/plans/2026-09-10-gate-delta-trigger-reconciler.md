# Gate delta-trigger reconciler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all seven commit-time content gates fire on the commit's staged
delta and satisfy against the whole document, with escape short-circuit and
masking owned by the shared driver.

**Architecture:** Extend `hooks/lib/gate-common.sh` with pinned
`gate_staged_delta`, `gate_hatch_class`, `gate_triggered TRIGGER [SAT…]`,
driver short-circuit on accepted hatch, central mask, and best-effort `deny`
diagnostics. Each gate sets `GATE_LABEL`, deletes local escape/mask calls, and
migrates triggers per
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
  unchanged (em dash or `--` + reason); no `gate_window_around`; no widening
  separators; pattern *strings* unchanged (scope only).
- Diff pins (verbatim):
  `git -c diff.algorithm=myers diff --cached --no-color --no-ext-diff --no-textconv --no-renames -U0 -- <path>`
- Greps/masker: `LC_ALL=C`.
- Escape order: classify **unmasked** blob → accepted skips `check_fn` → mask →
  `check_fn`. No gate may call `gate_has_escape` or `gate_mask_escape` after
  this lands (success criterion 5).
- `GATE_LABEL` set explicitly in every gate before `gate_scan_staged`.
- Diagnostics (near-miss, chained add, worktree hatch) are best-effort text on
  `deny` only — never flip allow/deny.
- Release: **0.37.0** (bump `.claude-plugin/plugin.json` + `CHANGELOG.md`).
- Spec/plan under `meta/superpowers/`, not `docs/`.
- Do not commit unless the user asked; Commit steps are optional gates.
- Smokes need unsandboxed `git init`.
- Never chain `git add` && `git commit` in one Bash tool call when gates can
  deny.

## File map

| File | Role |
|---|---|
| `hooks/lib/gate-common.sh` | Delta, hatch class, `gate_triggered`, driver, `deny` append |
| `hooks/*-gate.sh` (seven) | `GATE_LABEL` + trigger migration |
| `meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh` | New driver/API cases |
| `meta/superpowers/validation/2026-*-*gate*smoke.zsh` | Delta / delete-SAT / near-miss cases |
| `README.md` | Fix Write/Edit bullets → commit-time |
| `skills/session-continuity/REFERENCE.md` | Consumer section |
| `skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md` | Verify chain trap already present |
| `CHANGELOG.md` / `.claude-plugin/plugin.json` | 0.37.0 |

---

### Task 1: `gate_staged_delta` + color.diff pin (TDD)

**Files:**
- Modify: `hooks/lib/gate-common.sh`
- Modify: `meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh`
- Test: same smoke

**Interfaces:**
- Consumes: `GATE_CWD` (existing)
- Produces: `gate_staged_delta <relpath>` sets globals `GATE_DELTA_ADDED` and
  `GATE_DELTA_REMOVED` (newline-joined text, no `+`/`-` prefixes). Also
  `gate_staged_status <relpath>` → status letter from
  `git diff --cached --name-status --no-renames` (`A`/`M`/`D`/…); empty if
  missing.

- [ ] **Step 1: Append failing smoke cases**

Before the final `print -r -- "---"` in `2026-08-27-gate-common-smoke.zsh`:

```zsh
delta_added() {
  local repo="$1" path="$2"
  bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_CWD="'"$repo"'"; gate_staged_delta "'"$path"'"; printf "%s" "$GATE_DELTA_ADDED"'
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
out="$(delta_added "$repo" "meta/plans/s.md")"
check "pure rename added delta empty" "" "$out"
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

- [ ] **Step 2: Run smoke — expect FAIL**

```bash
zsh meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh
```

Expected: FAIL (`gate_staged_delta` missing).

- [ ] **Step 3: Implement in `hooks/lib/gate-common.sh`** (after `gate_staged_blob`)

```bash
gate_staged_status() {  # <relpath> -> A|M|D|... or empty
  local path="$1" line
  [ -n "${GATE_CWD:-}" ] || { printf ''; return 0; }
  line="$(git -C "$GATE_CWD" -c diff.algorithm=myers diff --cached --name-status \
    --no-color --no-ext-diff --no-textconv --no-renames -- "$path" 2>/dev/null | head -1 || true)"
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

- [ ] **Step 4: Re-run smoke — new cases PASS; existing still green.**

- [ ] **Step 5: Commit** (only if user asked)

```bash
git add hooks/lib/gate-common.sh meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh
git commit -m "feat(gates): pinned gate_staged_delta for commit-time triggers"
```

---

### Task 2: `gate_hatch_class` + driver short-circuit + `GATE_LABEL` stubs

**Files:**
- Modify: `hooks/lib/gate-common.sh`
- Modify: all seven `hooks/*-gate.sh` (set `GATE_LABEL=…` before `gate_scan_staged`)
- Modify: `meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh`

**Interfaces:**
- Produces: `gate_hatch_class <text> <Label>` → `accepted|near-miss|absent`;
  `gate_near_miss_line <text> <Label>` → `N:line` or empty;
  rewritten `gate_scan_staged` (short-circuit, mask, empty-`M` fallback);
  `deny` appends near-miss / chain / worktree clauses.

**Labels:** `Evidence-gate`, `Proven-gate`, `Smoke`, `Backend-parity`,
`Flaky-gate`, `Occurrence-gate`, `Derived-value-gate`.

- [ ] **Step 1: Failing classifier + short-circuit smokes**

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

- [ ] **Step 2: Run — expect FAIL.**

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

gate_near_miss_line() {  # <text> <Label> -> "N:line" or empty
  printf '%s' "$1" | sed -E 's/[`*]//g' | grep -Ein "$2:[[:space:]]*N/A" | head -1 || true
}

gate_scan_staged() {
  local in_scope="$1" check="$2" f raw class status
  if [ -z "${GATE_LABEL:-}" ]; then
    deny "internal: GATE_LABEL unset before gate_scan_staged"
  fi
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    "$in_scope" "$f" || continue
    gate_is_scratch "$f" && continue
    raw="$(gate_staged_blob "$f")"
    [ -z "$raw" ] && continue
    GATE_SCAN_PATH="$f"
    class="$(gate_hatch_class "$raw" "$GATE_LABEL")"
    GATE_NEAR_MISS=""
    [ "$class" = "accepted" ] && continue
    if [ "$class" = "near-miss" ]; then
      GATE_NEAR_MISS="$(gate_near_miss_line "$raw" "$GATE_LABEL")"
    fi
    gate_staged_delta "$f"
    status="$(gate_staged_status "$f")"
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
```

Extend `deny` (append before JSON emit):

```bash
deny() {
  local reason="$1" cmd norm wt_class st_class
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

- [ ] **Step 4: Set `GATE_LABEL=…` in all seven gates** before `gate_scan_staged`
  (keep local `gate_has_escape` until later tasks — driver short-circuit now
  handles accepted hatches on the file path; local calls become redundant but
  must not break until deleted).

- [ ] **Step 5: gate-common smoke PASS; all seven gate smokes still PASS.**

```bash
zsh meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh
for f in meta/superpowers/validation/2026-*-*gate*smoke.zsh; do zsh "$f" || exit 1; done
```

- [ ] **Step 6: Commit** (optional).

---

### Task 3: `gate_triggered` + rename+edit documentation smoke

**Files:**
- Modify: `hooks/lib/gate-common.sh`
- Modify: `meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh`

**Interfaces:**
- Consumes: `GATE_DELTA_ADDED`, `GATE_DELTA_REMOVED`
- Produces: `gate_triggered TRIGGER_ERE [SAT_ERE…]` → 0 fire / 1 quiet

- [ ] **Step 1: Failing smokes**

```zsh
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_DELTA_ADDED="hello smoke"; GATE_DELTA_REMOVED=""; gate_triggered smoke && echo fire || echo quiet')"
check "triggered on added" "fire" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_DELTA_ADDED="unrelated"; GATE_DELTA_REMOVED="Real path: x"; gate_triggered "proven|verified" "Real path:[[:space:]]*[^[:space:]]" && echo fire || echo quiet')"
check "re-arm on removed SAT" "fire" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_DELTA_ADDED="unrelated"; GATE_DELTA_REMOVED=""; gate_triggered smoke && echo fire || echo quiet')"
check "no trigger quiet" "quiet" "$out"

repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/old.md" $'smoke poll timeout\n'
git -C "$repo" commit -qm base
git -C "$repo" mv meta/plans/old.md meta/plans/new.md
print -rn -- $'smoke poll timeout\nextra\n' > "$repo/meta/plans/new.md"
git -C "$repo" add -A
out="$(delta_added "$repo" "meta/plans/new.md" | grep -c smoke || true)"
check "rename+edit attributes smoke into added delta (known tradeoff)" "1" "$out"
gt_cleanup "$repo"
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Implement**

```bash
gate_triggered() {  # TRIGGER_ERE [SAT_ERE…] -> 0 fire, 1 quiet
  local trigger="$1"; shift || true
  if printf '%s' "${GATE_DELTA_ADDED:-}" | LC_ALL=C grep -Eiq -- "$trigger"; then return 0; fi
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

### Task 4: Migrate `evidence-gate.sh` (canonical)

**Files:**
- Modify: `hooks/evidence-gate.sh`
- Modify: `meta/superpowers/validation/2026-07-01-evidence-gate-smoke.zsh`

**Interfaces:**
- Consumes: `gate_triggered`, driver short-circuit
- Produces: spec fire paths (smoke-in-delta OR smoke-in-doc + teardown/poll-in-delta)

- [ ] **Step 1: Add cases 8–11** to evidence smoke:

```zsh
# 8. HEAD has smoke+poll far apart; unrelated edit -> allow
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

# 10. delete dual-signal, leave poll+smoke -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/specs/s.md" $'smoke poll_until ok fail 5s\n'
git -C "$repo" commit -qm base
print -rn -- $'smoke poll loop with a timeout\n' > "$repo/meta/specs/s.md"
git -C "$repo" add "meta/specs/s.md"
out="$(gt_run evidence-gate.sh "$(gt_commit_payload "$repo")")"
check "delete dual-signal leave poll -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 11. single-hyphen hatch on denying content -> deny names near-miss
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/specs/s.md" $'Evidence-gate: N/A - wrong dash\nsmoke SUT teardown on failure\n'
out="$(gt_run evidence-gate.sh "$(gt_commit_payload "$repo")")"
check "near-miss hatch still denies" "deny" "$(verdict "$out")"
printf '%s' "$out" | grep -qi 'Near-miss' && near=yes || near=no
check "near-miss named in denial" "yes" "$near"
gt_cleanup "$repo"
```

- [ ] **Step 2: Run — case 8 FAIL** (still deny under whole-file).

- [ ] **Step 3: Rewrite `hooks/evidence-gate.sh` `gate_check`**

Keep deny message strings **verbatim** from the current file.

```bash
GATE_LABEL="Evidence-gate"

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

Delete every `gate_has_escape` / `gate_mask_escape` from this file.

- [ ] **Step 4: Evidence smoke all PASS** (cases 1–7 still: new-file delta = full content).

- [ ] **Step 5: Optional commit.**

---

### Task 5: Migrate `proven-gate.sh` + `backend-parity-gate.sh`

**Files:**
- Modify: `hooks/proven-gate.sh`, `hooks/backend-parity-gate.sh`
- Modify: `2026-06-17-proven-gate-smoke.zsh`, `2026-07-01-backend-parity-gate-smoke.zsh`

- [ ] **Step 1: Add failing cases**

Proven — incomplete claim already in HEAD, unrelated edit → allow after fix:

```zsh
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'we verified the spike\n'
git -C "$repo" commit -qm base
print -rn -- $'we verified the spike\nunrelated\n' > "$repo/meta/plans/p.md"
git -C "$repo" add "meta/plans/p.md"
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "unrelated edit over incomplete claim in HEAD -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"
```

Proven — delete `Real path:` leave verified → deny.

Backend — `backend` + one named backend in HEAD; unrelated edit → allow.  
Add second incomplete `backend` claim without second concrete backend as needed.

- [ ] **Step 2: FAIL on unrelated-edit allow case.**

- [ ] **Step 3: Rewrite**

```bash
# proven-gate.sh
GATE_LABEL="Proven-gate"
gate_check() {
  local content="$1" path="$2"
  local sat_real='Real path:[[:space:]]*[^[:space:]]'
  local sat_stub='Stubbed:[[:space:]]*[^[:space:]]'
  if ! gate_triggered 'proven|verified' "$sat_real" "$sat_stub" \
    && ! gate_triggered 'spike[[:space:]]+conclusive' "$sat_real" "$sat_stub"; then
    return 0
  fi
  # Keep existing Real path / Stubbed greps + deny text on "$content"
  …
}

# backend-parity-gate.sh
GATE_LABEL="Backend-parity"
gate_check() {
  local content="$1" path="$2"
  gate_triggered 'backends?\b' || return 0
  # existing name-count loop on "$content"
  …
}
```

Delete local escape/mask.

- [ ] **Step 4: Both smokes PASS + optional commit.**

---

### Task 6: Migrate `flaky-gate.sh`

**Files:**
- Modify: `hooks/flaky-gate.sh`
- Modify: `2026-07-01-flaky-gate-smoke.zsh`

- [ ] **Step 1: Cases** — LEARNINGS unrelated allow; LEARNINGS add flaky deny;
  commit-message `flaky` without Mechanism still deny (whole-text).

- [ ] **Step 2: Implement**

```bash
GATE_LABEL="Flaky-gate"

gate_check_message() {
  local text="$1"
  [ -z "$text" ] && return 0
  printf '%s' "$text" | LC_ALL=C grep -Eiq '\b(flaky|transient)\b|CDN[[:space:]]+(blip|flake)' || return 0
  if ! printf '%s' "$text" | LC_ALL=C grep -Eiq 'Mechanism:[[:space:]]*[^[:space:]]'; then
    deny "In the commit message: …"  # keep existing wording
  fi
}

gate_check_file() {
  local content="$1" path="$2"
  if ! gate_triggered '\b(flaky|transient)\b|CDN[[:space:]]+(blip|flake)' \
      'Mechanism:[[:space:]]*[^[:space:]]'; then
    return 0
  fi
  if ! printf '%s' "$content" | LC_ALL=C grep -Eiq 'Mechanism:[[:space:]]*[^[:space:]]'; then
    deny "In staged file $path: …"
  fi
}

gate_load
gate_is_commit || exit 0
GATE_LABEL="Flaky-gate"
# Message path: no delta; classify hatch on GATE_COMMAND yourself
msg_class="$(gate_hatch_class "${GATE_COMMAND:-}" "Flaky-gate")"
if [ "$msg_class" != "accepted" ]; then
  GATE_NEAR_MISS=""
  [ "$msg_class" = "near-miss" ] && GATE_NEAR_MISS="$(gate_near_miss_line "${GATE_COMMAND:-}" "Flaky-gate")"
  GATE_SCAN_PATH=""
  gate_check_message "$GATE_COMMAND"
fi
gate_scan_staged gate_in_scope gate_check_file
exit 0
```

Delete `gate_has_escape` / `gate_mask_escape` from flaky-gate.

- [ ] **Step 3: PASS + optional commit.**

---

### Task 7: Migrate occurrence + smoke + derived-value gates

**Files:**
- Modify: `hooks/occurrence-gate.sh`, `hooks/smoke-gate.sh`,
  `hooks/derived-value-gate.sh`
- Modify: their three smoke files

**occurrence-gate:** Parse `Occurrence count: N of M` with N≥2 from
`GATE_DELTA_ADDED` (reuse existing parse on added text). Re-arm if
`Invariant:` appears in `GATE_DELTA_REMOVED` while `$content` still has N≥2.
Satisfy `Invariant:` on whole `$content`. Delete local escape.

**smoke-gate:** `GATE_LABEL=Smoke`. Weak-smoke: smoke(+weak) on added lines.
Binary path: `gate_triggered 'binary|engine|container|daemon|--compile|bun build'`
when document lacks MANDATORY smoke. Keep deny strings. Driver short-circuits
accepted `Smoke:` hatch.

**derived-value-gate:** Each `_dvg_check_*` detects pattern on
`GATE_DELTA_ADDED`; cite real file line via `gate_first_match "$content"
'<matched substring>'` (or deny with delta context if map fails). No SAT.
`GATE_LABEL=Derived-value-gate`. Delete local escape/mask.

- [ ] **Step 1:** Add unrelated-allow + new-deny (+ SAT-delete for occurrence)
  cases to each smoke; run → FAIL.
- [ ] **Step 2:** Implement each gate per above.
- [ ] **Step 3:** Each smoke PASS.
- [ ] **Step 4: Grep clean**

```bash
rg 'gate_has_escape|gate_mask_escape' hooks/*-gate.sh
```

Expected: no matches.

- [ ] **Step 5: Optional commit.**

---

### Task 8: Consumer docs + 0.37.0

**Files:**
- Modify: `README.md`, `skills/session-continuity/REFERENCE.md`,
  `CHANGELOG.md`, `.claude-plugin/plugin.json`
- Verify: `skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md` already
  has the never-chain `git add`/`git commit` rule — edit only if wording drifts

- [ ] **Step 1: README** — seven gate bullets: commit-time / staged index, not
  Write/Edit.
- [ ] **Step 2: REFERENCE** — subsection **Commit-time gates — consumer traps**:
  index vs editor; file-scoped escapes; satisfy-before-escape; near-miss clause;
  chain trap; delta trigger (unrelated edits).
- [ ] **Step 3: CHANGELOG `[0.37.0]`** + `plugin.json` `"version": "0.37.0"`.
- [ ] **Step 4: Full suite**

```bash
zsh meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh
zsh meta/superpowers/validation/2026-07-01-evidence-gate-smoke.zsh
zsh meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh
zsh meta/superpowers/validation/2026-07-01-backend-parity-gate-smoke.zsh
zsh meta/superpowers/validation/2026-07-01-flaky-gate-smoke.zsh
zsh meta/superpowers/validation/2026-06-17-occurrence-gate-smoke.zsh
zsh meta/superpowers/validation/2026-08-06-smoke-gate-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-derived-value-gate-smoke.zsh
```

Expected: all `fail=0`.

- [ ] **Step 5: Primer Mid-flight** refresh for 0.37.0 when committing release
  docs (same commit as changelog if user asked to commit).

---

## Spec coverage checklist

| Spec requirement | Task |
|---|---|
| Pinned delta + color.diff | 1 |
| Hatch class + short-circuit + central mask + empty `M` | 2 |
| `gate_triggered` + rename+edit tradeoff | 3 |
| evidence fire paths + Bug A + near-miss | 4 |
| proven + backend-parity | 5 |
| flaky LEARNINGS delta + message whole-text | 6 |
| occurrence / smoke / derived-value | 7 |
| No hatch helpers in gate files | 7 Step 4 |
| README + REFERENCE + 0.37.0 | 8 |
| Denial diagnostics | 2 |
| Success criteria 1–8 | Tasks 4–8 |

## Self-review notes

- No TBD/placeholder steps. API names stable: `gate_staged_delta`,
  `gate_hatch_class`, `gate_triggered`, `GATE_LABEL`, `GATE_NEAR_MISS`.
- Task 2 requires LABEL stubs on all gates before Tasks 4–7 finish deleting
  local escape — called out so mid-flight smokes stay green.
- CLAUDE_MD_SNIPPET chain trap already exists — Task 8 verifies.
