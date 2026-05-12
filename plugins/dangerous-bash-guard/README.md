# dangerous-bash-guard

PreToolUse hook that adds a safety net for `Bash` tool calls — designed to pair with `bypassPermissions` mode so routine work runs friction-free while destructive commands still trip a gate.

## Behavior

| Tier | Examples | Decision |
|------|----------|----------|
| 1 — Irreversible filesystem | `rm -rf /`, `rm -rf ~`, `find / -delete`, `dd of=/dev/sd*`, `mkfs /dev/*`, `wipefs`, `shred /dev/*`, `> /dev/sd*` | **deny** (hard block) |
| 5 — Privilege/system | `sudo rm/dd/mkfs/wipefs/shred`, `chmod -R 777 /etc\|/usr\|/var\|...`, `chown -R ... /etc\|...`, fork bomb | **deny** (hard block) |
| 2 — Git history-rewriting | `git push --force / -f / --force-with-lease`, `git reset --hard`, `git clean -fd`, `git checkout .` / `git restore .`, `git branch -D`, `git filter-branch / filter-repo`, `git reflog expire`, `git commit --amend`, `git rebase` | **ask** (one-keypress confirm) |
| 4 — Shared-state side effects | `gh pr merge/close`, `gh issue close`, `gh release/repo delete`, `kubectl delete/apply`, `terraform apply/destroy`, `aws ... delete-*`, `aws s3 rb`, `aws s3 rm --recursive`, `docker system prune -a`, `docker volume rm` | **ask** (one-keypress confirm) |

The `ask` decision re-introduces the standard permission prompt for the matched command even when running under `bypassPermissions`.

## Escape hatch

To run a Tier 1 / Tier 5 command intentionally, prefix it with `CLAUDE_ALLOW_DANGEROUS=1`:

```bash
CLAUDE_ALLOW_DANGEROUS=1 dd if=image.iso of=/dev/disk5
```

Every override is appended to `~/.claude/dangerous-overrides.log` with timestamp, working directory, and the full command.

## Install

Available through the local `thapr0digy` marketplace at `/Users/pr0digy/projects/skills`.

Enable in `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "dangerous-bash-guard@thapr0digy": true
  }
}
```

## Requirements

- `jq` on `$PATH` (the hook exits 0 silently if absent — fail-open by design so a missing dependency doesn't break the session)
- Bash-compatible `$SHELL`

## Limitations

- Pattern-based detection. Heavy obfuscation (variable expansion, base64, eval) can evade it. This is a guardrail, not a sandbox.
- `kubectl delete/apply` and `terraform apply` always prompt — the hook can't reliably read the active context/workspace from the command string.
- Runs in addition to any other PreToolUse Bash hooks. Composes cleanly with `rtk-rewrite`-style proxies (the dangerous patterns match regardless of leading `rtk` prefix).
