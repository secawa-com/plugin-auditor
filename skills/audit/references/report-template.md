# Report Template

Template for the markdown report written by the orchestrator to `~/.claude/plugin-auditor-reports/{repo-slug}-{YYYY-MM-DD}-{shortsha}.md`.

Use ASCII characters only (no emojis) to match the project conventions documented in the README.

---

```markdown
# Security Audit: <repo-name>

**Date:** <YYYY-MM-DD> | **Commit:** <short-sha> | **Verdict:** <SAFE|CAUTION|UNSAFE> | **Risk Score:** <N>/10

## Executive Summary

<One paragraph. Open with the verdict in plain English. State the single most important reason
for that verdict. End with a clear recommendation: "Install with normal caution.",
"Install only after the listed caution items are reviewed.", or
"Do not install in the current state.">

## Red Flags (<count>)

### 1. <Short title>
- **Where:** `<path>:<line>`
- **Evidence:** `> <single quoted line from the file>`
- **Risk:** <one or two sentences explaining why this is dangerous>
- **Recommendation:** <what the user should do — reject, request a fix, mitigate locally>

### 2. <Short title>
- **Where:** ...
- ...

(Skip this whole section when the count is 0.)

## Caution (<count>)

### 1. <Short title>
- **Where:** `<path>:<line>`
- **Evidence:** `> <quoted line>`
- **Risk:** <why it's worth attention even though it's not an automatic fail>
- **Recommendation:** <what to verify or change>

(Skip this whole section when the count is 0.)

## Verified OK (<count>)

- <Positive check 1, copied from the relevant checklist's OK section>
- <Positive check 2>
- ...

## Per-agent details

### auditor-static

<verbatim FAIL / CAUTION / OK report from the sub-agent>

### auditor-claude-artifacts

<verbatim report>

### auditor-supply-chain

<verbatim report>

### auditor-config

<verbatim report>

### auditor-network-fs

<verbatim report>

## Audit metadata

- **plugin-auditor version:** 0.1.3
- **Repository path:** `<absolute path>`
- **Repository origin:** `<git remote URL or "local checkout">`
- **HEAD SHA:** `<full SHA>`
- **Delta mode:** `<true|false>` (if true, include the previous SHA and the count of changed files)
- **Sub-agents:** auditor-static, auditor-claude-artifacts, auditor-supply-chain, auditor-config, auditor-network-fs
- **Files scanned:** <count>
- **Lines of code (approx):** <count>
- **Audit started:** <ISO timestamp>
- **Audit finished:** <ISO timestamp>
- **Warnings:** <empty list, or one line per sub-agent that did not return a structured report>
```

---

## Style guidance

- Keep section headings exactly as shown — downstream tooling may grep for them.
- One finding per numbered subsection. Do not combine multiple lines of evidence in one block.
- Quote at most three lines of evidence per finding. If more is needed, link to the file path.
- The "Verified OK" list is not optional. A clean repo still has a long list of positive checks; show them so the user understands what was actually vetted.
- Always include the metadata block, even on `SAFE` verdicts.
