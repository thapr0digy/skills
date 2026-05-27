#!/usr/bin/env bash
# PostToolUse hook: when a spec/plan is written into the Obsidian superpowers
# vault, inject a reminder to reality-check it with verify-spec. Deterministic
# backstop for the CLAUDE.md pre-gate directive. Silent on everything else.
set -u

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE" ] && exit 0

# Only vault specs/plans. Exclude already-generated reality-check reports
# (in either specs/ or plans/) so the hook never re-triggers on its own output.
case "$FILE" in
  */Documents/obsidian/superpowers/*/specs/*-reality-check.md|\
  */Documents/obsidian/superpowers/*/plans/*-reality-check.md) exit 0 ;;
  */Documents/obsidian/superpowers/*/specs/*.md|\
  */Documents/obsidian/superpowers/*/plans/*.md) ;;
  *) exit 0 ;;
esac

REASON="A spec/plan was written to the Obsidian vault ($FILE). Before handing to the review gate / execution handoff, run /verify-spec on it to reality-check its assumptions against the code, docs, and API specs."

jq -n --arg r "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $r
  }
}'
exit 0
