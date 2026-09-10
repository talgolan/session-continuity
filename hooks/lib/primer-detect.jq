# CONTRACT_VERSION=1
# hooks/lib/primer-detect.jq — /session-continuity:primer dispatch decision.
# Invoked via primer-detect.sh; see that file for the CLI contract and
# meta/superpowers/specs/2026-09-08-primer-detect-design.md (amended by
# 2026-09-10-primer-detect-freshness-design.md) for the state machine.
#
# All decision logic lives here, not in the .sh wrapper — no I/O, so this
# is directly fixture-testable with synthetic strings (see the smoke test).
# LOG_DRIFT is injected by the .sh wrapper from primer-freshness.sh
# (not computed from an embedded git-log block).
# The trigger chain is evaluated by threading each trigger's effect
# forward into the fact the next trigger reads (PROJ_OI, PROJ_BL below),
# not by writing out "OR about to become true" disjunctions per trigger —
# see the spec's "Why threading, not disjunctions" note for why the naive
# approach doesn't compose past one chained link.

def has_inline_outstanding:
  test("(?m)^## Outstanding items");

def is_allowlisted:
  (startswith("docs/") or startswith(".session-continuity/")) as $dir_ok
  | (split("/") | .[-1]) as $base
  | ($base | test("^(README|CHANGELOG|LICENSE)")) as $name_ok
  | ($dir_ok or $name_ok);

def code_staged($files):
  ($files | split("\n") | map(select(length > 0))) as $paths
  | ($paths | any(is_allowlisted | not));

def github_origin($origin):
  $origin | test("github\\.com");

($primer_content | has_inline_outstanding) as $INLINE
| ($log_drift) as $DRIFT
| (code_staged($staged_files)) as $STAGED
| (github_origin($origin_url)) as $GH

| ($project_context_exists == 0) as $DO_SPLIT
| ($INLINE and ($outstanding_items_exists == 0)) as $DO_OSPLIT
| (if $DO_OSPLIT then 1 else $outstanding_items_exists end) as $PROJ_OI
| ($PROJ_OI == 1 and $backlog_exists == 0) as $DO_BRENAME
| (if $DO_BRENAME then 1 else $backlog_exists end) as $PROJ_BL
| ($PROJ_BL == 1 and $GH) as $DO_B2I
| ($DRIFT == 1 or $STAGED) as $DO_REFRESH

| ([]
   | if $DO_SPLIT then . + ["split"] else . end
   | if $DO_OSPLIT then . + ["outstanding_split"] else . end
   | if $DO_BRENAME then . + ["backlog_rename"] else . end
   | if $DO_B2I then . + ["backlog_to_issues"] else . end
   | if $DO_REFRESH then . + ["refresh"] else . end
  ) as $triggered_steps
| (if $primer_exists == 0 then ["init"] else $triggered_steps end) as $steps

| ("PRIMER_EXISTS=" + ($primer_exists|tostring)),
  ("LEARNINGS_EXISTS=" + ($learnings_exists|tostring)),
  ("PROJECT_CONTEXT_EXISTS=" + ($project_context_exists|tostring)),
  ("OUTSTANDING_ITEMS_EXISTS=" + ($outstanding_items_exists|tostring)),
  ("PRIMER_HAS_INLINE_OUTSTANDING=" + (if $INLINE then "1" else "0" end)),
  ("BACKLOG_EXISTS=" + ($backlog_exists|tostring)),
  ("ROADMAP_EXISTS=" + ($roadmap_exists|tostring)),
  ("GITHUB_ORIGIN=" + (if $GH then "1" else "0" end)),
  ("LOG_DRIFT=" + ($DRIFT|tostring)),
  ("CODE_STAGED=" + (if $STAGED then "1" else "0" end)),
  ("STEPS=" + ($steps | join(",")))
