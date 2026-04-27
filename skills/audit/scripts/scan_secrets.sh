#!/usr/bin/env bash
# scan_secrets.sh <repo_path>
#
# Greps a repository for hardcoded credential patterns and prints findings as
#   <path>:<line>:<category>:<redacted-excerpt>
# one per line on stdout.
#
# Read-only. Never modifies the repository.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: scan_secrets.sh <repo_path>" >&2
  exit 64
fi

REPO="$1"
if [[ ! -d "${REPO}" ]]; then
  echo "scan_secrets.sh: not a directory: ${REPO}" >&2
  exit 65
fi

# Common exclusions.
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
  --exclude=Gemfile.lock
  --exclude=composer.lock
)

# Pattern catalogue. Each pair: <category> | <ERE>.
PATTERNS=(
  'aws_access_key|AKIA[0-9A-Z]{16}'
  'github_pat_classic|ghp_[A-Za-z0-9]{36,}'
  'github_pat_fine_grained|github_pat_[A-Za-z0-9_]{82,}'
  'github_oauth|gho_[A-Za-z0-9]{36,}'
  'openai_key|sk-(proj-)?[A-Za-z0-9_-]{20,}'
  'anthropic_key|sk-ant-(api|admin)?[0-9]{2}-[A-Za-z0-9_-]{20,}'
  'stripe_live|sk_live_[A-Za-z0-9]{24,}'
  'slack_token|xox[abprs]-[0-9A-Za-z-]{10,}'
  'jwt_signed|eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'
  'pem_private_key|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
  'google_api_key|AIza[0-9A-Za-z_-]{35}'
  'gcp_oauth_refresh|1//0[A-Za-z0-9_-]{30,}'
)

for pair in "${PATTERNS[@]}"; do
  CATEGORY="${pair%%|*}"
  REGEX="${pair#*|}"
  # -E for ERE, -r recursive, -n line numbers, -I skip binary, -H always show filename.
  while IFS= read -r line; do
    # line format from grep: <path>:<lineno>:<match line>
    path="${line%%:*}"
    rest="${line#*:}"
    lineno="${rest%%:*}"
    excerpt="${rest#*:}"
    # Redact the matched secret value: keep up to the first 8 chars then mask.
    # We replace the regex match with a redaction marker.
    redacted="$(printf '%s' "${excerpt}" | awk -v re="${REGEX}" '
      {
        line=$0
        out=""
        while (match(line, re)) {
          before=substr(line,1,RSTART-1)
          matched=substr(line,RSTART,RLENGTH)
          # Keep the first 8 chars of the match, redact the rest.
          if (length(matched) > 8) {
            keep=substr(matched,1,8)
            redacted=keep "<REDACTED:" length(matched)-8 "chars>"
          } else {
            redacted="<REDACTED>"
          }
          out=out before redacted
          line=substr(line,RSTART+RLENGTH)
        }
        out=out line
        print out
      }
    ')"
    printf '%s:%s:%s:%s\n' "${path}" "${lineno}" "${CATEGORY}" "${redacted}"
  done < <(grep -REn -I "${EXCLUDES[@]}" -e "${REGEX}" "${REPO}" 2>/dev/null || true)
done
