# Changelog

All notable changes to `plugin-auditor` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.5] - 2026-05-15

### Fixed
- **Wildcard interpreter grants in `allowed-tools` were classified as CAUTION instead of FAIL.** Patterns like `Bash(python3 *)`, `Bash(node *)`, `Bash(sh *)`, `Bash(bash *)`, `Bash(ruby *)`, `Bash(deno *)` (and similar interpreters with `*` argument) are RCE-equivalent to `Bash(*)`: the wildcard matches `-c "..."` / `-e "..."` / arbitrary file paths, so the model can run any code on the host. The risk model now flags them as FAIL across slash commands (`commands/*.md`), skills (`SKILL.md`), agents (`agents/*.md` `tools` field), and `settings.json` (`permissions.allow`). Same treatment for shell evaluation builtins (`Bash(eval *)`, `Bash(exec *)`, `Bash(source *)`, `Bash(. *)`).
- **`Bash(*)`, bare `Bash`, and `Bash(:*)` were also CAUTION.** Promoted to FAIL for consistency: an unrestricted shell grant is the canonical full-host RCE primitive, not a yellow flag.

### Added
- New severity bucket: script-path-scoped interpreter grants (`Bash(python3 *.py)`, `Bash(node *.js)`, `Bash(ruby *.rb)`) are now CAUTION. Materially narrower than the wildcard form (no inline `-c`/`-e`), but an attacker who can drop a file in CWD still wins. Recommend pinning to a specific module or script path.
- Tightly pinned interpreter invocations (`Bash(python3 -m pytest *)`, `Bash(npm run lint)`, `Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/*.sh)`) are explicitly OK at the permission-grant level (the underlying script is still assessed by the static checklist).
- Expanded the interpreter catalogue beyond the obvious set: `bun`, `osascript` (macOS GUI shell), `pwsh` / `powershell` (cross-platform), `zsh`, `php`, `perl`, plus shell evaluation builtins (`eval`, `exec`, `source`, `.`).

### Changed
- Tool-grant rules now apply symmetrically to `allowed-tools` (commands, skills) and `tools` (sub-agents). A sub-agent with `tools: Bash(python3 *)` has the same RCE primitive as a slash command with the same grant, and is judged the same way.
- Updated `claude-artifacts-checklist.md` (section 6), `risk-model.md` (new "Slash command and agent tool grants" FAIL block plus revised CAUTION/OK rows), `config-patterns.md` (section 1, `permissions.allow` rules), and `auditor-claude-artifacts.md` (workflow step 6) to reflect the new model.

### Notes
- This is a risk-model patch, not an API change. Reports produced by the auditor on repos that previously came back CAUTION because of a wildcard interpreter grant will now come back UNSAFE. If you maintain a plugin that uses `Bash(python3 *)` etc. and you trust the slash command body, narrow the grant to the specific script (`Bash(python3 ./scripts/foo.py)`) or module (`Bash(python3 -m mypackage *)`) to clear the FAIL.

## [0.1.4] - 2026-05-04

### Fixed
- **Sub-agents hit permission-denied on the cloned repository.** `clone_repo.sh` was cloning into `/tmp/plugin-auditor/...`, which sits outside the Claude Code harness CWD. Sub-agents (whose Read/Grep/Glob are scoped to CWD) could not read any file in the audited repository. Clones now land in `${PWD}/.plugin-auditor-tmp/{slug}-{timestamp}/` and work out-of-the-box without the user having to extend `permissions.additionalDirectories`.
- **Reference paths were not being expanded inside the sub-agent prompt.** A literal `${CLAUDE_PLUGIN_ROOT}` in an Agent-tool prompt body is not guaranteed to be expanded — the sub-agent received the raw string and resolved paths against CWD or REPO_PATH. Added a new Step 4a in `SKILL.md` that requires the orchestrator to expand `${CLAUDE_PLUGIN_ROOT}` itself (`echo "${CLAUDE_PLUGIN_ROOT}"`) before building the sub-agent prompt, plus a prompt template with every path already expanded. Each `agents/*.md` now carries a hard rule: "reference files live EXCLUSIVELY under the absolute paths passed by the orchestrator".

### Added
- **Step 10 in `SKILL.md`: clone summary + optional cleanup.** After the report is produced, the orchestrator lists every directory under `${PWD}/.plugin-auditor-tmp/` and uses `AskUserQuestion` to offer three paths: remove only the current clone, remove everything under `.plugin-auditor-tmp/`, or leave as is. Removal goes through the new `cleanup_clone.sh`, which validates the target and refuses to operate outside the allowed base directory.
- New script `skills/audit/scripts/cleanup_clone.sh` with hardened validation: rejects non-absolute paths, paths containing `..`, and anything outside `${PWD}/.plugin-auditor-tmp/`. After deleting the requested clone it collapses the empty base directory automatically.

### Changed
- Sharpened the `description` field of all five sub-agents — "Read-only" → "Read-only with respect to the audited repository", with an explicit note that the agent may run the plugin's own helper scripts (where needed). Documentation-only change, but it prevents regressions of the "someone saw read-only and removed Bash" kind.
- Extended the `audit` skill's `allowed-tools` with two narrow entries: `Bash(echo ${CLAUDE_PLUGIN_ROOT})` (Step 4a) and `Bash(ls -1 ${PWD}/.plugin-auditor-tmp/)` (Step 10).

### Notes
- Moving the clone target from `/tmp/` to CWD means the audited repository briefly lives inside the user's working tree. By default it is not kept around (Step 10 offers cleanup), but adding `.plugin-auditor-tmp/` to the project's `.gitignore` is a good idea if the plugin is used regularly.

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
