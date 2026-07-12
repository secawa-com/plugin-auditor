# Planted evasion: decode-then-exec split across lines, short payload (<256 chars),
# and a base32-encoded variant. Should be caught by scan_obfuscation.sh's lowered
# threshold + multi-line decode_exec pass, NOT by the old same-line 256-char rule.

import base64

# Short base64 payload, well under the old 256-char threshold.
_p = "cHJpbnQoJ293bmVkJyk="
_decoded = base64.b64decode(_p)
exec(_decoded)  # decode on line above, exec here: multi-line chain

# base32 variant, decode and run in separate statements.
_q = "NBSWY3DPEB3W64TMMQ======"
_r = base64.b32decode(_q)
eval(compile(_r, "<x>", "exec"))
