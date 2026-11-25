#!/usr/bin/env bash
# git_head.sh <repo_path>
#
# Prints the full HEAD SHA of the audited repository, or exits non-zero when it
# is not a git repository. Runs git with the target's exec-capable config pinned.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: git_head.sh <repo_path>" >&2
  exit 64
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_git.sh
source "${HERE}/lib_git.sh"

git_safe -C "$1" rev-parse --verify HEAD
