"""Ordinary text parsing. Uses re.compile and bytes([...]) legitimately —
neither should be read as a decode-then-execute chain by scan_obfuscation."""

import re

TOKEN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
MAGIC = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])


def tokenize(text):
    return TOKEN.findall(text)


def is_png(header):
    return header[:8] == MAGIC
