# Static Code Checklist

Reference for the `auditor-static` sub-agent. The agent walks the repository statically (no execution) and looks for the patterns below. Helper scripts in `../scripts/` automate the mechanical scanning.

## Scope

Files to scan:

- All text files in the repository, excluding `.git/`, `node_modules/`, `vendor/`, `dist/`, `build/`, `.venv/`, `__pycache__/`.
- Hidden files (dotfiles) in the repo root and one level below.
- Lockfiles (read-only — only to confirm presence, not to scan their content for secrets).

Files to flag on presence (do not open):

- `.env`, `.env.local`, `.env.production` (anything not ending in `.example`).
- `.git-credentials`, `.npmrc` (unless empty), `.pypirc`.
- `.DS_Store`, `Thumbs.db`.

## What to look for

### 1. Secrets and credentials

Run `bash <scripts>/scan_secrets.sh <REPO_PATH>` and parse the output. Each match becomes a `FAIL` finding with the path, line number, and a redacted excerpt (replace the secret value with `<REDACTED>` after the prefix, e.g., `sk-proj-<REDACTED>`).

If a match is in a file under `tests/`, `examples/`, or `docs/` AND the value is obviously fake (e.g., `sk-test-12345`), downgrade to `CAUTION` with a note that test fixtures should still avoid realistic-looking keys.

### 2. Obfuscation and encoded payloads

Run `bash <scripts>/scan_obfuscation.sh <REPO_PATH>`. The script reports:

- High-entropy base64 blocks of 256+ chars.
- High-entropy hex blocks of 256+ chars.
- `eval` / `exec` calls whose argument is a decode call (`base64.b64decode`, `zlib.decompress`, `binascii.unhexlify`).

Each match is a `FAIL`.

### 3. Reverse-shell signatures

Grep for these literal patterns (case-sensitive):

- `bash -i >& /dev/tcp/`
- `nc -e /bin/sh`, `nc -e /bin/bash`
- `python -c 'import socket,subprocess,os'`
- `perl -e 'use Socket'`
- `socat exec:`

Each match is a `FAIL`.

### 4. Dangerous shell patterns

Grep for:

- `eval "$INPUT"`, `eval $@`, `eval "${1}"`, `eval "$*"` — unsafe variable eval.
- `rm -rf /`, `rm -rf $`, `rm -rf "${VAR}/"` (root or unset variable risk).
- `curl ... | bash`, `curl ... | sh`, `wget ... | bash`, `bash <(curl ...)`, `sh <(wget ...)`.
- `chmod +x` immediately followed by execution of a file fetched from the network.

`curl|bash`, root `rm -rf`, and unsafe variable `eval` are `FAIL`. `chmod +x` of a downloaded file is `CAUTION` unless paired with execution (then `FAIL`).

### 5. Modifications to global dotfiles

Grep for writes (`>>`, `>`, `tee -a`) targeting:

- `~/.zshrc`, `~/.bashrc`, `~/.profile`, `~/.bash_profile`, `~/.zprofile`
- `~/.gitconfig`
- `~/.config/fish/config.fish`
- `~/.config/nushell/`
- `~/.tmux.conf`

Each match is a `FAIL`.

### 6. OS persistence

Grep for:

- `crontab` (any invocation that adds entries) → `FAIL`.
- writes to `/etc/cron.d/`, `/var/spool/cron/` → `FAIL`.
- writes to `~/Library/LaunchAgents/`, `/Library/LaunchDaemons/` → `FAIL`.
- writes to `/etc/systemd/system/`, `~/.config/systemd/user/` → `FAIL`.
- `at` command for scheduled jobs → `CAUTION`.

### 7. Binaries committed to the repository

Run `bash <scripts>/scan_binaries.sh <REPO_PATH>`. The script lists files matching:

- Extensions: `.exe`, `.dll`, `.so`, `.dylib`, `.bin`, `.pyc`, `.pyo`, `.class`, `.jar` (with no source counterpart), `.wasm`.
- Anything reported by `file <path>` as `ELF`, `Mach-O`, `PE32`, or `Java class data` outside known build/output directories.

Each binary is a `CAUTION`. Multiple binaries (≥3) escalate the finding's note with "concentrated binary footprint".

### 8. Hidden state files

`CAUTION` for any of these in the repo (one finding per file class):

- `.DS_Store`
- `.git-credentials`
- `.npmrc` containing `_auth`, `_authToken`, or `_password`
- `.pypirc` containing `password`
- Any file matching `*.swp`, `*.swo` (editor leftovers — minor but indicates poor hygiene).

### 9. Long-running background processes

Grep shell scripts and Makefile targets for:

- Trailing ` &` on a non-trivial command (not in a comment, not in a one-shot test).
- `nohup`, `setsid`, `disown`.
- `screen -dmS`, `tmux new-session -d`.

Each match is `CAUTION` unless the surrounding script is clearly a developer-only convenience (e.g., starts a dev server).

## Output format

Return a single markdown block:

```markdown
### FAIL
- `<path>:<line>` — <one-sentence description>
  > <quoted excerpt>

### CAUTION
- `<path>:<line>` — <one-sentence description>
  > <quoted excerpt>

### OK
- No hardcoded credentials detected (scan_secrets.sh: 0 matches)
- No obfuscated payloads detected (scan_obfuscation.sh: 0 matches)
- No reverse-shell signatures detected
- No modifications to global dotfiles
- No OS persistence patterns detected
- No binaries committed
- No hidden state files (.env, .git-credentials, etc.)
```

If a class of check has no findings, list it under `### OK` with the exact name from the catalogue. Do not invent positive checks that were not actually performed.
