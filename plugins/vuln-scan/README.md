# vuln-scan

Autonomous vulnerability scanning pipeline for Claude Code. Scans code repositories for security vulnerabilities and produces actionable reports.

## Installation

```bash
claude plugins add github:pr0digy/vuln-scan
```

### Recommended external tools

These enhance scan quality but are not required:

```bash
# Static analysis (strongly recommended)
pip install semgrep

# Secret detection
pip install trufflehog

# Language-specific dependency scanning
pip install pip-audit          # Python
# npm is included with Node.js  # JavaScript
go install golang.org/x/vuln/cmd/govulncheck@latest  # Go
cargo install cargo-audit      # Rust
```

### Recommended Claude Code plugins

These are invoked automatically when installed:

```bash
claude plugins add trailofbits/static-analysis
claude plugins add trailofbits/semgrep-rule-creator
claude plugins add trailofbits/audit-context-building
claude plugins add trailofbits/sharp-edges
claude plugins add skills-curated/openai-security-threat-model
```

## Usage

```bash
# Scan current directory
/vuln-scan

# Scan a specific repository
/vuln-scan /path/to/repo
```

## Output

Results are written to `.vuln-scan/` in the target repository:

| File | Description |
|------|-------------|
| `SECURITY_REPORT.md` | Human-readable report with findings, remediation, and threat model |
| `report.sarif` | SARIF v2.1.0 for import into GitHub Advanced Security, Defect Dojo, etc. |
| `validated-findings.json` | Machine-readable findings with full metadata |
| `scan.log` | Scan execution log |

## How it works

vuln-scan runs an 8-phase pipeline:

1. **Recon** — structural analysis of the repository
2. **Threat Model** — STRIDE-based threat modeling
3. **Static Analysis** — Semgrep with community + auto-generated custom rules
4. **LLM Code Review** — deep security-focused code review
5. **Dependency Scan** — known CVEs in dependencies
6. **Secret Detection** — hardcoded secrets in code and git history
7. **Validation** — merge, deduplicate, and assign confidence tiers
8. **Reporting** — generate markdown + SARIF output

Phases 3-6 run in parallel for speed. The pipeline requires zero human interaction.

## Findings

Each finding includes:
- **Severity**: critical, high, medium, low
- **Confidence**: confirmed (verified), likely (strong signal), possible (weak signal)
- **Category**: OWASP Top 10 (2021) taxonomy
- **CWE**: Common Weakness Enumeration ID
- **Remediation**: actionable fix guidance

## License

MIT
