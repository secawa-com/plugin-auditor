# safe-fixture

Minimal known-good fixture for `plugin-auditor` regression tests.

The plugin should produce a `NO FINDINGS (static)` verdict on this directory:

- One inert skill, no hooks, no MCP servers.
- No dependency manifests, no CI/CD workflows, no Dockerfile.
- No network calls, no filesystem accesses outside the project.
- No secrets, no obfuscation, no binaries.
