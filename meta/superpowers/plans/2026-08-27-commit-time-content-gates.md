# Commit-Time Content Gates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the five content gates (proven, smoke, evidence, backend-parity, occurrence) and flaky-gate's file check from blocking `Write|Edit` to blocking `Bash(git commit *)`, so files always save and only commits are gated — plus a decoration-tolerant escape line and dot-prefixed-scratch skip.

**Architecture:** A new sourced `hooks/lib/gate-common.sh` owns payload parsing, `git commit` detection, cwd extraction, staged-file enumeration, staged-blob reads, scratch-skip, escape-line matching, and the JSON `deny`. Each gate becomes a thin script that sources the lib, defines `gate_in_scope` + `gate_check`, and calls the shared driver. Gates read the staged index version of each matching file at commit time instead of the tool-call payload.

**Tech Stack:** Bash (hooks), zsh (hermetic test runners), git plumbing (`diff --cached`, `show :path`), `python3 -m json.tool` for JSON-parse asserts.

**Spec:** `meta/superpowers/specs/2026-08-27-commit-time-content-gates-design.md`

## Global Constraints

- **`set -euo pipefail` safety.** Every helper and check runs under `set -euo pipefail`. Use `if cmd; then var=1; fi` — NEVER `cmd && var=1` or `cmd && return` (a non-matching `grep` returns non-zero and `set -e` will kill the script). Use `cmd || continue` / `cmd || return 0` freely (the `||` consumes the failure). This is the single most common way to break these gates.
- **Output contract (LEARNINGS #1).** Block = print one JSON object with `hookSpecificOutput.permissionDecision:"deny"` and exit 0. Allow = silent `exit 0`. PreToolUse does NOT treat plain stdout as context.
- **Permissive on the commit path.** Empty payload, non-Bash tool, non-`git commit` command, missing/invalid cwd, git error, empty staged set → silent `exit 0`. A miss fails to block; it never blocks a save. `git commit -a`/pathspec commits are an accepted permissive miss (spec Tradeoffs).
- **cwd source.** Read the payload `cwd` field, NOT `$CLAUDE_PLUGIN_ROOT` (for plugin installs the env var points at the plugin dir, not the user repo — see `pre-commit-check.sh`).
- **Self-reference (LEARNINGS #7).** Verify each gate ONLY via its hermetic fixture runner, never by self-scanning a real spec/plan/LEARNINGS.
- **Test hermeticity (LEARNINGS #12).** Every runner builds its own temp git repo with `git init -q`, local `user.email`/`user.name`, and `commit.gpgsign=false`; uses `git -C`; cleans up with a `trap`. No dependence on the caller's cwd or global git config.
- **`deny` reason names the staged file** (commit-time context) and notes the escape line accepts markdown decoration.
- **Sourcing idiom.** `source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"`. Verified: `perf-wrap.sh` runs `bash "$HOOKS_DIR/<gate>.sh"`, so `${BASH_SOURCE[0]}` is the gate's absolute path.
- **Version:** `plugin.json` → `0.17.0`.

---

### Task 1: Shared gate library + test harness

**Files:**
- Create: `hooks/lib/gate-common.sh`
- Create: `meta/superpowers/validation/lib/gate-test-common.zsh`
- Test: `meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh`

**Interfaces:**
- Produces (sourced by every gate): globals `GATE_PAYLOAD`, `GATE_TOOL`, `GATE_CWD`, `GATE_COMMAND`; functions `gate_load`, `gate_is_commit`, `gate_field <key>`, `gate_command`, `gate_staged_files`, `gate_staged_blob <path>`, `gate_is_scratch <path>`, `gate_has_escape <text> <Label>`, `json_escape <str>`, `deny <reason>`, `gate_scan_staged <in_scope_fn> <check_fn>`.
- Produces (sourced by every runner): `gt_make_repo` (echoes a fresh temp repo path), `gt_stage <repo> <relpath> <content>`, `gt_commit_payload <repo> <command>` (echoes JSON), `gt_run <gate-name> <payload>` (echoes gate stdout), `gt_is_deny <gate-output>` / `gt_is_allow <gate-output>`, `gt_cleanup <repo>`.

- [ ] **Step 1: Write the failing lib self-test**

Create `meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# Hermetic self-test for hooks/lib/gate-common.sh.
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
HOOKS="${HERE:h:h}/hooks"   # meta/superpowers/validation -> repo root -> hooks

pass=0; fail=0
check() {  # <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++))
  else print -r -- "FAIL - $1 (expected [$2] got [$3])"; ((fail++)); fi
}

# gate_is_scratch
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_is_scratch ".x.md" && echo yes || echo no')"
check "dot-prefixed is scratch" "yes" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_is_scratch "a/b/plan.md" && echo yes || echo no')"
check "normal not scratch" "no" "$out"

# gate_has_escape: bare and decorated both match; absent does not
esc_bare='Proven-gate: N/A — reason here'
esc_dec='> **Proven-gate:** N/A — reason here'
none='no hatch on this line'
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_has_escape "'"$esc_bare"'" "Proven-gate" && echo yes || echo no')"
check "bare escape matches" "yes" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_has_escape "'"$esc_dec"'" "Proven-gate" && echo yes || echo no')"
check "decorated escape matches" "yes" "$out"
out="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; gate_has_escape "'"$none"'" "Proven-gate" && echo yes || echo no')"
check "no escape does not match" "no" "$out"

# staged enumeration + blob read against a real temp repo
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/x.md" $'line one\nRealword\n'
files="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_CWD="'"$repo"'"; gate_staged_files')"
check "staged file listed" "meta/plans/x.md" "$files"
blob="$(bash -c 'source "'"$HOOKS"'/lib/gate-common.sh"; GATE_CWD="'"$repo"'"; gate_staged_blob "meta/plans/x.md"' | head -1)"
check "staged blob read" "line one" "$blob"
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `zsh meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh`
Expected: FAIL — `gate-common.sh` and `gate-test-common.zsh` do not exist yet (source errors / non-zero exit).

- [ ] **Step 3: Write the test harness `gate-test-common.zsh`**

```zsh
#!/usr/bin/env zsh
# Shared hermetic harness for the gate runners.
gt_make_repo() {
  local d; d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email "t@t.t"
  git -C "$d" config user.name "t"
  git -C "$d" config commit.gpgsign false
  print -r -- "$d"
}
gt_stage() {  # <repo> <relpath> <content>
  local repo="$1" rel="$2" content="$3"
  mkdir -p "$repo/${rel:h}"
  print -rn -- "$content" > "$repo/$rel"
  git -C "$repo" add "$rel"
}
gt_commit_payload() {  # <repo> <command> ; command defaults to a plain commit
  local repo="$1" cmd="${2:-git commit -m msg}"
  # JSON with cwd top-level and command nested; escape backslashes and quotes.
  local esc="${cmd//\\/\\\\}"; esc="${esc//\"/\\\"}"
  print -r -- "{\"tool_name\":\"Bash\",\"cwd\":\"$repo\",\"tool_input\":{\"command\":\"$esc\"}}"
}
gt_run() {  # <gate-name> <payload>  -> gate stdout
  local gate="$1" payload="$2"
  local hooks="${0:A:h:h:h}/hooks"   # runner is in meta/superpowers/validation
  print -rn -- "$payload" | bash "$hooks/$gate"
}
gt_is_deny() { print -rn -- "$1" | grep -q '"permissionDecision":"deny"'; }
gt_is_allow() { ! gt_is_deny "$1"; }   # allow == not a deny (silent or allow JSON)
gt_cleanup() { [[ -n "${1:-}" && -d "$1" ]] && rm -rf "$1"; }
```

Note: `gt_run` invokes the gate script directly (not through `perf-wrap.sh`) so a test never writes to `performance.log`. The block/allow semantics are identical; perf-wrap only wraps timing.

- [ ] **Step 4: Write `gate-common.sh`**

```bash
#!/usr/bin/env bash
# hooks/lib/gate-common.sh — shared helpers for the commit-time content gates.
# SOURCED, never executed. Callers run `set -euo pipefail`; every function here
# is written to be safe under it (if-form, never `cmd && var=1`).

# --- payload parsing -------------------------------------------------------
gate_field() {  # <json-key> -> scalar string value from $GATE_PAYLOAD
  printf '%s' "${GATE_PAYLOAD:-}" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' \
    || true
}

gate_command() {  # decoded git command string from $GATE_PAYLOAD
  printf '%s' "${GATE_PAYLOAD:-}" \
    | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(.*)/\1/p' \
    | head -1 \
    | sed -E 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g; s/\\\\/\\/g' \
    || true
}

gate_load() {  # read stdin once; populate globals
  GATE_PAYLOAD="$(cat || true)"
  GATE_TOOL="$(gate_field tool_name)"
  GATE_CWD="$(gate_field cwd)"
  GATE_COMMAND="$(gate_command)"
}

gate_is_commit() {  # true iff a Bash `git commit` invocation
  [ "${GATE_TOOL:-}" = "Bash" ] || return 1
  printf '%s' "${GATE_COMMAND:-}" | grep -Eq 'git[[:space:]]+commit'
}

# --- staged content --------------------------------------------------------
gate_staged_files() {  # relative paths staged in the index
  [ -n "${GATE_CWD:-}" ] || return 0
  [ -d "$GATE_CWD" ] || return 0
  git -C "$GATE_CWD" diff --cached --name-only 2>/dev/null || true
}

gate_staged_blob() {  # <relpath> -> staged (index) content of the file
  git -C "${GATE_CWD:-}" show ":$1" 2>/dev/null || true
}

gate_is_scratch() {  # <relpath> -> true if basename is dot-prefixed
  case "${1##*/}" in
    .*) return 0 ;;
    *)  return 1 ;;
  esac
}

# --- escape hatch (decoration-tolerant) ------------------------------------
gate_has_escape() {  # <text> <Label> -> true if an escape line is present
  # Strip markdown emphasis/code marks so `**Label:**` and `` `Label:` ``
  # still match. Leading blockquote `>`/heading `#` are harmless: the match
  # is not anchored to line start.
  printf '%s' "$1" \
    | sed -E 's/[`*]//g' \
    | grep -Eiq "$2:[[:space:]]*N/A[[:space:]]*(—|--)[[:space:]]*[^[:space:]]"
}

# --- output contract -------------------------------------------------------
json_escape() {
  printf '%s' "$1" | sed -E 's/\\/\\\\/g; s/"/\\"/g' | tr '\000-\037' ' '
}

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(json_escape "$1")"
  exit 0
}

# --- driver ----------------------------------------------------------------
# Caller defines two functions and passes their names:
#   <in_scope_fn> <relpath>            -> return 0 if this gate should scan it
#   <check_fn>    <content> <relpath>  -> inspect; call deny (exits) on violation
gate_scan_staged() {
  local in_scope="$1" check="$2" f content
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    "$in_scope" "$f" || continue
    if gate_is_scratch "$f"; then continue; fi
    content="$(gate_staged_blob "$f")"
    [ -z "$content" ] && continue
    "$check" "$content" "$f"
  done <<EOF
$(gate_staged_files)
EOF
}
```

- [ ] **Step 5: Run the lib self-test to verify it passes**

Run: `zsh meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh`
Expected: PASS — `pass=8 fail=0`.

- [ ] **Step 6: shellcheck the lib**

Run: `shellcheck hooks/lib/gate-common.sh`
Expected: no findings. (Sourced-file globals like `GATE_PAYLOAD` are assigned in `gate_load`; if shellcheck warns SC2154 on read-before-assign in a helper, add `# shellcheck disable=SC2154` with a one-line reason, or reference `${GATE_PAYLOAD:-}`.)

- [ ] **Step 7: Commit**

```bash
git add hooks/lib/gate-common.sh meta/superpowers/validation/lib/gate-test-common.zsh meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh
git commit -m "feat: gate-common.sh shared lib + hermetic test harness for commit-time gates"
```

---

### Task 2: proven-gate → commit-time (reference implementation)

**Files:**
- Modify (rewrite): `hooks/proven-gate.sh`
- Modify (rewrite): `meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh`

**Interfaces:**
- Consumes: all of `gate-common.sh` (Task 1) and the harness.

- [ ] **Step 1: Rewrite the proven-gate runner for the commit path**

Replace the file with commit-time cases:

```zsh
#!/usr/bin/env zsh
set -uo pipefail
HERE="${0:A:h}"
source "$HERE/lib/gate-test-common.zsh"
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then print -r -- "ok   - $1"; ((pass++)); else print -r -- "FAIL - $1 (want $2 got $3)"; ((fail++)); fi }
verdict() { gt_is_deny "$1" && print deny || print allow; }

# 1. staged plan with a bare "verified" claim, no fields -> deny
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'We verified the pipeline works end to end.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "claim without fields -> deny" "deny" "$(verdict "$out")"
gt_cleanup "$repo"

# 2. same claim WITH Real path + Stubbed -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'Verified.\nReal path: prod runner ran.\nStubbed: nothing.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "claim with both fields -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 3. decorated escape line -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'Verified by reading source.\n> **Proven-gate:** N/A — reads only, nothing run.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "decorated escape -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 4. dot-prefixed scratch file with a violation -> allow (skipped)
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/.grounding.md" $'We verified it.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "scratch file skipped -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 5. no matching staged file (wrong dir) -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "src/x.md" $'We verified it.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "out-of-scope path -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 6. non-git-commit Bash command -> allow
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'We verified it.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo" "git status")")"
check "non-commit command -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

# 7. word-boundary: "unproven" alone does not trigger
repo="$(gt_make_repo)"
gt_stage "$repo" "meta/plans/p.md" $'This remains unproven for now.\n'
out="$(gt_run proven-gate.sh "$(gt_commit_payload "$repo")")"
check "unproven not a claim -> allow" "allow" "$(verdict "$out")"
gt_cleanup "$repo"

print -r -- "---"; print -r -- "pass=$pass fail=$fail"; [[ $fail -eq 0 ]]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `zsh meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh`
Expected: FAIL — `proven-gate.sh` still reads a Write payload; against a Bash-commit payload it early-exits (allow) on every case, so case 1 fails (`want deny got allow`).

- [ ] **Step 3: Rewrite `hooks/proven-gate.sh`**

```bash
#!/usr/bin/env bash
# proven-gate.sh — commit-time content gate (session-continuity plugin).
#
# Fires before Bash(git commit *). For each staged */specs/*.md or */plans/*.md
# file (skipping dot-prefixed scratch), BLOCKS the commit when the file makes a
# "proven"/"verified"/"spike conclusive" claim (word boundaries) without BOTH:
#   Real path: <which production code path actually ran>
#   Stubbed:   <what stood in — or "nothing">
# Escape hatch (decoration tolerant): a line `Proven-gate: N/A — <reason>`.
# See meta/superpowers/specs/2026-08-27-commit-time-content-gates-design.md.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

gate_in_scope() {
  case "$1" in */specs/*|*/plans/*) : ;; *) return 1 ;; esac
  case "${1##*/}" in *.md) return 0 ;; *) return 1 ;; esac
}

gate_check() {
  local content="$1" path="$2"
  if gate_has_escape "$content" "Proven-gate"; then return 0; fi
  local has_claim=0
  if printf '%s' "$content" | grep -Eiqw 'proven|verified'; then has_claim=1; fi
  if printf '%s' "$content" | grep -Eiq 'spike[[:space:]]+conclusive'; then has_claim=1; fi
  [ "$has_claim" -eq 0 ] && return 0
  local has_real=0 has_stub=0
  if printf '%s' "$content" | grep -Eiq 'Real path:[[:space:]]*[^[:space:]]'; then has_real=1; fi
  if printf '%s' "$content" | grep -Eiq 'Stubbed:[[:space:]]*[^[:space:]]'; then has_stub=1; fi
  if [ "$has_real" -eq 0 ] || [ "$has_stub" -eq 0 ]; then
    deny "In staged file $path: makes a 'proven/verified/spike conclusive' claim but does not name what was tested. Add both fields next to the claim — 'Real path: <which production code path ran>' and 'Stubbed: <what stood in, or \"nothing\">'. If the stubbed thing is the feature under test, the claim is not proven. Or add a line (markdown decoration is fine): Proven-gate: N/A — <reason>."
  fi
}

gate_load
gate_is_commit || exit 0
gate_scan_staged gate_in_scope gate_check
exit 0
```

- [ ] **Step 4: Run the runner to verify it passes**

Run: `zsh meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh`
Expected: PASS — `pass=7 fail=0`.

- [ ] **Step 5: shellcheck**

Run: `shellcheck hooks/proven-gate.sh`
Expected: no findings. (`gate_in_scope`/`gate_check` are referenced by name string in `gate_scan_staged`; if SC2317 "unreachable" appears, add `# shellcheck disable=SC2317` above each with the reason "called indirectly by gate_scan_staged".)

- [ ] **Step 6: Commit**

```bash
git add hooks/proven-gate.sh meta/superpowers/validation/2026-06-17-proven-gate-smoke.zsh
git commit -m "feat: proven-gate enforces at commit time, not on write"
```

---

### Task 3: smoke-gate → commit-time

**Files:**
- Modify (rewrite): `hooks/smoke-gate.sh`
- Modify (rewrite): `meta/superpowers/validation/2026-08-06-smoke-gate-smoke.zsh`

**Interfaces:** Consumes `gate-common.sh` + harness.

- [ ] **Step 1: Rewrite the runner (commit path)**

Key cases (build each as: `gt_make_repo` → `gt_stage <repo> meta/plans/p.md <content>` → `gt_run smoke-gate.sh "$(gt_commit_payload $repo)"` → assert). Use `verdict`/`check` helpers from Task 2's runner:

| # | staged content | expect |
|---|---|---|
| 1 | `binary build step; deploy the engine.` (no smoke) | deny |
| 2 | `Run the smoke test after building the binary.` | allow |
| 3 | `smoke test is optional for the binary.` | deny (weak-smoke adjacent) |
| 4 | `smoke is MANDATORY — never deferred. builds a binary.` | allow (explicit MANDATORY) |
| 5 | `> **Smoke:** N/A — pure docs change.` + `binary` | allow (decorated escape) |
| 6 | `.scratch.md` with content of case 1 | allow (scratch skip) |
| 7 | plan with no binary/engine/smoke words | allow |

- [ ] **Step 2: Run to verify it fails**

Run: `zsh meta/superpowers/validation/2026-08-06-smoke-gate-smoke.zsh`
Expected: FAIL (gate still on Write payload → all allow; case 1/3 fail).

- [ ] **Step 3: Rewrite `hooks/smoke-gate.sh`**

```bash
#!/usr/bin/env bash
# smoke-gate.sh — commit-time content gate (session-continuity plugin).
# Fires before Bash(git commit *). For each staged plan file (*/plans/*.md or a
# *plan*.md basename), BLOCKS a binary/engine-touching plan that lacks a
# MANDATORY smoke task (weak-smoke or no-smoke). Escape: `Smoke: N/A — <reason>`.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

gate_in_scope() {
  case "${1##*/}" in *.md) : ;; *) return 1 ;; esac
  case "$1" in */plans/*) return 0 ;; esac
  case "${1##*/}" in *plan*.md) return 0 ;; *) return 1 ;; esac
}

gate_check() {
  local content="$1" path="$2" mentions_smoke offender
  if gate_has_escape "$content" "Smoke"; then return 0; fi
  # Explicit MANDATORY pass (before weak-smoke).
  if printf '%s' "$content" | grep -Eiq 'smoke.*\bMANDATORY\b|\bMANDATORY\b.*smoke'; then return 0; fi
  mentions_smoke="$(printf '%s' "$content" | grep -ci 'smoke' || true)"
  local weak='optional|deferred|after.?merge|nice.?to.?have'
  if [ "${mentions_smoke:-0}" -gt 0 ]; then
    offender="$(printf '%s' "$content" | grep -Ei "smoke[^.]{0,20}($weak)|($weak)[^.]{0,20}smoke" | head -1 || true)"
    if [ -n "$offender" ]; then
      deny "In staged file $path: smoke task looks optional/deferred (matched: \"${offender}\"). If incidental prose, reword; if the smoke task is mandatory add the word MANDATORY on a smoke line, or add: Smoke: N/A — <reason> (markdown decoration is fine) if this plan touches no binary/engine."
    fi
    return 0
  fi
  if printf '%s' "$content" | grep -Eiq 'binary|engine|container|daemon|--compile|bun build'; then
    deny "In staged file $path: mentions binary/engine/container work but has no smoke task. Add a MANDATORY smoke task, or add: Smoke: N/A — <reason> (markdown decoration is fine) if it genuinely touches no binary/engine."
  fi
}

gate_load
gate_is_commit || exit 0
gate_scan_staged gate_in_scope gate_check
exit 0
```

- [ ] **Step 4: Run the runner — expect PASS (`fail=0`).**

Run: `zsh meta/superpowers/validation/2026-08-06-smoke-gate-smoke.zsh`

- [ ] **Step 5: shellcheck** — `shellcheck hooks/smoke-gate.sh` (no findings).

- [ ] **Step 6: Commit**

```bash
git add hooks/smoke-gate.sh meta/superpowers/validation/2026-08-06-smoke-gate-smoke.zsh
git commit -m "feat: smoke-gate enforces at commit time, not on write"
```

---

### Task 4: evidence-gate → commit-time

**Files:**
- Modify (rewrite): `hooks/evidence-gate.sh`
- Modify (rewrite): `meta/superpowers/validation/2026-07-01-evidence-gate-smoke.zsh`

**Interfaces:** Consumes `gate-common.sh` + harness.

- [ ] **Step 1: Rewrite runner (commit path).** Cases (staged to `meta/specs/s.md`):

| # | content | expect |
|---|---|---|
| 1 | `smoke SUT teardown on failure` (no preserve) | deny (A) |
| 2 | `smoke: surface the diagnostic into the log before any teardown` | allow |
| 3 | `smoke poll loop with a timeout` (no dual-signal) | deny (B) |
| 4 | `smoke poll_until <success> <failure> <timeout>` | allow |
| 5 | spec with no `smoke` word at all (has teardown) | allow (out of section scope) |
| 6 | `> **Evidence-gate:** N/A — reason` + teardown+smoke | allow (decorated escape) |
| 7 | `.scratch.md` with case 1 content | allow (scratch skip) |

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Rewrite `hooks/evidence-gate.sh`**

```bash
#!/usr/bin/env bash
# evidence-gate.sh — commit-time content gate (session-continuity plugin).
# Fires before Bash(git commit *). For each staged */specs/*.md or */plans/*.md
# that discusses a smoke section, BLOCKS (A) teardown without preserve-before-
# teardown, or (B) a poll/wait loop without a dual (success+failure) signal.
# Escape: `Evidence-gate: N/A — <reason>`.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

gate_in_scope() {
  case "$1" in */specs/*|*/plans/*) : ;; *) return 1 ;; esac
  case "${1##*/}" in *.md) return 0 ;; *) return 1 ;; esac
}

gate_check() {
  local content="$1" path="$2"
  # Only relevant when the file discusses smoke.
  printf '%s' "$content" | grep -Eiq 'smoke' || return 0
  if gate_has_escape "$content" "Evidence-gate"; then return 0; fi
  if printf '%s' "$content" | grep -Eiq 'teardown|tear down|cleanup|clean up'; then
    if ! printf '%s' "$content" | grep -Eiq 'before teardown|before tear down|keep_on_fail|preserve[^.]*(diagnostic|evidence|log)|diagnostic[^.]*before|on failure[^.]*(preserve|keep|dump|surface)'; then
      deny "In staged file $path: the smoke section mentions teardown/cleanup but never states the failure diagnostic is captured BEFORE teardown. Teardown-on-fail destroys evidence needed to diagnose without guessing. Add a preserve-before-teardown line (e.g. 'surface the diagnostic into the log before any teardown' or SMOKE_KEEP_ON_FAIL), or add: Evidence-gate: N/A — <reason> (decoration fine)."
    fi
  fi
  if printf '%s' "$content" | grep -Eiq 'poll|wait[_-]?for|readiness check|timeout loop'; then
    if ! printf '%s' "$content" | grep -Eiq 'poll_until|both[^.]*(success|pass)[^.]*(failure|fail)|success and failure|dual.signal|failure signal'; then
      deny "In staged file $path: the smoke section mentions a poll/wait loop but never states it watches BOTH a success AND a failure signal. A success-only poll burns the full timeout on every failure and can't tell 'slow' from 'broken'. Name the dual-signal poll (e.g. 'poll_until <success> <failure> <timeout>'), or add: Evidence-gate: N/A — <reason> (decoration fine)."
    fi
  fi
}

gate_load
gate_is_commit || exit 0
gate_scan_staged gate_in_scope gate_check
exit 0
```

- [ ] **Step 4: Run runner — expect PASS.**
- [ ] **Step 5: shellcheck** `hooks/evidence-gate.sh`.
- [ ] **Step 6: Commit**

```bash
git add hooks/evidence-gate.sh meta/superpowers/validation/2026-07-01-evidence-gate-smoke.zsh
git commit -m "feat: evidence-gate enforces at commit time, not on write"
```

---

### Task 5: backend-parity-gate → commit-time

**Files:**
- Modify (rewrite): `hooks/backend-parity-gate.sh`
- Modify (rewrite): `meta/superpowers/validation/2026-07-01-backend-parity-gate-smoke.zsh`

**Interfaces:** Consumes `gate-common.sh` + harness.

- [ ] **Step 1: Rewrite runner (commit path).** Cases (staged to `meta/plans/p.md`):

| # | content | expect |
|---|---|---|
| 1 | `Smoke on the docker backend only.` | deny (<2 named) |
| 2 | `Smoke on docker and the apple container backend.` | allow (2 named) |
| 3 | plan with no `backend` word (names only docker) | allow (not framed multi-backend) |
| 4 | `> **Backend-parity:** N/A — single backend` + `backend docker` | allow (decorated escape) |
| 5 | `.scratch.md` with case 1 content | allow (scratch skip) |

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Rewrite `hooks/backend-parity-gate.sh`**

```bash
#!/usr/bin/env bash
# backend-parity-gate.sh — commit-time content gate (session-continuity plugin).
# Fires before Bash(git commit *). For each staged plan file that frames smoke as
# multi-backend (mentions "backend(s)"), BLOCKS when fewer than two concrete
# backends are named. Escape: `Backend-parity: N/A — <reason>`.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

gate_in_scope() {
  case "${1##*/}" in *.md) : ;; *) return 1 ;; esac
  case "$1" in */plans/*) return 0 ;; esac
  case "${1##*/}" in *plan*.md) return 0 ;; *) return 1 ;; esac
}

gate_check() {
  local content="$1" path="$2" n hit_count=0
  printf '%s' "$content" | grep -Eiq 'backends?\b' || return 0
  if gate_has_escape "$content" "Backend-parity"; then return 0; fi
  for n in docker apple podman containerd colima kata lima orbstack; do
    if printf '%s' "$content" | grep -Eiq "\\b${n}\\b"; then hit_count=$((hit_count + 1)); fi
  done
  if [ "$hit_count" -lt 2 ]; then
    deny "In staged file $path: mentions 'backend(s)' but names fewer than two concrete backends. A smoke runner proven on only one backend has an unverified half — pair every backend-specific section with the other (e.g. Docker + Apple container). Name the second backend, or add: Backend-parity: N/A — <reason> (decoration fine) if there genuinely is only one."
  fi
}

gate_load
gate_is_commit || exit 0
gate_scan_staged gate_in_scope gate_check
exit 0
```

- [ ] **Step 4: Run runner — expect PASS.**
- [ ] **Step 5: shellcheck** `hooks/backend-parity-gate.sh`.
- [ ] **Step 6: Commit**

```bash
git add hooks/backend-parity-gate.sh meta/superpowers/validation/2026-07-01-backend-parity-gate-smoke.zsh
git commit -m "feat: backend-parity-gate enforces at commit time, not on write"
```

---

### Task 6: occurrence-gate → commit-time

**Files:**
- Modify (rewrite): `hooks/occurrence-gate.sh`
- Modify (rewrite): `meta/superpowers/validation/2026-06-17-occurrence-gate-smoke.zsh`

**Interfaces:** Consumes `gate-common.sh` + harness.

- [ ] **Step 1: Rewrite runner (commit path).** Scope is `LEARNINGS.md` under `.session-continuity/`. Cases (staged to `.session-continuity/LEARNINGS.md`):

| # | content | expect |
|---|---|---|
| 1 | `Occurrence count: 2 of 2` (no Invariant) | deny |
| 2 | `Occurrence count: 3 of 3` + `Invariant: reconciler enforces X` | allow |
| 3 | `Occurrence count: 1 of 2` (N<2) | allow |
| 4 | `> **Occurrence-gate:** N/A — quoting` + count 2 of 2 | allow (decorated escape) |
| 5 | same violation staged as `.session-continuity/LEARNINGS.md` but basename `NOTES.md` | allow (out of scope) |
| 6 | violation staged as top-level `LEARNINGS.md` (not under .session-continuity) | allow (out of scope) |

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Rewrite `hooks/occurrence-gate.sh`**

```bash
#!/usr/bin/env bash
# occurrence-gate.sh — commit-time content gate (session-continuity plugin).
# Fires before Bash(git commit *). For each staged LEARNINGS.md under a
# .session-continuity/ path, BLOCKS an entry that records `Occurrence count: N
# of M` (N>=2) without a non-empty `Invariant:` line. Escape:
# `Occurrence-gate: N/A — <reason>`.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

gate_in_scope() {
  [ "${1##*/}" = "LEARNINGS.md" ] || return 1
  case "$1" in */.session-continuity/*) return 0 ;; *) return 1 ;; esac
}

gate_check() {
  local content="$1" path="$2" n max_n=0 has_inv=0
  if gate_has_escape "$content" "Occurrence-gate"; then return 0; fi
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    if [ "$n" -gt "$max_n" ] 2>/dev/null; then max_n="$n"; fi
  done <<EOF
$(printf '%s' "$content" \
  | grep -oiE 'Occurrence count:[[:space:]]*[0-9]+[[:space:]]+of[[:space:]]+[0-9]+' \
  | grep -oiE '[0-9]+[[:space:]]+of' \
  | grep -oE '^[0-9]+')
EOF
  [ "$max_n" -ge 2 ] || return 0
  if printf '%s' "$content" | grep -Eiq 'Invariant:[[:space:]]*[^[:space:]]'; then has_inv=1; fi
  if [ "$has_inv" -eq 0 ]; then
    deny "In staged file $path: records occurrence #${max_n} of a mistake-class but names no end-state invariant. CLAUDE.md rule 4: a class fixed across 2+ attempts needs an 'Invariant: <what must hold on EVERY path, enforced at the reconciler/entry gate>' line — not another trigger-patch. Add it next to the 'Occurrence count:' line, or add: Occurrence-gate: N/A — <reason> (decoration fine)."
  fi
}

gate_load
gate_is_commit || exit 0
gate_scan_staged gate_in_scope gate_check
exit 0
```

- [ ] **Step 4: Run runner — expect PASS.**
- [ ] **Step 5: shellcheck** `hooks/occurrence-gate.sh`.
- [ ] **Step 6: Commit**

```bash
git add hooks/occurrence-gate.sh meta/superpowers/validation/2026-06-17-occurrence-gate-smoke.zsh
git commit -m "feat: occurrence-gate enforces at commit time, not on write"
```

---

### Task 7: flaky-gate → dual (commit message + staged LEARNINGS)

**Files:**
- Modify (rewrite): `hooks/flaky-gate.sh`
- Modify (rewrite): `meta/superpowers/validation/2026-07-01-flaky-gate-smoke.zsh`

**Interfaces:** Consumes `gate-common.sh` + harness. flaky is the ONE gate that also inspects the commit message text.

- [ ] **Step 1: Rewrite runner.** Two check surfaces: the commit MESSAGE, and staged `LEARNINGS.md` under `.session-continuity/`. Cases:

| # | setup | expect |
|---|---|---|
| 1 | commit `git commit -m "fix flaky test"`, no staged LEARNINGS | deny (message: flaky, no Mechanism) |
| 2 | commit `-m "fix flaky test. Mechanism: shared temp dir race"` | allow |
| 3 | staged LEARNINGS.md `Test is flaky.` (plain commit msg) | deny (file: flaky, no Mechanism) |
| 4 | staged LEARNINGS.md `Test is flaky. Mechanism: DNS timeout in CI` | allow |
| 5 | staged LEARNINGS.md `flaky` + `> **Flaky-gate:** N/A — glossary` | allow (decorated escape) |
| 6 | `.session-continuity/.scratch.md` with `flaky`, plain msg | allow (scratch + wrong basename) |
| 7 | non-commit Bash (`git status`) with `flaky` in it | allow (not a commit) |

For the message check, `gt_commit_payload "$repo" 'git commit -m "fix flaky test"'` puts the message into the command string.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Rewrite `hooks/flaky-gate.sh`**

```bash
#!/usr/bin/env bash
# flaky-gate.sh — commit-time gate (session-continuity plugin). DUAL surface:
# Fires before Bash(git commit *). BLOCKS when a failure is called "flaky"/
# "transient"/"CDN blip|flake" without a `Mechanism:` line, in EITHER the commit
# message OR any staged LEARNINGS.md under .session-continuity/. Escape:
# `Flaky-gate: N/A — <reason>`.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

gate_in_scope() {
  [ "${1##*/}" = "LEARNINGS.md" ] || return 1
  case "$1" in */.session-continuity/*) return 0 ;; *) return 1 ;; esac
}

gate_check() {  # <text> <label-for-reason>
  local text="$1" where="$2"
  [ -z "$text" ] && return 0
  if gate_has_escape "$text" "Flaky-gate"; then return 0; fi
  printf '%s' "$text" | grep -Eiq '\b(flaky|transient)\b|CDN[[:space:]]+(blip|flake)' || return 0
  if ! printf '%s' "$text" | grep -Eiq 'Mechanism:[[:space:]]*[^[:space:]]'; then
    deny "In $where: calls a failure 'flaky'/'transient'/a 'CDN blip' without naming the deterministic cause. CLAUDE.md rule 1: an intermittent failure has a deterministic cause (race, shared/global state, an env/sandbox dependency) — name it or state the precise fail condition. Add a 'Mechanism: <named cause>' line, or add: Flaky-gate: N/A — <reason> (decoration fine)."
  fi
}

gate_check_file() { gate_check "$1" "staged file $2"; }

gate_load
gate_is_commit || exit 0
# (1) commit message text
gate_check "$GATE_COMMAND" "the commit message"
# (2) staged LEARNINGS.md content
gate_scan_staged gate_in_scope gate_check_file
exit 0
```

Note: `gate_scan_staged` calls `<check_fn> <content> <path>`; `gate_check_file` adapts the two-arg call into flaky's `gate_check <text> <where>`. The message check calls `gate_check` directly with a `where` label. Both paths deny via the same helper.

- [ ] **Step 4: Run runner — expect PASS.**
- [ ] **Step 5: shellcheck** `hooks/flaky-gate.sh`.
- [ ] **Step 6: Commit**

```bash
git add hooks/flaky-gate.sh meta/superpowers/validation/2026-07-01-flaky-gate-smoke.zsh
git commit -m "feat: flaky-gate enforces at commit time (message + staged LEARNINGS)"
```

---

### Task 8: Rewire hooks.json + contract runner + full suite

**Files:**
- Modify: `hooks/hooks.json`
- Modify: `meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh`

**Interfaces:** Consumes all rewritten gates.

- [ ] **Step 1: Update the JSON-contract runner for the commit payload shape**

The contract runner asserts each gate's deny output parses as JSON. Update it to drive each of the 5 content gates + flaky through the commit path (temp repo + staged violating fixture + `gt_commit_payload`) and pipe the deny output to `python3 -m json.tool` (fail if any gate with a fixture produces unparseable deny JSON, or has no fixture). Fixtures — one violating case per gate reusing the content from Tasks 2–7. Keep the existing "every hooks/*-gate.sh must have a fixture here" coverage assertion, updated to the commit-path harness.

- [ ] **Step 2: Run it to verify it fails**

Run: `zsh meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh`
Expected: FAIL — gates that still expected Write payloads (before Tasks 2–7 land) or the old harness shape. (If Tasks 2–7 already landed, this may instead fail only on the harness/matcher wiring — adjust until green.)

- [ ] **Step 3: Rewrite `hooks/hooks.json`**

Move the 5 content gates + flaky off `Write|Edit`; add the 5 to the `git commit` block (flaky + pre-commit already there). Result:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh session-start.sh" } ] }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "if": "Bash(git commit *)", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh pre-commit-check.sh" },
          { "type": "command", "if": "Bash(git commit *)", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh flaky-gate.sh" },
          { "type": "command", "if": "Bash(git commit *)", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh proven-gate.sh" },
          { "type": "command", "if": "Bash(git commit *)", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh smoke-gate.sh" },
          { "type": "command", "if": "Bash(git commit *)", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh evidence-gate.sh" },
          { "type": "command", "if": "Bash(git commit *)", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh backend-parity-gate.sh" },
          { "type": "command", "if": "Bash(git commit *)", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh occurrence-gate.sh" },
          { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh learnings-surface.sh" }
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh learnings-surface.sh" }
        ]
      }
    ]
  }
}
```

(`learnings-surface.sh` stays on both — it is a non-blocking `additionalContext` surface, not a block, and is out of scope for this change.)

- [ ] **Step 4: Validate the JSON and run the full suite**

Run:
```bash
python3 -m json.tool hooks/hooks.json >/dev/null && echo "hooks.json OK"
for f in meta/superpowers/validation/2026-*-smoke.zsh; do echo "== $f"; zsh "$f" || echo "SUITE FAIL: $f"; done
```
Expected: `hooks.json OK` and every runner ends `fail=0` with no `SUITE FAIL` line.

- [ ] **Step 5: shellcheck every gate + lib**

Run: `shellcheck hooks/*.sh hooks/lib/gate-common.sh`
Expected: no findings.

- [ ] **Step 6: Commit**

```bash
git add hooks/hooks.json meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh
git commit -m "feat: wire content gates to Bash(git commit *), off Write|Edit"
```

---

### Task 9: Docs, version, LEARNINGS, primer

**Files:**
- Modify: `.claude-plugin/plugin.json` (version → `0.17.0`)
- Modify: `CHANGELOG.md`
- Modify: `skills/session-continuity/SKILL.md`
- Modify: `.session-continuity/LEARNINGS.md`
- Modify: `.session-continuity/SESSION_PRIMER.md`

- [ ] **Step 1: Bump version.** `.claude-plugin/plugin.json` `"version": "0.16.0"` → `"0.17.0"`.

- [ ] **Step 2: CHANGELOG `[0.17.0]` entry.** Under a new dated heading, document: content gates (proven/smoke/evidence/backend-parity/occurrence) + flaky-gate's file check now enforce at `git commit`, not on `Write`/`Edit` — files always save; only commits are gated. New `hooks/lib/gate-common.sh`. Decoration-tolerant escape line (fixes `**Gate:**` rejection). Dot-prefixed scratch files skipped. Accepted limitation: `git commit -a`/pathspec is a permissive miss.

- [ ] **Step 3: SKILL.md.** In the gates section, document: (a) gates fire at commit time, not on save — iterate freely, the gate asks at commit; (b) the escape hatch `<Gate>: N/A — <reason>` and that it now accepts markdown decoration (`> **Gate:** N/A — …` works); (c) the `Real path:`/`Stubbed:` convention proven-gate expects. Grep first for the existing gate docs (`grep -n 'gate' skills/session-continuity/SKILL.md`) and edit in place to match its structure.

- [ ] **Step 4: LEARNINGS entry.** Append one entry: the `git commit -a`/pathspec permissive miss (index-only `diff --cached` at PreToolUse time) and the `${BASH_SOURCE[0]}`-under-`perf-wrap` sourcing resolution. Follow the file's existing entry format and Symptoms index. If it carries `Occurrence count:`, remember the gate now runs at commit — this very file, when staged, must satisfy occurrence-gate (add an `Invariant:` line if N≥2, or `Occurrence-gate: N/A — <reason>`).

- [ ] **Step 5: Refresh the primer.** Add a v0.17.0 Current-state bullet; update the in-flight bullet (the commit-time-gates work is now landed, not staged). Re-run `/session-continuity:primer` refresh mode is the sanctioned path, but a manual edit staged in this commit is fine.

- [ ] **Step 6: Full suite + shellcheck one more time** (guard against a doc edit that touched a fixture):

```bash
python3 -m json.tool hooks/hooks.json >/dev/null && echo OK
for f in meta/superpowers/validation/2026-*-smoke.zsh; do zsh "$f" >/dev/null || echo "FAIL: $f"; done
shellcheck hooks/*.sh hooks/lib/gate-common.sh
```
Expected: `OK`, no `FAIL:` lines, no shellcheck findings.

- [ ] **Step 7: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md skills/session-continuity/SKILL.md .session-continuity/LEARNINGS.md .session-continuity/SESSION_PRIMER.md
git commit -m "docs: v0.17.0 — commit-time content gates (CHANGELOG, SKILL, LEARNINGS, primer)"
```

---

## Self-Review

**1. Spec coverage:**
- Goal invariant (block commit, never block save) → Tasks 2–7 (gates fire on `Bash(git commit *)`, `Write|Edit` branch removed) + Task 8 (hooks.json). ✓
- `gate-common.sh` (all listed helpers) → Task 1. ✓
- Per-gate commit mode + globs → Tasks 2 (proven), 3 (smoke), 4 (evidence), 5 (backend-parity), 6 (occurrence). ✓
- flaky-gate dual (message + staged LEARNINGS, Write|Edit removed) → Task 7. ✓
- hooks.json rewire (remove 6 from Write|Edit, add 5 to commit block, learnings-surface stays) → Task 8. ✓
- False-trigger fixes: decoration-tolerant escape (`gate_has_escape`, Task 1; tested Tasks 2–7), dot-prefixed skip (`gate_is_scratch`, Task 1; tested Tasks 2–6), instruction (SKILL.md, Task 9). ✓
- Testing: runners rewritten to commit path + shared harness (Tasks 1–8), contract runner (Task 8). ✓
- Docs/version: plugin.json 0.17.0, CHANGELOG, SKILL.md, LEARNINGS, primer (Task 9). ✓
- Accepted tradeoffs (permissive `-a` miss; no write-time immediacy) → documented in CHANGELOG + LEARNINGS (Task 9). ✓

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N". Every gate file and the lib are given as complete code; runner cases give concrete fixture strings + expected verdicts. Tasks 3–6 give full gate files (short) and case tables with real content rather than repeating a worked runner — the harness call pattern is fully worked in Task 2 and identical in shape.

**3. Type/name consistency:** `gate_load`, `gate_is_commit`, `gate_scan_staged <in_scope_fn> <check_fn>`, `gate_has_escape <text> <Label>`, `gate_is_scratch`, `gate_staged_files`/`gate_staged_blob`, `deny`, `json_escape` used identically across Tasks 1–7. Every gate defines exactly `gate_in_scope` + `gate_check` (flaky adds `gate_check_file` adapter, and calls `gate_check` with a `where` label — documented in Task 7). Harness names `gt_make_repo`/`gt_stage`/`gt_commit_payload`/`gt_run`/`gt_is_deny`/`gt_is_allow`/`gt_cleanup` consistent across all runners. Globals `GATE_PAYLOAD`/`GATE_TOOL`/`GATE_CWD`/`GATE_COMMAND` consistent.
