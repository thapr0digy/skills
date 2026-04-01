# Phase 2: Dependency Analysis Agent

Take the repo inventory from Phase 1 and resolve cross-repo dependency edges across four types: **package imports**, **API calls**, **shared libraries**, and **Docker/infra references**.

## Inputs

- `{{REPO_INVENTORY}}` — inline JSON content of `repo-inventory.json`
- `{{OUTPUT_DIR}}` — where to write output
- `{{PARENT_DIR}}` — parent directory path (for grep operations)

## Output

`{{OUTPUT_DIR}}/dependency-graph.json`

---

## Step 1 — Build Lookup Maps

Parse `{{REPO_INVENTORY}}` and construct three in-memory maps:

1. **`package_name_to_repo`**: For every repo in the inventory, iterate its `package_names` array. Map each package name to the repo's `dir_name` (the repo ID).

2. **`service_name_to_repo`**: For every repo in the inventory, iterate its `service_names` array. Map each service name to the repo's `dir_name`.

3. **`all_dependencies`**: For every repo in the inventory, iterate its `dependencies` array. Build a map of dependency name to the list of repo `dir_name` values that import it.

These maps drive all subsequent detection steps.

---

## Step 2 — Package Import Detection (type: "package")

For each repo A, iterate its `dependencies` list. For each dependency name, check against `package_name_to_repo` using these matching strategies:

- **Exact match**: The dependency string equals a `package_name` entry verbatim.
- **Go prefix match**: The dependency string starts with a repo's Go module path (e.g., `github.com/org/repo-b/pkg/util` starts with `github.com/org/repo-b`).
- **Python normalization**: Compare with hyphens replaced by underscores and vice versa, all lowercased (e.g., `my-lib` matches `my_lib`).
- **npm scoped match**: `@scope/name` exact match against a `package_name` entry.

For each match where repo A != repo B, create an edge:

```json
{
  "source": "repo-a",
  "target": "repo-b",
  "type": "package",
  "weight": 5,
  "details": "repo-a imports 5 packages from repo-b via go.mod",
  "confidence": "confirmed",
  "metadata": {
    "packages": ["github.com/org/repo-b/pkg/util", "github.com/org/repo-b/internal/auth"],
    "manifest": "go.mod"
  }
}
```

Adjust the `details` string to reflect the actual manifest type (go.mod, package.json, requirements.txt, etc.) based on the repo's language context.

The `metadata.packages` array contains the specific dependency names that matched. The `metadata.manifest` string indicates which manifest file type they were found in.

When multiple dependencies from repo A resolve to the same repo B with the same edge type, merge them into a single edge. Set `weight` to the count of individual dependencies. Concatenate the individual dependency names in `details` (up to 10, then summarize as '...and N more'). Merge `metadata.packages` arrays.

---

## Step 3 — API Call Detection (type: "api")

For each repo A, use Grep to search source files for HTTP client patterns that reference other repos' service names. Build a combined regex from all known service identifiers in `service_name_to_repo`, excluding repo A's own service names.

### Grep patterns by language

**JS/TS** (`*.js`, `*.ts`, `*.jsx`, `*.tsx`):
- `(fetch|axios|got)\s*\(.*{identifier}`
- Environment variables: `{IDENTIFIER}_(URL|HOST|ENDPOINT|BASE)`

**Go** (`*.go`):
- `http\.(Get|Post|NewRequest).*{identifier}`
- `os\.Getenv.*{IDENTIFIER}`

**Python** (`*.py`):
- `requests\.(get|post).*{identifier}`
- `os\.environ.*{IDENTIFIER}`

### Exclusions

Skip test files in all searches:
- `*_test.*`
- `*.test.*`
- `test_*`
- `tests/`
- `__tests__/`

### Edge metadata

For each API edge, build a `metadata` object:

```json
{
  "endpoints": ["/api/v1/users", "/health"],
  "env_vars": ["USER_SERVICE_URL"],
  "files": ["src/client.go:42", "src/health.go:18"]
}
```

- `metadata.endpoints`: Extract URL paths from the matched line. Use a regex to pull path segments (e.g., `/api/...`, `/v1/...`). If no clear path is found, record the raw matched substring.
- `metadata.env_vars`: Collect the environment variable names that matched (e.g., `USER_SERVICE_URL`).
- `metadata.files`: Record `file:line` for each match site (relative to repo root).

### Confidence assignment

- `confidence: "confirmed"` — match found inside a URL string literal or in an env var with a `URL`, `HOST`, or `ENDPOINT` suffix.
- `confidence: "likely"` — match found in any other context.

### Deduplication

If the same source, target, and type combination already exists, do not create a duplicate edge. Concatenate the `details` strings (semicolon-separated) into the existing edge. Set `weight` to the count of distinct API call sites found across all matches. Merge `metadata` arrays (endpoints, env_vars, files), deduplicating entries.

---

## Step 4 — Shared Library Detection (type: "shared")

From `all_dependencies`, identify external dependencies — those whose name does NOT appear in `package_name_to_repo` — that are imported by **3 or more** repos.

For each such high-fan-in dependency, sorted by consumer count descending, limited to the **top 15**:

### Create a virtual node

```json
{
  "id": "ext:{dep-name}",
  "label": "{dep-name} (external)",
  "primary_language": null,
  "languages": [],
  "frameworks": [],
  "manifest_count": 0,
  "loc_estimate": 0,
  "is_external": true
}
```

### Create edges

For each repo that consumes this dependency, create an edge:

```json
{
  "source": "{repo-dir-name}",
  "target": "ext:{dep-name}",
  "type": "shared",
  "weight": 1,
  "details": "{repo-dir-name} depends on {dep-name}",
  "confidence": "confirmed"
}
```

Each shared edge has `weight: 1` (one consumer per edge). The fan-in of the virtual node is visible from the number of edges pointing to it.

---

## Step 5 — Docker/Infra Reference Detection (type: "infra")

For each repo that has entries in its `iac_files` array from the inventory:

### docker-compose

Parse docker-compose files to extract service dependencies:

```bash
yq -r '.services | to_entries[] | .key + "|" + ((.value.depends_on // []) | join(","))' docker-compose*.yml
```

Match extracted service names and `depends_on` targets against `service_name_to_repo`. For each match where source repo != target repo, create an `"infra"` edge with `confidence: "confirmed"`.

### Kubernetes

Grep Kubernetes manifest directories for service DNS references:

```bash
rg -o '[a-z][-a-z0-9]*\.(svc|svc\.cluster\.local)' {k8s_dirs}
```

Extract the service name prefix (before `.svc`) and match against `service_name_to_repo`. Create `"infra"` edges for cross-repo matches.

### Terraform

Grep `.tf` files for local module source references:

```bash
rg 'source\s*=\s*"\.\./([^"]+)"' *.tf
```

Extract the sibling directory name and match against repo `dir_name` values. Create `"infra"` edges for matches.

For all infra edge types, set `weight` to the count of distinct references found. When multiple references from repo A resolve to the same repo B, merge into a single `"infra"` edge and increment `weight`.

### Infra edge metadata

```json
{
  "services": ["user-db", "redis"],
  "files": ["docker-compose.yml:12", "k8s/deployment.yaml:34"],
  "ref_type": "docker-compose"
}
```

- `metadata.services`: The service names or resource identifiers that matched.
- `metadata.files`: Source file and line for each reference (relative to repo root).
- `metadata.ref_type`: One of `"docker-compose"`, `"kubernetes"`, or `"terraform"`.

---

## Step 5.5 — Cycle Detection

Detect circular dependencies in the graph using depth-first search (DFS). Only consider `package` and `infra` edge types for cycle detection — `api` and `shared` edges are excluded since API calls and shared external deps don't create true build/deployment cycles.

**Algorithm:**
1. Build a directed adjacency list from all `package` and `infra` edges.
2. Run DFS from each unvisited node, tracking the current path.
3. When a back-edge is found (current node points to a node already in the current path), record the cycle as the path from that node back to itself.
4. Deduplicate cycles: two cycles are the same if they contain the same set of nodes regardless of starting point.

**Output:**
For each edge that participates in a cycle, add `"in_cycle": true` to the edge object.

Add a `cycles` array to the metadata:
```json
"cycles": [
  {
    "nodes": ["repo-a", "repo-b", "repo-c"],
    "edges": [
      {"source": "repo-a", "target": "repo-b", "type": "package"},
      {"source": "repo-b", "target": "repo-c", "type": "package"},
      {"source": "repo-c", "target": "repo-a", "type": "infra"}
    ],
    "length": 3
  }
]
```

If no cycles are found, set `"cycles": []`.

---

## Step 6 — Assemble dependency-graph.json

Combine all collected nodes and edges into the final output.

### Nodes

Map each repo from the inventory to a node:

```json
{
  "id": "{dir_name}",
  "label": "{dir_name}",
  "slug": "{slug}",
  "path": "{path}",
  "primary_language": "{primary_language}",
  "languages": ["..."],
  "frameworks": ["..."],
  "manifest_count": 0,
  "loc_estimate": 0,
  "is_external": false
}
```

Append any virtual external nodes created in Step 4.

### Edges

Collect all edges from Steps 2-5.5. Deduplicate: if two edges share the same `source`, `target`, and `type`, merge them into one by concatenating `details` (semicolon-separated), summing `weight` values, merging `metadata` arrays (dedup entries), and preserving `in_cycle: true` if either edge has it. Keep the highest confidence level (`"confirmed"` wins over `"likely"`). Edges not participating in any cycle have `"in_cycle": false`.

### Metadata

```json
{
  "nodes": [],
  "edges": [],
  "metadata": {
    "scan_date": "ISO8601 timestamp",
    "parent_directory": "{{PARENT_DIR}}",
    "total_repos": 12,
    "total_edges": 34,
    "edge_counts": {
      "package": 20,
      "api": 5,
      "shared": 6,
      "infra": 3
    },
    "cycles": [],
    "cycle_count": 0
  }
}
```

Each edge in the `edges` array follows this schema:

```json
{
  "source": "repo-a",
  "target": "repo-b",
  "type": "package",
  "weight": 3,
  "details": "...",
  "confidence": "confirmed",
  "in_cycle": false,
  "metadata": {}
}
```

The `metadata` object varies by edge type:

| Edge type | `metadata` fields |
|---|---|
| `package` | `packages` (string[]), `manifest` (string) |
| `api` | `endpoints` (string[]), `env_vars` (string[]), `files` (string[]) |
| `shared` | _(empty object)_ |
| `infra` | `services` (string[]), `files` (string[]), `ref_type` (string) |

Write the assembled JSON to `{{OUTPUT_DIR}}/dependency-graph.json`.

---

## Error Handling

- If Grep fails for a repo during API detection, log the error, skip that repo, and continue with the remaining repos.
- If `yq` is unavailable for docker-compose parsing, fall back to grep-based extraction of service names and `depends_on` values.
- If a detection type (package, api, shared, infra) finds zero edges, that is a valid result — continue to the next step.
- Always produce valid JSON output, even if `nodes` and `edges` arrays are empty.

## Write Boundary

Only write files inside `{{OUTPUT_DIR}}/`.

## Constraints

- Do not use the Agent tool.
- Do not prompt the user.
- Complete in under 180 seconds.

## Success Condition

`{{OUTPUT_DIR}}/dependency-graph.json` exists and is valid JSON containing `nodes`, `edges`, and `metadata` fields.
