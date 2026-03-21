---
name: vuln-scan
description: Autonomous vulnerability scanning pipeline — scans repos for security issues and produces markdown + SARIF reports. Invoke via /vuln-scan [path].
user_invocable: true
---

# vuln-scan — Coordinator

You are the orchestrator of an 8-phase autonomous vulnerability scanning pipeline. When a user invokes `/vuln-scan [path]`, follow every step below exactly. Make no decisions interactively — every choice is defined here. Do not prompt the user at any point during execution.

---

## Step 1 — Parse Arguments

Extract the target path from the skill invocation arguments.

- If an argument was provided, use it as the target path (resolve to an absolute path if relative).
- If no argument was provided, default to the current working directory.

Store this value as `TARGET_PATH` for all subsequent steps.

---

## Step 2 — Validate Target

Use the Bash tool to confirm the target is a usable directory:

```bash
[ -d "{TARGET_PATH}" ] && echo "exists" || echo "missing"
```

Then use Glob to check that the directory contains at least one source file (any file matching `**/*.*` excluding `.vuln-scan/**`).

**If the directory does not exist or contains no source files:** output an error message to the user explaining the problem and stop. Do not proceed.

---

## Step 3 — Setup Output Directory

Execute the following using the Bash tool. Run these as a single shell script block.

```bash
# Remove any previous scan output
rm -rf "{TARGET_PATH}/.vuln-scan"

# Create fresh output directories
mkdir -p "{TARGET_PATH}/.vuln-scan/findings"
```

Then check whether `.vuln-scan` is listed in `{TARGET_PATH}/.gitignore`. If the file does not exist, or if `.vuln-scan` is not present in it, append `.vuln-scan` as a new line. Use the Read tool to read `.gitignore` first, then Write or Edit to update it — only modify `.gitignore`, no other files.

Initialize the scan log by writing the following JSON line to `{TARGET_PATH}/.vuln-scan/scan.log` using the Write tool:

```json
{"ts": "<ISO 8601 timestamp>", "phase": "coordinator", "event": "start", "target": "{TARGET_PATH}"}
```

---

## Step 4 — Phase 1: Recon

**Goal:** Produce `{TARGET_PATH}/.vuln-scan/repo-profile.json`.

1. Use the Read tool to read the file at `{SKILL_DIR}/phases/recon.md` where `{SKILL_DIR}` is the directory containing this SKILL.md file (i.e., the `skills/vuln-scan/` directory within the repository where you were loaded from).
2. In the loaded text, replace every occurrence of `{{TARGET_PATH}}` with the actual value of `TARGET_PATH`.
3. Use the Agent tool to dispatch the prepared prompt as a subagent. Use this description: `"Run Phase 1 recon"`.
4. Wait for the subagent to return.
5. Append this line to `{TARGET_PATH}/.vuln-scan/scan.log`:
   - On success: `{"ts": "<timestamp>", "phase": "recon", "event": "completed", "duration_s": <elapsed>}`
   - On failure: `{"ts": "<timestamp>", "phase": "recon", "event": "failed", "reason": "<short reason>"}`
6. Use the Read tool to load `{TARGET_PATH}/.vuln-scan/repo-profile.json`.
   - **If this file does not exist or is not valid JSON:** write a `failed` log entry, output a single error message to the user ("Phase 1 (Recon) failed — cannot continue without a repo profile"), and stop. Do not proceed to any further phase.
7. Store the file contents as `REPO_PROFILE`.

---

## Step 5 — Phase 2: Threat Model

**Goal:** Produce `{TARGET_PATH}/.vuln-scan/threat-model.json`.

1. Use the Read tool to read `{SKILL_DIR}/phases/threat-model.md`.
2. Replace every occurrence of `{{REPO_PROFILE}}` with the contents of `REPO_PROFILE`.
3. Dispatch the prepared prompt as an Agent subagent. Description: `"Run Phase 2 threat model"`.
4. Wait for the subagent to return.
5. Use the Read tool to load `{TARGET_PATH}/.vuln-scan/threat-model.json`.
   - **If the file exists and is valid JSON:** store its contents as `THREAT_MODEL`. Append a `completed` log entry.
   - **If the file is missing or invalid:** store `THREAT_MODEL` as the string `{}`. Append a `failed` log entry with `"reason": "threat model output missing, continuing with empty model"`. Do not abort — partial results are acceptable.

---

## Step 6 — Phases 3–6: Parallel Scanning

**Goal:** Run static analysis, code review, dependency scan, and secret scan simultaneously.

### 6a — Prepare all four prompts

Use the Read tool four times (may be parallelized) to load:
- `{SKILL_DIR}/phases/static-analysis.md`
- `{SKILL_DIR}/phases/code-review.md`
- `{SKILL_DIR}/phases/dependency-scan.md`
- `{SKILL_DIR}/phases/secret-scan.md`

For each loaded text, perform the following replacements (skip a replacement if that placeholder does not appear in the file):
- Replace `{{REPO_PROFILE}}` with the contents of `REPO_PROFILE`.
- Replace `{{THREAT_MODEL}}` with the contents of `THREAT_MODEL`.

### 6b — Dispatch all four agents in a single message

**CRITICAL:** You MUST invoke all four Agent tool calls in a single response message. This triggers parallel execution. Do not send them in separate messages.

Use these descriptions:
- Static analysis agent: `"Run Phase 3 static analysis"`
- Code review agent: `"Run Phase 4 code review"`
- Dependency scan agent: `"Run Phase 5 dependency scan"`
- Secret scan agent: `"Run Phase 6 secret scan"`

### 6c — Handle results

After all four subagents return, append a log entry for each:
- `{"ts": "<timestamp>", "phase": "<phase-name>", "event": "completed", "duration_s": <elapsed>}`
- `{"ts": "<timestamp>", "phase": "<phase-name>", "event": "failed", "reason": "<short reason>"}`

If the parallel dispatch itself fails (e.g., tool error before any agent runs), fall back to dispatching each of the four agents sequentially, one at a time, with separate Agent tool calls. Log a `skipped` entry for parallel mode:

```json
{"ts": "<timestamp>", "phase": "parallel-dispatch", "event": "skipped", "reason": "parallel dispatch failed, falling back to sequential"}
```

Do not abort if one or more of these phases fail — proceed to validation with whatever findings were produced.

---

## Step 7 — Phase 7: Validation

**Goal:** Produce `{TARGET_PATH}/.vuln-scan/validated-findings.json`.

1. Use the Read tool to read `{SKILL_DIR}/phases/validation.md`.

2. Perform these replacements:
   - Replace `{{THREAT_MODEL}}` with the contents of `THREAT_MODEL`.
   - Replace `{{FINDINGS_DIR}}` with the path `{TARGET_PATH}/.vuln-scan/findings`.

3. For each findings file, attempt to read it with the Read tool. If the file exists, replace the corresponding placeholder with its contents. If the file does not exist, leave the placeholder as-is (the validation phase prompt handles absent data gracefully).

   | Placeholder                    | File path                                              |
   |-------------------------------|--------------------------------------------------------|
   | `{{STATIC_ANALYSIS_FINDINGS}}` | `{TARGET_PATH}/.vuln-scan/findings/static-analysis.json` |
   | `{{CODE_REVIEW_FINDINGS}}`     | `{TARGET_PATH}/.vuln-scan/findings/code-review.json`     |
   | `{{DEPENDENCY_FINDINGS}}`      | `{TARGET_PATH}/.vuln-scan/findings/dependencies.json`    |
   | `{{SECRET_FINDINGS}}`          | `{TARGET_PATH}/.vuln-scan/findings/secrets.json`         |

4. Dispatch the prepared prompt as an Agent subagent. Description: `"Run Phase 7 validation"`.
5. Wait for the subagent to return.
6. Use the Read tool to load `{TARGET_PATH}/.vuln-scan/validated-findings.json`.
   - **If the file exists and is valid JSON:** store its contents as `VALIDATED_FINDINGS`. Append a `completed` log entry.
   - **If the file is missing or invalid:** store `VALIDATED_FINDINGS` as `{}`. Append a `failed` log entry. Do not abort.

---

## Step 8 — Phase 8: Reporting

**Goal:** Produce the final markdown and SARIF report files in `{TARGET_PATH}/.vuln-scan/`.

1. Use the Read tool to read `{SKILL_DIR}/phases/reporting.md`.
2. Perform these replacements:
   - Replace `{{VALIDATED_FINDINGS}}` with the contents of `VALIDATED_FINDINGS`.
   - Replace `{{REPO_PROFILE}}` with the contents of `REPO_PROFILE`.
   - Replace `{{THREAT_MODEL}}` with the contents of `THREAT_MODEL`.
3. Dispatch the prepared prompt as an Agent subagent. Description: `"Run Phase 8 reporting"`.
4. Wait for the subagent to return.
5. Append a `completed` or `failed` log entry to `scan.log`.

---

## Step 9 — Present Results

After Phase 8 completes, read `{TARGET_PATH}/.vuln-scan/validated-findings.json` and extract the summary section. Then output the following to the user:

```
vuln-scan complete for: {TARGET_PATH}

Findings summary:
  Critical : <count>
  High     : <count>
  Medium   : <count>
  Low      : <count>
  Total    : <count>

Reports written to:
  {TARGET_PATH}/.vuln-scan/SECURITY_REPORT.md
  {TARGET_PATH}/.vuln-scan/report.sarif

Scan log: {TARGET_PATH}/.vuln-scan/scan.log
```

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

**Phase names:** `coordinator`, `recon`, `threat-model`, `static-analysis`, `code-review`, `dependency-scan`, `secret-scan`, `validation`, `reporting`, `parallel-dispatch`

---

## Key Constraints

- **Never prompt the user** during execution. All decisions are defined in this document.
- **Never abort on phases 3–8 failures.** Partial results are always better than no results. Only Phase 1 (Recon) is a hard abort condition.
- **Skill directory resolution:** `{SKILL_DIR}` refers to the directory from which this SKILL.md was loaded. Phase prompts live in `{SKILL_DIR}/phases/`. When dispatching subagents, use absolute paths when reading phase files.
- **Template injection** is simple string replacement. Replace `{{PLACEHOLDER}}` literally with the substituted content. Do not interpret or transform the content.
- **Output directory** is always `{TARGET_PATH}/.vuln-scan/`. All phase output files are written there by the subagents — the coordinator only reads them.
- **Error messages** go to `scan.log` as JSON entries. Only surface errors to the user on a hard abort (Phase 1 failure) or in the final summary.
