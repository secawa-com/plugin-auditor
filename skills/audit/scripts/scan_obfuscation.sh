#!/usr/bin/env bash
# scan_obfuscation.sh <repo_path>
#
# Surfaces obfuscation indicators:
#   - base64 / base32 / hex blocks (>= 64 chars) with high Shannon entropy
#   - reverse-shell signatures
#   - decode-then-execute sequences, on one line AND across lines in the same file
#   - alternative encoders (bytes([...]), String.fromCharCode, zlib/gzip/lzma)
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

# 1) Encoded blocks (base64 / base32 / hex) with entropy check, and cross-line
#    decode-then-execute detection. Done in Python for entropy + multi-line state.
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

# Threshold lowered from 256 to 64: a stager payload fits in far fewer chars
# than a full script. Entropy gate keeps prose and identifiers out.
MIN_BLOB = 64
BASE64_RUN = re.compile(r"[A-Za-z0-9+/]{%d,}={0,2}" % MIN_BLOB)
BASE32_RUN = re.compile(r"[A-Z2-7]{%d,}={0,6}" % MIN_BLOB)
HEX_RUN = re.compile(r"(?:0x)?[0-9a-fA-F]{%d,}" % MIN_BLOB)

# Any decode primitive across common languages.
# bytes([...]) is narrowed to a numeric byte-list of at least 8 elements so an
# ordinary bytes([0]) does not read as a payload builder.
DECODE_RE = re.compile(
    r"b64decode|b32decode|base64_decode|unhexlify|fromhex|"
    r"zlib\.decompress|gzip\.decompress|lzma\.decompress|"
    r"Buffer\.from\s*\([^)]*base64|atob\s*\(|"
    r"String\.fromCharCode|bytes\s*\(\s*\[\s*(?:\d+\s*,\s*){7,}",
    re.IGNORECASE,
)
# Any execution primitive across common languages.
# compile( uses fixed-width negative lookbehinds so the stdlib re.compile /
# regex.compile pattern-compilers are not mistaken for code compilation. Other
# module-qualified compile() calls (e.g. builtins.compile) are still caught.
EXEC_RE = re.compile(
    r"\bexec\s*\(|\beval\s*\(|(?<!re\.)(?<!regex\.)\bcompile\s*\(|runpy|"
    r"os\.system|subprocess\.(run|call|Popen|check_output)|popen|"
    r"child_process|\bFunction\s*\(|new\s+Function|"
    r"\bsystem\s*\(|\bspawn\s*\(",
    re.IGNORECASE,
)

# Checksums and git SHA pins are long hex runs with no malicious intent. A
# sha256 digest is exactly 64 hex chars with entropy ~3.8, which clears the hex
# gate. Skip a hex blob when its length is a known digest width and the line
# names a hash, or when it is a git-style pin immediately preceded by '@'.
HASH_CONTEXT = re.compile(r"sha1|sha256|sha512|integrity|checksum|digest|hash", re.IGNORECASE)
DIGEST_WIDTHS = {40, 64, 128}
# Same-line decode->exec (kept for the tight classic form).
SAME_LINE = re.compile(r"(exec|eval|system|popen|spawn|Function)\s*\(.*(b64decode|b32decode|unhexlify|decompress|atob|fromCharCode)", re.IGNORECASE)

def entropy(s):
    if not s:
        return 0.0
    counts = {}
    for c in s:
        counts[c] = counts.get(c, 0) + 1
    n = len(s)
    h = 0.0
    for k in counts.values():
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
                lines = f.readlines()
        except (OSError, UnicodeDecodeError):
            continue

        decode_lines = []   # (lineno) where a decode primitive appears
        exec_lines = []     # (lineno) where an execution primitive appears

        for lineno, line in enumerate(lines, start=1):
            # Encoded blocks. Longest/most-specific first so hex does not eat base32.
            for category, regex in (
                ("base64_blob", BASE64_RUN),
                ("base32_blob", BASE32_RUN),
                ("hex_blob", HEX_RUN),
            ):
                for m in regex.finditer(line):
                    blob = m.group(0)
                    # Digest / git-SHA suppression, applied to any category
                    # (a 64-hex digest is also a valid base64 run). A hex-only
                    # blob of digest width in a hash context, or a git pin
                    # preceded by '@', is legitimate and skipped.
                    hexonly = re.fullmatch(r"(?:0x)?[0-9a-fA-F]+", blob)
                    if hexonly and len(blob.removeprefix("0x")) in DIGEST_WIDTHS:
                        at_pinned = m.start() > 0 and line[m.start() - 1] == "@"
                        if at_pinned or HASH_CONTEXT.search(line):
                            continue
                    # Hex entropy is naturally low (16-symbol alphabet); use a
                    # lower gate for hex, higher for the richer base alphabets.
                    h = entropy(blob)
                    gate = 3.2 if category == "hex_blob" else 4.0
                    if h >= gate:
                        print(f"{path}:{lineno}:{category}:length={len(blob)} entropy={h:.2f}")
                        break  # one report per line per category is enough

            if SAME_LINE.search(line):
                print(f"{path}:{lineno}:decode_exec:same-line decode fed to execution")

            if DECODE_RE.search(line):
                decode_lines.append(lineno)
            if EXEC_RE.search(line):
                exec_lines.append(lineno)

        # Cross-line: a decode followed by an execution primitive within a 25-line
        # window. The window bounds both directions so an unrelated decode and exec
        # at opposite ends of a large file do not chain into a false positive.
        if decode_lines and exec_lines:
            for el in exec_lines:
                near = [d for d in decode_lines if abs(d - el) <= 25 and d != el]
                if near:
                    src = max([d for d in near if d <= el], default=near[0])
                    print(f"{path}:{el}:decode_exec_multiline:decode at line {src} executed at line {el}")
                    break  # one multiline report per file avoids noise
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
