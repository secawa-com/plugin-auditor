# Pinned base image by digest — a legitimate supply-chain hardening practice.
# The 64-char sha256 must NOT trip scan_obfuscation's hex-blob detector.
FROM python:3.12-slim@sha256:9c1c1c1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6

# A git-action-style pin also uses a 40-char hex SHA.
# uses: actions/checkout@a12f3e4b5c6d7089a1b2c3d4e5f60718293a4b5c
LABEL org.opencontainers.image.title="safe-fixture"
