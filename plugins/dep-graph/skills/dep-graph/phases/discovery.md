# Phase 1: Repository Discovery Agent

Scan all git repositories in a parent directory and extract metadata, dependency lists, API surfaces, and service identifiers for each.

## Inputs

- `{{PARENT_DIR}}` — absolute path to the parent directory containing repos
- `{{OUTPUT_DIR}}` — where to write output

## Output

- `{{OUTPUT_DIR}}/repo-inventory.json`

## Write Boundary

Only write files inside `{{OUTPUT_DIR}}/`. Do not modify any repository or directory outside of this path.

## Constraints

- Do not use the Agent tool
- Do not prompt the user
- Do not deep-read source files — structural scanning only
- Complete in under 120 seconds

---

## Step 1 — Find All Git Repos

Use Bash to locate every git repository under the parent directory:

```bash
fd --type d --max-depth 2 '.git' "{{PARENT_DIR}}" --hidden
```

Derive repo root paths by taking the parent of each `.git` directory. Exclude any path that contains `{{OUTPUT_DIR}}`.

If `fd` is unavailable, fall back to:

```bash
find "{{PARENT_DIR}}" -maxdepth 2 -type d -name '.git'
```

---

## Step 2 — Extract Metadata Per Repo

For each discovered repo, extract the following. If an individual repo scan fails, log the error and continue with the remaining repos.

### a. Identity

Determine the directory basename, the org/repo slug, and any published package names.

**Slug** — extract the `org/repo` slug from the git remote:

```bash
cd "{repo_path}" && git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+/[^/]+?)(\\.git)?$|\\1|'
```

If the remote cannot be parsed or doesn't exist, set `slug` to `null`.

**Package names:**

- **npm**: `jq -r '.name // empty' package.json`
- **Go**: first `module` line in `go.mod`
- **Python**: extract `name` from the `[project]` section of `pyproject.toml`, or from `setup.py` / `setup.cfg`
- **Rust**: extract the `[package] name` from `Cargo.toml`

### b. Languages

Count source files by extension using `fd` scoped to the repo. Map extensions to language names (e.g., `.go` → go, `.ts` → typescript, `.py` → python, `.rs` → rust, `.java` → java, `.rb` → ruby, `.php` → php, `.js` → javascript). Pick the primary language by highest file count.

### c. Frameworks

Check for framework markers in dependency manifests:

- **Go** (`go.mod` imports): gin, echo, fiber, chi
- **JS/TS** (`package.json` deps + devDeps): react, next, express, fastify, nestjs
- **Python** (`requirements.txt`, `pyproject.toml`): django, flask, fastapi
- **Rust** (`Cargo.toml` deps): actix, axum, rocket
- **Java** (`pom.xml`): spring

### d. Dependency Manifests

Glob for the following files within the repo and record their paths relative to the repo root:

- `package.json`
- `go.mod`
- `requirements.txt`
- `pyproject.toml`
- `Cargo.toml`
- `pom.xml`
- `build.gradle`
- `Gemfile`
- `composer.json`

### e. Dependencies List

For each manifest found, extract dependency names. If a manifest parser fails, use an empty array for that manifest's dependencies.

- **package.json**: `jq -r '(.dependencies // {} | keys[]) , (.devDependencies // {} | keys[])'`
- **go.mod**: grep `require` blocks, extract module paths (first field of each line inside the block)
- **requirements.txt**: extract package names, stripping version specifiers (`==`, `>=`, `~=`, `!=`, `<=`, `>`, `<`, etc.)
- **pyproject.toml**: extract from `[project.dependencies]` using grep or `yq`
- **Cargo.toml**: extract `[dependencies]` keys
- **pom.xml**: extract `groupId:artifactId` from `<dependency>` blocks

### f. API Surface

Grep for route definitions — scan only, do not deep-read source:

- **Express**: `app.get(`, `app.post(`, `app.put(`, `app.delete(`, `router.get(`, `router.post(`, etc.
- **Gin**: `r.GET(`, `r.POST(`, `r.PUT(`, `r.DELETE(`
- **Flask**: `@app.route(`
- **FastAPI**: `@router.get(`, `@router.post(`, `@app.get(`, `@app.post(`
- **Django**: `urlpatterns`
- **Spring**: `@RequestMapping`, `@GetMapping`, `@PostMapping`

Also extract `EXPOSE` directives from any Dockerfiles found in the repo.

### g. Service Names

Extract service name variations from:

- **Docker Compose**: `yq '.services | keys[]' docker-compose*.yml`
- **Kubernetes manifests**: deployment names from k8s YAML files
- **Directory name**: the repo directory basename itself
- **Variations**: generate hyphenated (`my-service`), underscored (`my_service`), and uppercase (`MY_SERVICE`) forms

### h. IaC Files

Glob for infrastructure-as-code files within the repo:

- `docker-compose*.yml`
- `docker-compose*.yaml`
- `**/k8s/**`
- `**/kubernetes/**`
- `**/*.tf`
- `**/helm/**`

Record paths relative to the repo root.

### i. LOC Estimate

Estimate total lines of code:

```bash
fd -e go -e js -e ts -e py -e rs -e java -e rb -e php --type f . "{repo_path}" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}'
```

### j. Repository Description

Extract a concise description (2–4 sentences) of what the repo does and how it fits into the broader system. Check these sources in order:

**Source 1 — Manifest descriptions:**
- `package.json` → `description` field: `jq -r '.description // empty' package.json`
- `pyproject.toml` → `[project].description` field
- `Cargo.toml` → `[package].description` field

**Source 2 — README:**
- Read the first 80 lines of `README.md` or `README.rst`
- Extract the introductory paragraph(s) — the text between the first heading and either the second heading or line 80, skipping badges, build status images, and blank lines
- Use up to 3 sentences or 500 characters, whichever comes first

**Source 3 — GitHub API:**
- If `gh` is available: `gh repo view --json description -q '.description' 2>/dev/null`

**Source 4 — Code context inference (fallback):**
If none of the above produce a meaningful description (empty, null, or generic like "TODO" / "A project"), infer the description from the code itself:

1. List the top-level directory structure: `ls -1 "{repo_path}" | head -20`
2. Read the main entry point (first match): `main.go`, `cmd/main.go`, `src/main.ts`, `src/index.ts`, `app.py`, `main.py`, `src/main.rs`, `src/App.tsx`, `src/main/java/**/Application.java`
3. Read the first 50 lines of the entry point to understand what the application does
4. Check for a `Dockerfile` — read the `CMD` or `ENTRYPOINT` line to understand how it runs
5. Check `docker-compose.yml` service names and environment variables for context

From these signals, write a 2–4 sentence description covering:
- **What it is** (API server, CLI tool, library, worker, frontend app, etc.)
- **What it does** (its primary responsibility — "handles user authentication", "processes payment webhooks", etc.)
- **How it relates** to other services if apparent from env vars, API calls, or service names

Write the description in plain language, not marketing copy. Be specific about what the code actually does rather than restating the repo name.

**Quality check:** If the description from sources 1–3 is too short (under 20 characters) or too generic (matches patterns like "A .* project", "TODO", "WIP", "Description", "My project"), fall through to the code context inference fallback.

### k. Vulnerability Data

Check if vuln-scan results exist for this repo. Look for `validated-findings.json` in these locations (check in order, use the first match):

- `{CWD}/vuln-scan-results/{dir_name}/validated-findings.json`
- `{CWD}/vuln-scan-results/{dir_name_lowercase}/validated-findings.json`
- `{repo_path}/vuln-scan-results/validated-findings.json` (legacy location)

If found, read the file and extract:

- `summary.total_findings` — total count
- `summary.by_severity` — counts per severity level

If not found or invalid JSON, set vulnerability data to null.

---

## Step 3 — Assemble Output

Write `{{OUTPUT_DIR}}/repo-inventory.json` with this schema:

```json
{
  "parent_directory": "/absolute/path",
  "scan_date": "ISO8601",
  "repos": [
    {
      "dir_name": "my-service",
      "slug": "myorg/my-service",
      "package_names": ["@myorg/my-service", "github.com/myorg/my-service"],
      "path": "/absolute/path/my-service",
      "primary_language": "go",
      "languages": ["go", "javascript"],
      "frameworks": ["gin", "react"],
      "package_managers": ["go", "npm"],
      "dependency_manifests": ["go.mod", "frontend/package.json"],
      "dependencies": ["github.com/gin-gonic/gin", "github.com/myorg/shared-lib"],
      "api_endpoints": ["/api/v1/users"],
      "exposed_ports": [8080],
      "service_names": ["my-service", "myservice", "MY_SERVICE"],
      "iac_files": ["docker-compose.yml"],
      "description": "API gateway service that handles authentication, rate limiting, and request routing to downstream microservices. Sits in front of the user-service and order-service, proxying authenticated requests based on JWT claims.",
      "loc_estimate": 15000,
      "manifest_count": 2,
      "vulnerability_counts": {
        "total": 7,
        "critical": 1,
        "high": 2,
        "medium": 3,
        "low": 1
      }
    }
  ]
}
```

Fields:

| Field | Type | Description |
|---|---|---|
| `dir_name` | string | Repository directory basename |
| `slug` | string\|null | Org/repo slug from git remote origin (e.g., `myorg/my-service`). Null if remote unavailable. |
| `package_names` | string[] | Published package/module names from manifests |
| `path` | string | Absolute path to the repo root |
| `primary_language` | string | Language with the highest source file count |
| `languages` | string[] | All detected languages |
| `frameworks` | string[] | Detected frameworks |
| `package_managers` | string[] | Package manager types present (npm, go, pip, cargo, maven, gradle, bundler, composer) |
| `dependency_manifests` | string[] | Paths to manifest files, relative to repo root |
| `dependencies` | string[] | Deduplicated list of all dependency names across manifests |
| `api_endpoints` | string[] | Discovered route paths |
| `exposed_ports` | int[] | Ports from Dockerfile EXPOSE directives |
| `service_names` | string[] | All name variations for cross-referencing |
| `iac_files` | string[] | Infrastructure-as-code file paths, relative to repo root |
| `description` | string\|null | 2–4 sentence description of what the repo does, from manifest, README, or inferred from code context |
| `loc_estimate` | int | Estimated total lines of code |
| `manifest_count` | int | Number of dependency manifest files found |
| `vulnerability_counts` | object\|null | Severity breakdown from vuln-scan results (`total`, `critical`, `high`, `medium`, `low`). Set to `null` if no vuln-scan results were found for this repo. |

---

## Error Handling

- If an individual repo scan fails, log the error to stderr and continue scanning the remaining repos.
- If `fd` is unavailable, fall back to `find` and `grep`.
- If `jq` is unavailable, fall back to `grep` and `sed` for JSON extraction.
- If a manifest parser fails for a specific file, record an empty array for that manifest's dependencies and continue.
- Never let a single repo failure prevent the inventory file from being written.

---

## Success Condition

`{{OUTPUT_DIR}}/repo-inventory.json` exists and is valid JSON containing at least one repo entry.
