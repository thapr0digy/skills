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

### Penetration Testing Suite

A modular set of plugins covering the full offensive security engagement lifecycle.

| Plugin | Description |
|--------|-------------|
| [pentest-core](plugins/pentest-core/) | Engagement management — configuration, scope validation, remote execution, evidence organization, Plextrac-compatible export. |
| [pentest-recon](plugins/pentest-recon/) | Passive and active reconnaissance — subdomain enumeration, port scanning, service fingerprinting, OSINT, attack surface discovery. |
| [pentest-enum](plugins/pentest-enum/) | Enumeration of web apps, network services, and cloud infrastructure. |
| [pentest-analysis](plugins/pentest-analysis/) | Target prioritization — synthesizes recon/enum/scan data to recommend high-value attack paths. |
| [pentest-scanning](plugins/pentest-scanning/) | Nuclei-based vulnerability scanning with tech-stack-aware template selection and custom template generation. |
| [pentest-exploit](plugins/pentest-exploit/) | Exploitation guidance, payload generation, and credential attacks (password spraying, hash cracking). |
| [pentest-postexploit](plugins/pentest-postexploit/) | Active Directory attack chains, privilege escalation, lateral movement, loot collection, and detection rules. |
| [pentest-evasion](plugins/pentest-evasion/) | Defense evasion — payload obfuscation, AMSI/ETW bypass, LOLBins, process injection, C2 comms. **RoE-gated.** |
| [pentest-social](plugins/pentest-social/) | Phishing campaign setup, email templates, infrastructure configuration, results parsing. **RoE-gated.** |
| [pentest-utility](plugins/pentest-utility/) | Finding report writing, engagement cleanup checklists, remediation retesting. |

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
| recon-passive | `/recon-passive` | OSINT, subdomain enumeration, cloud asset discovery, leaked credentials. |
| recon-active | `/recon-active` | Port scanning, service fingerprinting, web tech detection, SSL/TLS scanning. |

### pentest-enum
| Skill | Invocation | Purpose |
|-------|------------|---------|
| enum-web | `/enum-web` | Web/API enumeration — fuzzing, crawling, CMS detection, GraphQL, auth. |
| enum-network | `/enum-network` | SMB, LDAP/AD, SNMP, DNS, RDP/SSH/WinRM, SMTP, FTP, databases, IPMI. |
| enum-cloud | `/enum-cloud` | AWS, Azure, GCP — IAM, storage, compute, multi-cloud auditing. |
| enum-js | `/enum-js` | Extract endpoints, secrets, API keys from JS using jsluice. |

### pentest-analysis
| Skill | Invocation | Purpose |
|-------|------------|---------|
| prioritize | `/prioritize` | Rank targets by value, recommend attack paths. |

### pentest-scanning
| Skill | Invocation | Purpose |
|-------|------------|---------|
| scan-vuln | `/scan-vuln` | Nuclei scanning with tech-stack-aware template selection. |
| nuclei-template | `/nuclei-template` | Generate custom nuclei YAML templates from natural-language descriptions. |

### pentest-exploit
| Skill | Invocation | Purpose |
|-------|------------|---------|
| exploit-assist | `/exploit-assist` | Exploit search, payload generation, web exploitation (SQLi, SSTI, SSRF, XXE, deserialization). |
| attack-creds | `/attack-creds [mode]` | Password spraying, hash cracking, credential stuffing with lockout-safe defaults. |

### pentest-postexploit
| Skill | Invocation | Purpose |
|-------|------------|---------|
| post-exploit | `/post-exploit` | Situational awareness, privesc, lateral movement, pivoting, loot, persistence (RoE-gated). |
| attack-ad | `/attack-ad` | Kerberoasting, AS-REP Roasting, DCSync, delegation abuse, ACL abuse, ADCS, NTLM relay. |

### pentest-evasion
| Skill | Invocation | Purpose |
|-------|------------|---------|
| evade | `/evade` | Payload obfuscation, AMSI/ETW bypass, LOLBins, process injection, C2, covering tracks. |

### pentest-social
| Skill | Invocation | Purpose |
|-------|------------|---------|
| phish | `/phish` | Phishing campaign setup, email generation, infrastructure, results parsing. |

### pentest-utility
| Skill | Invocation | Purpose |
|-------|------------|---------|
| finding-write | `/finding-write` | Draft pentest findings with CVSS scoring, CWE mapping, compliance tagging. |
| pentest-cleanup | `/pentest-cleanup` | Generate a cleanup checklist from the engagement activity log. |
| pentest-retest | `/pentest-retest` | Verify remediation of previously reported findings. |

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
