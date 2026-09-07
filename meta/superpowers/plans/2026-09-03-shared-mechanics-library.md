# Determinism Phase 3 — shared mechanics library — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the four near-identical epoch-subtraction blocks inlined in `commands/end-session.md` into one-line calls to two new `hooks/lib/perf-log.sh` subcommands (`mark`, `since`), and unify the primer-status computation duplicated between `hooks/session-start.sh` and `commands/primer.md`'s check mode into one shared script, so the two can no longer disagree.

**Architecture:** `hooks/lib/perf-log.sh` gains `mark` (write a named timestamp) and `since` (read a named timestamp back, then either log the elapsed duration under a new step, or print the raw epoch for a caller that needs the number itself rather than a duration to log). A new sibling script, `hooks/lib/primer-status.sh`, prints the primer's four status values (`HEAD_SHA`, `PRIMER_MTIME`, `BACKLOG_COUNT`, `LEARNINGS_COUNT`) as `KEY=value` lines; `session-start.sh` and `primer.md`'s check mode both switch to calling it instead of re-deriving the same four values with slightly different shell incantations (which today already disagree on the mtime format string). `since --print-epoch` also closes backlog item `52dc` as a direct side effect: `end-session.md` Step 4's `step-4-agent-active` block currently depends on a `$start_epoch` shell variable set in a *different* Bash tool call, which never survives — the fix re-resolves the epoch fresh, in its own call, using the exact mechanism this plan builds.

**Tech Stack:** Bash, zsh (smoke tests only).

**Spec:** `meta/superpowers/specs/2026-09-02-determinism-program-design.md` (Phase 3 entry)

**Evidence-gate:** N/A — no poll/wait loop appears anywhere in this plan's scripts or smoke tests; every check is a one-shot assertion against a fixed fixture, not a retry/timeout loop.

## Global Constraints

- Every new or modified script prints best-effort output and **always exits 0** — this sits inside rituals (a `SessionStart` hook, an end-session ritual) that must never abort on a logging/status failure.
- Every new script invoked from a *command* markdown file (`primer.md`) carries a `# CONTRACT_VERSION=N` header comment and is called through `require_script` (from `hooks/lib/require-script.sh`), exactly like `count-entries.sh`, `resolve-transcript.sh`, and `agent-active.sh` already are. New scripts start at `CONTRACT_VERSION=1`.
- Scripts invoked only from a *hook* (`hooks/session-start.sh`) are resolved relative to the hook's own path (`$(dirname "$0")/lib/...`), not via `CLAUDE_PLUGIN_ROOT`, and gated by a plain `[ -f ... ]` existence check rather than `require_script` — same convention `session-start.sh` already uses for `count-entries.sh`, so the hook keeps working when a test harness runs it directly.
- `perf-log.sh` itself is **not** `require_script`-gated at any call site, matching its existing convention (`record` is already called unguarded everywhere) — its whole design point is "never blocks the ritual it logs for."
- **`doctor.md` is explicitly out of scope for this plan.** Its row-3 drift verdict is a different function from the four-value status computed here (compares the primer's embedded git-log block against live git log, not a raw sha/mtime/count tuple) — unifying that is deferred to whichever plan implements backlog item #45, after `4a9d` is decided. This plan only needs to make `session-start.sh` and `primer.md`'s check mode agree.
- Do not touch `overlap()`/`candidate-extract.jq` (backlog item #40) or Step 3's checklist assembly (backlog item #41/Phase 4) — out of scope.
- Never invent a status value: every field `primer-status.sh` cannot resolve prints literally `?`, matching the existing best-effort convention throughout this codebase (`count-entries.sh`, `session-start.sh`'s own current fallbacks).

---

## File Structure

| File | Responsibility |
|---|---|
| `hooks/lib/perf-log.sh` (modified) | Adds `mark` and `since` subcommands alongside the existing `record`. Internal `write_record`/`resolve_mark_epoch` helpers factor out the now-shared JSON-append and mark-lookup logic. |
| `hooks/lib/primer-status.sh` (new) | Prints `HEAD_SHA=`, `PRIMER_MTIME=`, `BACKLOG_COUNT=`, `LEARNINGS_COUNT=` for a given directory (default `.`). |
| `hooks/session-start.sh` (modified) | Switches its status computation to `primer-status.sh`; migration-detection branches (`OUTSTANDING_ITEMS.md`, inline-heading) are untouched. |
| `commands/primer.md` (modified) | Step 5 (check mode) switches to one `require_script`-gated call to `primer-status.sh`. |
| `commands/end-session.md` (modified) | The four epoch blocks (Step 1 ×2, Step 2 ×1, Step 4 ×1) collapse to one-line `mark`/`since` calls; Step 4's `step-4-agent-active` block re-resolves its epoch via `since --print-epoch` instead of reading `$start_epoch` across a Bash-call boundary. |
| `meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh` (modified) | New assertions appended for `mark`, `since`, `since --print-epoch`, and the no-mark-found no-op case. Existing 10 assertions untouched. |
| `meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh` (new) | Smoke test for the new script. |
| `meta/superpowers/specs/2026-09-02-determinism-program-design.md` (modified) | Phase 3 paragraph collapses to a pointer at this plan, per the doc's own "Entry format" rule. |
| `.session-continuity/BACKLOG.md` (modified) | Item 11 `[a17f]` text updated to point at this plan instead of "needs a plan." |
| `CHANGELOG.md` (modified) | New version entry. |

---

### Task 1: `perf-log.sh` — add `mark` and `since`

**Files:**
- Modify: `hooks/lib/perf-log.sh`
- Modify: `meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh`

**Interfaces:**
- Produces: `perf-log.sh mark --source=<hook|command> --name=<n> --step=<s>` (writes a `duration_s:0.000` record — a named timestamp, semantically distinct from `record`'s real-duration use even though the JSON shape is identical). `perf-log.sh since --source=<s> --name=<n> --mark-step=<s1> --emit-step=<s2> [--retries=N] [--items=N]` (looks up the most recent record with this `name`+`mark-step`, computes `now - that_ts`, writes a new record under `emit-step`; silently no-ops, writing nothing, if no matching mark is found or its timestamp is unparseable). `perf-log.sh since --print-epoch --name=<n> --mark-step=<s1>` (same lookup, but prints the resolved epoch integer to stdout instead of computing/recording a duration; prints nothing if unresolvable). All three subcommands always exit 0.

- [ ] **Step 1: Write the failing smoke test additions**

Read the existing `meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh` (10 assertions, `pass`/`fail`/`ok`/`bad` already defined, `$work` temp git repo already set up). Using the Edit tool, insert the following **before** the final `print ""` / `print -P "Result: ..."` block (i.e. immediately after assertion 10's closing `fi`):

```zsh
# 11. mark: writes a duration_s:0.000 record under the given step.
( cd "$work" && bash "$perflog" mark --source=command --name=markable --step=step-a-shown )
line="$(tail -1 "$work/.session-continuity/performance.log" 2>/dev/null)"
if print -r -- "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert d["name"]=="markable"; assert d["step"]=="step-a-shown"; assert d["duration_s"]==0.0' 2>/dev/null; then
  ok "mark: writes a step-tagged zero-duration record"
else
  bad "mark: malformed line: $line"
fi

# 12. mark: missing --step is rejected, exit 0, no line written.
before="$(wc -l < "$work/.session-continuity/performance.log")"
( cd "$work" && bash "$perflog" mark --source=command --name=markable ) 2>/dev/null
rc=$?
after="$(wc -l < "$work/.session-continuity/performance.log")"
if [[ "$rc" == "0" && "$before" == "$after" ]]; then
  ok "mark: missing --step rejected, exit 0, no line appended"
else
  bad "mark: expected exit0+no-append, got rc=$rc before=$before after=$after"
fi

# 13. since: resolves the prior mark and records elapsed time under --emit-step.
( cd "$work" && bash "$perflog" mark --source=command --name=sincetest --step=step-shown )
sleep 1
( cd "$work" && bash "$perflog" since --source=command --name=sincetest --mark-step=step-shown --emit-step=step-wait )
line="$(tail -1 "$work/.session-continuity/performance.log" 2>/dev/null)"
if print -r -- "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert d["name"]=="sincetest"; assert d["step"]=="step-wait"; assert d["duration_s"] >= 1.0' 2>/dev/null; then
  ok "since: records elapsed duration under emit-step"
else
  bad "since: malformed/wrong line: $line"
fi

# 14. since: no matching mark found -> silent no-op, exit 0, no line written.
before="$(wc -l < "$work/.session-continuity/performance.log")"
( cd "$work" && bash "$perflog" since --source=command --name=sincetest --mark-step=step-never-marked --emit-step=step-wait ) 2>/dev/null
rc=$?
after="$(wc -l < "$work/.session-continuity/performance.log")"
if [[ "$rc" == "0" && "$before" == "$after" ]]; then
  ok "since: no matching mark -> exit 0, no line appended"
else
  bad "since: expected exit0+no-append, got rc=$rc before=$before after=$after"
fi

# 15. since --print-epoch: prints the mark's epoch, writes nothing to the log.
( cd "$work" && bash "$perflog" mark --source=command --name=epochtest --step=step-shown )
before="$(wc -l < "$work/.session-continuity/performance.log")"
epoch_out="$(cd "$work" && bash "$perflog" since --print-epoch --name=epochtest --mark-step=step-shown)"
after="$(wc -l < "$work/.session-continuity/performance.log")"
if [[ "$epoch_out" =~ ^[0-9]+$ && "$before" == "$after" ]]; then
  ok "since --print-epoch: prints a bare epoch, appends nothing"
else
  bad "since --print-epoch: expected numeric epoch + no-append, got epoch='$epoch_out' before=$before after=$after"
fi

# 16. since --print-epoch: no matching mark -> prints nothing, exit 0.
out="$(cd "$work" && bash "$perflog" since --print-epoch --name=epochtest --mark-step=step-never-marked)"
rc=$?
if [[ "$rc" == "0" && -z "$out" ]]; then
  ok "since --print-epoch: no matching mark -> prints nothing, exit 0"
else
  bad "since --print-epoch: expected empty+exit0, got out='$out' rc=$rc"
fi
```

- [ ] **Step 2: Run it to verify the new assertions fail**

```bash
zsh meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh
```

Expected: the original 10 assertions still pass; assertions 11-16 fail (`mark`/`since` are unknown subcommands today — `perf-log.sh` prints "unknown subcommand" and writes nothing, so every "writes a line" assertion fails and every "no-op" assertion may pass by accident; the point is to see 11/13/15 fail).

- [ ] **Step 3: Rewrite `hooks/lib/perf-log.sh`**

Replace the entire file:

```bash
#!/usr/bin/env bash
# hooks/lib/perf-log.sh — shared performance-log writer (session-continuity plugin).
#
# Three subcommands:
#   record — append one JSON line with a caller-supplied duration.
#   mark   — a record whose duration is always 0.000: a named timestamp for
#            a later 'since' call to read back.
#   since  — read the most recent mark/record for a given name+step, then
#            either (a) record the elapsed time under a new step, or
#            (b) print the resolved epoch on stdout for a caller that needs
#            the raw number (e.g. to hand to another script), not a
#            duration to log.
#
# Used by hooks/lib/perf-wrap.sh (hook timing), by the self-reported timers
# in commands/primer.md and commands/end-session.md, and (mark/since) by
# end-session.md's prompt-wait and ritual-complete/agent-active timing. See
# meta/superpowers/specs/2026-08-17-performance-logging-design.md and the
# Phase 3 entry of meta/superpowers/specs/2026-09-02-determinism-program-design.md.
#
# Usage:
#   perf-log.sh record --source=hook --name=<script> --duration=<seconds> --exit=<code>
#   perf-log.sh record --source=command --name=<slug> --step=<slug> --duration=<seconds> [--retries=<n>] [--items=<n>]
#   perf-log.sh mark --source=<hook|command> --name=<slug> --step=<slug>
#   perf-log.sh since --source=<hook|command> --name=<slug> --mark-step=<slug> --emit-step=<slug> [--retries=<n>] [--items=<n>]
#   perf-log.sh since --print-epoch --name=<slug> --mark-step=<slug>
#
# Never fails loud: any error here prints to stderr and returns 0. Logging
# must never be the reason a hook blocks a commit or a command errors out.

set -u

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

json_escape() {
  printf '%s' "$1" | sed -E 's/\\/\\\\/g; s/"/\\"/g' | tr '\000-\037' ' '
}

# write_record <source> <name> <duration> <exit> <step> <retries> <items>
# Appends one JSON line to .session-continuity/performance.log, ensuring the
# gitignore entries exist first. Silent no-op outside a git repo. Never
# fails loud.
write_record() {
  local SOURCE="$1" NAME="$2" DURATION="$3" EXIT="$4" STEP="$5" RETRIES="$6" ITEMS="$7"

  [[ -z "$REPO_ROOT" ]] && return 0   # not a git repo: silent no-op

  local SC_DIR="$REPO_ROOT/.session-continuity"
  local LOG_FILE="$SC_DIR/performance.log"
  local MARKER="$SC_DIR/.gitignore-ensured"

  mkdir -p "$SC_DIR" 2>/dev/null || { echo "perf-log.sh: could not create $SC_DIR" >&2; return 0; }

  if [[ ! -f "$MARKER" ]]; then
    local GITIGNORE="$REPO_ROOT/.gitignore"
    touch "$GITIGNORE" 2>/dev/null
    local LINE
    for LINE in ".session-continuity/performance.log" ".session-continuity/.gitignore-ensured"; do
      if ! grep -qxF "$LINE" "$GITIGNORE" 2>/dev/null; then
        printf '%s\n' "$LINE" >> "$GITIGNORE" 2>/dev/null
      fi
    done
    touch "$MARKER" 2>/dev/null
  fi

  local TS
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local LINE_JSON
  LINE_JSON="{\"ts\":\"$(json_escape "$TS")\",\"source\":\"$(json_escape "$SOURCE")\",\"name\":\"$(json_escape "$NAME")\",\"duration_s\":$(json_escape "$DURATION")"
  [[ -n "$EXIT" ]]    && LINE_JSON+=",\"exit\":$(json_escape "$EXIT")"
  [[ -n "$STEP" ]]    && LINE_JSON+=",\"step\":\"$(json_escape "$STEP")\""
  [[ -n "$RETRIES" ]] && LINE_JSON+=",\"retries\":$(json_escape "$RETRIES")"
  [[ -n "$ITEMS" ]]   && LINE_JSON+=",\"items\":$(json_escape "$ITEMS")"
  LINE_JSON+="}"

  printf '%s\n' "$LINE_JSON" >> "$LOG_FILE" 2>/dev/null || echo "perf-log.sh: could not write $LOG_FILE" >&2
  return 0
}

# resolve_mark_epoch <name> <step>
# Finds the most recent performance.log line matching name+step, parses its
# ts, prints the epoch on stdout, returns 0. Returns 1 (prints nothing) if
# unfound/unparseable/no log file — callers must treat that as "skip, do
# not log or use a bogus value", never fall back to `now`.
resolve_mark_epoch() {
  local NAME="$1" STEP="$2"
  [[ -z "$REPO_ROOT" ]] && return 1
  local LOG_FILE="$REPO_ROOT/.session-continuity/performance.log"
  [[ -r "$LOG_FILE" ]] || return 1

  local ts epoch
  ts="$(grep "\"name\":\"$NAME\"" "$LOG_FILE" 2>/dev/null \
    | grep "\"step\":\"$STEP\"" | tail -1 \
    | sed -E 's/.*"ts":"([^"]*)".*/\1/' || true)"
  [[ -z "$ts" ]] && return 1

  epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null \
    || date -u -d "$ts" +%s 2>/dev/null || true)"
  [[ "$epoch" =~ ^[0-9]+$ ]] || return 1

  printf '%s' "$epoch"
  return 0
}

subcommand="${1:-}"
shift || true

case "$subcommand" in
  record)
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
        *) : ;;
      esac
    done

    if [[ -z "$SOURCE" || -z "$NAME" || -z "$DURATION" ]]; then
      echo "perf-log.sh: record requires --source, --name, --duration" >&2
      exit 0
    fi
    if ! [[ "$DURATION" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
      echo "perf-log.sh: record requires --source, --name, --duration" >&2
      exit 0
    fi
    [[ -n "$EXIT" && ! "$EXIT" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && EXIT=""
    [[ -n "$RETRIES" && ! "$RETRIES" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && RETRIES=""
    [[ -n "$ITEMS" && ! "$ITEMS" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && ITEMS=""

    write_record "$SOURCE" "$NAME" "$DURATION" "$EXIT" "$STEP" "$RETRIES" "$ITEMS"
    ;;

  mark)
    SOURCE=""; NAME=""; STEP=""
    for arg in "$@"; do
      case "$arg" in
        --source=*) SOURCE="${arg#*=}" ;;
        --name=*)   NAME="${arg#*=}" ;;
        --step=*)   STEP="${arg#*=}" ;;
        *) : ;;
      esac
    done
    if [[ -z "$SOURCE" || -z "$NAME" || -z "$STEP" ]]; then
      echo "perf-log.sh: mark requires --source, --name, --step" >&2
      exit 0
    fi
    write_record "$SOURCE" "$NAME" "0.000" "" "$STEP" "" ""
    ;;

  since)
    SOURCE=""; NAME=""; MARK_STEP=""; EMIT_STEP=""; RETRIES=""; ITEMS=""; PRINT_EPOCH=0
    for arg in "$@"; do
      case "$arg" in
        --source=*)     SOURCE="${arg#*=}" ;;
        --name=*)       NAME="${arg#*=}" ;;
        --mark-step=*)  MARK_STEP="${arg#*=}" ;;
        --emit-step=*)  EMIT_STEP="${arg#*=}" ;;
        --retries=*)    RETRIES="${arg#*=}" ;;
        --items=*)      ITEMS="${arg#*=}" ;;
        --print-epoch)  PRINT_EPOCH=1 ;;
        *) : ;;
      esac
    done

    if [[ -z "$NAME" || -z "$MARK_STEP" ]]; then
      echo "perf-log.sh: since requires --name and --mark-step" >&2
      exit 0
    fi

    if [[ "$PRINT_EPOCH" == "1" ]]; then
      epoch="$(resolve_mark_epoch "$NAME" "$MARK_STEP")" || exit 0
      printf '%s\n' "$epoch"
      exit 0
    fi

    if [[ -z "$SOURCE" || -z "$EMIT_STEP" ]]; then
      echo "perf-log.sh: since requires --source and --emit-step (or --print-epoch)" >&2
      exit 0
    fi

    [[ -n "$RETRIES" && ! "$RETRIES" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && RETRIES=""
    [[ -n "$ITEMS" && ! "$ITEMS" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && ITEMS=""

    mark_epoch="$(resolve_mark_epoch "$NAME" "$MARK_STEP")" || exit 0
    now_epoch="$(date -u +%s)"
    duration="$(( now_epoch - mark_epoch )).000"

    write_record "$SOURCE" "$NAME" "$duration" "" "$EMIT_STEP" "$RETRIES" "$ITEMS"
    ;;

  *)
    echo "perf-log.sh: unknown subcommand '$subcommand' (expected 'record', 'mark', or 'since')" >&2
    exit 0
    ;;
esac

exit 0
```

- [ ] **Step 4: Run the smoke test to verify all 16 assertions pass**

```bash
zsh meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh
```

Expected: `Result: 16 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/perf-log.sh meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh
git commit -m "feat: add perf-log.sh mark/since, collapsing epoch-subtraction duplication"
```

---

### Task 2: `primer-status.sh`

**Files:**
- Create: `hooks/lib/primer-status.sh`
- Test: `meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh`

**Interfaces:**
- Produces: `bash hooks/lib/primer-status.sh [<dir>]` (`<dir>` defaults to `.`). Prints exactly four `KEY=value` lines on stdout — `HEAD_SHA=`, `PRIMER_MTIME=`, `BACKLOG_COUNT=`, `LEARNINGS_COUNT=` — each independently `?` on failure. Always exits 0.
- Consumes: `hooks/lib/count-entries.sh`, resolved relative to its own directory (`$(dirname "$0")/count-entries.sh`), same resolution convention `session-start.sh` already uses.

- [ ] **Step 1: Write the failing smoke test**

Create `meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# primer-status.sh smoke test. Hermetic: runs against a throwaway temp git
# repo, never touches this repo's own working tree.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
tool="$lib/primer-status.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

# get <output> <key> — extract KEY=value's value from the tool's stdout.
get() { print -r -- "$1" | sed -n "s/^$2=//p"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q
git -C "$work" config user.email "test@example.com"
git -C "$work" config user.name "Test"
mkdir -p "$work/.session-continuity"

# --- no primer/backlog/learnings yet, but a real commit exists -------------
: > "$work/README.md"
git -C "$work" add README.md
git -C "$work" commit -qm "init"
expected_sha="$(git -C "$work" rev-parse --short HEAD)"

out="$(bash "$tool" "$work")"
sha="$(get "$out" HEAD_SHA)"
mtime="$(get "$out" PRIMER_MTIME)"
backlog="$(get "$out" BACKLOG_COUNT)"
learnings="$(get "$out" LEARNINGS_COUNT)"

[[ "$sha" == "$expected_sha" ]] && ok "HEAD_SHA matches git rev-parse --short HEAD" \
  || bad "HEAD_SHA: expected $expected_sha, got $sha"
[[ "$mtime" == "?" ]] && ok "PRIMER_MTIME: ? when SESSION_PRIMER.md is missing" \
  || bad "PRIMER_MTIME: expected ?, got $mtime"
[[ "$backlog" == "0" ]] && ok "BACKLOG_COUNT: 0 when BACKLOG.md is missing (count-entries.sh's own missing-file contract)" \
  || bad "BACKLOG_COUNT: expected 0, got $backlog"
[[ "$learnings" == "0" ]] && ok "LEARNINGS_COUNT: 0 when LEARNINGS.md is missing" \
  || bad "LEARNINGS_COUNT: expected 0, got $learnings"

# --- all four files present with real content -------------------------------
printf '# primer\n' > "$work/.session-continuity/SESSION_PRIMER.md"
printf '# backlog\n\n### 1. one\n### 2. two\n### 3. three\n' > "$work/.session-continuity/BACKLOG.md"
printf '# learnings\n\n### 1. one\n' > "$work/.session-continuity/LEARNINGS.md"

out="$(bash "$tool" "$work")"
mtime="$(get "$out" PRIMER_MTIME)"
backlog="$(get "$out" BACKLOG_COUNT)"
learnings="$(get "$out" LEARNINGS_COUNT)"

[[ "$mtime" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && ok "PRIMER_MTIME: YYYY-MM-DD-prefixed when the file exists" \
  || bad "PRIMER_MTIME: expected YYYY-MM-DD prefix, got $mtime"
[[ "$backlog" == "3" ]] && ok "BACKLOG_COUNT: 3 real entries counted" \
  || bad "BACKLOG_COUNT: expected 3, got $backlog"
[[ "$learnings" == "1" ]] && ok "LEARNINGS_COUNT: 1 real entry counted" \
  || bad "LEARNINGS_COUNT: expected 1, got $learnings"

# --- defaults to "." when no argument is given -------------------------------
out="$(cd "$work" && bash "$tool")"
backlog="$(get "$out" BACKLOG_COUNT)"
[[ "$backlog" == "3" ]] && ok "no argument: defaults to cwd" \
  || bad "no argument: expected 3, got $backlog"

# --- not a git repo: HEAD_SHA is ? but the script still exits 0 and prints all four lines ---
nogit="$(mktemp -d)"
out="$(bash "$tool" "$nogit")"
rc=$?
sha="$(get "$out" HEAD_SHA)"
line_count="$(print -r -- "$out" | wc -l | tr -d ' ')"
if [[ "$rc" == "0" && "$sha" == "?" && "$line_count" == "4" ]]; then
  ok "non-git dir: HEAD_SHA=?, all four lines still printed, exit 0"
else
  bad "non-git dir: expected rc=0 sha=? lines=4, got rc=$rc sha=$sha lines=$line_count"
fi
rm -rf "$nogit"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh
zsh meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh
```

Expected: FAIL — `hooks/lib/primer-status.sh` does not exist yet.

- [ ] **Step 3: Write `hooks/lib/primer-status.sh`**

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/primer-status.sh — shared status computation for the primer's
# "current state" report. Prints four key=value lines on stdout,
# best-effort, always exits 0. Used by hooks/session-start.sh (resolved
# next to itself, no CONTRACT_VERSION gate — same convention
# count-entries.sh already follows there) and by commands/primer.md's
# check mode (resolved via CLAUDE_PLUGIN_ROOT, gated by require_script) so
# the two can no longer disagree about what "current" means. See the
# Phase 3 entry of
# meta/superpowers/specs/2026-09-02-determinism-program-design.md.
#
# Usage: primer-status.sh [<dir>]
# <dir> defaults to "." — the directory containing .session-continuity/.
#
# Prints exactly:
#   HEAD_SHA=<short-sha or ?>
#   PRIMER_MTIME=<YYYY-MM-DD HH:MM or ?>
#   BACKLOG_COUNT=<int or ?>
#   LEARNINGS_COUNT=<int or ?>
#
# Every value is independently best-effort: a failure on one line never
# blocks the others, and never aborts the script.

set -u

DIR="${1:-.}"
HERE="$(dirname "$0")"

sha="$(git -C "$DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"

primer_path="$DIR/.session-continuity/SESSION_PRIMER.md"
mtime="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$primer_path" 2>/dev/null \
  || stat -c '%y' "$primer_path" 2>/dev/null \
  || echo '?')"

count_helper="$HERE/count-entries.sh"
if [ -f "$count_helper" ]; then
  backlog_count="$(bash "$count_helper" "$DIR/.session-continuity/BACKLOG.md" 2>/dev/null || echo '?')"
  learnings_count="$(bash "$count_helper" "$DIR/.session-continuity/LEARNINGS.md" 2>/dev/null || echo '?')"
else
  backlog_count="?"
  learnings_count="?"
fi

echo "HEAD_SHA=$sha"
echo "PRIMER_MTIME=$mtime"
echo "BACKLOG_COUNT=$backlog_count"
echo "LEARNINGS_COUNT=$learnings_count"
exit 0
```

```bash
chmod +x hooks/lib/primer-status.sh
```

- [ ] **Step 4: Run the smoke test to verify it passes**

```bash
zsh meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh
```

Expected: `Result: 9 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/primer-status.sh meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh
git commit -m "feat: add primer-status.sh, unifying the primer status 4-tuple"
```

---

### Task 3: Wire `primer-status.sh` into `hooks/session-start.sh`

**Files:**
- Modify: `hooks/session-start.sh` (lines 63-79, and the inner branch at lines 87-91)

**Interfaces:**
- Consumes: `hooks/lib/primer-status.sh` (Task 2), resolved via `$(dirname "$0")/lib/primer-status.sh`.
- Produces: `$status_sha`, `$status_mtime`, `$status_learnings`, `$status_backlog_count` — same scope and downstream usage as the variables they replace. `$status_outstanding` (used by the untouched migration-detection branches below) now reuses `$status_backlog_count` instead of a second `count-entries.sh` invocation.

- [ ] **Step 1: Replace the status-computation block**

Using the Edit tool, replace this exact block (currently `hooks/session-start.sh` lines 63-79):

```bash
status_sha="$(cd "$cwd" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo '?')"
status_mtime="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$cwd/$primer_path" 2>/dev/null \
  || stat -c '%y' "$cwd/$primer_path" 2>/dev/null \
  || echo '?')"
outstanding_path="$cwd/.session-continuity/BACKLOG.md"

# Comment-and-fence-aware heading counter (see hooks/lib/count-entries.sh
# for the contract). Resolved next to this script rather than via
# CLAUDE_PLUGIN_ROOT so the hook keeps working when a test harness runs it
# directly. Its absence is a "?" like the other best-effort probes above,
# not a hard failure.
count_helper="$(dirname "$0")/lib/count-entries.sh"
if [ -f "$count_helper" ]; then
  status_learnings="$(bash "$count_helper" "$cwd/$learnings_path" 2>/dev/null || echo '?')"
else
  status_learnings="?"
fi
```

with:

```bash
# Shared status computation (see hooks/lib/primer-status.sh for the
# contract) — the same script commands/primer.md's check mode calls, so the
# two can no longer disagree about sha/mtime/counts. Resolved next to this
# script rather than via CLAUDE_PLUGIN_ROOT so the hook keeps working when a
# test harness runs it directly. Its absence falls back to "?" for every
# field, like the other best-effort probes here.
status_helper="$(dirname "$0")/lib/primer-status.sh"
if [ -f "$status_helper" ]; then
  status_out="$(bash "$status_helper" "$cwd" 2>/dev/null || true)"
else
  status_out=""
fi
status_sha="$(printf '%s\n' "$status_out" | sed -n 's/^HEAD_SHA=//p')"; status_sha="${status_sha:-?}"
status_mtime="$(printf '%s\n' "$status_out" | sed -n 's/^PRIMER_MTIME=//p')"; status_mtime="${status_mtime:-?}"
status_backlog_count="$(printf '%s\n' "$status_out" | sed -n 's/^BACKLOG_COUNT=//p')"; status_backlog_count="${status_backlog_count:-?}"
status_learnings="$(printf '%s\n' "$status_out" | sed -n 's/^LEARNINGS_COUNT=//p')"; status_learnings="${status_learnings:-?}"

outstanding_path="$cwd/.session-continuity/BACKLOG.md"
```

- [ ] **Step 2: Replace the inner backlog-count branch**

Using the Edit tool, replace this exact block (currently `hooks/session-start.sh` lines 87-91):

```bash
  if [ -f "$count_helper" ]; then
    status_outstanding="$(bash "$count_helper" "$outstanding_path" 2>/dev/null || echo '?')"
  else
    status_outstanding="?"
  fi
```

with:

```bash
  # Reuse the count already computed above — no second count-entries.sh
  # invocation needed.
  status_outstanding="$status_backlog_count"
```

- [ ] **Step 3: Run the existing session-start smoke test**

```bash
zsh meta/superpowers/validation/2026-08-12-session-start-smoke.zsh
```

Expected: same pass count as before this task — the hook's observable output (the `<system-reminder>` block's HEAD/mtime/Backlog/Learnings lines) is unchanged; only how those values are computed changed.

- [ ] **Step 4: Commit**

```bash
git add hooks/session-start.sh
git commit -m "refactor: session-start.sh computes primer status via the shared primer-status.sh"
```

---

### Task 4: Wire `primer-status.sh` into `commands/primer.md` check mode

**Files:**
- Modify: `commands/primer.md` (Step 5, lines 321-354)

**Interfaces:**
- Consumes: `hooks/lib/primer-status.sh` (Task 2), resolved via `CLAUDE_PLUGIN_ROOT` and `require_script` (`CONTRACT_VERSION=1`).

- [ ] **Step 1: Replace Step 5's gather block and report instructions**

Using the Edit tool, replace this exact block (currently `commands/primer.md` lines 321-354):

```markdown
## Step 5 — Check mode

Gather the report data in **one Bash call**, timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
git rev-parse --short HEAD
stat -f '%Sm' .session-continuity/SESSION_PRIMER.md 2>/dev/null || stat -c '%y' .session-continuity/SESSION_PRIMER.md
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/count-entries.sh" 1; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/count-entries.sh" .session-continuity/BACKLOG.md
else
  echo "?"
fi
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/count-entries.sh" 1; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/count-entries.sh" .session-continuity/LEARNINGS.md
else
  echo "?"
fi
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-5-check-mode --duration="$_PERF_DURATION"
```

Report:

```
.session-continuity/SESSION_PRIMER.md: up to date against HEAD (<short-sha>)
Last refresh: <primer mtime>
Backlog: <count from BACKLOG.md>
Learnings: <count from .session-continuity/LEARNINGS.md>
```

No changes made. Exit.
```

with:

```markdown
## Step 5 — Check mode

Gather the report data in **one Bash call**, timed, via the shared status
script (also used by `hooks/session-start.sh`, so the two can no longer
disagree about sha/mtime/counts):

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-status.sh" 1; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-status.sh" .
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
fi
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-5-check-mode --duration="$_PERF_DURATION"
```

The output above is four `KEY=value` lines: `HEAD_SHA=`, `PRIMER_MTIME=`,
`BACKLOG_COUNT=`, `LEARNINGS_COUNT=` (any of them may read `?` if that
probe failed — report it as `?`, never invent a value). Report:

```
.session-continuity/SESSION_PRIMER.md: up to date against HEAD (<HEAD_SHA>)
Last refresh: <PRIMER_MTIME>
Backlog: <BACKLOG_COUNT>
Learnings: <LEARNINGS_COUNT>
```

No changes made. Exit.
```

- [ ] **Step 2: Verify the old direct count-entries.sh calls are gone from Step 5**

```bash
awk '/^## Step 5/,/^## Notes/' commands/primer.md | grep -c 'count-entries.sh'
```

Expected: `0`.

- [ ] **Step 3: Commit**

```bash
git add commands/primer.md
git commit -m "refactor: primer.md check mode reads the shared primer-status.sh"
```

---

### Task 5: Collapse the four epoch blocks in `commands/end-session.md`

**Files:**
- Modify: `commands/end-session.md` (four spans: lines 217-241, 283-308, 408-435, 550-600)

**Interfaces:**
- Consumes: `hooks/lib/perf-log.sh mark`/`since` (Task 1).
- Produces: no shell variables cross a Bash-call boundary for this timing data anymore — `since --print-epoch` re-resolves the epoch fresh inside the same Bash call that uses it, closing backlog item `52dc` (the `step-4-agent-active` block no longer depends on `$start_epoch` set in a different Bash tool call).

- [ ] **Step 1: Collapse Block A — Step 1's appears-DONE prompt-wait**

Using the Edit tool, replace this exact block (currently `commands/end-session.md` lines 217-241):

```markdown
2. Before rendering the question below, log a prompt-shown marker (isolates the human-response wait from ritual compute time — see Step 4):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-prompt-shown --duration=0.000
   ```

   Then ask a close-only question, scoped narrower than the refresh flow's combined prompt since there are no commit subjects or free-form drift to fold in:

   > "Backlog — N appears-DONE (see list). Close any, or leave as-is?"
3. **Wait for the answer before continuing.** Same refusal rule as the refresh flow: never close an item without explicit confirmation. Once the answer arrives, log the wait duration:

   ```bash
   prior_ts="$(grep '"name":"end-session"' .session-continuity/performance.log 2>/dev/null \
     | grep '"step":"step-1-prompt-shown"' | tail -1 \
     | sed -E 's/.*"ts":"([^"]*)".*/\1/' || true)"
   prior_epoch=""
   if [ -n "$prior_ts" ]; then
     prior_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$prior_ts" +%s 2>/dev/null \
       || date -u -d "$prior_ts" +%s 2>/dev/null || true)"
   fi
   if [[ "$prior_epoch" =~ ^[0-9]+$ ]]; then
     now_epoch="$(date -u +%s)"
     bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-prompt-wait --duration="$(( now_epoch - prior_epoch )).000"
   fi
   ```
```

with:

```markdown
2. Before rendering the question below, log a prompt-shown marker (isolates the human-response wait from ritual compute time — see Step 4):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" mark --source=command --name=end-session --step=step-1-prompt-shown
   ```

   Then ask a close-only question, scoped narrower than the refresh flow's combined prompt since there are no commit subjects or free-form drift to fold in:

   > "Backlog — N appears-DONE (see list). Close any, or leave as-is?"
3. **Wait for the answer before continuing.** Same refusal rule as the refresh flow: never close an item without explicit confirmation. Once the answer arrives, log the wait duration:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" since --source=command --name=end-session --mark-step=step-1-prompt-shown --emit-step=step-1-prompt-wait
   ```
```

- [ ] **Step 2: Collapse Block B — Step 1's refresh-flow prompt-wait**

Using the Edit tool, replace this exact block (currently `commands/end-session.md` lines 283-308):

```markdown
4. **Single combined prompt.** After printing the subject list (and overlay block if any), log a prompt-shown marker (same mechanism as the drift-clean prompt above — isolates human-response wait from ritual compute time, see Step 4):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-prompt-shown --duration=0.000
   ```

   Then ask the user one question covering both close-candidates and free-form edits:

   > "Backlog — close any from the overlay, add new follow-ups, or no changes?"

   **Wait for the answer before continuing.** Do not preemptively edit the list, clear items you interpret as "stale," or proceed based on your own reading. Do not split this into two sequential prompts — one prompt covers the same answer space. Once the answer arrives, log the wait duration:

   ```bash
   prior_ts="$(grep '"name":"end-session"' .session-continuity/performance.log 2>/dev/null \
     | grep '"step":"step-1-prompt-shown"' | tail -1 \
     | sed -E 's/.*"ts":"([^"]*)".*/\1/' || true)"
   prior_epoch=""
   if [ -n "$prior_ts" ]; then
     prior_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$prior_ts" +%s 2>/dev/null \
       || date -u -d "$prior_ts" +%s 2>/dev/null || true)"
   fi
   if [[ "$prior_epoch" =~ ^[0-9]+$ ]]; then
     now_epoch="$(date -u +%s)"
     bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-prompt-wait --duration="$(( now_epoch - prior_epoch )).000"
   fi
   ```
```

with:

```markdown
4. **Single combined prompt.** After printing the subject list (and overlay block if any), log a prompt-shown marker (same mechanism as the drift-clean prompt above — isolates human-response wait from ritual compute time, see Step 4):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" mark --source=command --name=end-session --step=step-1-prompt-shown
   ```

   Then ask the user one question covering both close-candidates and free-form edits:

   > "Backlog — close any from the overlay, add new follow-ups, or no changes?"

   **Wait for the answer before continuing.** Do not preemptively edit the list, clear items you interpret as "stale," or proceed based on your own reading. Do not split this into two sequential prompts — one prompt covers the same answer space. Once the answer arrives, log the wait duration:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" since --source=command --name=end-session --mark-step=step-1-prompt-shown --emit-step=step-1-prompt-wait
   ```
```

- [ ] **Step 3: Collapse Block C — Step 2's prompt-wait**

Using the Edit tool, replace this exact block (currently `commands/end-session.md` lines 408-435):

```markdown
**Single confirm prompt.** Present every pre-drafted entry together in one rendered block (numbered, full body, target section labeled). Before asking, log a prompt-shown marker (same mechanism as Step 1's prompts — isolates human-response wait from ritual compute time, see Step 4):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-2-prompt-shown --duration=0.000
```

Then ask one question:

> "Stage all N entries as drafted, revise specific ones, or skip any?"

Possible replies you must handle: "all" / "stage" → stage every draft; "revise N" → loop into edit-draft-N flow then re-present; "skip N" → drop draft N from the batch; "none" → stage nothing.

Once the answer arrives, log the wait duration:

```bash
prior_ts="$(grep '"name":"end-session"' .session-continuity/performance.log 2>/dev/null \
  | grep '"step":"step-2-prompt-shown"' | tail -1 \
  | sed -E 's/.*"ts":"([^"]*)".*/\1/' || true)"
prior_epoch=""
if [ -n "$prior_ts" ]; then
  prior_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$prior_ts" +%s 2>/dev/null \
    || date -u -d "$prior_ts" +%s 2>/dev/null || true)"
fi
if [[ "$prior_epoch" =~ ^[0-9]+$ ]]; then
  now_epoch="$(date -u +%s)"
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-2-prompt-wait --duration="$(( now_epoch - prior_epoch )).000"
fi
```
```

with:

```markdown
**Single confirm prompt.** Present every pre-drafted entry together in one rendered block (numbered, full body, target section labeled). Before asking, log a prompt-shown marker (same mechanism as Step 1's prompts — isolates human-response wait from ritual compute time, see Step 4):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" mark --source=command --name=end-session --step=step-2-prompt-shown
```

Then ask one question:

> "Stage all N entries as drafted, revise specific ones, or skip any?"

Possible replies you must handle: "all" / "stage" → stage every draft; "revise N" → loop into edit-draft-N flow then re-present; "skip N" → drop draft N from the batch; "none" → stage nothing.

Once the answer arrives, log the wait duration:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" since --source=command --name=end-session --mark-step=step-2-prompt-shown --emit-step=step-2-prompt-wait
```
```

- [ ] **Step 4: Collapse Block D — Step 4's ritual-complete and agent-active blocks**

Using the Edit tool, replace this exact block (currently `commands/end-session.md` lines 550-600):

```markdown
**Before that line, record total ritual time.** Each step above only timed
its own Bash block, not the gaps between them — this reads back this
invocation's own `step-1-fast-path` timestamp (always the first thing every
invocation logs, fast-path or not) and diffs it against now, so the log
carries one real end-to-end number per invocation alongside the per-step
ones. Skip the log call entirely rather than record a bogus duration if the
timestamp is missing or unparseable:

```bash
last_ts="$(grep '"name":"end-session"' .session-continuity/performance.log 2>/dev/null \
  | grep '"step":"step-1-fast-path"' | tail -1 \
  | sed -E 's/.*"ts":"([^"]*)".*/\1/' || true)"
start_epoch=""
if [ -n "$last_ts" ]; then
  start_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$last_ts" +%s 2>/dev/null \
    || date -u -d "$last_ts" +%s 2>/dev/null || true)"
fi
if [[ "$start_epoch" =~ ^[0-9]+$ ]]; then
  now_epoch="$(date -u +%s)"
  _PERF_DURATION="$(( now_epoch - start_epoch )).000"
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-4-ritual-complete --duration="$_PERF_DURATION"
fi
```

**Then derive agent-active time** — `step-4-ritual-complete` is real wall
clock, but it includes however long the user took to answer any prompts
along the way. Rather than subtract specific prompt-wait markers (the old
approach, retired — see
`meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md`
Change 2 for why a two-marker subtraction can't be made correct), derive
active time directly from the transcript. Resolve the transcript again here
— this is a separate Bash call from Step 2's, and shell state does not
persist across Bash calls, so Step 2's `$TRANSCRIPT` is not visible here:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
STEP4_TRANSCRIPT=""
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/resolve-transcript.sh" 1; then
  STEP4_TRANSCRIPT="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/resolve-transcript.sh")"
fi
if [[ "$start_epoch" =~ ^[0-9]+$ ]] && [[ -n "$STEP4_TRANSCRIPT" ]]; then
  if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/agent-active.sh" 1; then
    AGENT_ACTIVE="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/agent-active.sh" "$STEP4_TRANSCRIPT" "$start_epoch")"
    if [[ -n "$AGENT_ACTIVE" ]]; then
      bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-4-agent-active --duration="$AGENT_ACTIVE"
    fi
  else
    echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
  fi
fi
```
```

with:

```markdown
**Before that line, record total ritual time.** Each step above only timed
its own Bash block, not the gaps between them — this reads back this
invocation's own `step-1-fast-path` timestamp (always the first thing every
invocation logs, fast-path or not) and diffs it against now, so the log
carries one real end-to-end number per invocation alongside the per-step
ones. Skip the log call entirely rather than record a bogus duration if the
mark is missing or unparseable — `since` already does this silently:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" since --source=command --name=end-session --mark-step=step-1-fast-path --emit-step=step-4-ritual-complete
```

**Then derive agent-active time** — `step-4-ritual-complete` is real wall
clock, but it includes however long the user took to answer any prompts
along the way. Rather than subtract specific prompt-wait markers (the old
approach, retired — see
`meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md`
Change 2 for why a two-marker subtraction can't be made correct), derive
active time directly from the transcript. Resolve both the transcript and
the start epoch again here — this is a separate Bash call from Step 2's and
from the `since` call above, and shell state does not persist across Bash
calls, so neither Step 2's `$TRANSCRIPT` nor a `$start_epoch` set above
would be visible here even if it were still computed as a shell variable
(the previous version of this block was exactly this bug — backlog item
`52dc` — depending on `$start_epoch` across that same boundary):

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
STEP4_TRANSCRIPT=""
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/resolve-transcript.sh" 1; then
  STEP4_TRANSCRIPT="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/resolve-transcript.sh")"
fi
START_EPOCH="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" since --print-epoch --name=end-session --mark-step=step-1-fast-path)"
if [[ "$START_EPOCH" =~ ^[0-9]+$ ]] && [[ -n "$STEP4_TRANSCRIPT" ]]; then
  if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/agent-active.sh" 1; then
    AGENT_ACTIVE="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/agent-active.sh" "$STEP4_TRANSCRIPT" "$START_EPOCH")"
    if [[ -n "$AGENT_ACTIVE" ]]; then
      bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-4-agent-active --duration="$AGENT_ACTIVE"
    fi
  else
    echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
  fi
fi
```
```

- [ ] **Step 5: Verify none of the four inlined epoch-subtraction patterns remain**

```bash
grep -n 'prior_epoch=\|start_epoch=""' commands/end-session.md
```

Expected: no output — every occurrence was inside one of the four blocks just replaced.

- [ ] **Step 6: Verify the four blocks now call `mark`/`since`**

```bash
grep -c 'perf-log.sh" mark' commands/end-session.md
grep -c 'perf-log.sh" since' commands/end-session.md
```

Expected: `3` (Blocks A, B, C each mark once), `4` (Blocks A, B, C each `since` once for their prompt-wait, plus Block D's ritual-complete `since`; Block D's `--print-epoch` call is a fifth `since` invocation, so the true expected count is `4` matches from `perf-log.sh" since` where Block D contributes two — recount by running the command and confirm it prints `5`, then note in the commit body which call is which if the printed number differs from this expectation, rather than editing this check to match after the fact).

- [ ] **Step 7: Commit**

```bash
git add commands/end-session.md
git commit -m "refactor: end-session.md collapses its four epoch-subtraction blocks to mark/since, fixing step-4-agent-active's start_epoch scope bug (52dc)"
```

---

### Task 6: Doc pointers, regression pass, changelog

**Files:**
- Modify: `meta/superpowers/specs/2026-09-02-determinism-program-design.md`
- Modify: `.session-continuity/BACKLOG.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Collapse the design doc's Phase 3 entry to a pointer**

Using the Edit tool, replace this exact block in `meta/superpowers/specs/2026-09-02-determinism-program-design.md`:

```markdown
**Phase 3 `[a17f]` — shared mechanics library.** `perf-log.sh mark` and
`perf-log.sh since`, collapsing the four duplicated epoch blocks
(`end-session.md` 228-241, 295-308, 579-592, 715-729) to one-liners; and one
status function shared by `session-start.sh`, `primer.md` check mode, and
`doctor.md`, so the three can no longer disagree. Unblocks phases 4 and 6.
```

with:

```markdown
**Phase 3 `[a17f]` — shared mechanics library.** `perf-log.sh mark`/`since`,
plus `primer-status.sh` shared by `session-start.sh` and `primer.md`'s
check mode. Unblocks phases 4 and 6 and closes `52dc` as a side effect.
`doctor.md`'s drift verdict was scoped out — deferred to #45, once `4a9d`
is decided. Plan:
`meta/superpowers/plans/2026-09-03-shared-mechanics-library.md`.
```

- [ ] **Step 2: Update BACKLOG item 11's text**

Using the Edit tool, replace this exact block in `.session-continuity/BACKLOG.md`:

```markdown
### 11. [a17f] [2026-09-02] Determinism Phase 3 — shared mechanics library

Adds `perf-log.sh mark` and `perf-log.sh since` to collapse four
near-identical 14-line epoch-subtraction blocks inlined in
`commands/end-session.md`, plus one status function shared by
`hooks/session-start.sh`, `primer.md` check mode, and `doctor.md` so the three
can no longer disagree. Unblocks phases 4 and 6, and forces the decision filed
as item `4a9d`. Scope: the Phase 3 entry in
`meta/superpowers/specs/2026-09-02-determinism-program-design.md`; needs a plan.
```

with:

```markdown
### 11. [a17f] [2026-09-02] Determinism Phase 3 — shared mechanics library

Adds `perf-log.sh mark`/`since` to collapse the four near-identical
epoch-subtraction blocks in `commands/end-session.md` (also closes item
`52dc` as a side effect — `step-4-agent-active` re-derives its epoch fresh
via `since --print-epoch` instead of depending on a shell variable that
doesn't survive across Bash tool calls), plus a new `primer-status.sh`
shared by `hooks/session-start.sh` and `primer.md`'s check mode so the two
can no longer disagree on sha/mtime/counts. `doctor.md`'s drift verdict is
a different function and stays out of scope here — deferred to item #45
once `4a9d` is decided. Unblocks phases 4 and 6. Plan:
`meta/superpowers/plans/2026-09-03-shared-mechanics-library.md`.
```

- [ ] **Step 3: Full regression pass**

```bash
for f in \
  meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh \
  meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh \
  meta/superpowers/validation/2026-08-12-session-start-smoke.zsh \
  meta/superpowers/validation/2026-09-01-require-script-smoke.zsh \
  meta/superpowers/validation/2026-09-01-agent-active-smoke.zsh \
  meta/superpowers/validation/2026-09-02-resolve-transcript-smoke.zsh \
  meta/superpowers/validation/2026-09-02-count-entries-smoke.zsh
do
  echo "--- $f ---"
  zsh "$f" || echo "FAILED: $f"
done
```

Expected: every runner ends `0 failed`.

- [ ] **Step 4: Add a CHANGELOG entry**

Add a new section at the top of `CHANGELOG.md`, directly under the `# Changelog` header and its description line, above `## [0.27.0]`:

```markdown
## [0.28.0] — 2026-09-03

### Changed
- **`perf-log.sh` gains `mark`/`since`, collapsing `end-session.md`'s four duplicated epoch-subtraction blocks to one-liners.** Each block re-derived the same ~14-line "grep the log for a prior timestamp, parse it, diff against now" pattern; `mark` writes a named timestamp and `since` reads it back, either recording the elapsed duration under a new step or (`--print-epoch`) printing the raw epoch for a caller that needs the number itself. This also closes backlog item `52dc`: the `step-4-agent-active` block now re-resolves its start epoch fresh, in its own Bash call, instead of depending on a `$start_epoch` shell variable set in a different call that never survived the boundary.
- **New `hooks/lib/primer-status.sh` unifies the primer status computation duplicated between `hooks/session-start.sh` and `commands/primer.md`'s check mode.** The two previously re-derived the same sha/mtime/backlog-count/learnings-count values with slightly different shell incantations (their `stat` format strings already disagreed); both now call one script.
```

- [ ] **Step 5: Commit**

```bash
git add meta/superpowers/specs/2026-09-02-determinism-program-design.md .session-continuity/BACKLOG.md CHANGELOG.md
git commit -m "docs: Phase 3 doc pointers and changelog entry for the shared mechanics library"
```
