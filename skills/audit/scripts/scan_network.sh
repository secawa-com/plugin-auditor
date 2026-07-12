#!/usr/bin/env bash
# scan_network.sh <repo_path>
#
# Extracts network destinations from the repository and groups them by host.
# Covers http(s), ftp, ws(s) URLs, bare IP:port literals, and hosts passed to
# DNS tools (dig/nslookup/host/drill) so DNS-based exfiltration is surfaced too.
#
# Output: <host> <count> <comma-separated paths>
#
# The auditor-network-fs sub-agent then classifies each host against the
# allowlist in references/risk-model.md.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: scan_network.sh <repo_path>" >&2
  exit 64
fi

REPO="$1"
if [[ ! -d "${REPO}" ]]; then
  echo "scan_network.sh: not a directory: ${REPO}" >&2
  exit 65
fi

EXCLUDES=(
  --exclude-dir=.git
  --exclude-dir=node_modules
  --exclude-dir=vendor
  --exclude-dir=dist
  --exclude-dir=build
  --exclude-dir=.venv
  --exclude-dir=__pycache__
  --exclude=package-lock.json
  --exclude=yarn.lock
  --exclude=pnpm-lock.yaml
  --exclude=poetry.lock
  --exclude=uv.lock
  --exclude=Cargo.lock
)

TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

emit() {
  # emit <host> <path:lineno> <raw>
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "${TMP}"
}

# --- 1) Scheme URLs: http(s), ftp, ws(s). ---
URL_REGEX='(https?|ftp|wss?)://[A-Za-z0-9._~:/?#@!$&'"'"'()*+,;=%-]+'
while IFS= read -r hit; do
  path="${hit%%:*}"; rest="${hit#*:}"; lineno="${rest%%:*}"; url="${rest#*:}"
  h="${url}"
  h="${h#*://}"
  h="${h%%[/:?#]*}"
  h="$(printf '%s' "${h}" | tr -cd 'a-zA-Z0-9._-')"
  [[ -n "${h}" ]] && emit "${h}" "${path}:${lineno}" "${url}"
done < <(grep -RnoE -I "${EXCLUDES[@]}" "${URL_REGEX}" "${REPO}" 2>/dev/null || true)

# --- 2) Bare IPv4[:port] literals not preceded by a word char or dot. ---
# Captures 192.0.2.1:31337 style destinations that have no scheme.
IP_REGEX='(^|[^0-9A-Za-z._-])([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]{1,5})?'

# valid_octets <ip> — true only when every octet is 0-255. Filters the many
# dotted-quad lookalikes (version strings, 999.999.999.999) the regex admits.
valid_octets() {
  local IFS=.
  local o1 o2 o3 o4
  read -r o1 o2 o3 o4 <<<"$1"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    [[ "$o" =~ ^[0-9]+$ ]] || return 1
    (( o >= 0 && o <= 255 )) || return 1
  done
  return 0
}

while IFS= read -r hit; do
  path="${hit%%:*}"; rest="${hit#*:}"; lineno="${rest%%:*}"; frag="${rest#*:}"
  ip="$(printf '%s' "${frag}" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]{1,5})?' | head -n1 || true)"
  host="${ip%%:*}"
  # Skip loopback / unspecified / broadcast and anything that is not a real IPv4.
  case "${host}" in
    ""|0.0.0.0|127.0.0.1|255.255.255.255) continue ;;
  esac
  valid_octets "${host}" || continue
  # RFC1918 private space and link-local are routable only inside a network, so
  # they are not exfiltration destinations; surface them as a distinct 'local'
  # host key that the sub-agent treats as CAUTION context, not a FAIL. Documentation
  # ranges (TEST-NET) stay in the main stream because malware uses them as stand-ins.
  case "${host}" in
    10.*|192.168.*|169.254.*) emit "local:${ip}" "${path}:${lineno}" "${ip}"; continue ;;
    172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) emit "local:${ip}" "${path}:${lineno}" "${ip}"; continue ;;
  esac
  emit "${ip}" "${path}:${lineno}" "${ip}"
done < <(grep -RnoE -I "${EXCLUDES[@]}" "${IP_REGEX}" "${REPO}" 2>/dev/null || true)

# --- 3) DNS-tool targets: dig/nslookup/host/drill <name>. ---
# The argument after the tool is the exfil channel candidate; surface its host.
DNS_REGEX='(^|[^A-Za-z0-9_])(dig|nslookup|drill|host)[[:space:]].*[A-Za-z0-9._-]+\.[A-Za-z]{2,}'
while IFS= read -r hit; do
  path="${hit%%:*}"; rest="${hit#*:}"; lineno="${rest%%:*}"; frag="${rest#*:}"
  # last dotted token on the line is the queried name
  name="$(printf '%s' "${frag}" | grep -oE '[A-Za-z0-9._-]+\.[A-Za-z]{2,}' | tail -n1 || true)"
  [[ -n "${name}" ]] && emit "${name}" "${path}:${lineno}" "dns-query:${name}"
done < <(grep -RnoE -I "${EXCLUDES[@]}" "${DNS_REGEX}" "${REPO}" 2>/dev/null || true)

# --- Aggregate by host. ---
if [[ ! -s "${TMP}" ]]; then
  exit 0
fi

sort -u "${TMP}" \
  | awk -F'\t' '
    {
      counts[$1]++
      if (locations[$1] == "") {
        locations[$1] = $2
      } else if (length(locations[$1]) < 400) {
        locations[$1] = locations[$1] "," $2
      }
    }
    END {
      for (h in counts) {
        printf "%s\t%d\t%s\n", h, counts[h], locations[h]
      }
    }' \
  | sort -k2,2nr -k1,1 || true

exit 0
