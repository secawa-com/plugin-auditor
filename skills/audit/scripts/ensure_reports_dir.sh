#!/usr/bin/env bash
# ensure_reports_dir.sh
#
# Idempotently creates the reports directory tree under the user's home dir.
# Called at the start of every audit by SKILL.md.

set -euo pipefail

REPORTS_DIR="${HOME}/.claude/plugin-auditor-reports"
STATE_DIR="${REPORTS_DIR}/.state"
# Raw scan outputs, written by the orchestrator for the mechanical cross-check.
# Kept beside reports so a compromised sub-agent cannot silence a helper without
# the orchestrator's own copy disagreeing.
RAW_DIR="${REPORTS_DIR}/.raw"

mkdir -p "${REPORTS_DIR}"
mkdir -p "${STATE_DIR}"
mkdir -p "${RAW_DIR}"

# Restrict permissions: reports and raw outputs may contain quoted code from
# audited repos (including potentially sensitive identifiers) so keep them user-only.
chmod 700 "${REPORTS_DIR}"
chmod 700 "${STATE_DIR}"
chmod 700 "${RAW_DIR}"

echo "${REPORTS_DIR}"
