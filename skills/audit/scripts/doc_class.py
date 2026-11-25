"""Tags scan hits that sit in plain documentation with a `doc:` prefix.

Used by the scan_*.sh helpers, never run on its own. A hit in documentation is
context (pattern catalogues, changelogs, READMEs), not code that runs, but it is
still reported so the sub-agent can read it and promote it when the doc tells a
user or agent to run it.

Documentation = markdown-family file that is NOT an instruction file an agent
loads: SKILL.md, CLAUDE.md, CLAUDE.local.md, AGENTS.md, GEMINI.md, agent rule
files (.cursorrules, copilot-instructions.md, ...), anything under skills/,
agents/, commands/, hooks/, output-styles/, .claude/, rule dirs of other agents,
and any markdown whose YAML frontmatter has both name: and description:.
Names and directories match case-insensitively, on the path relative to the
audited repo root (an ancestor dir like ~/.claude/plugins must not count).

Usage: doc_class.py <mode> <repo_root>
Modes (stdin to stdout):
  lines  <path>:<rest>            becomes doc:<path>:<rest> for doc paths
  host   <host>\t<path:line>\t<raw> becomes doc:<host>\t... for doc paths
"""

import os
import re
import sys

DOC_EXT = {".md", ".mdx", ".markdown", ".rst", ".adoc"}
INSTRUCTION_NAMES = {
    "skill.md", "claude.md", "claude.local.md", "agents.md", "agent.md", "gemini.md",
    "copilot-instructions.md", ".cursorrules", ".windsurfrules", ".clinerules",
}
INSTRUCTION_DIRS = {
    "skills", "agents", "commands", "hooks", "output-styles", ".claude",
    ".cursor", ".windsurf", ".clinerules", ".roo", ".kiro", "instructions", "prompts",
}
_cache = {}


def has_artifact_frontmatter(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            head = f.read(4096)
    except OSError:
        return False
    m = re.match(r"\A\ufeff?---\s*\n(.*?)\n---\s*(\n|\Z)", head, re.S)
    if not m:
        return False
    fm = m.group(1)
    return bool(re.search(r"^name\s*:", fm, re.M) and re.search(r"^description\s*:", fm, re.M))


def relative(path, root):
    if root and path.startswith(root + "/"):
        return path[len(root):].lstrip("/")
    return path


def is_doc(path, root):
    if path in _cache:
        return _cache[path]
    rel = relative(path, root).replace("\\", "/").lower()
    base = os.path.basename(rel)
    parts = set(rel.split("/")[:-1])
    doc = (
        os.path.splitext(base)[1] in DOC_EXT
        and base not in INSTRUCTION_NAMES
        and not (parts & INSTRUCTION_DIRS)
        and not has_artifact_frontmatter(path)
    )
    _cache[path] = doc
    return doc


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "lines"
    root = sys.argv[2].rstrip("/") if len(sys.argv) > 2 else ""
    for line in sys.stdin:
        line = line.rstrip("\n")
        if not line:
            continue
        if mode == "host":
            host, loc, *rest = line.split("\t")
            path = loc.rsplit(":", 1)[0]
            if is_doc(path, root) and not host.startswith("local:"):
                host = "doc:" + host
            print("\t".join([host, loc, *rest]))
        else:
            path = line.split(":", 1)[0]
            print(("doc:" + line) if is_doc(path, root) else line)


main()
