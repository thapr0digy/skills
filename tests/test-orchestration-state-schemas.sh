#!/usr/bin/env bash
# Validate orchestration-state fixtures against their JSON schemas.

set -u

python3 -c "import jsonschema, json" 2>/dev/null || {
  echo "FATAL: python3 + jsonschema not available." >&2
  exit 1
}

SCHEMA_DIR="plugins/pentest-core/skills/shared/schemas"
FIX_DIR="tests/fixtures/orchestration-state"
FAILS=0

assert_valid() {
  local label="$1" schema="$2" fixture="$3"
  if python3 -c "
import json, jsonschema
schema = json.load(open('$schema'))
inst = json.load(open('$fixture'))
jsonschema.validate(inst, schema)
" 2>/dev/null; then
    echo "PASS: $label"
  else
    echo "FAIL: $label — $fixture should validate but did not"
    FAILS=$((FAILS + 1))
  fi
}

assert_invalid() {
  local label="$1" schema="$2" fixture="$3"
  if python3 -c "
import json, jsonschema
schema = json.load(open('$schema'))
inst = json.load(open('$fixture'))
jsonschema.validate(inst, schema)
" 2>/dev/null; then
    echo "FAIL: $label — $fixture should have failed but passed"
    FAILS=$((FAILS + 1))
  else
    echo "PASS: $label (correctly rejected)"
  fi
}

assert_valid   "plan-initial validates"              "$SCHEMA_DIR/plan-state.schema.json"      "$FIX_DIR/plan-initial.json"
assert_valid   "plan-mid-engagement validates"       "$SCHEMA_DIR/plan-state.schema.json"      "$FIX_DIR/plan-mid-engagement.json"
assert_invalid "plan-invalid-rerun-count rejected"   "$SCHEMA_DIR/plan-state.schema.json"      "$FIX_DIR/plan-invalid-rerun-count.json"

assert_valid   "mutation-phase-unlocked validates"   "$SCHEMA_DIR/plan-mutation.schema.json"   "$FIX_DIR/mutation-phase-unlocked.json"
assert_valid   "mutation-scope-added validates"      "$SCHEMA_DIR/plan-mutation.schema.json"   "$FIX_DIR/mutation-scope-added.json"
assert_invalid "mutation-invalid-kind rejected"      "$SCHEMA_DIR/plan-mutation.schema.json"   "$FIX_DIR/mutation-invalid-kind.json"

assert_valid   "halted-scope-violation validates"    "$SCHEMA_DIR/halted-state.schema.json"    "$FIX_DIR/halted-scope-violation.json"
assert_valid   "halted-supervisor-failure validates" "$SCHEMA_DIR/halted-state.schema.json"    "$FIX_DIR/halted-supervisor-failure.json"
assert_valid   "halted-user-abort validates"        "$SCHEMA_DIR/halted-state.schema.json"    "$FIX_DIR/halted-user-abort.json"
assert_invalid "halted-missing-reason rejected"     "$SCHEMA_DIR/halted-state.schema.json"    "$FIX_DIR/halted-missing-reason.json"
assert_invalid "mutation-missing-reason rejected"   "$SCHEMA_DIR/plan-mutation.schema.json"   "$FIX_DIR/mutation-missing-reason.json"

assert_valid   "complete-ok validates"               "$SCHEMA_DIR/complete-state.schema.json"  "$FIX_DIR/complete-ok.json"
assert_invalid "complete-invalid-coverage rejected"  "$SCHEMA_DIR/complete-state.schema.json"  "$FIX_DIR/complete-invalid-coverage.json"

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS test(s) failed."
  exit 1
fi
echo ""
echo "all orchestration-state schema tests passed"
