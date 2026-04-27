# Learnings — {{PROJECT_NAME}}

This is a graveyard of subtle, painful bugs we've hit while building
{{PROJECT_NAME}}. Each entry is a recipe for a future engineer (or
future Claude) to avoid re-discovering what was expensive to discover
the first time. Entries are grouped by layer, most-painful-first
within each group.

---

## {{LAYER_1_NAME}}

<!--
  Examples: "Runtime — Bun", "Runtime — Node.js", "HTTP / REST",
  "Database — Postgres", "Auth / OAuth / CSRF", "Shell scripts",
  "CI / CD", "Build tooling", etc. Adapt to the actual layers of
  this project. Delete layers that don't apply.
-->

### 1. {{ENTRY_TITLE}}

**The trap.** {{WHAT_YOU_TRIED_THAT_SEEMED_REASONABLE}}

**Symptom.** {{WHAT_YOU_OBSERVED_INCLUDING_MISLEADING_ERROR_MESSAGES}}

**Fix.** {{WHAT_ACTUALLY_WORKS}}

```
{{OPTIONAL_CODE_OR_COMMAND_EXAMPLE}}
```

**Diagnostic signal** *(optional)*. {{HOW_TO_RECOGNIZE_THIS_NEXT_TIME}}

---

## {{LAYER_2_NAME}}

### 2. {{ENTRY_TITLE}}

<!-- same structure -->

---

## Security incidents

<!--
  Log security-adjacent events here: leaked credentials (names only,
  NEVER values), access control mistakes, CSP/CORS/CSRF failures that
  had user impact. Each entry should include: what happened, what was
  rotated/mitigated, what changed to prevent recurrence. Never record
  actual secret values — use <redacted> or a description.
-->

---

## Anti-patterns we were tempted by (and rejected)

<!--
  This section is for "we thought X would work, we tried X, here is
  why X is wrong." Prevents re-tempting. Each entry names the
  anti-pattern, explains the appeal, and explains why it loses.
-->

---

## Checklist for a fresh dev-env setup

<!--
  Distilled from everything above, the shortest path to a working
  local stack. Numbered steps a new engineer can follow without
  reading the rest of the file.
-->

1. {{STEP_1}}
2. {{STEP_2}}

---

*Last reviewed: {{DATE}}. Add new entries at the top of each section
as they surface. Rule of thumb: if a bug takes more than 15 minutes
to diagnose, it goes here.*

*Numbering note: new entries take the next available number (N+1) and
are placed at the top of their section. Old entries keep their numbers
so historical references ("see #7 above") stay valid even when the
visual order no longer matches numeric order.*
