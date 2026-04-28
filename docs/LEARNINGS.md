# Learnings — session-continuity

This is a graveyard of subtle, painful bugs we've hit while building
session-continuity. Each entry is a recipe for a future engineer (or
future Claude) to avoid re-discovering what was expensive to discover
the first time. Entries are grouped by layer, most-painful-first
within each group.

---

## Claude Code plugin mechanics

<!-- Add entries here as they surface -->

---

## Slash command skill authoring

<!-- Add entries here as they surface -->

---

## Hook scripting (SessionStart / PreToolUse)

<!-- Add entries here as they surface -->

---

## Security incidents

<!-- Log security-adjacent events here: leaked credentials (names only,
NEVER values), access control mistakes. Never record actual secret values. -->

---

## Anti-patterns we were tempted by (and rejected)

<!-- This section is for "we thought X would work, we tried X, here is
why X is wrong." Each entry names the anti-pattern, explains the appeal,
and explains why it loses. -->

---

## Checklist for a fresh dev-env setup

1. `claude plugins install github:talgolan/session-continuity`
2. Open a scratch project and run `/session-continuity:primer` to verify init mode.
3. Make a small change and run `/session-continuity:end-session` to verify close-out.

---

*Last reviewed: 2026-04-28. Add new entries at the top of each section
as they surface. Rule of thumb: if a bug takes more than 15 minutes to
diagnose, it goes here.*

*Numbering note: new entries take the next available number (N+1) and
are placed at the top of their section. Old entries keep their numbers
so historical references ("see #7 above") stay valid even when the
visual order no longer matches numeric order.*
