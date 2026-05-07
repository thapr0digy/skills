#!/usr/bin/env bash
# Test pentest-tool-block.sh against fixture inputs.

set -u
HOOK="plugins/pentest-methodology-guard/scripts/pentest-tool-block.sh"
FIXDIR="tests/fixtures/hooks"
FAILS=0

REPO_ROOT="$(pwd)"
PENTEST_CORE_SHARED="$REPO_ROOT/plugins/pentest-core/skills/shared"
export PENTEST_CORE_SHARED

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-tool-block.XXXXXX")
cp tests/fixtures/active-engagement/engagement.json "$WORK/eng.json"
ln -sf "$WORK/eng.json" "$WORK/active-engagement"

# Capture both stdout and exit code in two globals: $out and $rc
run_capture() {
  local mode="$1" fixture="$2"
  if [ "$mode" = "active" ]; then
    out=$(ACTIVE_ENGAGEMENT_LINK="$WORK/active-engagement" bash "$HOOK" < "$fixture" 2>/dev/null)
  else
    out=$(ACTIVE_ENGAGEMENT_LINK="$WORK/no-such-link" bash "$HOOK" < "$fixture" 2>/dev/null)
  fi
  rc=$?
}

assert() {
  local label="$1" cond="$2"
  if eval "$cond"; then
    echo "PASS: $label"
  else
    echo "FAIL: $label"
    echo "  rc=$rc"
    echo "  out=$out"
    FAILS=$((FAILS + 1))
  fi
}

# --- Case 1: ffuf in enum-web (allowed by phase-tool-allowlist.json) ---
run_capture active "$FIXDIR/bash-tool-pentest-allowed.json"
assert "ffuf in enum-web → exit 0 silent" '[ "$rc" = "0" ] && [ -z "$out" ]'

# --- Case 2: nmap in enum-web (denied — nmap belongs to recon-active) ---
run_capture active "$FIXDIR/bash-tool-pentest-denied.json"
assert "nmap in enum-web → exit 2" '[ "$rc" = "2" ]'
assert "nmap in enum-web → deny verdict" 'printf "%s" "$out" | jq -e ".hookSpecificOutput.permissionDecision == \"deny\"" >/dev/null'
assert "nmap in enum-web → cites recon-active skill" 'printf "%s" "$out" | grep -q -- "pentest-recon:recon-active"'
assert "nmap in enum-web → instructs no-retry" 'printf "%s" "$out" | grep -q -- "Do NOT retry"'

# --- Case 3: ls (not a pentest tool) → silent allow ---
run_capture active "$FIXDIR/bash-tool-not-pentest.json"
assert "ls → exit 0 silent" '[ "$rc" = "0" ] && [ -z "$out" ]'

# --- Case 4: nmap, no engagement → warn-only, no block ---
run_capture inactive "$FIXDIR/bash-tool-pentest-denied.json"
assert "nmap, no engagement → exit 0" '[ "$rc" = "0" ]'
assert "nmap, no engagement → additionalContext warn" 'printf "%s" "$out" | jq -e ".hookSpecificOutput.additionalContext" >/dev/null'
assert "nmap, no engagement → no permissionDecision" 'printf "%s" "$out" | jq -e ".hookSpecificOutput | has(\"permissionDecision\") | not" >/dev/null'

# --- Case 5: nmap inside $() — command-substitution evasion → should deny ---
cmd_sub_fixture="$WORK/cmd-sub.json"
# Use jq to build the fixture so the shell doesn't interpret $() or backticks
jq -rn '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"foo $(nmap -sV) bar"}}' > "$cmd_sub_fixture"
run_capture active "$cmd_sub_fixture"
assert "nmap in \$(…) → exit 2" '[ "$rc" = "2" ]'
assert "nmap in \$(…) → deny verdict" 'printf "%s" "$out" | jq -e ".hookSpecificOutput.permissionDecision == \"deny\"" >/dev/null'

# --- Case 6: nmap inside backticks — command-substitution evasion → should deny ---
backtick_fixture="$WORK/backtick.json"
# Use jq to build the fixture so backticks are not interpreted by bash
jq -rn '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"foo `nmap -sV` bar"}}' > "$backtick_fixture"
run_capture active "$backtick_fixture"
assert "nmap in backticks → exit 2" '[ "$rc" = "2" ]'
assert "nmap in backticks → deny verdict" 'printf "%s" "$out" | jq -e ".hookSpecificOutput.permissionDecision == \"deny\"" >/dev/null'

# --- Case 5b: active engagement but data files missing → must deny (fail-closed) ---
# Override PENTEST_CORE_SHARED to a non-existent directory
missing_data_fixture="$FIXDIR/bash-tool-pentest-denied.json"
out=$(ACTIVE_ENGAGEMENT_LINK="$WORK/active-engagement" PENTEST_CORE_SHARED="$WORK/no-such-shared" bash "$HOOK" < "$missing_data_fixture" 2>/dev/null)
rc=$?
assert "active + missing data files → exit 2 (fail-closed)" '[ "$rc" = "2" ]'
assert "active + missing data files → deny verdict" 'printf "%s" "$out" | jq -e ".hookSpecificOutput.permissionDecision == \"deny\"" >/dev/null'
assert "active + missing data files → reason mentions unreachable" 'printf "%s" "$out" | jq -r ".hookSpecificOutput.permissionDecisionReason" | grep -qi "unreachable"'

# --- Case 7: nmap with surrounding tabs/newlines — matched_tool must be clean "nmap" ---
# Ensures tr -cd 'a-zA-Z0-9_-' strips whitespace so jq gets a clean tool name
whitespace_fixture="$WORK/whitespace.json"
# Use jq so \t is decoded to a real tab character (raw tabs are invalid JSON)
jq -rn '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"\t nmap \t -sV"}}' > "$whitespace_fixture"
run_capture active "$whitespace_fixture"
assert "nmap with tabs → exit 2" '[ "$rc" = "2" ]'
assert "nmap with tabs → deny verdict" 'printf "%s" "$out" | jq -e ".hookSpecificOutput.permissionDecision == \"deny\"" >/dev/null'
# Reason string must contain the clean tool name "nmap", not raw whitespace chars
assert "nmap with tabs → reason references clean tool name" 'printf "%s" "$out" | jq -r ".hookSpecificOutput.permissionDecisionReason" | grep -q "nmap"'

rm -rf "$WORK"

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS test(s) failed."
  exit 1
fi
echo ""
echo "all tool-block tests passed"
