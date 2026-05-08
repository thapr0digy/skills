#!/usr/bin/env bash
# Test inline-checks.sh against fixture scenarios.

set -u
HOOK="plugins/pentest-core/skills/pentest-engage/scripts/inline-checks.sh"
FIX="tests/fixtures/inline-checks"
FAILS=0

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-ic.XXXXXX")
mkdir -p "$WORK/output" "$WORK/workers-pass" "$WORK/workers-scope-fail" "$WORK/workers-artifact-fail" "$WORK/workers-traversal-fail"

jq --arg d "$WORK/output" '.output_dir = $d' "$FIX/engagement.json" > "$WORK/engagement.json"
cp "$FIX/activity.log" "$WORK/output/activity.log"

# Patch worker artifact paths to point at temp output_dir for the pass scenario
patch_worker() {
  local src="$1" dst="$2"
  jq --arg out "$WORK/output" '.artifacts |= map(sub("/tmp/inline-checks-output"; $out))' "$src" > "$dst"
}

# Scenario A: clean
patch_worker "$FIX/workers/worker-ok.json" "$WORK/workers-pass/worker-1.json"

# Scenario B: out-of-scope
patch_worker "$FIX/workers/worker-ok.json" "$WORK/workers-scope-fail/worker-1.json"
cp "$FIX/workers/worker-out-of-scope.json" "$WORK/workers-scope-fail/worker-2.json"

# Scenario C: bad artifact (literal /etc/passwd, no rewrite)
cp "$FIX/workers/worker-bad-artifact.json" "$WORK/workers-artifact-fail/worker-1.json"

# Scenario D: relative-path traversal
cat > "$WORK/workers-traversal-fail/worker-1.json" <<EOF
{
  "phase": "enum-web", "batch_id": "batch-T", "worker_id": "worker-1", "status": "ok",
  "targets_processed": ["acme.com"],
  "artifacts": ["../../../etc/passwd"],
  "services_discovered": [], "errors": [], "duration_seconds": 30.0
}
EOF

run_check() {
  local results_dir="$1"
  out=$(ENGAGEMENT_JSON="$WORK/engagement.json" \
        OUTPUT_DIR="$WORK/output" \
        BATCH_ID="batch-T" \
        WORKER_RESULTS_DIR="$results_dir" \
        bash "$HOOK" 2>&1)
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

run_check "$WORK/workers-pass"
assert "clean batch → exit 0" '[ "$rc" = "0" ]'
assert "clean batch → no violations" '! printf "%s" "$out" | grep -q "violation:"'

run_check "$WORK/workers-scope-fail"
assert "out-of-scope batch → exit 1" '[ "$rc" = "1" ]'
assert "out-of-scope batch → scope_subset violation" 'printf "%s" "$out" | grep -q "violation:scope_subset"'

run_check "$WORK/workers-artifact-fail"
assert "bad-artifact batch → exit 1" '[ "$rc" = "1" ]'
assert "bad-artifact batch → artifact_path violation" 'printf "%s" "$out" | grep -q "violation:artifact_path"'

run_check "$WORK/workers-traversal-fail"
assert "traversal-path batch → exit 1" '[ "$rc" = "1" ]'
assert "traversal-path batch → artifact_path violation cites traversal" 'printf "%s" "$out" | grep -q "parent-directory traversal"'

run_check_with_allowlist() {
  local results_dir="$1"
  out=$(ENGAGEMENT_JSON="$WORK/engagement.json" \
        OUTPUT_DIR="$WORK/output" \
        BATCH_ID="batch-T" \
        WORKER_RESULTS_DIR="$results_dir" \
        PHASE_TOOL_ALLOWLIST="$(pwd)/plugins/pentest-core/skills/shared/phase-tool-allowlist.json" \
        bash "$HOOK" 2>&1)
  rc=$?
}

# Scenario E: missing dispatch entry → check 3 violation
mkdir -p "$WORK/workers-no-dispatch"
patch_worker "$FIX/workers/worker-ok.json" "$WORK/workers-no-dispatch/worker-99.json"
jq '.worker_id = "worker-99"' "$WORK/workers-no-dispatch/worker-99.json" > "$WORK/workers-no-dispatch/worker-99.json.tmp" && \
  mv "$WORK/workers-no-dispatch/worker-99.json.tmp" "$WORK/workers-no-dispatch/worker-99.json"
run_check "$WORK/workers-no-dispatch"
assert "no-dispatch batch → exit 1" '[ "$rc" = "1" ]'
assert "no-dispatch batch → dispatch_log violation" 'printf "%s" "$out" | grep -q "violation:dispatch_log"'

# Scenario F: restricted technique mentioned → check 4 violation
cp "$WORK/output/activity.log" "$WORK/output/activity.log.bak"
echo '{"ts":"2026-05-07T15:02:00Z","tester":"x","event_type":"tool_call","batch_id":"batch-T","worker_id":"worker-1","phase":"enum-web","attempt_number":1,"command":"slowloris-DoS-attack -t target.com"}' >> "$WORK/output/activity.log"
mkdir -p "$WORK/workers-restricted"
patch_worker "$FIX/workers/worker-ok.json" "$WORK/workers-restricted/worker-1.json"
run_check "$WORK/workers-restricted"
assert "restricted-tech batch → exit 1" '[ "$rc" = "1" ]'
assert "restricted-tech batch → restricted_technique violation" 'printf "%s" "$out" | grep -q "violation:restricted_technique"'
mv "$WORK/output/activity.log.bak" "$WORK/output/activity.log"

# Scenario G: tool not in phase allowlist → check 5 violation
# sqlmap is in exploit-assist allowlist, NOT enum-web
echo '{"ts":"2026-05-07T15:03:00Z","tester":"x","event_type":"tool_call","batch_id":"batch-T","worker_id":"worker-1","phase":"enum-web","attempt_number":1,"command":"sqlmap -u https://acme.com/login.php"}' >> "$WORK/output/activity.log"
run_check_with_allowlist "$WORK/workers-restricted"
assert "phase-allowlist batch → exit 1" '[ "$rc" = "1" ]'
assert "phase-allowlist batch → phase_tool_allowlist violation" 'printf "%s" "$out" | grep -q "violation:phase_tool_allowlist"'

rm -rf "$WORK"

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS test(s) failed."
  exit 1
fi
echo ""
echo "all inline-checks tests passed"
