# Zero-turn read-only commands — Implementation Plan (Phase 1)

Proven-gate: N/A — this is an unexecuted implementation plan. Every task's
checkboxes are unchecked and no code in it has been written or run. Task 1 is
a measurement gate whose results are expected to revise Tasks 2-6; nothing
below claims a working mechanism.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the four read-only commands cost zero model calls and zero
context. Asking for the backlog today costs two model calls (decide to read,
then render) and pulls the whole file into context — `LEARNINGS.md` is 35,562
bytes in this repo for 15 entries whose titles fit in 20 lines. The rendering
rules are also enforced by prompt text rather than by code, which is why
`skills/session-continuity/REFERENCE.md:12` carries a standing instruction
about dropped numbering and missing hex tags.

**Architecture:** Two new layers plus four command stubs. A renderer layer
(`hooks/lib/render.sh` and two `.awk` siblings) turns `BACKLOG.md` and
`LEARNINGS.md` into plain-text lists and absorbs the fixed text that
`commands/help.md` and `commands/update.md` currently ask the model to
assemble. An interception layer (`hooks/prompt-intercept.sh`, the plugin's
first `UserPromptSubmit` hook) matches the whole submitted prompt against a
fixed table and, on a hit, returns `{"decision":"block","reason":"<rendered
list>"}` so the prompt never reaches the model. Every command keeps a working
prompt body as its fallback, so interception failing to fire costs a model
call instead of producing an error — there is no Claude Code version floor.

**Tech Stack:** bash, `jq` (required here, see Global Constraints), POSIX
`awk`, zsh for the smoke runner. No new runtime dependency beyond what
`candidate-extract.sh` already requires.

**Spec:** `meta/superpowers/specs/2026-09-02-zero-turn-read-only-commands-design.md`
— written by Task 1 from measured payloads, not ahead of them. The design
sketch in this plan's header is the input to that spec, not a substitute.

**Program:** this is Phase 1 of
`meta/superpowers/specs/2026-09-02-determinism-program-design.md`, which states
the invariant the whole program serves: no command prompt asks a model to
compute a value that is a pure function of files, git state, or transcript
data. Phase 1 is the only phase that reaches literally zero model calls — the
later phases reduce turns and remove error modes. Phase 0
(`2026-09-02-fresh-install-count-defects.md`) is independent of this plan and
can ship before or after it.

**Decision already settled (do not relitigate):** display-only. A blocked
prompt is erased from context, so the model never sees the rendered list.
Acting on an item afterwards is a normal request in which Claude reads the
file itself. The alternative — injecting the list via `additionalContext` so
the model also sees it — was considered and rejected, because the hooks
reference states `additionalContext` is added "if not blocked" for
`UserPromptSubmit`, making zero-turn and model-visible mutually exclusive on
that event.

## Status: Tasks 2-6 are provisional pending Task 1

Four behaviors are unmeasured, and each one changes the shape of what
follows. Do not start Task 2 before Task 1 has answered all four and the
spec records the payloads. If a measurement contradicts a task below, amend
the task and say so in the spec — do not code around it.

## Global Constraints

- **A false positive is the only unacceptable failure.** Blocking a prompt
  erases it. If the interception layer matches a prompt the user meant for
  the model, real work is silently destroyed with no transcript entry. Every
  ambiguity therefore resolves toward `exit 0`.
- **Match the whole normalized prompt, never a substring.** `show the
  backlog` blocks. `show the backlog and then fix item 3` does not. The
  matcher is an equality test against a fixed table, not a search.
- **Fail open on every uncertainty.** No `jq` on `PATH`, an unparseable
  payload, a renderer exiting non-zero, an empty render — `exit 0` and let
  the prompt proceed, which is exactly today's behavior.
- **`jq` is mandatory in the interception layer, on both directions.**
  Inbound, a user prompt can legitimately contain quotes and newlines, so
  `session-start.sh`'s regex extraction of `cwd` is not a usable pattern
  here. Outbound, the rendered list is multi-line, and
  `gate-common.sh`'s `json_escape` ends with `tr '\000-\037' ' '` — it
  converts newlines to spaces and would flatten every list to one line.
  Build the output with `jq -n --arg`/`--rawfile`, never with `printf`. This
  is the same defect class as the 2026-08-12 hook-JSON escaping fix.
- **The renderer is fence-aware from its first commit.** A `### 9. …` line
  inside a fenced code block is not an entry. `learnings-index-report.awk`
  and `learnings-index-bullets.awk` are both fence-blind (finding F9 of the
  2026-09-01 hardening plan) and LEARNINGS §7 and §13 are both instances of
  grep-based scanning breaking on a file that documents its own syntax. Do
  not inherit that.
- **Renderer scripts follow `hooks/lib/learnings-index.sh` conventions:** a
  `# CONTRACT_VERSION=1` marker on the entry script and on each `.awk`
  sibling, sibling existence and version checked before use, bad input
  (missing or unreadable file) exits 0 with one plain line, broken install
  exits 2 with one line on stderr.
- **`LEARNINGS.md` renders as a title index only.** The file is 35KB; the
  point of this change is to not move 35KB anywhere.
- **Entry order and numbering are not the same thing.** `BACKLOG.md`
  positions are ephemeral display order, recomputed `1..N` on every render.
  `LEARNINGS.md` numbers are permanent and its entries are deliberately not
  in numeric order (the file's sections currently run 11, 8, 2 / 10, 6, 5, 4,
  3 / 14, 12, 13, 9, 7, 1 — newest first, number preserved). Render LEARNINGS
  in file order with numbers verbatim. Sorting it is a bug.
- **Hooks run from `${CLAUDE_PLUGIN_ROOT}`**
  (`~/.claude/plugins/cache/talgolan/session-continuity/<version>/`), not
  from this repo. Sync the cache before any end-to-end check, or the edits
  under test never execute. This is how v0.23.0 shipped without its new code
  path ever running.
- **The `UserPromptSubmit` default timeout is 30 seconds, shorter than the
  600 seconds most events allow, and the hook blocks model processing until
  it returns.** The renderer is `awk` over 35KB, so the budget is not at
  risk, but nothing network-bound or interactive may enter this path.
- Regex portability: `grep -E` only, `sort` always under `LC_ALL=C`.

---

### Task 1: Measure the interception surface (GATE)

Nothing else starts until this finishes. Output is a spec file, not code.

**Files:**
- Create: `meta/superpowers/specs/2026-09-02-zero-turn-read-only-commands-design.md`
- Create (throwaway, deleted at the end of the task): a payload-logging hook
  and a temporary `settings.json` hook registration

**Interfaces:**
- Produces: four measured answers, each with the raw payload pasted into the
  spec. Tasks 2-6 consume them.

- [ ] **Step 1: Sync the plugin cache and confirm which copy runs**

Confirm the running plugin root and that it matches this working tree before
measuring anything. A measurement taken against a stale cache measures the
old version.

- [ ] **Step 2: Register a throwaway logging hook on both events**

A single script registered on `UserPromptSubmit` and on
`UserPromptExpansion` that appends its entire stdin payload plus the event
name to a log file and exits 0. It must alter nothing — no block, no output
on stdout.

- [ ] **Step 3: Measure, and paste every payload into the spec**

1. **Does a typed slash command reach `UserPromptSubmit`, and what is
   `prompt`?** Type `/session-continuity:help` and read the log. If the
   event fires with `prompt` holding the raw `/…` text, one event covers
   both slash commands and natural language and Task 3 needs no second
   entry point. If it does not, slash commands need a `UserPromptExpansion`
   entry matched on `command_name`, and Task 3 grows a second handler.
2. **What is `command_name` for a plugin-scoped command** — `help` or
   `session-continuity:help`? The matcher in `hooks.json` is compared
   against this field, so guessing wrong means the hook silently never
   fires.
3. **How does a multi-line `reason` render, and where does it truncate?**
   Block a throwaway prompt with a `reason` containing 10, 30, and 80 lines.
   Record the ceiling. If a 20-line list does not survive, the LEARNINGS
   render becomes a section-count summary and Task 2's contract changes.
4. **Is `suppressOriginalPrompt` top-level or inside `hookSpecificOutput`?**
   The hooks reference lists it in the same decision-control table as
   `decision` and `reason`, which implies top-level, but the neighboring
   `additionalContext` and `sessionTitle` both live under
   `hookSpecificOutput` in the same table. Measure both placements and
   record which one suppresses the echoed prompt text.

- [ ] **Step 4: Write the spec, then remove the throwaway hook**

The spec records the four answers, the raw payloads, and any amendment the
measurements force on Tasks 2-6. Then unregister and delete the logging hook
and its log — leaving a hook that captures every prompt to a file on disk is
not acceptable.

---

### Task 2: Renderer layer

Independent of Task 1's results except for the `reason` size ceiling. Fully
testable from a shell with no hook involved.

**Files:**
- Create: `hooks/lib/render.sh`
- Create: `hooks/lib/render-backlog.awk`
- Create: `hooks/lib/render-learnings.awk`
- Test: `meta/superpowers/validation/2026-09-02-render-smoke.zsh`

**Interfaces:**
- Produces: `render.sh backlog <project-dir>`, `render.sh learnings
  <project-dir>`, `render.sh help`, `render.sh update` → plain text on
  stdout, exit 0. Exit 2 with one line on stderr on a broken install. Task 3
  consumes stdout and branches on the exit status.

- [ ] **Step 1: `render-backlog.awk`**

Parse `### <position>. [<tag>] [<date>] <Title>` and emit one line per item
as `N [tag] [date] Title`, where `N` is a counter starting at 1 — the
position written in the file is discarded, so gaps and duplicates in the
file self-heal on display. Fence-aware: a heading inside a ``` block is
ignored. Emit nothing for a file with no items; `render.sh` handles the
empty case.

- [ ] **Step 2: `render-learnings.awk`**

Track the current `## <section>` heading. For each `### <n>. <Title>`, emit
the number verbatim and the title, grouped under its section heading, in
file order. Skip the `## Symptoms index` section, which holds bullets rather
than entries. Skip any section that yields no entries — this repo has three
(`## Security incidents`, `## Anti-patterns we were tempted by (and
rejected)`, `## Checklist for a fresh dev-env setup`). Fence-aware, as
above.

- [ ] **Step 3: `render.sh`**

Dispatcher with sibling existence and `CONTRACT_VERSION` checks copied in
shape from `learnings-index.sh`. A missing target file prints one line
naming the file and pointing at `/session-continuity:primer`, and exits 0 —
that is bad input, not a broken install. `help` absorbs the version parse
and the `for`-loop over `commands/*.md` frontmatter descriptions that
`commands/help.md` currently hands the model, plus that command's fixed
reference text. `update` absorbs `commands/update.md`'s fixed text.

- [ ] **Step 4: Smoke test (MANDATORY)**

Fixtures: this repo's real `BACKLOG.md` (7 items) and `LEARNINGS.md` (15
entries, `MAX 15`), plus synthetic files covering non-contiguous positions,
a duplicate position, a heading inside a fence, an empty file, a missing
file, and a missing `.awk` sibling. Follow the existing convention —
`pass`/`fail` counters with `ok`/`bad` helpers, every `bad` message carrying
the mismatched value, and preserve the failing diagnostic in the run log
before teardown so a failure stays diagnosable from the run's own output.

---

### Task 3: Interception layer

**Provisional — shape depends on Task 1 Step 3 answers 1, 2, and 4.**

**Files:**
- Create: `hooks/prompt-intercept.sh`
- Modify: `hooks/hooks.json`
- Test: `meta/superpowers/validation/2026-09-02-prompt-intercept-smoke.zsh`
- Test: `meta/superpowers/validation/2026-08-12-hook-json-contract-smoke.zsh`
  (extend)

**Interfaces:**
- Consumes: `render.sh` from Task 2.
- Produces: a JSON object on stdout carrying `decision: "block"` and the
  rendered list as `reason`, or nothing at all with exit 0.

- [ ] **Step 1: Normalization and the match table**

Normalize the prompt: trim, collapse internal whitespace runs to one space,
lowercase, strip one optional trailing `?` or `.`, strip a leading
`please `. Then test for equality against a fixed table. Initial entries,
to be reviewed with the user before coding:

- backlog — `backlog`, `the backlog`, `backlog list`, `show backlog`,
  `show the backlog`, `show me the backlog`, `list the backlog`,
  `what's in the backlog`
- learnings — `learnings`, `the learnings`, `learnings list`,
  `show the learnings`, `show me the learnings`, `list the learnings`,
  `what's in learnings`

Plus the slash forms, in whichever field Task 1 established carries them.

- [ ] **Step 2: The handler**

Read the payload once. Parse with `jq`; absent `jq` or a parse failure exits
0. On a table hit, call `render.sh`; a non-zero exit or empty output exits 0.
Build the response with `jq -n --arg`/`--rawfile` so the multi-line list is
escaped by a real serializer. Set `suppressOriginalPrompt` in the placement
Task 1 measured, so the user sees the list alone rather than the list plus
an echo of what they typed.

- [ ] **Step 3: Register in `hooks.json`**

A `UserPromptSubmit` entry wrapped in `perf-wrap.sh`, matching how every
other hook here is registered. `perf-wrap.sh` neither reads nor rewrites
stdin or stdout, so the block semantics pass through — the same property
`session-start.sh` already relies on.

- [ ] **Step 4: Extend the hook-JSON contract runner**

`2026-08-12-hook-json-contract-smoke.zsh` exists because a substring assert
on `deny` passes against malformed JSON, which is exactly how two gate
defects shipped green. A multi-line `reason` is the highest-risk JSON this
plugin has ever emitted. Add a fixture that drives `prompt-intercept.sh`
with a real payload and requires its stdout to parse with a real parser.

---

### Task 4: Command stubs with working fallback bodies

**Files:**
- Create: `commands/backlog.md`
- Create: `commands/learnings.md`
- Modify: `commands/help.md`
- Modify: `commands/update.md`

**Interfaces:**
- Consumes: `render.sh` from Task 2, the match table from Task 3.

- [ ] **Step 1: The two new commands**

Frontmatter `description` fields written for the `/help` listing, which
`render.sh help` reads at run time — so the description is authored once, in
the command file, exactly as `commands/help.md` already insists.

- [ ] **Step 2: Fallback bodies that actually work**

Each body is a real prompt: run `render.sh <subcommand>` and print the
output unchanged. When interception fires, the body is never sent. When it
does not fire — an older Claude Code, `jq` absent, a hook misregistered —
the command still returns the right answer for one model call. This is what
removes the version floor, so do not shorten these bodies to a stub that
only makes sense when the hook works.

- [ ] **Step 3: Retrofit `help` and `update`**

Both shrink to the same fallback shape. `commands/help.md`'s fixed reference
text and its description loop move into `render.sh help`; its instruction
"do not re-derive it from `SKILL.md` per invocation" becomes true by
construction rather than by request.

---

### Task 5: Interception smoke test (MANDATORY)

**Files:**
- Create: `meta/superpowers/validation/2026-09-02-prompt-intercept-smoke.zsh`

- [ ] **Step 1: The must-block set**

Every table entry, plus casing and whitespace variants: `Show The Backlog`,
`  backlog  `, `backlog?`, `please show me the backlog`.

- [ ] **Step 2: The must-NOT-block set — equal weight, more important**

Compound requests (`show the backlog and then fix item 3`, `add this to the
backlog`, `is item 3 in the backlog still open`), incidental mentions (`what
does the backlog file look like on disk`), prose that merely contains the
word, and a prompt with embedded quotes and newlines. Each asserts that
stdout is empty and the exit status is 0. A regression here destroys user
work, so these assertions carry the same weight as the positive set.

- [ ] **Step 3: The fail-open set**

`jq` absent from `PATH`, a payload that is not JSON, a payload with no
`prompt` field, and `render.sh` replaced by a stub that exits 2. All four
must produce empty stdout and exit 0. Preserve the failing diagnostic in the
run log before teardown.

---

### Task 6: Docs, changelog, version

**Files:**
- Modify: `README.md`
- Modify: `skills/session-continuity/SKILL.md`
- Modify: `skills/session-continuity/REFERENCE.md`
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.session-continuity/BACKLOG.md`
- Modify: `.session-continuity/SESSION_PRIMER.md`

- [ ] **Step 1: Command count and the new hook**

`SKILL.md` says "seven commands are available" in two places and lists them
inline; that becomes nine. `REFERENCE.md`'s hook table gains
`prompt-intercept.sh` with its fail-open contract stated explicitly, since a
hook that can erase a prompt needs its safety property documented where a
consuming project will read it. `README.md` gains the two commands and a
note that four of them consume no tokens.

- [ ] **Step 2: Keep the numbering instruction, repoint it**

`REFERENCE.md:12`'s standing instruction still governs free-form chat, where
Claude echoes backlog items outside any command. Keep it, and add that
`render.sh backlog` is the canonical renderer whose output it should match.

- [ ] **Step 3: Changelog, version, and repo bookkeeping**

`CHANGELOG.md` entry and a minor bump to `0.26.0` in
`.claude-plugin/plugin.json` (current: `0.25.1` at `b642de4`). File a
`BACKLOG.md` item with a fresh unused 4-hex tag for retrofitting
`/session-continuity:doctor`, the third read-only command with mostly
deterministic output, which this change does not touch. Refresh the primer
in the same commit as the real change, per the plugin's own rule.

## Deliberately out of scope

- `/session-continuity:doctor`. Its checks are deterministic, but it reads
  installation state rather than a repo file, so its renderer is a different
  shape. Backlog item, filed in Task 6.
- Arguments and filters (`/backlog 3`, tag lookup). The mechanism supports
  them — `command_args` is in the payload — but every argument form is a new
  false-positive surface in the match table. Ship the bare lists first.
