# Per-repo performance logging — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Backend-parity: N/A — this plan names `backend-parity-gate.sh` as one
of the 10 existing hooks routed through the timing wrapper; it has no
multi-backend smoke coverage to speak of.

Proven-gate: N/A — this plan names `proven-gate.sh` as one of the 10
existing hooks routed through the timing wrapper, and as the fixture
target in Task 2's regression smoke test. It makes no proven/verified
claim about the performance-logging feature itself — the smoke tests
in Tasks 1-2 are the actual verification, run at implementation time.

**Goal:** Log wall-clock time (and, for slash commands, retry/rerun and
item counts) for every shipped hook invocation and every named
batched-bash-call operation inside `primer.md`/`end-session.md`, to a
per-repo `.session-continuity/performance.log`, so slow operations can
be identified from real data instead of guesswork.

**Architecture:** A shared writer (`hooks/lib/perf-log.sh record`)
appends one JSONL line per event. Two producers feed it: a timing
wrapper (`hooks/lib/perf-wrap.sh`) that `hooks/hooks.json` calls
instead of each shipped hook directly (zero changes to the 10 hook
scripts themselves), and self-reported timer/record calls added
directly inside the specific existing (or newly introduced) single-
Bash-call operations in `primer.md`/`end-session.md` — never around a
whole `## Step N` heading, since those routinely span multiple tool
calls and sometimes a user-wait, which can't share shell state and
shouldn't be counted as operation time. `learning.md` is not
instrumented — it has no batched bash operation to time.

**Tech Stack:** Bash (hooks, matches existing shipped hooks), markdown
slash-command instructions (matches existing `commands/*.md`), zsh
smoke-test runners under `meta/superpowers/validation/` (matches this
repo's existing hermetic-fixture convention — no new test framework
introduced).

**Spec:** `meta/superpowers/specs/2026-08-17-performance-logging-design.md`

## Global Constraints

- Storage path: `.session-continuity/performance.log` in the *target*
  repo (wherever the plugin runs), gitignored via a targeted line
  (not the whole `.session-continuity/` directory).
- No per-write `git check-ignore` subprocess — use the
  `.session-continuity/.gitignore-ensured` marker file described in
  the spec's Storage section.
- A logging failure must never block a hook or error out a command —
  `perf-log.sh` prints to stderr and returns 0 on any failure.
- `perf-wrap.sh` must not alter the wrapped hook's stdin, stdout,
  stderr, or exit code in any way.
- No changes to the 10 existing hook scripts (`backend-parity-gate.sh`,
  `evidence-gate.sh`, `flaky-gate.sh`, `learnings-surface.sh`,
  `occurrence-gate.sh`, `pre-commit-check.sh`, `proven-gate.sh`,
  `session-start.sh`, `smoke-gate.sh`, `version-check.sh`) — only
  `hooks/hooks.json` changes to route through the wrapper.
- `learning.md` is not instrumented — do not add timer code there.
- Never commit automatically — every task stages with `git add`, never
  `git commit`.
- Semantic versioning: bump `.claude-plugin/plugin.json` (`0.14.4` →
  `0.15.0`, minor — new feature, no breaking removal) and add a
  `CHANGELOG.md` `[0.15.0]` entry in the same commit as the feature
  (Task 6).
- Conventional commit messages (`feat:`, `docs:`, `chore:`).
- This repo has no automated test runner — validation is manual zsh
  smoke scripts (`meta/superpowers/validation/*.zsh`) plus a scratch-
  repo manual pass, matching the existing pattern.

---

### Task 1: Shared writer — `hooks/lib/perf-log.sh`

**Files:**
- Create: `hooks/lib/perf-log.sh`
- Test: `meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh`

**Interfaces:**
- Produces: `perf-log.sh record --source=<hook|command> --name=<n> --duration=<seconds> [--exit=<n>] [--step=<slug>] [--retries=<n>] [--items=<n>]` — appends one JSONL line to `<repo-root>/.session-continuity/performance.log`. Silent no-op (exit 0) outside a git repo or on any I/O failure. Every later task (2, 4, 5) calls this exact CLI.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# hooks/lib/perf-log.sh — shared performance-log writer (session-continuity plugin).
#
# Single 'record' subcommand, used by hooks/lib/perf-wrap.sh (hook timing)
# and by the self-reported timers in commands/primer.md and
# commands/end-session.md. See
# meta/superpowers/specs/2026-08-17-performance-logging-design.md.
#
# Usage:
#   perf-log.sh record --source=hook --name=<script> --duration=<seconds> --exit=<code>
#   perf-log.sh record --source=command --name=<slug> --step=<slug> --duration=<seconds> [--retries=<n>] [--items=<n>]
#
# Never fails loud: any error here prints to stderr and returns 0. Logging
# must never be the reason a hook blocks a commit or a command errors out.

set -u

subcommand="${1:-}"
shift || true
if [[ "$subcommand" != "record" ]]; then
  echo "perf-log.sh: unknown subcommand '$subcommand' (only 'record' is supported)" >&2
  exit 0
fi

SOURCE=""; NAME=""; DURATION=""; EXIT=""; STEP=""; RETRIES=""; ITEMS=""
for arg in "$@"; do
  case "$arg" in
    --source=*)   SOURCE="${arg#*=}" ;;
    --name=*)     NAME="${arg#*=}" ;;
    --duration=*) DURATION="${arg#*=}" ;;
    --exit=*)     EXIT="${arg#*=}" ;;
    --step=*)     STEP="${arg#*=}" ;;
    --retries=*)  RETRIES="${arg#*=}" ;;
    --items=*)    ITEMS="${arg#*=}" ;;
    *) : ;;  # ignore unknown flags rather than fail
  esac
done

if [[ -z "$SOURCE" || -z "$NAME" || -z "$DURATION" ]]; then
  echo "perf-log.sh: record requires --source, --name, --duration" >&2
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$REPO_ROOT" ]] && exit 0   # not a git repo: silent no-op

SC_DIR="$REPO_ROOT/.session-continuity"
LOG_FILE="$SC_DIR/performance.log"
MARKER="$SC_DIR/.gitignore-ensured"

mkdir -p "$SC_DIR" 2>/dev/null || { echo "perf-log.sh: could not create $SC_DIR" >&2; exit 0; }

if [[ ! -f "$MARKER" ]]; then
  GITIGNORE="$REPO_ROOT/.gitignore"
  LINE=".session-continuity/performance.log"
  touch "$GITIGNORE" 2>/dev/null
  if ! grep -qxF "$LINE" "$GITIGNORE" 2>/dev/null; then
    printf '%s\n' "$LINE" >> "$GITIGNORE" 2>/dev/null
  fi
  touch "$MARKER" 2>/dev/null
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

json_escape() {
  printf '%s' "$1" | sed -E 's/\\/\\\\/g; s/"/\\"/g' | tr '\000-\037' ' '
}

LINE_JSON="{\"ts\":\"$(json_escape "$TS")\",\"source\":\"$(json_escape "$SOURCE")\",\"name\":\"$(json_escape "$NAME")\",\"duration_s\":$(json_escape "$DURATION")"
[[ -n "$EXIT" ]]    && LINE_JSON+=",\"exit\":$(json_escape "$EXIT")"
[[ -n "$STEP" ]]    && LINE_JSON+=",\"step\":\"$(json_escape "$STEP")\""
[[ -n "$RETRIES" ]] && LINE_JSON+=",\"retries\":$(json_escape "$RETRIES")"
[[ -n "$ITEMS" ]]   && LINE_JSON+=",\"items\":$(json_escape "$ITEMS")"
LINE_JSON+="}"

printf '%s\n' "$LINE_JSON" >> "$LOG_FILE" 2>/dev/null || echo "perf-log.sh: could not write $LOG_FILE" >&2
exit 0
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x hooks/lib/perf-log.sh
```

- [ ] **Step 3: Write the smoke test**

```bash
#!/usr/bin/env zsh
# perf-log.sh writer smoke test. Hermetic: runs against a throwaway temp
# git repo, never touches this repo's own working tree.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
perflog="$repo/hooks/lib/perf-log.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q
git -C "$work" config user.email "test@example.com"
git -C "$work" config user.name "Test"

# 1. Basic record call appends a parseable JSON line with the right fields.
( cd "$work" && bash "$perflog" record --source=hook --name=session-start.sh --duration=0.42 --exit=0 )
line="$(tail -1 "$work/.session-continuity/performance.log" 2>/dev/null)"
if [[ -z "$line" ]]; then
  bad "record: no line written"
else
  if print -r -- "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert d["source"]=="hook"; assert d["name"]=="session-start.sh"; assert d["duration_s"]==0.42; assert d["exit"]==0' 2>/dev/null; then
    ok "record: hook line parses with correct fields"
  else
    bad "record: hook line malformed: $line"
  fi
fi

# 2. Command-source line carries step/retries/items, omits exit.
( cd "$work" && bash "$perflog" record --source=command --name=end-session --step=step-1-outstanding-items-verification --duration=12.5 --items=5 )
line="$(tail -1 "$work/.session-continuity/performance.log" 2>/dev/null)"
if print -r -- "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert d["step"]=="step-1-outstanding-items-verification"; assert d["items"]==5; assert "exit" not in d' 2>/dev/null; then
  ok "record: command line carries step/items, omits exit"
else
  bad "record: command line malformed: $line"
fi

# 3. Gitignore marker: two calls => one gitignore line, one marker file.
gitignore_count="$(grep -c '^\.session-continuity/performance\.log$' "$work/.gitignore" 2>/dev/null || echo 0)"
if [[ "$gitignore_count" == "1" ]]; then
  ok "gitignore: exactly one entry after two record calls"
else
  bad "gitignore: expected 1 entry, got $gitignore_count"
fi
if [[ -f "$work/.session-continuity/.gitignore-ensured" ]]; then
  ok "gitignore: marker file created"
else
  bad "gitignore: marker file missing"
fi

# 4. Outside a git repo: silent no-op, no directory created, exit 0.
nogit="$(mktemp -d)"
( cd "$nogit" && bash "$perflog" record --source=hook --name=x.sh --duration=0.1 --exit=0 )
rc=$?
if [[ "$rc" == "0" && ! -d "$nogit/.session-continuity" ]]; then
  ok "non-git dir: silent no-op, exit 0"
else
  bad "non-git dir: expected no-op+exit0, got rc=$rc dir-exists=$([[ -d "$nogit/.session-continuity" ]] && echo yes || echo no)"
fi
rm -rf "$nogit"

# 5. Missing required flags: exit 0, no crash, no line written.
before="$(wc -l < "$work/.session-continuity/performance.log")"
( cd "$work" && bash "$perflog" record --source=hook ) 2>/dev/null
rc=$?
after="$(wc -l < "$work/.session-continuity/performance.log")"
if [[ "$rc" == "0" && "$before" == "$after" ]]; then
  ok "missing flags: exit 0, no line appended"
else
  bad "missing flags: expected exit0+no-append, got rc=$rc before=$before after=$after"
fi

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 4: Run the smoke test**

```bash
chmod +x meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh
zsh meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh
```

Expected: `Result: 6 passed, 0 failed` (one `ok`/`bad` per numbered check
above, two checks in section 1 count as one — recount against the
script: 6 `ok`/`bad` call sites total).

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/perf-log.sh meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh
git commit -m "feat: add shared perf-log.sh writer for performance logging"
```

---

### Task 2: Hook timing wrapper — `hooks/lib/perf-wrap.sh`

**Files:**
- Create: `hooks/lib/perf-wrap.sh`
- Test: `meta/superpowers/validation/2026-08-17-perf-wrap-smoke.zsh`

**Interfaces:**
- Consumes: `hooks/lib/perf-log.sh record --source=hook --name=<n> --duration=<s> --exit=<n>` (Task 1).
- Produces: `perf-wrap.sh <script-name-or-path> [args...]` — execs the target script with stdin/stdout/stderr untouched, logs via `perf-log.sh`, re-exits with the target's own exit code. Task 3 wires `hooks/hooks.json` to call this instead of each hook directly.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# hooks/lib/perf-wrap.sh — timing wrapper for shipped hooks (session-continuity plugin).
#
# Usage (from hooks/hooks.json): bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh <script-name> [args...]
#
# Execs the real hook by name (resolved under hooks/, or used directly if
# already an executable path — the latter exists so tests can point this at
# a throwaway stub without touching hooks/), times it, logs via
# perf-log.sh, then exits with the real hook's own exit code. Never reads
# or alters stdin/stdout/stderr — the wrapped hook's JSON output and
# block/allow semantics pass through untouched. See
# meta/superpowers/specs/2026-08-17-performance-logging-design.md.

set -u

SCRIPT_NAME="${1:-}"
shift || true

if [[ -z "$SCRIPT_NAME" ]]; then
  echo "perf-wrap.sh: no script name given" >&2
  exit 0
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$HERE")"

if [[ "$SCRIPT_NAME" == */* && -x "$SCRIPT_NAME" ]]; then
  TARGET="$SCRIPT_NAME"
else
  TARGET="$HOOKS_DIR/$SCRIPT_NAME"
fi
NAME_FOR_LOG="$(basename "$SCRIPT_NAME")"

if [[ ! -x "$TARGET" ]]; then
  echo "perf-wrap.sh: $TARGET not found or not executable" >&2
  exit 0
fi

PROBE="$(date +%s.%N 2>/dev/null || true)"
if [[ "$PROBE" == *[0-9].[0-9]* ]]; then
  PRECISE=1
  START="$PROBE"
else
  PRECISE=0
  START="$SECONDS"
fi

bash "$TARGET" "$@"
EXIT_CODE=$?

if [[ "$PRECISE" == "1" ]]; then
  END="$(date +%s.%N)"
  DURATION="$(awk -v a="$START" -v b="$END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "0")"
else
  DURATION="$(( SECONDS - START ))"
fi

bash "$HERE/perf-log.sh" record --source=hook --name="$NAME_FOR_LOG" --duration="$DURATION" --exit="$EXIT_CODE" >/dev/null

exit "$EXIT_CODE"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x hooks/lib/perf-wrap.sh
```

- [ ] **Step 3: Write the smoke test**

```bash
#!/usr/bin/env zsh
# perf-wrap.sh timing-wrapper smoke test. Hermetic: stub scripts in a temp
# dir, plus one real-gate regression check (the plugin's own claim-checking
# gate hook) to prove the wrapper never alters block/allow behavior — the
# one real regression risk in this whole feature.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
wrap="$repo/hooks/lib/perf-wrap.sh"
hooks="$repo/hooks"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q
git -C "$work" config user.email "test@example.com"
git -C "$work" config user.name "Test"

# Stub scripts with known exit codes and known stdout/stderr.
for code in 0 1 2; do
  cat > "$work/stub-$code.sh" <<EOF
#!/usr/bin/env bash
echo "stub-$code-stdout"
echo "stub-$code-stderr" >&2
exit $code
EOF
  chmod +x "$work/stub-$code.sh"
done

for code in 0 1 2; do
  out="$(cd "$work" && bash "$wrap" "$work/stub-$code.sh" 2>/tmp/perf-wrap-smoke-stderr.$$)"
  rc=$?
  err="$(cat /tmp/perf-wrap-smoke-stderr.$$)"; rm -f /tmp/perf-wrap-smoke-stderr.$$
  if [[ "$rc" == "$code" && "$out" == "stub-$code-stdout" && "$err" == "stub-$code-stderr" ]]; then
    ok "stub exit $code: exit code + stdout + stderr pass through unchanged"
  else
    bad "stub exit $code: got rc=$rc out='$out' err='$err'"
  fi
done

log="$work/.session-continuity/performance.log"
lines="$(wc -l < "$log" 2>/dev/null || echo 0)"
if [[ "$lines" == "3" ]]; then
  ok "one log line per wrapped invocation (3 stubs => 3 lines)"
else
  bad "expected 3 log lines, got $lines"
fi
if tail -3 "$log" | python3 -c '
import sys, json
lines = [json.loads(l) for l in sys.stdin]
exits = sorted(l["exit"] for l in lines)
assert exits == [0,1,2], exits
' 2>/dev/null; then
  ok "logged exit codes match [0,1,2]"
else
  bad "logged exit codes do not match [0,1,2]: $(tail -3 "$log")"
fi

# Real-gate regression check: wrapping this plugin's claim-checking gate
# hook must not change its deny decision. Fixture matches the one already
# used in 2026-08-12-hook-json-contract-smoke.zsh.
# Proven-gate: N/A — this smoke test names proven-gate.sh as its fixture
# target, not a verification claim about this plan.
spec_payload() { printf '{"file_path":"/x/specs/s.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }
payload="$(spec_payload 'Approach is proven, option A.')"
gate_hook="proven-gate.sh"
out="$(printf '%s' "$payload" | bash "$wrap" "$gate_hook" 2>/dev/null)"
rc=$?
if [[ "$rc" == "0" ]] && printf '%s' "$out" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert d["hookSpecificOutput"]["permissionDecision"]=="deny"' 2>/dev/null; then
  ok "wrapped $gate_hook still denies the claim (exit 0, JSON deny)"
else
  bad "wrapped $gate_hook regression: rc=$rc out=$out"
fi

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 4: Run the smoke test**

```bash
chmod +x meta/superpowers/validation/2026-08-17-perf-wrap-smoke.zsh
zsh meta/superpowers/validation/2026-08-17-perf-wrap-smoke.zsh
```

Expected: `Result: 6 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/perf-wrap.sh meta/superpowers/validation/2026-08-17-perf-wrap-smoke.zsh
git commit -m "feat: add perf-wrap.sh timing wrapper for shipped hooks"
```

---

### Task 3: Wire `hooks/hooks.json` through the wrapper

**Files:**
- Modify: `hooks/hooks.json`

**Interfaces:**
- Consumes: `hooks/lib/perf-wrap.sh` (Task 2).

- [ ] **Step 1: Replace every hook command with a wrapped call**

Current content:
```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(git commit *)",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/pre-commit-check.sh"
          },
          {
            "type": "command",
            "if": "Bash(git commit *)",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/flaky-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/learnings-surface.sh"
          }
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/learnings-surface.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/smoke-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/proven-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/occurrence-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/evidence-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/flaky-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/backend-parity-gate.sh"
          }
        ]
      }
    ]
  }
}
```

New content — every `"command"` value changes from
`bash ${CLAUDE_PLUGIN_ROOT}/hooks/<script>` to
`bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh <script>` (script
name only, no path prefix — `perf-wrap.sh` resolves it under `hooks/`
itself). `version-check.sh` is not in `hooks.json` today (it runs on a
different trigger — leave it alone; this task only touches what's
already wired here):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh session-start.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(git commit *)",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh pre-commit-check.sh"
          },
          {
            "type": "command",
            "if": "Bash(git commit *)",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh flaky-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh learnings-surface.sh"
          }
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh learnings-surface.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh smoke-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh proven-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh occurrence-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh evidence-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh flaky-gate.sh"
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-wrap.sh backend-parity-gate.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate JSON syntax**

```bash
python3 -c "import json; json.load(open('hooks/hooks.json'))" && echo "valid JSON"
```

Expected: `valid JSON`, no traceback.

- [ ] **Step 3: Re-run the existing hook-JSON-contract smoke test**

This existing test (`meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh`)
calls each gate script directly by path, not through `hooks.json` — it
does not exercise the wrapper. Run it anyway as a regression check that
this task didn't touch the gate scripts themselves:

```bash
zsh meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh
```

Expected: same pass/fail counts as before this task (no change — this
task only edited `hooks.json`, not any `*-gate.sh` file).

- [ ] **Step 4: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: route shipped hooks through perf-wrap.sh for timing"
```

---

### Task 4: Instrument `commands/primer.md`

**Files:**
- Modify: `commands/primer.md`

**Interfaces:**
- Consumes: `hooks/lib/perf-log.sh record` (Task 1).

Six named units, per the spec's Mechanism 2. Each edit below batches
existing (already-described) commands into one Bash call with a timer
wrapped around it — no behavioral change to what gets checked or
derived, only to how it's grouped and timed. Each unit is a
self-contained Bash call — none depends on a variable set by a
sibling unit's call, since shell state doesn't persist across
separate tool calls.

- [ ] **Step 1: `step-1-detect-state`**

Modify `commands/primer.md` — the section starting `## Step 1 — Detect
state` (currently lines 11-19). Old content:

```markdown
## Step 1 — Detect state

Run these checks, in order:

1. Do `.session-continuity/SESSION_PRIMER.md` and `.session-continuity/LEARNINGS.md` exist?
2. If a primer exists, does the `git log --oneline -5` block inside it match the actual output of `git log --oneline -5` for the primary branch? (mtime is intentionally not checked — formatters, save-on-blur, and `cat | tee` all bump mtime without changing content. The log-block diff is the authoritative drift signal.)
3. Does `git diff --cached --name-only` contain any file outside `docs/`, `.session-continuity/`, `README*`, `CHANGELOG*`, `LICENSE*`? (Code is staged and a commit is imminent — the primer will be stale the moment that commit lands.)
4. If a primer exists, does `.session-continuity/PROJECT_CONTEXT.md` also exist?
```

New content:

```markdown
## Step 1 — Detect state

Gather the raw data for every check below in **one Bash call**, timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
[ -f .session-continuity/SESSION_PRIMER.md ] && echo "PRIMER_EXISTS=1" || echo "PRIMER_EXISTS=0"
[ -f .session-continuity/LEARNINGS.md ] && echo "LEARNINGS_EXISTS=1" || echo "LEARNINGS_EXISTS=0"
[ -f .session-continuity/PROJECT_CONTEXT.md ] && echo "PROJECT_CONTEXT_EXISTS=1" || echo "PROJECT_CONTEXT_EXISTS=0"
git log --oneline -5
git diff --cached --name-only
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-1-detect-state --duration="$_PERF_DURATION"
```

Interpret the output:

1. Do `.session-continuity/SESSION_PRIMER.md` and `.session-continuity/LEARNINGS.md` exist? (`PRIMER_EXISTS` / `LEARNINGS_EXISTS` above.)
2. If a primer exists, does the `git log --oneline -5` block inside it match the `git log --oneline -5` output above? (mtime is intentionally not checked — formatters, save-on-blur, and `cat | tee` all bump mtime without changing content. The log-block diff is the authoritative drift signal.)
3. Does the `git diff --cached --name-only` output above contain any file outside `docs/`, `.session-continuity/`, `README*`, `CHANGELOG*`, `LICENSE*`? (Code is staged and a commit is imminent — the primer will be stale the moment that commit lands.)
4. If a primer exists, does `.session-continuity/PROJECT_CONTEXT.md` also exist? (`PROJECT_CONTEXT_EXISTS` above.)
```

- [ ] **Step 2: `step-2-init-derive-placeholders`**

Modify `commands/primer.md` — Step 2's item 5 (currently the
"Fill in placeholders Claude can derive automatically" bullet list).
Old content:

```markdown
5. Fill in placeholders Claude can derive automatically:
   - `{{PROJECT_NAME}}` — from `package.json` `name`, `Cargo.toml` `name`, `pyproject.toml` `name`, or the current directory basename.
   - `{{LATEST_COMMIT_HASH_N}}` / `{{LATEST_COMMIT_SUBJECT_N}}` — from `git log --oneline -5`.
   - `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}` — from `pwd`.
   - `{{TEST_COMMAND_SUMMARY}}` — from `package.json` `scripts.test` if present.
   - `{{REPO_LAYOUT_SUMMARY}}` — best-effort from `find . -maxdepth 2 -not -path './node_modules/*' -not -path './.git/*'` plus a one-line description Claude infers from the file extensions present.
   - `{{MODULES_TABLE}}` — leave as `TBD` unless the project has an obvious package/module manifest to read (`package.json` workspaces, Cargo workspace members, etc.) — don't invent structure that isn't there.
```

New content:

```markdown
5. Fill in placeholders Claude can derive automatically. Gather the raw
   data in **one Bash call**, timed:

   ```bash
   _PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   pwd
   basename "$(pwd)"
   [ -f package.json ] && grep -m1 '"name"' package.json
   [ -f Cargo.toml ] && grep -m1 '^name' Cargo.toml
   [ -f pyproject.toml ] && grep -m1 '^name' pyproject.toml
   git log --oneline -5
   [ -f package.json ] && grep -A1 '"scripts"' package.json | grep '"test"'
   find . -maxdepth 2 -not -path './node_modules/*' -not -path './.git/*'
   _PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   _PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
   bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-2-init-derive-placeholders --duration="$_PERF_DURATION"
   ```

   Derive from that output:
   - `{{PROJECT_NAME}}` — from `package.json` `name`, `Cargo.toml` `name`, `pyproject.toml` `name`, or the current directory basename.
   - `{{LATEST_COMMIT_HASH_N}}` / `{{LATEST_COMMIT_SUBJECT_N}}` — from the `git log --oneline -5` output above.
   - `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}` — from the `pwd` output above.
   - `{{TEST_COMMAND_SUMMARY}}` — from the `scripts.test` grep above, if present.
   - `{{REPO_LAYOUT_SUMMARY}}` — from the `find` output above, plus a one-line description Claude infers from the file extensions present.
   - `{{MODULES_TABLE}}` — leave as `TBD` unless the project has an obvious package/module manifest to read (`package.json` workspaces, Cargo workspace members, etc.) — don't invent structure that isn't there.
```

- [ ] **Step 3: `step-4-git-log-refresh` and `step-4-activity-surface`**

Modify `commands/primer.md` — Step 4, items 2 and 4 (currently
"Regenerate the `git log --oneline -5` block" and "Surface activity
since the last primer refresh"). These are two SEPARATE units, not
merged into one Bash call — item 3 (`step-4-test-count-rerun`, its own
independent Bash call, edited in Step 4 below) sits between them in
the numbered list, and shell state doesn't persist across separate
Bash tool calls. A variable set in item 2's call would be gone by the
time item 4 runs. Each item gets its own self-contained timer instead;
item 4 recomputes `git log -1 --format=%H ...` itself rather than
reusing item 2's output.

Old content (item 2 in full, item 4's first two sentences):

```markdown
2. Regenerate the `git log --oneline -5` block with current output.
```
```markdown
4. **Surface activity since the last primer refresh.** Find the last commit that touched the primer with `git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md`. Run `git log <that-hash>..HEAD --oneline` and present the subject list to the user as candidate prompts:
```

New content — item 2, its own timed Bash call:

```markdown
2. Regenerate the `git log --oneline -5` block. **One Bash call**, timed:

   ```bash
   _PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   git log --oneline -5
   _PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   _PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
   bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-4-git-log-refresh --duration="$_PERF_DURATION"
   ```

   Use the output above to regenerate the primer's block.
```

New content — item 4, its own separate timed Bash call (recomputes the
last-primer-commit hash itself; does not depend on item 2's call):

```markdown
4. **Surface activity since the last primer refresh.** **One Bash
   call**, timed:

   ```bash
   _PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   LAST_PRIMER_COMMIT=$(git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md)
   git log "$LAST_PRIMER_COMMIT"..HEAD --oneline
   _PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   _PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
   bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-4-activity-surface --duration="$_PERF_DURATION"
   ```

   Present the subject list from the `git log` output above to the
   user as candidate prompts:
```

- [ ] **Step 4: `step-4-test-count-rerun`**

Modify `commands/primer.md` — Step 4, item 3 (the test-count
recheck). Old content:

```markdown
3. If the primer has a test-counts section, decide whether to re-run it:
   - **Skip the rerun** if `git diff <last-primer-commit>..HEAD --name-only` (the commit range since the primer was last touched) contains no file outside `.session-continuity/` — no source or test file changed, so the recorded count cannot have drifted. Reuse this diff if already computed elsewhere in this flow; don't recompute it just for this check.
   - **Otherwise, run the test command(s) once.** If that single run's count matches the primer's recorded count, stop there — no drift on this axis, no further runs.
   - **Only if that first run disagrees with the recorded count**, retry up to 2 more times (3 runs total) to rule out flakiness before reporting drift — a single sample can swing a pass/fail count and produce a false drift alarm. Pin to the count seen in ≥2 of the 3 runs. If that pinned count matches the primer's recorded count, the first run was the flake — no drift. If it differs, report drift with the pinned count. If all three runs disagree with each other, surface the spread (`saw 1162 / 1161 / 1162 across 3 runs — using 1162; suite is unstable`) instead of silently picking one.
   
   This keeps the common cases cheap: zero test runs when no relevant file changed, one run when relevant files changed but the count still holds, and the full 3-run majority vote only when there's an actual discrepancy to resolve.
```

New content — same logic, plus the instrumentation instruction (the
test command itself is project-specific, same as the existing
`<last-primer-commit>` placeholder convention already used verbatim
throughout this file, so the timing instruction is prose directing the
agent to bracket whichever 0-3 actual test invocations this logic
runs, inside one Bash call, tracking a real retry count):

```markdown
3. If the primer has a test-counts section, decide whether to re-run it.
   Do this as **one Bash call**, timed, tracking a `RETRIES` count (0
   if skipped or the first run matched, else the number of *extra*
   runs actually executed beyond the first):
   - **Skip the rerun** if `git diff <last-primer-commit>..HEAD --name-only` (the commit range since the primer was last touched) contains no file outside `.session-continuity/` — no source or test file changed, so the recorded count cannot have drifted. Reuse this diff if already computed elsewhere in this flow; don't recompute it just for this check.
   - **Otherwise, run the test command(s) once.** If that single run's count matches the primer's recorded count, stop there — no drift on this axis, no further runs.
   - **Only if that first run disagrees with the recorded count**, retry up to 2 more times (3 runs total) to rule out flakiness before reporting drift — a single sample can swing a pass/fail count and produce a false drift alarm. Pin to the count seen in ≥2 of the 3 runs. If that pinned count matches the primer's recorded count, the first run was the flake — no drift. If it differs, report drift with the pinned count. If all three runs disagree with each other, surface the spread (`saw 1162 / 1161 / 1162 across 3 runs — using 1162; suite is unstable`) instead of silently picking one.

   This keeps the common cases cheap: zero test runs when no relevant file changed, one run when relevant files changed but the count still holds, and the full 3-run majority vote only when there's an actual discrepancy to resolve.

   At the end of this Bash call (whichever branch above ran), call:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-4-test-count-rerun --duration="$_PERF_DURATION" --retries="$RETRIES"
   ```
   using the same `_PERF_START`/`_PERF_END`/`_PERF_DURATION` pattern
   shown in item 2 above, captured around this whole check.
```

- [ ] **Step 5: `step-5-check-mode`**

Modify `commands/primer.md` — the section starting `## Step 5 — Check
mode` (currently lines 110-121). Old content:

```markdown
## Step 5 — Check mode

Report:

```
.session-continuity/SESSION_PRIMER.md: up to date against HEAD (<short-sha>)
Last refresh: <primer mtime>
Outstanding items: <count from primer>
Learnings: <count from .session-continuity/LEARNINGS.md>
```

No changes made. Exit.
```

New content:

```markdown
## Step 5 — Check mode

Gather the report data in **one Bash call**, timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
git rev-parse --short HEAD
stat -f '%Sm' .session-continuity/SESSION_PRIMER.md 2>/dev/null || stat -c '%y' .session-continuity/SESSION_PRIMER.md
grep -c '^[0-9]\+\.' .session-continuity/SESSION_PRIMER.md 2>/dev/null || echo 0
grep -c '^### [0-9]\+\.' .session-continuity/LEARNINGS.md 2>/dev/null || echo 0
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-5-check-mode --duration="$_PERF_DURATION"
```

Report:

```
.session-continuity/SESSION_PRIMER.md: up to date against HEAD (<short-sha>)
Last refresh: <primer mtime>
Outstanding items: <count from primer>
Learnings: <count from .session-continuity/LEARNINGS.md>
```

No changes made. Exit.
```

- [ ] **Step 6: Manual smoke check**

In a scratch git repo with `.claude-plugin` pointed at this checkout
(or via the plugin's normal install path), run
`/session-continuity:primer` in both refresh mode (stage an unrelated
file first) and check mode. After each run:

```bash
tail -5 .session-continuity/performance.log | python3 -c "
import sys, json
for l in sys.stdin:
    d = json.loads(l)
    assert d['source'] == 'command'
    assert d['name'] == 'primer'
    print(d)
"
```

Expected: one line per named unit that actually ran (up to six:
`step-1-detect-state`, `step-2-init-derive-placeholders`,
`step-4-git-log-refresh`, `step-4-test-count-rerun`,
`step-4-activity-surface`, `step-5-check-mode`), each parses, and
`step-4-test-count-rerun` (if the scratch repo has a test-counts
section in its primer) carries a `retries` key.

- [ ] **Step 7: Commit**

```bash
git add commands/primer.md
git commit -m "feat: instrument primer.md's batched bash operations for perf logging"
```

---

### Task 5: Instrument `commands/end-session.md`

**Files:**
- Modify: `commands/end-session.md`

**Interfaces:**
- Consumes: `hooks/lib/perf-log.sh record` (Task 1).

Five named units, per the spec's Mechanism 2.

- [ ] **Step 1: `step-1-fast-path`**

Modify `commands/end-session.md` — the "Fast path" code fence
(currently lines 38-42). Old content:

```markdown
Run all three in **one Bash call** (one round trip, not three):

```bash
git status --porcelain
git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md   # <last-primer-commit>
git rev-parse HEAD
```
```

New content:

```markdown
Run all three in **one Bash call** (one round trip, not three), timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
git status --porcelain
git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md   # <last-primer-commit>
git rev-parse HEAD
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-fast-path --duration="$_PERF_DURATION"
```
```

- [ ] **Step 2: `step-1-outstanding-items-verification`**

Modify `commands/end-session.md` — the "Outstanding-items
verification" section, specifically the "Verify code items" bullet
(currently item 2 under the numbered classify/verify list). Old
content:

```markdown
2. **Verify code items** with a derived `grep`/`glob`/file-exists check via
   Bash. **Batch every item's check into one Bash call** — one script that
   runs all the derived checks back-to-back (e.g. one `grep`/`test -e` per
   item, each echoing a labeled result line) and returns all evidence in a
   single round trip. Never spend one round trip per item. Assign one
   verdict per item from that combined output:
```

New content — same instruction, plus the timing/count wrap (the
derived checks are dynamic per-item, so — same as primer.md's
test-count section — this is prose directing the agent to wrap
whatever script it constructs, tracking a real `ITEMS` count):

```markdown
2. **Verify code items** with a derived `grep`/`glob`/file-exists check via
   Bash. **Batch every item's check into one Bash call** — one script that
   runs all the derived checks back-to-back (e.g. one `grep`/`test -e` per
   item, each echoing a labeled result line) and returns all evidence in a
   single round trip. Never spend one round trip per item. Wrap that one
   Bash call with a timer, and set `ITEMS` to the count of items that went
   through this classify/verify pass (i.e. items NOT already resolved as
   `manual` by the overlap gate above):

   ```bash
   _PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   # ... the derived per-item grep/test -e checks run here ...
   _PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   _PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
   bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-outstanding-items-verification --duration="$_PERF_DURATION" --items="$ITEMS"
   ```

   Assign one verdict per item from that combined output:
```

- [ ] **Step 3: `step-1-drift-test-rerun`**

Modify `commands/end-session.md` — the "Drift check" section's
test-counts paragraph (currently the "If the primer has a test-counts
section..." paragraph under `### Drift check (silent — no user
prompt)`). Old content:

```markdown
If the primer has a test-counts section, decide whether to re-run it (logic
lives in Step 5.3 of `commands/primer.md` — summarized here):

- **Skip the rerun** if the commit list already computed above
  (`<last-primer-commit>..HEAD`) contains no file outside
  `.session-continuity/` — no source or test file changed, so the recorded
  count cannot have drifted.
- **Otherwise, run the test command(s) once.** Matches the primer's
  recorded count → stop, no drift on this axis.
- **Only if that first run disagrees**, retry up to 2 more times (3 total)
  to rule out flakiness. Pin to the count seen in ≥2 of 3 runs — if that
  pinned count matches the primer, the first run was the flake and there's
  no drift; if it still differs, report drift with the pinned count. If all
  three runs disagree with each other, surface the spread (`saw 1162 / 1161
  / 1162 across 3 runs — using 1162; suite is unstable`) instead of
  silently picking one.

Common cases stay cheap: zero test runs when nothing relevant changed, one
run when the count still holds, three only when there's an actual
discrepancy to resolve.
```

New content:

```markdown
If the primer has a test-counts section, decide whether to re-run it (logic
lives in Step 5.3 of `commands/primer.md` — summarized here). Do this as
**one Bash call**, timed, tracking a `RETRIES` count (0 if skipped or the
first run matched, else the number of *extra* runs actually executed
beyond the first):

- **Skip the rerun** if the commit list already computed above
  (`<last-primer-commit>..HEAD`) contains no file outside
  `.session-continuity/` — no source or test file changed, so the recorded
  count cannot have drifted.
- **Otherwise, run the test command(s) once.** Matches the primer's
  recorded count → stop, no drift on this axis.
- **Only if that first run disagrees**, retry up to 2 more times (3 total)
  to rule out flakiness. Pin to the count seen in ≥2 of 3 runs — if that
  pinned count matches the primer, the first run was the flake and there's
  no drift; if it still differs, report drift with the pinned count. If all
  three runs disagree with each other, surface the spread (`saw 1162 / 1161
  / 1162 across 3 runs — using 1162; suite is unstable`) instead of
  silently picking one.

Common cases stay cheap: zero test runs when nothing relevant changed, one
run when the count still holds, three only when there's an actual
discrepancy to resolve.

At the end of this Bash call (whichever branch above ran):
```bash
bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-drift-test-rerun --duration="$_PERF_DURATION" --retries="$RETRIES"
```
using the same `_PERF_START`/`_PERF_END`/`_PERF_DURATION` pattern used
elsewhere in this file, captured around this whole check.
```

- [ ] **Step 4: `step-2-transcript-extraction`**

Modify `commands/end-session.md` — the paragraph right before the
```jq``` fence under `### Combined extraction pass (transcript-file
mode only)`. Old content:

```markdown
Run the `jq` filter below over the transcript file in **one Bash call**
(`jq -n -f <(cat <<'JQEOF' ... JQEOF) "$TRANSCRIPT"` or write it to a temp
file and `jq -n -f`). It has been validated against real Claude Code
transcripts across schema variants (some tool_result lines carry a
`toolUseResult.{stdout,stderr}` object, others carry only a `content`
string prefixed `"Exit code N\n..."` — the filter handles both) and runs in
well under a second even on multi-megabyte, 200+-call transcripts. Use it
as-is; do not re-derive a filter from scratch (a naive rewrite is exactly
what caused a syntax-error retry round trip in past runs — e.g. `"" |
split("\n")[0]` returns `null` in jq, not `""`, and crashes the next
`gsub` in the chain):
```

New content — same paragraph, plus a timing instruction naming exactly
where to place the timer around that one Bash call:

```markdown
Run the `jq` filter below over the transcript file in **one Bash call**
(`jq -n -f <(cat <<'JQEOF' ... JQEOF) "$TRANSCRIPT"` or write it to a temp
file and `jq -n -f`). It has been validated against real Claude Code
transcripts across schema variants (some tool_result lines carry a
`toolUseResult.{stdout,stderr}` object, others carry only a `content`
string prefixed `"Exit code N\n..."` — the filter handles both) and runs in
well under a second even on multi-megabyte, 200+-call transcripts. Use it
as-is; do not re-derive a filter from scratch (a naive rewrite is exactly
what caused a syntax-error retry round trip in past runs — e.g. `"" |
split("\n")[0]` returns `null` in jq, not `""`, and crashes the next
`gsub` in the chain). Time this Bash call: capture
`_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")` immediately
before running `jq`, `_PERF_END` the same way immediately after, compute
`_PERF_DURATION` the same way as elsewhere in this file, and call:
```bash
bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-2-transcript-extraction --duration="$_PERF_DURATION"
```
in the same call, right after `jq` returns.
```

- [ ] **Step 5: `step-3-gather-facts`**

Modify `commands/end-session.md` — the "Gather the facts" code fence
(currently lines 547-554). Old content:

```markdown
Run all six in **one Bash call** (one round trip, not six):

```bash
git diff --cached --name-only          # staged files
git diff --name-only                    # unstaged modifications
git ls-files --others --exclude-standard   # untracked (ignoring .gitignore'd)
git rev-parse --abbrev-ref HEAD         # current branch (or "HEAD" if detached)
git rev-parse --abbrev-ref @{u} 2>/dev/null  # upstream branch, or empty if none
git rev-list --count @{u}..HEAD 2>/dev/null  # unpushed commits, empty if no upstream
```
```

New content:

```markdown
Run all six in **one Bash call** (one round trip, not six), timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
git diff --cached --name-only          # staged files
git diff --name-only                    # unstaged modifications
git ls-files --others --exclude-standard   # untracked (ignoring .gitignore'd)
git rev-parse --abbrev-ref HEAD         # current branch (or "HEAD" if detached)
git rev-parse --abbrev-ref @{u} 2>/dev/null  # upstream branch, or empty if none
git rev-list --count @{u}..HEAD 2>/dev/null  # unpushed commits, empty if no upstream
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "$CLAUDE_PLUGIN_ROOT/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-3-gather-facts --duration="$_PERF_DURATION"
```
```

- [ ] **Step 6: Manual smoke check**

In a scratch repo, run `/session-continuity:end-session` with (a)
nothing changed since last close-out (exercises only the fast path)
and (b) with staged changes and ≥1 outstanding item (exercises the
other four units). After each run:

```bash
tail -10 .session-continuity/performance.log | python3 -c "
import sys, json
for l in sys.stdin:
    d = json.loads(l)
    assert d['source'] == 'command'
    assert d['name'] == 'end-session'
    print(d)
"
```

Expected: run (a) shows only `step-1-fast-path`. Run (b) shows
`step-1-outstanding-items-verification` with an `items` count matching
the scratch primer's actual outstanding-items count, and
`step-1-drift-test-rerun` with a `retries` key if the scratch repo has
a test-counts section.

- [ ] **Step 7: Commit**

```bash
git add commands/end-session.md
git commit -m "feat: instrument end-session.md's batched bash operations for perf logging"
```

---

### Task 6: Version bump, CHANGELOG, README note

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`
- Modify: `README.md`

**Interfaces:**
- None — this task only updates metadata/docs to match Tasks 1-5.

- [ ] **Step 1: Bump the version**

Modify `.claude-plugin/plugin.json`:

```json
  "version": "0.14.4",
```
to:
```json
  "version": "0.15.0",
```

- [ ] **Step 2: Add a CHANGELOG entry**

Modify `CHANGELOG.md` — insert a new section immediately after the
`# Changelog` header and its description line, before the existing
`## [0.14.4]` entry:

```markdown
## [0.15.0] — 2026-08-17

### Added
- **Per-repo performance logging.** Every shipped hook invocation, and
  the heavier batched-bash-call operations inside
  `/session-continuity:primer` and `/session-continuity:end-session`
  (test-count reruns, outstanding-items verification, transcript
  extraction, git-log gathering), now append a timing line to
  `.session-continuity/performance.log` in the repo where the plugin
  runs. Gitignored automatically. No new command surfaces the data yet
  — read it directly with `jq`/`grep`/`bat`. `/session-continuity:learning`
  is not instrumented (no batched bash operation to time). See
  `meta/superpowers/specs/2026-08-17-performance-logging-design.md`.
```

- [ ] **Step 3: Add a README note**

Modify `README.md` — insert a new bullet after the "Weekly version
check" bullet under the "Stay fresh:" heading (currently the section
ending at line 106):

Old content:
```markdown
**Stay fresh:**

- **Weekly version check** makes one unauthenticated GitHub API call per machine per seven days and nudges you inside Claude when a new release ships. Opt out with `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`.
```

New content:
```markdown
**Stay fresh:**

- **Weekly version check** makes one unauthenticated GitHub API call per machine per seven days and nudges you inside Claude when a new release ships. Opt out with `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`.
- **Performance logging** times every hook invocation and the heavier
  operations inside `/session-continuity:primer` and
  `/session-continuity:end-session`, appending JSONL lines to
  `.session-continuity/performance.log` (auto-gitignored). Read it
  directly — `jq`, `grep`, `bat` — there's no summary command yet.
```

- [ ] **Step 4: Verify JSON and read back the diffs**

```bash
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))" && echo "valid JSON"
git diff CHANGELOG.md README.md .claude-plugin/plugin.json
```

Expected: `valid JSON`, and the diff shows exactly the three additions
above.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md README.md
git commit -m "docs: v0.15.0 — per-repo performance logging"
```

---

### Task 7: End-to-end validation log

**Files:**
- Create: `meta/superpowers/validation/2026-08-17-performance-logging.md`

**Interfaces:**
- None — this task records real output from running the finished
  feature, it does not add code.

- [ ] **Step 1: Run the full scratch-repo scenario and record real output**

In a fresh scratch git repo (`mktemp -d && git init`), install this
checkout as the active plugin (or symlink `hooks/`/`commands/` in per
however this repo is normally dev-tested), then:

1. Run `/session-continuity:primer` (init mode) — commit the result.
2. Make an unrelated code change, stage it, run
   `/session-continuity:primer` again (refresh mode).
3. Run `/session-continuity:end-session` with nothing further changed
   (fast path).
4. Add an outstanding item to the primer whose artifact already
   exists in the scratch repo (to exercise an `appears-DONE`
   verdict), stage an unrelated change, run
   `/session-continuity:end-session` again (full Step 1 path).
5. After each of the four runs, capture
   `cat .session-continuity/performance.log` and
   `cat .gitignore` (to confirm the auto-added entry).

- [ ] **Step 2: Write the validation log**

Create `meta/superpowers/validation/2026-08-17-performance-logging.md`
using the existing validation-log format (see
`meta/superpowers/validation/2026-07-30-outstanding-items-verification.md`
for the convention: Branch/Spec/Plan header, one `## Scenario N`
section per run above with Setup/Expected/Actual/Result, `Actual` and
`Result` filled with the REAL captured output from Step 1 — not left
as `_(filled at validation time)_` placeholders, since this task's
whole job is running that validation now).

- [ ] **Step 3: Commit**

```bash
git add meta/superpowers/validation/2026-08-17-performance-logging.md
git commit -m "test: end-to-end validation log for performance logging"
```

---

## Self-Review Notes

- **Spec coverage:** Storage/gitignore-marker (Task 1), Schema fields
  ts/source/name/duration_s/exit/step/retries/items (Tasks 1, 2, 4, 5),
  Mechanism 1 wrapper + hooks.json wiring (Tasks 2-3), Mechanism 2's
  six primer.md units + five end-session.md units (Tasks 4-5),
  Mechanism 3's never-fails-loud behavior (Task 1), Testing plan's four
  bullets (Tasks 1, 2, 4 Step 6, 5 Step 6, 7). `learning.md`
  explicitly NOT touched (Global Constraints, and absent from Tasks
  4-5). Token accounting and a summary/report command are out of
  scope per the spec and are absent here by design.
- **Placeholder scan:** no TBD/TODO. The `<last-primer-commit>`,
  `<test command>`-shaped prose in Task 4 Step 4 and Task 5 Step 3
  mirrors this file's own existing style (verbatim placeholders like
  `<sha>`, `<subject>` already appear throughout `primer.md` and
  `end-session.md` today) — these are the target files' domain
  convention for a value that's genuinely dynamic per-project/per-run,
  not an unresolved planning gap.
- **Cross-call state check:** confirmed no unit's Bash call reads a
  variable set by a *different* unit's Bash call — caught and fixed
  one violation during review (Task 4 Step 3 originally tried to
  share `$LAST_PRIMER_COMMIT` between primer.md items 2 and 4 across
  item 3's intervening separate call; split into two self-contained
  units instead, `step-4-git-log-refresh` and
  `step-4-activity-surface`). The `<last-primer-commit>`-style
  bracket placeholders elsewhere (Task 4 Step 4, Task 5 Step 3) are
  safe by contrast — they're values the agent re-emits literally from
  its own context, not a shell variable expected to survive a
  separate process.
- **Type/name consistency:** every task's `perf-log.sh record` call
  uses the same flag names (`--source`, `--name`, `--duration`,
  `--exit`, `--step`, `--retries`, `--items`) defined in Task 1's
  parser. Every `--step` slug used in Tasks 4-5 matches the exact list
  named in the spec's Mechanism 2 and in this plan's own task
  headings — cross-checked name-by-name while writing Tasks 4-5.
