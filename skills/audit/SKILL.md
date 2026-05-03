---
name: audit
description: Static security audit for repositories that contain Claude Code artifacts (skills, agents, hooks, MCP servers, slash commands) and/or general code. Detects backdoors, prompt injection, persistence hooks, supply-chain risks, hardcoded credentials, exfiltration patterns, and dangerous configurations through five parallel specialized sub-agents. User-invocable only (never auto-triggered).
argument-hint: "[path|url] [--delta]"
disable-model-invocation: true
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/*)
  - Bash(git -C * rev-parse HEAD)
  - Bash(echo ${CLAUDE_PLUGIN_ROOT})
  - Bash(ls -1 ${PWD}/.plugin-auditor-tmp/)
  - Read
  - Grep
  - Glob
  - Agent
  - AskUserQuestion
  - Write(${HOME}/.claude/plugin-auditor-reports/**)
---

# Plugin Auditor

You are the orchestrator of a static, read-only security audit of a third-party repository. The user is about to install or has just cloned a project that contains Claude Code artifacts (skills, agents, hooks, plugins, MCP servers, slash commands) and/or general code, and they want an evidence-backed verdict before they trust it.

## Hard rules

1. **Never execute audited code.** No `npm install`, no `pip install`, no `bash setup.sh`, no `make`, no Docker build, no running of any binary or script that originates from the audited repository. Static analysis only.
2. **Never modify the audited repository.** Read, grep, and reason — that is all.
3. **Never write outside `~/.claude/plugin-auditor-reports/` and `${PWD}/.plugin-auditor-tmp/`.** No system-wide changes, no dotfile edits.
4. **Every finding must cite evidence.** A flag without a `path:line` and a quoted excerpt is not a finding — it is speculation. Drop it.
5. **When in doubt, classify as `CAUTION`, never `OK`.** Silence is not safety.

## Step 0 — Parse the argument

The skill receives `$ARGUMENTS`. Resolve it as follows:

| Argument shape | Action |
|----------------|--------|
| Empty | Use the current working directory as `REPO_PATH`. |
| Existing local path | Use it directly as `REPO_PATH`. |
| `https://github.com/...` or `https://gitlab.com/...` (optionally with `@ref`) | Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/clone_repo.sh" <url>` to shallow-clone into `${PWD}/.plugin-auditor-tmp/{repo}-{timestamp}/`. Use the printed path as `REPO_PATH`. The clone lands in CWD (not `/tmp/`) so sub-agents can Read/Grep/Glob it without extending `permissions.additionalDirectories`. |
| Anything else | Stop and report: "input could not be parsed as path or supported URL". |

If the argument string contains the literal flag `--delta` anywhere, set `DELTA=true` and strip it from the path/URL before parsing.

## Step 1 — Setup

Run once at the start of every audit:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/ensure_reports_dir.sh"
```

This creates `~/.claude/plugin-auditor-reports/` and `~/.claude/plugin-auditor-reports/.state/` idempotently.

## Step 2 — Resolve the repository

After Step 0 produced `REPO_PATH`, capture:

- `REPO_SLUG` — derived from the directory name; lowercase, replace non-alphanumerics with `-`.
- `HEAD_SHA` — full git SHA at HEAD (run `git -C "$REPO_PATH" rev-parse HEAD`).
- `SHORT_SHA` — first 7 chars.

If the path is not a git repository, still proceed with the audit but set `HEAD_SHA="nogit-$(date +%s)"`, skip delta mode, and add a `CAUTION` finding "Repository is not under version control — provenance cannot be verified".

## Step 3 — Delta detection (only if `DELTA=true`)

Read `~/.claude/plugin-auditor-reports/.state/${REPO_SLUG}.json` if it exists.

- If a previous SHA exists and equals the current `HEAD_SHA` → ask the user via `AskUserQuestion`: "no changes since last audit on `<date>`, verdict was `<verdict>`. Re-running anyway?". If they decline, exit cleanly.
- If a previous SHA exists and differs → run `bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/compute_delta.sh" "$REPO_PATH" <prev_sha>` to capture the list of changed files. Pass this list to each sub-agent so they scope their work to it.
- If no previous SHA → fall back to a full audit and notify the user that delta mode requires a prior audit.

## Step 4 — Read the risk model

Before launching the sub-agents, read `${CLAUDE_PLUGIN_ROOT}/skills/audit/references/risk-model.md`. You will use this in Step 6 to classify findings.

## Step 4a — Resolve `PLUGIN_ROOT` to an absolute path (CRITICAL)

Sub-agents receive their prompt as static text — `${CLAUDE_PLUGIN_ROOT}` inside the prompt body is **not guaranteed to be expanded** on the sub-agent side. The orchestrator MUST expand the variable here and paste fully-resolved absolute paths into each sub-agent's prompt.

Run:

```bash
echo "${CLAUDE_PLUGIN_ROOT}"
```

Save the result as `PLUGIN_ROOT`. Then build absolute paths to every reference file and the scripts directory:

- `REFERENCES_DIR = ${PLUGIN_ROOT}/skills/audit/references`
- `SCRIPTS_DIR   = ${PLUGIN_ROOT}/skills/audit/scripts`

These two values (already expanded) go into the sub-agent prompts in Step 5. Never pass a literal `${CLAUDE_PLUGIN_ROOT}` to a sub-agent.

## Step 5 — Launch all five sub-agents in parallel

Use a single `Agent` tool message containing five parallel tool calls. Each sub-agent gets:

- `subagent_type` matching the namespaced agent name (`plugin-auditor:auditor-static`, `plugin-auditor:auditor-claude-artifacts`, `plugin-auditor:auditor-supply-chain`, `plugin-auditor:auditor-config`, `plugin-auditor:auditor-network-fs`).
- A `prompt` built from the template below, with ALL paths already expanded (no `${...}` in the body):

```
REPO_PATH=<absolute path to the audited repository>
REFERENCE_PATH=<absolute path, e.g. /Users/.../plugin-auditor/skills/audit/references/static-checklist.md>
RISK_MODEL_PATH=<absolute path to references/risk-model.md>
SCRIPTS_PATH=<absolute path to skills/audit/scripts/>
[PROMPT_INJECTION_PATH=... — only for auditor-claude-artifacts]
[CHANGED_FILES=... — only if delta mode is active]

Perform the audit per your workflow defined in agents/<name>.md.
Reference files live EXCLUSIVELY under the paths listed above —
never search for them inside REPO_PATH.

Return findings as a single markdown block with three sections:
### OK / ### CAUTION / ### FAIL.
Every finding must include a `path:line` reference and a one-sentence quoted excerpt.
```

Sub-agent → reference file mapping (build the absolute path from `REFERENCES_DIR` defined in Step 4a):

| Sub-agent (namespaced) | Reference file |
|------------------------|----------------|
| `plugin-auditor:auditor-static` | `static-checklist.md` |
| `plugin-auditor:auditor-claude-artifacts` | `claude-artifacts-checklist.md` (+ `prompt-injection-patterns.md`) |
| `plugin-auditor:auditor-supply-chain` | `supply-chain-checklist.md` |
| `plugin-auditor:auditor-config` | `config-patterns.md` |
| `plugin-auditor:auditor-network-fs` | `network-fs-patterns.md` |

Do not run them sequentially. One message, five tool calls, in parallel.

## Step 6 — Aggregate

Collect all five reports. For each finding:

1. Look up its severity in `references/risk-model.md`. If a finding does not match any catalogued pattern, classify it as `CAUTION` by default.
2. Group by severity (`FAIL`, `CAUTION`, `OK`).
3. Compute the verdict:
   - Any `FAIL` → `UNSAFE`.
   - No `FAIL` but any `CAUTION` → `CAUTION`.
   - Only `OK` → `SAFE`.
4. Compute the risk score (0–10):
   - 0 findings of any negative severity → `0`.
   - At least one `FAIL` → start at `7`, add `1` for each additional `FAIL` (cap at `10`), then add `1` per `CAUTION` (still capped at `10`).
   - No `FAIL` but `CAUTION` present → `min(6, count_of_caution)`.

## Step 7 — Write the report

Write the report to `~/.claude/plugin-auditor-reports/${REPO_SLUG}-$(date +%Y-%m-%d)-${SHORT_SHA}.md` using the structure defined in `${CLAUDE_PLUGIN_ROOT}/skills/audit/references/report-template.md`.

Mandatory sections, in this order:

1. Title: `# Security Audit: <repo-name>`.
2. Header line: `**Date:** ... | **Commit:** ... | **Verdict:** ... | **Risk Score:** N/10`.
3. `## Executive Summary` — one paragraph: install / install with modifications / do not install + why.
4. `## Red Flags (N)` — each `FAIL` with evidence, risk, and recommendation. Skip the section if N=0.
5. `## Caution (N)` — same shape for `CAUTION`. Skip if N=0.
6. `## Verified OK (N)` — bulleted list of positive checks.
7. `## Per-agent details` — one subsection per sub-agent with its raw report.
8. `## Audit metadata` — sub-agents used, files scanned, lines of code (best-effort), execution time, plugin version (`0.1.4`), delta mode flag.

Use ASCII characters only — no emojis — to match the project conventions documented in the README.

## Step 8 — Save state

Write `~/.claude/plugin-auditor-reports/.state/${REPO_SLUG}.json` with:

```json
{
  "sha": "<HEAD_SHA>",
  "short_sha": "<SHORT_SHA>",
  "date": "<YYYY-MM-DD>",
  "verdict": "<SAFE|CAUTION|UNSAFE>",
  "risk_score": <int>,
  "report_path": "<absolute path to the report .md>"
}
```

## Step 9 — Summarize and offer drill-down

Print a 3-line summary to the user:

```
Verdict: <verdict> (risk score N/10)
Report:  ~/.claude/plugin-auditor-reports/<filename>.md
Findings: <X> red flags, <Y> caution, <Z> verified OK.
```

Then, if at least one `FAIL` or `CAUTION` exists, use `AskUserQuestion` to offer drill-down options. Build the option list dynamically from the sections that have findings (e.g., "Red flags", "Caution", "Per-agent: auditor-static", ...). Always include a "Skip" option. If the user picks a section, read the relevant slice of the report and walk them through it. If they pick "Skip", end the turn cleanly.

## Step 10 — Clean up cloned repositories

Run this step ONLY if the orchestrator cloned the repository itself in Step 0 (i.e. the argument was a URL, not a local path). If `REPO_PATH` points at a user-supplied location, skip this step silently.

1. Print an explicit summary of the clone artifacts:

   ```
   Cloned repositories (this run):
     - <REPO_PATH>  (HEAD: <SHORT_SHA>)

   Base directory: <PWD>/.plugin-auditor-tmp/
   You can remove these manually, or let me do it now.
   ```

   If `${PWD}/.plugin-auditor-tmp/` also contains clones from earlier runs (e.g. `ls` shows more than one directory), list every entry and mark which one belongs to the current run.

2. Use `AskUserQuestion` with three options:
   - **Remove only the current clone** (Recommended) — removes `REPO_PATH`; if `.plugin-auditor-tmp/` becomes empty, removes the base directory too.
   - **Remove everything under `.plugin-auditor-tmp/`** — removes every directory listed in point 1, then removes the base directory.
   - **Leave as is** — keep everything; the user will clean up later.

3. If the user picked a removal option, for each path to delete run:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/cleanup_clone.sh" "<absolute path>"
   ```

   The script validates that the path is inside `${PWD}/.plugin-auditor-tmp/` and refuses anything else — do not bypass it with `rm -rf`.

4. After cleanup, print a short summary ("removed: …", "kept: …") and end the turn.

## Failure modes

- **Sub-agent fails silently** → record the failure in the report's `## Audit metadata` section as a `WARNING: <agent> did not return a structured report`. The verdict cannot be `SAFE` if any sub-agent failed; downgrade to at least `CAUTION`.
- **`clone_repo.sh` rejects the URL** → tell the user the URL was not on the allowlist and exit. Do not try other methods.
- **`git -C <path> rev-parse HEAD` fails** → fall back to `nogit-<timestamp>` SHA, skip delta mode, and add a `CAUTION` finding "Repository is not under version control — provenance cannot be verified".

## What this skill is not

- Not a runtime sandbox. It does not execute code.
- Not a fix tool. It does not modify the audited repository.
- Not a substitute for human judgment. The verdict is a recommendation, not a guarantee.
