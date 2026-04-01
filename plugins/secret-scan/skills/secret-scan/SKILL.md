---
name: secret-scan
description: Standalone secret scanning — finds hardcoded secrets and leaked credentials using trufflehog. Can append results to existing vuln-scan reports. Invoke via /secret-scan [path].
user_invocable: true
---

# secret-scan — Coordinator

You are the orchestrator of a standalone secret scanning skill. When a user invokes `/secret-scan [path]`, follow every step below exactly. Make no decisions interactively — every choice is defined here. Do not prompt the user at any point during execution.

---

## Step 1 — Parse Arguments

Extract the target path from the skill invocation arguments.

- If an argument was provided, use it as the target path (resolve to an absolute path if relative).
- If no argument was provided, default to the current working directory.

Store this value as `TARGET_PATH` for all subsequent steps.

---

## Step 2 — Detect vuln-scan Results

Check if a `vuln-scan-results/` directory exists at the current working directory level.

```bash
[ -d "{CWD}/vuln-scan-results" ] && echo "exists" || echo "missing"
```

If it exists, determine whether there is a matching subdirectory for the target:

1. Compute the relative path of `TARGET_PATH` from the current working directory. If `TARGET_PATH` is the current working directory, use the directory's basename.
2. Replace path separators (`/`) with hyphens (`-`). Remove leading/trailing hyphens.
3. Check if `{CWD}/vuln-scan-results/{sanitized-name}/` exists.

If a matching vuln-scan results directory exists AND contains `repo-profile.json`:
- Set `VULN_SCAN_DIR` to `{CWD}/vuln-scan-results/{sanitized-name}`
- Set `APPEND_MODE` to `true`

Otherwise:
- Set `APPEND_MODE` to `false`

---

## Step 3 — Setup Output

### If APPEND_MODE is true

- Set `OUTPUT_DIR` to `VULN_SCAN_DIR` (write findings into the existing vuln-scan results directory).
- Do NOT wipe the directory — only create the `findings/` subdirectory if it does not already exist:
  ```bash
  mkdir -p "{OUTPUT_DIR}/findings"
  ```
- Use the Read tool to load `{OUTPUT_DIR}/repo-profile.json`. Store its contents as `REPO_PROFILE`.

### If APPEND_MODE is false

- Compute the sanitized target name using the same logic as Step 2.
- Set `OUTPUT_DIR` to `{CWD}/secret-scan-results/{sanitized-target-name}/`.
- Create the output directory:
  ```bash
  mkdir -p "{OUTPUT_DIR}/findings"
  ```
- Set `REPO_PROFILE` to `{}` (no repo profile available).

### Initialize scan.log

Append to `{OUTPUT_DIR}/scan.log` if it exists, or create it if not. Write the following JSON line:

```json
{"ts": "<ISO 8601>", "phase": "secret-scan-coordinator", "event": "start", "target": "<TARGET_PATH>", "append_mode": <true|false>}
```

---

## Step 4 — Run Secret Scan

1. Use the Read tool to read the file at `{SKILL_DIR}/phases/scan.md` where `{SKILL_DIR}` is the directory containing this SKILL.md file.
2. In the loaded text, perform these replacements:
   - Replace `{{TARGET_PATH}}` with the actual value of `TARGET_PATH`.
   - Replace `{{OUTPUT_DIR}}` with the actual value of `OUTPUT_DIR`.
   - Replace `{{REPO_PROFILE}}` with the contents of `REPO_PROFILE`.
   - Replace `{{SERVICES}}` with the `services` array extracted from `REPO_PROFILE` (as a JSON array string). If `REPO_PROFILE` is `{}` or does not contain a `services` key, or if `is_monorepo` is `false`, replace `{{SERVICES}}` with `[]`.
3. Dispatch the prepared prompt as a subagent using the Agent tool. Description: `"Run secret scan"`.
4. Wait for the subagent to return.
5. Append a log entry to `{OUTPUT_DIR}/scan.log`:
   - On success: `{"ts": "<timestamp>", "phase": "secret-scan", "event": "completed", "duration_s": <elapsed>}`
   - On failure: `{"ts": "<timestamp>", "phase": "secret-scan", "event": "failed", "reason": "<short reason>"}`

---

## Step 5 — Re-run Validation and Reporting (Append Mode Only)

**If `APPEND_MODE` is false:** skip this step entirely — proceed to Step 6.

**If `APPEND_MODE` is true AND `{OUTPUT_DIR}/findings/secrets.json` was created (file exists and is valid JSON):**

### 5a — Re-run Validation

1. Use the Read tool to read the vuln-scan validation phase prompt from the absolute path: `{CWD}/plugins/vuln-scan/skills/vuln-scan/phases/validation.md`

   If this file cannot be read (e.g., vuln-scan plugin is not installed at the expected path), log a warning and skip to Step 6:
   ```json
   {"ts": "<timestamp>", "phase": "secret-scan-coordinator", "event": "skipped", "reason": "vuln-scan validation phase not found, skipping re-validation"}
   ```

2. Perform all template replacements on the loaded text:
   - `{{THREAT_MODEL}}`: read from `{OUTPUT_DIR}/threat-model.json` if it exists, otherwise use `{}`
   - `{{OUTPUT_DIR}}`: the output directory path
   - `{{FINDINGS_DIR}}`: `{OUTPUT_DIR}/findings`
   - `{{STATIC_ANALYSIS_FINDINGS}}`: read from `{OUTPUT_DIR}/findings/static-analysis.json` if it exists, otherwise leave placeholder as-is
   - `{{CODE_REVIEW_FINDINGS}}`: read from `{OUTPUT_DIR}/findings/code-review.json` if it exists, otherwise leave placeholder as-is
   - `{{DEPENDENCY_FINDINGS}}`: read from `{OUTPUT_DIR}/findings/dependencies.json` if it exists, otherwise leave placeholder as-is
   - `{{SECRET_FINDINGS}}`: read from `{OUTPUT_DIR}/findings/secrets.json`
   - `{{SERVICES}}`: from `REPO_PROFILE` services array, or `[]`

3. Dispatch the prepared prompt as a subagent using the Agent tool. Description: `"Re-run validation with secrets"`.
4. Wait for the subagent to return.
5. Append a log entry to `{OUTPUT_DIR}/scan.log`:
   - On success: `{"ts": "<timestamp>", "phase": "validation", "event": "completed", "duration_s": <elapsed>}`
   - On failure: `{"ts": "<timestamp>", "phase": "validation", "event": "failed", "reason": "<short reason>"}`

### 5b — Re-run Reporting

1. Use the Read tool to read the vuln-scan reporting phase prompt from the absolute path: `{CWD}/plugins/vuln-scan/skills/vuln-scan/phases/reporting.md`

   If this file cannot be read, log a warning and skip:
   ```json
   {"ts": "<timestamp>", "phase": "secret-scan-coordinator", "event": "skipped", "reason": "vuln-scan reporting phase not found, skipping re-reporting"}
   ```

2. Perform all template replacements:
   - `{{VALIDATED_FINDINGS}}`: read from `{OUTPUT_DIR}/validated-findings.json` if it exists, otherwise use `{}`
   - `{{REPO_PROFILE}}`: the contents of `REPO_PROFILE`
   - `{{THREAT_MODEL}}`: read from `{OUTPUT_DIR}/threat-model.json` if it exists, otherwise use `{}`
   - `{{OUTPUT_DIR}}`: the output directory path
   - `{{SERVICES}}`: from `REPO_PROFILE` services array, or `[]`

3. Dispatch the prepared prompt as a subagent using the Agent tool. Description: `"Re-run reporting with secrets"`.
4. Wait for the subagent to return.
5. Append a log entry to `{OUTPUT_DIR}/scan.log`:
   - On success: `{"ts": "<timestamp>", "phase": "reporting", "event": "completed", "duration_s": <elapsed>}`
   - On failure: `{"ts": "<timestamp>", "phase": "reporting", "event": "failed", "reason": "<short reason>"}`

### Error Handling for Step 5

If re-validation or re-reporting fails, preserve the original report files and note the failure. Do not delete or corrupt any existing vuln-scan output. Log the failure and continue to Step 6.

---

## Step 6 — Present Results

### If APPEND_MODE is true

1. Read `{OUTPUT_DIR}/validated-findings.json` and extract the summary section.
2. Output to the user:

```
Secret scan complete. Findings appended to vuln-scan report at {OUTPUT_DIR}/

Findings summary:
  Critical : <count>
  High     : <count>
  Medium   : <count>
  Low      : <count>
  Total    : <count>

Updated reports:
  {OUTPUT_DIR}/SECURITY_REPORT.md
  {OUTPUT_DIR}/report.sarif
```

If `validated-findings.json` is absent or unparseable, note that re-validation was unavailable and show the raw secret findings count from `findings/secrets.json` instead.

### If APPEND_MODE is false

1. Read `{OUTPUT_DIR}/findings/secrets.json`.
2. Count the number of findings.
3. Output to the user:

```
Secret scan complete for {TARGET_PATH}. Found N secrets.

Results: {OUTPUT_DIR}/findings/secrets.json

Tip: Run /vuln-scan first to get a full security report with secret findings integrated.
```

### Final log entry

Append to `{OUTPUT_DIR}/scan.log`:

```json
{"ts": "<ISO 8601>", "phase": "secret-scan-coordinator", "event": "completed", "duration_s": <total elapsed since start>}
```

---

## Key Constraints

- **Never prompt the user** during execution. All decisions are defined in this document.
- **Skill directory resolution:** `{SKILL_DIR}` refers to the directory containing this SKILL.md file. Phase prompts for this skill live in `{SKILL_DIR}/phases/`. When reading vuln-scan phase prompts (validation.md, reporting.md) in append mode, use the absolute path `{CWD}/plugins/vuln-scan/skills/vuln-scan/phases/`.
- **Template injection** is simple string replacement. Replace `{{PLACEHOLDER}}` literally with the substituted content. Do not interpret or transform the content.
- **Output directory** is always `{OUTPUT_DIR}/`. All output files are written there by subagents — the coordinator only reads them.
- **Write boundary:** Subagents must only write files inside `{OUTPUT_DIR}/`. If a subagent writes or modifies any file outside this boundary, it must revert the change and log a violation entry.
- **Append mode safety:** When writing into an existing vuln-scan results directory, never delete or overwrite files other than `findings/secrets.json`, `validated-findings.json`, `SECURITY_REPORT.md`, and `report.sarif`. Preserve all other files (repo-profile.json, threat-model.json, other findings files, config.json).
- **Error messages** go to `scan.log` as JSON entries. Only surface errors to the user in the final summary.
