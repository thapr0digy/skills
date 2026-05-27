#!/usr/bin/env bash
# Unit test for the verify-spec PostToolUse reminder hook.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/plugins/verify-spec/scripts/verify-spec-reminder.sh"
fail=0

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -q "$needle"; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc — expected to find '$needle' in: $haystack"; fail=1
  fi
}
assert_empty() {
  local desc="$1" out="$2"
  if [ -z "$out" ]; then echo "PASS: $desc"; else
    echo "FAIL: $desc — expected empty, got: $out"; fail=1; fi
}

# 1. A vault spec write triggers the reminder.
spec_in='{"tool_name":"Write","tool_input":{"file_path":"/Users/pr0digy/Documents/obsidian/superpowers/skills/specs/2026-05-27-foo-design.md"}}'
out=$(printf '%s' "$spec_in" | "$HOOK")
assert_contains "vault spec triggers reminder" "$out" "verify-spec"
assert_contains "reminder is PostToolUse additionalContext" "$out" "additionalContext"

# 2. A vault plan write triggers the reminder.
plan_in='{"tool_name":"Write","tool_input":{"file_path":"/Users/pr0digy/Documents/obsidian/superpowers/meteor/plans/2026-05-27-bar.md"}}'
out=$(printf '%s' "$plan_in" | "$HOOK")
assert_contains "vault plan triggers reminder" "$out" "verify-spec"

# 3. A non-vault markdown write is silent.
other_in='{"tool_name":"Write","tool_input":{"file_path":"/Users/pr0digy/projects/skills/README.md"}}'
out=$(printf '%s' "$other_in" | "$HOOK")
assert_empty "non-vault write is silent" "$out"

# 4. A reality-check report write must NOT re-trigger (avoid loops).
report_in='{"tool_name":"Write","tool_input":{"file_path":"/Users/pr0digy/Documents/obsidian/superpowers/skills/specs/2026-05-27-foo-reality-check.md"}}'
out=$(printf '%s' "$report_in" | "$HOOK")
assert_empty "reality-check report is silent" "$out"

# 5. A reality-check report under plans/ must also not re-trigger (symmetric loop avoidance).
plan_report_in='{"tool_name":"Write","tool_input":{"file_path":"/Users/pr0digy/Documents/obsidian/superpowers/meteor/plans/2026-05-27-bar-reality-check.md"}}'
out=$(printf '%s' "$plan_report_in" | "$HOOK")
assert_empty "plans/ reality-check report is silent" "$out"

# 6. A MultiEdit-shaped payload on a vault spec triggers (matcher covers MultiEdit).
multiedit_in='{"tool_name":"MultiEdit","tool_input":{"file_path":"/Users/pr0digy/Documents/obsidian/superpowers/skills/specs/2026-05-27-baz-design.md"}}'
out=$(printf '%s' "$multiedit_in" | "$HOOK")
assert_contains "MultiEdit on vault spec triggers reminder" "$out" "verify-spec"

exit $fail
