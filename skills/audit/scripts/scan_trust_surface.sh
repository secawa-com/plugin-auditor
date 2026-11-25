#!/usr/bin/env bash
# scan_trust_surface.sh <repo_path>
#
# Surfaces code paths that run later, outside the user's review, or with more
# reach than the plugin needs: writes to files another trusted process loads,
# exec-capable git config, Python import shadowing, sandbox weakening, things
# that run before trust, credential reach, lateral movement, non-HTTP exfil
# channels, third-party model routers and non-default package indexes.
#
# Output: <path>:<line>:<category>:<excerpt>, one per line, and
#         skipped:<reason>:<relpath> for files it could not read.
# Owners (for the orchestrator's mechanical cross-check):
#   auditor-config        config_write git_exec_config py_stdlib_shadow py_pth
#                         sandbox_weaken pre_trust
#   auditor-network-fs    cred_reach lateral_movement exfil_channel llm_router
#   auditor-supply-chain  nondefault_index lifecycle_script
#
# Read-only. Never executes or modifies anything in the repository.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_status.sh
source "${HERE}/lib_status.sh"

if [[ $# -lt 1 ]]; then
  echo "usage: scan_trust_surface.sh <repo_path>" >&2
  exit 64
fi

REPO="$1"
if [[ ! -d "${REPO}" ]]; then
  echo "scan_trust_surface.sh: not a directory: ${REPO}" >&2
  exit 65
fi

# Hits in plain documentation get a doc: prefix; the sub-agent decides if they matter.
python3 -I - "${REPO}" <<'PYEOF' | python3 -I "${HERE}/doc_class.py" lines "${REPO}"
import json
import os
import re
import sys
from urllib.parse import urlsplit

repo = sys.argv[1].rstrip("/")
EXCLUDE_DIRS = {".git", "node_modules", "vendor", "dist", "build", ".venv", "__pycache__"}
EXCLUDE_FILES = {
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
    "poetry.lock", "uv.lock", "Cargo.lock", "Gemfile.lock", "composer.lock",
}
MAX_BYTES = 2 * 1024 * 1024
seen = set()


def emit(path, lineno, cat, text):
    key = (path, lineno, cat)
    if key in seen:
        return
    seen.add(key)
    excerpt = " ".join(text.strip().split())[:160]
    print(f"{path}:{lineno}:{cat}:{excerpt}")


def skip(full, reason):
    print(f"skipped:{reason}:{os.path.relpath(full, repo)}")


def line_of(lines, needle):
    for i, l in enumerate(lines, start=1):
        if needle in l:
            return i, l
    return 1, lines[0] if lines else ""


# Stdlib names commonly imported by tooling; a same-named file in a script dir wins the import.
STDLIB = {
    "abc", "argparse", "ast", "asyncio", "base64", "binascii", "codecs", "collections",
    "contextlib", "copy", "csv", "ctypes", "datetime", "dataclasses", "enum", "functools",
    "getpass", "glob", "gzip", "hashlib", "hmac", "html", "http", "importlib", "inspect",
    "io", "ipaddress", "itertools", "json", "logging", "math", "os", "pathlib", "pickle",
    "platform", "pprint", "queue", "random", "re", "secrets", "select", "shlex", "shutil",
    "signal", "site", "socket", "sqlite3", "ssl", "stat", "string", "struct", "subprocess",
    "sys", "tempfile", "textwrap", "threading", "time", "traceback", "types", "typing",
    "unittest", "urllib", "uuid", "warnings", "weakref", "zipfile", "zlib",
}
ALWAYS_SHADOW = {"sitecustomize", "usercustomize"}

ARTIFACT_RE = re.compile(r"(^|/)(SKILL\.md|CLAUDE\.md|AGENTS\.md)$|(^|/)(agents|commands|hooks)/")

# Files another trusted process loads later: agent settings, hooks, editor tasks, git, venv, CI.
TRUSTED_TARGET = (
    r"(\.claude/(settings[\w.-]*\.json|hooks/|commands/|agents/|skills/)|\.mcp\.json|"
    r"\.vscode/(tasks|settings|launch)\.json|\.git/hooks/|\.git/config|\.githooks/|\.husky/|"
    r"(bin|Scripts)/activate|\.envrc|\.github/workflows/|\.gitlab-ci\.yml|\.circleci/config)"
)
# The target must be the destination: redirect, tee, last arg of cp/mv/ln, or a write call.
P = r"[\"']?[^\s\"']*"
CODE_WRITE_TO = (
    rf"(>>?\s*{P}|\btee\s+(-a\s+)?{P}|\b(cp|mv|ln)\s[^\n]*\s{P}|\b(sed|perl)\s+-p?i\S*\s[^\n]*|"
    rf"(writeFile\w*|appendFile\w*|createWriteStream|copyFile\w*|shutil\.(copy\w*|move))\([^)]*|"
    rf"\b(Write|Edit)\([^)]*|open\([^)]*)"
)
CODE_WRITE = r"(>>?|\btee\b|\bcp\b|\bmv\b|writeFile|appendFile|write_text|write_bytes|open\([^)]*['\"][wa])"
PROSE_WRITE = r"\b(write|edit|append|add|update|modify|create|overwrite|replace|patch|insert|drop)\b"

LINE_RULES = [
    ("config_write", re.compile(rf"{CODE_WRITE_TO}{TRUSTED_TARGET}")),
    ("config_write", re.compile(r"\bnpm\s+(pkg\s+set\s+scripts\.|set-script\b)|(writeFile\w*|write_text|json\.dump)\([^\n]*package\.json")),
    ("git_exec_config", re.compile(
        r"\bgit\s+(-c\s+|config\s+(--\w+\s+)*)"
        r"(core\.(fsmonitor|hookspath|sshcommand|pager|editor|askpass|gitproxy)|diff\.external|"
        r"diff\.[\w.-]+\.(textconv|command)|filter\.[\w.-]+\.(clean|smudge|process)|"
        r"merge\.[\w.-]+\.driver|credential\.helper|include\.path)", re.I)),
    ("git_exec_config", re.compile(r"\bGIT_(SSH_COMMAND|EXTERNAL_DIFF|PAGER|ASKPASS|CONFIG_GLOBAL|CONFIG_PARAMETERS)\s*=(?![\"']?(/dev/null|true|false|cat|0|1)?[\"']?(\s|$))")),
    ("py_pth", re.compile(r"(site-packages|dist-packages|getsitepackages|USER_SITE)[^\n]*\.p[t]h\b|\.p[t]h\b[^\n]*(site-packages|dist-packages)")),
    ("py_pth", re.compile(rf"{CODE_WRITE}[^\n]*(sitecustomize|usercustomize)\.py")),
    ("sandbox_weaken", re.compile(
        r"dangerouslyDisableSandbo[x]|--dangerously-skip-permission[s]|"
        r"(defaultMode[\"']?\s*[:=]\s*[\"']?|--permission-mode[\s=]+)bypassPermissions|"
        r"allowUnsandboxedCommands[\"']?\s*[:=]\s*true|skipDangerousModePermissionPromp[t]|"
        r"docker\.sock|--privilege[d]\b|"
        r"(-v|--volume|--mount)[\s=]+[\"']?(\$HOME|\$\{HOME\}|~|/Users/[\w.-]+|/home/[\w.-]+|/root)/?[\"']?:")),
    ("pre_trust", re.compile(r"enableAllProjectMcpServers[\"']?\s*[:=]\s*true|enabledMcpjsonServer[s]")),
    ("cred_reach", re.compile(
        r"(~|\$HOME|\$\{HOME\}|homedir\(\)|expanduser\([\"']~)[/\"', +]*\.(aws|ssh|kube|azure|docker/config\.json|netrc|pgpass|git-credentials|config/(gh|gcloud))|"
        r"\.ssh/i[d]_|\bgh\s+auth\s+token\b|\bsecurity\s+(find-generic-password|find-internet-password|dump-keychain)|"
        r"\bsecret-tool\s+lookup|Login Dat[a]|Cookies\.sqlite|key4\.db|Application Support/(Google/Chrome|BraveSoftware|Firefox|Microsoft Edge)|"
        r"\.mozill[a]/firefox|\baws\s+configure\s+(export-credentials|get)|gcloud\s+auth\s+print-access-token|"
        r"az\s+account\s+get-access-token|(\bcat|\bsource|load_dotenv\(|readFile\w*\(|open\()[^\n]*['\" /]\.env\b|"
        r"\$\{?(GITHUB_TOKEN|GH_TOKEN|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|ANTHROPIC_API_KEY|OPENAI_API_KEY|NPM_TOKEN)\b")),
    ("lateral_movement", re.compile(
        r"(^|[\s;&|(`$\"'])ssh\s+(-\S+\s+)*[\w.-]+@[\w.-]+|\b(scp|sftp|rsync)\s[^\n]*?[\w.-]+@[\w.-]+:|"
        r"\b(Invoke-Comman[d]|Enter-PSSessio[n]|New-PSSessio[n])\b|\baws\s+ssm\s+(send-command|start-session)|"
        r"\bgcloud\s+compute\s+ssh|\baz\s+(vm\s+run-command|ssh\s+vm)|\bkubectl\s+(exec|cp)\b|\bdocker\s+-H\s|"
        r"claude-in-chrom[e]|--remote-debugging-por[t]|launchPersistentContex[t]|user-data-di[r]", re.I)),
    ("exfil_channel", re.compile(
        r"\bgit\s+push\s+(-\S+\s+)*(https?://|git@|ssh://)|\bgit\s+remote\s+(add|set-url)\s+\S+\s+(https?://|git@|ssh://)|"
        r"\baws\s+s3\s+(cp|sync|mv)\b|\bs3api\s+put-object|\bgsutil\s+(cp|rsync|mv)\b|\bgcloud\s+storage\s+(cp|rsync)\b|"
        r"\baz\s+storage\s+blob\s+upload|\brclone\s+(copy|sync|move)\b|\bgh\s+gist\s+create|\bgh\s+issue\s+(create|comment)|"
        r"\bgh\s+api\s[^\n]*(gists|/issues)|api\.github\.com/gists|hooks\.slack\.com/|discord(app)?\.com/api/webhooks|"
        r"webhook\.site|pastebin\.com|transfer\.sh|requestbi[n]|\binteract\.sh|\.oast\.")),
    ("nondefault_index", re.compile(
        r"\b(pip3?|uv\s+pip|python3?\s+-m\s+pip)\s+install\b[^\n]*(--index-url|--extra-index-url|-i\s+https?://|--trusted-host)|"
        r"\b(npm|pnpm|yarn|npx|bun)\b[^\n]*--registry[\s=]|\bnpm\s+config\s+set\s+registry|"
        r"\bInstall-(Module|Package|PSResource)\b[^\n]*-Repository|\bRegister-PS(Repository|ResourceRepository)\b|"
        r"\bgem\s+install\b[^\n]*--source", re.I)),
]
# Every index option on the line, so a first-party --index-url cannot vouch for an --extra-index-url.
INDEX_OPT = re.compile(r"(?:--index-url|--extra-index-url|--registry|(?<![\w-])-i)(?:\s+|=)[\"']?([^\s\"']+)")
FIRST_PARTY_INDEX_HOSTS = {"pypi.org", "registry.npmjs.org"}
ROUTER_RE = re.compile(
    r"\b(ANTHROPIC_BASE_URL|ANTHROPIC_BEDROCK_BASE_URL|ANTHROPIC_VERTEX_BASE_URL|OPENAI_BASE_URL|OPENAI_API_BASE)\b"
    r"[^\n]*?(https?://[^\s\"'<>`]+)")
# Loopback is the user's own proxy or a test stub, not a third-party router.
FIRST_PARTY_MODEL = {"api.anthropic.com", "api.openai.com", "localhost", "127.0.0.1"}


def url_host(url):
    # hostname drops userinfo and port: https://api.anthropic.com@evil.example.invalid is evil.example.invalid.
    try:
        return (urlsplit(url).hostname or "").lower()
    except ValueError:
        return ""


def first_party_index(line):
    urls = INDEX_OPT.findall(line)
    return bool(urls) and all(
        u.lower().startswith("https://") and url_host(u) in FIRST_PARTY_INDEX_HOSTS for u in urls)


LIFECYCLE = {"preinstall", "install", "postinstall", "prepare", "prepack", "postpack", "prepublish", "preuninstall", "postuninstall"}

GIT_KEYS = {
    "core": {"fsmonitor", "hookspath", "sshcommand", "pager", "editor", "askpass", "gitproxy"},
    "diff": {"external", "textconv", "command"},
    "filter": {"clean", "smudge", "process"},
    "merge": {"driver"},
    "credential": {"helper"},
    "include": {"path"},
    "includeif": {"path"},
    "sequence": {"editor"},
    "gpg": {"program"},
    "alias": None,
}


def scan_git_config(rel, lines):
    section = None
    for n, raw in enumerate(lines, start=1):
        s = raw.strip()
        m = re.match(r"^\[\s*([A-Za-z]+)", s)
        if m:
            section = m.group(1).lower()
            continue
        kv = re.match(r"^([A-Za-z][\w-]*)\s*=\s*(.*)$", s)
        if not kv or section not in GIT_KEYS:
            continue
        key, val = kv.group(1).lower(), kv.group(2).strip()
        if section == "alias":
            if val.strip("\"'").startswith("!"):
                emit(rel, n, "git_exec_config", raw)
            continue
        if key in GIT_KEYS[section]:
            # Booleans (builtin fsmonitor) and cat are inert; only a command path runs code.
            if val.strip("\"'").lower() in {"true", "false", "0", "1", "cat", ""}:
                continue
            emit(rel, n, "git_exec_config", raw)


def walk_json(obj, path=()):
    yield path, obj
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield from walk_json(v, path + (k,))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from walk_json(v, path + (i,))


def scan_settings(rel, lines, data):
    if not isinstance(data, dict):
        return
    sb = data.get("sandbox")
    if isinstance(sb, dict):
        if sb.get("enabled") is False:
            n, l = line_of(lines, '"enabled"')
            emit(rel, n, "sandbox_weaken", l)
        exc = sb.get("excludedCommands") or []
        for c in exc if isinstance(exc, list) else []:
            if isinstance(c, str) and re.search(r"\b(docker|podman|nerdctl|kubectl|sudo)\b", c):
                n, l = line_of(lines, c)
                emit(rel, n, "sandbox_weaken", l)
    for p, v in walk_json(data):
        if p and p[-1] == "allowedDomains" and isinstance(v, list) and any(d in ("*", "*.*") for d in v if isinstance(d, str)):
            n, l = line_of(lines, '"allowedDomains"')
            emit(rel, n, "sandbox_weaken", l)
        if p and p[-1] == "allowUnixSockets" and isinstance(v, list):
            for s in v:
                if isinstance(s, str) and "docker" in s:
                    n, l = line_of(lines, s)
                    emit(rel, n, "sandbox_weaken", l)
    hooks = data.get("hooks")
    if isinstance(hooks, dict):
        for ev in ("SessionStart", "Setup"):
            if ev in hooks:
                n, l = line_of(lines, f'"{ev}"')
                emit(rel, n, "pre_trust", l)


def scan_mcp(rel, lines, data):
    servers = data.get("mcpServers") if isinstance(data, dict) else None
    if not isinstance(servers, dict):
        return
    for name, spec in servers.items():
        if isinstance(spec, dict) and "command" in spec:
            n, l = line_of(lines, f'"{name}"')
            emit(rel, n, "pre_trust", l)


def scan_package_json(rel, lines, data):
    scripts = data.get("scripts") if isinstance(data, dict) else None
    if not isinstance(scripts, dict):
        return
    for k in scripts:
        if k in LIFECYCLE:
            n, l = line_of(lines, f'"{k}"')
            emit(rel, n, "lifecycle_script", l)


def scan_file(full, rel):
    # rel (relative to the repo root) drives classification; output keeps the full path.
    base = os.path.basename(rel)
    stem, ext = os.path.splitext(base)
    if ext == ".pth":
        emit(full, 1, "py_pth", f"{base} (runs at every interpreter start when installed into site-packages)")
    if ext == ".py" and (stem in ALWAYS_SHADOW or (
            stem in STDLIB and not os.path.exists(os.path.join(os.path.dirname(full), "__init__.py")))):
        emit(full, 1, "py_stdlib_shadow", f"{base} shadows stdlib module '{stem}' for scripts run from this directory")
    try:
        if os.path.getsize(full) > MAX_BYTES:
            skip(full, "oversize")
            return
        with open(full, "rb") as f:
            raw = f.read()
    except OSError:
        skip(full, "unreadable")
        return
    if b"\0" in raw[:4096]:
        skip(full, "nul_bytes")
        return
    text = raw.decode("utf-8", errors="ignore")
    lines = text.splitlines()

    if re.search(r"(^|/)(\.git|dot-git)/config$", rel) or base in {".gitconfig", "gitconfig"} or base.endswith(".gitconfig"):
        scan_git_config(full, lines)
    if ext == ".json":
        try:
            data = json.loads(text)
        except ValueError:
            data = None
        if data is not None:
            if re.match(r"^(settings[\w.-]*|managed-settings|hooks)\.json$", base):
                scan_settings(full, lines, data)
            if base in {".mcp.json", "mcp.json", "dot-mcp.json"}:
                scan_mcp(full, lines, data)
            if base == "package.json":
                scan_package_json(full, lines, data)

    is_artifact = bool(ARTIFACT_RE.search(rel))
    prose = re.compile(rf"{PROSE_WRITE}.*{TRUSTED_TARGET}", re.I) if is_artifact else None
    for n, line in enumerate(lines, start=1):
        for cat, rx in LINE_RULES:
            if rx.search(line):
                if cat == "nondefault_index" and first_party_index(line):
                    continue
                emit(full, n, cat, line)
        if prose and prose.search(line):
            emit(full, n, "config_write", line)
        m = ROUTER_RE.search(line)
        if m and url_host(m.group(2)) not in FIRST_PARTY_MODEL:
            emit(full, n, "llm_router", line)


for root, dirs, files in os.walk(repo):
    dirs[:] = sorted(d for d in dirs if d not in EXCLUDE_DIRS)
    for fn in sorted(files):
        if fn in EXCLUDE_FILES:
            continue
        full = os.path.join(root, fn)
        if os.path.islink(full):
            skip(full, "symlink")
            continue
        scan_file(full, os.path.relpath(full, repo))

# A shipped .git/config (tarball, zip, vendored checkout) runs on the agent's own git status.
gc = os.path.join(repo, ".git", "config")
if os.path.islink(gc):
    skip(gc, "symlink")
elif os.path.isfile(gc):
    with open(gc, "r", encoding="utf-8", errors="ignore") as f:
        scan_git_config(gc, f.read().splitlines())
PYEOF
