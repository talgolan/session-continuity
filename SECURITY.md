# Security policy

Thanks for taking the time to look at security on this plugin. session-continuity is a small project with a narrow surface area, but it does ship hooks that execute shell scripts on every Claude Code session, so security issues matter.

## Scope

In scope for a security report:

- Command injection, path traversal, or arbitrary-code execution in the shell hooks (`hooks/*.sh`).
- Any path by which untrusted input (Claude Code hook JSON payloads, user-supplied file paths, GitHub tag names fed into CI) can cause the hooks or release workflow to execute attacker-controlled code.
- Privilege escalation in `.github/workflows/release.yml` (the workflow holds `contents: write` on this repo).
- Leakage of secrets or credentials caused by the plugin's behavior.

Out of scope:

- Claude Code itself — report those to Anthropic directly at <https://www.anthropic.com/security>.
- Third-party MCP servers or other plugins that users happen to have installed alongside this one.
- Denial-of-service against a user's own machine from misusing the slash commands (e.g. asking Claude to loop forever). The slash commands are prose instructions to Claude; they don't execute user-supplied shell.

## Reporting

Please open a private report via GitHub's **Security → Report a vulnerability** tab on the repo: <https://github.com/talgolan/session-continuity/security/advisories/new>.

If GitHub Security Advisories isn't available to you for some reason, you can also email the maintainer directly — the email is in recent commit metadata (`git log --format='%ae' -1`).

Please include:

- A minimal reproduction (hook payload, commit/tag contents, etc.).
- The version of the plugin you tested against (`cat .claude-plugin/plugin.json`).
- What you believe the impact is.

A reasonable response should arrive within a week. If you haven't heard back after two weeks, please escalate by opening a (non-detailed) public issue pointing at the advisory.

## Design notes relevant to security reviewers

- **Hooks read stdin JSON, not env vars.** Claude Code delivers hook payloads as stdin; the hooks extract `cwd` and `tool_input.command` from that JSON using `grep`/`sed`. These values are only used as test operands (`[ -d ]`, `[ -f ]`), as an argument to `git -C`, or matched against a `case` glob pattern — never `eval`ed or interpolated into a shell string that gets executed. Failure modes on malformed input are a silent `exit 0`.
- **Network call.** `hooks/version-check.sh` makes one unauthenticated `HEAD`-style GET per week per machine to the public GitHub Releases API, with a 3-second timeout, silent failure, and an opt-out env var (`SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`). No analytics, no identifiers, no PII. The cache key is stored at `${XDG_CACHE_HOME:-$HOME/.cache}/session-continuity/last-check`.
- **Release workflow input validation.** `.github/workflows/release.yml` reads the tag name from `GITHUB_REF_NAME`, strips the leading `v`, and validates the result against a strict semver regex before feeding it to `awk`. Additional belt-and-suspenders: the `awk` pattern uses `index()` (string-literal match) rather than regex (`~`), so unusual characters in the tag name can never become pattern metacharacters.
- **Hook matcher scope.** The `PreToolUse` hook is registered with `matcher: "Bash"` plus a per-hook `if: Bash(git commit *)` filter, so the hook script only spawns when Claude is about to run `git commit` — not on every `ls`/`grep`/`cat`.
