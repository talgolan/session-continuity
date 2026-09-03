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
