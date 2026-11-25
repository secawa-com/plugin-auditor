#!/usr/bin/env bash
# lib_status.sh: sourced first by every scan helper.
#
# A helper that fails or writes to stderr must not read as a clean scan. Its
# stderr is captured and, on exit, one status line goes to the original stdout:
#   helper_error:<helper>:rc=<n>:<first stderr line>
# The captured stderr is replayed to the caller's stderr as well.

_HS_NAME="$(basename "$0")"
_HS_ERR="$(mktemp)"
_HS_TMP=""
exec 3>&1 4>&2 2>"${_HS_ERR}"

_hs_exit() {
  local rc=$?
  if [[ ${rc} -ne 0 || -s "${_HS_ERR}" ]]; then
    printf 'helper_error:%s:rc=%s:%s\n' "${_HS_NAME}" "${rc}" "$(head -n1 "${_HS_ERR}" | tr -d '\r')" >&3
    cat "${_HS_ERR}" >&4
  fi
  rm -f "${_HS_ERR}"
  if [[ -n "${_HS_TMP}" ]]; then rm -f "${_HS_TMP}"; fi
  exit "${rc}"
}
trap _hs_exit EXIT
