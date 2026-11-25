# Network and Filesystem Patterns Checklist

Reference for the `auditor-network-fs` sub-agent. This agent focuses on what the project tries to reach — outwards (network) and inwards (filesystem) — independent of who declares it (manifests, configs, scripts, skills).

## Scope

Files to scan:

- All source files (any language).
- Shell scripts and Makefile targets.
- Skill bodies and agent prompts (for instructions that direct Claude to fetch URLs or read files outside the project).
- Configuration files referencing endpoints (CI/CD, Dockerfile, docker-compose, etc.).

The helper script `scripts/scan_network.sh` produces a starting list of URLs and domains; the agent then classifies each. The helper `scripts/scan_trust_surface.sh` pre-extracts sections 10 to 12; this agent owns its `cred_reach`, `lateral_movement`, `exfil_channel` and `llm_router` lines.

## What to look for

### 1. Outbound URL allowlist enforcement

Run the network scan helper. It surfaces destinations from four passes, not just `https?://` URLs: scheme URLs (`http(s)`, `ftp`, `ws(s)`), bare `IP[:port]` literals with no scheme, and hosts passed to DNS tools (`dig`/`nslookup`/`host`/`drill`). The output is a list of hosts grouped and counted. For each host:

- On the standard allowlist (see `risk-model.md`) → `OK`.
- A well-known infrastructure host that does not appear on the allowlist but is clearly legitimate (e.g., `cloudflare.com`, `microsoft.com`, `apple.com`) → `CAUTION` (worth a human glance).
- A user-content subdomain on an otherwise trusted host (`*.github.io`, `*.pages.dev`, `*.web.app`, `*.workers.dev`, `*.netlify.app`, `*.vercel.app`) → `CAUTION` even though the parent domain is trusted: anyone can host an exfiltration endpoint there.
- An obscure host: a long random subdomain, a numeric IP, a dynamic-DNS provider (`*.duckdns.org`, `*.no-ip.com`, `*.ngrok.io`, `*.serveo.net`) → `FAIL`.
- A bare `IP:port` destination with no scheme (a common way to dodge URL-only scanners) → `FAIL` unless it is loopback/`0.0.0.0` in a clearly local context. The helper validates octets (0-255), so version strings and malformed quads never reach this list.
- A host key prefixed `local:` is an RFC1918 / link-local address (`10.*`, `192.168.*`, `172.16-31.*`, `169.254.*`). It routes only inside a network and is not an exfiltration destination, so it is `CAUTION` context at most (usually `OK` in dev docs), never `FAIL`. Documentation ranges (TEST-NET `192.0.2.*`, `198.51.100.*`, `203.0.113.*`) are deliberately NOT treated as local, because malware uses them as stand-in C2 addresses; they stay in the main stream.
- A host that only ever appears as the argument to a DNS tool, especially with a constructed subdomain → treat as DNS-exfiltration (see #7) → `FAIL`.
- A URL shortener (`bit.ly`, `t.co`, `goo.gl`, `tinyurl.com`) → `FAIL` (destination cannot be vetted statically).

### 2. Network call libraries

For each call to common HTTP clients — Python (`requests`, `urllib`, `httpx`, `http.client`, `aiohttp`), Node (`axios`, `node-fetch`, `got`, the global `fetch`), shell (`curl`, `wget`), PowerShell (`Invoke-WebRequest`):

- The URL is hardcoded → severity follows the host classification above.
- The URL is constructed from input (template strings over arguments, f-strings over variables) → `CAUTION` minimum.
- The call result is fed into a shell or a code interpreter (any process-spawn helper, runtime evaluation) → `FAIL`.
- TLS verification disabled (`verify=False`, `rejectUnauthorized: false`, `--insecure`) → `CAUTION`.
- Custom CA bundle bundled in the repo → `CAUTION` (provenance check needed).

### 3. Filesystem scope

Grep all source files and skill bodies for paths matching:

- Absolute paths outside the project that are not OS standard locations (`/usr/local/`, `/etc/profile.d/`, `/opt/`) → `CAUTION`.
- `~/.ssh/`, `~/.aws/`, `~/.azure/`, `~/.config/gcloud/`, `~/.kube/`, `~/.netrc`, `~/.pgpass` → `FAIL`.
- `~/.config/gh/`, `~/.gitconfig` → `CAUTION` (read) or `FAIL` (write).
- `~/.claude/` paths other than `~/.claude/plugin-auditor-reports/` → `FAIL`.
- Browser-state paths (`~/Library/Application Support/Google/Chrome/`, `~/.mozilla/`, `~/.config/google-chrome/`) → `FAIL` (cookie/credential theft surface).

### 4. Path traversal

Grep for:

- Hardcoded `../../../`, `../../`, `../` in arguments to file-read or file-write functions.
- Path joins where the second component comes from input without sanitisation.
- Glob patterns reaching outside the project (`/**/*` rooted at `/`, `~/**/*`).

Hardcoded traversal outside the project root is `FAIL`. Input-based traversal (without sanitisation) is `CAUTION` to `FAIL` depending on whether the input is attacker-controlled.

### 5. Data exfiltration chains

A finding is escalated when read + send patterns coexist in the same script or module:

- Read of a sensitive file (any path from #3) → write/transmit of that content to network → `FAIL` (active exfiltration).
- Read of process environment (`process.env`, `os.environ` and equivalents) → outbound HTTP request that includes those values → `FAIL`.
- Read of git history or `.git/config` → outbound transmission → `FAIL`.

### 6. Long-running and persistent processes

- `nohup`, `setsid`, `disown` invocations → `CAUTION`.
- Trailing `&` outside a clearly developer-only context (e.g., dev server) → `CAUTION`.
- `screen -dmS`, `tmux new-session -d` → `CAUTION`.
- Spawning a process that listens on a network port without documentation → `FAIL`.

### 7. DNS-based exfiltration

- DNS queries constructed from data (e.g., `dig <data>.attacker.example`) → `FAIL`.
- TXT record lookups against non-standard hosts → `CAUTION`.

### 8. Web sockets / persistent connections

- Outgoing WebSocket to a non-allowlisted host → `CAUTION`.
- Long-poll or SSE connection to a non-allowlisted host → `CAUTION`.
- Reverse-tunnel tools (`ssh -R`, `ngrok`, `frp`, `chisel`) → `FAIL`.

### 9. Telemetry

- Telemetry that is on by default (no opt-in) and sends free-form text or environment data → `CAUTION`.
- Telemetry endpoint not on the allowlist → `CAUTION`.
- Telemetry that includes anything matching the secret regex catalogue → `FAIL`.

### 10. Credential reach

Section 3 covers credential files by path. Also flag the other ways a plugin reaches credentials:

- macOS keychain (`security find-generic-password`, `find-internet-password`, `dump-keychain`), `secret-tool lookup` → `FAIL`.
- Token minting from a logged-in CLI: `gh auth token`, `aws configure export-credentials`, `gcloud auth print-access-token`, `az account get-access-token` → `FAIL` in a hook or MCP server, `CAUTION` in a skill the user invokes.
- `~/.config/gh/hosts.yml`, `~/.docker/config.json`, `~/.git-credentials` → `FAIL`.
- Browser profiles (`Login Data`, `Cookies`, `key4.db`, any `Application Support/<browser>` path) → `FAIL`.
- Reads of `.env` → `CAUTION`; `FAIL` when the values reach a network call or a log.
- Hooks and MCP servers inherit the user's environment. One that reads or forwards `GITHUB_TOKEN`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `ANTHROPIC_API_KEY`, `NPM_TOKEN` and the like, or passes `os.environ` / `process.env` wholesale to a child → `CAUTION`; `FAIL` when combined with an outbound call.
- An MCP server that holds a broad token (admin, org-wide, write scope) where a read-only or project-scoped one would do → `CAUTION`. In the recommendation, name the narrower scope and suggest short-lived credentials: AWS STS `GetScopedCredentials` or `AssumeRole` with a session policy and short duration, fine-grained GitHub tokens, read-only tracker tokens.

### 11. Lateral movement

The plugin reaching past this machine. Strictest in hooks and MCP servers, which run without the user's per-call review and outside the sandbox:

- `ssh user@host`, `scp`, `sftp`, `rsync host:` → `FAIL` in a hook or MCP server, `CAUTION` in a skill.
- PowerShell remoting: `Invoke-Command`, `Enter-PSSession`, `New-PSSession` → same rule.
- Cloud remote exec: `aws ssm send-command` / `start-session`, `gcloud compute ssh`, `az vm run-command`, `kubectl exec` / `cp`, `docker -H` → same rule.
- Driving a browser with the user's logged-in sessions (Claude in Chrome tools, `--remote-debugging-port`, a persistent `user-data-dir`) → `CAUTION`; `FAIL` when the instructions target credentials or admin consoles, or pair it with an exfil channel.

### 12. Exfil channels beyond plain HTTP

- `git push` or `git remote add` to a hardcoded URL that is not the project's own upstream → `FAIL`.
- Object storage uploads: `aws s3 cp/sync`, `s3api put-object`, `gsutil cp`, `gcloud storage cp`, `az storage blob upload`, `rclone copy` → `FAIL` when the source is repo, home or credential data; `CAUTION` otherwise.
- GitHub as a dead drop: `gh gist create`, `gh issue create/comment`, `api.github.com/gists` → `CAUTION`; `FAIL` when the body carries file contents, env or history.
- Paste and webhook sinks (`webhook.site`, `pastebin.com`, `transfer.sh`, Slack or Discord webhooks, `*.oast.*`) → `FAIL`.
- Third-party model routers: `ANTHROPIC_BASE_URL`, `OPENAI_BASE_URL`, `OPENAI_API_BASE` (and Bedrock/Vertex base-URL variants) pointing at a host other than `api.anthropic.com` / `api.openai.com` → `FAIL` in shipped settings `env`, hooks, MCP config or scripts; `CAUTION` in docs or tests. Every prompt, every file the model reads, and every credential it sees goes through that host (a 2026 UCSB study found 17 of 428 third-party routers stealing AWS credentials and 9 injecting code). Loopback is the user's own proxy and is not reported.

DNS exfil is section 7; reverse tunnels are section 8.

## Output format

```markdown
### FAIL
- `<path>:<line>` — <description>
  > <quoted excerpt>

### CAUTION
- `<path>:<line>` — <description>
  > <quoted excerpt>

### OK
- All outbound URLs are on the standard allowlist
- No reads of ~/.ssh, ~/.aws, ~/.azure, ~/.kube, ~/.netrc, browser state
- No path traversal patterns
- No read+send exfiltration chains
- No persistent processes spawned silently
- No DNS-based exfiltration patterns
- No reverse-tunnel tools invoked
- Telemetry (if present) is opt-in and points at allowlisted hosts
- No keychain, token-minting, browser-profile or inherited-token credential reach
- No lateral movement (ssh/scp, PowerShell remoting, cloud remote exec, logged-in browser driving)
- No git-push, object-storage, gist/issue or webhook exfil channels
- No model base-URL override to a third-party router
```
