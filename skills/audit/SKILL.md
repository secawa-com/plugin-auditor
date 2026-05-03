---
name: audit
description: Static security audit for repositories that contain Claude Code artifacts (skills, agents, hooks, MCP servers, slash commands) and/or general code. Detects backdoors, prompt injection, persistence hooks, supply-chain risks, hardcoded credentials, exfiltration patterns, and dangerous configurations through five parallel specialized sub-agents. User-invocable only (never auto-triggered).
argument-hint: "[path|url] [--delta]"
disable-model-invocation: true
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/*)
  - Bash(git -C * rev-parse HEAD)
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
3. **Never write outside `~/.claude/plugin-auditor-reports/` and `/tmp/plugin-auditor/`.** No system-wide changes, no dotfile edits.
4. **Every finding must cite evidence.** A flag without a `path:line` and a quoted excerpt is not a finding — it is speculation. Drop it.
5. **When in doubt, classify as `CAUTION`, never `OK`.** Silence is not safety.

## Step 0 — Parse the argument

The skill receives `$ARGUMENTS`. Resolve it as follows:

| Argument shape | Action |
|----------------|--------|
| Empty | Use the current working directory as `REPO_PATH`. |
| Existing local path | Use it directly as `REPO_PATH`. |
| `https://github.com/...` or `https://gitlab.com/...` (optionally with `@ref`) | Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/clone_repo.sh" <url>` to shallow-clone into `/tmp/plugin-auditor/{repo}-{sha}/`. Use the printed path as `REPO_PATH`. |
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

## Step 5 — Launch all five sub-agents in parallel

Use a single `Agent` tool message containing five parallel tool calls. Each sub-agent gets:

- `subagent_type` matching the namespaced agent name (`plugin-auditor:auditor-static`, `plugin-auditor:auditor-claude-artifacts`, `plugin-auditor:auditor-supply-chain`, `plugin-auditor:auditor-config`, `plugin-auditor:auditor-network-fs`).
- A `prompt` that includes:
  - The absolute `REPO_PATH`.
  - The absolute path to its dedicated reference file under `${CLAUDE_PLUGIN_ROOT}/skills/audit/references/`.
  - The absolute path to the helper scripts directory `${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/`.
  - If delta mode is active, the list of changed files (otherwise tell it to scan the whole repo).
  - A reminder to return findings as a single markdown block with three sections: `### OK`, `### CAUTION`, `### FAIL`. Each finding must have a `path:line` reference and a one-sentence quoted excerpt.

Sub-agent → reference file mapping:

| Sub-agent (namespaced) | Reference file |
|------------------------|----------------|
| `plugin-auditor:auditor-static` | `references/static-checklist.md` |
| `plugin-auditor:auditor-claude-artifacts` | `references/claude-artifacts-checklist.md` |
| `plugin-auditor:auditor-supply-chain` | `references/supply-chain-checklist.md` |
| `plugin-auditor:auditor-config` | `references/config-patterns.md` |
| `plugin-auditor:auditor-network-fs` | `references/network-fs-patterns.md` |

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
8. `## Audit metadata` — sub-agents used, files scanned, lines of code (best-effort), execution time, plugin version (`0.1.3`), delta mode flag.

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

## Failure modes

- **Sub-agent fails silently** → record the failure in the report's `## Audit metadata` section as a `WARNING: <agent> did not return a structured report`. The verdict cannot be `SAFE` if any sub-agent failed; downgrade to at least `CAUTION`.
- **`clone_repo.sh` rejects the URL** → tell the user the URL was not on the allowlist and exit. Do not try other methods.
- **`git -C <path> rev-parse HEAD` fails** → fall back to `nogit-<timestamp>` SHA, skip delta mode, and add a `CAUTION` finding "Repository is not under version control — provenance cannot be verified".

## What this skill is not

- Not a runtime sandbox. It does not execute code.
- Not a fix tool. It does not modify the audited repository.
- Not a substitute for human judgment. The verdict is a recommendation, not a guarantee.
