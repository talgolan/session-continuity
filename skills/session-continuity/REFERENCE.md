# Session Continuity — Reference

Detail split out of `SKILL.md` to keep the skill itself a short operational
quick-ref. Read this when you need gate internals, customization guidance,
the full decision tree, or the philosophy behind the five-file pattern —
not on every session.

## Hooks and content gates

`hooks/hooks.json` wires up several non-blocking and blocking hooks:

- **`session-start.sh`** (SessionStart) — reminds Claude to read the primer, and injects the backlog shortlist. **Standing rule: whenever you discuss or echo backlog to the user — in this reminder, in `/session-continuity:end-session`'s prompts, or in free-form chat when directly asked — render them as a numbered list, always starting at 1, never 0, with each item's permanent `[hex tag]` shown alongside its number, e.g. `1 [a3f9]`.** Paraphrasing the list into unnumbered prose (e.g. "same question stand: X or Y") drops the numbering the user relies on to reply with a bare number. This applies even to a one-line summary reply — number it, tag it, don't collapse it, and don't zero-index it.
- **`pre-commit-check.sh`** (PreToolUse, before `git commit`) — non-blocking nudge when code is staged without a primer refresh.
- **`learnings-surface.sh`** (PreToolUse, before Bash/Write/Edit) — the retrieval hook: surfaces any LEARNINGS entry carrying a `Trigger: <tool> /<regex>/` line when the imminent action matches, so the lesson lands *before* the mistake instead of after.

The six content gates below all fire at **commit time**, not on save:
each one is a `PreToolUse` hook scoped to `Bash(git commit *)` that
scans the files already staged in the git index, not the `Write`/`Edit`
payload. Iterate on a spec/plan/LEARNINGS file freely — a `Write` or
`Edit` never gets blocked — and the gate only asks its question when
you run `git commit`, naming the offending staged file in its denial.
(`git commit -a` and pathspec commits are a documented, accepted
permissive miss — see CHANGELOG `[0.17.0]` and LEARNINGS.)

- **`smoke-gate.sh`** — blocks a staged plan file that touches binary/engine work but lacks a MANDATORY smoke task.
- **`proven-gate.sh`** — blocks a staged spec/plan's "proven"/"verified" claim unless it also names the real path exercised and what was stubbed.
- **`occurrence-gate.sh`** — blocks a staged LEARNINGS entry recording a 2nd-or-later occurrence of a mistake-class unless it also names the end-state invariant.
- **`evidence-gate.sh`** — blocks a staged spec/plan's smoke design if it tears down before capturing failure evidence, or polls for success only.
- **`flaky-gate.sh`** — blocks a commit message or staged LEARNINGS entry that calls a failure "flaky"/"transient" without naming the deterministic mechanism behind it.
- **`backend-parity-gate.sh`** — blocks a staged plan that frames its smoke coverage as multi-backend but names only one concrete backend.

Every blocking gate has an explicit skip-with-reason escape hatch (e.g.
`Smoke: N/A — <reason>`) documented in that hook's own header comment.
The escape line tolerates markdown decoration — `> **Smoke:** N/A —
<reason>` (blockquote, bold) works exactly like the bare
`Smoke: N/A — <reason>` form; only the `Label:`, `N/A`, and a dash then
a non-blank reason are required, wrapped in any combination of `>`,
`#`, `**`, or `` ` ``. The escape hatch is **file-scoped, not
entry-scoped** — one `Gate: N/A` line in a LEARNINGS.md whitelists the
whole file for that gate, not just the entry it's attached to.

`proven-gate.sh` specifically: rather than escaping a real
"proven"/"verified" claim, prefer meeting its requirement directly —
add two fields next to the claim, `Real path: <which production code
path actually ran>` and `Stubbed: <what stood in, or "nothing">`. If
the stubbed thing is the feature under test, the claim isn't proven;
say so instead of asserting it.

## What goes where — a decision tree

| Observation | Where it goes |
|---|---|
| "The latest commit is X" | `.session-continuity/SESSION_PRIMER.md` → Current state |
| "We should follow up on X" | `.session-continuity/BACKLOG.md` → new numbered entry |
| "How is this repo laid out" | `.session-continuity/PROJECT_CONTEXT.md` → Repo layout |
| "What are our workflow conventions" | `.session-continuity/PROJECT_CONTEXT.md` → Workflow conventions |
| "Bun replaces the CA trust store" | `.session-continuity/LEARNINGS.md` → new numbered entry |
| "The CLI uses portless URLs" | `CLAUDE.md` (per-project config) |
| "User prefers Bun to Node" | `CLAUDE.md` (per-project) or user's global `~/.claude/CLAUDE.md` |
| "Last session tried approach X and rejected it" | `.session-continuity/LEARNINGS.md` → Anti-patterns section |
| "API keys leaked in transcript on date Y" | `.session-continuity/LEARNINGS.md` → Security section (names only, never values) |

**Do not put in these files:**

- Secrets. Ever. Even in "Fixed by changing `KEY=abc`" commentary — redact to `KEY=<redacted>`.
- Information that is trivially rederivable from the code (module layout, function signatures — the code itself is the source of truth).
- Narrative fluff ("We spent a long time on this and finally…"). Write recipes, not war stories.

## Customization guidance

Different projects have different shapes, but the core file pattern adapts well:

- **Test counts in the primer.** If you have one package, one line. If you have three packages (like SF_Tunnel: relay, tunnel, web), show three. If counts are unstable (integration tests that depend on external services), drop the exact count and document the green command instead.
- **"Workflow conventions" section.** Replace with whatever this project's disciplines are: commit message format, branch naming, code review process, required CI checks.
- **"Backlog" section.** Use your own taxonomy: "blocked", "deferred", "needs decision". Keep it actionable.
- **LEARNINGS section headings.** Replace "Bun", "SvelteKit", etc. with the actual layers of the project. Stack varies, structure is universal.

## For team-wide use

If multiple people are working on the same project and should all benefit from this:

1. All five files are **checked-in** artifacts, not gitignored. Commit them in the project repo under `.session-continuity/`.
2. Copy [`templates/CLAUDE_MD_SNIPPET.md`](templates/CLAUDE_MD_SNIPPET.md) into the project's `CLAUDE.md` verbatim. It covers the read-first pointer, the primer-refresh-alongside-commits rule, the backlog-item verify-before-close rule, and the gate-chain-commit trap — the things a project otherwise has to rediscover and hand-write for itself (as architect-workbench did before this snippet existed).
3. Document the maintenance rules in the primer itself (last section). Templates include this.
4. Human teammates benefit too — LEARNINGS.md doubles as a living post-mortem log, and the primer is a great onboarding handoff.

## Red flags — when NOT to use

- **One-off scripts or throwaway repos.** Not worth the overhead.
- **Repos where the user explicitly prefers other memory mechanisms** (e.g., a heavily-used wiki, a confluence space). Don't duplicate.
- **Projects whose CLAUDE.md already does this** (some projects keep all session handoff in `CLAUDE.md`). Extend that approach instead of imposing a new structure.

## Complementary mechanisms

- **`CLAUDE.md`** covers "how to work in this repo" — durable, rarely changes. Primer covers "what's true right now" — changes per commit.
- **MemPalace / similar agent-memory systems** cover color that doesn't deserve a commit: user preferences, debugging narratives, session-level observations. Primer/LEARNINGS cover things the team should see.
- **Stop / pre-commit hooks** can enforce the "refresh the primer in the same commit as substantive changes" rule if drift becomes a problem. This skill does not install one — it relies on discipline. Add a hook only if you find yourself forgetting.

## Philosophy

The five files answer five different questions:

- Primer: "What is true about this project **right now**?"
- BACKLOG: "What has been **explicitly deferred** (decisions, follow-ups, follow-ons) that we should not forget?"
- ROADMAP: "Where is this headed, independent of what's in the tactical queue?"
- PROJECT_CONTEXT: "What is true about this project **generally**, and rarely changes?"
- LEARNINGS: "What should I know to avoid rediscovering something painful?"

Together they compress the cost of session handoff from "re-explain everything" to "read a couple of files." The primer stays short (a shortlist, not a snapshot); BACKLOG accumulates deferred work; ROADMAP holds direction independent of the tactical queue; PROJECT_CONTEXT and LEARNINGS both grow organically but at different rates — one when the project's shape changes, the other with every hard-won bug. All five outlive any single session.
