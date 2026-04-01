# JIRA Finding Template

This template defines the field mapping for creating JIRA tickets from vuln-scan findings. Each validated finding (from `validated-findings.json`) maps to one JIRA ticket.

## Field Mapping

| JIRA Field | Source | Description |
|---|---|---|
| **Work Type** | `"Vulnerability"` | Fixed value |
| **Summary** | `finding.title` | The finding title as-is |
| **Description** | See template below | Full finding detail |
| **Detection Source** | `"Penetration Test"` | Fixed value |
| **Repository** | `{org}/{repo}` | Full org/repo slug from git remote |
| **Security Severity** | `finding.severity` | Maps 1:1: `critical`, `high`, `medium`, `low` |
| **Asset Type** | `"Code"` | Fixed value |

## Repository Slug Resolution

Extract the org/repo slug from the target repository's git remote:

```bash
cd "{TARGET_PATH}" && git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+/[^/]+?)(\.git)?$|\1|'
```

If the remote URL is not available, fall back to `"unknown/{repo.name}"` using the repo name from `repo-profile.json`.

## Description Template

The JIRA description field uses the following format. All values are sourced from the validated finding object.

```
h2. {finding.title}

||Field||Value||
|ID|{finding.id}|
|Phase|{finding.phase}|
|Source Tool|{finding.source_tool}|
|Category|{finding.category}|
|CWE|{finding.cwe or "N/A"}|
|Severity|{finding.severity}|
|Confidence|{finding.confidence}|
|Exploitability|{finding.exploitability.classification or "N/A"}|

h3. Location

{For source findings:}
File: {{finding.location.file}}
Lines: {finding.location.line_start}–{finding.location.line_end}

{For dependency findings:}
Manifest: {finding.location.manifest_file}
Package: {finding.location.package}@{finding.location.installed_version}
Fixed Version: {finding.location.fixed_version or "No fix available"}
CVSS: {finding.location.cvss or "N/A"}

{For git_history findings:}
Commit: {finding.location.commit}
File at Commit: {finding.location.file_at_commit}
Current File: {finding.location.current_file or "Deleted"}

h3. Description

{finding.description — vulnerability explanation portion}

h3. Impact

{finding.description — impact statement portion, starting with "An attacker..."}

h3. Evidence

{finding.evidence or "No additional evidence recorded."}

{If finding.exploitability exists:}
h3. Exploitability Assessment

Classification: {finding.exploitability.classification}
Reason: {finding.exploitability.reason}
Input Source: {finding.exploitability.input_source}
Sanitization: {finding.exploitability.sanitization}

{If finding.data_flow exists and is non-empty:}
h3. Data Flow

||Step||File||Line||Role||Detail||
{For each entry in finding.data_flow:}
|{index}|{df.file}|{df.line}|{df.role}|{df.label}|

{If finding.location.snippet exists:}
h3. Code Snippet

{code}
{finding.location.snippet}
{code}

h3. Remediation

{finding.remediation}

{If finding.references is non-empty:}
h3. References

{For each ref in finding.references:}
* {ref}

{If finding.correlated_ids is non-empty:}
h3. Correlated Findings

The following scan IDs were merged into this finding: {finding.correlated_ids joined with ", "}

{If finding.blast_radius exists:}
h3. Blast Radius

This vulnerability is in shared code ({finding.blast_radius.shared_service}) and affects: {finding.blast_radius.affected_services joined with ", "}
```

## Notes

- Split the `description` field into Description and Impact sections using the same rule as the SECURITY_REPORT: find the first sentence starting with "An attacker" or "A remote attacker" — everything before is the description, everything from that sentence onward is the impact.
- The description template uses JIRA wiki markup (`h2.`, `h3.`, `||header||`, `|cell|`, `{code}`, `*` for bullets).
- One ticket per validated finding. Dismissed findings (from `dismissed_findings`) do not get tickets.
- If a finding has `exploitability.classification` of `undetermined`, include the exploitability section so the assignee can investigate.
