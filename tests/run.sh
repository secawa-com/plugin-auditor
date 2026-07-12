#!/usr/bin/env bash
# run.sh — regression harness for plugin-auditor's mechanical scan helpers.
#
# Runs each scan_*.sh against the safe and malicious fixtures and checks their
# output against the contract in tests/expectations.md:
#   - safe-fixture: every helper must return zero findings.
#   - malicious-fixture: each planted category must be reported at least N times.
#
# Read-only: never installs anything, never executes fixture code. Exit 0 on
# success, 1 on any regression.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
SCRIPTS="${ROOT}/skills/audit/scripts"
SAFE="${HERE}/fixtures/safe-fixture"
MAL="${HERE}/fixtures/malicious-fixture"

PASS=0
FAIL=0

green() { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
red()   { printf '  FAIL %s\n' "$1"; FAIL=$((FAIL + 1)); }

# count_cat <output> <category-substring>
count_cat() { grep -c -- "$2" <<<"$1" 2>/dev/null || true; }

echo "== safe-fixture: expect zero findings from every helper =="
for s in scan_secrets scan_obfuscation scan_network scan_binaries; do
  out="$(bash "${SCRIPTS}/${s}.sh" "${SAFE}" 2>/dev/null || true)"
  n="$(grep -c . <<<"${out}" 2>/dev/null || true)"
  # grep -c on empty input returns 0 but with a trailing state; normalise.
  [[ -z "${out}" ]] && n=0
  if [[ "${n}" -eq 0 ]]; then
    green "${s}: 0 findings"
  else
    red "${s}: expected 0, got ${n}"
    printf '%s\n' "${out}" | sed 's/^/       /'
  fi
done

echo "== malicious-fixture: expect planted categories present =="

SEC="$(bash "${SCRIPTS}/scan_secrets.sh" "${MAL}" 2>/dev/null || true)"
OBF="$(bash "${SCRIPTS}/scan_obfuscation.sh" "${MAL}" 2>/dev/null || true)"
NET="$(bash "${SCRIPTS}/scan_network.sh" "${MAL}" 2>/dev/null || true)"

# assert <label> <actual> <min>
assert() {
  local label="$1" actual="$2" min="$3"
  if [[ "${actual}" -ge "${min}" ]]; then
    green "${label}: ${actual} >= ${min}"
  else
    red "${label}: ${actual} < ${min}"
  fi
}

# Secrets: prefix catalogue (any of the well-known categories) >= 2.
prefix_hits=0
for c in openai_key anthropic_key github_pat_classic aws_access_key stripe_live sendgrid_key; do
  prefix_hits=$((prefix_hits + $(count_cat "${SEC}" ":${c}:")))
done
assert "secrets prefix-catalogue" "${prefix_hits}" 2
assert "secrets generic_high_entropy_assignment" "$(count_cat "${SEC}" ":generic_high_entropy_assignment:")" 1

# Obfuscation.
blob_hits=$(( $(count_cat "${OBF}" ":base64_blob:") + $(count_cat "${OBF}" ":hex_blob:") + $(count_cat "${OBF}" ":base32_blob:") ))
assert "obfuscation encoded-blob" "${blob_hits}" 1
decode_hits=$(( $(count_cat "${OBF}" ":decode_exec:") + $(count_cat "${OBF}" ":decode_exec_multiline:") ))
assert "obfuscation decode->exec" "${decode_hits}" 1
assert "obfuscation reverse_shell" "$(count_cat "${OBF}" ":reverse_shell:")" 1

# Network. Host column is field 1; match on the host token.
assert "network duckdns host" "$(grep -c 'duckdns' <<<"${NET}" 2>/dev/null || true)" 1
assert "network bare IP:port" "$(grep -cE '^203\.0\.113\.7:8443' <<<"${NET}" 2>/dev/null || true)" 1
assert "network ws:// host" "$(grep -c 'c2.evasion-host.example' <<<"${NET}" 2>/dev/null || true)" 1
assert "network dns-query host" "$(grep -c 'attacker-dns.example' <<<"${NET}" 2>/dev/null || true)" 1

echo
echo "== summary =="
printf 'passed: %d   failed: %d\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]] || exit 1
