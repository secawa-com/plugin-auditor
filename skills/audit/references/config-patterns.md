# Configuration Patterns Checklist

Reference for the `auditor-config` sub-agent. Configuration files often run before any source code and can subvert the entire trust model of a system.

## Scope

Files to scan:

- `settings.json`, `settings.local.json` — Claude Code settings.
- `.github/workflows/*.yml`, `.gitlab-ci.yml`, `.circleci/config.yml`, `.travis.yml`, `azure-pipelines.yml`, `Jenkinsfile` — CI/CD.
- `Dockerfile`, `docker-compose.yml`, `*.dockerfile` — container builds.
- `Makefile`, `justfile`, `Taskfile.yml`, `package.json` `scripts` (cross-checked with supply-chain).
- `setup.sh`, `install.sh`, `bootstrap.sh`, any top-level shell installer.
- `.env`, `.env.example` (presence only — content not parsed).
- Any shipped git config: `.git/config`, `dot-git/config`, `*.gitconfig`, plus `git config` / `git -c` invocations anywhere.
- `*.pth`, `sitecustomize.py`, `usercustomize.py`, and `.py` files named like stdlib modules.
- `hooks/hooks.json` and every `settings*.json` (sandbox, permission mode, MCP auto-approval, `env`).

The helper `scripts/scan_trust_surface.sh` pre-extracts sections 9 to 13. This agent owns its `config_write`, `git_exec_config`, `py_stdlib_shadow`, `py_pth`, `sandbox_weaken` and `pre_trust` lines.

## What to look for

### 1. Claude Code settings overrides

Read `settings.json` and `settings.local.json`:

- `permissions.allow` containing unrestricted Bash (`Bash(*)`, bare `Bash`, `Bash(:*)`) → `FAIL`. Same primitive as a slash command with the same grant: full host RCE.
- `permissions.allow` containing wildcard interpreter grants (`Bash(python3 *)`, `Bash(node *)`, `Bash(sh *)`, `Bash(bash *)`, `Bash(ruby *)`, `Bash(deno *)`, `Bash(bun *)`, `Bash(perl *)`, `Bash(php *)`, `Bash(zsh *)`, `Bash(osascript *)`, `Bash(pwsh *)`, `Bash(powershell *)` and similar) → `FAIL`. Wildcard arg matches `-c "..."` / `-e "..."` and is equivalent to `Bash(*)`. Same rule for `Bash(eval *)`, `Bash(exec *)`, `Bash(source *)`, `Bash(. *)`.
- `permissions.allow` containing script-path-scoped interpreter grants (`Bash(python3 *.py)`, `Bash(node *.js)`) → `CAUTION`. Materially narrower but still allows arbitrary script paths.
- `permissions.allow` granting `Bash` plus `Edit` plus `Write` together with no scope restrictions → `FAIL` (full machine takeover surface).
- `permissions.allow` for tools that fetch from the network (`WebFetch`, MCP clients) without a host scope → `CAUTION`.
- `permissions.deny` notably empty when other settings are extremely permissive → `CAUTION`.
- `env` block injecting variables that match credential patterns → `FAIL`.
- `hooks` block referencing scripts in the repo (cross-check with the persistence section of claude-artifacts checklist).

### 2. CI/CD workflow abuse

For each workflow file:

- Trigger `pull_request_target` combined with a checkout of the PR head (`ref: ${{ github.event.pull_request.head.ref }}`) → `FAIL`. This is the classic "GitHub Actions injection" pattern that grants secrets to attacker-controlled code.
- Logging or echoing `${{ secrets.* }}` → `FAIL`.
- `env > somefile` or any pipeline step that writes the environment to a file or artifact → `FAIL`.
- Third-party action used at a mutable ref (`@main`, `@master`, `@v1` instead of a SHA) → `CAUTION`. Same author pinned to a SHA → `OK`.
- `runs-on: self-hosted` without labels constraining the runner → `CAUTION`.
- `permissions:` block missing or set to `write-all` → `CAUTION`.
- `actions/checkout` with `persist-credentials: true` and a privileged later step → `CAUTION`.
- Step that posts to a non-allowlisted domain (cross-reference with allowlist in `risk-model.md`) → `CAUTION`.

### 3. Dockerfile

- `FROM` an unpinned image tag (`:latest`, no tag) → `CAUTION`.
- `ADD https://...` (downloads and extracts at build time, with no integrity check) → `CAUTION`.
- `RUN` with a curl/wget piped into a shell → `FAIL`.
- `RUN` that decodes a base64 blob and pipes it to a shell → `FAIL`.
- `USER root` without a later `USER` switch → `CAUTION`.
- Secret material baked in via `ARG` or `ENV` → `FAIL`.
- `ENTRYPOINT` or `CMD` that fetches code at container start → `FAIL`.

### 4. docker-compose.yml

- `volumes` mounting host paths like `/`, `/var`, `/home`, `~/.ssh`, `~/.aws` → `FAIL`.
- `privileged: true` containers → `CAUTION`.
- `network_mode: host` for services that don't need it → `CAUTION`.
- `environment` listing credentials inline → `FAIL`.

### 5. Setup / bootstrap scripts

For any `setup.sh`, `install.sh`, `bootstrap.sh`, `Makefile install` target:

- Modifies global dotfiles → `FAIL` (cross-check with static checklist).
- Installs a launchd / systemd / cron entry → `FAIL`.
- Installs a global package manager hook → `FAIL`.
- Downloads and runs a remote script unconditionally → `FAIL`.
- Asks for `sudo` to perform actions other than installing a system package from the official repo → `CAUTION`.

### 6. Sandbox-evasion patterns

Grep all configs and scripts for:

- Conditionals on `CI=true`, `GITHUB_ACTIONS=true`, `RUNNER_OS`, `AGENT_TOOLSDIRECTORY` that change behaviour → `CAUTION` (suspicious but legitimate use cases exist; flag for human review).
- Conditionals on `DOCKER_CONTAINER`, `KUBERNETES_SERVICE_HOST`, virtualisation-detection (`/proc/1/cgroup` parsing) → `CAUTION`.
- Conditionals that disable telemetry or log spam only when a sandbox marker is present → `CAUTION`.

### 7. Environment files

- `.env` (not `.env.example`) committed to the repo → `CAUTION`. If the file contains values that match credential regexes → `FAIL`.
- `.env.example` is `OK`.
- `.env.local`, `.env.production`, `.env.development` containing real-looking values → `FAIL`.

### 8. Editor / tooling configuration

- `.vscode/settings.json` enabling `terminal.integrated.allowChords` plus auto-tasks that execute shell on open → `CAUTION`.
- `.vscode/tasks.json` with an auto-run task that fetches from the network → `FAIL`.
- `.devcontainer/devcontainer.json` referencing a `postCreateCommand` that runs an install script → `CAUTION` (cross-check the script content).

### 9. Config write is future execute

A write is an execute that happens later, in a process the user already trusts. Flag any code, hook, script or skill instruction that writes, copies over, appends to or edits a file another trusted process loads:

- `.claude/settings.json`, `.claude/settings.local.json`, `.claude/hooks/`, `.claude/commands/`, `.claude/agents/`, `.claude/skills/`, `.mcp.json` → `FAIL`. Another session (or another agent, Cursor CVE-2026-48124 style) trusts the file without re-prompting.
- `.vscode/tasks.json` (`runOn: folderOpen`), `.vscode/settings.json`, `.vscode/launch.json` → `FAIL`.
- `.git/hooks/*`, `.git/config`, `.githooks/`, `.husky/` → `FAIL`. Runs on the next commit, checkout, or `git status`.
- Virtualenv activate scripts (`bin/activate`, `Scripts/activate*`), `.envrc` → `FAIL`.
- `package.json` lifecycle scripts (`prepare`, `preinstall`, `install`, `postinstall`) changed through `npm pkg set scripts.*`, `npm set-script`, or a JSON write → `FAIL`. So is a sync step that overwrites the file a lifecycle script points at (the "drift-check" swap: a benign `prepare` target replaced by a later vendor sync). Claude Code `acceptEdits` guards `.claude/`, `.vscode/`, `.mcp.json` and `.git/hooks`, but not `package.json` scripts, so this is the path of least resistance.
- `.github/workflows/*`, `.gitlab-ci.yml`, `.circleci/config.yml` → `FAIL`. Runs with CI secrets on the next push.
- The same write expressed as an instruction in a skill, agent, command or CLAUDE.md ("add this hook to `.claude/settings.local.json`") → `FAIL`. A plugin-authoring skill that documents these files for the user to edit by hand is `CAUTION`.

### 10. Git config that executes (GitSpawn)

Git runs these keys on ordinary read commands, including the agent's own `git status` and `git diff`. In a shipped `.git/config` (tarball, zip, vendored checkout), a `*.gitconfig` the repo includes, or a `git config` / `git -c` / `GIT_*` env set by the plugin:

- `core.fsmonitor` set to a command (not `true`/`false`) → `FAIL`.
- `core.hooksPath`, `core.sshCommand`, `core.pager`, `core.editor`, `core.askPass`, `core.gitProxy` → `FAIL`.
- `diff.external`, `diff.<driver>.textconv`, `diff.<driver>.command` → `FAIL`.
- `filter.<driver>.clean` / `smudge` / `process`, `merge.<driver>.driver` → `FAIL` (`cat` is inert).
- `credential.helper`, `include.path`, `includeIf.*.path`, `alias.* = !...` → `FAIL` when shipped or written by the plugin.
- `GIT_SSH_COMMAND`, `GIT_EXTERNAL_DIFF`, `GIT_PAGER`, `GIT_ASKPASS`, `GIT_CONFIG_PARAMETERS` exported to a command → `FAIL` (`/dev/null`, `true`, `cat` are inert hardening).

### 11. Python import shadowing

- A `.pth` file shipped or written into `site-packages` → `FAIL`. Lines that start with `import` run at every interpreter start, for every Python process on the machine.
- `sitecustomize.py` / `usercustomize.py` shipped or written → `FAIL`.
- A file named like a stdlib module (`json.py`, `struct.py`, `os.py`, `subprocess.py`...) in a directory without `__init__.py` → `CAUTION`. Any script run from that directory imports it instead of the stdlib. Escalate to `FAIL` when the file does network, process or file-write work, or when a hook or skill runs a script from that directory. Package-internal modules (directory has `__init__.py`) are `OK`.

### 12. Sandbox and permission weakening

The Claude Code sandbox covers Bash, PowerShell and Monitor commands and their child processes. File tools, MCP servers and hooks run outside it, so a plugin that also weakens the sandbox removes the only boundary left. In any shipped `settings*.json`, hook, script or skill instruction:

- `sandbox.enabled: false` → `FAIL`.
- `sandbox.allowUnsandboxedCommands: true`, or `dangerouslyDisableSandbox` in a hook, script or skill → `FAIL`.
- `sandbox.excludedCommands` containing `docker`, `podman`, `nerdctl`, `kubectl` or `sudo` → `FAIL`. A reachable `docker.sock` is a full host escape.
- `allowUnixSockets` containing `docker.sock`, or a container run that mounts `docker.sock`, `$HOME`, `~`, `/Users/<name>` or `/root` → `FAIL`.
- `allowedDomains` containing `"*"` → `FAIL` (network sandbox off in all but name).
- `permissions.defaultMode: bypassPermissions`, `--permission-mode bypassPermissions`, `--dangerously-skip-permissions`, `skipDangerousModePermissionPrompt` → `FAIL` in shipped settings, hooks and scripts; `CAUTION` in documentation that tells the user when to use it.
- `--privileged` containers → `CAUTION`.

### 13. Runs before trust

- `SessionStart` or `Setup` hooks (plugin `hooks/hooks.json` or shipped settings) → apply the persistence rule in `claude-artifacts-checklist.md` #3. They run before the user has typed anything.
- A project `.mcp.json` with local `command` servers → `CAUTION`: once approved they start with every session, outside the sandbox. Name each server.
- `enableAllProjectMcpServers: true` or a non-empty `enabledMcpjsonServers` in shipped settings → `FAIL`. It removes the per-server approval prompt, so the servers start before trust.

## Output format

```markdown
### FAIL
- `<path>:<line>` — <description>
  > <quoted excerpt>

### CAUTION
- `<path>:<line>` — <description>
  > <quoted excerpt>

### OK
- No Claude Code permission overrides that grant wildcard Bash or wildcard interpreter access
- No CI/CD pull_request_target abuse
- No secrets dumped in workflows
- All third-party actions pinned to SHAs
- Dockerfile uses pinned base images and avoids curl|bash
- docker-compose does not mount sensitive host paths
- No setup script modifies global dotfiles or installs persistence units
- No sandbox-evasion conditionals
- No real .env files committed
- Editor configs do not auto-run network fetches
- No writes to files another trusted process loads (agent settings, hooks, editor tasks, git hooks/config, venv activate, CI, package.json lifecycle scripts)
- No shipped or written git config that executes commands
- No .pth, sitecustomize, or stdlib-shadowing Python files
- No sandbox or permission-mode weakening
- No MCP auto-approval or pre-trust hooks in shipped settings
```
