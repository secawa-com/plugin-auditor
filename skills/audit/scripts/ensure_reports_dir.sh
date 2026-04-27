#!/usr/bin/env bash
# ensure_reports_dir.sh
#
# Idempotently creates the reports directory tree under the user's home dir.
# Called at the start of every audit by SKILL.md.

set -euo pipefail

REPORTS_DIR="${HOME}/.claude/plugin-auditor-reports"
STATE_DIR="${REPORTS_DIR}/.state"

mkdir -p "${REPORTS_DIR}"
mkdir -p "${STATE_DIR}"

# Restrict permissions: reports may contain quoted code from audited repos
# (including potentially sensitive identifiers) so keep them user-only.
chmod 700 "${REPORTS_DIR}"
chmod 700 "${STATE_DIR}"

echo "${REPORTS_DIR}"
