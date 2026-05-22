# Validation log — end-session heuristic pass (v0.6.0)

**Branch:** `feat/end-session-heuristics`
**Spec:** `docs/superpowers/specs/2026-05-21-end-session-heuristic-pass-design.md`
**Plan:** `docs/superpowers/plans/2026-05-21-end-session-heuristic-pass.md`

This log records the manual validation matrix runs for the v0.6.0
end-session heuristic pass. Each scenario is documented with: setup,
expected behavior, actual behavior, pass/fail.

---

## Scenario 1 — clean repo, no commits since last primer refresh

**Setup.** Branch `feat/end-session-heuristics` after Task 6 commits.
The primer's last commit (Task 6) IS HEAD, but the `git log --oneline
-5` block inside the primer was written *before* the Task 6 commit
landed, so the block's most recent SHA is Task 5's commit
(`9625fd7 chore: bump to v0.6.0 + CHANGELOG entry`), not Task 6's
commit (`8083fbd docs(primer): refresh for v0.6.0`). This is a known
artifact of the per-task-commit plan structure; in practice the
refresh would bundle with the substantive commit.

**Expected.** Step 1 drift check fires (block does not match HEAD).
The §1 overlay finds no matches because there is exactly one
"missing" commit (the primer-refresh itself), and its subject
(`docs(primer): refresh for v0.6.0`) tokenizes to `{primer, refresh}`
after stopwords are removed (`docs` and `for` are in the stopword
list, `primer` is in the stopword list, leaving only `refresh`).
Cardinality 1 — below the ≥3 threshold for every outstanding item.
No "may close outstanding items" block appears.

**Actual.** _(filled in at validation time by walking through the skill prose against actual repo state)_

**Result.** _(pass / fail / note)_

---

## Scenario 2 — commits without matches

**Setup.** Branch state after Tasks 1–5 + 6 commits, with primer
outstanding items as updated in Task 6.

**Expected.** Step 1 surfaces the raw subject list of all commits
since the primer's referenced log block. The §1 overlay computes
stem-intersection for each subject against each outstanding item;
all intersections are <3 because the commit subjects share at most
2 stems with any item ("end, session" with item #1; nothing with
items #2, #3). No "may close outstanding items" block appears.

**Actual.** _(filled in at validation time)_

**Result.** _(pass / fail / note)_

---

## Scenario 3 — commit with stem-intersection match

**Setup.** Hypothetical synthetic commit subject:
`feat(release): merge feat/end-session-heuristics into main`.
Tokenized + stopword-filtered, this yields
`{merge, end, session, heuristics, main}`. Outstanding item #1's
text yields `{land, main, merge, end, session, heuristics, then, git, fire, workflow}`. Intersection cardinality = 5 ≥ 3.

**Expected.** Step 1 surfaces the subject in the raw list AND
appends a "May close outstanding items" block citing
`<sha> → item #1 ("Land v0.6.0 on main and tag")`.

**Actual.** _(filled in at validation time)_

**Result.** _(pass / fail / note)_

---

## Scenario 4 — retry burst (Heuristic A)

**Setup.** Hypothetical session with 4 invocations of
`bun run smoke-test` over a 30-minute window.

**Expected.** Heuristic A normalizes the command (no transformation
needed — it's already canonical), counts 4 occurrences ≥ 3, fires
with title `bun run smoke-test — investigated for 4 retries.`
Evidence bullets cite the four timestamps + exit codes.

**Actual.** _(filled in at validation time)_

**Result.** _(pass / fail / note)_

---

## Scenario 5 — revert / reset (Heuristic B)

**Setup.** Hypothetical session with one `git reset --hard HEAD~1`
invocation following a commit subject `feat: try X for Y`.

**Expected.** Heuristic B fires with title
`Reverted approach: feat: try X for Y.` (the abandoned commit's
subject). Evidence cites the reset invocation and the reverted
commit's SHA.

**Actual.** _(filled in at validation time)_

**Result.** _(pass / fail / note)_
