# Project conventions — session-continuity

Project-local instructions. These override skill defaults for work
inside this repo only.

## Agent meta-artifacts go under `meta/superpowers/`, not `docs/`

Superpowers skills (brainstorming, writing-plans, etc.) default to
`docs/superpowers/specs/` and `docs/superpowers/plans/`. **Do not use
those paths in this repo.**

Canonical locations for in-repo agent artifacts:

| Artifact | Path |
|---|---|
| Specs (design docs from brainstorming) | `meta/superpowers/specs/` |
| Plans (implementation plans from writing-plans) | `meta/superpowers/plans/` |
| Validation logs | `meta/superpowers/validation/` |
| Recommendation / feedback docs | `meta/superpowers/recommendations/` |
| Administrative notes (marketplace submission, etc.) | `meta/administrative/` |

History: the `docs/` → `meta/` move shipped in v0.3 (see CHANGELOG).
The three files the plugin ships to user projects
(`SESSION_PRIMER.md`, `PROJECT_CONTEXT.md`, and `LEARNINGS.md`
templates) live under `skills/session-continuity/templates/`, not
`docs/`. This repo has no top-level `docs/` directory at all today —
if one gets added later for some other purpose, it stays clean of
agent meta-artifacts per the table above.

If a superpowers skill suggests `docs/superpowers/<thing>/`, redirect
to `meta/superpowers/<thing>/` before creating the file.
