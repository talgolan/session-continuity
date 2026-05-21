# session-continuity plugin — usage feedback + recommendations

## 1. Drift detection — what works, what misses

### What works
- `git log --oneline -5` block comparison catches commit drift reliably.
- The "stage primer alongside the substantive commit, never alone" rule prevents self-referential chains and is well-stated in the skill body.

### What misses
- **`mtime newer than HEAD`** is fragile. Anything that touches the file (linter, format-on-save, even `cat | tee`) bumps mtime without changing content. Reverse the check: compare HEAD subject against the primer's log block — if HEAD's subject isn't there, primer is stale. Subject + short-hash is enough; mtime adds noise.
- **Test counts drift silently.** Today's session: primer says "1162 pass / 0 fail." After my `src/backend.ts` change, it stayed 1162. Lucky. If I'd added 5 SSH tests, the primer would still say 1162. **Suggested:** when refresh mode runs, also re-run the test command(s) found in the "Test expectations" code block and report deltas. Skill already mentions this; make it default-on rather than conditional, and **always retry once on failure** before reporting (3/3 of my runs today had one flaky run that resolved on retry — see also LEARNINGS #28-class flakiness).
- **Outstanding items drift.** No automated check. When user asks for "refresh," skill asks "anything to remove (finished) or add (new follow-ups)?" — burden on me to remember. **Suggested:** scan `git log <last-primer-refresh>..HEAD` for commit subjects matching "fix", "close", "implement", "drop" against the substring text of each outstanding item. Surface the matches as candidates: "commit `4528976 fix(build): write sshd-itb.conf` may close item #6 sub-bullet 3 — confirm?" Don't auto-close; just surface.

## 2. Primer-only-commit rule needs branch-aware nuance

The skill's "no primer-only commits" rule is correct on `main` but wrong on squash-merge feature branches. We learned this the hard way — captured as LEARNINGS #86. The rule cost me real time today: I reverted a primer-only edit on `feat/ssh-access` because I followed the skill literally, then re-staged it for the next bundled commit. On a squash-merge branch, the standalone primer commit would have collapsed to nothing and saved a step.

**Suggested:** primer skill checks branch policy. Heuristics in priority order:
1. `gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed` — if squash-only repo or branch has `Squash and merge` selected on its open PR, primer-only commits are free.
2. Branch name pattern (`feat/`, `fix/`, `chore/`) on a non-default branch + non-empty `git log main..HEAD` → likely squash-bound; warn but don't block.
3. Default branch (`main`/`master`) → enforce strict bundle rule.

Even simpler version: ask once per branch and cache the answer in `.git/info/session-continuity-policy` (gitignored, per-clone).

## 3. Init mode could derive much more

Current init asks user for layout summary, packages, outstanding items, workflow conventions. For a TS-on-Bun project, most of this is grep-able:
- **Layout summary** — shell out to `find src -name '*.ts' | head -50` + `tree -L 2 -I 'node_modules|dist|.git'`.
- **Packages/modules** — parse the JSDoc `@module` headers + `Exports:` lines (this project uses them consistently — see `src/backend.ts:4`). Auto-generate the modules table.
- **Test command** — `package.json` `scripts.test`, then run it once and capture the count regex (`(\d+) pass`).
- **Workflow conventions** — read `CLAUDE.md` if present; quote it in a "Conventions inherited from CLAUDE.md" sub-section instead of asking the user to retype.
- **Repo layout block** — read `.gitignore`, exclude those, render `tree`.

The user prompt today (rule from skill: "wait for their answer") burns a turn. With auto-derivation, ask only what truly can't be inferred: outstanding items, current state narrative, why-this-project. Three questions tops.

## 4. LEARNINGS — entry creation and search

### Numbering should be automatic
Today I had to grep `^### \d+\.` and pick max+1. Skill `session-continuity:learning` exists but I bypassed it because the friction was higher than just editing. Result: numbering policy works for me because I'm careful, but earlier sessions left **5 duplicate-number sets** in the file (#14, #15, #36, #37, #78). Document had no guard.

**Suggested:** `learning` skill should:
1. Read all `^### \d+\.` lines, pick true max + 1 (not "next after the most recent" — that fails when an old entry gets edited last).
2. Validate uniqueness before write.
3. On detected duplicate, refuse and report: "entry 78 already exists at line N — choose 89 or merge into existing."
4. Lower the friction so users (and Claude) actually invoke it. Right now its prompt requires choosing a section, typing the entry. Could accept the entry inline as args, with section auto-suggested from grep against the section headers.

### Cross-references decay
`See also #N` blocks I added today are static text. If #57 gets renumbered, #46's pointer rots. **Suggested:** introduce a slug syntax — `[[trampoline-binary]]` resolves to whatever entry has that slug. Skill maintains a slug→number index in a comment block at file top. Same model as the auto-memory `[[name]]` linking already in CLAUDE.md.

### Search-by-symptom is hard
71 entries, 9 sections, no index. Today I knew to grep "DNS" but a new engineer hitting "container can't reach archive.ubuntu.com" wouldn't think "DNS" first — they'd grep "apt-get update". **Suggested:** auto-generate a "Symptoms index" section at the top by extracting the `**Symptom.**` lines (every entry has one). Sort alphabetically, link to entry. ~80 lines, doubles the file's pickup-by-pattern hit rate.

### "Last reviewed" dating is manual + always stale
I bumped it today; it had been wrong for 14 entries. **Suggested:** end-session skill (which already touches LEARNINGS) auto-updates this date when it appends an entry. Date doesn't reflect a "review" anyway — it reflects last *change*. Rename to "Last entry: 2026-05-21 (#89)" and let the skill manage it.

## 5. End-session skill never fired during a 6-hour session

`session-continuity:end-session` exists. I never invoked it, and the user didn't either. Reasons:
- No trigger. There's no "session is ending" event in Claude Code. The skill expects manual invocation.
- The "LEARNINGS candidates from this session" pitch is high-value but invisible until invoked.

**Suggested:**
1. Hook into Claude Code's `Stop` or session-end events (the harness can run hooks — see `update-config` skill description). Auto-prompt at session end: "3 events from this session look LEARNINGS-worthy: [list]. Capture any?"
2. Heuristics for candidates: (a) >15-min wall-clock span with the same error tag; (b) ≥3 retries on the same command; (c) reverted commits / abandoned approaches; (d) discovery sequences ending in `git commit -m "fix"`. Today's session would have surfaced two: the `sshd-itb.conf` regression (15 min from build failure to root cause) and the Apple DNS investigation (1 hr+).
3. Even a manual /end-session command that runs the heuristics would beat the current zero-trigger setup.

## 6. The primer file is now ~320 lines — context cost

`SESSION_PRIMER.md` loads in full at every conversation start (CLAUDE.md says so). At 320 lines × 75 tokens/line ≈ 25K tokens/turn × every-turn... it's expensive. Two related issues:

### Mix of stable and volatile content
- **Stable** (changes monthly at most): Ground rules, repo layout, modules table, conventions, "Where to look for what."
- **Volatile** (changes per commit): git log -5 block, test counts, current state narrative, outstanding items.

**Suggested:** split into two files. `docs/SESSION_PRIMER.md` becomes the volatile shortlist (≤80 lines: current state + outstanding + log block + test counts). Stable content moves to `docs/PROJECT_CONTEXT.md` (linked from primer's "First things first"). Both still get read at session start, but `PROJECT_CONTEXT.md` can be cache-eligible while `SESSION_PRIMER.md` rotates each commit.

### Closed outstanding items pile up
Today's primer outstanding section: 15 items, 8 of which are struck-through "done" entries. Future-Claude reads them every time. **Suggested:** primer-refresh trims items closed >30 days ago, archives them to `docs/PROJECT_CONTEXT.md`'s "Resolved decisions" appendix. Trail of *why* something closed survives, but the active list stays short.

## 7. Schema validation for primer fields

Primer is freeform markdown. Two real bugs from today + earlier sessions:
- I tried `backend: "apple"` in `~/.itb/settings.json` because muscle memory; the schema is `["docker", "container"]`. Took 5 min to find. Primer didn't help — it doesn't document the enum. Same hazard for primer field values (e.g., test counts as numbers, outstanding items as numbered list).
- Item numbering in outstanding section is non-monotonic — there's an old `10.` and `11.` after `15.` because someone hand-edited and forgot. Renumbers happen incorrectly.

**Suggested:** primer template grows a small JSON sidecar (`docs/.session-primer.lock`) with the volatile fields in structured form. `git log -5` block, test counts, outstanding items array. Skill regenerates the markdown from the lock, validates schema. Nobody hand-edits the markdown — they edit the lock or pass new values to the skill. Costs one file but eliminates the renumbering / typo class entirely.

## 8. Plugin awareness of sibling tools

This codebase uses caveman / cavecrew alongside session-continuity. Currently they don't talk. Some natural integrations:

- **`caveman:compress` on PROJECT_CONTEXT.md** — the stable half doesn't need full prose. Compressed form cuts ~75% of tokens with no loss; primer skill could emit compressed PROJECT_CONTEXT.md by default.
- **`cavecrew-investigator` for "is this LEARNING already captured"** — before appending a new LEARNING, dispatch an investigator to grep for matching symptoms. If hit, suggest cross-link or merge instead of new entry. Today's #89 could have been a sub-section of #28 — but #28's entry was so vague I created a new one and collapsed #28 by hand.
- **Auto-memory file format alignment** — `~/.claude/projects/.../memory/MEMORY.md` already uses the slug-link `[[name]]` syntax. LEARNINGS would benefit from the same convention. Cross-referencing across the two stores ("user feedback memory says X; LEARNING #N captured the why") would chain naturally.

## 9. Specific friction moments worth recording

These are concrete things that cost time *this session*:

1. **Forgot `MEMORY.md` exists.** Auto-memory file at `/Users/tal.golan/.claude/projects/.../memory/` is loaded into context, but it's separate from the primer. I treated them as redundant — primer outstanding item #6 vs. the corresponding memory entry. **Suggested:** primer's "First things first" section explicitly names the auto-memory file with a one-line of what's in there. Or merge them.

2. **`/session-continuity:primer` invocation lacks a quick-status mode.** Step 4 ("Check mode") prints 4 lines. Useful, but I only knew it existed because the skill body documents it. Surface it: at primer load (i.e., at any session start), have the skill auto-print the 4-line status if no other action is needed. Free observability.

3. **Tests flake during refresh.** Skill says "run the test command" — implicit single run. Bun test counts on this codebase flake (saw 1162→1161→1162 in three consecutive runs, all on `main`). Refresh mode should retry up to 3× before reporting drift, and warn "test counts unstable across N runs — pin to highest stable count."

4. **No "what changed since last refresh" diff helper.** The user asked me twice "anything else changed?" Skill could compute `git log <last-primer-commit-hash>..HEAD` and surface subjects, leaving me to ask "do these need primer entries or LEARNINGS?" — but giving me the candidate list.

5. **Outstanding-items consolidation is awkward.** I just collapsed three Apple-Container items into one nested entry. The primer doesn't have a structure for nested items — I used markdown sub-bullets, which work, but the next refresh might break formatting if someone adds a sibling item. **Suggested:** outstanding items as a YAML block (or the JSON lock from §7) would naturally support nesting + status fields (`open`, `done`, `deferred`).

6. **The skill's "Init Mode" template path is hardcoded** to `~/.claude/plugins/cache/session-continuity/...`. If the plugin is dev-mode (symlinked from a local repo), this path is wrong. Today my plugin source is presumably at `/Users/tal.golan/.claude/plugins/...` but a fresh dev clone wouldn't have that. **Suggested:** resolve the template path via the plugin's own metadata (Claude Code exposes plugin install dirs) or fall back to bundled plain-text constants in the skill body.

## 10. Quick wins ranked

If you want a 2-hour patch session:
1. **Skill auto-prints 4-line status at session start** (zero new logic; surface what already exists). [§9.2]
2. **`learning` skill validates uniqueness before write.** [§4.1]
3. **Refresh mode retries flaky tests up to 3×.** [§9.3]
4. **End-session manual command:** `/session-continuity:end-session-now` that runs the heuristics. Drop the auto-trigger ambition until later. [§5]
5. **`Last reviewed:` field auto-bumped by `learning` skill.** [§4.4]

If you want a weekend project:
6. **Split primer into volatile + stable halves.** [§6.1]
7. **JSON sidecar lock for volatile fields, regenerated markdown.** [§7]
8. **Slug-based cross-refs in LEARNINGS.** [§4.2]
9. **Symptoms index auto-generated at top of LEARNINGS.** [§4.3]
10. **Branch-policy detection for primer-commit rule.** [§2]

If you want a real research arc:
11. **Heuristic discovery of LEARNINGS candidates from session transcripts.** [§5]
12. **Cross-tool integration with caveman/cavecrew.** [§8]
13. **Outstanding-items state machine + auto-close detection from commit subjects.** [§1]
