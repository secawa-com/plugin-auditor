#!/usr/bin/env bash
# cleanup_clone.sh <clone_path>
#
# Safely removes a directory from a previous clone:
#   1. <clone_path> must be a directory inside <cwd>/.plugin-auditor-tmp/.
#   2. After removal, if .plugin-auditor-tmp/ is empty we also remove the
#      base directory itself.
#
# Stdout: short report of what was done (one line per action).
# Exits non-zero if the path is outside the allowed base directory.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: cleanup_clone.sh <clone_path>" >&2
  exit 64
fi

TARGET="$1"
BASE="${PWD}/.plugin-auditor-tmp"

# Require an absolute path to avoid ambiguity.
case "${TARGET}" in
  /*) ;;
  *)
    echo "cleanup_clone.sh: refusing non-absolute path: ${TARGET}" >&2
    exit 65
    ;;
esac

# Reject path traversal (../) in the argument.
case "${TARGET}" in
  *..*)
    echo "cleanup_clone.sh: refusing path containing '..': ${TARGET}" >&2
    exit 66
    ;;
esac

# TARGET must have BASE/ as prefix and must not be BASE itself.
if [[ "${TARGET}" != "${BASE}/"* ]]; then
  echo "cleanup_clone.sh: refusing path outside ${BASE}: ${TARGET}" >&2
  exit 67
fi

if [[ ! -d "${TARGET}" ]]; then
  echo "cleanup_clone.sh: not a directory (already removed?): ${TARGET}"
  # Still try to collapse an empty BASE below.
else
  rm -rf -- "${TARGET}"
  echo "removed: ${TARGET}"
fi

# If BASE is empty, remove it as well.
if [[ -d "${BASE}" ]]; then
  if [[ -z "$(ls -A "${BASE}" 2>/dev/null)" ]]; then
    rmdir -- "${BASE}"
    echo "removed empty base: ${BASE}"
  else
    echo "kept base (still has entries): ${BASE}"
  fi
fi
