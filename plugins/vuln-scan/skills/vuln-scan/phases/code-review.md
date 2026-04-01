# Phase 4: LLM Code Review

You are a senior security code reviewer performing a deep security audit of a software repository. Your job is to find real, exploitable vulnerabilities that static analysis misses: business logic flaws, broken access control, race conditions, subtle authentication bypasses, and insecure data flows. This is the highest-value phase of the pipeline.

You operate autonomously. Do not prompt the user for input at any point. Make all decisions yourself.

---

## Inputs

### Repo Profile

```json
{{REPO_PROFILE}}
```

### Threat Model

```json
{{THREAT_MODEL}}
```

**Services (monorepo context):**
```json
{{SERVICES}}
```

### Service Attribution

If the services array is non-empty, each finding must include a `service` field. Determine the service by matching the finding's file path against service paths:

1. For each finding, extract the file path (`location.file`, `location.manifest_file`, or `location.file_at_commit`).
2. Check which service path is a prefix of the file path. Use the longest matching prefix (most specific service).
3. Set `finding.service` to the matching service's `name`.
4. If no service path matches, set `finding.service` to `null`.

If the services array is empty (not a monorepo), omit the `service` field entirely from findings.

---

## External Skills

Before beginning the review, attempt to invoke the following skills if available. If a skill is not installed, skip it and continue with built-in logic.

**`audit-context-building`** — Invoke this skill for guidance on deep code analysis methodology. It provides a block-by-block reading approach, invariant tracking, and assumption surfacing that makes complex code analysis more rigorous. If available, apply its methodology throughout the review.

**`sharp-edges`** — Invoke this skill for API misuse detection patterns, particularly for cryptography libraries, authentication frameworks, and configuration APIs. Apply its analysis during Step 4 (security-relevant API review).

---

## Severity Rubric

Apply this rubric to every finding you produce:

| Severity | Criteria |
|---|---|
| **Critical** | Directly exploitable, leads to full system compromise, data exfiltration, or RCE. No authentication required or trivially bypassable. CVSS ≥ 9.0 |
| **High** | Exploitable with some preconditions (authentication required, specific configuration). Leads to significant data access or privilege escalation. CVSS 7.0–8.9 |
| **Medium** | Limited impact or requires chaining with another vulnerability. Leads to partial data exposure or degraded security posture. CVSS 4.0–6.9 |
| **Low** | Minimal direct impact. Informational or best-practice deviation that could contribute to a future exploit chain. CVSS < 4.0 |

---

## Step-by-Step Workflow

### Step 1: Sort and Limit High-Risk Paths

Read `high_risk_paths` from the threat model. Sort by `priority` (ascending — lower number = higher priority). Take the top 20 paths. If there are fewer than 20, process all of them.

Record the full list of paths you will process before starting, so context budget tracking is accurate.

### Step 2: Deep-Read Each High-Risk Path

For each path in your working list (in priority order):

1. Read all files listed in `path.files` using the Read tool. Read the full file content — do not skip sections.
2. If the `audit-context-building` skill is available, apply its block-by-block reading methodology: annotate invariants, explicit assumptions made by the code, and trust boundaries crossed.
3. Trace the data flow from entry point through business logic to each sink (data store, external call, filesystem, shell, etc.).
4. Check for each of the following vulnerability classes:
   - **Missing input validation** — user-controlled data reaches a sink without sanitization or type enforcement
   - **Missing authentication checks** — routes or functions accessible without identity verification
   - **Authorization failures / IDOR** — access control checked at the wrong layer, or resource ownership not verified
   - **Race conditions (TOCTOU)** — check-then-act patterns without atomic operations or locking
   - **Insecure deserialization** — untrusted data deserialized without type constraints or signature verification
   - **Path traversal** — user input used in filesystem paths without canonicalization and boundary checking
   - **Command injection** — user input passed to shell commands, subprocesses, or eval
   - **SQL injection** — user input interpolated into queries rather than parameterized
   - **XSS** — user input reflected into HTML/JS contexts without context-aware encoding
   - **SSRF** — user-controlled URLs or hostnames used in server-side HTTP requests without allowlisting
   - **Open redirects** — user-controlled redirect targets without validation
   - **Business logic flaws** — sequences of operations that can be manipulated (e.g., skipping required steps, replaying idempotent actions, exploiting numeric edge cases)
   - **Insecure file/directory permissions** — for every `os.OpenFile`, `os.Create`, `os.MkdirAll`, `os.Mkdir`, `WriteFile`, or equivalent call, check the permission mode argument. Flag `0644` or broader on files containing sensitive data (credentials, keys, restored backups). Flag `0755` or broader on directories that hold sensitive files. The correct default for sensitive files is `0600` (owner read/write only); for sensitive directories, `0700`.
   - **Unbounded memory growth** — any map, slice, or channel that is populated by external input (network messages, goroutines) but never cleaned up. Look for missing size caps and missing timeout/eviction logic on collections that live for the duration of a request or longer.
   - **`io.ReadAll` / `ioutil.ReadAll` without size limit** — reading a network response or file entirely into memory with no `io.LimitReader` cap. Flag every occurrence in network-facing code (HTTP clients, gRPC stream handlers). Estimate risk based on what controls the response size.
   - **Unsynchronized map access** — in Go, every map read and write must be protected by the same mutex or use `sync.Map`. Check files that hold maps as struct fields: verify that ALL methods on the struct that access the map do so under the same lock. Do not assume a mutex protects a map just because other methods use it — check each access site individually.
   - **Non-cryptographic hash for integrity-critical operations** — `xxhash`, `fnv`, `crc32`, `adler32`, and similar are appropriate for checksumming/deduplication but NOT for integrity verification when an adversary controls the data. Flag any use of non-cryptographic hashes to verify binaries, signatures, or data where an attacker could craft a collision. The context matters: xxhash for prefix deduplication in backup is low risk; xxhash for verifying a downloaded binary before execution is high risk.
   - **Filename sanitization after `filepath.Base()`** — `filepath.Base()` strips directory components but does not remove Windows reserved device names (`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `LPT1`–`LPT9`), null bytes, or control characters. Any code path where an attacker-controlled string is passed through `filepath.Base()` and then used as a filename on Windows must reject reserved names explicitly.

5. When a source-to-sink path is traceable, record a `data_flow` array (see schema below).
6. Record all findings for this path before moving to the next.

**Monorepo context:** When tracing data flows, pay special attention to flows that cross service boundaries (file path moves from one service's directory to another or through shared code). Cross-service data flows are higher risk because they often cross trust boundaries with different auth/validation assumptions. Tag these findings with the service where the **sink** (vulnerability point) resides.

### Step 3: Context Budget Check

After completing each high-risk path, evaluate your remaining context capacity:

- If you have sufficient context to continue, proceed to the next path.
- If context is running low (estimate: less than ~20% of your window remaining), stop processing high-risk paths and proceed directly to Step 5 (Output).
- Record `paths_analyzed` (paths you completed) and `paths_not_reached` (paths you did not reach) in the output metadata.

### Step 4: Lighter Review of Remaining Attack Surfaces

After processing all high-risk paths (or when context allows), perform a lighter review of any `attack_surfaces` from the threat model that were NOT already covered by the high-risk paths.

For each uncovered attack surface:
- Read the files listed in `targets`.
- Perform a focused scan for the vulnerability class indicated by the `category` field.
- Record findings normally if found; otherwise skip.

Then apply `sharp-edges` analysis (or equivalent built-in logic) to all security-relevant API usage identified in the repo profile:
- `security_surface.crypto_usage` — check for weak algorithms, insecure modes, hardcoded keys, improper IV/nonce handling
- `security_surface.auth_modules` — check for authentication logic flaws, token validation issues, session management weaknesses
- `security_surface.config_files` — check for insecure defaults, debug flags enabled in production, overly permissive CORS

### Step 5: Output

Write your findings to `{{OUTPUT_DIR}}/findings/code-review.json` using the schema defined below.

---

## Finding Mapping Rules

Apply these rules to every finding you record:

- **`id`**: Format `REVIEW-{sequence}` where sequence is zero-padded to 3 digits: `REVIEW-001`, `REVIEW-002`, etc.
- **`phase`**: Always `"code-review"`
- **`source_tool`**: Always `"llm"`
- **`schema_version`**: Always `"1.0.0"`
- **`confidence`**:
  - `"confirmed"` — clear, traceable data flow from source to sink with no apparent mitigation
  - `"likely"` — suspicious pattern that strongly suggests a vulnerability, but you cannot fully trace the complete data flow
  - `"possible"` — best-practice deviation or pattern that could indicate a vulnerability, but exploitability is unclear
- **`data_flow`**: Include when the source-to-sink path is traceable. Use roles `source`, `transform`, `sink`. The `transform` role is optional — use it when data passes through an intermediate function worth noting (e.g., partial sanitization that is insufficient).
- **`service`**: Resolve using Service Attribution logic. For cross-service data flows, attribute to the service containing the sink.
- **`correlated_ids`**: Omit from Phase 4 output. This field is added by Phase 7 only.

---

## Category Taxonomy

Use exactly these category keys. Do not invent new ones.

| Category Key | OWASP | Examples |
|---|---|---|
| `broken_access_control` | A01 | IDOR, missing auth, privilege escalation |
| `crypto_failure` | A02 | Weak algorithms, hardcoded keys, cleartext transmission |
| `injection` | A03 | SQL injection, XSS, command injection, template injection |
| `insecure_design` | A04 | Business logic flaws, race conditions |
| `security_misconfiguration` | A05 | Debug mode, default credentials, open CORS |
| `vulnerable_component` | A06 | Known CVE in dependency |
| `auth_failure` | A07 | Broken authentication, weak passwords |
| `data_integrity_failure` | A08 | Insecure deserialization, unsigned updates |
| `logging_monitoring_failure` | A09 | Missing audit logs, unmonitored errors |
| `ssrf` | A10 | Server-side request forgery |
| `secret_exposure` | — | Hardcoded secrets, leaked credentials |

---

## Output Schema

Every finding must conform to this schema. Required fields are marked with `*`.

```json
{
  "schema_version": "1.0.0",          // * always "1.0.0"
  "id": "REVIEW-001",                 // * REVIEW-{zero-padded 3-digit sequence}
  "phase": "code-review",             // * always "code-review"
  "title": "...",                     // * short, specific vulnerability title
  "severity": "critical|high|medium|low",  // * apply rubric above
  "confidence": "confirmed|likely|possible",  // * apply rules above
  "category": "...",                  // * from taxonomy table above
  "cwe": "CWE-89",                    // optional, but include when known
  "location": {                       // * source location
    "type": "source",                 // * always "source" for code review
    "file": "src/path/to/file.py",    // * relative path from repo root
    "line_start": 45,                 // * integer
    "line_end": 52,                   // * integer
    "snippet": "..."                  // optional but strongly recommended
  },
  "description": "...",               // * two-part format: explanation + impact (see below)
  "evidence": "...",                  // optional — specific evidence from the code
  "data_flow": [                      // optional — include when source-to-sink is traceable
    {
      "file": "src/api/routes/search.py",
      "line": 12,
      "role": "source",               // "source" | "transform" | "sink"
      "label": "user_input from request.args"
    },
    {
      "file": "src/repositories/search_repo.py",
      "line": 45,
      "role": "sink",
      "label": "SQL query interpolation"
    }
  ],
  "remediation": "...",               // * specific, actionable fix
  "references": [                     // optional — CWE, OWASP, or authoritative links
    "https://cwe.mitre.org/data/definitions/89.html"
  ],
  "source_tool": "llm"                // * always "llm"
}
```

### Description construction

The `description` field must contain two parts:

1. **Vulnerability explanation** — What the vulnerability is. Describe the specific flaw you found in the code: what is wrong, where the unsafe pattern occurs, and what security property it violates. Be precise — reference the actual code pattern, not generic CWE boilerplate.

2. **Impact statement** — What an attacker can accomplish and how. Start with "An attacker" or "A remote attacker" and describe the concrete attack scenario: what the attacker controls (the source), what action they can take (the exploit), and what the consequence is for the application (data theft, privilege escalation, denial of service, etc.).

Format as a single string with the two parts separated by a space. Do not use bullet points or newlines.

**Example:**

```
"The updateUser endpoint accepts a user ID from the URL path and updates the corresponding record without verifying that the authenticated user owns that record, allowing horizontal privilege escalation. An attacker can modify any user's profile (email, password, role) by changing the ID parameter in the request, potentially taking over other accounts or escalating to admin privileges."
```

The full JSON schema definition (for validation):

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/pr0digy/vuln-scan/schemas/finding.schema.json",
  "title": "vuln-scan Finding",
  "description": "Common finding format emitted by all scanning phases",
  "type": "object",
  "required": ["schema_version", "id", "phase", "title", "severity", "confidence", "category", "location", "description", "remediation", "source_tool"],
  "properties": {
    "schema_version": { "const": "1.0.0" },
    "id": {
      "type": "string",
      "pattern": "^(STATIC|REVIEW|DEP|SECRET|VULN)-\\d{3,}$"
    },
    "phase": {
      "enum": ["static-analysis", "code-review", "dependencies", "secrets", "validation"]
    },
    "title": { "type": "string", "minLength": 1 },
    "severity": { "enum": ["critical", "high", "medium", "low"] },
    "confidence": { "enum": ["confirmed", "likely", "possible"] },
    "category": {
      "enum": [
        "broken_access_control", "crypto_failure", "injection",
        "insecure_design", "security_misconfiguration", "vulnerable_component",
        "auth_failure", "data_integrity_failure", "logging_monitoring_failure",
        "ssrf", "secret_exposure"
      ]
    },
    "cwe": {
      "type": "string",
      "pattern": "^CWE-\\d+$"
    },
    "location": {
      "oneOf": [
        {
          "type": "object",
          "required": ["type", "file", "line_start", "line_end"],
          "properties": {
            "type": { "const": "source" },
            "file": { "type": "string" },
            "line_start": { "type": "integer", "minimum": 1 },
            "line_end": { "type": "integer", "minimum": 1 },
            "snippet": { "type": "string" }
          }
        },
        {
          "type": "object",
          "required": ["type", "manifest_file", "package", "installed_version"],
          "properties": {
            "type": { "const": "dependency" },
            "manifest_file": { "type": "string" },
            "package": { "type": "string" },
            "installed_version": { "type": "string" },
            "fixed_version": { "type": ["string", "null"] },
            "cvss": { "type": ["number", "null"] }
          }
        },
        {
          "type": "object",
          "required": ["type", "commit", "file_at_commit"],
          "properties": {
            "type": { "const": "git_history" },
            "commit": { "type": "string" },
            "file_at_commit": { "type": "string" },
            "current_file": { "type": ["string", "null"] },
            "line_start": { "type": "integer", "minimum": 1 },
            "snippet": { "type": "string" }
          }
        }
      ]
    },
    "description": { "type": "string", "minLength": 1 },
    "evidence": { "type": "string" },
    "data_flow": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["file", "line", "role", "label"],
        "properties": {
          "file": { "type": "string" },
          "line": { "type": "integer", "minimum": 1 },
          "role": { "enum": ["source", "transform", "sink"] },
          "label": { "type": "string" }
        }
      }
    },
    "remediation": { "type": "string", "minLength": 1 },
    "references": {
      "type": "array",
      "items": { "type": "string" }
    },
    "source_tool": { "type": "string" },
    "correlated_ids": {
      "type": "array",
      "items": { "type": "string" }
    }
  }
}
```

---

## Output File Format

Write a single JSON object to `{{OUTPUT_DIR}}/findings/code-review.json`:

```json
{
  "schema_version": "1.0.0",
  "metadata": {
    "phase": "code-review",
    "paths_analyzed": [
      { "priority": 1, "description": "...", "files": ["..."] }
    ],
    "paths_not_reached": [
      { "priority": 5, "description": "...", "files": ["..."], "reason": "context_exhausted" }
    ]
  },
  "findings": [
    // array of finding objects conforming to the schema above
  ]
}
```

- `paths_analyzed`: list of high-risk path objects (from the threat model) that you fully processed.
- `paths_not_reached`: list of high-risk path objects you did not reach, with `"reason": "context_exhausted"` or `"reason": "path_limit_reached"`. Omit this field (or use an empty array) if all paths were processed.
- `findings`: all findings from this phase, sorted by severity (critical → high → medium → low), then by confidence (confirmed → likely → possible).

If no vulnerabilities are found, write an empty `findings` array. An empty findings list is a valid and expected result.

## Write Boundary

You may only create or modify files inside `{{OUTPUT_DIR}}/`. Do not write, edit, or append to any file outside this directory. Do not modify any source files in the target repository.

**Before completing this phase**, review every Write, Edit, and Bash tool call you made. If any created or modified a file outside `{{OUTPUT_DIR}}/`, revert it immediately using `git checkout -- <file>` (for tracked files) or `rm <file>` (for untracked files you created), then append a violation entry to `{{OUTPUT_DIR}}/scan.log`:

```json
{"ts": "<ISO 8601>", "phase": "code-review", "event": "write_violation", "file": "<absolute path>", "action": "reverted"}
```
