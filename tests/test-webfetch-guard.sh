#!/usr/bin/env bash
# Test webfetch-scope-guard.sh against fixture inputs.

set -u
HOOK="plugins/pentest-methodology-guard/scripts/webfetch-scope-guard.sh"
FIXDIR="tests/fixtures/hooks"
FAILS=0

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-wfg.XXXXXX")
cp tests/fixtures/active-engagement/engagement.json "$WORK/eng.json"
ln -sf "$WORK/eng.json" "$WORK/active-engagement"

run_active() {
  out=$(ACTIVE_ENGAGEMENT_LINK="$WORK/active-engagement" bash "$HOOK" < "$1" 2>/dev/null)
  rc=$?
}
run_inactive() {
  out=$(ACTIVE_ENGAGEMENT_LINK="$WORK/no-such-link" bash "$HOOK" < "$1" 2>/dev/null)
  rc=$?
}

assert() {
  local label="$1" cond="$2"
  if eval "$cond"; then
    echo "PASS: $label"
  else
    echo "FAIL: $label"
    echo "  rc=$rc out=$out"
    FAILS=$((FAILS + 1))
  fi
}

# Case 1: in-scope host (example.com) → deny
run_active "$FIXDIR/webfetch-in-scope.json"
assert "in-scope host → exit 2 (deny)" '[ "$rc" = "2" ]'
assert "in-scope host → permissionDecision=deny" 'printf "%s" "$out" | jq -e ".hookSpecificOutput.permissionDecision == \"deny\"" >/dev/null'
assert "in-scope host → reason cites scope entry" 'printf "%s" "$out" | grep -q -- "engagement scope entry"'

# Case 2: subdomain of in-scope host → deny
run_active "$FIXDIR/webfetch-subdomain-of-scope.json"
assert "subdomain of in-scope → exit 2" '[ "$rc" = "2" ]'

# Case 3: allowed source (NVD) → silent allow
run_active "$FIXDIR/webfetch-allowed-source.json"
assert "allowed source → exit 0 silent" '[ "$rc" = "0" ] && [ -z "$out" ]'

# Case 4: in-scope host, no engagement → silent passthrough
run_inactive "$FIXDIR/webfetch-in-scope.json"
assert "no engagement → exit 0 silent" '[ "$rc" = "0" ] && [ -z "$out" ]'

rm -rf "$WORK"

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS test(s) failed."
  exit 1
fi
echo ""
echo "all webfetch-guard tests passed"
