---
description: Diagnose whether session-continuity is actually wired up in this project — hooks registered, all five files present and not stale, plugin root resolves and isn't a stale cache, gate scripts executable. Zero args, read-only.
---

# /session-continuity:doctor

You are responding to the `/session-continuity:doctor` slash command.

**Your job: answer "is this actually working?" directly, instead of the user finding out by hitting a gate denial cold or discovering a mechanism silently never fired.** This command is read-only — it never edits, stages, or commits anything. Every row either reports a fact or, if something's broken, prints the exact command to fix it; the user runs that themselves.

## Step 1 — Gather

Run everything in **one Bash call**, timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")

echo "--- plugin root ---"
echo "RESOLVED_ROOT=${CLAUDE_PLUGIN_ROOT:-}"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}" ]; then
  echo "ROOT_EXISTS=1"
  [ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] && grep -m1 '"version"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
  [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json" ] && echo "HOOKS_JSON_EXISTS=1" || echo "HOOKS_JSON_EXISTS=0"
  CACHE_PARENT="$(dirname "${CLAUDE_PLUGIN_ROOT}")"
  [ -d "$CACHE_PARENT" ] && ls "$CACHE_PARENT" 2>/dev/null
  echo "--- gate script exec bits ---"
  if [ -d "${CLAUDE_PLUGIN_ROOT}/hooks" ]; then
    for s in session-start.sh pre-commit-check.sh learnings-surface.sh smoke-gate.sh proven-gate.sh occurrence-gate.sh evidence-gate.sh flaky-gate.sh backend-parity-gate.sh version-check.sh; do
      p="${CLAUDE_PLUGIN_ROOT}/hooks/$s"
      if [ -f "$p" ]; then
        [ -x "$p" ] && echo "$s=EXEC" || echo "$s=NOEXEC:$p"
      fi
    done
  fi
else
  echo "ROOT_EXISTS=0"
fi

echo "--- vendored-mode check (only matters if ROOT_EXISTS=0 above) ---"
[ -f .claude/settings.json ] && cat .claude/settings.json || echo "NO_PROJECT_SETTINGS"

echo "--- .session-continuity/ files ---"
for f in SESSION_PRIMER.md BACKLOG.md ROADMAP.md PROJECT_CONTEXT.md LEARNINGS.md; do
  [ -f ".session-continuity/$f" ] && echo "$f=EXISTS" || echo "$f=MISSING"
done

echo "--- current git log (compare against primer's block) ---"
git log --oneline -5

_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=doctor --step=step-1-gather --duration="$_PERF_DURATION"
fi
```

## Step 2 — Interpret and report

Work through the five rows below using the output above. Never invent a result for something the output above didn't actually show — if a probe was skipped (e.g. no cache-parent directory), report `?` for that row rather than guessing.

1. **Install mode.** `ROOT_EXISTS=1` → **plugin mode**: report the version parsed from `plugin.json` and the resolved path. `ROOT_EXISTS=0` → **vendored mode**: note that `CLAUDE_PLUGIN_ROOT` never resolved, which is expected for a manually-vendored install — proceed to row 2's vendored branch.

2. **Hooks registered.**
   - Plugin mode: ✓ if `HOOKS_JSON_EXISTS=1` (Claude Code auto-wires this when the plugin is enabled — this is a sanity check that the install isn't partial/corrupted, not proof the user configured anything). ⚠️ if `HOOKS_JSON_EXISTS=0` — the plugin directory is missing `hooks/hooks.json`; reinstalling the plugin is the fix.
   - Vendored mode: grep the `.claude/settings.json` content captured above for the hook script names (`session-start.sh`, `learnings-surface.sh`, etc.). ✓ if at least `session-start.sh` and `learnings-surface.sh` appear (the two hooks a vendored install needs most — the primer reminder and the retrieval hook). ⚠️ listing which expected hook names are absent, with a pointer to `SKILL.md`'s hooks section for the entries to copy in.

3. **Five `.session-continuity/` files exist; primer not stale.** ✓/⚠️ per file from the `EXISTS`/`MISSING` lines. For `SESSION_PRIMER.md` specifically, if it exists, also compare its own `git log --oneline -5` block (read the file) against the `git log --oneline -5` output captured above — mismatch means ⚠️ stale, "run `/session-continuity:primer` to refresh." This is the only file with an objective staleness signal in this repo; the other four don't get a staleness check here, only an existence check.

4. **`CLAUDE_PLUGIN_ROOT` resolves and isn't stale.** Skip this row entirely in vendored mode (nothing to check). In plugin mode: ✓ if `ROOT_EXISTS=1`. Then check staleness — from the `ls "$CACHE_PARENT"` output, if it lists sibling version directories, compare the resolved version (parsed from `plugin.json` above) against the highest version number listed. If a newer one exists: ⚠️ "resolved root is v`<old>`, but v`<new>` is already installed in the cache — this session started before the update landed; restart the session to pick it up." If they match, or the cache-parent listing wasn't available (different install layout), ✓ with a note that the check was skipped when applicable — don't fail the row over a probe that simply didn't apply.

5. **Gate scripts executable.** Skip in vendored mode (no resolved root to check against). In plugin mode, one sub-row per `EXEC`/`NOEXEC:<path>` line captured above. ✓ if all are `EXEC`. For each `NOEXEC:<path>`, ⚠️ with the exact fix: `chmod +x <path>`.

**List every missing file, every missing hook name, and every non-executable script — do not summarize, filter, or pick a "primary" one.** If two gate scripts are missing their exec bit, the row lists both `chmod +x` commands, not one.

Emit the report as a table, same convention as `/session-continuity:end-session`'s checklist:

| Row | Marker | Content |
|---|---|---|
| Install mode | ✓ | "Plugin vX.Y.Z at `<path>`" OR "Vendored (CLAUDE_PLUGIN_ROOT unresolved)" |
| Hooks registered | ✓ / ⚠️ | plugin: "hooks.json present" OR "⚠️ hooks/hooks.json missing — reinstall the plugin" · vendored: "session-start.sh + learnings-surface.sh found in .claude/settings.json" OR "⚠️ missing: `<names>` — see SKILL.md's hooks section" |
| .session-continuity/ files | ✓ / ⚠️ | "All five present, primer current" OR "⚠️ missing: `<names>`" OR "⚠️ primer stale — run /session-continuity:primer" |
| CLAUDE_PLUGIN_ROOT | ✓ / ⚠️ / (skipped) | "vX.Y.Z, matches latest cached" OR "⚠️ resolved to vX.Y.Z, but vX.Y.Z+1 is cached — restart the session" OR "skipped (vendored mode)" |
| Gate scripts executable | ✓ / ⚠️ / (skipped) | "All N gate scripts executable" OR "⚠️ not executable: `chmod +x <path>`, `chmod +x <path>`" OR "skipped (vendored mode)" |

## Notes

- **Never mutates anything.** No file writes, no `git add`, no `chmod` run on the user's behalf — every fix is a command printed for the user to run themselves.
- **Fail soft on probes that don't apply**, not on the row as a whole. A probe that was skipped because it doesn't apply to this install mode is not the same as a probe that ran and found a problem — don't conflate a `?`/skip with a ⚠️.
- **Never invent a version number, path, or file list.** Every value in the report must trace back to a literal line in Step 1's output.
