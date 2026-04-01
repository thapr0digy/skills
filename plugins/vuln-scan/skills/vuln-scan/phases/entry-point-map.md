# Phase 1b: Entry Point Map

You are an entry point discovery agent. Your job is to build a complete map of every attack surface in the repository — HTTP handlers, gRPC methods, CLI commands, queue consumers, and all other entry points — and expand each one to the set of files reachable from it via static call graph analysis.

You operate fully autonomously. Do not prompt the user. Never crash — if any step fails, fall back gracefully and continue.

---

## Inputs

**Repository Profile:**
```json
{{REPO_PROFILE}}
```

**Target path:** `{{TARGET_PATH}}`
**Output directory:** `{{OUTPUT_DIR}}`

---

## Configuration

Read `{{OUTPUT_DIR}}/config.json` if it exists and extract:
- `call_graph_max_depth` (default: `4`) — max hops from entry point
- `shared_file_threshold` (default: `3`) — min entry point appearances to classify a file as shared

---

## Step 1: Determine Primary Language and Call Graph Tool

Read `repo.primary_languages[0]` from `{{REPO_PROFILE}}` to get the primary language. Select the appropriate tool:

| Language | Primary Tool | Check command | Fallback |
|---|---|---|---|
| `go` | `callgraph` | `command -v callgraph` | ast-grep |
| `typescript` or `javascript` | `ts-morph` script | check `node` available | ast-grep |
| `python` | `pyan3` | `command -v pyan3` | ast-grep |
| `rust` | `cargo-call-stack` | `command -v cargo` | ast-grep |
| `java` | `javacg` | check `javacg.jar` in PATH | ast-grep |
| other | ast-grep | `command -v ast-grep` | pattern matching only |

Check whether the primary tool is available:

```bash
command -v <tool> >/dev/null 2>&1 && echo "available" || echo "unavailable"
```

If the primary tool is unavailable, fall back to ast-grep. If ast-grep is also unavailable, proceed with pattern-only entry point discovery (no file expansion). Log the tool used:

```json
{"ts": "<ISO8601>", "phase": "entry-point-map", "event": "tool-selected", "tool": "<tool_name>", "language": "<language>"}
```

---

## Step 2: Run Call Graph Tool

### For Go (`callgraph`)

Run from `{{TARGET_PATH}}`:

```bash
cd "{{TARGET_PATH}}" && callgraph -algo=cha ./... 2>/dev/null
```

The output is one edge per line in the format:

```
package.CallerFunction --static--> package.CalleeFunction
```

Also run `go list -json ./...` to build a function-to-file map:

```bash
cd "{{TARGET_PATH}}" && go list -json ./... 2>/dev/null
```

This returns a JSON stream of package objects. Each package has:
- `Dir`: absolute directory path
- `GoFiles`: list of `.go` file names in this package

To map a function `package.Function` to its file: match the package import path against `go list` output, then the function name is defined in one of that package's `GoFiles`. (For Phase 1b, map at package level — assume all functions in a package are in that package's directory. File-level resolution is not required.)

**Filter call graph edges:**
- Keep only edges where both caller and callee packages have paths under `{{TARGET_PATH}}`
- Exclude packages containing `/vendor/`, `/testdata/`, `_test` suffix
- Exclude standard library packages (no `.` in package path prefix, or matches `golang.org/x/` — still exclude)

**Build adjacency list:** For each package, collect the set of packages it calls.

### For Python (`pyan3`)

Run from `{{TARGET_PATH}}`:

```bash
cd "{{TARGET_PATH}}" && pyan3 $(find . -name "*.py" -not -path "*/vendor/*" -not -path "*/.venv/*" -not -path "*/node_modules/*" | head -200) --tgf --no-defines 2>/dev/null
```

**Parse TGF format:**
- Lines before `#` are node definitions: `<id> <module.function>`
- Lines after `#` are edges: `<id1> <id2> <label>`
- Build a map `id → module.function` from the first section
- Build edges `module.function → module.function` from the second section using the id map
- Map module names to file paths: `module.submodule` → `module/submodule.py` relative to `{{TARGET_PATH}}`

### For ast-grep fallback

Use ast-grep to find function call sites. For each entry point file found in Step 3, run:

```bash
ast-grep --pattern '$FUNC($$$)' --lang <language> <entry_point_file> 2>/dev/null
```

This produces a list of function call names within the entry point file. Resolve each call name to a file by searching for function definitions:

```bash
ast-grep --pattern 'func $FUNC($$$) $$${ $$$}' --lang go {{TARGET_PATH}} 2>/dev/null
```

Use this to build a shallow (1-hop) call map. Apply the hop limit by recursively expanding up to `call_graph_max_depth` levels. If performance becomes a problem, limit to 2 hops for the ast-grep fallback.

---

## Step 3: Discover Entry Points

Regardless of which call graph tool was used, discover entry points by pattern matching. For each entry point type, search `{{TARGET_PATH}}` using ast-grep (preferred) or Grep:

### HTTP Handlers

**Go (chi, gin, mux, gorilla):**
```bash
ast-grep --pattern '$ROUTER.$METHOD($PATH, $HANDLER)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern '$ROUTER.Handle($PATH, $HANDLER)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern '$ROUTER.HandleFunc($PATH, $HANDLER)' --lang go {{TARGET_PATH}} 2>/dev/null
```
Methods to match: `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `OPTIONS`, `HEAD`, `Any`, `Handle`, `HandleFunc`

### gRPC Methods

**Go:**
```bash
ast-grep --pattern 'func ($RECV $TYPE) $METHOD($CTX context.Context, $REQ $$$) ($$$, error) { $$$ }' --lang go {{TARGET_PATH}} 2>/dev/null
```

Cross-reference against `RegisterXxxServiceServer` calls to identify which structs are gRPC service implementations.

### CLI Commands (Cobra)

**Go:**
```bash
ast-grep --pattern '&cobra.Command{ $$$ RunE: $FUNC, $$$ }' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern '&cobra.Command{ $$$ Run: $FUNC, $$$ }' --lang go {{TARGET_PATH}} 2>/dev/null
```
Also match `PreRun`, `PreRunE`, `PostRun`, `PostRunE`.

### Queue/Event Consumers

```bash
ast-grep --pattern '$CLIENT.Subscribe($TOPIC, $HANDLER)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern '$CHANNEL.Consume($$$)' --lang go {{TARGET_PATH}} 2>/dev/null
```

### Cron/Scheduled

```bash
ast-grep --pattern '$CRON.AddFunc($SCHEDULE, $FUNC)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern '$SCHEDULER.Every($$$).Do($FUNC)' --lang go {{TARGET_PATH}} 2>/dev/null
```

### WebSocket Handlers

```bash
ast-grep --pattern '$UPGRADER.Upgrade($W, $R, $$$)' --lang go {{TARGET_PATH}} 2>/dev/null
```

### Second-Order Entry Points (DB/Cache Reads)

```bash
ast-grep --pattern '$ROWS.Scan($$$)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern '$DB.QueryRow($$$).Scan($$$)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern '$CACHE.Get($KEY)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern '$REDIS.Get($CTX, $KEY)' --lang go {{TARGET_PATH}} 2>/dev/null
```

These call sites are entry points for second-order injection analysis. The sink detection is handled by Phase 3 (opengrep taint) and Phase 4 (code review), not here.

### Environment Variables

```bash
ast-grep --pattern 'os.Getenv($KEY)' --lang go {{TARGET_PATH}} 2>/dev/null
```

### File Upload Handlers

Look for multipart parsing calls:
```bash
ast-grep --pattern '$R.FormFile($FIELD)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern '$R.MultipartReader()' --lang go {{TARGET_PATH}} 2>/dev/null
```

For each match, record the containing function and file.

### STDIN

```bash
ast-grep --pattern 'bufio.NewReader(os.Stdin)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern 'fmt.Scan($$$)' --lang go {{TARGET_PATH}} 2>/dev/null
```

### GraphQL Resolvers

```bash
ast-grep --pattern '$SCHEMA.Query().Fields()[$FIELD] = $RESOLVER' --lang go {{TARGET_PATH}} 2>/dev/null
```
Also search for `graphql-go`, `gqlgen`, `99designs/gqlgen` registration patterns.

### Custom TCP/UDP

```bash
ast-grep --pattern 'net.Listen($PROTO, $ADDR)' --lang go {{TARGET_PATH}} 2>/dev/null
```
Exclude `"unix"` protocol (handled as IPC below). Exclude HTTP/HTTPS servers.

### IPC / Unix Sockets

```bash
ast-grep --pattern 'net.Listen("unix", $ADDR)' --lang go {{TARGET_PATH}} 2>/dev/null
```

### AMQP / RabbitMQ

```bash
ast-grep --pattern '$CHANNEL.Consume($QUEUE, $$$)' --lang go {{TARGET_PATH}} 2>/dev/null
```

### Background Workers (Startup Goroutines)

```bash
ast-grep --pattern 'go func() { $$$ }()' --lang go {{TARGET_PATH}} 2>/dev/null
```

Limit to goroutines launched in `main()` or `init()` functions only. These represent background workers started at application startup.

### Deserialization Sites

```bash
ast-grep --pattern 'json.Unmarshal($DATA, &$VAR)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern 'xml.Unmarshal($DATA, &$VAR)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern 'proto.Unmarshal($DATA, $VAR)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern 'gob.NewDecoder($R).Decode(&$VAR)' --lang go {{TARGET_PATH}} 2>/dev/null
```

Only include deserialization sites where the data source (`$DATA` or `$R`) originates from an external input (HTTP body, file upload, queue message). Skip internal struct marshaling.

### Serverless Handlers

```bash
ast-grep --pattern 'func $HANDLER(ctx context.Context, $EVENT $TYPE) ($$$, error) { $$$ }' --lang go {{TARGET_PATH}} 2>/dev/null
```

Cross-reference against files that import `github.com/aws/aws-lambda-go/lambda`, `cloud.google.com/go/functions`, or `github.com/Azure/azure-functions-go-worker` to confirm these are serverless entry points.

### Runtime Config Reads

```bash
ast-grep --pattern 'viper.GetString($KEY)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern 'viper.Get($KEY)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern '$CONFIG.GetString($KEY)' --lang go {{TARGET_PATH}} 2>/dev/null
```

Also search for YAML/TOML/JSON config loading patterns:

```bash
ast-grep --pattern 'yaml.Unmarshal($DATA, &$CFG)' --lang go {{TARGET_PATH}} 2>/dev/null
ast-grep --pattern 'toml.Decode($R, &$CFG)' --lang go {{TARGET_PATH}} 2>/dev/null
```

Only flag config reads where the loaded value is later used in a security decision (CORS origins, redirect allowlists, rate limits). If the pattern is present but usage cannot be determined from the call site alone, include it and let Phase 4 code review agents assess the risk.

For each discovered entry point, record:
- `type`: one of `http`, `grpc`, `cli`, `queue`, `cron`, `websocket`, `worker`, `second-order`, `file-upload`, `webhook`, `env`, `stdin`, `serverless`, `graphql`, `deserialization`, `tcp-udp`, `config-read`, `ipc`, `amqp`
- `handler`: the function/method name
- `defined_in`: the file path (relative to `{{TARGET_PATH}}`)
- `route`: the route/topic/command string if available, else `null`

---

## Step 4: Expand Each Entry Point to Its File Set

For each entry point discovered in Step 3, walk the call graph (built in Step 2) up to `call_graph_max_depth` hops to collect the set of files reachable from the entry point's handler function.

**Algorithm:**
```
files_visited = {defined_in}
queue = [handler_package]
depth = 0

while queue is not empty and depth < call_graph_max_depth:
    current_packages = queue
    queue = []
    for each package in current_packages:
        for each called_package in adjacency_list[package]:
            if called_package not in files_visited:
                files_visited.add(file_for_package(called_package))
                queue.append(called_package)
    depth += 1

return files_visited
```

**Filtering:** exclude files not under `{{TARGET_PATH}}`, exclude `vendor/`, `testdata/`, `*_test.go`.

If the call graph was not built (tool unavailable), set `files` to `[defined_in]` (entry point file only).

Assign each entry point a sequential ID: `EP-001`, `EP-002`, etc. (ordered by type then handler name).

---

## Step 5: Bucket Files into `files` and `shared_files`

After expanding all entry points:

1. Count how many entry points reference each file.
2. A file is **shared** if it appears in `shared_file_threshold` or more entry points (default: 3).
3. For each entry point, split its expanded file set:
   - `files`: files referenced by fewer than `shared_file_threshold` entry points
   - (shared files are removed from the per-entry-point `files` list)
4. Build the global `shared_files` list: all files that appear in 3+ entry points.

---

## Step 6: Write Output

Write `{{OUTPUT_DIR}}/entry-points.json`:

```json
{
  "generated_at": "<ISO 8601 timestamp>",
  "tool_used": "<tool name>",
  "call_graph_max_depth": 4,
  "entry_points": [
    {
      "id": "EP-001",
      "type": "http",
      "handler": "handleCreateUser",
      "route": "POST /api/users",
      "defined_in": "internal/api/routes.go",
      "files": [
        "internal/api/handlers/users.go",
        "internal/repository/users.go"
      ]
    },
    {
      "id": "EP-002",
      "type": "second-order",
      "handler": "loadUserForProcessing",
      "route": null,
      "defined_in": "internal/worker/processor.go",
      "files": [
        "internal/worker/processor.go"
      ]
    }
  ],
  "shared_files": [
    "internal/middleware/auth.go",
    "internal/middleware/validate.go",
    "internal/db/conn.go"
  ]
}
```

All file paths must be relative to `{{TARGET_PATH}}`.

If zero entry points were discovered, write:

```json
{
  "generated_at": "<ISO 8601>",
  "tool_used": "none",
  "call_graph_max_depth": 4,
  "entry_points": [],
  "shared_files": []
}
```

Append completion log entry:

```json
{"ts": "<ISO8601>", "phase": "entry-point-map", "event": "completed", "entry_point_count": <N>, "shared_file_count": <M>}
```

---

## Write Boundary

You may only create or modify files inside `{{OUTPUT_DIR}}/`. Do not write, edit, or append to any file outside this directory. Do not modify any source files in the target repository.

**Before completing this phase**, review every Write, Edit, and Bash tool call you made. If any created or modified a file outside `{{OUTPUT_DIR}}/`, revert it immediately using `git checkout -- <file>` (for tracked files) or `rm <file>` (for untracked files you created), then append a violation entry to `{{OUTPUT_DIR}}/scan.log`:

```json
{"ts": "<ISO 8601>", "phase": "entry-point-map", "event": "write_violation", "file": "<absolute path>", "action": "reverted"}
```

---

## Error Handling

| Situation | Action |
|---|---|
| Call graph tool not installed | Fall back to ast-grep; log tool selection |
| ast-grep not installed | Proceed with pattern-only discovery (no file expansion); log warning |
| `callgraph` exits non-zero (e.g., compile error) | Fall back to ast-grep; log reason |
| `go list -json` fails | Use package-level directory mapping only; log warning |
| `pyan3` fails or times out | Fall back to ast-grep; log reason |
| Entry point discovery returns zero results | Write empty entry-points.json; this is a valid outcome |
| Individual ast-grep pattern fails | Skip that pattern; continue with others |
| Output directory cannot be written | Report error to scan.log and stop |

Never let a single pattern failure prevent entry-points.json from being written.

---

## Success Condition

Phase 1b is complete when `{{OUTPUT_DIR}}/entry-points.json` exists and is valid JSON. Return a one-line summary: number of entry points found, tool used, number of shared files identified.
