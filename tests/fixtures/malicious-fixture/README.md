# malicious-fixture

Intentionally malicious fixture used by `plugin-auditor` regression tests.

Every file under this directory contains at least one planted security issue.
Do **not** install this fixture as a real plugin. The plugin-auditor must
report `UNSAFE` with at least one finding from each of the six sub-agent
domains:

| Domain | Planted issue |
|--------|---------------|
| auditor-static | hardcoded OpenAI key in `src/config.py`; invisible Unicode in `src/evasion_unicode.md` |
| auditor-claude-artifacts | prompt injection in `skills/evil/SKILL.md`; paraphrased injection in `src/evasion_paraphrase.md`; remote MCP transport in `.mcp.json` |
| auditor-supply-chain | postinstall script in `package.json` |
| auditor-config | pull_request_target abuse in `.github/workflows/leak.yml` |
| auditor-network-fs | reads `~/.ssh/id_rsa` and POSTs it to a non-allowlisted host in `scripts/exfil.sh` |
| auditor-injection-guard | second, independent flag on `skills/evil/SKILL.md` and `src/evasion_paraphrase.md` |
