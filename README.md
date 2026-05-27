# Claude Code Plugins

A marketplace of Claude Code plugins for offensive security, penetration testing, and vulnerability analysis.

## Installation

```bash
/plugin marketplace add thapr0digy/skills
```

Then install individual plugins:

```bash
/plugin install <plugin-name>@thapr0digy
```

## Available Plugins

### Security Scanning

| Plugin | Description |
|--------|-------------|
| [vuln-scan](plugins/vuln-scan/) | Autonomous 8-phase vulnerability scanning pipeline (recon, threat model, static analysis, LLM review, dep scan, secret detection, validation, reporting). |
| [secret-scan](plugins/secret-scan/) | Standalone secret scanning with trufflehog. Can append results to existing vuln-scan reports. |
| [dep-graph](plugins/dep-graph/) | Scans a parent directory of git repos and generates an interactive D3.js dependency graph. |

### Development Workflow

| Plugin | Description |
|--------|-------------|
| [verify-spec](plugins/verify-spec/) | Reality-checks a freshly written spec/plan against code, docs, and API specs using parallel read-only agents, then applies approved corrections. Wired into the superpowers brainstorming/writing-plans pipeline. |

### Penetration Testing Suite

A modular set of plugins covering the full offensive security engagement lifecycle, with built-in safety policies for sensitive data handling and credential validation.

| Plugin | Description |
|--------|-------------|
| [pentest-core](plugins/pentest-core/) | Engagement management, scope validation, remote execution, evidence organization, Plextrac-compatible export, and shared safety policies. |
| [pentest-recon](plugins/pentest-recon/) | Passive and active reconnaissance — two-phase port scanning, subdomain enumeration, service fingerprinting, OSINT, JS analysis, attack surface discovery. |
| [pentest-enum](plugins/pentest-enum/) | Enumeration of web apps (ffuf + katana + httpx), network services, JS analysis (auto-triggered), and cloud infrastructure. |
| [pentest-analysis](plugins/pentest-analysis/) | Target prioritization — synthesizes recon/enum/scan data to recommend high-value attack paths. |
| [pentest-scanning](plugins/pentest-scanning/) | Nuclei-based vulnerability scanning with tech-stack-aware template selection and custom template generation. |
| [pentest-exploit](plugins/pentest-exploit/) | Exploitation guidance, payload generation, and credential attacks with tiered sensitive data access controls. |
| [pentest-postexploit](plugins/pentest-postexploit/) | Active Directory attack chains, privilege escalation, tiered lateral movement, loot collection, and detection rules. |
| [pentest-evasion](plugins/pentest-evasion/) | Defense evasion — payload obfuscation, AMSI/ETW bypass, LOLBins, process injection, C2 comms. **RoE-gated.** |
| [pentest-social](plugins/pentest-social/) | Phishing campaign setup, email templates, infrastructure configuration, results parsing. **RoE-gated.** |
| [pentest-utility](plugins/pentest-utility/) | Finding report writing, engagement cleanup checklists, remediation retesting. |

## Safety Policies

The pentest suite enforces two shared safety policies across all skills that handle credentials or sensitive data:

### Sensitive Data Policy

Defines a 3-tier validation hierarchy to minimize unnecessary exposure of PII, PHI, and financial data:

| Tier | What it does | Example |
|------|-------------|---------|
| **1 — Metadata** | Proves access exists using structure only | `sqlmap --dbs`, `--tables`, `--current-user`; `whoami`; `/api/health` |
| **2 — Non-sensitive data** | Proves read access without user data | Config tables, roles/permissions, application settings |
| **3 — Sensitive data** | Retrieves actual user records (requires confirmation) | `sqlmap --dump` on user tables; browser credential stores; `/etc/shadow` |

Skills always attempt Tier 1 first and only escalate with explicit tester approval.

### Safe Authentication Validation Policy

Defines a 3-tier hierarchy for credential validation to avoid destructive side effects:

| Tier | What it does | Example |
|------|-------------|---------|
| **1 — Read-only probes** | Confirms credential validity without side effects | `crackmapexec smb` (no `-x`); `ssh ... exit`; RDP `+auth-only` |
| **2 — Identity confirmation** | Confirms access level | `whoami /groups`; `--shares`; `--admin-count` |
| **3 — Interactive sessions** | Opens shells, executes commands (requires confirmation) | `impacket-psexec`; `evil-winrm`; `crackmapexec -x` |

Credential validation always uses Tier 1 first. Interactive exploitation requires explicit tester confirmation.

## Skill Reference

### vuln-scan
| Skill | Invocation | Purpose |
|-------|------------|---------|
| vuln-scan | `/vuln-scan [path]` | Run full vulnerability scanning pipeline. |
| jira-submit | `/jira-submit` | Submit findings to Jira via Atlassian MCP. |

### secret-scan
| Skill | Invocation | Purpose |
|-------|------------|---------|
| secret-scan | `/secret-scan [path]` | Trufflehog secret scan, optionally appended to a vuln-scan report. |

### dep-graph
| Skill | Invocation | Purpose |
|-------|------------|---------|
| dep-graph | `/dep-graph [parent-dir]` | Generate an interactive D3.js cross-repo dependency graph. |

### pentest-core
| Skill | Invocation | Purpose |
|-------|------------|---------|
| pentest-init | `/pentest-init` | Create a new engagement with scope, RoE, remote host, and tooling. |
| pentest-status | `/pentest-status` | Show active engagement scope, contacts, RoE, and recent activity. |
| pentest-switch | `/pentest-switch <id>` | Switch the active engagement. |
| pentest-scope-add | `/pentest-scope-add <target>` | Add an in-scope target. |
| pentest-scope-remove | `/pentest-scope-remove <target>` | Move a target to out-of-scope. |
| pentest-export | `/pentest-export` | Deduplicate and export findings for Plextrac. |

### pentest-recon
| Skill | Invocation | Purpose |
|-------|------------|---------|
| recon-passive | `/recon-passive [domain]` | OSINT, subdomain enumeration (root domains only), URL discovery (gau + waybackurls), auto JS analysis, cloud assets, leaked credentials. |
| recon-active | `/recon-active [target]` | Two-phase port scanning (top 1000 sync + full 65535 async), service fingerprinting, HTTP probing, web tech detection, WAF detection, screenshots (gowitness), SSL/TLS scanning (tlsx on all web services). |

### pentest-enum
| Skill | Invocation | Purpose |
|-------|------------|---------|
| enum-web | `/enum-web [url]` | Web/API enumeration — requires ffuf + katana + httpx. Auto-triggers JS analysis (jsluice + trufflehog) when JS files found. CMS detection, GraphQL, auth enumeration, CORS testing. |
| enum-network | `/enum-network [target]` | SMB, LDAP/AD, SNMP, DNS, RDP/SSH/WinRM, SMTP, FTP, databases, IPMI. |
| enum-cloud | `/enum-cloud [provider]` | AWS, Azure, GCP — IAM, storage, compute, multi-cloud auditing. |
| enum-js | `/enum-js [target]` | Standalone JavaScript analysis — endpoint extraction, secret detection, API key discovery via jsluice. |

### pentest-analysis
| Skill | Invocation | Purpose |
|-------|------------|---------|
| prioritize | `/prioritize` | Rank targets by value, recommend attack paths. |

### pentest-scanning
| Skill | Invocation | Purpose |
|-------|------------|---------|
| scan-vuln | `/scan-vuln [target]` | Nuclei scanning with tech-stack-aware template selection. |
| nuclei-template | `/nuclei-template <description>` | Generate custom nuclei YAML templates from natural-language descriptions. |

### pentest-exploit
| Skill | Invocation | Purpose |
|-------|------------|---------|
| exploit-assist | `/exploit-assist [target]` | Exploit search, payload generation, web exploitation (SQLi, SSTI, SSRF, XXE, deserialization). Tiered data access — prefers metadata over sensitive data dumps. |
| attack-creds | `/attack-creds [mode]` | Password spraying, hash cracking, credential stuffing. Lockout-safe defaults, Tier 1 read-only validation of discovered credentials. |

### pentest-postexploit
| Skill | Invocation | Purpose |
|-------|------------|---------|
| post-exploit | `/post-exploit` | Situational awareness, privesc, tiered lateral movement (validate → identify → exploit), tiered loot collection, persistence (RoE-gated), detection rules. |
| attack-ad | `/attack-ad` | Kerberoasting, AS-REP Roasting, DCSync, delegation abuse, ACL abuse, ADCS, NTLM relay. |

### pentest-evasion
| Skill | Invocation | Purpose |
|-------|------------|---------|
| evade | `/evade [technique]` | Payload obfuscation, AMSI/ETW bypass, LOLBins, process injection, C2, covering tracks. |

### pentest-social
| Skill | Invocation | Purpose |
|-------|------------|---------|
| phish | `/phish [mode]` | Phishing campaign setup, email generation, infrastructure, results parsing. |

### pentest-utility
| Skill | Invocation | Purpose |
|-------|------------|---------|
| finding-write | `/finding-write [input]` | Draft pentest findings with CVSS scoring, CWE mapping, compliance tagging. |
| pentest-cleanup | `/pentest-cleanup` | Generate a cleanup checklist from the engagement activity log. |
| pentest-retest | `/pentest-retest [finding-id]` | Verify remediation of previously reported findings. |

## Rules of Engagement (RoE) Gating

Plugins marked **RoE-gated** (`pentest-evasion`, `pentest-social`, and portions of `pentest-postexploit`) require explicit authorization flags in the active engagement's RoE configuration before their skills will execute. Configure these via `/pentest-init` or by editing the engagement config directly.

## Adding a New Plugin

1. Create a directory under `plugins/<plugin-name>/`
2. Add `.claude-plugin/plugin.json` with name, version, description, and author
3. Add `skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`, `user_invocable`)
4. Add a `README.md` documenting the plugin
5. Register the plugin in `.claude-plugin/marketplace.json`

## License

MIT
