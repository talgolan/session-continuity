# Design: Thin hard-template SESSION_PRIMER.md (engrim + graphify required)

Date: 2026-09-09
Status: approved (brainstorming complete); pending implementation plan
Revised: 2026-09-09 (post caveman-review)

## Problem

`.session-continuity/SESSION_PRIMER.md` was the plugin's volatile
session handoff. Three other systems now cover most of what fat primers
grew into:

| Concern | Owner today |
|---|---|
| Deferred work queue | GitHub Issues labeled `backlog` (`#N`) |
| Durable decisions / facts / feedback / state | engrim |
| Code structure and "how does X work" | graphify (`graphify-out/`) |
| Stable layout / conventions | `PROJECT_CONTEXT.md` |
| Hard-won bug wisdom | `LEARNINGS.md` |

What remains uniquely valuable is a **clone-local, agent-agnostic,
commit-coupled mid-flight narrative** plus **confirm commands** and a
**boot-order contract**. This repo's live primer (~700 lines) proves the
failure mode: without a hard shape, the file becomes a changelog and
competes with `git log`, Issues, and engrim.

Dropping the primer entirely would sacrifice: in-repo mid-flight story,
SessionStart boot nudge keyed on primer presence, pre-commit
refresh ritual, and `/session-continuity:primer` +
`/session-continuity:end-session` presence gates. This design keeps
those mechanics and strips the content contract to what still earns
its keep.

## Goals

1. Keep `.session-continuity/SESSION_PRIMER.md` as the product file name
   (Approach A — no rename to HANDOFF.md).
2. Hard template only: fixed `##` headings, hard line/bullet caps.
   Refresh and doctor refuse unknown sections and banlist content via a
   **deterministic validator** (not agent judgment alone).
3. Treat **engrim** and **graphify** as required peers. Missing either
   at SessionStart or doctor = **hard incomplete** (agent must set up
   before other work).
4. Primer owns only mid-flight + confirm + boot order + peer stubs.
   Never owns backlog bodies, durable memory, or code maps.
5. Existing fat primers migrate in one `/session-continuity:primer`
   slim-migrate shot.
6. Pre-commit nudge and end-session still key off primer presence;
   refresh logic only edits allowed sections.
7. Replace today's doctor staleness check (diff primer's embedded
   `git log --oneline -5` block) with a freshness rule that does not
   require banlist content.

## Non-goals

- Renaming the file or `/session-continuity:primer` command.
- Auto-generating Mid-flight from git / engrim / Issues (Approach C).
- Requiring Obsidian, wiki, Neo4j, or other graphify export flags.
- Replacing or deleting `PROJECT_CONTEXT.md`, `LEARNINGS.md`, or
  `ROADMAP.md`.
- Changing GitHub Issues backlog identity or
  `/session-continuity:backlog`.
- Making `.cursor/RESUME.md` part of the plugin contract (Cursor-local
  optional mirror only; name matches the user's Cursor resume note).
- Soft-warn-only peer probes (rejected — hard incomplete).

## Decisions

- **Approach A.** Slim the file and probe peers in hooks; keep the name.
- **Peers assumed.** Consuming projects are incomplete without engrim
  and graphify. Primer thins hard under that assumption.
- **Hard incomplete.** SessionStart injects a stop instruction;
  doctor fails. Not a soft ⚠️-only path.
- **Hard template.** Fixed sections + caps; refresh refuses extras;
  doctor fails on unknown headings, oversize, or over-cap bullets.
- **Banlist content** moves out or is deleted on migrate: `git log`
  dumps, test-count tables, shipped-history bullets, backlog item
  lists, architecture tours, LEARNINGS copies.
- **Probe definitions (v1) — canonical paths:**
  - **graphify OK** iff `cwd/graphify-out/graph.json` exists and is
    non-empty. That file is the **only** probe target (not
    `GRAPH_REPORT.md`, not wiki, not HTML). Building the graph
    (`/graphify` / `graphify` update) must produce it.
  - **engrim OK** iff a small helper can successfully invoke engrim
    context or recall (MCP tool or documented CLI equivalent). Failure
    or missing binary/tool = not OK. **Plan must land this probe
    before doctor/SessionStart hard-fail wiring** — otherwise CI and
    success criteria are untestable.
- **Size gate:** whole file ≤80 lines **excluding** the fenced Confirm
  code block. Mid-flight ≤5 bullets. Confirm ≤5 commands (see counting
  rule below). Boot order ≤8 lines.
- **Confirm command count:** inside the single ` ```bash ` … ` ``` `
  fence under `## Confirm`, count non-empty lines that do not start
  with `#`. Each such line = one command (including lines that use
  `&&`). No commands outside that fence.
- **Freshness (replaces git-log block compare):** primer is **stale**
  iff there exists at least one commit on `HEAD` after
  `git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md`
  whose touched paths are **substantive** (not solely under
  `.session-continuity/`, not solely `README*` / `CHANGELOG*` /
  `LICENSE*`). Doctor ⚠️ on stale (warn, not hard-fail in v1 — peers
  and shape remain hard-fail). Pre-commit nudge already covers the
  same gap at commit time.
- **Validator script:** `hooks/lib/primer-validate.sh` is the single
  enforcement point. Doctor and `/primer` check/refresh/slim-migrate
  must call it. Agent prose may paraphrase; it may not be the only
  gate.
- **Install order (documented in init output + README):**
  1. `/session-continuity:primer` (init or slim-migrate)
  2. Build graphify → `graphify-out/graph.json`
  3. Ensure engrim usable
  4. `/session-continuity:doctor` green  
  Post-init doctor red until steps 2–3 is expected, not a bug.
- **SessionStart when primer missing:** do **not** stay fully silent.
  Inject a one-line nudge: run `/session-continuity:primer` to init
  (and that engrim + graphify are required peers). Still exit 0; do
  not hard-stop feature work solely for a missing primer (unchanged
  soft posture for uninstalled repos). Hard-stop applies only when
  primer **exists** and a peer probe fails.
- **Copy churn in same change set:** update
  `PROJECT_CONTEXT.md` Maintenance (drop “regenerate git log block”),
  `skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md`,
  `commands/primer.md`, `commands/end-session.md`,
  `commands/doctor.md`, and skill/README blurb so nothing still tells
  agents to maintain banlist content.

## Content contract

Exact shape of the shipped template
(`skills/session-continuity/templates/SESSION_PRIMER.md`):

```markdown
# Session Primer — {{PROJECT_NAME}}

## Boot order
1. `.session-continuity/PROJECT_CONTEXT.md`
2. `.session-continuity/LEARNINGS.md` (grep on surprise)
3. engrim context / recall (required)
4. graphify query when the question is about code structure
5. This file — Mid-flight + Confirm
6. `/session-continuity:backlog` for the deferred queue

## Mid-flight
- …

## Confirm
```bash
…
```

## Peers
- engrim: required — …
- graphify: required — `graphify-out/graph.json`
- backlog: GitHub Issues labeled `backlog`
```

### Section rules

| Section | Rule |
|---|---|
| Title | One H1: `# Session Primer — <project>` |
| `## Boot order` | Fixed intent as above; ≤8 lines; not freeform essays |
| `## Mid-flight` | ≤5 bullets; each names open work + pointer (file/PR/`#N`) + optional one-line trap |
| `## Confirm` | ≤5 counted commands (see counting rule); must falsify Mid-flight if they fail |
| `## Peers` | Three stubs only; status lines may be machine-updated |

**Allowed `##` headings:** exactly `Boot order`, `Mid-flight`,
`Confirm`, `Peers`. Any other `##` → validator fail; refresh refuse.

**Invariant:** a clone without MCP still has Mid-flight text. A boot
without engrim or graphify is incomplete regardless of primer quality.

## Runtime

### New helper: `hooks/lib/peer-probes.sh`

`CONTRACT_VERSION=1`. Best-effort probes, always exit 0, print
key=value lines:

```
ENGRIM=ok|missing|error
GRAPHIFY=ok|missing|error
```

- graphify: test `-s "$DIR/graphify-out/graph.json"` only.
- engrim: invoke the agreed probe (implementation plan picks MCP vs
  CLI; must match what SessionStart can actually call in Claude Code /
  Cursor). Timeout short (~2s). No network beyond what engrim itself
  needs for local recall.

Used by SessionStart and doctor. Single definition — no duplicated
probe prose in command markdown.

### New helper: `hooks/lib/primer-validate.sh`

`CONTRACT_VERSION=1`. Exit 0 = valid shape; non-zero = invalid.
Checks: allowed headings only; line budget (≤80 excluding Confirm
fence); Mid-flight ≤5 bullets; Confirm ≤5 counted commands; no
banlist patterns (e.g. fenced `git log`, “Outstanding items”, embedded
`git log --oneline` blocks). Prints machine-readable reasons on
stderr/stdout for doctor to surface.

Doctor **and** `/primer` refresh/check/slim-migrate invoke this script.
If validate fails, refresh stops and reports the script output — no
“best effort” rewrite past a red validator.

### SessionStart (`hooks/session-start.sh`)

When primer **missing:**

- Inject one-line install nudge (primer + required peers). Exit 0.
  No hard-stop.

When primer **exists:**

1. Run `peer-probes.sh`.
2. If either peer ≠ `ok`: inject hard-stop reminder — do not start
   feature work; set up missing peer(s); doctor will fail. Optionally
   still append backlog shortlist after the stop line.
3. If both `ok`: inject read Mid-flight + Confirm; peers OK; backlog
   shortlist as today; primer freshness line from `primer-status.sh`
   (substantive-commit-since-primer rule above).

### Doctor

**Hard-fail** when any of:

- `primer-validate.sh` non-zero.
- `ENGRIM` or `GRAPHIFY` ≠ `ok`.

**Warn only (⚠️)** when freshness rule says stale.

Remove the current “compare embedded `git log --oneline -5` block”
staleness check — that content is banlisted.

### `/session-continuity:primer`

- **Init:** copy thin template; fill project name; Peers stubs;
  stage. Print install-order blurb (primer → graphify → engrim →
  doctor). Doctor remaining red until peers exist is intentional.
- **Refresh:** run `primer-validate.sh` on the proposed result (or
  validate current + refuse Mid-flight/Confirm only). Rewrite only
  Mid-flight + Confirm (+ Peers status lines). On validator failure,
  stop and show reasons. Do not regenerate git-log blocks or
  test-count tables.
- **Slim-migrate (new):** when fat primer detected (validator fail
  with fat-class reasons, or leftover Outstanding items / inline
  backlog), one-shot rewrite to hard template. Agent selects ≤5
  Mid-flight bullets from the old narrative; remaining open work →
  file as Issues if needed; rest dropped. Validate before stage. No
  dual-write of old sections.
- **Check:** `primer-status.sh` + `primer-validate.sh` + peer probe
  summary.

### Pre-commit nudge

Unchanged trigger (substantive commit, primer not staged). Reminder
text: refresh Mid-flight and Confirm only; do not grow the file.

### `/session-continuity:end-session`

Still requires primer (+ LEARNINGS). Step 1 = thin refresh + re-run
Confirm commands + `primer-validate.sh`. Drop any remaining
instructions that regenerate git-log blocks or treat primer as
changelog.

## Migration

Consuming repos with fat primers:

1. `/session-continuity:primer` (detect → slim-migrate).
2. Review staged thin primer.
3. Ensure `graphify-out/graph.json` exists and engrim is usable.
4. `/session-continuity:doctor` green.

This plugin repo dogfoods the same migrate when implementing.

No markdown backlog fallback (already true post-Issues migration).

## Testing

| Case | Expect |
|---|---|
| Template fixture | passes `primer-validate.sh`; exact four `##` headings |
| Doctor thin + peers ok | pass |
| Doctor fat / unknown heading / >5 bullets / banlist pattern | fail |
| Doctor missing engrim or graphify | fail |
| Doctor stale (substantive commit after primer) | ⚠️ only |
| SessionStart primer missing | one-line init nudge; exit 0 |
| SessionStart peers missing | hard-stop text in stdout |
| SessionStart peers ok | Mid-flight nudge + backlog shortlist |
| Slim-migrate fixture | output passes validator; ≤5 Mid-flight |
| Confirm counting | `#` comments ignored; `&&` line counts as one |

Mock engrim probe in tests; do not require live MCP in CI. Graphify
probe uses a fixture `graphify-out/graph.json` in the scratch repo.
Land mockable engrim probe **before** enabling doctor hard-fail in the
same release train.

## Privacy / product copy

README, help, doctor, and PRIVACY (if peer data is mentioned): one
sentence each that session boot expects local engrim memory and a
local graphify graph (`graphify-out/graph.json`), and that Mid-flight
text is committed to the repo (same class of disclosure as today for
in-repo continuity files).

## Open implementation choices (plan, not design)

Resolved in the implementation plan, not re-litigated here:

1. Exact engrim probe command/API for Claude Code vs Cursor (**must
   be decided in plan Task 1** — blocks doctor hard-fail).
2. Whether Peers status lines are rewritten by SessionStart (file
   mutate) or only injected into the reminder (prefer inject-only in
   v1 to avoid dirty trees on every boot).
3. Version bump and CHANGELOG framing (likely minor: contract change
   for consuming primers).
4. Exact banlist regexes in `primer-validate.sh` (start from: embedded
   `git log`, `## Outstanding`, `BACKLOG.md` item dumps, test-count
   tables).

## Success criteria

- Thin template is the only shipped primer shape.
- Fat content cannot survive `primer-validate.sh` + doctor.
- Cold start with primer present but without engrim or graphify
  cannot look "healthy."
- Cold start with no primer gets an init nudge, not silence.
- Mid-flight still answers "what is open right now?" in one screen.
- Backlog, engrim, and graphify are never re-encoded as primer prose.
- No shipped copy still instructs agents to maintain a primer git-log
  block.
