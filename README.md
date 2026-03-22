# Claude Code Plugins

A marketplace of Claude Code plugins for security analysis and vulnerability scanning.

## Installation

```bash
/plugin marketplace add thapr0digy/skills
```

## Available Plugins

| Plugin | Description |
|--------|-------------|
| [vuln-scan](plugins/vuln-scan/) | Autonomous 8-phase vulnerability scanning pipeline |

## Adding a New Plugin

1. Create a directory under `plugins/<plugin-name>/`
2. Add `.claude-plugin/plugin.json` with name, version, description, and author
3. Add `skills/<skill-name>/SKILL.md` with YAML frontmatter
4. Add a `README.md` documenting the plugin
5. Register the plugin in `.claude-plugin/marketplace.json`

## License

MIT
