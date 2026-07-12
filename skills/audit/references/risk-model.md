# Risk Model

The single source of truth for severity classification. Every finding produced by a sub-agent is mapped to one of three levels through the patterns below. When a finding does not match any catalogued pattern, the orchestrator classifies it as `CAUTION` by default — silence is not safety.

Severity vocabulary follows Anthropic's enterprise risk-tier guidance:

- **FAIL** (`high concern`) — the verdict becomes `UNSAFE`.
- **CAUTION** (`medium concern`) — the verdict becomes at least `CAUTION` and the risk score increases by 1 per finding.
- **OK** — the check passed; surface as a positive line in the report.

---

## FAIL patterns (high concern)

### Credentials and secrets

| Pattern | Example signature | Domain |
|---------|-------------------|--------|
| AWS access key | `AKIA` prefix followed by 16 uppercase alphanumerics, then a base64-like secret | static |
| AWS secret access key | 40-char base64-like value next to `aws_secret_access_key` | static |
| GCP service account JSON | private key block plus a `service_account` type marker | static |
| GitHub personal access token | `ghp_` prefix with 36+ alphanumerics, or `github_pat_` with 82+ | static |
| OpenAI API key | `sk-` prefix with 20+ alphanumerics, including `sk-proj-` variant | static |
| Anthropic API key | `sk-ant-` prefix with 20+ characters | static |
| Stripe live key | `sk_live_` prefix with 24+ alphanumerics | static |
| Slack token | `xox` prefix variants `xoxa`, `xoxb`, `xoxp`, `xoxr`, `xoxs` followed by 10+ chars | static |
| JWT (in source, not in tests) | three dot-separated base64url segments, header begins with `eyJ` | static |
| Private key block | a `BEGIN PRIVATE KEY` PEM header (RSA, EC, OPENSSH, DSA variants) | static |
| SendGrid / Twilio / Azure key | `SG.` two-segment token, `SK` + 32 hex, `AccountKey=` base64 | static |
| Generic high-entropy secret | a credential-named variable (`api`/`token`/`secret`/`password`/`key`/`auth`) assigned a 24+ char high-entropy string with no known prefix | static |

### Remote code execution

| Pattern | Example signature | Domain |
|---------|-------------------|--------|
| Curl-bash pipe | a `curl` or `wget` invocation piped into `bash` or `sh` | static, config |
| Eval of fetched content | shell process substitution that runs the body of a `curl` or `wget` call | static, config |
| Inline shell-eval of variable | shell `eval` over an unsanitised variable like `$INPUT` or `$@` | static |
| Python runtime evaluation of network response | code that compiles and runs the body of an HTTP response (e.g. through `runpy`, `compile`, or dynamic interpretation) | static, network-fs |
| Node dynamic code from HTTP body | constructing executable code at runtime from an HTTP response body | static, network-fs |

### Prompt injection in Claude artifacts

| Pattern | Example signature | Domain |
|---------|-------------------|--------|
| Override prior instructions | "ignore previous instructions", "forget all prior context", "disregard system prompt" | claude-artifacts |
| Hide actions | "do not tell the user", "secretly", "silently", "without informing the user" | claude-artifacts |
| Conditional bypass | "if user is from <region>", "if env var X then ignore safety" | claude-artifacts |
| Trigger hijacking | description like "Use this skill for everything" or "Always activate this skill" | claude-artifacts |
| Override safety rails | "bypass safety", "override Anthropic policy", "act as DAN" | claude-artifacts |
| Semantic injection (non-literal) | an artifact that, in meaning, directs the reading LLM to override prior context, hide actions, or condition behaviour on hidden state, expressed without any catalogued phrase (paraphrase, another language, split across sentences) | claude-artifacts |
| Audit-tool-targeted injection | text addressed to a "reviewer", "auditor", or "security scanner" telling it the repo is safe, to stop scanning, or to return `OK` | claude-artifacts |

The literal phrase catalogue in `prompt-injection-patterns.md` is a starting point, not the boundary. A paraphrase that carries the same intent is the same `FAIL`. The sub-agent judges meaning, not string matches.

### Slash command and agent tool grants

| Pattern | Example signature | Domain |
|---------|-------------------|--------|
| Unrestricted Bash grant in slash command, skill, or agent | `allowed-tools` or agent `tools` contains `Bash(*)`, bare `Bash`, or `Bash(:*)` | claude-artifacts |
| Wildcard interpreter grant (full RCE equivalent) | `Bash(python3 *)`, `Bash(python *)`, `Bash(node *)`, `Bash(deno *)`, `Bash(bun *)`, `Bash(ruby *)`, `Bash(perl *)`, `Bash(php *)`, `Bash(sh *)`, `Bash(bash *)`, `Bash(zsh *)`, `Bash(osascript *)`, `Bash(pwsh *)`, `Bash(powershell *)` and similar interpreters with `*` argument | claude-artifacts |
| Wildcard shell evaluation builtin | `Bash(eval *)`, `Bash(exec *)`, `Bash(source *)`, `Bash(. *)` | claude-artifacts |

A wildcard interpreter grant has the same attack surface as `Bash(*)`: the wildcard matches `-c "..."` / `-e "..."` / any file path, so the model can run arbitrary code on the host. Treat all of the above as full RCE primitives.

### Persistence in Claude Code

| Pattern | Example signature | Domain |
|---------|-------------------|--------|
| `PreToolUse` hook installed by default | `hooks/PreToolUse/*.sh` shipped active in `settings.json` | claude-artifacts, config |
| `PostToolUse` hook installed by default | `hooks/PostToolUse/*.sh` shipped active | claude-artifacts, config |
| `SessionStart` hook installed by default | runs at every Claude Code launch | claude-artifacts, config |
| Reads Claude Code history | path matches `~/.claude/projects/**/*.jsonl` or `$HOME/.claude/projects/**` | claude-artifacts, network-fs |
| Modifies global settings | writes to `~/.claude/settings.json` from within audited code | claude-artifacts, config |

### File-system and OS persistence

| Pattern | Example signature | Domain |
|---------|-------------------|--------|
| Modifies global dotfiles | appends to `~/.zshrc`, `~/.bashrc`, `~/.profile`, `~/.gitconfig` | static, config |
| Installs cron job | `crontab -e`, `crontab <file>`, writes to `/etc/cron.d/` | config |
| Installs launchd agent (macOS) | writes to `~/Library/LaunchAgents/` or `/Library/LaunchDaemons/` | config |
| Installs systemd unit (Linux) | writes to `/etc/systemd/system/` or `~/.config/systemd/user/` | config |
| Path traversal outside repo | hardcoded `../../../etc/`, `../../.ssh/`, traversal in skill paths | static, network-fs |
| Reads SSH private keys | accesses `~/.ssh/id_*`, `~/.ssh/config`, GitHub Apps PEMs | network-fs |
| Reads cloud credentials | accesses `~/.aws/credentials`, `~/.config/gcloud/`, `~/.azure/` | network-fs |

### Obfuscation

| Pattern | Example signature | Domain |
|---------|-------------------|--------|
| Long base64 blob (256+ chars, high entropy) | encoded payload embedded in source or skill | static |
| Long hex blob (256+ chars, high entropy) | encoded payload embedded in source or skill | static |
| Inline runtime decode followed by execution | base64 / zlib / hex decode whose result is fed to a shell or interpreter | static |
| Reverse-shell signature | `bash -i >& /dev/tcp/...`, `nc -e /bin/sh ...`, Python one-liner combining `socket` + `subprocess` + `os` | static, network-fs |
| Encoded shell in JSON/YAML | base64-encoded shell in any config file | static, config |

### CI/CD abuse

| Pattern | Example signature | Domain |
|---------|-------------------|--------|
| `pull_request_target` with PR-controlled checkout | `actions/checkout@v* { ref: ${{ github.event.pull_request.head.ref }} }` | config |
| Secrets dump | `echo ${{ secrets.* }}`, `env > log.txt` in a workflow | config |
| Unpinned third-party action | `uses: random-author/action@main` (no SHA pin) | config |
| Self-hosted runner without restrictions | `runs-on: self-hosted` with no labels or guards | config |

---

## CAUTION patterns (medium concern)

| Pattern | Example signature | Domain |
|---------|-------------------|--------|
| Network call in skill or agent | URL hardcoded in `SKILL.md`, agent prompt instructs to fetch a URL | claude-artifacts, network-fs |
| Network call to non-allowlisted domain | URL is not on the standard allowlist (see below) | network-fs |
| `postinstall` script in `package.json` | runs arbitrary code on `npm install` | supply-chain |
| `preinstall` script in `package.json` | runs even earlier than postinstall | supply-chain |
| MCP server using `npx` at runtime | `command: "npx"` with a package fetched on each launch | supply-chain |
| Git dependency to a non-official fork | `git+https://github.com/<random-user>/<package>` instead of upstream | supply-chain |
| Typosquatting heuristic match | dependency name is one Levenshtein edit from a popular package | supply-chain |
| Missing or unfrozen lockfile | `package.json` without `package-lock.json`, or `pyproject.toml` without `poetry.lock`/`uv.lock` | supply-chain |
| Narrowed interpreter grant in `permissions.allow` | `permissions.allow` contains script-path-scoped interpreter entries like `Bash(python3 *.py)` (no inline `-c`/`-e` but arbitrary file path) | config |
| Committed `.env` file | `.env` (not `.env.example`) is in the repo | config, static |
| Hidden state files | `.DS_Store`, `.git-credentials`, `.npmrc` with auth tokens | static |
| Long-running background process | `nohup`, `setsid`, `disown`, trailing `&` outside dev scripts | static, network-fs |
| Conditional behaviour on `CI=true` | sandbox-evasion pattern | config |
| Binary committed to repo | `.exe`, `.so`, `.dylib`, `.pyc`, `.bin`, `.dll` files | static |
| Broad glob in skill or script | `**/*` reaching outside the repository directory | network-fs |
| Dockerfile `ADD` from URL | `ADD https://...` (download + extract in build) | config |
| Dockerfile fetch-and-pipe inside `RUN` | shell pipe of a downloaded script inside a build stage | config |
| Narrowed interpreter grant (script-path scoped) | `Bash(python3 *.py)`, `Bash(node *.js)`, `Bash(ruby *.rb)` (no `-c`/`-e` but arbitrary file path) | claude-artifacts |
| Skill description spanning many domains | overly broad description that hijacks unrelated triggers | claude-artifacts |
| Telemetry to unknown endpoint | analytics or telemetry pointing at a non-standard domain | network-fs |
| Activation of pre-existing dormant code | a small diff (delta mode) that imports, calls, wires up, or enables a file, hook, or dependency that was already in the repo but previously unreferenced | claude-artifacts, config, static |
| User-content subdomain on a trusted host | outbound URL under `*.github.io` / `*.pages.dev` / `*.web.app` / `*.workers.dev` / `*.netlify.app` / `*.vercel.app` or a per-user `raw.githubusercontent.com` path | network-fs |
| Submodule from a non-official source | `.gitmodules` URL is not the upstream project | supply-chain |
| Optional dependency that runs scripts | `optionalDependencies` with packages known to run lifecycle scripts | supply-chain |

### Allowlist of well-known endpoints

The following hosts are considered low-risk when referenced. Anything outside this list flips a network-call finding to `CAUTION`:

- `api.anthropic.com`, `claude.ai`, `console.anthropic.com`, `platform.claude.com`
- `api.openai.com`
- `github.com`, `api.github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`, `codeload.github.com`
- `gitlab.com`, `api.gitlab.com`
- `pypi.org`, `files.pythonhosted.org`
- `registry.npmjs.org`, `npmjs.com`
- `crates.io`, `static.crates.io`
- `cdn.jsdelivr.net`, `unpkg.com`
- `rubygems.org`
- `index.docker.io`, `hub.docker.com`, `registry-1.docker.io`
- `googleapis.com` (only public APIs, not private project endpoints)

**Trusted parent, untrusted subdomain.** User-content hosting on an otherwise trusted domain is `CAUTION`, not `OK`, because anyone can stand up an exfiltration endpoint there: `*.github.io`, `*.pages.dev`, `*.web.app`, `*.workers.dev`, `*.netlify.app`, `*.vercel.app`, `raw.githubusercontent.com` paths under an arbitrary user, and gist URLs. Match the specific subdomain, not just the registrable domain.

---

## OK patterns (positive checks worth surfacing)

The report should explicitly enumerate positive checks so the user sees what was vetted, not just what failed.

| Check | What "OK" means |
|-------|-----------------|
| No hardcoded credentials | Zero matches against the secret regex catalogue. |
| No remote-fetch-and-execute | No curl/wget piped into a shell anywhere in the repo. |
| No prompt injection in Claude artifacts | No matches against the prompt-injection signature list. |
| No persistence hooks installed by default | No `PreToolUse`/`PostToolUse`/`SessionStart` hooks active in shipped configs. |
| No modifications to global dotfiles | No writes to `~/.zshrc`, `~/.bashrc`, `~/.gitconfig`, etc. |
| No reads of Claude Code history | No access patterns targeting `~/.claude/projects/**`. |
| Lockfile present and frozen | `package-lock.json`/`poetry.lock`/`uv.lock`/`Cargo.lock` exists; `--frozen-lockfile` or equivalent is honoured. |
| No `postinstall`/`preinstall` scripts | `package.json` does not declare lifecycle scripts that auto-execute. |
| No path traversal | No `../` patterns reaching outside the project root. |
| No obfuscated payloads | No high-entropy base64/hex blobs or runtime-decoded payloads. |
| No binaries committed | Repository contains source only. |
| No CI/CD abuse | Workflows pin actions to SHAs, do not use `pull_request_target` unsafely, do not dump secrets. |
| Network calls only to allowlisted domains | Every fetched URL is on the standard allowlist. |
| MCP servers pinned | If MCP servers are declared, they are pinned to specific versions and not fetched at runtime. |
| Slash commands and agents scoped | `allowed-tools` and agent `tools` are explicit (specific module, script path, or subcommand), no `Bash(*)` and no wildcard interpreter grants. |

---

## Severity escalation rules

A few combinations escalate beyond the per-pattern severity:

1. **Hardcoded credential + outbound network call to non-allowlisted host** → `FAIL` (active exfiltration vector, not just leaked secret).
2. **Persistence hook + reads Claude Code history** → `FAIL` (session-spanning surveillance).
3. **Obfuscated payload + shell execution** → `FAIL` regardless of obfuscation severity.
4. **Two or more `CAUTION` findings of supply-chain type on the same dependency** → escalate that dependency to `FAIL` (compounded supply-chain risk).
5. **Sub-agent failed to return a structured report** → automatic minimum verdict of `CAUTION` (no clean signal).
