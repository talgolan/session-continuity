# Zero-turn read-only commands — Design (Task 1 measurement results)

Proven-gate: N/A — this is a design/spec document recording empirical
measurements, not source code with tests to run.

This spec records the four measurements Task 1 of
`meta/superpowers/plans/2026-09-02-zero-turn-read-only-commands.md` required
before Tasks 2-6 could start, plus the amendments those measurements force
on the plan. It amends, and does not relitigate, that plan's architecture.

## Method

Measured headlessly, not by typing into an interactive TUI session. A
scratch git repo at a throwaway path was driven with:

```
claude -p "<prompt>" \
  --plugin-dir <this repo's worktree> \
  --settings <throwaway settings.json registering a logging/blocking hook> \
  --output-format json --permission-mode bypassPermissions
```

A throwaway hook script logged every `UserPromptSubmit` and
`UserPromptExpansion` payload verbatim to a log file (deleted after this
task, along with the scratch repo and the hook). A second throwaway hook
selectively returned a `decision:"block"` JSON body to test rendering and
suppression. `claude -p --output-format json` reports `num_turns` and
`total_cost_usd` for the whole invocation, which is the most direct evidence
available that a blocked prompt truly never reached the model — both read
`0` on every blocking test below.

**Caveat:** this measures the `-p`/headless contract, not an interactive TUI
session. The hook event contract is documented as the same surface in both
modes; this was not independently re-verified inside an interactive session
in this task.

## Measurement 1 — Does a slash command reach `UserPromptSubmit`, and what is `prompt`?

**Yes.** Typing `/session-continuity:help` fires `UserPromptSubmit` with
`prompt` holding the raw, unexpanded slash text:

```json
{"session_id":"82a4ed38-...","transcript_path":"...","cwd":"/private/tmp/sc-measure","prompt_id":"54f6b474-...","permission_mode":"bypassPermissions","hook_event_name":"UserPromptSubmit","prompt":"/session-continuity:help"}
```

**Consequence for Task 3:** one event, `UserPromptSubmit`, covers both
natural-language phrasing and literal slash-command text. No second entry
point on `UserPromptExpansion` is needed. The matcher's normalized-prompt
table gains the literal slash forms (`/session-continuity:backlog`,
`/session-continuity:learnings`, and so on) as additional table rows,
matched the same way as the natural-language rows.

## Measurement 2 — What is `command_name` for a plugin-scoped command?

**`UserPromptExpansion` fires first (same turn, logged before
`UserPromptSubmit`) and carries `command_name: "session-continuity:help"`
— plugin-scoped, colon-separated, no leading slash:**

```json
{"session_id":"82a4ed38-...","transcript_path":"...","cwd":"/private/tmp/sc-measure","prompt_id":"54f6b474-...","permission_mode":"bypassPermissions","hook_event_name":"UserPromptExpansion","expansion_type":"slash_command","command_name":"session-continuity:help","command_args":"","command_source":"plugin","prompt":"/session-continuity:help"}
```

**But `UserPromptSubmit`'s own payload has no `command_name` field at
all** — see Measurement 1's payload above; its only relevant field is
`prompt`. The plan's Task 3 Step 1 anticipated matching on whichever field
carried the slash form; that field turned out to be the same `prompt`
string `UserPromptSubmit` already exposes for natural language, not a
separate `command_name` lookup.

**Consequence for Task 3:** the matcher never reads `command_name` — it
does not exist on the event the matcher runs on. Match purely on the
normalized `prompt` string, adding literal slash-command text as table
entries per Measurement 1.

## Measurement 3 — How does a multi-line `reason` render, and where does it truncate?

**No truncation or corruption observed at 10, 30, or 80 lines.** Each test
blocked a throwaway prompt with a `reason` of exactly N lines
(`line-<i>-of-<n>-reason-content`); the CLI's reported `result` text
contained all N lines verbatim in every case, byte-exact, no ellipsis, no
truncation marker:

- 10 lines: 10/10 present.
- 30 lines: 30/30 present.
- 80 lines: 80/80 present, 2355 bytes, last line `line-80-of-80-reason-content` intact.

**Consequence for Task 2:** no ceiling was found inside the range tested.
The largest real render this plan produces is a `LEARNINGS.md` title index
(15 entries, well under 80 lines, likely under 20 lines / ~1.2KB by the
`N <n>. <Title>` format). This is comfortably inside the measured-safe
range. Nothing amends Task 2's contract on this basis — proceed with a
title-index render as planned, not a section-count summary.

## Measurement 4 — Is `suppressOriginalPrompt` top-level or inside `hookSpecificOutput`?

**Inside `hookSpecificOutput`, not top-level.** This contradicts the
implied top-level placement in the hooks reference (which lists it
alongside `decision`/`reason` in the same table, distinct from where
`additionalContext`/`sessionTitle` are shown nested). Both placements were
tested with an identical 10-line reason:

**Top-level (`{"decision":"block","reason":"...","suppressOriginalPrompt":true}`)
— did NOT suppress.** The CLI appended the original prompt regardless:

```
UserPromptSubmit operation blocked by hook:
line-1-of-10-reason-content
...
line-10-of-10-reason-content

Original prompt: MEASURE_BLOCK_10
```

**Nested (`{"decision":"block","reason":"...","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","suppressOriginalPrompt":true}}`)
— suppressed correctly.** Identical reason, no `Original prompt:` trailer:

```
UserPromptSubmit operation blocked by hook:
line-1-of-10-reason-content
...
line-10-of-10-reason-content
```

**Consequence for Task 3:** `prompt-intercept.sh` must nest
`suppressOriginalPrompt` under `hookSpecificOutput` alongside
`hookEventName: "UserPromptSubmit"`, matching the shape validated above.
No other code in this repo currently sets `suppressOriginalPrompt` (grepped
clean), so this is a new-code correction, not a fix to an existing bug.

## End-to-end confirmation: blocking a real slash command costs zero turns

Beyond the four required measurements, one additional check: does blocking
`UserPromptSubmit` *after* `UserPromptExpansion` has already fired actually
prevent the plugin's real `/session-continuity:help` command body from
running? Re-ran the nested-placement block hook against the literal prompt
`/session-continuity:help` (with `--plugin-dir` pointed at this plugin, so
the command genuinely resolves):

```json
{"num_turns":0,"total_cost_usd":0,"is_error":false,"subtype":"success","result":"UserPromptSubmit operation blocked by hook:\nline-1-of-5-reason-content\n..."}
```

`num_turns:0`, `total_cost_usd:0`. `UserPromptExpansion` firing first does
not commit the session to running the expanded command — a subsequent
`UserPromptSubmit` block still short-circuits before any model call. This
is the mechanism Phase 1 depends on; it holds.

## Amendments to Tasks 2-6

- **Task 3 Step 1 (match table):** drop any plan to read `command_name`.
  Match on normalized `prompt` text only. Add literal slash-command strings
  (`/session-continuity:backlog`, `/session-continuity:learnings`, and the
  slash forms of `help`/`update`) as additional table rows alongside the
  natural-language phrasings already listed in the plan.
- **Task 3 Step 2 (the handler):** set `suppressOriginalPrompt` nested
  under `hookSpecificOutput.suppressOriginalPrompt`, with
  `hookSpecificOutput.hookEventName` set to `"UserPromptSubmit"` — not
  top-level. This is the one placement verified to work.
- **Task 2 (renderer):** no change. The 80-line no-truncation result gives
  ample margin over the ~15-20 line real renders; a title-index contract
  is confirmed sufficient.
- **No change forced on Task 4, 5, or 6** beyond carrying the corrected
  match-table shape and JSON shape from Tasks 2-3 through their consumers
  and tests.

## Cleanup

Scratch repo, throwaway hooks, and hook log were all deleted after this
task (`rm -rf` on a `/tmp` scratch path created solely for this
measurement — nothing under this repo).
