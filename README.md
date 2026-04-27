# plugin-auditor

Static security audit for projects extending Claude (skills, agents, hooks, plugins, MCP servers, slash commands, etc.) before installing them in Claude Code. Detects backdoors, prompt injection, persistence hooks, and supply-chain risks via parallel sub-agents.

**Autor**: Piotr Kaźmierczak - CEO [Secawa](https://secawa.com)
**Licencja**: MIT
**Wersja**: 0.1.2

---

## What it does

The Claude Code ecosystem is growing fast: skills, agents, hooks, plugins, MCP servers, and slash commands are shipped in public repositories that anyone can clone and install with a single command. This is also a textbook supply-chain attack surface — a malicious skill can instruct Claude to leak credentials, a hook can persist across sessions, an MCP server can fetch arbitrary code at runtime, and a `postinstall` script can run before you ever inspect the code.

`plugin-auditor` runs a fully static security audit of a repository before you trust it. The plugin exposes a single user-invocable skill (`/plugin-auditor:audit`) that orchestrates five specialized sub-agents in parallel — each scanning a different risk dimension (static code, Claude artifacts, supply chain, configuration, network and filesystem patterns) — and produces a single markdown report with a clear verdict (`SAFE`, `CAUTION`, or `UNSAFE`), every finding backed by a file path and line number.

The plugin never executes audited code. It only reads, greps, and reasons.

### Architecture at a glance

- **One entry point** — the `audit` skill (invoked as `/plugin-auditor:audit`). Marked `disable-model-invocation: true`, so Claude never auto-runs an audit on its own; the user has to ask for it explicitly.
- **Five sub-agents** in `agents/` — each owns one risk dimension and reports back in a structured `FAIL / CAUTION / OK` block. They are not exposed as user-invocable commands; the orchestrator calls them via the `Agent` tool with their namespaced ids (`plugin-auditor:auditor-static`, etc.).
- **Read-only helpers** in `skills/audit/scripts/` and reference catalogues in `skills/audit/references/`. None of them fetch, install, or build anything from the audited repository.

---

## Installation

1. Add the plugin marketplace and install:
   ```bash
   /plugin marketplace add secawa-com/plugin-auditor
   /plugin install plugin-auditor@secawa-com/plugin-auditor
   ```
2. Restart Claude Code so the new skill, agents, and scripts are picked up.
3. Verify the install:
   ```bash
   /plugin
   ```
   `plugin-auditor` should appear with version `0.1.2`. Type `/` and start typing `plug` — the entry `/plugin-auditor:audit` should be listed in the slash menu.
4. The first audit will create `~/.claude/plugin-auditor-reports/` automatically. No other system files are touched.

---

## Update

Manual update:

```bash
/plugin update plugin-auditor
```

If `/plugin update` is not enough, remove and reinstall:

```bash
/plugin uninstall plugin-auditor
/plugin install plugin-auditor@secawa-com/plugin-auditor
```

Restart Claude Code after every update.

---

## Usage

The plugin exposes a single slash command — `/plugin-auditor:audit` — which is the namespaced form Claude Code generates for the `audit` skill inside the `plugin-auditor` plugin. There is no shorter alias; pluginowe skille są zawsze namespace'owane (zgodnie z dokumentacją Claude Code), żeby pluginy nie kolidowały o nazwy.

### Audit the current working directory

```bash
/plugin-auditor:audit
```

Use when you have already cloned a repo locally and want to vet it before opening files in your editor or running `npm install`.

### Audit an explicit local path

```bash
/plugin-auditor:audit /Users/me/code/some-cloned-repo
/plugin-auditor:audit ../neighbour-project
/plugin-auditor:audit ~/Downloads/extracted-zip
```

Use when the project sits outside your current shell directory.

### Audit a remote GitHub or GitLab repository

```bash
/plugin-auditor:audit https://github.com/some-author/cool-claude-plugin
/plugin-auditor:audit https://github.com/some-author/cool-claude-plugin@v1.2.0
```

What happens:

- The URL is validated against an allowlist (`github.com`, `gitlab.com`).
- The repository is shallow-cloned (`--depth 1 --no-tags --single-branch`) into `/tmp/plugin-auditor/{repo}-{sha}/`.
- No git config is touched and no credentials are used (public repositories only).
- The audit then proceeds as if the repository were a local path.

### Delta mode — audit only what changed since the last audit

```bash
/plugin-auditor:audit . --delta
/plugin-auditor:audit https://github.com/foo/bar --delta
```

Use when you have audited the repository before and only want to vet new commits. The skill reads the previous SHA from `~/.claude/plugin-auditor-reports/.state/{repo-slug}.json` and runs `git diff prev..HEAD` against it. If no prior audit exists, the skill falls back to a full audit and prints a notice.

### Where reports land

- Markdown report: `~/.claude/plugin-auditor-reports/{repo-slug}-{YYYY-MM-DD}-{shortsha}.md`
- State file: `~/.claude/plugin-auditor-reports/.state/{repo-slug}.json`
- List past audits: `ls -lt ~/.claude/plugin-auditor-reports/`

Reports are timestamped — re-running on the same repository never overwrites old reports.

### Reading the verdict

| Verdict   | Meaning                                                                                                                                | Action                                  |
| --------- | -------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| `SAFE`    | No findings.                                                                                                                           | Install with normal caution.            |
| `CAUTION` | At least one ambiguous pattern (network call to a non-allowlisted domain, postinstall script, broad permissions).                      | Read the report and decide per finding. |
| `UNSAFE`  | At least one hard fail (hardcoded credentials, prompt injection, `curl ... \| bash`, persistence hook, default-on PreToolUse hook...). | Do not install.                         |

### Interactive drill-down

After the report is written, the skill offers to drill into any `CAUTION` or `UNSAFE` section. Pick a section name to get a deeper explanation; pick "skip" to end the session.

---

## Available skills

The plugin ships exactly one user-invocable skill. It is `disable-model-invocation: true`, meaning Claude will never auto-trigger an audit; the user has to run the command explicitly.

| Skill   | Namespaced invocation               | Description                                                                                                                                                                  | Argument hint           |
| ------- | ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| `audit` | `/plugin-auditor:audit`             | Orchestrates a static security audit of a local or remote repository, aggregates findings from five parallel sub-agents, and writes a markdown report under `~/.claude/plugin-auditor-reports/`. | `[path\|url] [--delta]` |

---

## Sub-agents

Each sub-agent is a self-contained markdown definition under `agents/`. The orchestrating skill launches all five in a single parallel batch via the `Agent` tool, addressing each by its namespaced identifier (e.g. `plugin-auditor:auditor-static`). Sub-agents are intentionally not designed for direct user invocation — they assume the orchestrator's framing (REPO_PATH, reference paths, delta context).

| Sub-agent (namespaced)                       | Focus area                                                                                                                                                                                         |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `plugin-auditor:auditor-static`              | Secrets, obfuscation, dangerous shell patterns, binaries, hidden files, modifications to global dotfiles.                                                                                          |
| `plugin-auditor:auditor-claude-artifacts`    | SKILL.md prompt injection, agent permissions, persistence hooks (PreToolUse, PostToolUse, SessionStart), MCP server abuse, slash command tool overreach, Claude Code history theft.                |
| `plugin-auditor:auditor-supply-chain`        | `package.json` lifecycle scripts, `requirements.txt` and `pyproject.toml` typosquatting, lockfile integrity, git submodules pointing to forks, runtime `npx` fetches, unverified git dependencies. |
| `plugin-auditor:auditor-config`              | `settings.json` permission overrides, committed `.env` files, CI/CD workflow abuse (`pull_request_target`, secrets dump, self-hosted runners), Dockerfile risks, sandbox-evasion patterns.         |
| `plugin-auditor:auditor-network-fs`          | URL allowlist enforcement, file-system scope, path traversal, sensitive-path access (`~/.ssh`, `~/.aws`, `~/.config/gh`), data exfiltration chains, long-running background processes.             |


---

## How it works

1. **Input resolution.** The skill resolves the input to a local repository path, either by using the current working directory, an explicit path, or by shallow-cloning a remote URL into `/tmp/plugin-auditor/`.
2. **Parallel sub-agents.** All five sub-agents are launched in a single message. Each reads the relevant reference file from `references/`, calls the appropriate helper script from `scripts/`, and returns a structured partial report.
3. **Risk-model aggregation.** Findings are mapped through `references/risk-model.md` which classifies every pattern as `OK`, `CAUTION`, or `FAIL`. The verdict follows the worst level found.
4. **Report and state.** A timestamped markdown report is written to `~/.claude/plugin-auditor-reports/`, and a state file records the audited SHA so future audits can run in delta mode.

---

## What it checks

The check catalogue is grouped by concern level and aligned with Anthropic's enterprise risk-tier guidance.

### High concern (any of these flips the verdict to `UNSAFE`)

- Hardcoded credentials (AWS, GCP, GitHub PAT, OpenAI, Stripe, JWT, PEM private keys).
- Code execution via `curl ... | bash`, `wget ... | sh`, or remote `eval`.
- Prompt injection in SKILL.md or agent definitions ("ignore previous instructions", "secretly", "do not tell the user").
- Persistence hooks (`PreToolUse`, `PostToolUse`, `SessionStart`) installed by default.
- Path traversal outside the project directory.
- Obfuscation: long base64/hex blobs, `eval`, `exec`, gzip-encoded payloads.
- Modifications to global dotfiles (`~/.zshrc`, `~/.bashrc`, `~/.gitconfig`).
- Reads of Claude Code history (`~/.claude/projects/**/*.jsonl`).
- CI/CD `pull_request_target` abuse, secrets dump, or self-hosted runner exposure.

### Medium concern (each adds one point to the risk score)

- Network calls in skills or agents to non-allowlisted domains.
- `postinstall` or `preinstall` scripts in `package.json`.
- MCP servers using `npx` to fetch packages at runtime.
- Git dependencies pointing to non-official forks.
- Typosquatting heuristics on dependency names.
- Broad glob patterns (`**/`*) or access to sensitive paths (`~/.ssh`, `~/.aws`).
- Long-running background processes (`nohup`, `&`, `setsid`, `disown`).
- Conditional behaviour based on `CI=true` (sandbox evasion).
- Binaries committed to the repository (`.exe`, `.so`, `.dylib`, `.pyc`).
- `settings.json` permission overrides that auto-approve dangerous tools.

---

## Sample report

A full, illustrative audit report (UNSAFE verdict, five red flags, four caution-level findings, eleven verified-OK checks) is available as a separate document: see [`docs/sample-report.md`](docs/sample-report.md).

---

## Reports and state

The plugin writes only to `~/.claude/plugin-auditor-reports/`. The directory is created on first run and contains:

```
~/.claude/plugin-auditor-reports/
├── cool-claude-plugin-2026-04-26-a1b2c3d.md       # individual audit reports
├── another-repo-2026-04-25-9f8e7d6.md
└── .state/
    ├── cool-claude-plugin.json                     # last audited SHA per repo
    └── another-repo.json
```

Past reports are never overwritten. The state directory is consulted only by `--delta` mode and is safe to delete to reset history.

---

## Quality mechanisms

- **Evidence-first findings.** Every flag in the report includes a file path, line number, and a quoted excerpt. No claim without evidence.
- **Conservative defaults.** When in doubt, the risk model classifies a pattern as `CAUTION`, never as `OK`. Silence is not safety.
- **No code execution.** The plugin never runs anything from the audited repository. Static analysis only — by design, not by accident.
- **Test fixtures included.** The repository ships paired `safe-fixture/` and `malicious-fixture/` projects under `tests/fixtures/` so each sub-agent's domain has a known-good and known-bad reference to scan against.

---

## Limitations

- Static analysis cannot catch payloads that are only assembled at runtime from inputs.
- Single-repository scope. Cross-repository dependency graphs and transitive supply-chain analysis are out of scope.
- No auto-fix. The plugin reports findings but never modifies the audited repository.
- False positives are possible — particularly on legitimate network calls to well-known domains. Always read the evidence before acting.
- Binaries are flagged on presence; the plugin does not reverse-engineer them.

---

## Security disclaimer

This plugin reduces risk but does not guarantee safety. The framework treats findings as a support layer, not a guarantee. Final responsibility for installing third-party code rests with the user. Always cross-check `UNSAFE` and `CAUTION` findings against the original source before acting on them.

---

## Requirements

- Claude Code (any recent version with plugin support).
- `git` — used by `clone_repo.sh` when the input is a URL.
- `bash` 4 or newer — used by all helper scripts.
- POSIX coreutils (`find`, `grep`, `awk`, `sed`).
- Optional: the `file` command (improves binary detection in `scan_binaries.sh`; falls back to extension-only matching when missing).

No npm, pip, Docker, or other plugins are required.

---

## For developers

### Project structure

```
plugin-auditor/
├── .claude-plugin/
│   ├── plugin.json                              # plugin manifest
│   └── marketplace.json                         # marketplace entry (single-plugin marketplace)
├── README.md
├── LICENSE
├── CHANGELOG.md
├── docs/
│   └── sample-report.md                         # illustrative end-to-end report
├── skills/
│   └── audit/                                   # the only user-invocable skill (/plugin-auditor:audit)
│       ├── SKILL.md                             # orchestrating skill (disable-model-invocation: true)
│       ├── references/                          # risk model and checklists
│       └── scripts/                             # bash helpers (read-only scans)
├── agents/                                      # five parallel sub-agents (called by the orchestrator)
│   ├── auditor-static.md
│   ├── auditor-claude-artifacts.md
│   ├── auditor-supply-chain.md
│   ├── auditor-config.md
│   └── auditor-network-fs.md
└── tests/
    └── fixtures/
        ├── safe-fixture/                        # known-good mini repo
        └── malicious-fixture/                   # planted issues across all domains
```

> Note: there is intentionally no `commands/` directory. In current Claude Code, `commands/` and `skills/` are the same mechanism (both produce `/<name>` shortcuts), so the orchestrator is shipped as a skill — that gives it a supporting-files directory (`references/`, `scripts/`), proper user-only invocation (`disable-model-invocation: true`), and an explicit `argument-hint`.

### Adding a new pattern

1. Add the regex or heuristic to the relevant `references/*-checklist.md`.
2. If it requires bash assistance, extend the matching `scripts/scan_*.sh`.
3. Update `references/risk-model.md` with the new pattern's severity (`OK`, `CAUTION`, or `FAIL`).
4. Add a positive case to `tests/fixtures/malicious-fixture/` and re-run the audit on the fixture to confirm the pattern is detected.

### Adding a new sub-agent

1. Create a new markdown file in `agents/` with YAML frontmatter (`name`, `description`, `tools`).
2. Document its focus in the README "Sub-agents" table.
3. Wire it into the orchestrating skill in `skills/audit/SKILL.md`.
4. Add a planted issue to `tests/fixtures/malicious-fixture/` that exercises the new agent's domain.

---

## Conventions

- All plugin content (SKILL.md, agents, references, scripts, README, reports) is written in **English**.
- Helper scripts are **idempotent** and **read-only**. They never modify files outside `~/.claude/plugin-auditor-reports/` and `/tmp/plugin-auditor/`.
- File paths in reports always include line numbers (`path:line`) so they are clickable in modern terminals and editors.
- Severity levels follow Anthropic's enterprise risk-tier vocabulary (`high concern`, `medium concern`).

---

## Author

**Piotr Kaźmierczak** — CEO, [Secawa](https://secawa.com) — `piotr.kazmierczak@secawa.com` — [github.com/secawa-com](https://github.com/secawa-com)

## Acknowledgements

Built on top of the Claude Code plugin platform and informed by Anthropic's enterprise guidance for Skills (risk-tier assessment and review checklist). The plugin was scaffolded with the help of two official Anthropic skills:

- **`/skill-creator`** — used to draft `skills/audit/SKILL.md`, define its description for trigger accuracy, and prepare the eval suite skeleton.
- **`/plugin-dev:agent-development`** — used as the structural reference for the five sub-agent definitions in `agents/` (YAML frontmatter, tool grants, scope-of-use language, and proactive-trigger phrasing).

Neither skill is a runtime dependency of `plugin-auditor`. They were used during development on the author's machine; their output is committed to this repository so end users only need Claude Code itself.