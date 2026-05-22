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
