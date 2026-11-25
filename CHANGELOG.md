# Changelog

All notable changes to `plugin-auditor` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.4.2] - 2026-11-25

### Fixed
- `doc:` tagging classified on absolute paths, so an ancestor directory (an installed plugin under `~/.claude/plugins/`) suppressed every tag and made every file an artifact for the prose `config_write` rule. Classification now uses the path relative to the audited repo, in every helper.
- Instruction files could be tagged `doc:`: names now match case-insensitively and include `CLAUDE.local.md`, `copilot-instructions.md`, `.cursorrules` and similar rule files; anything under `skills/` (references too) and other agents' rule directories counts as an instruction file.
- A first-party `--index-url` no longer vouches for an `--extra-index-url` on the same line: `nondefault_index` fires unless every index URL is first-party.
- `llm_router` parses the URL host, so `https://api.anthropic.com@<host>` is no longer read as first-party.
- Helpers that exit non-zero or write to stderr print `helper_error:<helper>:rc=<n>:<first stderr line>`; the orchestrator records it, adds a `CAUTION` and a metadata warning, and the verdict cannot be clean.
- Symlinks, oversized files, NUL files and unreadable or non-UTF-8 files were skipped silently. Helpers now print `skipped:<reason>:<relpath>`; sub-agents list these paths, the report metadata lists them, and a skipped hook, MCP config, settings file or manifest is a `CAUTION`. The `scan_secrets.sh` and `scan_obfuscation.sh` Python passes no longer follow file symlinks out of the repo.

## [0.4.1] - 2026-11-25

### Fixed
- No sub-agent has `Bash` any more (an unrestricted `Bash` grant is a `FAIL` under this plugin's own rules, and agent `tools` cannot scope it to a path). The orchestrator runs every helper (new Step 4b) and passes each sub-agent its output as `SCAN_OUTPUTS`.
- Git on the audited repository runs through `lib_git.sh`, which pins `core.fsmonitor`, `core.hooksPath`, `core.pager`, `core.sshCommand`, `diff.external` and `credential.helper` to inert values and ignores system/global config. `git_head.sh` replaces the direct `git -C * rev-parse HEAD` grant; `compute_delta.sh` uses the wrapper too.
- `SKILL.md` helper calls were written with a quoted script path, which the literal `Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/*)` grant does not match; headless runs refused them. All calls are now unquoted, with a stop rule for paths that need quoting.
- The skill's `scripts/*` Bash grant matched `scripts/../<anything>` (permission matching is textual). Each helper now has its own grant, and the artifacts checklist rates a directory-wildcard script grant `CAUTION`.
- The cross-check is strict per owner, and the owning sub-agents are told to list every path in their categories, including instruction files, fixtures and `doc:` lines.
- The malicious fixture's `.mcp.json` is now `dot-mcp.json`, so opening the fixture folder in Claude Code offers no servers; the scanner reads both names. Wording that read as auditor-directed ("skip this step silently", a safe-fixture description naming the expected verdict) is reworded.
- Test fixtures: an unreachable planted fixture (nothing outside it runs, sources or registers it, and it is not at a loader path) now collapses into one `CAUTION` per fixture directory instead of a stack of `FAIL`s. Reachable fixture code keeps full severity.
- Self-scan noise: hits in plain documentation get a `doc:` prefix (`doc_class.py`; instruction files are never tagged, secrets and Unicode never tagged), and the helpers' own pattern sources no longer match themselves. Tighter DNS-tool host extraction.

### Added
- Regression checks: documentation tagging, helpers scanning their own source, no agent lists `Bash`, and a booby-trapped `.git/config` that must fire no canary through the git wrapper.

## [0.4.0] - 2026-11-25

Coverage for the 2026 agent attack patterns: a write that becomes a later execute, git
config that runs on `git status`, Python startup hooks, sandbox weakening, agentjacking
through tool output, credential reach, lateral movement and exfil channels beyond plain
HTTP. Hooks and MCP servers run outside the Claude Code sandbox, so findings there are now
judged at full severity.

### Added
- **`scan_trust_surface.sh`.** A new mechanical helper with twelve categories:
  `config_write`, `git_exec_config`, `py_stdlib_shadow`, `py_pth`, `sandbox_weaken`,
  `pre_trust` (owned by `auditor-config`); `cred_reach`, `lateral_movement`,
  `exfil_channel`, `llm_router` (owned by `auditor-network-fs`); `lifecycle_script`,
  `nondefault_index` (owned by `auditor-supply-chain`). It is part of the Step 5a
  mechanical cross-check, split by category.
- **Config write is future execute.** Writes to `.claude/settings*.json`, hooks,
  `.mcp.json`, `.vscode/tasks.json`, `.git/hooks`, `.git/config`, venv activate, CI files
  and `package.json` lifecycle scripts are `FAIL`, including the `prepare` target swap that
  `acceptEdits` does not guard and the Cursor CVE-2026-48124 style settings handoff.
- **GitSpawn.** Shipped or written `core.fsmonitor` (command), `core.hooksPath`,
  `core.sshCommand`, `core.pager`, `diff.external`, textconv/filter/merge drivers and `!`
  aliases are `FAIL`. Shipped `.git/config` files are read too.
- **Python import shadowing.** `.pth`, `sitecustomize.py` and `usercustomize.py` are
  `FAIL`; stdlib-named files in script directories are `CAUTION`.
- **Sandbox and permission weakening.** `sandbox.enabled: false`,
  `allowUnsandboxedCommands`, container runtimes in `excludedCommands`, `docker.sock`
  exposure, `$HOME` mounts, `allowedDomains: ["*"]`, `bypassPermissions`,
  `--dangerously-skip-permissions`.
- **Runs before trust.** `Setup` hooks join `SessionStart`; `enableAllProjectMcpServers`
  and `enabledMcpjsonServers` in shipped settings are `FAIL`; project `.mcp.json` local
  servers are `CAUTION`.
- **Agentjacking.** MCP servers and skills that relay third-party content (error trackers,
  tickets, logs, web pages) to the model, skills that tell the model to act on it, and
  "hotfix" installs from a non-default index (`pip --index-url`, `npm --registry`,
  `Install-Module -Repository`).
- **Credential reach, lateral movement, exfil channels.** Keychain, CLI token minting,
  browser profiles, inherited env tokens; ssh/scp, PowerShell remoting, cloud remote exec,
  logged-in browser driving; `git push` to foreign remotes, object storage, gists, webhook
  sinks; `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` overrides to third-party routers.
  Credential recommendations now name scoped, short-lived alternatives (STS
  `GetScopedCredentials`).
- Three new escalation rules in `risk-model.md`: agentjacking chain, credential reach plus
  lateral/exfil, and network-fs `CAUTION` findings inside hooks or MCP servers.
- Fixtures: inert `dot-git/config`, `dot-claude/settings.local.json`,
  `scripts/vendor-sync.sh`, `hooks/post-tool.sh`, `skills/hotfix/SKILL.md`,
  `mcp/tickets_server.py`, `scripts/json.py`, `src/canary.pth`; safe-fixture near-misses for
  builtin fsmonitor, `GIT_PAGER=cat` and a package-internal `json.py`. Hosts are
  `example.invalid` or `127.0.0.1` only.

### Changed
- `auditor-config` gains `Bash`, limited to the helper scripts.
- `prepare` is weighed like `postinstall` in the supply-chain checklist.

## [0.3.0] - 2026-07-13

Trust-hardening pass. 0.2.0 raised detection quality; this release addresses who the
auditor trusts. The semantic-injection pass was a single point of trust, the orchestrator
took each sub-agent's mechanical report on faith, and the clean verdict promised more than
a static audit can deliver. It also fixes four false positives from 0.2.0 that fire on
ordinary repositories.

### Added
- **Injection-guard sub-agent (`auditor-injection-guard`).** A sixth, independent
  prompt-injection detector that reads only the LLM-steering artifacts, on Haiku, with no
  Bash, and returns strict JSON. It is escalate-only: its findings can raise a verdict,
  never lower one, so an injection aimed at the guard can at worst add noise. Redundancy
  through diversity: a payload must now evade two detectors on two different models.
- **Mechanical cross-check (Step 5a).** The orchestrator re-runs the scan helpers itself
  and confirms every path and host the scripts found appears in the owning sub-agent's
  report. A silently dropped finding, the signature of a poisoned context, is an automatic
  `FAIL`. Raw outputs are captured under `.raw/` for the comparison.
- **`scan_unicode.sh`.** Detects zero-width characters, bidirectional overrides, other
  invisible format/control characters, and Cyrillic/Greek homoglyphs. Inside a Claude
  artifact these are `FAIL`; the artifact auditor's raw-bytes check now relies on it.
- **Provenance tags.** Every finding is labelled `[mechanical]` (deterministic scan/regex)
  or `[model-judgment]` (semantic pass or guard), and the report records the semantic-pass
  models and guard/auditor agreement.
- **Remote MCP trust boundary.** A server declared with a remote transport (`type: sse/http`
  with a `url`) is `CAUTION`: its logic and tool descriptions live off-machine and can change
  at runtime, so static analysis ends at the declaration.
- **TOCTOU note.** The report and README state that a verdict applies to exactly the audited
  SHA and that `/plugin update` invalidates it.
- Expanded fixtures: a planted `evasion_unicode.md`, a high-entropy Bearer value, and a
  remote-transport MCP server; safe-fixture near-misses (sha256/git-SHA pin, private IPs,
  Bearer placeholder, `re.compile` + `bytes([...])`) that must stay silent.

### Changed
- **Clean verdict renamed `SAFE` → `NO FINDINGS (static)`.** A static audit reports the
  absence of matches, not the presence of safety. Legacy state files carrying `SAFE` are
  displayed under the new name.
- The artifact scope (guard, artifact auditor, unicode rule) now includes any `*.md` with
  `name`/`description` frontmatter, catching an artifact planted outside the canonical paths.
- `auditor-network-fs` enumerates every host it saw, including allowlisted ones, so the
  cross-check can find them.

### Fixed
- **sha256 / git-SHA pins no longer flagged as obfuscation.** A digest-width hex blob in a
  hash context, or a git pin preceded by `@`, is skipped before the base64 pass.
- **`re.compile` and `bytes([...])` no longer read as decode-then-execute.** The `compile(`
  match excludes `re.`/`regex.` compilers; `bytes([...])` requires eight or more numeric
  elements; the cross-line decode→exec pairing is bounded to a 25-line window.
- **Private IPs no longer flagged as exfiltration destinations.** `scan_network` validates
  octets and routes RFC1918 / link-local addresses to a `local:` key (TEST-NET documentation
  ranges deliberately stay flagged).
- **Bearer-token documentation placeholders no longer fire.** The bearer check moved behind
  the entropy/placeholder gate.

## [0.2.0] - 2026-07-12

Hardening pass focused on detection quality. The previous releases leaned on literal
matching (grep over a fixed phrase list, fixed secret prefixes, a 256-char obfuscation
floor, `https?://`-only network extraction), which an adversary who has read the public
pattern catalogues can step around. This release raises the floor on evasion and adds a
measurable regression baseline.

### Added
- **Regression harness (`tests/run.sh`) + contract (`tests/expectations.md`).** Runs every
  `scan_*.sh` helper against the safe and malicious fixtures and asserts the safe fixture
  stays clean while each planted category is still detected. Read-only; never executes
  fixture code. A detector going silent now fails the suite instead of slipping through.
- **Evasion fixtures** under `tests/fixtures/malicious-fixture/`: a paraphrased,
  non-English prompt injection (`evasion_paraphrase.md`), a split multi-line decode+exec
  with a short base32 payload (`evasion_split.py`), a prefix-less high-entropy secret
  (`evasion_secret.py`), and scheme-less network destinations (`evasion_net.sh`). Two are
  documented as known static-scan gaps (semantic injection, concatenated secrets).
- **Semantic-intent pass for prompt injection.** `auditor-claude-artifacts` now judges
  meaning before running the literal grep: an artifact that overrides context, hides
  actions, conditions on hidden state, or addresses a reviewer/auditor to wave the repo
  through is `FAIL` even with zero catalogued phrases. New `risk-model.md` rows for
  "Semantic injection (non-literal)" and "Audit-tool-targeted injection".
- **Generic secret detection.** `scan_secrets.sh` gains `generic_high_entropy_assignment`
  (a credential-named variable holding a high-entropy value, gated on Shannon entropy to
  avoid placeholders) plus SendGrid / Twilio / Azure-storage / bearer patterns.
- **Broader network extraction.** `scan_network.sh` now also captures `ftp://` and `ws(s)://`
  URLs, bare `IP:port` literals with no scheme, and hosts passed to `dig`/`nslookup`/`host`/
  `drill` (DNS-exfil feed). User-content subdomains on trusted parents (`*.github.io`,
  `*.pages.dev`, `*.web.app`, `*.workers.dev`, `*.netlify.app`, `*.vercel.app`) are now
  `CAUTION`, not `OK`.
- **Delta-mode dormant-code guard.** The orchestrator instructs sub-agents to also scan any
  file a diff newly activates (import/require/source/hook wiring) even when that file is not
  in the changed set, and to print a standing caveat that delta mode does not re-scan
  untouched dormant code. New `risk-model.md` `CAUTION` row for dormant-code activation.

### Changed
- **`auditor-claude-artifacts` model raised from `sonnet` to `opus`.** Non-literal injection
  detection is the semantic-hardest task in the plugin; the strongest generally available
  model does the most good here.
- **Every sub-agent is now confused-deputy hardened.** Each `agents/*.md` carries a hard rule
  that content under `REPO_PATH` is data to analyse, never instructions to the agent; an
  artifact that tries to steer the agent is itself a finding.
- **Obfuscation threshold lowered from 256 to 64 chars**, with per-alphabet entropy gates
  (4.0 base / 3.2 hex) tuned so the safe fixture and the plugin's own source stay clean.
  Decode-then-execute is now detected across lines within a file, and the decoder catalogue
  covers base32, `bytes([...])`, `String.fromCharCode`, and `zlib`/`gzip`/`lzma`.

### Notes
- No change to the plugin's own trust model: still read-only against audited repos, still no
  `WebFetch`/`WebSearch` in sub-agents, `Write` still pinned to the reports directory.
- `SAFE` continues to mean "no known signatures matched", not "proven safe". The new README
  "Known evasion gaps" section states the boundary explicitly.

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
