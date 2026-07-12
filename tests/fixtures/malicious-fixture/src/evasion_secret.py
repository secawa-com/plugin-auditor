# Planted evasion: a provider-agnostic secret with no recognisable prefix,
# assigned as a high-entropy string. Should be caught by scan_secrets.sh's
# generic_high_entropy_assignment pass (the prefix catalogue would miss it).
#
# A second secret is split across concatenation to dodge single-token regexes;
# this one is a KNOWN GAP (documented in expectations.md) — static concat
# reassembly is out of scope for the mechanical scanner.

session_api_token = "Zx9Qw3Rt7Yu1Op4As6Df8Gh0Jk2Lm5Nb"

# Known gap: reassembled at runtime, not visible to a per-line scan.
_a = "AKIA" + "JKLMNOP" + "QRSTUV12" + "3456"
