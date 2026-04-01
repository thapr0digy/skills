---
name: vuln-scan
description: Autonomous vulnerability scanning pipeline — scans repos for security issues and produces markdown + SARIF reports. Invoke via /vuln-scan [path].
user_invocable: true
---

# vuln-scan — Coordinator

You are the orchestrator of a 7-phase autonomous vulnerability scanning pipeline. When a user invokes `/vuln-scan [path]`, follow every step below exactly. Make no decisions interactively — every choice is defined here. Do not prompt the user at any point during execution.

---

## Step 1 — Parse Arguments

Extract the target path from the skill invocation arguments.

- If an argument was provided, use it as the target path (resolve to an absolute path if relative).
- If no argument was provided, default to the current working directory.

Store this value as `TARGET_PATH` for all subsequent steps.

### Derive OUTPUT_DIR

Compute the output directory by deriving a sanitized directory name from `TARGET_PATH` relative to the current working directory:

1. Compute the relative path of `TARGET_PATH` from the current working directory. If `TARGET_PATH` is the current working directory, use the directory's basename.
2. Replace path separators (`/`) with hyphens (`-`). Remove leading/trailing hyphens.
3. Set `OUTPUT_DIR` to `{CWD}/vuln-scan-results/{sanitized-name}` where `{CWD}` is the current working directory.

**Examples:**
- `/vuln-scan` (target = CWD `/home/user/myapp`) → `OUTPUT_DIR` = `/home/user/myapp/vuln-scan-results/myapp`
- `/vuln-scan src/api` → `OUTPUT_DIR` = `/home/user/myapp/vuln-scan-results/src-api`
- `/vuln-scan /other/repo` → `OUTPUT_DIR` = `/home/user/myapp/vuln-scan-results/other-repo`

This ensures each scan target gets its own results directory that persists across runs.

---

## Step 2 — Validate Target

Use the Bash tool to confirm the target is a usable directory:

```bash
[ -d "{TARGET_PATH}" ] && echo "exists" || echo "missing"
```

Then use Glob to check that the directory contains at least one source file (any file matching `**/*.*` excluding `vuln-scan-results/**`).

**If the directory does not exist or contains no source files:** output an error message to the user explaining the problem and stop. Do not proceed.

---

## Step 3 — Setup Output Directory

Check whether `{OUTPUT_DIR}/config.json` exists (this file is user-created, NOT generated). If it exists, preserve it across the cleanup.

Execute the following using the Bash tool. Run these as a single shell script block.

```bash
# Preserve user config if it exists (stash in parent vuln-scan-results/ dir)
[ -f "{OUTPUT_DIR}/config.json" ] && mv "{OUTPUT_DIR}/config.json" "{OUTPUT_DIR}/../.vuln-scan-config-preserve.json"

# Remove previous scan output
rm -rf "{OUTPUT_DIR}"

# Create fresh output directories
mkdir -p "{OUTPUT_DIR}/findings"

# Restore user config if it was preserved
[ -f "{OUTPUT_DIR}/../.vuln-scan-config-preserve.json" ] && mv "{OUTPUT_DIR}/../.vuln-scan-config-preserve.json" "{OUTPUT_DIR}/config.json"
```

Initialize the scan log by writing the following JSON line to `{OUTPUT_DIR}/scan.log` using the Write tool:

```json
{"ts": "<ISO 8601 timestamp>", "phase": "coordinator", "event": "start", "target": "{TARGET_PATH}"}
```

---

## Step 4 — Phase 1: Recon

**Goal:** Produce `{OUTPUT_DIR}/repo-profile.json`.

1. Use the Read tool to read the file at `{SKILL_DIR}/phases/recon.md` where `{SKILL_DIR}` is the directory containing this SKILL.md file (i.e., the `skills/vuln-scan/` directory within the repository where you were loaded from).
2. In the loaded text, replace every occurrence of `{{TARGET_PATH}}` with the actual value of `TARGET_PATH`, and every occurrence of `{{OUTPUT_DIR}}` with the actual value of `OUTPUT_DIR`.
3. Use the Agent tool to dispatch the prepared prompt as a subagent. Use this description: `"Run Phase 1 recon"`.
4. Wait for the subagent to return.
5. Append this line to `{OUTPUT_DIR}/scan.log`:
   - On success: `{"ts": "<timestamp>", "phase": "recon", "event": "completed", "duration_s": <elapsed>}`
   - On failure: `{"ts": "<timestamp>", "phase": "recon", "event": "failed", "reason": "<short reason>"}`
6. Use the Read tool to load `{OUTPUT_DIR}/repo-profile.json`.
   - **If this file does not exist or is not valid JSON:** write a `failed` log entry, output a single error message to the user ("Phase 1 (Recon) failed — cannot continue without a repo profile"), and stop. Do not proceed to any further phase.
7. Store the file contents as `REPO_PROFILE`.

---

## Step 4b — Phase 1b: Entry Point Map

**Goal:** Produce `{OUTPUT_DIR}/entry-points.json`.

1. Use the Read tool to read `{SKILL_DIR}/phases/entry-point-map.md`.
2. Replace every occurrence of `{{REPO_PROFILE}}` with the contents of `REPO_PROFILE`.
3. Replace every occurrence of `{{TARGET_PATH}}` with the actual value of `TARGET_PATH`.
4. Replace every occurrence of `{{OUTPUT_DIR}}` with the actual value of `OUTPUT_DIR`.
5. Dispatch the prepared prompt as a subagent. Description: `"Run Phase 1b entry point map"`.
6. Wait for the subagent to return.
7. Use the Read tool to load `{OUTPUT_DIR}/entry-points.json`.
   - **If the file exists and is valid JSON:** store its contents as `ENTRY_POINTS`. Append a `completed` log entry: `{"ts": "<timestamp>", "phase": "entry-point-map", "event": "completed", "duration_s": <elapsed>}`
   - **If the file is missing or invalid:** store `ENTRY_POINTS` as `{}`. Append a `failed` log entry: `{"ts": "<timestamp>", "phase": "entry-point-map", "event": "failed", "reason": "entry-points.json missing or invalid, downstream phases will use fallback behavior"}`. Do not abort.

---

## Step 5 — Phase 2: Threat Model

**Goal:** Produce `{OUTPUT_DIR}/threat-model.json`.

1. Use the Read tool to read `{SKILL_DIR}/phases/threat-model.md`.
2. Replace every occurrence of `{{REPO_PROFILE}}` with the contents of `REPO_PROFILE`.
3. Replace every occurrence of `{{ENTRY_POINTS}}` with the contents of `ENTRY_POINTS`.
4. Replace `{{OUTPUT_DIR}}` with the actual value of `OUTPUT_DIR`.
5. Replace `{{SERVICES}}` with the `services` array from `REPO_PROFILE` (extracted as a JSON array string). If `is_monorepo` is `false` in the repo profile, replace `{{SERVICES}}` with `[]`.
6. Dispatch the prepared prompt as an Agent subagent. Description: `"Run Phase 2 threat model"`.
7. Wait for the subagent to return.
8. Use the Read tool to load `{OUTPUT_DIR}/threat-model.json`.
   - **If the file exists and is valid JSON:** store its contents as `THREAT_MODEL`. Append a `completed` log entry.
   - **If the file is missing or invalid:** store `THREAT_MODEL` as the string `{}`. Append a `failed` log entry with `"reason": "threat model output missing, continuing with empty model"`. Do not abort — partial results are acceptable.

---

## Step 6 — Phases 3–5: Parallel Scanning

**Goal:** Run static analysis, code review, and dependency scan simultaneously.

### 6a — Prepare all prompts

**6a-i — Load phase templates**

Use the Read tool (may be parallelized) to load:
- `{SKILL_DIR}/phases/static-analysis.md` — perform replacements: `{{REPO_PROFILE}}` → `REPO_PROFILE`, `{{THREAT_MODEL}}` → `THREAT_MODEL`, `{{SERVICES}}` → services array from `REPO_PROFILE`, `{{OUTPUT_DIR}}` → `OUTPUT_DIR`, `{{ENTRY_POINTS}}` → `ENTRY_POINTS`. Store the result as the prepared static-analysis prompt.
- `{SKILL_DIR}/phases/dependency-scan.md` — perform replacements: `{{REPO_PROFILE}}` → `REPO_PROFILE`, `{{OUTPUT_DIR}}` → `OUTPUT_DIR`, `{{SERVICES}}` → services array from `REPO_PROFILE`. Store the result as the prepared dependency-scan prompt.
- `{SKILL_DIR}/phases/code-review.md` — load as a template only. Do NOT dispatch it directly. Store as `CODE_REVIEW_TEMPLATE`.

For all replacements, if `is_monorepo` is `false` in the repo profile, replace `{{SERVICES}}` with `[]`. Skip a replacement if that placeholder does not appear in the file.

**6a-ii — Form path groups**

Read `high_risk_paths` from `THREAT_MODEL`. Group them in priority order:

For each path, estimate its token cost:

```bash
# Sum the byte sizes of all unique files in this path
total=0
for f in <path.files>; do
  size=$(wc -c < "{TARGET_PATH}/$f" 2>/dev/null || echo 0)
  total=$((total + size))
done
echo $total
```

Note: In SKILL.md coordinator steps, `{TARGET_PATH}` is the resolved variable (no double-braces). Double-brace `{{PLACEHOLDER}}` syntax is only used inside phase files dispatched as subagent prompts.

Use 4 bytes ≈ 1 token as a proxy.

Read `code_review_token_budget` from `{OUTPUT_DIR}/config.json` (default: `60000`).
Read `code_review_group_size` from `{OUTPUT_DIR}/config.json` (default: `5`).

Assign paths to groups:
- Start group 1. Add paths in priority order.
- After adding each path, check: if group path count ≥ `code_review_group_size` OR cumulative token estimate ≥ `code_review_token_budget`, start a new group.
- Token budget check takes precedence: if adding a path would exceed the budget, start a new group first even if path count < `code_review_group_size`.
- A single path whose files alone exceed `code_review_token_budget` forms its own group.

Result: an array of group objects, each with `group_id` (integer, starting at 1) and `paths` (array of path objects).

**6a-iii — Pre-load shared files per group**

For each group, collect the union of `shared_files_needed` across all paths in the group. Read each file:

```bash
cat "{TARGET_PATH}/<shared_file_path>"
```

Build a JSON object mapping file path → file content: `{"internal/middleware/auth.go": "<content>", ...}`.

Store this as the group's `SHARED_FILES_CONTENT`.

**6a-iv — Prepare one prompt per group**

For each group, take the `CODE_REVIEW_TEMPLATE` and perform these replacements:
- Replace `{{GROUP_ASSIGNMENT}}` with a JSON object: `{"group_id": <N>, "paths": [<path objects>]}`
- Replace `{{SHARED_FILES_CONTENT}}` with the pre-loaded shared files JSON for this group
- Replace `{{REPO_PROFILE}}` with `REPO_PROFILE`
- Replace `{{THREAT_MODEL}}` with `THREAT_MODEL`
- Replace `{{SERVICES}}` with the services array from `REPO_PROFILE`
- Replace `{{OUTPUT_DIR}}` with `OUTPUT_DIR`
- Replace `{{GROUP_ID}}` with the group's integer ID

### 6b — Dispatch all agents in a single message

**CRITICAL:** You MUST invoke all agent tool calls in a single response message. This triggers parallel execution.

Dispatch:
- Static analysis agent: prepared `static-analysis.md` prompt. Description: `"Run Phase 3 static analysis"`
- **One agent per code review group**: use each group's prepared prompt from 6a-iv. Description: `"Run Phase 4 code review group {group_id}"`
- Dependency scan agent: prepared `dependency-scan.md` prompt. Description: `"Run Phase 5 dependency scan"`

Example for 3 groups: dispatch 5 agents total (1 static + 3 code review + 1 dependency) in one message.

### 6c — Handle results

After all subagents return, append a log entry for each:
- Static analysis: `{"ts": "<timestamp>", "phase": "static-analysis", "event": "completed/failed", ...}`
- Each code review group: `{"ts": "<timestamp>", "phase": "code-review", "group_id": <N>, "event": "completed/failed", ...}`
- Dependency scan: `{"ts": "<timestamp>", "phase": "dependency-scan", "event": "completed/failed", ...}`

If parallel dispatch fails, fall back to dispatching each agent sequentially. For code review groups, dispatch group 1 first, then group 2, etc. Log a `skipped` entry for parallel mode:

```json
{"ts": "<timestamp>", "phase": "parallel-dispatch", "event": "skipped", "reason": "parallel dispatch failed, falling back to sequential"}
```

Do not abort if one or more of these phases fail — proceed to validation with whatever findings were produced.

---

## Step 7 — Phase 6: Validation

**Goal:** Produce `{OUTPUT_DIR}/validated-findings.json`.

1. Use the Read tool to read `{SKILL_DIR}/phases/validation.md`.

2. Perform these replacements:
   - Replace `{{THREAT_MODEL}}` with the contents of `THREAT_MODEL`.
   - Replace `{{OUTPUT_DIR}}` with the actual value of `OUTPUT_DIR`.
   - Replace `{{FINDINGS_DIR}}` with the path `{OUTPUT_DIR}/findings`.
   - Replace `{{SERVICES}}` with the `services` array from `REPO_PROFILE` (extracted as a JSON array string). If `is_monorepo` is `false` in the repo profile, replace `{{SERVICES}}` with `[]`.

3. For each findings file, attempt to read it with the Read tool. If the file exists, replace the corresponding placeholder with its contents. If the file does not exist, leave the placeholder as-is (the validation phase prompt handles absent data gracefully).

   | Placeholder                    | File path                                              |
   |-------------------------------|--------------------------------------------------------|
   | `{{STATIC_ANALYSIS_FINDINGS}}` | `{OUTPUT_DIR}/findings/static-analysis.json` |
   | `{{CODE_REVIEW_FINDINGS}}`     | `{OUTPUT_DIR}/findings/code-review.json`     |
   | `{{DEPENDENCY_FINDINGS}}`      | `{OUTPUT_DIR}/findings/dependencies.json`    |

4. Dispatch the prepared prompt as an Agent subagent. Description: `"Run Phase 6 validation"`.
5. Wait for the subagent to return.
6. Use the Read tool to load `{OUTPUT_DIR}/validated-findings.json`.
   - **If the file exists and is valid JSON:** store its contents as `VALIDATED_FINDINGS`. Append a `completed` log entry.
   - **If the file is missing or invalid:** store `VALIDATED_FINDINGS` as `{}`. Append a `failed` log entry. Do not abort.

---

## Step 8 — Phase 7: Reporting

**Goal:** Produce the final markdown and SARIF report files in `{OUTPUT_DIR}/`.

1. Use the Read tool to read `{SKILL_DIR}/phases/reporting.md`.
2. Perform these replacements:
   - Replace `{{VALIDATED_FINDINGS}}` with the contents of `VALIDATED_FINDINGS`.
   - Replace `{{REPO_PROFILE}}` with the contents of `REPO_PROFILE`.
   - Replace `{{THREAT_MODEL}}` with the contents of `THREAT_MODEL`.
   - Replace `{{OUTPUT_DIR}}` with the actual value of `OUTPUT_DIR`.
   - Replace `{{SERVICES}}` with the `services` array from `REPO_PROFILE` (extracted as a JSON array string). If `is_monorepo` is `false` in the repo profile, replace `{{SERVICES}}` with `[]`.
3. Dispatch the prepared prompt as an Agent subagent. Description: `"Run Phase 7 reporting"`.
4. Wait for the subagent to return.
5. Append a `completed` or `failed` log entry to `scan.log`.

---

## Step 9 — Present Results

After Phase 8 completes, read `{OUTPUT_DIR}/validated-findings.json` and extract the summary section. Then output the following to the user:

```
vuln-scan complete for: {TARGET_PATH}

Findings summary:
  Critical : <count>
  High     : <count>
  Medium   : <count>
  Low      : <count>
  Total    : <count>

Reports written to:
  {OUTPUT_DIR}/SECURITY_REPORT.md
  {OUTPUT_DIR}/report.sarif

Scan log: {OUTPUT_DIR}/scan.log
```

If the repo profile's `is_monorepo` is `true`, also display:

```
Service breakdown:
  {service_name}: {count} findings
  {service_name}: {count} findings
  shared ({shared_name}): {count} findings (affects: {consumers list})
```

Read the `by_service` counts from `validated-findings.json`'s summary section.

If `validated-findings.json` is absent or unparseable, omit the findings summary section and note that validation output was unavailable.

Append a final log entry to `scan.log`:

```json
{"ts": "<ISO 8601 timestamp>", "phase": "coordinator", "event": "completed", "duration_s": <total elapsed since start>}
```

---

## scan.log Format Reference

Every log entry is a single JSON object written as one line. Append entries with the Write or Bash tool (append mode). Never overwrite the log — only append.

```
{"ts": "<ISO 8601>", "phase": "<name>", "event": "<type>", ...context}
```

**Event types:**
- `start` — pipeline is beginning; include `"target": "<path>"`
- `dispatched` — agent has been sent (optional, use for long phases)
- `completed` — phase finished successfully; include `"duration_s": <number>`
- `failed` — phase produced no usable output; include `"reason": "<string>"`
- `skipped` — phase was intentionally bypassed; include `"reason": "<string>"`

**Phase names:** `coordinator`, `recon`, `entry-point-map`, `threat-model`, `static-analysis`, `code-review`, `dependency-scan`, `validation`, `reporting`, `parallel-dispatch`

---

## Key Constraints

- **Never prompt the user** during execution. All decisions are defined in this document.
- **Never abort on phases 3–7 failures.** Partial results are always better than no results. Only Phase 1 (Recon) is a hard abort condition.
- **Skill directory resolution:** `{SKILL_DIR}` refers to the directory from which this SKILL.md was loaded. Phase prompts live in `{SKILL_DIR}/phases/`. When dispatching subagents, use absolute paths when reading phase files.
- **Template injection** is simple string replacement. Replace `{{PLACEHOLDER}}` literally with the substituted content. Do not interpret or transform the content.
- **Output directory** is always `{OUTPUT_DIR}/`. All phase output files are written there by the subagents — the coordinator only reads them.
- **Write boundary:** Subagents must only write files inside `{OUTPUT_DIR}/`. If a subagent writes or modifies any file outside this directory, it must revert the change (e.g., `git checkout -- <file>`) and log a violation entry to `scan.log`: `{"ts": "<ISO 8601>", "phase": "<phase>", "event": "write_violation", "file": "<path>", "action": "reverted"}`.
- **Error messages** go to `scan.log` as JSON entries. Only surface errors to the user on a hard abort (Phase 1 failure) or in the final summary.
