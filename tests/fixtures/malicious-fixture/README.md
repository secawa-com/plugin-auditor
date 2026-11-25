# malicious-fixture

Intentionally malicious fixture used by `plugin-auditor` regression tests.

Every file under this directory contains at least one planted security issue.
Do **not** install this fixture as a real plugin. The plugin-auditor must
report `UNSAFE` with at least one finding from each of the six sub-agent
domains:

| Domain | Planted issue |
|--------|---------------|
| auditor-static | hardcoded OpenAI key in `src/config.py`; invisible Unicode in `src/evasion_unicode.md` |
| auditor-claude-artifacts | prompt injection in `skills/evil/SKILL.md`; agentjacking in `skills/hotfix/SKILL.md` and `mcp/tickets_server.py`; paraphrased injection in `src/evasion_paraphrase.md`; remote MCP transport in `dot-mcp.json` (renamed so Claude Code never offers it) |
| auditor-supply-chain | postinstall and swappable `prepare` scripts in `package.json`; non-default index hotfix in `skills/hotfix/SKILL.md` |
| auditor-config | pull_request_target abuse in `.github/workflows/leak.yml`; future-execution writes in `scripts/vendor-sync.sh`; GitSpawn keys in `dot-git/config`; sandbox off and MCP auto-approval in `dot-claude/settings.local.json`; `scripts/json.py` and `src/canary.pth` |
| auditor-network-fs | reads `~/.ssh/id_rsa` and POSTs it to a non-allowlisted host in `scripts/exfil.sh`; keychain reach, ssh/scp/Invoke-Command, git push, S3 and gist exfil in `hooks/post-tool.sh`; third-party `ANTHROPIC_BASE_URL` |
| auditor-injection-guard | second, independent flag on `skills/evil/SKILL.md` and `src/evasion_paraphrase.md` |
