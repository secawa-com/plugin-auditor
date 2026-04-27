#!/usr/bin/env bash
# scan_binaries.sh <repo_path>
#
# Lists files that look like committed binaries.
# Falls back to extension-only matching if the `file` command is unavailable.
#
# Output: <path>\t<source>
#   where <source> is "ext" or "file"

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: scan_binaries.sh <repo_path>" >&2
  exit 64
fi

REPO="$1"
if [[ ! -d "${REPO}" ]]; then
  echo "scan_binaries.sh: not a directory: ${REPO}" >&2
  exit 65
fi

# Extension-based pass.
BIN_EXTENSIONS=(
  exe dll so dylib bin pyc pyo class jar wasm
  o a obj lib msi deb rpm pkg dmg iso
)

EXT_FIND_ARGS=()
for i in "${!BIN_EXTENSIONS[@]}"; do
  if [[ ${i} -gt 0 ]]; then
    EXT_FIND_ARGS+=( -o )
  fi
  EXT_FIND_ARGS+=( -name "*.${BIN_EXTENSIONS[$i]}" )
done

find "${REPO}" \
  -type d \( -name .git -o -name node_modules -o -name vendor -o -name dist -o -name build -o -name .venv -o -name __pycache__ \) -prune \
  -o -type f \( "${EXT_FIND_ARGS[@]}" \) -print 2>/dev/null \
  | while IFS= read -r f; do
      printf '%s\text\n' "${f}"
    done

# `file`-based pass for everything else.
if command -v file >/dev/null 2>&1; then
  find "${REPO}" \
    -type d \( -name .git -o -name node_modules -o -name vendor -o -name dist -o -name build -o -name .venv -o -name __pycache__ \) -prune \
    -o -type f -size +1k -print 2>/dev/null \
    | while IFS= read -r f; do
        # Skip already-flagged ext matches.
        case "${f}" in
          *.exe|*.dll|*.so|*.dylib|*.bin|*.pyc|*.pyo|*.class|*.jar|*.wasm|*.o|*.a|*.obj|*.lib|*.msi|*.deb|*.rpm|*.pkg|*.dmg|*.iso)
            continue ;;
        esac
        ftype="$(file -b "${f}" 2>/dev/null || true)"
        case "${ftype}" in
          ELF*|Mach-O*|"PE32 "*|"PE32+ "*|"Java class data"*|"WebAssembly"*)
            printf '%s\tfile:%s\n' "${f}" "${ftype%% *}"
            ;;
        esac
      done
fi
