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
  'sendgrid_key|SG\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
  'twilio_key|SK[0-9a-fA-F]{32}'
  'azure_storage_key|AccountKey=[A-Za-z0-9+/]{40,}={0,2}'
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

# Generic high-entropy secret assignment: catches provider-agnostic secrets that
# have no distinctive prefix (api_token = "<40 random chars>"). A bare regex would
# fire on placeholders, so we gate on Shannon entropy and reject common dummies.
python3 - "${REPO}" <<'PYEOF'
import math
import os
import re
import sys

repo = sys.argv[1]
EXCLUDE_DIRS = {".git", "node_modules", "vendor", "dist", "build", ".venv", "__pycache__"}
EXCLUDE_FILES = {
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
    "poetry.lock", "uv.lock", "Cargo.lock", "Gemfile.lock", "composer.lock",
}

ASSIGN = re.compile(
    r"""(?P<key>[A-Za-z0-9_.-]*(api|token|secret|passwd|password|auth|key|access|private)[A-Za-z0-9_.-]*)"""
    r"""\s*[:=]\s*['"](?P<val>[A-Za-z0-9+/_=-]{24,})['"]""",
    re.IGNORECASE,
)
# Authorization: Bearer <token>. Gated on the same entropy/placeholder checks as
# the generic assignment so documentation like "Bearer YOUR_API_TOKEN_HERE" does
# not fire; only a high-entropy value survives.
BEARER = re.compile(r"[Bb]earer\s+(?P<val>[A-Za-z0-9._-]{24,})")
# Reject obvious placeholders / non-secrets.
DUMMY = re.compile(
    r"^(x{6,}|\.{3,}|change[_-]?me|your[_-]|example|placeholder|dummy|test|sample|"
    r"none|null|undefined|redacted|todo|fixme|00+|123456|abcdef)", re.IGNORECASE)

def entropy(s):
    if not s:
        return 0.0
    c = {}
    for ch in s:
        c[ch] = c.get(ch, 0) + 1
    n = len(s)
    return -sum((k / n) * math.log2(k / n) for k in c.values())

def looks_secret(val):
    return not (DUMMY.match(val) or len(set(val)) < 12 or entropy(val) < 3.5)

for root, dirs, files in os.walk(repo):
    dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
    for fn in files:
        if fn in EXCLUDE_FILES:
            continue
        path = os.path.join(root, fn)
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                for lineno, line in enumerate(f, start=1):
                    m = ASSIGN.search(line)
                    if m and looks_secret(m.group("val")):
                        val = m.group("val")
                        redacted = f"{m.group('key')}={val[:8]}<REDACTED:{len(val)-8}chars>"
                        print(f"{path}:{lineno}:generic_high_entropy_assignment:{redacted}")
                        continue
                    b = BEARER.search(line)
                    if b and looks_secret(b.group("val")):
                        val = b.group("val")
                        redacted = f"bearer {val[:8]}<REDACTED:{len(val)-8}chars>"
                        print(f"{path}:{lineno}:generic_bearer:{redacted}")
        except (OSError, UnicodeDecodeError):
            continue
PYEOF
