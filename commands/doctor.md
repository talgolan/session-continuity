---
description: Diagnose whether session-continuity is actually wired up in this project — hooks, four files, peers, freshness, GitHub backlog, plugin root, gate scripts. Zero args, read-only. Zero-turn when UserPromptSubmit intercepts.
---

# /session-continuity:doctor

You are responding to the `/session-continuity:doctor` slash command.

**Your job: run the command below and print its output verbatim — no
reformatting, no summarizing, no added commentary.** Read-only — never
edits, stages, or commits anything. Every fix is already a printed
command in the report for the user to run themselves.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/doctor-report.sh" "$(pwd)"
```

`doctor-report.sh` already handles every failure mode (vendored vs plugin
install, missing peers, stale primer, fossil BACKLOG.md, non-executable
gates, GitHub queue unavailable, broken plugin install) by printing its
own table — do not add your own "if the output looks wrong, do X" branch
on top of it.
