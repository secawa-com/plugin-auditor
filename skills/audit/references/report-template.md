# Report Template

Template for the markdown report written by the orchestrator to `~/.claude/plugin-auditor-reports/{repo-slug}-{YYYY-MM-DD}-{shortsha}.md`.

Use ASCII characters only (no emojis) to match the project conventions documented in the README.

---

```markdown
# Security Audit: <repo-name>

**Date:** <YYYY-MM-DD> | **Commit:** <short-sha> | **Verdict:** <NO FINDINGS (static)|CAUTION|UNSAFE> | **Risk Score:** <N>/10

## Executive Summary

<One paragraph. Open with the verdict in plain English. State the single most important reason
for that verdict. End with a clear recommendation: "Install with normal caution.",
"Install only after the listed caution items are reviewed.", or
"Do not install in the current state.">

> This verdict applies to exactly the commit below. Install this SHA; running
> `/plugin update` to a newer state invalidates the audit — re-run it (for
> example with `--delta`) before trusting the update.

## Red Flags (<count>)

Each finding carries a provenance tag: `[mechanical]` for a deterministic detector (scan helper, regex, entropy) or `[model-judgment]` for a model-driven pass (the semantic-intent pass or the injection guard). The tag lets the reader weight the evidence: a mechanical finding is reproducible; a model-judgment finding is strong but not a guarantee.

### 1. <Short title> `[mechanical|model-judgment]`
- **Where:** `<path>:<line>`
- **Evidence:** `> <single quoted line from the file>`
- **Risk:** <one or two sentences explaining why this is dangerous>
- **Recommendation:** <what the user should do — reject, request a fix, mitigate locally>

### 2. <Short title> `[mechanical|model-judgment]`
- **Where:** ...
- ...

(Skip this whole section when the count is 0.)

## Caution (<count>)

### 1. <Short title> `[mechanical|model-judgment]`
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

### auditor-injection-guard

<the guard's JSON findings, rendered as a short list; or "no suspected injection" when empty>

## Audit metadata

- **plugin-auditor version:** 0.3.0
- **Repository path:** `<absolute path>`
- **Repository origin:** `<git remote URL or "local checkout">`
- **HEAD SHA:** `<full SHA>`
- **Delta mode:** `<true|false>` (if true, include the previous SHA and the count of changed files)
- **Sub-agents:** auditor-static, auditor-claude-artifacts, auditor-supply-chain, auditor-config, auditor-network-fs, auditor-injection-guard
- **Semantic-pass models:** auditor-claude-artifacts (opus), auditor-injection-guard (haiku)
- **Guard/auditor agreement:** `<in agreement | disagreement on N file(s)>`
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
- Always include the metadata block, even on `NO FINDINGS (static)` verdicts.
