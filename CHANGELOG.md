# Changelog

All notable changes to `plugin-auditor` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
