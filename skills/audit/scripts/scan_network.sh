#!/usr/bin/env bash
# scan_network.sh <repo_path>
#
# Extracts every absolute URL from the repository and groups them by host.
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

URL_REGEX='https?://[A-Za-z0-9._~:/?#@!$&'"'"'()*+,;=%-]+'

# Collect URLs with file:line context.
TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

{ grep -RnoE -I "${EXCLUDES[@]}" "${URL_REGEX}" "${REPO}" 2>/dev/null || true; } \
  | awk -F: '
    {
      # Reconstruct URL: everything from $3 onwards (URL may contain colons).
      path=$1; lineno=$2; url=$3
      for (i=4; i<=NF; i++) url=url ":" $i
      # Extract host: strip scheme then take up to first / or :.
      h=url
      sub(/^https?:\/\//, "", h)
      sub(/[\/:?#].*$/, "", h)
      gsub(/[^a-zA-Z0-9._-]/, "", h)
      if (h != "") {
        print h "\t" path ":" lineno "\t" url
      }
    }' \
  | sort -u > "${TMP}"

# Aggregate by host.
awk -F'\t' '
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
  }' "${TMP}" \
  | sort -k2,2nr -k1,1 || true

# Always exit 0 — empty output (no URLs found) is a valid result.
exit 0
