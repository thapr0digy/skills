---
name: jira-submit
description: Submit vuln-scan findings to JIRA as tickets using the Atlassian MCP server. Presents findings for selection and creates issues with full detail. Invoke via /jira-submit.
user_invocable: true
---

# jira-submit — Submit Findings to JIRA

You are an interactive skill that submits vuln-scan findings to JIRA as tickets. Unlike other vuln-scan skills, this skill **prompts the user** at specific decision points.

---

## Step 1 — Locate Findings

Search for `vuln-scan-results/` directories under the current working directory.

```bash
find "{CWD}/vuln-scan-results" -name "validated-findings.json" -type f 2>/dev/null
```

If no results are found, output an error:
```
No vuln-scan results found. Run /vuln-scan first to generate findings.
```
Stop.

If exactly one `validated-findings.json` is found, use it automatically and note which target it belongs to (the parent directory name).

If multiple are found, present them to the user and ask which one to use:

```
Multiple scan results found:

  1. vuln-scan-results/myapp/
  2. vuln-scan-results/src-api/
  3. vuln-scan-results/other-repo/

Which scan results should I submit? (number):
```

Use the AskUserQuestion tool to get their choice.

---

## Step 2 — Load and Parse Findings

Read the selected `validated-findings.json` using the Read tool. Parse the JSON and extract:

- `findings` array — the validated findings
- `dismissed_findings` array — excluded from submission
- `metadata.repo` — repository name

If the findings array is empty, output:
```
No findings to submit — the scan produced zero validated findings.
```
Stop.

---

## Step 3 — Resolve Repository Slug

The JIRA ticket needs the full `org/repo` slug. Determine it by running:

```bash
cd "{TARGET_PATH}" && git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+/[^/]+?)(\.git)?$|\1|'
```

Where `{TARGET_PATH}` is inferred from the scan results directory name (reverse the sanitization: replace `-` with `/`, check if that path exists relative to CWD).

If the git remote cannot be determined, ask the user:

```
Could not detect the repository slug from git remote. What is the org/repo? (e.g., myorg/myapp):
```

Use the AskUserQuestion tool.

---

## Step 4 — Connect to JIRA

### 4a — Get Cloud ID

Call `mcp__atlassian__getAccessibleAtlassianResources` to get the list of accessible Atlassian sites. If there is exactly one site, use it. If multiple, ask the user which one.

Store the `cloudId` for all subsequent calls.

### 4b — Get Project

Ask the user which JIRA project to create tickets in:

```
Which JIRA project should I create tickets in? (e.g., SEC, VULN):
```

Use the AskUserQuestion tool.

After the user responds, validate the project exists by calling `mcp__atlassian__getVisibleJiraProjects` with `searchString` set to the user's input. If the project is not found, tell the user and ask again.

Store the `projectKey`.

### 4c — Determine Issue Type and Custom Fields

Call `mcp__atlassian__getJiraProjectIssueTypesMetadata` with the `projectKey` to list available issue types.

Look for an issue type that matches "Vulnerability", "Bug", or "Task" (in that priority order). If "Vulnerability" exists, use it. Otherwise fall back to "Bug", then "Task".

Then call `mcp__atlassian__getJiraIssueTypeMetaWithFields` with the `projectKey` and selected `issueTypeId` to get the available fields. Search the field metadata for custom fields matching these names (case-insensitive partial match):

| Target Field | Search Terms |
|---|---|
| Detection Source | `detection source` |
| Security Severity | `security severity` |
| Asset Type | `asset type` |
| Work Type | `work type` |
| Epic Link | `epic link`, `epic name` |
| Parent | `parent` |

For each matched field, record its `fieldId` (e.g., `customfield_10XXX`) and whether it accepts string values, select values (with `allowedValues`), or other types.

If a field is not found, skip it — not all JIRA projects have the same custom fields.

### 4d — Optional Parent/Epic Link

Ask the user:

```
Should these tickets be linked to a parent ticket or epic? Enter a JIRA key to link (e.g., SEC-42), or press Enter to skip:
```

Use the AskUserQuestion tool.

If the user provides a key:
- Call `mcp__atlassian__getJiraIssue` with `issueKey` set to the provided key and `cloudId`.
- If the issue is not found or an error is returned, tell the user and ask again (offer to skip).
- If found, store the key as `{PARENT_KEY}` and the issue type name as `{PARENT_ISSUE_TYPE}`.

Determine the linking strategy based on what was discovered in Step 4c:

| Condition | Strategy |
|---|---|
| `parent` field exists in issue metadata | Set `parent: { key: "{PARENT_KEY}" }` in `additional_fields` on create |
| `epic link` custom field exists | Set that custom field to `"{PARENT_KEY}"` in `additional_fields` on create |
| Neither field found | After each ticket is created, call `mcp__atlassian__createIssueLink` with link type `"Relates"` |

Store the determined strategy as `{LINK_STRATEGY}` (one of: `parent_field`, `epic_link_field`, `post_create_link`).

If the user skips (empty input), set `{PARENT_KEY}` to null and skip all linking.

---

## Step 5 — Present Findings for Selection

Display all findings grouped by severity with a numbered list:

```
Findings from vuln-scan-results/{target}/ ({repo_slug}):

  Critical:
    1. VULN-001 — Hardcoded database password in config/settings.py [exploitable]
  High:
    2. VULN-002 — SQL Injection via string concatenation [exploitable]
    3. VULN-003 — Broken access control on /api/users endpoint [undetermined]
  Medium:
    4. VULN-004 — Missing CSRF token on form submission [exploitable]
  Low:
    5. VULN-005 — Verbose error messages expose stack traces [undetermined]

  ({N} dismissed findings not shown)

Select findings to send (e.g., 1,3 or 1-4 or all or critical or critical+high):
```

Show the exploitability classification in brackets after each title. Show dismissed count at the bottom.

Use the AskUserQuestion tool to get the user's selection.

### Parse Selection

| Input | Meaning |
|---|---|
| `all` | All findings |
| `1,3,5` | Specific numbers |
| `1-4` | Range (inclusive) |
| `critical` | All findings with that severity |
| `critical+high` | Multiple severity levels (split on `+`) |
| `exploitable` | Only findings with `exploitability.classification == "exploitable"` |

Build the list of selected findings.

---

## Step 6 — Confirm and Create Tickets

Show a summary before creating:

```
Ready to create {N} JIRA tickets in {PROJECT_KEY}:

  VULN-001 — Hardcoded database password in config/settings.py (Critical)
  VULN-002 — SQL Injection via string concatenation (High)

{If PARENT_KEY is set:}
  Linked to: {PARENT_KEY} ({PARENT_ISSUE_TYPE})

Proceed? (yes/no):
```

Use the AskUserQuestion tool. If the user says no, stop.

### Create Tickets

For each selected finding, call `mcp__atlassian__createJiraIssue` with:

```json
{
  "cloudId": "{CLOUD_ID}",
  "projectKey": "{PROJECT_KEY}",
  "issueTypeName": "{ISSUE_TYPE_NAME}",
  "summary": "{finding.title}",
  "contentFormat": "markdown",
  "description": "<constructed from template below>",
  "additional_fields": {
    "<work_type_field_id>": <value>,
    "<detection_source_field_id>": <value>,
    "<security_severity_field_id>": <value>,
    "<asset_type_field_id>": <value>,
    "<repository_field_id>": <value>,
    "<if LINK_STRATEGY == parent_field>": { "parent": { "key": "{PARENT_KEY}" } },
    "<if LINK_STRATEGY == epic_link_field>": { "<epic_link_field_id>": "{PARENT_KEY}" }
  }
}
```

After a successful `createJiraIssue` call, if `{LINK_STRATEGY} == post_create_link` and `{PARENT_KEY}` is set:

Call `mcp__atlassian__createIssueLink` with:
```json
{
  "cloudId": "{CLOUD_ID}",
  "inwardIssueKey": "{NEWLY_CREATED_JIRA_KEY}",
  "outwardIssueKey": "{PARENT_KEY}",
  "linkTypeName": "Relates"
}
```

If the `createIssueLink` call fails (e.g., link type not found), retry once with `linkTypeName: "relates to"`. If it still fails, note it in the final report but do not abort the remaining tickets.

#### Description Construction

Read the JIRA finding template from `{SKILL_DIR}/../vuln-scan/templates/jira-finding.md` (relative to this skill's directory within the vuln-scan plugin). If the template file cannot be read, use the fallback format below.

**Fallback format** (markdown, since `contentFormat: "markdown"` is set):

```markdown
## {finding.title}

| Field | Value |
|---|---|
| ID | {finding.id} |
| Phase | {finding.phase} |
| Source Tool | {finding.source_tool} |
| Category | {finding.category} |
| CWE | {finding.cwe or "N/A"} |
| Severity | {finding.severity} |
| Confidence | {finding.confidence} |
| Exploitability | {finding.exploitability.classification or "N/A"} |

### Location

{For source findings:}
**File:** {finding.location.file}
**Lines:** {finding.location.line_start}–{finding.location.line_end}

{For dependency findings:}
**Manifest:** {finding.location.manifest_file}
**Package:** {finding.location.package}@{finding.location.installed_version}
**Fixed Version:** {finding.location.fixed_version or "No fix available"}
**CVSS:** {finding.location.cvss or "N/A"}

### Description

{vulnerability explanation portion of finding.description}

### Impact

{impact statement portion of finding.description, starting with "An attacker..."}

### Evidence

{finding.evidence or "No additional evidence recorded."}

{If finding.exploitability exists:}
### Exploitability Assessment

**Classification:** {finding.exploitability.classification}
**Reason:** {finding.exploitability.reason}
**Input Source:** {finding.exploitability.input_source}
**Sanitization:** {finding.exploitability.sanitization}

{If finding.data_flow exists:}
### Data Flow

| Step | File | Line | Role | Detail |
|---|---|---|---|---|
{For each df entry:}
| {index} | {df.file} | {df.line} | {df.role} | {df.label} |

{If finding.location.snippet exists:}
### Code Snippet

```
{finding.location.snippet}
```

### Remediation

{finding.remediation}

{If finding.references:}
### References

{For each ref:}
- {ref}
```

#### Custom Field Values

Set custom fields based on what was discovered in Step 4c. For each field:

| Field | Value |
|---|---|
| Work Type | `"Vulnerability"` — use the `allowedValues` entry matching this name if it's a select field, or the string if it's a text field |
| Detection Source | `"Penetration Test"` — same matching logic |
| Repository | `"{org/repo slug}"` — always a string |
| Security Severity | `"{finding.severity}"` — use the capitalized form (`"Critical"`, `"High"`, `"Medium"`, `"Low"`) if the field has allowedValues, otherwise use lowercase |
| Asset Type | `"Code"` — same matching logic as Work Type |

For select/option fields: match the `allowedValues[].value` or `allowedValues[].name` (case-insensitive). Use the full allowed value object (`{"id": "...", "value": "..."}` or `{"id": "..."}`) as required by the field schema.

If a custom field was not found in Step 4c, omit it from `additional_fields`.

### Rate Limiting

Wait 1 second between each `createJiraIssue` call to avoid hitting JIRA rate limits.

---

## Step 7 — Report Results

After all tickets are created, output:

```
Created {N} JIRA tickets in {PROJECT_KEY}:

  {JIRA_KEY}-123 — VULN-001 — Hardcoded database password in config/settings.py
  {JIRA_KEY}-124 — VULN-002 — SQL Injection via string concatenation
  {JIRA_KEY}-125 — VULN-003 — Broken access control on /api/users endpoint

{If PARENT_KEY is set:}
  All tickets linked to {PARENT_KEY}.

{If any link calls failed:}
  Link failures (tickets were still created):
    {JIRA_KEY}-123 — could not link to {PARENT_KEY}: {error reason}

{If any tickets failed to create:}
Failed to create:
  VULN-004 — Missing CSRF token: {error reason}
```

Extract the JIRA issue key from each `createJiraIssue` response.

---

## Key Constraints

- **This skill prompts the user** at specific steps (finding selection, project selection, parent/epic link, confirmation). This is intentional — unlike the autonomous vuln-scan phases.
- **Dismissed findings are never submitted.** Only validated findings from the `findings` array.
- **Custom field discovery is best-effort.** If a field doesn't exist in the JIRA project, skip it silently. The Summary and Description are the critical fields.
- **Description uses markdown format.** Set `contentFormat: "markdown"` on every `createJiraIssue` call.
- **Parent/epic linking is optional.** If the user skips it, no links are created. If linking fails, tickets are still reported as successfully created.
- **Do not create tickets without user confirmation.**
- **Split description the same way as reporting:** find the first sentence starting with "An attacker" to separate vulnerability explanation from impact statement.
