# Changelog

All notable changes to `plugin-auditor` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.3] - 2026-05-03

### Changed
- Tightened tool permissions in frontmatter as defense-in-depth.
  - All five sub-agents now declare `disallowedTools: Edit, Write, NotebookEdit, WebFetch, WebSearch`. The audit is intentionally offline; sub-agents never need to write files (the orchestrator is the only writer) or contact external services.
  - The `audit` skill's `allowed-tools` was narrowed: pre-approved Bash is limited to `bash ${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/*` and `git -C * rev-parse HEAD`; pre-approved `Write` is restricted to `${HOME}/.claude/plugin-auditor-reports/**`. Other Bash invocations or writes will surface a normal Claude Code permission prompt.
- Added a "Trust model" section to the README explaining what the plugin grants and denies itself, and recommending optional user-side `permissions.deny` rules for outbound networking commands.

### Notes
- No behavioural change for users running audits as documented. The narrowing only affects scenarios where the model would have improvised outside the documented workflow (e.g. attempted ad-hoc `WebFetch` from a sub-agent).

## [0.1.2] - 2026-04-26

### Added
- Initial release of `plugin-auditor`.
- Manual skill `/plugin-auditor:audit` that orchestrates a static security audit of a local path or remote GitHub/GitLab repository.
- Five parallel sub-agents:
  - `auditor-static` — secrets, obfuscation, binaries, dotfile modifications.
  - `auditor-claude-artifacts` — SKILL.md, agents, hooks, MCP servers, slash commands, prompt injection.
  - `auditor-supply-chain` — `package.json`, `requirements.txt`, lockfiles, typosquatting, runtime fetches.
  - `auditor-config` — `settings.json`, CI/CD workflows, Dockerfile, setup scripts, sandbox evasion.
  - `auditor-network-fs` — URL allowlist, exfiltration patterns, file-system scope, background processes.
- Helper bash scripts for mechanical scanning (`clone_repo.sh`, `scan_secrets.sh`, `scan_obfuscation.sh`, `scan_network.sh`, `scan_binaries.sh`, `compute_delta.sh`, `ensure_reports_dir.sh`).
- Reference files documenting the risk model, checklists, and prompt-injection patterns.
- Markdown report output in `~/.claude/plugin-auditor-reports/` with persistent state for delta audits.
- Test fixtures: `safe-fixture` (known good) and `malicious-fixture` (planted issues across all five sub-agent domains).
