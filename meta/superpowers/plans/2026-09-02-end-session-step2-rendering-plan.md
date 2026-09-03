# end-session Step 2 — rendering and reference relocation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/session-continuity:end-session` Step 2's ~160-line unconditional prompt load (heuristics documentation + JSON-to-markdown formatting rules) conditional — loaded only in context-window mode — by scripting extraction-result rendering and transcript resolution, and relocating the heuristics prose to a file read on demand.

**Architecture:** Two new sibling scripts in `hooks/lib/`: `resolve-transcript.sh` (prints the resolved transcript path, or nothing) and `candidate-render.sh` (reads `candidate-extract.sh`'s JSON on stdin, prints the finished user-facing block, or a one-line `SC-FALLBACK: context-window — <detail>` sentinel when there is no script-derived answer). `commands/end-session.md` Step 2 becomes a three-script pipeline plus one branch on that sentinel; the heuristics documentation moves to a new `skills/session-continuity/HEURISTICS.md`, read only when the sentinel fires. Step 4's `agent-active.sh` call site also switches to on-demand transcript resolution, because it currently depends on a `$TRANSCRIPT` shell variable set in a different Bash tool call than the one that reads it, and shell state does not persist across Bash tool calls.

**Tech Stack:** Bash, jq, zsh (smoke tests only).

**Spec:** `meta/superpowers/specs/2026-09-02-end-session-step2-rendering-design.md`

**Evidence-gate:** N/A — no poll/wait loop appears in this plan's smoke-test design (Task 6's regression pass is a fixed one-shot loop over a known runner list, no retry/wait). The word "polling" appears only inside relocated heuristic-A documentation (Task 3/Task 4) describing command-repetition detection, unrelated to test design.

## Global Constraints

- Every new script prints best-effort output and **always exits 0** — this sits inside a ritual that must never abort (spec: "Design" intro, "Testing").
- Every new script invoked from `commands/end-session.md` carries a `# CONTRACT_VERSION=N` header comment and is called through `require_script` (from `hooks/lib/require-script.sh`), exactly like `candidate-extract.sh`, `learnings-index.sh`, and `agent-active.sh` already are. New scripts start at `CONTRACT_VERSION=1`.
- `candidate-extract.sh` and `candidate-extract.jq` are **not modified** — their contract (`CONTRACT_VERSION=2`) is left alone, and the existing `meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh` must keep passing **unchanged**, byte-for-byte, as the proof of that (spec: "Testing").
- The renderer treats `evidence` array entries as opaque, pre-formatted strings and prints them as-is — it must never re-derive, reformat, or assume a shape across heuristics (spec: "Two defects found while reading the source").
- Do not fix the `overlap()` dedupe asymmetry (BACKLOG item `c9a4`) as part of this work — out of scope, spec: "Out of scope".
- Do not touch Step 3's checklist assembly (BACKLOG item `b93c`/Phase 4) or the four duplicated epoch-subtraction blocks (BACKLOG item `a17f`/Phase 3) — out of scope, spec: "Out of scope".
- New shipped reference file is `skills/session-continuity/HEURISTICS.md`, not `skills/session-continuity/REFERENCE.md` and not anything under `meta/` (spec: "Where the heuristics documentation goes").

---

## File Structure

| File | Responsibility |
|---|---|
| `hooks/lib/resolve-transcript.sh` (new) | Resolve the current session's transcript path from `pwd`, or print nothing. No staleness check (that stays in `candidate-extract.sh`). |
| `hooks/lib/candidate-render.sh` (new) | Read `candidate-extract.sh`'s JSON contract on stdin, print the finished Step 2 user-facing block, or the `SC-FALLBACK:` sentinel. |
| `skills/session-continuity/HEURISTICS.md` (new) | The four heuristics' definitions, the privacy rule, and the by-hand Presentation spec — read only in context-window mode. |
| `commands/end-session.md` (modified) | Step 2 becomes the three-script pipeline + one branch on the sentinel. Step 4's agent-active block resolves the transcript on demand instead of reading Step 2's `$TRANSCRIPT`. |
| `meta/superpowers/validation/2026-09-02-resolve-transcript-smoke.zsh` (new) | Smoke test for the resolver. |
| `meta/superpowers/validation/2026-09-02-candidate-render-smoke.zsh` (new) | Smoke test for the renderer, per fixture list in spec "Testing". |
| `CHANGELOG.md` (modified) | New version entry. |

---

### Task 1: `resolve-transcript.sh`

**Files:**
- Create: `hooks/lib/resolve-transcript.sh`
- Test: `meta/superpowers/validation/2026-09-02-resolve-transcript-smoke.zsh`

**Interfaces:**
- Produces: `bash hooks/lib/resolve-transcript.sh` — no arguments, reads `$HOME` and `pwd`. Prints the resolved transcript path (one line, no trailing content) on stdout, or prints nothing. Always exits 0.

- [ ] **Step 1: Write the failing smoke test**

Create `meta/superpowers/validation/2026-09-02-resolve-transcript-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# resolve-transcript.sh smoke test. Hermetic: synthetic $HOME and cwd dirs;
# the real ~/.claude/projects is never touched.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

fake_home="$(mktemp -d)"
proj_cwd_raw="$(mktemp -d)"
# Resolve symlinks (e.g. macOS /tmp -> /private/tmp) so the encoded path we
# assert against matches what the script itself computes via `pwd`.
proj_cwd="$(cd "$proj_cwd_raw" && pwd)"
encoded="$(print -r -- "$proj_cwd" | sed 's#/#-#g')"
sess_dir="$fake_home/.claude/projects/$encoded"

run_it() {
  ( export HOME="$fake_home"
    cd "$proj_cwd" || exit 1
    bash "$lib/resolve-transcript.sh" )
}

# --- no ~/.claude/projects dir at all ----------------------------------------
out="$(run_it)"
[[ -z "$out" ]] && ok "no ~/.claude/projects dir -> prints nothing" \
  || bad "expected empty, got: $out"

# --- projects dir exists, encoded subdir does not ----------------------------
mkdir -p "$fake_home/.claude/projects"
out="$(run_it)"
[[ -z "$out" ]] && ok "no matching encoded-cwd dir -> prints nothing" \
  || bad "expected empty, got: $out"

# --- encoded dir exists, no .jsonl files --------------------------------------
mkdir -p "$sess_dir"
: > "$sess_dir/notes.txt"
out="$(run_it)"
[[ -z "$out" ]] && ok "encoded dir with no .jsonl -> prints nothing" \
  || bad "expected empty, got: $out"

# --- one .jsonl file -----------------------------------------------------------
: > "$sess_dir/session-a.jsonl"
out="$(run_it)"
[[ "$out" == "$sess_dir/session-a.jsonl" ]] && ok "single .jsonl -> resolves it" \
  || bad "expected $sess_dir/session-a.jsonl, got: $out"

# --- newest of several .jsonl files wins --------------------------------------
: > "$sess_dir/session-b.jsonl"
touch -t 202001010000 "$sess_dir/session-a.jsonl" 2>/dev/null \
  || touch -mt 202001010000 "$sess_dir/session-a.jsonl"
touch -t 202601010000 "$sess_dir/session-b.jsonl" 2>/dev/null \
  || touch -mt 202601010000 "$sess_dir/session-b.jsonl"
out="$(run_it)"
[[ "$out" == "$sess_dir/session-b.jsonl" ]] && ok "picks newest-mtime .jsonl" \
  || bad "expected $sess_dir/session-b.jsonl, got: $out"

rm -rf "$fake_home" "$proj_cwd_raw"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x meta/superpowers/validation/2026-09-02-resolve-transcript-smoke.zsh
zsh meta/superpowers/validation/2026-09-02-resolve-transcript-smoke.zsh
```

Expected: FAIL — `hooks/lib/resolve-transcript.sh` does not exist yet, every case errors or prints nothing/wrong.

- [ ] **Step 3: Write `hooks/lib/resolve-transcript.sh`**

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/resolve-transcript.sh — resolve the current session's transcript
# path. See meta/superpowers/specs/2026-09-02-end-session-step2-rendering-design.md.
#
# Usage: resolve-transcript.sh
# Prints the resolved transcript path on stdout, or nothing, and always
# exits 0 — best-effort, no error path. An empty result feeds
# candidate-extract.sh an empty path, which itself reports
# mode:"unavailable"; that is the one fallback path, not a second one here.
#
# Resolution: encode `pwd` with '/' -> '-' (a leading '/' becomes a leading
# '-'), look under ~/.claude/projects/<encoded-cwd>/, and pick the .jsonl
# file with the newest mtime. Prints nothing if that directory does not
# exist or holds no .jsonl file.
#
# Staleness (>5min) is NOT checked here. candidate-extract.sh already checks
# it and must stay correct when handed a path from any source, so that check
# stays the one place responsible for it.

set -uo pipefail

# Same GNU/BSD stat ordering trap as candidate-extract.sh: GNU stat's -f
# means --file-system and writes to stdout while exiting 1, so the BSD form
# must never be tried first inside a command substitution.
mtime_epoch() {
  local v
  v="$(stat -c %Y "$1" 2>/dev/null)"
  [[ "$v" =~ ^[0-9]+$ ]] && { printf '%s' "$v"; return 0; }
  v="$(stat -f %m "$1" 2>/dev/null)"
  [[ "$v" =~ ^[0-9]+$ ]] && { printf '%s' "$v"; return 0; }
  return 1
}

encoded="$(pwd | sed 's#/#-#g')"
dir="$HOME/.claude/projects/$encoded"

[[ -d "$dir" ]] || exit 0

best=""
best_mtime=-1
for f in "$dir"/*.jsonl; do
  [[ -e "$f" ]] || continue
  m="$(mtime_epoch "$f")" || continue
  [[ "$m" =~ ^[0-9]+$ ]] || continue
  if (( m > best_mtime )); then
    best_mtime="$m"
    best="$f"
  fi
done

[[ -n "$best" ]] && printf '%s\n' "$best"
exit 0
```

```bash
chmod +x hooks/lib/resolve-transcript.sh
```

- [ ] **Step 4: Run the smoke test to verify it passes**

```bash
zsh meta/superpowers/validation/2026-09-02-resolve-transcript-smoke.zsh
```

Expected: `Result: 5 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/resolve-transcript.sh meta/superpowers/validation/2026-09-02-resolve-transcript-smoke.zsh
git commit -m "feat: add resolve-transcript.sh, resolving the session transcript path on demand"
```

---

### Task 2: `candidate-render.sh`

**Files:**
- Create: `hooks/lib/candidate-render.sh`
- Test: `meta/superpowers/validation/2026-09-02-candidate-render-smoke.zsh`

**Interfaces:**
- Consumes: JSON on stdin matching `candidate-extract.sh`'s contract — `{"mode":"transcript"|"unavailable"|"error","candidates":[{"heuristic":"…","title":"…","evidence":["…"]}],"overflow":N,"detail":"…"}`.
- Produces: the finished Step 2 user-facing text block on stdout, or a single line beginning `SC-FALLBACK: context-window — <detail>`. Always exits 0.

- [ ] **Step 1: Write the failing smoke test**

Create `meta/superpowers/validation/2026-09-02-candidate-render-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# candidate-render.sh smoke test. Hermetic: fixture JSON on stdin only — no
# transcript, no git state.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

render() { print -rn -- "$1" | bash "$lib/candidate-render.sh"; }

# --- malformed JSON on stdin must not crash, must fall back -------------------
out="$(render 'not json at all')"
[[ "$out" == SC-FALLBACK:* ]] && ok "malformed JSON -> SC-FALLBACK" \
  || bad "expected SC-FALLBACK, got: $out"

# --- mode:unavailable -----------------------------------------------------------
out="$(render '{"mode":"unavailable","candidates":[],"overflow":0,"detail":"the transcript is stale."}')"
[[ "$out" == "SC-FALLBACK: context-window — the transcript is stale." ]] \
  && ok "mode:unavailable -> SC-FALLBACK carrying detail" \
  || bad "got: $out"

# --- mode:error -------------------------------------------------------------------
out="$(render '{"mode":"error","candidates":[],"overflow":0,"detail":"jq is not installed."}')"
[[ "$out" == "⚠️ LEARNINGS candidates unavailable: jq is not installed." ]] \
  && ok "mode:error -> warning line with detail verbatim" \
  || bad "got: $out"

# --- detail containing quotes and a newline ---------------------------------------
detail_json='{"mode":"error","candidates":[],"overflow":0,"detail":"failed on \"weird\" input\nsecond line"}'
out="$(render "$detail_json")"
expected='⚠️ LEARNINGS candidates unavailable: failed on "weird" input
second line'
[[ "$out" == "$expected" ]] && ok "detail with embedded quotes and a newline renders verbatim" \
  || bad "got: $out"

# --- zero candidates, mode:transcript ---------------------------------------------
out="$(render '{"mode":"transcript","candidates":[],"overflow":0,"detail":""}')"
[[ "$out" == "No LEARNINGS candidates surfaced from this session — Step 2 is a no-op." ]] \
  && ok "zero candidates -> the no-op line" \
  || bad "got: $out"

# --- one candidate, command-bearing evidence (heuristic A shape) -----------------
one='{"mode":"transcript","candidates":[{"heuristic":"retry-burst","title":"bun test — re-run 3 times with 1 file edits in between.","evidence":["Bash @ 2026-09-01T00:00:00Z → failed: FAIL","Bash @ 2026-09-01T00:01:00Z → ok"]}],"overflow":0,"detail":""}'
out="$(render "$one")"
expected="LEARNINGS candidates from this session:

1. [retry-burst] bun test — re-run 3 times with 1 file edits in between.
   Evidence:
   - Bash @ 2026-09-01T00:00:00Z → failed: FAIL
   - Bash @ 2026-09-01T00:01:00Z → ok

Capture any? (1, 2, 3, all, none, or describe another)"
[[ "$out" == "$expected" ]] && ok "single candidate renders the numbered list exactly" \
  || bad "got: $out"

# --- all four heuristic ids, mixed bare-timestamp vs command-bearing evidence -----
four='{"mode":"transcript","candidates":[
  {"heuristic":"retry-burst","title":"T-A","evidence":["Bash @ t1 → ok"]},
  {"heuristic":"revert","title":"T-B","evidence":["Bash @ t2 → git checkout -- x"]},
  {"heuristic":"error-recurrence","title":"T-C","evidence":["@ t3","@ t4"]},
  {"heuristic":"fix-burst","title":"T-D","evidence":["Bash @ t5 → git commit"]}
],"overflow":0,"detail":""}'
out="$(render "$four")"
expected="LEARNINGS candidates from this session:

1. [retry-burst] T-A
   Evidence:
   - Bash @ t1 → ok

2. [revert] T-B
   Evidence:
   - Bash @ t2 → git checkout -- x

3. [error-recurrence] T-C
   Evidence:
   - @ t3
   - @ t4

4. [fix-burst] T-D
   Evidence:
   - Bash @ t5 → git commit

Capture any? (1, 2, 3, all, none, or describe another)"
[[ "$out" == "$expected" ]] && ok "all four heuristic ids render, bare-ts and command-bearing evidence both printed plainly" \
  || bad "got: $out"

# --- overflow > 0 appends the +N more candidates line -----------------------------
ov='{"mode":"transcript","candidates":[{"heuristic":"retry-burst","title":"T","evidence":["e1"]}],"overflow":2,"detail":""}'
out="$(render "$ov")"
[[ "$out" == *"+2 more candidates not shown — capture these first, then re-run /session-continuity:end-session."* ]] \
  && ok "overflow>0 appends the +N more candidates line" \
  || bad "got: $out"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x meta/superpowers/validation/2026-09-02-candidate-render-smoke.zsh
zsh meta/superpowers/validation/2026-09-02-candidate-render-smoke.zsh
```

Expected: FAIL — `hooks/lib/candidate-render.sh` does not exist yet.

- [ ] **Step 3: Write `hooks/lib/candidate-render.sh`**

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/candidate-render.sh — renders candidate-extract.sh's JSON into the
# user-facing Step 2 block.
# See meta/superpowers/specs/2026-09-02-end-session-step2-rendering-design.md.
#
# Usage: candidate-extract.sh <transcript> | candidate-render.sh
# Reads one JSON object on stdin — the extractor's contract:
#   {"mode":"transcript"|"unavailable"|"error","candidates":[...],
#    "overflow":N,"detail":"..."}
# — and prints the finished user-facing block on stdout. Always exits 0: a
# rendering failure must fall back to context-window mode, never abort the
# ritual.
#
#   mode:"transcript", candidates present -> numbered list, indented evidence
#     bullets, the "+N more…" line when overflow>0, the capture prompt.
#   mode:"transcript", no candidates, no overflow -> the single no-op line.
#   mode:"error" -> "⚠️ LEARNINGS candidates unavailable: <detail>", verbatim.
#   mode:"unavailable", or unparseable/unrecognized stdin -> one line:
#     "SC-FALLBACK: context-window — <detail>"
#
# The caller's only branch: if the output starts with "SC-FALLBACK:", switch
# to context-window mode; otherwise print the output verbatim.

set -uo pipefail

INPUT="$(cat)"

fallback() {  # <detail>
  printf 'SC-FALLBACK: context-window — %s\n' "$1"
  exit 0
}

command -v jq >/dev/null 2>&1 || fallback "jq is not installed."

if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  fallback "malformed candidate JSON."
fi

MODE="$(printf '%s' "$INPUT" | jq -r 'if (type=="object" and (.mode|type)=="string") then .mode else "" end')"

case "$MODE" in
  error)
    DETAIL="$(printf '%s' "$INPUT" | jq -r '.detail // "unknown error"')"
    printf '⚠️ LEARNINGS candidates unavailable: %s\n' "$DETAIL"
    exit 0
    ;;
  unavailable)
    DETAIL="$(printf '%s' "$INPUT" | jq -r '.detail // "the transcript is unavailable."')"
    fallback "$DETAIL"
    ;;
  transcript)
    ;;
  *)
    fallback "unrecognized mode '${MODE:-<none>}'."
    ;;
esac

printf '%s' "$INPUT" | jq -r '
  def render_candidate($i; $c):
    (($i+1)|tostring) + ". [" + $c.heuristic + "] " + $c.title + "\n"
    + "   Evidence:\n"
    + ([$c.evidence[] | "   - " + .] | join("\n"));

  (.candidates // []) as $cands
  | ((.overflow // 0)) as $overflow
  | if ($cands | length) == 0 and $overflow == 0 then
      "No LEARNINGS candidates surfaced from this session — Step 2 is a no-op."
    else
      "LEARNINGS candidates from this session:\n\n"
      + ([range(0; $cands|length) as $i | render_candidate($i; $cands[$i])] | join("\n\n"))
      + "\n"
      + (if $overflow > 0 then
           "\n+" + ($overflow|tostring) + " more candidates not shown — capture these first, then re-run /session-continuity:end-session.\n"
         else "" end)
      + "\nCapture any? (1, 2, 3, all, none, or describe another)"
    end
'
```

```bash
chmod +x hooks/lib/candidate-render.sh
```

- [ ] **Step 4: Run the smoke test to verify it passes**

```bash
zsh meta/superpowers/validation/2026-09-02-candidate-render-smoke.zsh
```

Expected: `Result: 8 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/candidate-render.sh meta/superpowers/validation/2026-09-02-candidate-render-smoke.zsh
git commit -m "feat: add candidate-render.sh, scripting Step 2's JSON-to-markdown rendering"
```

---

### Task 3: Relocate heuristics documentation to `HEURISTICS.md`

**Files:**
- Create: `skills/session-continuity/HEURISTICS.md`

**Interfaces:**
- Produces: a file `commands/end-session.md` points to (Task 4) for context-window-mode Step 2 behavior. No script reads this file — it is for a model to read on demand.

- [ ] **Step 1: Create `skills/session-continuity/HEURISTICS.md`**

```markdown
# LEARNINGS candidate heuristics (context-window fallback)

Read this file only when `/session-continuity:end-session`'s Step 2 has no
script-derived answer — `candidate-render.sh` printed a line starting
`SC-FALLBACK:`. In transcript-file mode, `hooks/lib/candidate-extract.jq`
already decided all of this and `hooks/lib/candidate-render.sh` already
rendered it. The subsections below exist so a reader can audit that output
without reading jq — they are not instructions for that path.

In context-window mode there is no script and no transcript to run it
against. There, and only there, apply the rules below by hand against what
you can still see in the conversation, skipping the wall-clock gates you
cannot evaluate.

## Privacy

Heuristic candidates' "evidence" bullets paraphrase tool inputs; they
never quote raw stdout/stderr beyond the first error line of any
failing tool call. Never include full prompt text, full command
output, or any value that could plausibly be a secret. When in
doubt, paraphrase.

## Heuristic A — retry burst

Commands are grouped by **full normalized text** — every run of whitespace,
newlines included, collapsed to a single space. A heredoc's body is part of its
identity, so two commits with different messages are two commands, not two runs
of one.

Near-variants merge on a **family key**: digits following a `-` or `=` are
rewritten to `N`, so `tail -8` and `tail -15` are one family, while
`gh pr merge 22` and `gh pr merge 24` are not (that digit follows a space).

Bookkeeping commands never count: `cat`, `ls`, `grep`, `rg`, `find`, `stat`,
`pwd`, `which`, `echo`, `printf`, `wc`, `head`, `tail`, `sed`, `awk`, `jq`,
`du`, `file`, `date`, `env`, `tree`, `mkdir`, `touch`, `chmod`, `open`, and
`git status|diff|log|show|branch|add|commit|stash|rev-parse|ls-files` — tested
after stripping a leading `cd <path> &&`, `timeout <n>`, or `env VAR=x`.

**Trigger:** one command family appears ≥3 times AND at least one `Edit`,
`Write`, or `MultiEdit` call falls between the first and last occurrence. A
command repeated with no intervening edit is polling, not investigation.

**Candidate title:** `<command> — re-run N times with M file edits in between.`

**Evidence:** up to 3 timestamps, each annotated `ok` or `failed: <first error line>`.

## Heuristic B — revert / reset

**Trigger:** in `bash_calls`, any invocation matching one of:

- `git reset --hard`
- `git checkout -- <path>`
- `git revert`
- `git restore`
- `rm -rf <path>` where `<path>` appears in `git ls-files` output
  (i.e. a tracked file, not a tmp directory).

A git verb counts only at a **command position** — the start of the command, or
directly after `&&`, `;`, or `|`. A command that merely contains the string
`git revert` (a jq program filtering for it, say) is not a revert. The `rm -rf`
branch requires a tracked path to appear as an actual argument token, or as a
parent directory of one, not as a substring anywhere in the command.

**Candidate title:** `Reverted approach: <the matched segment, ≤76 chars>.` The
segment, not the head of the command — a real `git checkout -- <path>` was found
sitting behind two unrelated `tmux kill-session` calls.

**Evidence:** the offending Bash invocation.

## Heuristic C — error recurrence

The error string comes from any tool result that either carries `is_error: true`
or whose body opens with `Exit code <non-zero>`. Within that body, the first
line matching an error vocabulary (`error`, `fail`, `fatal`, `cannot`, `no such`,
`not found`, `no matches`, `denied`, `refused`, `unexpected`, `invalid`,
`missing`) wins over the first line of output, because the first line of a
failing `bun test` is its version banner. Capped at 160 characters, and at 120
in the title. Normalized: home directories
rewritten to `~/`, absolute paths reduced to basenames, `:line:col` refs,
ISO-8601 and `HH:MM:SS` timestamps, and hex addresses stripped.

**Trigger:** the same normalized error appears ≥2 times spanning ≥5 minutes.

**Candidate title:** `<error string> — recurred N times over M minutes.`

**Evidence:** up to 3 invocation citations spanning the timeline.

## Heuristic D — fix burst

**Trigger:** a commit whose **parsed subject** — from `-m "…"`, `-m '…'`, or
the first non-empty line of a `<<'EOF'` body — matches `^fix(\(…\))?: `, AND
whose preceding 30 minutes contain ≥10 non-bookkeeping Bash calls, AND among
those a command family repeated ≥3 times.

**Candidate title:** `<commit subject> — fix preceded by a N-action investigation.`
The subject only — never the raw command, which on a real commit runs to 20
lines including the trailer.

**Evidence:** the commit invocation + a representative sample of the
preceding burst (3 citations, evenly spaced through the 30-minute
window).

## Presentation (context-window mode only)

Render candidates as a numbered list with `[heuristic-id]` annotations and
indented evidence bullets:

```
LEARNINGS candidates from this session:

1. [retry-burst] <title>
   Evidence:
   - <evidence bullet>
   - <evidence bullet>

2. [error-recurrence] <title>
   Evidence:
   - <evidence bullet>

Capture any? (1, 2, 3, all, none, or describe another)
```

The `[heuristic-id]` tag is one of: `retry-burst`, `revert`,
`error-recurrence`, `fix-burst`. Always include it — it tells the user which
signal triggered the candidate. Enumerate every candidate found — never
summarize multiple candidates into one line or silently drop one to keep the
list short.

If more than 5 candidates triggered, cap at 5 (no heuristic contributing more
than 2) and append:

```
+N more candidates not shown — capture these first, then re-run /session-continuity:end-session.
```

If zero candidates are found, skip the prompt entirely and print `No
LEARNINGS candidates surfaced from this session — Step 2 is a no-op.`, then
note "no new learnings" in Step 3's checklist.

Then append, always (this file is reached only in context-window mode):

```
Note: session context may be compacted; some early-session events may not have surfaced.
```
```

- [ ] **Step 2: Verify all four heuristics and both required sections are present**

```bash
grep -c '^## Heuristic ' skills/session-continuity/HEURISTICS.md
grep -c '^## Privacy$' skills/session-continuity/HEURISTICS.md
grep -c '^## Presentation' skills/session-continuity/HEURISTICS.md
```

Expected: `4`, `1`, `1`.

- [ ] **Step 3: Commit**

```bash
git add skills/session-continuity/HEURISTICS.md
git commit -m "docs: relocate LEARNINGS heuristics documentation to HEURISTICS.md"
```

---

### Task 4: Rewrite `commands/end-session.md` Step 2

**Files:**
- Modify: `commands/end-session.md` (the span from `## Step 2 — Session reflection for learnings` through the end of the old `### Presentation` section, immediately before `### Capture flow — batch presentation, single confirm`)

**Interfaces:**
- Consumes: `hooks/lib/resolve-transcript.sh` (Task 1), `hooks/lib/candidate-render.sh` (Task 2), `skills/session-continuity/HEURISTICS.md` (Task 3), and the unchanged `hooks/lib/candidate-extract.sh`.
- Produces: `$RENDERED` (a shell variable holding the rendered block or the `SC-FALLBACK:` sentinel) and `$TRANSCRIPT` (the resolved path, possibly empty), both scoped to Step 2's own Bash call — nothing downstream may assume either survives into a later Bash call (see Task 5).

- [ ] **Step 1: Replace the Step 2 section**

Using the Edit tool, replace this exact block (currently `commands/end-session.md` lines 322–552):

```markdown
## Step 2 — Session reflection for learnings

Apply four explicit heuristics to surface LEARNINGS candidates from
this session. Each heuristic emits zero-or-more candidates; the union
is presented to the user, deduplicated by title, capped at 5.

### Input source

Prefer the session transcript file when accessible; fall back to the
context window when not. Transcript file location:

```
~/.claude/projects/<url-encoded-cwd>/<session-id>.jsonl
```

URL-encoding rule: `/` → `-`, leading `/` becomes leading `-`. Example
cwd `/Users/tal.golan/repo` → directory `-Users-tal-golan-repo`.

**Resolution order:**

1. Compute the expected directory from `pwd` using the encoding rule.
2. If the directory exists, pick the `.jsonl` file with the most
   recent mtime — this is assumed to be the live session.
3. Fall back to context-window mode if any of: the directory does not
   exist, no `.jsonl` files inside, or the most-recent file's mtime
   is older than 5 minutes (stale, probably the wrong session).
4. Best-effort. Any failure falls through to context-window mode
   without error.

When in transcript-file mode, prefer `grep`/`wc`/`jq` via Bash to
filter relevant entries (Bash tool calls, errors, commits) before
pulling raw JSON into context. JSONL files for long sessions can be
megabytes — do not Read the whole file into context.

When in context-window mode, note the limitation in the candidate
output: "session context may be compacted; some early-session events
may not have surfaced." Do not pretend to have full visibility.

### Candidate extraction (transcript-file mode only)

Run once, via the shipped script — never re-derive this jq filter or
re-filter the extracted JSON per heuristic (that was the entire cost
problem this replaced; see Finding 2 of
`meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md`).

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-extract.sh" 2; then
  CANDIDATE_JSON="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-extract.sh" "$TRANSCRIPT")"
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
  CANDIDATE_JSON='{"mode":"error","candidates":[],"overflow":0,"detail":"candidate-extract.sh is missing or outdated."}'
fi
```

The script times itself — do not wrap this call in a timer, and do not add a
`perf-log.sh record` line for `step-2-transcript-extraction`; you would
double-log it.

Parse `$CANDIDATE_JSON`'s `.mode`, `.candidates[]` (each with `.heuristic`,
`.title`, `.evidence[]`), `.overflow`, and `.detail`.

### Privacy

Heuristic candidates' "evidence" bullets paraphrase tool inputs; they
never quote raw stdout/stderr beyond the first error line of any
failing tool call. Never include full prompt text, full command
output, or any value that could plausibly be a secret. When in
doubt, paraphrase.

### Heuristics

`hooks/lib/candidate-extract.jq` decides all of this. The subsections below
record what it decides so a reader can audit the output without reading jq —
they are **not instructions to you**. In transcript-file mode you have already
received the finished candidate list from the script; do not re-derive, re-filter,
or re-check any of it. Re-deriving these by hand is what made this step cost
~88 seconds of round trips before the script existed (Finding 2 of the design
spec).

In context-window mode there is no script and no transcript to run it against.
There, and only there, apply the rules below by hand against what you can still
see in the conversation, skipping the wall-clock gates you cannot evaluate.

#### Heuristic A — retry burst

Commands are grouped by **full normalized text** — every run of whitespace,
newlines included, collapsed to a single space. A heredoc's body is part of its
identity, so two commits with different messages are two commands, not two runs
of one.

Near-variants merge on a **family key**: digits following a `-` or `=` are
rewritten to `N`, so `tail -8` and `tail -15` are one family, while
`gh pr merge 22` and `gh pr merge 24` are not (that digit follows a space).

Bookkeeping commands never count: `cat`, `ls`, `grep`, `rg`, `find`, `stat`,
`pwd`, `which`, `echo`, `printf`, `wc`, `head`, `tail`, `sed`, `awk`, `jq`,
`du`, `file`, `date`, `env`, `tree`, `mkdir`, `touch`, `chmod`, `open`, and
`git status|diff|log|show|branch|add|commit|stash|rev-parse|ls-files` — tested
after stripping a leading `cd <path> &&`, `timeout <n>`, or `env VAR=x`.

**Trigger:** one command family appears ≥3 times AND at least one `Edit`,
`Write`, or `MultiEdit` call falls between the first and last occurrence. A
command repeated with no intervening edit is polling, not investigation.

**Candidate title:** `<command> — re-run N times with M file edits in between.`

**Evidence:** up to 3 timestamps, each annotated `ok` or `failed: <first error line>`.

#### Heuristic B — revert / reset

**Trigger:** in `bash_calls`, any invocation matching one of:

- `git reset --hard`
- `git checkout -- <path>`
- `git revert`
- `git restore`
- `rm -rf <path>` where `<path>` appears in `git ls-files` output
  (i.e. a tracked file, not a tmp directory).

A git verb counts only at a **command position** — the start of the command, or
directly after `&&`, `;`, or `|`. A command that merely contains the string
`git revert` (a jq program filtering for it, say) is not a revert. The `rm -rf`
branch requires a tracked path to appear as an actual argument token, or as a
parent directory of one, not as a substring anywhere in the command.

**Candidate title:** `Reverted approach: <the matched segment, ≤76 chars>.` The
segment, not the head of the command — a real `git checkout -- <path>` was found
sitting behind two unrelated `tmux kill-session` calls.

**Evidence:** the offending Bash invocation.

#### Heuristic C — error recurrence

The error string comes from any tool result that either carries `is_error: true`
or whose body opens with `Exit code <non-zero>`. Within that body, the first
line matching an error vocabulary (`error`, `fail`, `fatal`, `cannot`, `no such`,
`not found`, `no matches`, `denied`, `refused`, `unexpected`, `invalid`,
`missing`) wins over the first line of output, because the first line of a
failing `bun test` is its version banner. Capped at 160 characters, and at 120
in the title. Normalized: home directories
rewritten to `~/`, absolute paths reduced to basenames, `:line:col` refs,
ISO-8601 and `HH:MM:SS` timestamps, and hex addresses stripped.

**Trigger:** the same normalized error appears ≥2 times spanning ≥5 minutes.
(Measured on real transcripts: a multi-megabyte session carries 5-8 error
results total, so the previous ≥3-over-15-minutes threshold could never fire.)

**Candidate title:** `<error string> — recurred N times over M minutes.`

**Evidence:** up to 3 invocation citations spanning the timeline.

#### Heuristic D — fix burst

**Trigger:** a commit whose **parsed subject** — from `-m "…"`, `-m '…'`, or
the first non-empty line of a `<<'EOF'` body — matches `^fix(\(…\))?: `, AND
whose preceding 30 minutes contain ≥10 non-bookkeeping Bash calls, AND among
those a command family repeated ≥3 times. Without that cluster the fix was
straightforward and there is nothing to learn; with the cluster requirement,
one measured session went from 8 fix-burst candidates to 3.

**Candidate title:** `<commit subject> — fix preceded by a N-action investigation.`
The subject only — never the raw command, which on a real commit runs to 20
lines including the trailer.

**Evidence:** the commit invocation + a representative sample of the
preceding burst (3 citations, evenly spaced through the 30-minute
window).

### Output

- **`mode:"unavailable"`**: the transcript could not be used (absent, stale,
  unreadable). Fall back to context-window mode exactly as before, and append
  the compaction note to the candidate list.
- **`mode:"error"`**: the plugin or its environment is broken — print
  `⚠️ LEARNINGS candidates unavailable: <detail>` using `.detail` verbatim,
  then continue to Step 3. Do **not** silently treat this as "no candidates";
  a derivation that fails invisibly is the failure this whole design exists to
  prevent.
- **`.overflow > 0`**: append the `+N more candidates…` line as before. Note
  that no heuristic contributes more than 2 of the 5 shown, so an overflow can
  mean "one signal fired many times", not "there are 5 better ones hidden".
- **Zero candidates** (`.candidates` empty, `.overflow` 0, `mode:"transcript"`):
  print `No LEARNINGS candidates surfaced from this session — Step 2 is a no-op.`

Render exactly as the `### Presentation` section below already specifies, reading `heuristic`/`title`/`evidence` from each `.candidates[]` entry instead of from hand-computed heuristic results. Enumerate every entry in `.candidates[]` — the example below shows three numbered entries to illustrate the format, not a cap; if `.candidates[]` holds four or five entries, print all four or five. Never summarize multiple candidates into one line or silently drop one to keep the list short.

### Presentation

Render candidates as a numbered list with `[heuristic-id]` annotations
and indented evidence bullets. Format:

```
LEARNINGS candidates from this session:

1. [retry-burst] `bun test 2>&1 | tail -10` — re-run 31 times with 112 file edits in between.
   Evidence:
   - Bash @ 2026-09-01T00:12:04Z → failed: FAIL src/foo.test.ts
   - Bash @ 2026-09-01T00:19:41Z → failed: FAIL src/foo.test.ts
   - Bash @ 2026-09-01T00:26:02Z → ok

2. [error-recurrence] "<normalized error string>" — recurred N times over M minutes.
   Evidence: N Bash invocations across <paraphrased context>; resolved by <paraphrased fix>.

3. [revert] Reverted approach: `git checkout -- docs/history.jsonl.`
   Evidence:
   - Bash @ 2026-09-01T00:05:12Z → tmux kill-session -t smoke 2>/dev/null; git checkout -- docs/history.jsonl; echo done

Capture any? (1, 2, 3, all, none, or describe another)
```

The `[heuristic-id]` tag is one of: `retry-burst`, `revert`,
`error-recurrence`, `fix-burst`. Always include it — it tells the
user which signal triggered the candidate.

If the cap fired (more than 5 triggered), append after the list:

```
+N more candidates not shown — capture these first, then re-run /session-continuity:end-session.
```

If you find **zero** candidates, skip the prompt entirely and print
`No LEARNINGS candidates surfaced from this session — Step 2 is a no-op.`
to the user, then note "no new learnings" in Step 3's checklist.

If the input source was context-window (transcript file unavailable),
append a single line under the list:

```
Note: session context may be compacted; some early-session events may not have surfaced.
```
```

with:

```markdown
## Step 2 — Session reflection for learnings

Apply four explicit heuristics to surface LEARNINGS candidates from
this session. Each heuristic emits zero-or-more candidates; the union
is presented to the user, deduplicated by title, capped at 5.

### Resolve, extract, and render

Three scripts, one pipeline. Never re-derive the jq filter, re-filter the
extracted JSON per heuristic, or hand-format the result — that was the
entire cost problem this replaced; see Finding 2 of
`meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md`.

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"

TRANSCRIPT=""
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/resolve-transcript.sh" 1; then
  TRANSCRIPT="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/resolve-transcript.sh")"
fi

if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-extract.sh" 2; then
  CANDIDATE_JSON="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-extract.sh" "$TRANSCRIPT")"
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
  CANDIDATE_JSON='{"mode":"error","candidates":[],"overflow":0,"detail":"candidate-extract.sh is missing or outdated."}'
fi

if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-render.sh" 1; then
  RENDERED="$(printf '%s' "$CANDIDATE_JSON" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-render.sh")"
else
  RENDERED="SC-FALLBACK: context-window — $SC_REQUIRE_SCRIPT_MSG"
fi
```

`candidate-extract.sh` times itself — do not wrap this call in a timer, and
do not add a `perf-log.sh record` line for `step-2-transcript-extraction`;
you would double-log it.

### Privacy

Relevant only in context-window mode — see
`skills/session-continuity/HEURISTICS.md`. Transcript-mode evidence is
already redacted by `candidate-extract.jq` before it reaches you.

### Output

`$RENDERED` starts with `SC-FALLBACK:` in exactly the cases where there is no
script-derived answer: no transcript, a stale or unreadable one, a
missing/outdated script, or extractor output the renderer could not parse.
That is your one branch:

- **`$RENDERED` starts with `SC-FALLBACK:`** — switch to context-window mode.
  Apply the heuristics in `skills/session-continuity/HEURISTICS.md` by hand
  against what you can still see in the conversation, skipping the
  wall-clock gates you cannot evaluate, render the result following that
  file's Presentation section, and append this line under the list:

  ```
  Note: session context may be compacted; some early-session events may not have surfaced.
  ```

- **Otherwise, print `$RENDERED` verbatim.** It is already the finished
  user-facing block: either the numbered candidate list with evidence
  bullets, a capture prompt, and (if candidates were capped) a `+N more
  candidates…` line; or the single no-op line `No LEARNINGS candidates
  surfaced from this session — Step 2 is a no-op.` (note "no new learnings"
  in Step 3's checklist when this is what printed); or `⚠️ LEARNINGS
  candidates unavailable: <detail>` when the plugin or its environment is
  broken. Do **not** treat the last case as "no candidates" — continue to
  Step 3 regardless.

If `$RENDERED` was the no-op line or the `⚠️` line, skip the capture prompt
entirely — there is nothing to capture.
```

- [ ] **Step 2: Verify the old heuristics prose is gone and the new pipeline is present**

```bash
grep -c '#### Heuristic A' commands/end-session.md
grep -c 'candidate-render.sh' commands/end-session.md
grep -c 'HEURISTICS.md' commands/end-session.md
```

Expected: `0`, at least `1`, at least `1`.

- [ ] **Step 3: Regression — run the existing extractor smoke test unchanged**

```bash
zsh meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh
```

Expected: same pass count as before this task (the extractor and its filter were not touched).

- [ ] **Step 4: Commit**

```bash
git add commands/end-session.md
git commit -m "refactor: end-session Step 2 pipes through candidate-render.sh, relocates heuristics prose"
```

---

### Task 5: On-demand transcript resolution in Step 4

**Files:**
- Modify: `commands/end-session.md` (the "Then derive agent-active time" block and its following paragraph, in Step 4)

**Interfaces:**
- Consumes: `hooks/lib/resolve-transcript.sh` (Task 1). Does **not** consume Step 2's `$TRANSCRIPT` — that variable is scoped to a different Bash tool call, and per the Bash tool's own contract shell state does not persist across calls.
- Produces: `$STEP4_TRANSCRIPT`, scoped to Step 4's own Bash call.

- [ ] **Step 1: Replace the Step 4 agent-active block**

Using the Edit tool, replace this exact block (currently `commands/end-session.md` lines 731–757):

```markdown
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

with:

```markdown
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

If `resolve-transcript.sh` prints nothing (no readable `.jsonl` under this
session's transcript directory, or the script is missing/outdated), this
block is skipped entirely — no `step-4-agent-active` line is logged for
this invocation, same "skip rather than log a wrong number" rule that
already governs the rest of this design.
```

- [ ] **Step 2: Verify no dangling reference to Step 2's `$TRANSCRIPT` remains in Step 4**

```bash
grep -n '\$TRANSCRIPT' commands/end-session.md
```

Expected: only the occurrence inside Step 2's own block (the `resolve-transcript.sh`/`candidate-extract.sh` pipeline written in Task 4) — no occurrence inside Step 4.

- [ ] **Step 3: Commit**

```bash
git add commands/end-session.md
git commit -m "fix: end-session Step 4 resolves the transcript on demand instead of reading Step 2's shell variable"
```

---

### Task 6: Full regression pass and changelog

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run every smoke runner touched or exercised by this plan**

```bash
for f in \
  meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh \
  meta/superpowers/validation/2026-09-01-require-script-smoke.zsh \
  meta/superpowers/validation/2026-09-02-resolve-transcript-smoke.zsh \
  meta/superpowers/validation/2026-09-02-candidate-render-smoke.zsh \
  meta/superpowers/validation/2026-09-01-agent-active-smoke.zsh
do
  echo "--- $f ---"
  zsh "$f" || echo "FAILED: $f"
done
```

Expected: every runner ends `0 failed`.

- [ ] **Step 2: Add a CHANGELOG entry**

Add a new section at the top of `CHANGELOG.md`, directly under the `# Changelog` header and its description line, above `## [0.26.0]`:

```markdown
## [0.27.0] — 2026-09-02

### Changed
- **`end-session` Step 2's heuristics documentation and JSON-to-markdown formatting rules are now conditional, not unconditional.** Roughly 160 of `commands/end-session.md`'s 790 lines described what `hooks/lib/candidate-extract.jq` already decides and handed the model a formatting job it did unreliably (three anti-drift instructions existed because of it). Two new sibling scripts, `hooks/lib/resolve-transcript.sh` and `hooks/lib/candidate-render.sh`, now resolve the transcript path and render the finished candidate block; the relocated heuristics prose lives in the new `skills/session-continuity/HEURISTICS.md`, read only when there is no script-derived answer (no transcript, a stale/unreadable one, or a missing/outdated script). Step 4's `agent-active.sh` call now resolves the transcript on demand as well, instead of depending on a shell variable set in Step 2's separate Bash call.
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog entry for the Step 2 rendering and reference relocation"
```
