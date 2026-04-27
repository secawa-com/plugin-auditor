#!/usr/bin/env bash
# scan_obfuscation.sh <repo_path>
#
# Surfaces obfuscation indicators:
#   - long base64 / hex blocks (>= 256 chars) with high Shannon entropy
#   - reverse-shell signatures
#   - decode-then-spawn-shell sequences (best-effort grep)
#
# Output: <path>:<line>:<category>:<short reason>

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: scan_obfuscation.sh <repo_path>" >&2
  exit 64
fi

REPO="$1"
if [[ ! -d "${REPO}" ]]; then
  echo "scan_obfuscation.sh: not a directory: ${REPO}" >&2
  exit 65
fi

# 1) Long base64 / hex blocks with entropy check.
python3 - "${REPO}" <<'PYEOF'
import math
import os
import re
import sys

repo = sys.argv[1]

EXCLUDE_DIRS = {".git", "node_modules", "vendor", "dist", "build", ".venv", "__pycache__"}
EXCLUDE_FILES = {
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
    "poetry.lock", "uv.lock", "Cargo.lock",
    "Gemfile.lock", "composer.lock",
}

BASE64_RUN = re.compile(r"[A-Za-z0-9+/=]{256,}")
HEX_RUN = re.compile(r"[0-9a-fA-F]{256,}")

def entropy(s):
    if not s:
        return 0.0
    counts = {}
    for c in s:
        counts[c] = counts.get(c, 0) + 1
    n = len(s)
    h = 0.0
    for c, k in counts.items():
        p = k / n
        h -= p * math.log2(p)
    return h

for root, dirs, files in os.walk(repo):
    dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
    for fn in files:
        if fn in EXCLUDE_FILES:
            continue
        path = os.path.join(root, fn)
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                for lineno, line in enumerate(f, start=1):
                    for category, regex in (("base64_blob", BASE64_RUN), ("hex_blob", HEX_RUN)):
                        for m in regex.finditer(line):
                            blob = m.group(0)
                            h = entropy(blob)
                            if h >= 4.5:
                                print(f"{path}:{lineno}:{category}:length={len(blob)} entropy={h:.2f}")
        except (OSError, UnicodeDecodeError):
            continue
PYEOF

# 2) Reverse-shell signatures.
EXCLUDES=(
  --exclude-dir=.git
  --exclude-dir=node_modules
  --exclude-dir=vendor
  --exclude-dir=dist
  --exclude-dir=build
  --exclude-dir=.venv
  --exclude-dir=__pycache__
)

REVERSE_SHELL_PATTERNS=(
  'bash -i >& /dev/tcp/'
  'sh -i >& /dev/tcp/'
  'bash -c .*dev/tcp'
  'nc -e /bin/sh'
  'nc -e /bin/bash'
  'ncat -e /bin/sh'
  'socat exec:'
  'New-Object System.Net.Sockets.TCPClient'
)
for p in "${REVERSE_SHELL_PATTERNS[@]}"; do
  while IFS= read -r line; do
    path="${line%%:*}"; rest="${line#*:}"; lineno="${rest%%:*}"
    printf '%s:%s:reverse_shell:%s\n' "${path}" "${lineno}" "${p}"
  done < <(grep -RnE -I "${EXCLUDES[@]}" -e "${p}" "${REPO}" 2>/dev/null || true)
done

# 3) Decode-then-execute sequences (best-effort: same line).
DECODE_EXEC_PATTERNS=(
  'b64decode\(.*\).*(system|popen|run|spawn|call)'
  'unhexlify\(.*\).*(system|popen|run|spawn|call)'
  'zlib.decompress\(.*\).*(system|popen|run|spawn|call)'
  'Buffer.from\([^)]*base64[^)]*\).*(exec|spawn)'
  'atob\(.*\).*(eval|Function)'
)
for p in "${DECODE_EXEC_PATTERNS[@]}"; do
  while IFS= read -r line; do
    path="${line%%:*}"; rest="${line#*:}"; lineno="${rest%%:*}"
    printf '%s:%s:decode_exec:%s\n' "${path}" "${lineno}" "${p}"
  done < <(grep -RnE -I "${EXCLUDES[@]}" -e "${p}" "${REPO}" 2>/dev/null || true)
done
