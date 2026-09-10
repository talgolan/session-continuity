#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/doctor-report.sh — zero-model-call report for /session-continuity:doctor.
# Runs the install probes and prints the finished markdown table to stdout.
# See GitHub #68. Does not write, stage, or chmod anything.
#
# Usage: doctor-report.sh [<project-dir>]
#   project-dir defaults to cwd. CLAUDE_PLUGIN_ROOT must point at the plugin
#   install (set by Claude for slash commands / intercept). When unset or
#   missing, report is vendored-mode.
#
# Exit 0 on every successful report (including ⚠️/✗ rows). Exit 2 only on
# broken install (missing/skewed helper sibling), matching render.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_FALLBACK="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIR="${1:-.}"
DIR="$(cd "$DIR" 2>/dev/null && pwd || echo "$DIR")"

die_install() {
  printf 'doctor-report.sh: %s\n' "$1" >&2
  exit 2
}

# Prefer the caller's CLAUDE_PLUGIN_ROOT; fall back to this script's plugin tree
# so smoke fixtures and local `bash hooks/lib/doctor-report.sh` work.
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  ROOT=""
fi
# When ROOT empty but we're executing from a real plugin tree, use it only if
# the caller exported CLAUDE_PLUGIN_ROOT="" intentionally for vendored tests —
# convention: unset = try fallback; CLAUDE_PLUGIN_ROOT="" = force vendored.
if [[ -z "${CLAUDE_PLUGIN_ROOT+x}" ]]; then
  ROOT="$PLUGIN_ROOT_FALLBACK"
elif [[ -n "${CLAUDE_PLUGIN_ROOT}" && -d "${CLAUDE_PLUGIN_ROOT}" ]]; then
  ROOT="$CLAUDE_PLUGIN_ROOT"
else
  ROOT=""
fi

# Sibling helpers used in plugin mode — refuse if missing/skewed.
check_helper() {
  local f="$1"
  [[ -r "$SCRIPT_DIR/$f" ]] || die_install \
    "$f is missing from $SCRIPT_DIR — the plugin cache is incomplete. Run \`/session-continuity:update\`."
  grep -q '^# CONTRACT_VERSION=1$' "$SCRIPT_DIR/$f" || die_install \
    "$f is from a different plugin version — run \`/session-continuity:update\`."
}

if [[ -n "$ROOT" ]]; then
  check_helper "peer-probes.sh"
  check_helper "primer-freshness.sh"
  check_helper "primer-validate.sh"
  check_helper "backlog-issues.sh"
fi

# --- gather -----------------------------------------------------------------

GATE_SCRIPTS=(
  session-start.sh
  pre-commit-check.sh
  learnings-surface.sh
  smoke-gate.sh
  proven-gate.sh
  occurrence-gate.sh
  evidence-gate.sh
  flaky-gate.sh
  backend-parity-gate.sh
  derived-value-gate.sh
  version-check.sh
)

gather() {
  echo "RESOLVED_ROOT=${ROOT}"
  if [[ -n "$ROOT" && -d "$ROOT" ]]; then
    echo "ROOT_EXISTS=1"
    if [[ -f "$ROOT/.claude-plugin/plugin.json" ]]; then
      ver="$(grep -m1 '"version"' "$ROOT/.claude-plugin/plugin.json" | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
      echo "PLUGIN_VERSION=${ver}"
    else
      echo "PLUGIN_VERSION="
    fi
    [[ -f "$ROOT/hooks/hooks.json" ]] && echo "HOOKS_JSON_EXISTS=1" || echo "HOOKS_JSON_EXISTS=0"
    CACHE_PARENT="$(dirname "$ROOT")"
    if [[ -d "$CACHE_PARENT" ]]; then
      echo "CACHE_PARENT=${CACHE_PARENT}"
      # shellcheck disable=SC2012
      ls "$CACHE_PARENT" 2>/dev/null | while IFS= read -r ent; do
        echo "CACHE_ENT=${ent}"
      done
    fi
    echo "--- gate scripts ---"
    for s in "${GATE_SCRIPTS[@]}"; do
      p="$ROOT/hooks/$s"
      if [[ -f "$p" ]]; then
        if [[ -x "$p" ]]; then
          echo "GATE=${s}=EXEC"
        else
          echo "GATE=${s}=NOEXEC:${p}"
        fi
      else
        echo "GATE=${s}=MISSING"
      fi
    done
  else
    echo "ROOT_EXISTS=0"
    echo "PLUGIN_VERSION="
    echo "HOOKS_JSON_EXISTS=0"
  fi

  if [[ -f "$DIR/.claude/settings.json" ]]; then
    echo "PROJECT_SETTINGS=1"
    # Flatten to one line markers for expected hook script names
    for name in session-start.sh learnings-surface.sh; do
      if grep -q "$name" "$DIR/.claude/settings.json" 2>/dev/null; then
        echo "VENDORED_HOOK=${name}=PRESENT"
      else
        echo "VENDORED_HOOK=${name}=ABSENT"
      fi
    done
  else
    echo "PROJECT_SETTINGS=0"
  fi

  for f in SESSION_PRIMER.md ROADMAP.md PROJECT_CONTEXT.md LEARNINGS.md; do
    if [[ -f "$DIR/.session-continuity/$f" ]]; then
      echo "FILE_${f}=EXISTS"
    else
      echo "FILE_${f}=MISSING"
    fi
  done
  if [[ -f "$DIR/.session-continuity/BACKLOG.md" ]]; then
    echo "BACKLOG_FOSSIL=1"
  else
    echo "BACKLOG_FOSSIL=0"
  fi

  if [[ -n "$ROOT" ]]; then
    if [[ -f "$DIR/.session-continuity/SESSION_PRIMER.md" ]]; then
      if bash "$SCRIPT_DIR/primer-validate.sh" "$DIR/.session-continuity/SESSION_PRIMER.md" >/dev/null 2>&1; then
        echo "PRIMER_VALIDATE=ok"
      else
        echo "PRIMER_VALIDATE=fail"
      fi
    else
      echo "PRIMER_VALIDATE=skip"
    fi
    # peer-probes / freshness always exit 0
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "$line"
    done < <(bash "$SCRIPT_DIR/peer-probes.sh" "$DIR")
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "$line"
    done < <(bash "$SCRIPT_DIR/primer-freshness.sh" "$DIR")
  else
    echo "PRIMER_VALIDATE=skip"
    echo "ENGRIM=?"
    echo "GRAPHIFY=?"
    echo "STALE=?"
  fi

  if command -v gh >/dev/null 2>&1; then
    echo "GH=PRESENT"
  else
    echo "GH=MISSING"
  fi
  if gh auth status >/dev/null 2>&1; then
    echo "GH_AUTH=OK"
  else
    echo "GH_AUTH=FAIL"
  fi
  if [[ -n "$ROOT" && -r "$SCRIPT_DIR/backlog-issues.sh" ]]; then
    count="$(bash "$SCRIPT_DIR/backlog-issues.sh" --count "$DIR" 2>/dev/null || true)"
    if [[ "$count" =~ ^[0-9]+$ ]]; then
      echo "BACKLOG_COUNT=${count}"
    else
      echo "BACKLOG_COUNT="
    fi
  else
    echo "BACKLOG_COUNT="
  fi
}

GATHER="$(gather)"

kv() {
  printf '%s\n' "$GATHER" | grep -m1 "^$1=" | sed "s/^$1=//" || true
}

# --- interpret --------------------------------------------------------------

ROOT_EXISTS="$(kv ROOT_EXISTS)"
PLUGIN_VERSION="$(kv PLUGIN_VERSION)"
RESOLVED_ROOT="$(kv RESOLVED_ROOT)"
HOOKS_JSON_EXISTS="$(kv HOOKS_JSON_EXISTS)"
PRIMER_VALIDATE="$(kv PRIMER_VALIDATE)"
ENGRIM="$(kv ENGRIM)"
GRAPHIFY="$(kv GRAPHIFY)"
STALE="$(kv STALE)"
BACKLOG_FOSSIL="$(kv BACKLOG_FOSSIL)"
GH="$(kv GH)"
GH_AUTH="$(kv GH_AUTH)"
BACKLOG_COUNT="$(kv BACKLOG_COUNT)"
PROJECT_SETTINGS="$(kv PROJECT_SETTINGS)"

# Row 1 — Install mode
if [[ "$ROOT_EXISTS" == "1" ]]; then
  R1_MARK="✓"
  R1_TEXT="Plugin v${PLUGIN_VERSION:-?} at \`${RESOLVED_ROOT}\`"
else
  R1_MARK="✓"
  R1_TEXT="Vendored (CLAUDE_PLUGIN_ROOT unresolved)"
fi

# Row 2 — Hooks registered
if [[ "$ROOT_EXISTS" == "1" ]]; then
  if [[ "$HOOKS_JSON_EXISTS" == "1" ]]; then
    R2_MARK="✓"
    R2_TEXT="hooks.json present"
  else
    R2_MARK="⚠️"
    R2_TEXT="hooks/hooks.json missing — reinstall the plugin"
  fi
else
  missing_h=()
  for name in session-start.sh learnings-surface.sh; do
    hv="$(printf '%s\n' "$GATHER" | grep -m1 "^VENDORED_HOOK=${name}=" | sed "s/^VENDORED_HOOK=${name}=//" || true)"
    if [[ "$hv" != "PRESENT" ]]; then
      missing_h+=("$name")
    fi
  done
  if [[ "$PROJECT_SETTINGS" != "1" ]]; then
    R2_MARK="⚠️"
    R2_TEXT="no .claude/settings.json — see SKILL.md's hooks section"
  elif [[ ${#missing_h[@]} -eq 0 ]]; then
    R2_MARK="✓"
    R2_TEXT="session-start.sh + learnings-surface.sh found in .claude/settings.json"
  else
    R2_MARK="⚠️"
    R2_TEXT="missing: $(IFS=,; echo "${missing_h[*]}") — see SKILL.md's hooks section"
  fi
fi

# Row 3 — .session-continuity/ files + shape + peers + freshness
problems=()
hard=0
for f in SESSION_PRIMER.md PROJECT_CONTEXT.md ROADMAP.md LEARNINGS.md; do
  st="$(kv "FILE_${f}")"
  if [[ "$st" != "EXISTS" ]]; then
    problems+=("missing: $f")
  fi
done
if [[ "$BACKLOG_FOSSIL" == "1" ]]; then
  problems+=("fossil BACKLOG.md; run /session-continuity:primer to migrate to GitHub Issues if gh is authenticated for the origin's host")
fi
if [[ "$PRIMER_VALIDATE" == "fail" ]]; then
  problems+=("primer shape — PRIMER_VALIDATE=fail")
  hard=1
fi
if [[ -n "$ENGRIM" && "$ENGRIM" != "ok" && "$ENGRIM" != "?" ]]; then
  problems+=("peers — ENGRIM=${ENGRIM}; install order: primer → graphify (commit graphify-out/graph.json) → engrim → re-doctor")
  hard=1
fi
if [[ -n "$GRAPHIFY" && "$GRAPHIFY" != "ok" && "$GRAPHIFY" != "?" ]]; then
  problems+=("peers — GRAPHIFY=${GRAPHIFY}; install order: primer → graphify (commit graphify-out/graph.json) → engrim → re-doctor")
  hard=1
fi
if [[ "$STALE" == "1" ]]; then
  problems+=("primer stale (STALE=1) — run /session-continuity:primer")
fi
# STALE=? → report ? only if nothing else wrong and peers skipped
if [[ ${#problems[@]} -eq 0 ]]; then
  if [[ "$STALE" == "?" || "$ENGRIM" == "?" || "$GRAPHIFY" == "?" ]]; then
    R3_MARK="?"
    R3_TEXT="probes incomplete (STALE=${STALE}, ENGRIM=${ENGRIM}, GRAPHIFY=${GRAPHIFY})"
  else
    R3_MARK="✓"
    R3_TEXT="All four present; primer shape ok; peers ok; freshness current"
  fi
elif [[ "$hard" -eq 1 ]]; then
  R3_MARK="✗"
  R3_TEXT="$(IFS='; '; echo "${problems[*]}")"
else
  R3_MARK="⚠️"
  R3_TEXT="$(IFS='; '; echo "${problems[*]}")"
fi

# Row 4 — CLAUDE_PLUGIN_ROOT staleness
if [[ "$ROOT_EXISTS" != "1" ]]; then
  R4_MARK="✓"
  R4_TEXT="skipped (vendored mode)"
else
  # Compare PLUGIN_VERSION against highest version-looking CACHE_ENT
  highest=""
  while IFS= read -r ent; do
    [[ -z "$ent" ]] && continue
    # strip optional session-continuity@ prefix / take version-like tokens
    cand="$(printf '%s' "$ent" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    [[ -z "$cand" ]] && continue
    if [[ -z "$highest" ]]; then
      highest="$cand"
    else
      # naive version compare via sort -V
      highest="$(printf '%s\n%s\n' "$highest" "$cand" | sort -V | tail -1)"
    fi
  done < <(printf '%s\n' "$GATHER" | grep '^CACHE_ENT=' | sed 's/^CACHE_ENT=//')
  if [[ -n "$highest" && -n "$PLUGIN_VERSION" && "$highest" != "$PLUGIN_VERSION" ]]; then
    # only warn if highest > current
    newer="$(printf '%s\n%s\n' "$PLUGIN_VERSION" "$highest" | sort -V | tail -1)"
    if [[ "$newer" == "$highest" && "$highest" != "$PLUGIN_VERSION" ]]; then
      R4_MARK="⚠️"
      R4_TEXT="resolved to v${PLUGIN_VERSION}, but v${highest} is cached — restart the session"
    else
      R4_MARK="✓"
      R4_TEXT="v${PLUGIN_VERSION}, matches latest cached"
    fi
  else
    R4_MARK="✓"
    if [[ -n "$PLUGIN_VERSION" ]]; then
      R4_TEXT="v${PLUGIN_VERSION}, matches latest cached"
    else
      R4_TEXT="root ok (version probe skipped)"
    fi
  fi
fi

# Row 5 — Gate scripts executable
if [[ "$ROOT_EXISTS" != "1" ]]; then
  R5_MARK="✓"
  R5_TEXT="skipped (vendored mode)"
else
  noexec=()
  missing_g=()
  n_ok=0
  while IFS= read -r line; do
    # GATE=name=EXEC|NOEXEC:path|MISSING
    rest="${line#GATE=}"
    name="${rest%%=*}"
    val="${rest#*=}"
    case "$val" in
      EXEC) n_ok=$((n_ok + 1)) ;;
      NOEXEC:*) noexec+=("chmod +x ${val#NOEXEC:}") ;;
      MISSING) missing_g+=("$name") ;;
    esac
  done < <(printf '%s\n' "$GATHER" | grep '^GATE=')
  if [[ ${#noexec[@]} -eq 0 && ${#missing_g[@]} -eq 0 ]]; then
    R5_MARK="✓"
    R5_TEXT="All ${n_ok} gate scripts executable"
  else
    R5_MARK="⚠️"
    parts=()
    [[ ${#noexec[@]} -gt 0 ]] && parts+=("not executable: $(IFS=', '; echo "${noexec[*]}")")
    [[ ${#missing_g[@]} -gt 0 ]] && parts+=("missing: $(IFS=', '; echo "${missing_g[*]}")")
    R5_TEXT="$(IFS='; '; echo "${parts[*]}")"
  fi
fi

# Row 6 — GitHub backlog
if [[ "$GH" == "PRESENT" && "$GH_AUTH" == "OK" && "$BACKLOG_COUNT" =~ ^[0-9]+$ ]]; then
  R6_MARK="✓"
  R6_TEXT="${BACKLOG_COUNT} open issues labeled backlog"
else
  R6_MARK="⚠️"
  fails=()
  [[ "$GH" != "PRESENT" ]] && fails+=("gh missing")
  [[ "$GH_AUTH" != "OK" ]] && fails+=("gh auth")
  [[ ! "$BACKLOG_COUNT" =~ ^[0-9]+$ ]] && fails+=("count unavailable")
  R6_TEXT="$(IFS=/; echo "${fails[*]}") — queue inactive. Filing an issue sends title+body to GitHub (public repo → public issues)."
fi

# --- emit -------------------------------------------------------------------

cat <<EOF
| Row | Marker | Content |
|---|---|---|
| Install mode | ${R1_MARK} | ${R1_TEXT} |
| Hooks registered | ${R2_MARK} | ${R2_TEXT} |
| .session-continuity/ files | ${R3_MARK} | ${R3_TEXT} |
| CLAUDE_PLUGIN_ROOT | ${R4_MARK} | ${R4_TEXT} |
| Gate scripts executable | ${R5_MARK} | ${R5_TEXT} |
| GitHub backlog | ${R6_MARK} | ${R6_TEXT} |

Notes:
- Never mutates anything. Every fix is a command for you to run.
- Freshness is \`STALE=\` only (no embedded git-log compare).
- Peer hard-fail install order: primer → graphify (commit \`graphify-out/graph.json\`) → engrim → re-doctor.
EOF

exit 0
