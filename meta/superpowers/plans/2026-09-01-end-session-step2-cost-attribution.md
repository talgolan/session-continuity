# End-session Step 2 cost attribution — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the LEARNINGS candidate-extraction heuristics, the agent-active-time metric, and the LEARNINGS.md derivations as real scripts instead of prose the agent re-executes by hand every run, fixing the three failure modes measured in the spec (compute-only counts human idle time, heuristics re-filter the transcript six extra times, the Symptoms index never regenerates at scale).

**Architecture:** Three new scripts under `hooks/lib/`, each invoked once per command step and each never failing loud on bad input (missing/stale transcript → `mode:"unavailable"`, not a crash). A fourth shared helper enforces version-skew: a script missing or contract-mismatched relative to the command prose invoking it reports itself unavailable and directs the user to update the plugin — no silent fallback to the old prose path. `commands/end-session.md` and `commands/learning.md` are rewired to call these scripts instead of embedding the logic in prose.

**Tech Stack:** bash (existing `hooks/lib/*.sh` convention), `jq` (already an implicit dependency via the current Step-2 filter), POSIX `awk` (portable across macOS/Linux, matches `gate-common.sh`/`version-check.sh` style — no new dependency).

**Spec:** `meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md`

## Global Constraints

- Every new script is bash, lives under `hooks/lib/`, and starts with `#!/usr/bin/env bash` then a `# CONTRACT_VERSION=N` comment line (Resolved decision 1 + version-skew mechanism below).
- No script may fail loud on bad *input data* (missing/unreadable/stale transcript, missing LEARNINGS.md file): print the documented "nothing to report" output and `exit 0`. This is distinct from version skew (script itself missing/outdated), which the *command* — not the script — detects and reports (Resolved decision 2).
- No new runtime dependency: `jq` (already used inline in `commands/end-session.md`) and POSIX `awk`/`bash`/`sed`/`grep` (already used throughout `hooks/lib/`) only. No `python3` — the plugin has zero existing python3 dependency in shipped code today (Change 1 is what removes the one ad-hoc python3 heredoc the *agent* improvised in a past run; don't reintroduce it as shipped code).
- Every script that touches `.session-continuity/LEARNINGS.md` or a transcript file must be safe to run twice in a row with no intervening change: the second run's output is byte-identical to the first (idempotency), except where noted (candidate-extraction's *input* — the live transcript — keeps growing between runs, so its output legitimately changes; the LEARNINGS-index script's output on an *unchanged* file must not).
- Smoke tests follow the existing convention: `meta/superpowers/validation/YYYY-MM-DD-<name>-smoke.zsh`, sourcing `meta/superpowers/validation/lib/gate-test-common.zsh` for hermetic repo fixtures (`gt_make_repo`, `gt_stage`, `gt_cleanup`) where a git repo is needed, with `pass`/`fail` counters and an `ok`/`bad` helper pair matching `2026-08-12-hook-json-contract-smoke.zsh`'s style.
- Every smoke test's teardown (`rm -f`/`rm -rf` on a fixture) runs *after* the `ok`/`bad` call for that fixture, and every `bad` message in this plan includes the mismatched value (`"...got $out"`) — the failure diagnostic is captured into the test's own stdout before the fixture is deleted, so a failure is diagnosable from the run's own output without needing the deleted fixture file. Evidence-gate: N/A — smoke fixtures print the full diagnostic value into the ok/bad log line before any rm -f/rm -rf teardown runs, per the bullet above.

---

### Task 1: Shared version-skew guard

**Files:**
- Create: `hooks/lib/require-script.sh`
- Test: `meta/superpowers/validation/2026-09-01-require-script-smoke.zsh`

**Interfaces:**
- Produces: `require_script <path> <expected-contract-version>` — a bash function (this file is SOURCED, never executed directly, matching `gate-common.sh`'s convention). Returns 0 silently if `<path>` is readable and its first `# CONTRACT_VERSION=N` line equals `<expected-contract-version>`. Returns 1 and sets the global `SC_REQUIRE_SCRIPT_MSG` to a one-line, user-facing message otherwise. Tasks 3, 5, 8 (the command-file edits) consume this.

- [ ] **Step 1: Write the smoke test**

Create `meta/superpowers/validation/2026-09-01-require-script-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# require_script() version-skew guard runner. Hermetic: fixture scripts in a
# temp dir, no real hooks/lib files touched.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"

# Fixture: a script with a matching contract version.
cat > "$work/good.sh" <<'EOF'
#!/usr/bin/env bash
# CONTRACT_VERSION=1
echo hi
EOF

# Fixture: a script with a mismatched contract version (simulates a stale
# plugin cache running against newer command prose).
cat > "$work/stale.sh" <<'EOF'
#!/usr/bin/env bash
# CONTRACT_VERSION=0
echo hi
EOF

source "$lib/require-script.sh"

if require_script "$work/good.sh" 1; then
  ok "matching contract version returns 0"
else
  bad "matching contract version should return 0, got 1 (msg: $SC_REQUIRE_SCRIPT_MSG)"
fi

if require_script "$work/stale.sh" 1; then
  bad "mismatched contract version should return 1, got 0"
else
  ok "mismatched contract version returns 1"
  [[ -n "$SC_REQUIRE_SCRIPT_MSG" ]] && ok "mismatch sets a message" || bad "mismatch left SC_REQUIRE_SCRIPT_MSG empty"
fi

if require_script "$work/does-not-exist.sh" 1; then
  bad "missing script should return 1, got 0"
else
  ok "missing script returns 1"
  [[ -n "$SC_REQUIRE_SCRIPT_MSG" ]] && ok "missing-script sets a message" || bad "missing-script left SC_REQUIRE_SCRIPT_MSG empty"
fi

rm -rf "$work"
print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run it, confirm it fails** (the library doesn't exist yet)

Run: `zsh meta/superpowers/validation/2026-09-01-require-script-smoke.zsh`
Expected: FAIL — `source: no such file or directory: .../hooks/lib/require-script.sh`

- [ ] **Step 3: Implement**

Create `hooks/lib/require-script.sh`:

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=n/a (this file has no CONTRACT_VERSION itself — it is
# sourced directly by every command edit, never invoked through the guard
# it implements)
# hooks/lib/require-script.sh — version-skew guard (session-continuity plugin).
# SOURCED, never executed.
#
# Usage: require_script <path> <expected-contract-version>
# Returns 0 if <path> is readable and its first "# CONTRACT_VERSION=N" line
# equals <expected-contract-version>. Returns 1 and sets
# SC_REQUIRE_SCRIPT_MSG to a one-line message otherwise. No fallback: per
# meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md
# Resolved decision 2, a version mismatch is reported to the user, never
# silently degraded to an old prose path.

require_script() {
  local path="$1" expected="$2" found
  SC_REQUIRE_SCRIPT_MSG=""
  if [[ ! -r "$path" ]]; then
    SC_REQUIRE_SCRIPT_MSG="$(basename "$path") not found at $path — plugin cache is out of date. Run \`/session-continuity:update\`."
    return 1
  fi
  found="$(grep -m1 '^# CONTRACT_VERSION=' "$path" 2>/dev/null | sed -E 's/^# CONTRACT_VERSION=//')"
  if [[ "$found" != "$expected" ]]; then
    SC_REQUIRE_SCRIPT_MSG="$(basename "$path") contract version mismatch (found '${found:-none}', need '$expected') — plugin cache is out of date. Run \`/session-continuity:update\`."
    return 1
  fi
  return 0
}
```

- [ ] **Step 4: Run the smoke test, confirm it passes**

Run: `zsh meta/superpowers/validation/2026-09-01-require-script-smoke.zsh`
Expected: `Result: 5 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/require-script.sh meta/superpowers/validation/2026-09-01-require-script-smoke.zsh
git commit -m "feat: add require_script version-skew guard for new hooks/lib scripts"
```

---

### Task 2: Candidate-extraction script (Change 1)

**Files:**
- Create: `hooks/lib/candidate-extract.jq`
- Create: `hooks/lib/candidate-extract.sh`
- Test: `meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `hooks/lib/candidate-extract.sh <transcript-path>` — prints one JSON object to stdout: `{"mode":"transcript"|"unavailable","candidates":[{"heuristic":str,"title":str,"evidence":[str,...]},...],"overflow":int}`. Always exits 0. Task 3 (Step 2 rewire) is the consumer.

- [ ] **Step 1: Write the smoke test**

Create `meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh`. This builds four small synthetic transcripts (one per heuristic) plus the degradation cases, and — because Heuristic B needs `git ls-files` — runs inside a hermetic repo via `gt_make_repo`.

```zsh
#!/usr/bin/env zsh
# candidate-extract.sh smoke test. Hermetic: synthetic JSONL fixtures, a
# throwaway git repo for the tracked-file check, temp files cleaned up.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
source "$here/lib/gate-test-common.zsh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

jline() { print -r -- "$1"; }  # readability alias

# --- degradation cases ------------------------------------------------------

out="$(bash "$lib/candidate-extract.sh" /no/such/file.jsonl)"
if [[ "$out" == '{"mode":"unavailable","candidates":[],"overflow":0}' ]]; then
  ok "missing transcript -> mode:unavailable"
else
  bad "missing transcript: got $out"
fi

empty_f="$(mktemp)"
out="$(bash "$lib/candidate-extract.sh" "$empty_f")"
[[ "$out" == '{"mode":"unavailable","candidates":[],"overflow":0}' ]] && ok "empty transcript -> mode:unavailable" || bad "empty transcript: got $out"
rm -f "$empty_f"

stale_f="$(mktemp)"
jline '{"type":"user","timestamp":"2026-01-01T00:00:00.000Z","message":{"content":[]}}' > "$stale_f"
touch -t 202001010000 "$stale_f" 2>/dev/null || touch -mt 202001010000 "$stale_f"
out="$(bash "$lib/candidate-extract.sh" "$stale_f")"
[[ "$out" == '{"mode":"unavailable","candidates":[],"overflow":0}' ]] && ok "stale (>5min old) transcript -> mode:unavailable" || bad "stale transcript: got $out"
rm -f "$stale_f"

# --- Heuristic A: retry burst ------------------------------------------------

mk_bash_call() {  # <ts> <tool_use_id> <command>
  jline "{\"type\":\"assistant\",\"timestamp\":\"$1\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"id\":\"$2\",\"input\":{\"command\":\"$3\"}}]}}"
}
mk_result() {  # <ts> <tool_use_id> <is_error> <text>
  jline "{\"type\":\"user\",\"timestamp\":\"$1\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"$2\",\"is_error\":$3,\"content\":\"$4\"}]}}"
}

a_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:00:01.000Z" "t1" true "Exit code 1\\nFAIL src/foo.test.ts"
  mk_bash_call "2026-09-01T00:01:00.000Z" "t2" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:01:01.000Z" "t2" true "Exit code 1\\nFAIL src/foo.test.ts"
  mk_bash_call "2026-09-01T00:02:00.000Z" "t3" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:02:01.000Z" "t3" false "Exit code 0\\nPASS"
} > "$a_f"
out="$(bash "$lib/candidate-extract.sh" "$a_f")"
if print -r -- "$out" | jq -e '.candidates | any(.heuristic == "retry-burst")' >/dev/null 2>&1; then
  ok "Heuristic A: 3x identical command triggers retry-burst"
else
  bad "Heuristic A did not trigger: $out"
fi
rm -f "$a_f"

# --- Heuristic B: revert / reset (needs a real tracked file) ---------------

repo_dir="$(gt_make_repo)"
gt_stage "$repo_dir" "src/broken.ts" "old content"
git -C "$repo_dir" commit -q -m "add broken.ts"
b_f="$(mktemp)"
mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "rm -rf src/broken.ts" > "$b_f"
out="$(cd "$repo_dir" && bash "$lib/candidate-extract.sh" "$b_f")"
if print -r -- "$out" | jq -e '.candidates | any(.heuristic == "revert")' >/dev/null 2>&1; then
  ok "Heuristic B: rm -rf on a tracked file triggers revert"
else
  bad "Heuristic B did not trigger: $out"
fi
rm -f "$b_f"
gt_cleanup "$repo_dir"

# --- Heuristic C: error recurrence ------------------------------------------

c_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "bun run build"
  mk_result    "2026-09-01T00:00:01.000Z" "t1" true "Error: Cannot find module 'foo'"
  mk_bash_call "2026-09-01T00:05:00.000Z" "t2" "bun run build"
  mk_result    "2026-09-01T00:05:01.000Z" "t2" true "Error: Cannot find module 'foo'"
  mk_bash_call "2026-09-01T00:20:00.000Z" "t3" "bun run build"
  mk_result    "2026-09-01T00:20:01.000Z" "t3" true "Error: Cannot find module 'foo'"
} > "$c_f"
out="$(bash "$lib/candidate-extract.sh" "$c_f")"
if print -r -- "$out" | jq -e '.candidates | any(.heuristic == "error-recurrence")' >/dev/null 2>&1; then
  ok "Heuristic C: 3x same error over >=15min triggers error-recurrence"
else
  bad "Heuristic C did not trigger: $out"
fi
rm -f "$c_f"

# --- Heuristic D: fix burst ---------------------------------------------------

d_f="$(mktemp)"
{
  # 10 investigatory calls, one per minute 00:00..00:09, all inside the 30
  # minutes preceding the 00:15 fix commit.
  for i in 00 01 02 03 04 05 06 07 08 09; do
    mk_bash_call "2026-09-01T00:${i}:00.000Z" "d$i" "bun test src/bar.test.ts"
    mk_result    "2026-09-01T00:${i}:01.000Z" "d$i" true "Exit code 1\\nFAIL src/bar.test.ts"
  done
  # single-quoted commit message -- mk_bash_call interpolates $3 straight
  # into a JSON string with no escaping, so it must not contain a `"`.
  mk_bash_call "2026-09-01T00:15:00.000Z" "dc" "git commit -m 'fix(bar): correct off-by-one in parser'"
} > "$d_f"
out="$(bash "$lib/candidate-extract.sh" "$d_f")"
if print -r -- "$out" | jq -e '.candidates | any(.heuristic == "fix-burst")' >/dev/null 2>&1; then
  ok "Heuristic D: fix commit preceded by >=10 calls in 30min triggers fix-burst"
else
  bad "Heuristic D did not trigger: $out"
fi
rm -f "$d_f"

# --- determinism -------------------------------------------------------------

out1="$(bash "$lib/candidate-extract.sh" "$a_f" 2>/dev/null || true)"
a_f2="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:00:01.000Z" "t1" true "Exit code 1\\nFAIL src/foo.test.ts"
  mk_bash_call "2026-09-01T00:01:00.000Z" "t2" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:01:01.000Z" "t2" true "Exit code 1\\nFAIL src/foo.test.ts"
  mk_bash_call "2026-09-01T00:02:00.000Z" "t3" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:02:01.000Z" "t3" false "Exit code 0\\nPASS"
} > "$a_f2"
out2="$(bash "$lib/candidate-extract.sh" "$a_f2")"
[[ "$out1" == "$out2" ]] && ok "determinism: identical transcript twice -> identical JSON" || bad "determinism: outputs differ"
rm -f "$a_f2"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run it, confirm it fails** (scripts don't exist yet)

Run: `zsh meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh`
Expected: FAIL — `bash: .../hooks/lib/candidate-extract.sh: No such file or directory`

- [ ] **Step 3: Implement**

Create `hooks/lib/candidate-extract.jq`:

```jq
# hooks/lib/candidate-extract.jq — LEARNINGS candidate extraction + heuristics A-D.
# Invoked via: jq -n --argjson tracked_files <json array from `git ls-files`> \
#   -f candidate-extract.jq <transcript.jsonl>
# See meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md
# Change 1. Absorbs the previously-inline Step-2 extraction filter unchanged,
# plus Heuristics A-D and the dedup/sort/cap output rules, so the agent
# invokes this once instead of re-filtering per heuristic.

def to_epoch: gsub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;

def norm_err:
  if (. == null or . == "") then ""
  else
    .
    | gsub("(?<p>/[^ :\"]+/)(?<b>[^/ :\"]+)"; "\(.b)")
    | gsub(":[0-9]+:[0-9]+"; "")
    | gsub("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z?"; "")
    | gsub("[0-9]{2}:[0-9]{2}:[0-9]{2}"; "")
    | gsub("0x[0-9a-fA-F]+"; "0xN")
  end;

def first_line_from_text:
  (split("\n") | map(select(length>0))) as $ls
  | if ($ls|length)==0 then ""
    elif ($ls[0] | test("^Exit code")) then ($ls[1] // "")
    else $ls[0]
    end;

def err_line_of($is_error; $stderr; $text):
  if ($stderr // "") != "" then $stderr
  elif $is_error then ($text // "" | first_line_from_text)
  else (($text // "" | split("\n") | map(select(test("^Error:"))) | .[0]) // "")
  end;

def norm_cmd: (split("\n")[0]) | gsub("[ \t]+"; " ") | sub("^ +"; "") | sub(" +$"; "");

def is_pure_read($cmd): $cmd | test("^ *(cat|ls|grep|find|stat|pwd|which|echo)( |$)");

def title_words:
  ascii_downcase
  | gsub("[^a-z0-9 ]+"; " ")
  | [splits(" +")]
  | map(select(length > 0));

def overlap($ta; $tb):
  ($ta | title_words) as $wa
  | ($tb | title_words) as $wb
  | ($wa + $wb | unique) as $u
  | if ($u|length) == 0 then 0
    else (($wa - ($wa - $wb)) | length) / ($u | length)
    end;

[inputs] as $lines

# --- shared extraction (unchanged from the previously-inline filter) -------
| ($lines
    | map(select(.type=="user" and (.message.content|type)=="array"))
    | map(. as $line
        | $line.message.content[]?
        | select(.type=="tool_result")
        | {
            ts: $line.timestamp,
            tool_use_id: .tool_use_id,
            is_error: (.is_error // false),
            text: (.content | if type=="string" then . else tostring end),
            stderr: ($line.toolUseResult | if type=="object" then .stderr else null end)
          })
  ) as $tool_results
| ($tool_results | map(. + {err_line: err_line_of(.is_error; .stderr; .text)})) as $tool_results2
| ($tool_results2 | map({key: .tool_use_id, value: .}) | from_entries) as $results_by_id
| ($lines
    | map(select(.type=="assistant"))
    | map(. as $line | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | {
        ts: $line.timestamp,
        tool_use_id: .id,
        command: .input.command,
        result: ($results_by_id[.id] // {is_error:false, err_line:""})
      })
  ) as $bash_calls_raw
| ($bash_calls_raw | map({
      ts, command,
      is_error: .result.is_error,
      first_err_line: (.result.err_line | norm_err),
      norm_command: (.command | norm_cmd)
    })) as $bash_calls
| ($bash_calls_raw | map(select(.command | test("git commit"))) | map({ts, command})) as $commits
| ($tool_results2 | map(select(.err_line != "")) | map({ts, err: (.err_line | norm_err)})) as $errors

# --- Heuristic A: retry burst ---------------------------------------------
| ($bash_calls
    | map(select(is_pure_read(.norm_command) | not))
    | group_by(.norm_command)
    | map(select(length >= 3))
    | map({
        heuristic: "retry-burst",
        title: (.[0].norm_command + " — investigated for " + (length|tostring) + " retries."),
        evidence: (.[0:3] | map("Bash @ " + .ts + " → " + (if .is_error then ("exit 1 (\"" + .first_err_line + "\")") else "exit 0" end))),
        evidence_count: length
      })
  ) as $heuristic_a

# --- Heuristic B: revert / reset -------------------------------------------
| ($bash_calls
    | map(select(
        (.command | test("git\\s+reset\\s+--hard"))
        or (.command | test("git\\s+checkout\\s+--\\s"))
        or (.command | test("git\\s+revert"))
        or (.command | test("git\\s+restore"))
        or ((.command | test("rm\\s+-rf\\s+"))
            and (.command as $cmd | $tracked_files | any(. as $f | ($f|length) > 0 and ($cmd | contains($f)))))
      ))
    | map({
        heuristic: "revert",
        title: ("Reverted approach: " + .command + "."),
        evidence: [("Bash @ " + .ts + " → " + .command)],
        evidence_count: 1
      })
  ) as $heuristic_b

# --- Heuristic C: error recurrence -----------------------------------------
| ($errors
    | map(select(.err != ""))
    | group_by(.err)
    | map(select(length >= 3))
    | map(select((((.[-1].ts | to_epoch) - (.[0].ts | to_epoch))) >= 900))
    | map({
        heuristic: "error-recurrence",
        title: (.[0].err + " — recurred " + (length|tostring) + " times over "
                + ((((.[-1].ts | to_epoch) - (.[0].ts | to_epoch)) / 60) | floor | tostring) + " minutes."),
        evidence: (.[0:3] | map("@ " + .ts)),
        evidence_count: length
      })
  ) as $heuristic_c

# --- Heuristic D: fix burst -------------------------------------------------
| ($commits
    | map(select(.command | test("fix(\\([^)]*\\))?:")))
    | map(. as $c
        | ($c.ts | to_epoch) as $c_epoch
        | ($bash_calls | map(select((.ts | to_epoch) < $c_epoch and (.ts | to_epoch) >= ($c_epoch - 1800)))) as $preceding
        | if ($preceding|length) >= 10 then
            {
              heuristic: "fix-burst",
              title: ($c.command + " — fix preceded by " + ($preceding|length|tostring) + "-action investigation."),
              evidence: ([$preceding[0], $preceding[($preceding|length)/2|floor], $preceding[-1]] | map("Bash @ " + .ts)),
              evidence_count: ($preceding|length)
            }
          else empty
          end
      )
  ) as $heuristic_d

# --- union, dedupe by title-word overlap, sort, cap -------------------------
| ($heuristic_a + $heuristic_b + $heuristic_c + $heuristic_d) as $all
| ($all | sort_by(-.evidence_count)) as $sorted_all
| (reduce $sorted_all[] as $cand ([];
      if (. as $kept | any($kept[]; overlap($cand.title; .title) >= 0.7)) then .
      else . + [$cand]
      end
    )) as $deduped
| ($deduped | length) as $total
| ($deduped[0:5] | map(del(.evidence_count))) as $capped
| {
    mode: "transcript",
    candidates: $capped,
    overflow: (if $total > 5 then $total - 5 else 0 end)
  }
```

Create `hooks/lib/candidate-extract.sh`:

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/candidate-extract.sh — LEARNINGS candidate extraction (Change 1).
# See meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md
#
# Usage: candidate-extract.sh <transcript-path>
# Prints one JSON object to stdout:
#   {"mode":"transcript"|"unavailable","candidates":[...],"overflow":N}
# Never fails loud: exit 0 always. Missing/unreadable/empty/stale (>5min)
# transcript, or a missing jq, yields mode:"unavailable" with empty
# candidates.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRANSCRIPT="${1:-}"

emit_unavailable() {
  printf '{"mode":"unavailable","candidates":[],"overflow":0}\n'
  exit 0
}

[[ -n "$TRANSCRIPT" ]] || emit_unavailable
[[ -r "$TRANSCRIPT" ]] || emit_unavailable
[[ -s "$TRANSCRIPT" ]] || emit_unavailable

MTIME_EPOCH="$(stat -f %m "$TRANSCRIPT" 2>/dev/null || stat -c %Y "$TRANSCRIPT" 2>/dev/null || echo "")"
if [[ "$MTIME_EPOCH" =~ ^[0-9]+$ ]]; then
  NOW_EPOCH="$(date -u +%s)"
  AGE=$(( NOW_EPOCH - MTIME_EPOCH ))
  [[ "$AGE" -le 300 ]] || emit_unavailable
fi

command -v jq >/dev/null 2>&1 || emit_unavailable

TRACKED_FILES_JSON="$(git ls-files 2>/dev/null | jq -R -s 'split("\n") | map(select(length>0))' 2>/dev/null || echo "[]")"

RESULT="$(jq -n --argjson tracked_files "$TRACKED_FILES_JSON" \
  -f "$SCRIPT_DIR/candidate-extract.jq" \
  "$TRANSCRIPT" 2>/dev/null)"

[[ -n "$RESULT" ]] || emit_unavailable

printf '%s\n' "$RESULT"
exit 0
```

- [ ] **Step 4: Run the smoke test, confirm it passes**

Run: `chmod +x hooks/lib/candidate-extract.sh && zsh meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh`
Expected: all lines `ok`, `Result: N passed, 0 failed`. If Heuristic A/B/C don't trigger, inspect with:
`bash hooks/lib/candidate-extract.sh <fixture> | jq .` and check `.norm_command`/`.command`/`.err` values against the raw fixture — the most likely break points are the `norm_err` regex (path-collapse) and jq regex escaping (`\\s` inside a double-quoted jq string must literally be backslash-s, verify with `jq -n '"\\s"'` prints `\s`).

- [ ] **Step 5: Replay against archived real transcripts (per spec's Testing plan)**

If real `architect-workbench` transcripts are reachable in this environment (`~/.claude/projects/-Users-*-architect-workbench*/*.jsonl`), run the script against the transcripts behind Finding 1's six gap-dominated runs and two fast runs, and compare the candidate set against what was captured by hand in those sessions' `.session-continuity/LEARNINGS.md` commits from those dates. Note any divergence as either a heuristic-transcription bug (fix it) or a finding about the old prose version (record it, don't silently drop it). This step is exploratory, not a fixed pass/fail assertion — do it manually with `bash hooks/lib/candidate-extract.sh <path> | jq .` and judgment, not as part of the automated smoke test.

- [ ] **Step 6: Commit**

```bash
git add hooks/lib/candidate-extract.jq hooks/lib/candidate-extract.sh meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh
git commit -m "feat: ship LEARNINGS candidate extraction + heuristics A-D as a script"
```

---

### Task 3: Wire `commands/end-session.md` Step 2 to the script

**Files:**
- Modify: `commands/end-session.md:357-471` (Combined extraction pass) and `commands/end-session.md:550-564` (Output) — two disjoint sub-ranges. Everything between them (`### Privacy` and `### Heuristics`, lines 464-548) and everything after (`### Presentation`, lines 566-608) is untouched by this task except for the one-sentence note added to `### Heuristics` in Step 1 below.

**Interfaces:**
- Consumes: `hooks/lib/candidate-extract.sh` (Task 2), `hooks/lib/require-script.sh`'s `require_script` function (Task 1).

- [ ] **Step 1: Replace the combined-extraction-pass and output sections**

The block from `### Combined extraction pass (transcript-file mode only)` (line 357) through the end of that section (line 462, just before `### Privacy` at 464) currently embeds the ~55-line `jq` filter. Replace it with a single script-invocation block. Separately, replace `### Output` (lines 550-564) with a much shorter block that reads from the script's JSON instead of hand-computed heuristic results. Do **not** touch `### Privacy` or `### Heuristics` (lines 464-548, describing what each heuristic decides) — Resolved decision 1's spirit ("prose stays as documentation, explicitly marked non-executable") means the *behavior* description remains for a human reading the file, but the *execution* path changes. Only add one sentence to the top of `### Heuristics` marking it non-executable (below).

Replace lines 357-462 (`### Combined extraction pass (transcript-file mode only)` through the section's end):

With:
````
### Candidate extraction (transcript-file mode only)

Run once, via the shipped script — never re-derive this jq filter or
re-filter the extracted JSON per heuristic (that was the entire cost
problem this replaced; see Finding 2 of
`meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md`).

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-extract.sh" 1; then
  CANDIDATE_JSON="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-extract.sh" "$TRANSCRIPT")"
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
  CANDIDATE_JSON='{"mode":"unavailable","candidates":[],"overflow":0}'
fi
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-2-transcript-extraction --duration="$_PERF_DURATION"
```

Parse `$CANDIDATE_JSON`'s `.mode`, `.candidates[]` (each with `.heuristic`, `.title`, `.evidence[]`), and `.overflow`.
````

Then replace lines 550-564 (`### Output` through its section's end):

```
### Output

- **`mode:"unavailable"`** (script reported it, or the version-skew guard fired above): behave exactly as the prior context-window fallback did — proceed with whatever input source Step 2's own resolution order already selected (context window, if the transcript path itself was never resolved) or, if a transcript path *was* resolved but the script still reported unavailable, treat it the same as zero candidates (print the no-candidates line below) rather than re-deriving anything by hand.
- **`.overflow > 0`**: after the candidate list, append the same `+N more candidates...` line as before, using `.overflow` as N.
- **Zero candidates** (`.candidates` is empty and `.overflow` is 0): print `No LEARNINGS candidates surfaced from this session — Step 2 is a no-op.` and proceed directly to Step 3, same as before.

Render exactly as the `### Presentation` section below already specifies, reading `heuristic`/`title`/`evidence` from each `.candidates[]` entry instead of from hand-computed heuristic results.
```

Leave `### Privacy`, `### Heuristics` (all four subsections), and `### Presentation` untouched, except: add one sentence at the top of `### Heuristics` —

> "The subsections below describe what `hooks/lib/candidate-extract.jq` decides. They are documentation, not an execution path — the agent never re-derives this logic by hand."

- [ ] **Step 2: Manual verification**

Run `/session-continuity:end-session` in this repo (or a scratch repo with a live transcript) and confirm: Step 2 issues exactly one Bash call for extraction (check `.session-continuity/performance.log`'s `step-2-transcript-extraction` entries — there should be one per invocation, not the seven-plus of Finding 2), and the presented candidates match the format shown in the existing `### Presentation` example block.

- [ ] **Step 3: Commit**

```bash
git add commands/end-session.md
git commit -m "refactor: end-session Step 2 delegates candidate extraction to hooks/lib/candidate-extract.sh"
```

---

### Task 4: Agent-active-time script (Change 2)

**Files:**
- Create: `hooks/lib/agent-active.sh`
- Test: `meta/superpowers/validation/2026-09-01-agent-active-smoke.zsh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `hooks/lib/agent-active.sh <transcript-path> <start-epoch>` — prints a single number (seconds, 3 decimals) to stdout, or nothing if the transcript is unreadable/empty. Always exits 0. Task 5 is the consumer.

- [ ] **Step 1: Write the smoke test**

Create `meta/superpowers/validation/2026-09-01-agent-active-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# agent-active.sh smoke test. Hermetic: synthetic JSONL fixtures only.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

jline() { print -r -- "$1"; }

# --- degradation ------------------------------------------------------------

out="$(bash "$lib/agent-active.sh" /no/such/file.jsonl 1000)"
[[ -z "$out" ]] && ok "missing transcript prints nothing" || bad "missing transcript printed: $out"

out="$(bash "$lib/agent-active.sh" "$repo/README.md" not-a-number)"
[[ -z "$out" ]] && ok "non-numeric start_epoch prints nothing" || bad "bad start_epoch printed: $out"

# --- primary mechanism: sum turn_duration.durationMs ------------------------

f1="$(mktemp)"
{
  jline '{"type":"system","subtype":"turn_duration","durationMs":5000,"timestamp":"2026-09-01T00:00:10.000Z"}'
  jline '{"type":"system","subtype":"away_summary","timestamp":"2026-09-01T00:10:00.000Z"}'
  jline '{"type":"system","subtype":"turn_duration","durationMs":3000,"timestamp":"2026-09-01T00:10:05.000Z"}'
} > "$f1"
start_epoch=1
out="$(bash "$lib/agent-active.sh" "$f1" "$start_epoch")"
# 5000ms + 3000ms = 8.000s active, regardless of the ~10-minute away_summary gap between them.
if [[ "$out" == "8.000" ]]; then
  ok "primary mechanism: sums turn_duration.durationMs, excludes the away gap"
else
  bad "primary mechanism: expected 8.000, got '$out'"
fi
rm -f "$f1"

# --- start_epoch filtering ---------------------------------------------------

f2="$(mktemp)"
{
  jline '{"type":"system","subtype":"turn_duration","durationMs":9999,"timestamp":"2020-01-01T00:00:00.000Z"}'
  jline '{"type":"system","subtype":"turn_duration","durationMs":1500,"timestamp":"2026-09-01T00:00:10.000Z"}'
} > "$f2"
start_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-09-01T00:00:00Z' +%s 2>/dev/null || date -u -d '2026-09-01T00:00:00Z' +%s)"
out="$(bash "$lib/agent-active.sh" "$f2" "$start_epoch")"
[[ "$out" == "1.500" ]] && ok "start_epoch filter excludes records before it" || bad "expected 1.500, got '$out'"
rm -f "$f2"

# --- fallback mechanism: no turn_duration records at all --------------------

f3="$(mktemp)"
{
  jline '{"type":"assistant","timestamp":"2026-09-01T00:00:00.000Z"}'
  jline '{"type":"system","subtype":"stop_hook_summary","timestamp":"2026-09-01T00:00:05.000Z"}'
  jline '{"type":"user","timestamp":"2026-09-01T00:10:00.000Z"}'
  jline '{"type":"assistant","timestamp":"2026-09-01T00:10:02.000Z"}'
}  > "$f3"
start_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-09-01T00:00:00Z' +%s 2>/dev/null || date -u -d '2026-09-01T00:00:00Z' +%s)"
out="$(bash "$lib/agent-active.sh" "$f3" "$start_epoch")"
# Fallback sums gaps whose left edge is NOT a turn_duration record:
# assistant->stop_hook_summary (5s, counted) + stop_hook_summary->user (595s,
# NOT counted -- this transcript has no turn_duration record at all, so the
# *only* boundary marker the fallback recognizes is a turn_duration record;
# since none exists, every gap counts, including the 595s one. This fixture
# exists to prove the fallback activates (produces a non-empty number) when
# turn_duration is absent, not to pin an exact value -- see Step 5.
if [[ -n "$out" ]]; then
  ok "fallback mechanism activates when turn_duration is absent (got $out)"
else
  bad "fallback mechanism produced no output"
fi
rm -f "$f3"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `zsh meta/superpowers/validation/2026-09-01-agent-active-smoke.zsh`
Expected: FAIL — script doesn't exist yet.

- [ ] **Step 3: Implement**

Create `hooks/lib/agent-active.sh`:

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/agent-active.sh — agent-active-time derivation (Change 2).
# See meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md
#
# Usage: agent-active.sh <transcript-path> <start-epoch>
# Prints a single number (seconds, 3 decimals) to stdout: time spent inside
# an assistant turn within [start-epoch, now]. Prints nothing and exits 0
# if the transcript is unreadable/empty or start-epoch isn't a plain
# integer — callers must check for empty output before logging
# step-4-agent-active.
#
# Primary mechanism: sums durationMs from every type=="system",
# subtype=="turn_duration" record in range -- the harness's own per-turn
# timer, already excluding idle time. Verified present in both a real
# architect-workbench transcript and this repo's own transcripts (see the
# spec's Change 2). Falls back to a timestamp turn-boundary walk (weaker:
# infers boundaries from record adjacency rather than reading an explicit
# field) only when zero turn_duration records exist in range at all.

set -u

TRANSCRIPT="${1:-}"
START_EPOCH="${2:-}"

[[ -r "$TRANSCRIPT" && -s "$TRANSCRIPT" ]] || exit 0
[[ "$START_EPOCH" =~ ^[0-9]+$ ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

RESULT="$(jq -s --argjson start "$START_EPOCH" '
  def to_epoch: gsub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
  (map(select(.timestamp != null and (.timestamp | to_epoch) >= $start))) as $in_range
  | ($in_range | map(select(.type=="system" and .subtype=="turn_duration"))) as $turns
  | if ($turns | length) > 0 then
      ($turns | map(.durationMs) | add) / 1000
    else
      ($in_range | sort_by(.timestamp | to_epoch)) as $sorted
      | (reduce range(0; (($sorted|length) - 1)) as $i (0;
          . as $acc
          | $sorted[$i] as $a
          | $sorted[$i+1] as $b
          | if ($a.type=="system" and $a.subtype=="turn_duration") then $acc
            else $acc + (($b.timestamp | to_epoch) - ($a.timestamp | to_epoch))
            end
        ))
    end
' "$TRANSCRIPT" 2>/dev/null)"

[[ -n "$RESULT" ]] || exit 0
awk -v v="$RESULT" 'BEGIN{printf "%.3f", v}'
```

- [ ] **Step 4: Run the smoke test, confirm it passes**

Run: `chmod +x hooks/lib/agent-active.sh && zsh meta/superpowers/validation/2026-09-01-agent-active-smoke.zsh`
Expected: all `ok`, `Result: N passed, 0 failed`.

- [ ] **Step 5: Metric-correction pass against real data (per spec's Testing plan)**

If `~/.claude/projects/-Users-*-architect-workbench*/*.jsonl` transcripts are reachable, pick the transcript behind Finding 1's slowest run and run:
`bash hooks/lib/agent-active.sh <path> <that invocation's step-1-fast-path epoch>`
Confirm the result is far smaller than that run's old `step-4-ritual-complete` value (the whole point of the fix), and separately confirm at least one transcript exercises the fallback path for real: `jq -s '[.[] | select(.type=="system" and .subtype=="turn_duration")] | length' <path>` — if any archived transcript returns `0`, that transcript exercises the fallback; note which one for the record. This step is exploratory verification, not part of the automated smoke test.

- [ ] **Step 6: Commit**

```bash
git add hooks/lib/agent-active.sh meta/superpowers/validation/2026-09-01-agent-active-smoke.zsh
git commit -m "feat: add agent-active.sh, replacing the compute-only prompt-wait subtraction"
```

---

### Task 5: Wire `commands/end-session.md` Step 4 to `agent-active.sh`, retire `step-4-compute-only`

**Files:**
- Modify: `commands/end-session.md:775-796` (the compute-only block only — the ritual-complete block at 747-773 is untouched).

**Interfaces:**
- Consumes: `hooks/lib/agent-active.sh` (Task 4), `require_script` (Task 1).

- [ ] **Step 1: Replace the compute-only derivation**

Replace the block starting `**Then derive compute-only time**` (line 775) through its closing code fence (line 796) with:

```
**Then derive agent-active time** — `step-4-ritual-complete` is real wall
clock, but it includes however long the user took to answer any prompts
along the way. Rather than subtract specific prompt-wait markers (the old
approach, retired — see
`meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md`
Change 2 for why a two-marker subtraction can't be made correct), derive
active time directly from the transcript:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if [[ "$start_epoch" =~ ^[0-9]+$ ]] && [[ -n "${TRANSCRIPT:-}" ]]; then
  if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/agent-active.sh" 1; then
    AGENT_ACTIVE="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/agent-active.sh" "$TRANSCRIPT" "$start_epoch")"
    if [[ -n "$AGENT_ACTIVE" ]]; then
      bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-4-agent-active --duration="$AGENT_ACTIVE"
    fi
  else
    echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
  fi
fi
```

If Step 2 never resolved a transcript path (context-window mode, or the
candidate-extraction script reported `mode:"unavailable"`), `$TRANSCRIPT`
is unset and this block is skipped entirely — no `step-4-agent-active` line
is logged for this invocation, same "skip rather than log a wrong number"
rule that already governs the rest of this design.
```

Also update the Notes section: find the bullet that starts with the bold phrase "`step-4-ritual-complete` includes human response time, by design." (line 820). Its final sentence currently says `step-4-compute-only` subtracts prompt-wait entries; change that sentence to describe `step-4-agent-active` deriving active time from the transcript instead, keeping the rest of the bullet (the "compare both numbers before assuming a script regression" guidance) intact.

- [ ] **Step 2: Manual verification**

Run `/session-continuity:end-session` in this repo. Confirm `.session-continuity/performance.log` gets a `step-4-agent-active` line (not `step-4-compute-only`) with a plausible value smaller than `step-4-ritual-complete`.

- [ ] **Step 3: Commit**

```bash
git add commands/end-session.md
git commit -m "refactor: end-session Step 4 uses hooks/lib/agent-active.sh, retires step-4-compute-only"
```

---

### Task 6: LEARNINGS.md derivations script (Change 3)

**Files:**
- Create: `hooks/lib/learnings-index.sh`
- Create: `hooks/lib/learnings-index-report.awk`
- Create: `hooks/lib/learnings-index-bullets.awk`
- Create: `hooks/lib/learnings-index-splice.awk`
- Test: `meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `hooks/lib/learnings-index.sh report <file>` — prints `MAX <n>` then one `DUPNUM <n> <line,line,...>` per duplicated entry number and one `DUPSLUG <slug> <line,line,...>` per duplicated slug.
  - `hooks/lib/learnings-index.sh reindex <file>` — regenerates `## Symptoms index` in `<file>` in place; prints `regenerated <n> bullet(s)` or `no change` to stdout. Idempotent from the first run.
  Tasks 7 and 8 are the consumers.

- [ ] **Step 1: Write the smoke test**

Create `meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# learnings-index.sh smoke test. Hermetic: synthetic + this repo's real
# LEARNINGS.md as fixtures, copied into a temp dir before every mutation.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"

# --- report: no duplicates on this repo's real file -------------------------

cat "$repo/.session-continuity/LEARNINGS.md" > "$work/real.md"
out="$(bash "$lib/learnings-index.sh" report "$work/real.md")"
if print -r -- "$out" | grep -q '^MAX 15$'; then ok "report: MAX matches real file (15)"; else bad "report MAX: $out"; fi
if print -r -- "$out" | grep -q DUPNUM; then bad "report: false-positive duplicate number on real file"; else ok "report: no duplicate numbers on real file"; fi
if print -r -- "$out" | grep -q DUPSLUG; then bad "report: false-positive duplicate slug on real file"; else ok "report: no duplicate slugs on real file"; fi

# --- report: duplicates detected on a synthetic fixture ---------------------

cat > "$work/dup.md" <<'EOF'
# fixture

### 3. one
Slug: foo

**The trap.** x

**Symptom.** x

**Fix.** x

---

### 3. dup-number
Slug: bar

**The trap.** x

**Symptom.** x

**Fix.** x

---

### 4. other
Slug: foo

**The trap.** x

**Symptom.** x

**Fix.** x

---
EOF
out="$(bash "$lib/learnings-index.sh" report "$work/dup.md")"
print -r -- "$out" | grep -q '^DUPNUM 3 ' && ok "report: detects duplicate entry number 3" || bad "report: missed duplicate number: $out"
print -r -- "$out" | grep -q '^DUPSLUG foo ' && ok "report: detects duplicate slug foo" || bad "report: missed duplicate slug: $out"

# --- report: missing file is a silent no-op, not a crash --------------------

out="$(bash "$lib/learnings-index.sh" report "$work/does-not-exist.md")"
[[ "$out" == "MAX 0" ]] && ok "report: missing file -> MAX 0" || bad "report: missing file gave '$out'"

# --- reindex: idempotent from the first run on the real 15-entry file -------

bash "$lib/learnings-index.sh" reindex "$work/real.md" > /dev/null
cp_after1="$(cat "$work/real.md")"
bash "$lib/learnings-index.sh" reindex "$work/real.md" > /dev/null
cp_after2="$(cat "$work/real.md")"
if [[ "$cp_after1" == "$cp_after2" ]]; then
  ok "reindex: idempotent from the first run (real 15-entry file)"
else
  bad "reindex: run 2 differs from run 1 on the real file"
fi
grep -q '^## Symptoms index' "$work/real.md" && ok "reindex: Symptoms index section present" || bad "reindex: no Symptoms index section after reindex"

# --- reindex: inserts a fresh section when none exists (68-entry-file case) -

awk 'BEGIN{skip=0} /^## Symptoms index/{skip=1} skip && /^## / && !/Symptoms index/{skip=0} !skip' \
  "$repo/.session-continuity/LEARNINGS.md" > "$work/virgin.md"
if grep -q '^## Symptoms index' "$work/virgin.md"; then
  bad "fixture setup: virgin.md still has an index (harness bug in this test, not the script)"
fi
bash "$lib/learnings-index.sh" reindex "$work/virgin.md" > /dev/null
if grep -q '^## Symptoms index' "$work/virgin.md"; then
  ok "reindex: inserts a Symptoms index where none existed"
else
  bad "reindex: insert path did not create a Symptoms index"
fi
n_bullets="$(grep -c '^- ' "$work/virgin.md")"
[[ "$n_bullets" -eq 15 ]] && ok "reindex: insert path produced 15 bullets" || bad "reindex: expected 15 bullets, got $n_bullets"
after1="$(cat "$work/virgin.md")"
bash "$lib/learnings-index.sh" reindex "$work/virgin.md" > /dev/null
after2="$(cat "$work/virgin.md")"
[[ "$after1" == "$after2" ]] && ok "reindex: insert path is idempotent from the first run" || bad "reindex: insert path run 2 differs from run 1"

# --- reindex: missing file is a silent no-op --------------------------------

bash "$lib/learnings-index.sh" reindex "$work/does-not-exist.md" > /dev/null
ok "reindex: missing file did not crash"

rm -rf "$work"
print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `zsh meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh`
Expected: FAIL — script doesn't exist yet.

- [ ] **Step 3: Implement**

Create `hooks/lib/learnings-index-report.awk`:

```awk
/^### [0-9]+\./ {
  line = $0
  sub(/^### /, "", line)
  sub(/\..*/, "", line)
  num = line + 0
  cnt[num]++
  lines[num] = (cnt[num] == 1) ? NR : (lines[num] "," NR)
  if (num > max) max = num
}
/^Slug:[ \t]*/ {
  s = $0
  sub(/^Slug:[ \t]*/, "", s)
  gsub(/[ \t]+$/, "", s)
  scnt[s]++
  slines[s] = (scnt[s] == 1) ? NR : (slines[s] "," NR)
}
END {
  print "MAX", max + 0
  for (n in cnt) if (cnt[n] > 1) print "DUPNUM", n, lines[n]
  for (s in scnt) if (scnt[s] > 1) print "DUPSLUG", s, slines[s]
}
```

Create `hooks/lib/learnings-index-bullets.awk`:

```awk
/^### [0-9]+\./ {
  line = $0
  sub(/^### /, "", line)
  sub(/\..*/, "", line)
  num = line + 0
  have_num = 1
}
/^\*\*Symptom\.\*\* / && have_num {
  text = $0
  sub(/^\*\*Symptom\.\*\* /, "", text)
  n = split(text, words, /[ \t]+/)
  lim = (n < 12) ? n : 12
  out = ""
  for (i = 1; i <= lim; i++) out = out (i > 1 ? " " : "") words[i]
  if (n > 12) out = out "…"
  print "- " out " — #" num
  have_num = 0
}
```

Create `hooks/lib/learnings-index-splice.awk`:

```awk
function emit_block() {
  print "## Symptoms index"
  print ""
  print "<!--"
  print "  Fully derived — never hand-edit. The /session-continuity:learning"
  print "  command regenerates this list from every entry's **Symptom.** line"
  print "  each time it appends a new entry."
  print "-->"
  print ""
  while ((getline bline < bfile) > 0) print bline
  close(bfile)
}
BEGIN { replaced = 0; in_old = 0; skip_one_blank = 0 }
/^## Symptoms index/ && !replaced {
  emit_block()
  print ""
  print "---"
  print ""
  in_old = 1
  replaced = 1
  next
}
in_old && /^## / { in_old = 0 }
in_old { next }
!has_index && !replaced && /^---$/ {
  emit_block()
  print ""
  print "---"
  print ""
  replaced = 1
  skip_one_blank = 1
  next
}
skip_one_blank && /^$/ { skip_one_blank = 0; next }
skip_one_blank { skip_one_blank = 0 }
{ print }
```

Create `hooks/lib/learnings-index.sh`:

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/learnings-index.sh — LEARNINGS.md derivations (Change 3).
# See meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md
#
# Usage:
#   learnings-index.sh report <file>    Prints "MAX <n>" then one
#                                        "DUPNUM <n> <lines>" per duplicated
#                                        entry number and one "DUPSLUG
#                                        <slug> <lines>" per duplicated slug.
#   learnings-index.sh reindex <file>   Regenerates "## Symptoms index" in
#                                        place from every entry's
#                                        "**Symptom.**" line. Idempotent
#                                        from the first run. Prints
#                                        "regenerated <n> bullet(s)" or
#                                        "no change".
#
# Never fails loud: a missing/unreadable file makes `report` print "MAX 0"
# and `reindex` a silent no-op. Both exit 0 regardless.
#
# The regenerated index applies this script's own rule (hard 12-word
# cutoff + ellipsis, dictionary-order case-insensitive sort) consistently.
# It does not and should not reproduce a prior hand/LLM-authored index
# byte-for-byte where that index applied looser judgment — see the spec's
# Testing plan, Index script.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBCOMMAND="${1:-}"
FILE="${2:-}"

if [[ ! -r "$FILE" ]]; then
  [[ "$SUBCOMMAND" == "report" ]] && echo "MAX 0"
  exit 0
fi

report() {
  awk -f "$SCRIPT_DIR/learnings-index-report.awk" "$1"
}

reindex() {
  local file="$1" has_index=0 bullets tmp
  grep -q '^## Symptoms index' "$file" && has_index=1
  bullets="$(mktemp)"
  tmp="$(mktemp)"

  awk -f "$SCRIPT_DIR/learnings-index-bullets.awk" "$file" | LC_ALL=C sort -d -f > "$bullets"
  awk -v bfile="$bullets" -v has_index="$has_index" \
    -f "$SCRIPT_DIR/learnings-index-splice.awk" "$file" > "$tmp"

  local n_bullets
  n_bullets="$(wc -l < "$bullets" | tr -d ' ')"

  if diff -q "$file" "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp" "$bullets"
    echo "no change"
  else
    cat "$tmp" > "$file"
    rm -f "$tmp" "$bullets"
    echo "regenerated $n_bullets bullet(s)"
  fi
}

case "$SUBCOMMAND" in
  report)  report "$FILE" ;;
  reindex) reindex "$FILE" ;;
  *) echo "learnings-index.sh: unknown subcommand '$SUBCOMMAND' (report|reindex)" >&2 ;;
esac
exit 0
```

- [ ] **Step 4: Run the smoke test, confirm it passes**

Run: `chmod +x hooks/lib/learnings-index.sh && zsh meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh`
Expected: all `ok`, `Result: N passed, 0 failed`. This exact algorithm was hand-verified against this repo's real 15-entry `LEARNINGS.md` while writing this plan (both the replace-path and a synthetic insert-path fixture derived from it), including two real bugs caught and fixed in that process (an insert-vs-replace single-pass ambiguity, and a double-blank-line artifact) — if this step fails, something about the shipped file differs from what was pasted above; diff carefully rather than assume the algorithm itself is untested.
Real path: the bullets/splice awk logic above, run directly against a scratch copy of this repo's actual `.session-continuity/LEARNINGS.md` (15 real entries), not a synthetic fixture. Stubbed: nothing — same file content a real `reindex` invocation would see.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/learnings-index.sh hooks/lib/learnings-index-report.awk hooks/lib/learnings-index-bullets.awk hooks/lib/learnings-index-splice.awk meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh
git commit -m "feat: add learnings-index.sh for LEARNINGS.md duplicate detection and Symptoms-index regeneration"
```

---

### Task 7: Wire `commands/learning.md` Steps 4 and 6 to the script

**Files:**
- Modify: `commands/learning.md:52-66` (Step 4)
- Modify: `commands/learning.md:98-105` (Step 6)

**Interfaces:**
- Consumes: `hooks/lib/learnings-index.sh` (Task 6), `require_script` (Task 1).

- [ ] **Step 1: Replace Step 4's duplicate-number scan with a script call**

Replace the two numbered sub-steps under `## Step 4 — Compute next number (with uniqueness guard)` that currently say "Scan `.session-continuity/LEARNINGS.md` for **every** `### N.` heading..." and "**Compute next number across all entries.**" with:

```
Run the shared derivation script rather than re-deriving this by hand:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" 1; then
  REPORT="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" report .session-continuity/LEARNINGS.md)"
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
  REPORT=""
fi
```

1. **Detect duplicates first.** If `$REPORT` contains any `DUPNUM` line, refuse to write and report:

   > "LEARNINGS.md has duplicate entry numbers: #X (line A, line B), #Y (line C, line D). Fix the file before appending — pick which entry keeps the number and renumber the other (or merge them). Re-run `/session-continuity:learning` after."

   (Build the message from every `DUPNUM <n> <lines>` line in `$REPORT`.) Exit. Do not append on top of a corrupt file.

2. **Compute next number.** Read `MAX` from `$REPORT` (the `MAX <n>` line). New entry gets `MAX + 1`.

After computing, validate: the chosen number must not already appear in the file (re-run the `report` script call above if a race is suspected). If it does, bump again and re-validate.
```

Keep sub-step 3 ("Validate the slug, if one was accepted") — but replace its scan with: "Check `$REPORT` for a `DUPSLUG <proposed-slug> ...` line. If present, tell the user which entry already owns it..." (same behavior, reading from the script's output instead of a fresh grep).

- [ ] **Step 2: Replace Step 6's regeneration description with a script call**

Replace the four numbered sub-steps under `## Step 6 — Regenerate the Symptoms index` with:

```
Run the shared derivation script after Step 5 has inserted the new entry:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" 1; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" reindex .session-continuity/LEARNINGS.md
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG — Symptoms index not regenerated this run."
fi
```

This regenerates `## Symptoms index` wholesale from every entry's
`**Symptom.**` line (creating the section when absent), applying a hard
12-word cutoff with a trailing "…" if cut, sorted dictionary-order
case-insensitive. Idempotent: running it twice with no new entry in
between produces no change. This section is fully derived — never
hand-edit it.
```

- [ ] **Step 3: Manual verification**

Run `/session-continuity:learning` in this repo with a throwaway title/trap/symptom/fix, confirm the new entry gets the correct next number, the Symptoms index regenerates to include it, and running `/session-continuity:learning` again (or re-running the reindex script directly) doesn't change the index a second time absent a new entry.

- [ ] **Step 4: Commit**

```bash
git add commands/learning.md
git commit -m "refactor: learning.md Steps 4 and 6 delegate to hooks/lib/learnings-index.sh"
```

---

### Task 8: Wire `commands/end-session.md`'s capture flow to call the index script directly

**Files:**
- Modify: `commands/end-session.md:650`

**Interfaces:**
- Consumes: `hooks/lib/learnings-index.sh` (Task 6), `require_script` (Task 1).

- [ ] **Step 1: Add the direct call**

Per Resolved decision 3 (both `learning.md` and end-session's capture flow call the index script directly, rather than end-session delegating through `/session-continuity:learning`), replace:

```
Once the user confirms, insert each accepted draft at the top of its chosen section per **Step 5 of `commands/learning.md`** and stage per **Step 6**: `git add .session-continuity/LEARNINGS.md`.
```

With:

```
Once the user confirms, insert each accepted draft at the top of its chosen section per **Step 5 of `commands/learning.md`**, then run the same index-regeneration script Step 6 of `commands/learning.md` calls (duplicated here deliberately — see Resolved decision 3 of the spec — rather than delegating, so this path can never leave the index stale regardless of whether a future change routes entries differently):

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" 1; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" reindex .session-continuity/LEARNINGS.md
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG — Symptoms index not regenerated this run."
fi
git add .session-continuity/LEARNINGS.md
```
```

- [ ] **Step 2: Manual verification**

Run `/session-continuity:end-session` in a scratch session with a capturable candidate, confirm the Symptoms index regenerates as part of the capture flow without needing a separate `/session-continuity:learning` invocation.

- [ ] **Step 3: Commit**

```bash
git add commands/end-session.md
git commit -m "refactor: end-session capture flow calls learnings-index.sh reindex directly"
```

---

### Task 9: End-to-end validation, CHANGELOG, spec/backlog cross-references

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `.session-continuity/BACKLOG.md` (remove item 5, this work is what it tracked)
- Modify: `.session-continuity/SESSION_PRIMER.md` (per this repo's own convention: refresh alongside the substantive commit that closes this out, not as a standalone commit)

**Interfaces:** none — this task closes the loop, no new code.

- [ ] **Step 1: Full end-to-end run**

In this repo (or a scratch repo with `/session-continuity:primer` already run), execute `/session-continuity:end-session` start to finish. Confirm via `.session-continuity/performance.log`:
- `step-2-transcript-extraction` appears exactly once for this invocation (not the seven-plus of Finding 2).
- `step-4-agent-active` appears (not `step-4-compute-only`).
- No `⚠️ ... contract version mismatch` or `... not found` message appeared (confirms all three new scripts and their CONTRACT_VERSION lines shipped correctly together).

Then execute `/session-continuity:learning` with a throwaway entry and confirm the Symptoms index regenerates and the duplicate/slug guards still work (re-run Task 6/7's manual verification if anything changed since).

- [ ] **Step 2: Add a CHANGELOG entry**

Read `CHANGELOG.md`'s existing format (most recent version's entry) and add a new entry following the same structure, summarizing: candidate extraction and Heuristics A-D now ship as `hooks/lib/candidate-extract.sh` instead of re-executed prose; `step-4-compute-only` is retired in favor of `step-4-agent-active`, derived from the transcript instead of subtracting prompt-wait markers; LEARNINGS.md's duplicate-detection and Symptoms-index regeneration now ship as `hooks/lib/learnings-index.sh`. Reference the spec path.

- [ ] **Step 3: Close backlog item 5**

Remove backlog item 5 from `.session-continuity/BACKLOG.md` per this file's own closing convention ("An item lives here from the moment it's flagged until the moment the code proves it resolved, then it's deleted outright"). First grep the repo for `item #?5\b|outstanding item(s)? 5` to confirm nothing else references it by number before deleting.

- [ ] **Step 4: Refresh the primer and commit everything together**

Update `.session-continuity/SESSION_PRIMER.md`'s current-state/outstanding-items/test-count sections to reflect this change, per this repo's CLAUDE.md instruction to refresh the primer in the same commit as the real change (never a primer-only commit).

```bash
git add CHANGELOG.md .session-continuity/BACKLOG.md .session-continuity/SESSION_PRIMER.md
git commit -m "docs: changelog, backlog, and primer for the Step 2 cost-attribution work"
```
