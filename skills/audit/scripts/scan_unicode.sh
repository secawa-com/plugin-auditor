#!/usr/bin/env bash
# scan_unicode.sh <repo_path>
#
# Surfaces invisible / deceptive Unicode in text files: characters that a human
# reviewer cannot see but that a language model reads. These are a classic way to
# hide prompt-injection instructions or to disguise one identifier as another.
#
# Detects:
#   - zero-width characters (U+200B-200D, U+FEFF, U+2060)
#   - bidirectional overrides (U+202A-202E, U+2066-2069)
#   - other invisible format / control characters
#   - Cyrillic/Greek homoglyphs mixed into an otherwise ASCII-Latin word
#
# Output: <path>:<line>:<category>:<codepoint(s)>
#
# Read-only. Never modifies the repository.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: scan_unicode.sh <repo_path>" >&2
  exit 64
fi

REPO="$1"
if [[ ! -d "${REPO}" ]]; then
  echo "scan_unicode.sh: not a directory: ${REPO}" >&2
  exit 65
fi

python3 - "${REPO}" <<'PYEOF'
import os
import sys
import unicodedata

repo = sys.argv[1]

EXCLUDE_DIRS = {".git", "node_modules", "vendor", "dist", "build", ".venv", "__pycache__"}
EXCLUDE_FILES = {
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
    "poetry.lock", "uv.lock", "Cargo.lock", "Gemfile.lock", "composer.lock",
}

ZERO_WIDTH = {0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF}
BIDI = {0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069}

# Homoglyph letters from non-Latin scripts that render like ASCII Latin letters.
HOMOGLYPHS = {
    0x0410, 0x0412, 0x0415, 0x041A, 0x041C, 0x041D, 0x041E, 0x0420, 0x0421,
    0x0422, 0x0425, 0x0430, 0x0435, 0x043E, 0x0440, 0x0441, 0x0443, 0x0445,  # Cyrillic
    0x0391, 0x0392, 0x0395, 0x0396, 0x0397, 0x0399, 0x039A, 0x039C, 0x039D,
    0x039F, 0x03A1, 0x03A4, 0x03A5, 0x03A7,  # Greek capitals
}


def is_invisible_format(cp):
    # Format (Cf) and most control (Cc, except tab/newline/carriage return) chars
    # carry no visible glyph.
    if cp in (0x09, 0x0A, 0x0D):
        return False
    cat = unicodedata.category(chr(cp))
    return cat in ("Cf", "Cc")


for root, dirs, files in os.walk(repo):
    dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
    for fn in files:
        if fn in EXCLUDE_FILES:
            continue
        path = os.path.join(root, fn)
        try:
            with open(path, "r", encoding="utf-8", errors="strict") as f:
                lines = f.readlines()
        except (OSError, UnicodeDecodeError):
            # Binary or non-UTF-8; not a text artifact we can reason about.
            continue

        for lineno, line in enumerate(lines, start=1):
            zw, bd, homo, other = [], [], [], []
            for ch in line:
                cp = ord(ch)
                if cp < 0x80:
                    continue
                if cp in ZERO_WIDTH:
                    zw.append(cp)
                elif cp in BIDI:
                    bd.append(cp)
                elif cp in HOMOGLYPHS:
                    homo.append(cp)
                elif is_invisible_format(cp):
                    other.append(cp)

            def fmt(cps):
                return " ".join("U+%04X" % c for c in sorted(set(cps)))

            if zw:
                print(f"{path}:{lineno}:zero_width:{fmt(zw)}")
            if bd:
                print(f"{path}:{lineno}:bidi_override:{fmt(bd)}")
            if other:
                print(f"{path}:{lineno}:invisible_format:{fmt(other)}")
            if homo:
                print(f"{path}:{lineno}:homoglyph:{fmt(homo)}")
PYEOF
