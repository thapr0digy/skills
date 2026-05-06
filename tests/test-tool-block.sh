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

rm -rf "$WORK"

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS test(s) failed."
  exit 1
fi
echo ""
echo "all tool-block tests passed"
