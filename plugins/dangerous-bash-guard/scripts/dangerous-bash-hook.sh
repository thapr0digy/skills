#!/usr/bin/env bash
# PreToolUse hook for Bash. Hard-blocks Tier 1 + Tier 5 destructive patterns;
# returns "ask" for Tier 2 + Tier 4 patterns so the user gets a one-keypress
# confirm even in bypass-permissions mode.
#
# Escape hatch: prefix the command with CLAUDE_ALLOW_DANGEROUS=1 to bypass
# (logged to ~/.claude/dangerous-overrides.log).

set -u

LOG_FILE="$HOME/.claude/dangerous-overrides.log"

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

emit_decision() {
  local decision="$1" reason="$2"
  jq -n --arg d "$decision" --arg r "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $d,
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# Escape hatch: literal CLAUDE_ALLOW_DANGEROUS=1 prefix in the command.
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])CLAUDE_ALLOW_DANGEROUS=1([[:space:]]|$)'; then
  mkdir -p "$(dirname "$LOG_FILE")"
  printf '%s\tcwd=%s\t%s\n' "$(date -u +%FT%TZ)" "$(pwd)" "$CMD" >> "$LOG_FILE"
  exit 0
fi

# Tier 1 — irreversible filesystem destruction.
TIER1_PATTERNS=(
  '(^|[[:space:];&|])rm[[:space:]]+(-[A-Za-z]*[rR][A-Za-z]*[fF]|-[A-Za-z]*[fF][A-Za-z]*[rR])[[:space:]]+(/|~|\$HOME|\.|\.\.|/\*|~/\*|\$HOME/\*|\*)([[:space:];&|]|$)'
  '(^|[[:space:];&|])find[[:space:]]+(/|~|\$HOME)[[:space:]].*(-delete|-exec[[:space:]]+rm)\b'
  '(^|[[:space:];&|])dd[[:space:]]+.*of=/dev/(sd|nvme|hd|disk|mmcblk|vd)'
  '(^|[[:space:];&|])mkfs(\.[a-z0-9]+)?[[:space:]]+/dev/'
  '(^|[[:space:];&|])wipefs[[:space:]]+.*[[:space:]]/dev/'
  '(^|[[:space:];&|])shred[[:space:]]+.*[[:space:]]/dev/'
  '>[[:space:]]*/dev/(sd|nvme|hd|disk|mmcblk|vd)'
)

# Tier 5 — privilege/system destruction.
TIER5_PATTERNS=(
  '(^|[[:space:];&|])sudo[[:space:]]+(rm[[:space:]]+-[A-Za-z]*[rRfF]|dd[[:space:]]|mkfs|wipefs|shred)\b'
  '(^|[[:space:];&|])chmod[[:space:]]+-R[[:space:]]+0*777[[:space:]]+/(etc|usr|var|bin|sbin|lib|boot|System|Library)\b'
  '(^|[[:space:];&|])chown[[:space:]]+-R[[:space:]]+[^[:space:]]+[[:space:]]+/(etc|usr|var|bin|sbin|lib|boot|System|Library)\b'
  ':\(\)[[:space:]]*\{[^}]*:[[:space:]]*\|[[:space:]]*:[^}]*&[^}]*\}[[:space:]]*;[[:space:]]*:'
)

for pat in "${TIER1_PATTERNS[@]}" "${TIER5_PATTERNS[@]}"; do
  if printf '%s' "$CMD" | grep -qE "$pat"; then
    emit_decision "deny" "Blocked by dangerous-bash-hook (Tier 1/5: irreversible/system-destructive). To override, prefix with CLAUDE_ALLOW_DANGEROUS=1."
  fi
done

# Tier 2 — git destructive / history-rewriting.
TIER2_PATTERNS=(
  '(^|[[:space:];&|])git[[:space:]]+push[[:space:]]+.*(--force\b|--force-with-lease\b|[[:space:]]-f\b|[[:space:]]-[A-Za-z]*f[A-Za-z]*\b)'
  '(^|[[:space:];&|])git[[:space:]]+reset[[:space:]]+(--hard|.*[[:space:]]--hard)\b'
  '(^|[[:space:];&|])git[[:space:]]+clean[[:space:]]+-[A-Za-z]*f[A-Za-z]*d'
  '(^|[[:space:];&|])git[[:space:]]+(checkout|restore)[[:space:]]+\.[[:space:]]*$'
  '(^|[[:space:];&|])git[[:space:]]+branch[[:space:]]+(-D|.*[[:space:]]-D)\b'
  '(^|[[:space:];&|])git[[:space:]]+filter-(branch|repo)\b'
  '(^|[[:space:];&|])git[[:space:]]+reflog[[:space:]]+expire\b'
  '(^|[[:space:];&|])git[[:space:]]+commit[[:space:]]+.*--amend\b'
  '(^|[[:space:];&|])git[[:space:]]+rebase\b'
)

# Tier 4 — network/shared-state side effects.
TIER4_PATTERNS=(
  '(^|[[:space:];&|])gh[[:space:]]+pr[[:space:]]+(merge|close)\b'
  '(^|[[:space:];&|])gh[[:space:]]+issue[[:space:]]+close\b'
  '(^|[[:space:];&|])gh[[:space:]]+release[[:space:]]+delete\b'
  '(^|[[:space:];&|])gh[[:space:]]+repo[[:space:]]+delete\b'
  '(^|[[:space:];&|])kubectl[[:space:]]+(delete|apply)\b'
  '(^|[[:space:];&|])terraform[[:space:]]+(apply|destroy)\b'
  '(^|[[:space:];&|])aws[[:space:]]+[A-Za-z0-9-]+[[:space:]]+delete-'
  '(^|[[:space:];&|])aws[[:space:]]+s3[[:space:]]+rb\b'
  '(^|[[:space:];&|])aws[[:space:]]+s3[[:space:]]+rm[[:space:]]+.*--recursive\b'
  '(^|[[:space:];&|])docker[[:space:]]+system[[:space:]]+prune\b.*-[A-Za-z]*a'
  '(^|[[:space:];&|])docker[[:space:]]+volume[[:space:]]+rm\b'
)

for pat in "${TIER2_PATTERNS[@]}" "${TIER4_PATTERNS[@]}"; do
  if printf '%s' "$CMD" | grep -qE "$pat"; then
    emit_decision "ask" "dangerous-bash-hook flagged this command (Tier 2/4: history-rewriting or shared-state side effect). Confirm before allowing."
  fi
done

exit 0
