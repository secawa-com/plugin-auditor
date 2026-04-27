#!/usr/bin/env bash
# clone_repo.sh <url>
#
# Safely shallow-clones a GitHub or GitLab URL to a temporary directory under
# /tmp/plugin-auditor/. URL is validated against an allowlist; no git config
# is touched; no credentials are used.
#
# Prints the absolute path to the cloned directory on stdout.
# Exits non-zero with an error on stderr if the URL is rejected.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: clone_repo.sh <url>" >&2
  exit 64
fi

INPUT="$1"

# Allow optional @ref pin: split on '@' AFTER the 'https://' part.
URL="${INPUT%@*}"
REF=""
if [[ "${INPUT}" == *"@"* && "${INPUT##*@}" != "${INPUT#*//}" ]]; then
  REF="${INPUT##*@}"
fi
# Re-derive URL safely: anything before the LAST '@' that is not part of the scheme.
# Simpler: split only if exactly one '@' after the scheme separator.
SCHEME_REST="${INPUT#https://}"
if [[ "${SCHEME_REST}" == *"@"* ]]; then
  URL="https://${SCHEME_REST%@*}"
  REF="${SCHEME_REST##*@}"
else
  URL="${INPUT}"
  REF=""
fi

# Allowlist: only github.com and gitlab.com over HTTPS.
case "${URL}" in
  https://github.com/*|https://gitlab.com/*) ;;
  *)
    echo "clone_repo.sh: refusing URL not on allowlist (only https://github.com/ and https://gitlab.com/): ${URL}" >&2
    exit 65
    ;;
esac

# Reject URLs that contain credentials.
if [[ "${URL}" == *"@"* ]]; then
  echo "clone_repo.sh: refusing URL containing credentials" >&2
  exit 66
fi

# Reject URLs with shell metacharacters.
case "${URL}" in
  *' '*|*';'*|*'&'*|*'|'*|*'$'*|*'`'*|*'('*|*')'*|*'<'*|*'>'*|*$'\n'*)
    echo "clone_repo.sh: refusing URL with shell metacharacters" >&2
    exit 67
    ;;
esac

# Derive a slug from the URL: last two path components joined by a dash.
PATH_PART="${URL#https://*/}"
PATH_PART="${PATH_PART%.git}"
SLUG="$(echo "${PATH_PART}" | tr '/' '-' | tr -cd 'a-zA-Z0-9-_')"

DEST_BASE="/tmp/plugin-auditor"
mkdir -p "${DEST_BASE}"

# Use a unique destination per clone to avoid stomping on prior clones.
TIMESTAMP="$(date +%s)"
DEST="${DEST_BASE}/${SLUG}-${TIMESTAMP}"

# Clone with no tags, single branch, depth 1.
# Use a clean GIT_CONFIG_GLOBAL to ignore user gitconfig hooks.
GIT_CONFIG_GLOBAL=/dev/null \
GIT_CONFIG_SYSTEM=/dev/null \
GIT_TERMINAL_PROMPT=0 \
GIT_ASKPASS=true \
git clone \
  --depth 1 \
  --no-tags \
  --single-branch \
  ${REF:+--branch "${REF}"} \
  -- \
  "${URL}" \
  "${DEST}" \
  >&2

# Print the absolute destination on stdout for the caller to consume.
echo "${DEST}"
