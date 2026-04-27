# Supply-Chain Checklist

Reference for the `auditor-supply-chain` sub-agent. Supply-chain risk is the most common path to a compromise in modern dev tooling, so even seemingly innocent dependency declarations need scrutiny.

## Scope

Files to scan:

- `package.json`, `package-lock.json`, `npm-shrinkwrap.json`, `yarn.lock`, `pnpm-lock.yaml` — Node.
- `requirements*.txt`, `pyproject.toml`, `poetry.lock`, `uv.lock`, `Pipfile`, `Pipfile.lock` — Python.
- `Cargo.toml`, `Cargo.lock` — Rust.
- `go.mod`, `go.sum` — Go.
- `Gemfile`, `Gemfile.lock` — Ruby.
- `composer.json`, `composer.lock` — PHP.
- `.gitmodules` — git submodules.
- `.mcp.json` — MCP server declarations (overlap with claude-artifacts; here the focus is on the source of the package, not the prompt content).

## What to look for

### 1. Lifecycle scripts in `package.json`

Read the `scripts` block. Flag the presence of any of these as `CAUTION`:

- `preinstall`
- `postinstall`
- `preuninstall`, `postuninstall`
- `prepublish`, `postpublish`
- `prepare`

If the script body contains `curl`, `wget`, a remote URL fetch, or invocation of a binary not present in the repo source — escalate to `FAIL`.

### 2. Typosquatting heuristics

For each dependency in `package.json`, `requirements.txt`, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc., compute a Levenshtein distance against a baseline list of popular packages:

- Node baseline: `react`, `lodash`, `express`, `axios`, `chalk`, `commander`, `dotenv`, `moment`, `jest`, `mocha`, `webpack`, `vite`, `next`, `eslint`, `prettier`, `typescript`.
- Python baseline: `requests`, `urllib3`, `flask`, `django`, `pandas`, `numpy`, `pytest`, `setuptools`, `pip`, `wheel`, `boto3`, `cryptography`, `pyyaml`.
- Rust baseline: `serde`, `tokio`, `clap`, `reqwest`, `hyper`, `anyhow`.

Distance == 1 from a baseline name is `CAUTION`. Distance == 1 from a baseline name with a leading or trailing digit / underscore (e.g., `requests1`, `_requests`) is `FAIL`.

Maintain the baseline as inline awareness; do not depend on an external typosquat database.

### 3. Lockfile presence and integrity

| Manifest | Required lockfile | Severity if missing |
|----------|-------------------|---------------------|
| `package.json` | `package-lock.json` or `pnpm-lock.yaml` or `yarn.lock` or `npm-shrinkwrap.json` | `CAUTION` |
| `pyproject.toml` (Poetry) | `poetry.lock` | `CAUTION` |
| `pyproject.toml` (uv) | `uv.lock` | `CAUTION` |
| `Pipfile` | `Pipfile.lock` | `CAUTION` |
| `Cargo.toml` (binary crate) | `Cargo.lock` | `CAUTION` |
| `Gemfile` | `Gemfile.lock` | `CAUTION` |
| `composer.json` | `composer.lock` | `CAUTION` |

If the lockfile exists but README/CI installs without `--frozen-lockfile` / `--locked` / `npm ci` / equivalent, surface a `CAUTION` "lockfile present but install command does not enforce it".

### 4. Git dependencies

Grep manifests for:

- `git+https://github.com/`, `git+ssh://`, `github:`
- `git = "https://..."` (Cargo)
- `dependencies` referencing `https://` URLs

For each match:

- Pinned to a SHA → `OK`.
- Pinned to a tag → `CAUTION`.
- Pinned to a branch (`main`, `master`, `develop`) or unpinned → `FAIL`.
- Repository owner is a personal account (not the official org of the package) → escalate one level (`CAUTION` → `FAIL`).

### 5. Submodules

Read `.gitmodules` if it exists. For each submodule:

- URL is on the official upstream domain → `OK`.
- URL is on a fork → `CAUTION`.
- Submodule has no specific commit pinned (would float) → `FAIL`.

### 6. MCP servers

Cross-reference with the claude-artifacts checklist — in this sub-agent the focus is the package source:

- `command: "npx"` with a package name → `CAUTION`.
- `command: "npx"` with a non-pinned version (`@latest`, `@next`, no `@`) → `FAIL`.
- `command: "uvx"` (Python equivalent) with no pinned version → `FAIL`.
- `command` pointing at an HTTP URL or binary path outside the repo → `FAIL`.

### 7. Optional / transient dependencies

Read `optionalDependencies`, `peerDependencies`, `devDependencies`:

- A `devDependency` that ships into runtime via re-export → flag the file that re-exports it as `CAUTION`.
- An `optionalDependency` that is known to run lifecycle scripts → `CAUTION`.

### 8. Registry overrides

Check for `.npmrc`, `.yarnrc`, `pip.conf`, `.cargo/config.toml`:

- A registry override pointing at a private/internal URL is `CAUTION` (provenance unclear without org context).
- A registry override pointing at a publicly known mirror with no integrity check is `CAUTION`.
- A registry override that disables integrity checks (`strict-ssl=false`, `package-lock=false`) is `FAIL`.

### 9. Vendored binaries marketed as code

If `node_modules/`, `vendor/`, or `dist/` is committed to the repo and the build step recompiles them — `CAUTION` (auditing the source is harder when binaries are tracked).

If the `bin` field of `package.json` points at a checked-in binary not built from the source in this repo — `FAIL`.

## Output format

```markdown
### FAIL
- `<path>:<line>` — <description>
  > <quoted excerpt>

### CAUTION
- `<path>:<line>` — <description>
  > <quoted excerpt>

### OK
- No lifecycle scripts in package.json (preinstall, postinstall, etc.)
- All dependencies passed typosquatting heuristic
- Lockfile present and install command enforces it
- All git dependencies pinned to specific SHAs
- All git submodules pinned to specific commits
- MCP servers pinned to specific versions (or no MCP servers declared)
- No registry overrides that weaken integrity checks
- No vendored binaries committed to the repo
```
