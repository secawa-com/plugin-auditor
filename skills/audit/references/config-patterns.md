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

## What to look for

### 1. Claude Code settings overrides

Read `settings.json` and `settings.local.json`:

- `permissions.allow` containing wildcards over Bash (e.g., entries that grant unrestricted shell) → `CAUTION`.
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

## Output format

```markdown
### FAIL
- `<path>:<line>` — <description>
  > <quoted excerpt>

### CAUTION
- `<path>:<line>` — <description>
  > <quoted excerpt>

### OK
- No Claude Code permission overrides that grant wildcard Bash
- No CI/CD pull_request_target abuse
- No secrets dumped in workflows
- All third-party actions pinned to SHAs
- Dockerfile uses pinned base images and avoids curl|bash
- docker-compose does not mount sensitive host paths
- No setup script modifies global dotfiles or installs persistence units
- No sandbox-evasion conditionals
- No real .env files committed
- Editor configs do not auto-run network fetches
```
