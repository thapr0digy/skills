#!/usr/bin/env bash
# Test inline-checks.sh against fixture scenarios.

set -u
HOOK="plugins/pentest-core/skills/pentest-engage/scripts/inline-checks.sh"
FIX="tests/fixtures/inline-checks"
FAILS=0

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-ic.XXXXXX")
mkdir -p "$WORK/output" "$WORK/workers-pass" "$WORK/workers-scope-fail" "$WORK/workers-artifact-fail"

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

rm -rf "$WORK"

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS test(s) failed."
  exit 1
fi
echo ""
echo "all inline-checks tests passed"
