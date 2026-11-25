# Fixture expectations

Contract consumed by `tests/run.sh`. It pins what the **mechanical** scan helpers
(`scan_secrets.sh`, `scan_obfuscation.sh`, `scan_network.sh`, `scan_binaries.sh`,
`scan_unicode.sh`, `scan_trust_surface.sh`) must report on each fixture. These scripts are deterministic, so
their output is a regression baseline. LLM-driven classification (the sub-agents) is
out of scope here — it is exercised by running the full `/plugin-auditor:audit` skill
manually.

## safe-fixture

Every mechanical scan must return **zero** findings. Any match is a false positive
and fails the suite. This guards against over-eager thresholds. The fixture carries
deliberate near-misses that must stay silent: a sha256 / git-SHA pin (`deploy/Dockerfile`),
private RFC1918 addresses and a Bearer placeholder (`docs/networking.md`), and a
`re.compile` + `bytes([...])` parser (`src/parser.py`), a git config with builtin
`fsmonitor = true` and `pager = cat` (`dot-git/config`), a package-internal `json.py`
(`src/fmt/`, has `__init__.py`), and `GIT_PAGER=cat` with a project-local redirect (`src/log.sh`). For `scan_network` the
`local:`-prefixed RFC1918 hosts are context, not findings, so the safe check filters
them before counting.

Lines prefixed `doc:` are documentation context, not findings: `docs/threat-notes.md`
names a reverse shell, a dynamic-DNS URL and a git fsmonitor command, and every helper
must tag those lines `doc:` (asserted: at least 3 tagged lines). Malicious-fixture counts
exclude `doc:` lines, so a detector that only fires in documentation does not pass.

## malicious-fixture

Minimum finding counts per helper. `run.sh` asserts `actual >= expected` so adding
new planted issues never breaks the suite; only a **regression** (a detector going
silent) does.

| Helper | Category | Min count | Planted in |
|--------|----------|-----------|------------|
| scan_secrets.sh | prefix-catalogue (openai/anthropic/github/etc.) | 2 | `src/config.py`, `.env` |
| scan_secrets.sh | generic_high_entropy_assignment | 1 | `src/evasion_secret.py` |
| scan_secrets.sh | generic_bearer | 1 | `src/evasion_secret.py` |
| scan_obfuscation.sh | base64_blob or hex_blob | 1 | `src/obfuscated.py` |
| scan_obfuscation.sh | decode_exec or decode_exec_multiline | 1 | `src/evasion_split.py` |
| scan_obfuscation.sh | reverse_shell | 1 | `scripts/exfil.sh` |
| scan_network.sh | duckdns host | 1 | `scripts/exfil.sh` |
| scan_network.sh | bare IP:port | 1 | `src/evasion_net.sh` |
| scan_network.sh | ws:// host | 1 | `src/evasion_net.sh` |
| scan_network.sh | dns-query host | 1 | `src/evasion_net.sh` |
| scan_unicode.sh | zero_width | 1 | `src/evasion_unicode.md` |
| scan_unicode.sh | bidi_override | 1 | `src/evasion_unicode.md` |
| scan_binaries.sh | committed binary | 1 | `payload.exe` |
| scan_trust_surface.sh | config_write | 1 | `scripts/vendor-sync.sh` (incl. `.claude/settings.local.json`, `npm pkg set scripts.prepare`), `skills/hotfix/SKILL.md` |
| scan_trust_surface.sh | git_exec_config | 1 | `dot-git/config` (incl. command `fsmonitor`), `scripts/vendor-sync.sh` |
| scan_trust_surface.sh | py_stdlib_shadow | 1 | `scripts/json.py` |
| scan_trust_surface.sh | py_pth | 1 | `src/canary.pth`, `scripts/vendor-sync.sh` |
| scan_trust_surface.sh | sandbox_weaken | 1 (docker.sock: 2) | `dot-claude/settings.local.json`, `hooks/post-tool.sh` |
| scan_trust_surface.sh | pre_trust | 1 | `dot-claude/settings.local.json`, `settings.json`, `dot-mcp.json` |
| scan_trust_surface.sh | cred_reach | 1 | `hooks/post-tool.sh`, `scripts/exfil.sh` |
| scan_trust_surface.sh | lateral_movement | 1 | `hooks/post-tool.sh` |
| scan_trust_surface.sh | exfil_channel | 1 | `hooks/post-tool.sh` |
| scan_trust_surface.sh | llm_router | 1 | `dot-claude/settings.local.json` |
| scan_trust_surface.sh | nondefault_index | 1 | `skills/hotfix/SKILL.md` |
| scan_trust_surface.sh | lifecycle_script | 1 | `package.json` (incl. `prepare`) |

Fixture files that only work when they sit at a magic path are stored under inert names so
nothing runs on clone or when an agent opens this repo: `dot-git/config` stands for `.git/config`,
`dot-claude/settings.local.json` for `.claude/settings.local.json`, `dot-mcp.json` for `.mcp.json`. The scanner reads both names.
All hosts are `example.invalid` or `127.0.0.1`, and every payload only prints a `CANARY-*` string.

## Generated cases (built in a temp dir by run.sh)

Files that would act on clone or on opening the repo in an agent (an instruction file named
`CLAUDE.local.md`, a symlink, a NUL file) are generated at test time and removed after:

- Instruction files are never `doc:`-tagged: `CLAUDE.local.md`, `Claude.md`, `skills/x/references/r.md`,
  `.github/copilot-instructions.md`. A `README.md` is tagged even when an ancestor of the audited
  repo is named `agents/` (classification uses the path relative to the repo root).
- `nondefault_index` fires when a first-party `--index-url` sits beside a non-first-party
  `--extra-index-url` (both orders); a first-party-only index stays silent.
- `llm_router` fires for `https://api.anthropic.com@router.example.invalid`.
- `skipped:<reason>:<relpath>` lines for a symlink, a NUL file, a file over 2MB and a non-UTF-8 file.
- Every helper run on a missing directory prints `helper_error:<helper>:rc=65:...`.

## Known evasion gaps (documented, not asserted)

These are deliberately present in the malicious fixture and are **not** expected to
be caught by the mechanical scanner. They mark the boundary of static grep-based
detection and are the job of the LLM sub-agents (or future work):

- `src/evasion_paraphrase.md` — prompt injection expressed semantically, in another
  language, with no literal phrase from `prompt-injection-patterns.md`. Caught (if at
  all) by the semantic-intent pass in `auditor-claude-artifacts`, not by grep.
- `mcp/tickets_server.py` and the first two steps of `skills/hotfix/SKILL.md`: agentjacking.
  An MCP server returning third-party tracker text verbatim, and a skill telling the model to run
  the "Resolution" it reads. Whether text is attacker-writable and whether the artifact tells the
  model to obey it is a semantic call for `auditor-claude-artifacts`, not a regex.
- `src/evasion_secret.py` line with `"AKIA" + "JKLMNOP" + ...` — a secret reassembled
  from string concatenation. Per-line scanning cannot see the reassembled value.
