---
name: dep-graph
description: Scans a parent directory of git repositories and generates an interactive D3.js dependency graph showing cross-repo relationships. Invoke via /dep-graph [parent-directory].
user_invocable: true
---

# dep-graph — Coordinator

You are the orchestrator of a 3-phase dependency graph generation pipeline. When a user invokes `/dep-graph [path]`, follow every step below exactly. Make no decisions interactively — every choice is defined here. Do not prompt the user at any point during execution.

---

## Step 1 — Parse Arguments

Extract the parent directory from the skill invocation arguments.

- If an argument was provided, use it as the parent directory (resolve to an absolute path if relative).
- If no argument was provided, default to the current working directory.

Store this value as `PARENT_DIR`.

### Derive OUTPUT_DIR

Compute the output directory:

1. Compute the relative path of `PARENT_DIR` from the current working directory. If `PARENT_DIR` is the current working directory, use the directory's basename.
2. Replace path separators (`/`) with hyphens (`-`). Remove leading/trailing hyphens.
3. Set `OUTPUT_DIR` to `{CWD}/dep-graph-results/{sanitized-name}` where `{CWD}` is the current working directory.

---

## Step 2 — Validate Target

Use the Bash tool to confirm the parent directory exists and contains git repositories:

```bash
[ -d "{PARENT_DIR}" ] && echo "exists" || echo "missing"
```

Then find git repos:

```bash
fd --type d --max-depth 2 '.git' "{PARENT_DIR}" --hidden 2>/dev/null | head -50
```

If the directory does not exist or contains no git repos, output an error and stop.

Store the repo count for the final summary.

---

## Step 3 — Setup Output Directory

```bash
rm -rf "{OUTPUT_DIR}" && mkdir -p "{OUTPUT_DIR}"
```

Initialize the scan log:

```json
{"ts": "<ISO 8601 timestamp>", "phase": "coordinator", "event": "start", "target": "{PARENT_DIR}"}
```

---

## Step 4 — Phase 1: Discovery

**Goal:** Produce `{OUTPUT_DIR}/repo-inventory.json`.

1. Read `{SKILL_DIR}/phases/discovery.md`.
2. Replace `{{PARENT_DIR}}` with `PARENT_DIR` and `{{OUTPUT_DIR}}` with `OUTPUT_DIR`.
3. Dispatch as Agent subagent. Description: `"Run Phase 1 discovery"`.
4. Wait for return.
5. Read `{OUTPUT_DIR}/repo-inventory.json`.
   - If missing or invalid JSON: log failed, output "Phase 1 (Discovery) failed — cannot continue without repo inventory", stop.
6. Store contents as `REPO_INVENTORY`.
7. Log completed entry.

---

## Step 5 — Phase 2: Analysis

**Goal:** Produce `{OUTPUT_DIR}/dependency-graph.json`.

1. Read `{SKILL_DIR}/phases/analysis.md`.
2. Replace `{{REPO_INVENTORY}}` with contents of `REPO_INVENTORY`, `{{OUTPUT_DIR}}` with `OUTPUT_DIR`, `{{PARENT_DIR}}` with `PARENT_DIR`.
3. Dispatch as Agent subagent. Description: `"Run Phase 2 analysis"`.
4. Wait for return.
5. Read `{OUTPUT_DIR}/dependency-graph.json`.
   - If missing or invalid: store `DEPENDENCY_GRAPH` as `{"nodes":[],"edges":[],"metadata":{}}`. Log failed. Do not abort.
   - Otherwise store as `DEPENDENCY_GRAPH`. Log completed.

---

## Step 6 — Phase 3: Rendering

**Goal:** Produce `{OUTPUT_DIR}/dep-graph.html`.

1. Read `{SKILL_DIR}/phases/rendering.md`.
2. Read `{SKILL_DIR}/templates/graph.html` and store as `HTML_TEMPLATE`.
3. Replace `{{DEPENDENCY_GRAPH}}` with contents of `DEPENDENCY_GRAPH`, `{{OUTPUT_DIR}}` with `OUTPUT_DIR`, `{{HTML_TEMPLATE}}` with `HTML_TEMPLATE`.
4. Dispatch as Agent subagent. Description: `"Run Phase 3 rendering"`.
5. Wait for return.
6. Log completed or failed.

---

## Step 7 — Present Results

Parse `DEPENDENCY_GRAPH` JSON to extract metadata. Output:

```
dep-graph complete for: {PARENT_DIR}

Graph summary:
  Repositories : {total_repos}
  Dependencies : {total_edges}
    Package    : {edge_counts.package}
    API        : {edge_counts.api}
    Shared Lib : {edge_counts.shared}
    Infra      : {edge_counts.infra}

Output: {OUTPUT_DIR}/dep-graph.html

Open in a browser to explore the interactive dependency graph.
```

Append final log entry.

---

## scan.log Format Reference

Same as vuln-scan: JSON lines, append only.

**Phase names:** `coordinator`, `discovery`, `analysis`, `rendering`

---

## Key Constraints

- **Never prompt the user** during execution.
- **Only Phase 1 is a hard abort condition.** Phases 2 and 3 degrade gracefully.
- **Skill directory resolution:** `{SKILL_DIR}` is the directory containing this SKILL.md.
- **Template injection** is simple string replacement.
- **Output directory** is always `{OUTPUT_DIR}/`.
- **Write boundary:** Subagents must only write files inside `{OUTPUT_DIR}/`.
- **Error messages** go to `scan.log` as JSON entries.
