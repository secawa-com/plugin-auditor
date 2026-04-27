#!/usr/bin/env bash
# compute_delta.sh <repo_path> <prev_sha>
#
# Lists files changed in the audited repository between <prev_sha> and HEAD.
# Output: one absolute path per line.
#
# Read-only. Prints nothing if the previous SHA is not reachable.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: compute_delta.sh <repo_path> <prev_sha>" >&2
  exit 64
fi

REPO="$1"
PREV="$2"

if [[ ! -d "${REPO}/.git" ]]; then
  echo "compute_delta.sh: ${REPO} is not a git repository" >&2
  exit 65
fi

# Verify the previous SHA is reachable.
if ! git -C "${REPO}" cat-file -e "${PREV}^{commit}" 2>/dev/null; then
  echo "compute_delta.sh: previous SHA ${PREV} not reachable in ${REPO}" >&2
  exit 66
fi

git -C "${REPO}" diff --name-only "${PREV}" HEAD 2>/dev/null \
  | while IFS= read -r rel; do
      [[ -z "${rel}" ]] && continue
      printf '%s/%s\n' "${REPO}" "${rel}"
    done
