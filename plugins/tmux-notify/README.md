# tmux-notify

Renames the active tmux window to a visible marker whenever Claude Code is
waiting on your input, and restores the original name once you respond.

When Claude is waiting (permission prompt, `AskUserQuestion`, idle), the window
name flips to:

```
⚠ CLAUDE
```

When you respond — by submitting a new prompt, approving/denying a permission,
answering a question, or once Claude finishes its turn — the original window
name is restored exactly as it was, including the `automatic-rename` setting.

## Requirements

- A tmux session (the hook is a no-op outside tmux).
- `tmux` available on `$PATH`.

## Installation

```
/plugin install tmux-notify@thapr0digy
```

## How it works

The marker name itself (`⚠ CLAUDE`) is the state indicator — there is no
separate flag tracking whether Claude is waiting. This makes the script robust
against `tmux rename-window` performed manually while Claude is waiting.

| Hook event | Action |
|------------|--------|
| `Notification` | Stash current window name + `automatic-rename` setting, rename to `⚠ CLAUDE`. |
| `Stop` | If window currently shows the marker, restore stashed name. |
| `UserPromptSubmit` | Same as Stop — covers user typing a new prompt. |
| `PostToolUse` | Same as Stop — covers `AskUserQuestion` answers and post-permission tool runs. |
| `PostToolUseFailure` | Same as Stop — covers permission denials. |

The `off` branch only restores when the marker is currently visible and only
touches state it stashed itself; it never blindly modifies a window's name or
`automatic-rename` setting.

## Customization

The marker text is the `MARKER` constant at the top of
`hooks/tmux-claude-waiting.sh`. Change it to whatever you want
(e.g. `🔴 WAITING`, `[CLAUDE]`).
