# Fixture expectations

Contract consumed by `tests/run.sh`. It pins what the **mechanical** scan helpers
(`scan_secrets.sh`, `scan_obfuscation.sh`, `scan_network.sh`, `scan_binaries.sh`)
must report on each fixture. These scripts are deterministic, so their output is a
regression baseline. LLM-driven classification (the sub-agents) is out of scope
here — it is exercised by running the full `/plugin-auditor:audit` skill manually.

## safe-fixture

Every mechanical scan must return **zero** findings. Any match is a false positive
and fails the suite. This guards against over-eager thresholds (e.g. the lowered
obfuscation entropy gate lighting up on ordinary prose or hashes).

## malicious-fixture

Minimum finding counts per helper. `run.sh` asserts `actual >= expected` so adding
new planted issues never breaks the suite; only a **regression** (a detector going
silent) does.

| Helper | Category | Min count | Planted in |
|--------|----------|-----------|------------|
| scan_secrets.sh | prefix-catalogue (openai/anthropic/github/etc.) | 2 | `src/config.py`, `.env` |
| scan_secrets.sh | generic_high_entropy_assignment | 1 | `src/evasion_secret.py` |
| scan_obfuscation.sh | base64_blob or hex_blob | 1 | `src/obfuscated.py` |
| scan_obfuscation.sh | decode_exec or decode_exec_multiline | 1 | `src/evasion_split.py` |
| scan_obfuscation.sh | reverse_shell | 1 | `scripts/exfil.sh` |
| scan_network.sh | duckdns host | 1 | `scripts/exfil.sh` |
| scan_network.sh | bare IP:port | 1 | `src/evasion_net.sh` |
| scan_network.sh | ws:// host | 1 | `src/evasion_net.sh` |
| scan_network.sh | dns-query host | 1 | `src/evasion_net.sh` |

## Known evasion gaps (documented, not asserted)

These are deliberately present in the malicious fixture and are **not** expected to
be caught by the mechanical scanner. They mark the boundary of static grep-based
detection and are the job of the LLM sub-agents (or future work):

- `src/evasion_paraphrase.md` — prompt injection expressed semantically, in another
  language, with no literal phrase from `prompt-injection-patterns.md`. Caught (if at
  all) by the semantic-intent pass in `auditor-claude-artifacts`, not by grep.
- `src/evasion_secret.py` line with `"AKIA" + "JKLMNOP" + ...` — a secret reassembled
  from string concatenation. Per-line scanning cannot see the reassembled value.
