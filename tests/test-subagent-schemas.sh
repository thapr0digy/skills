#!/usr/bin/env bash
# Validate subagent-result fixtures against their JSON schemas.

set -u
SCHEMA_DIR="plugins/pentest-core/skills/shared/schemas"
FIX_DIR="tests/fixtures/subagent-results"
FAILS=0

assert_valid() {
  local label="$1" schema="$2" fixture="$3"
  if python3 -c "
import json, jsonschema, sys
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
import json, jsonschema, sys
schema = json.load(open('$schema'))
inst = json.load(open('$fixture'))
jsonschema.validate(inst, schema)
" 2>/dev/null; then
    echo "FAIL: $label — $fixture should have failed validation but passed"
    FAILS=$((FAILS + 1))
  else
    echo "PASS: $label (correctly rejected)"
  fi
}

# Worker-result schema
assert_valid   "worker-ok validates"                  "$SCHEMA_DIR/worker-result.schema.json"      "$FIX_DIR/worker-ok.json"
assert_valid   "worker-blocked validates"             "$SCHEMA_DIR/worker-result.schema.json"      "$FIX_DIR/worker-blocked.json"
assert_invalid "worker-invalid rejected"              "$SCHEMA_DIR/worker-result.schema.json"      "$FIX_DIR/worker-invalid.json"
assert_invalid "worker-port-zero rejected"            "$SCHEMA_DIR/worker-result.schema.json"      "$FIX_DIR/worker-port-zero.json"

# Supervisor-verdict schema
assert_valid   "supervisor-proceed validates"               "$SCHEMA_DIR/supervisor-verdict.schema.json" "$FIX_DIR/supervisor-proceed.json"
assert_valid   "supervisor-replan validates"                "$SCHEMA_DIR/supervisor-verdict.schema.json" "$FIX_DIR/supervisor-replan.json"
assert_valid   "supervisor-halt validates"                  "$SCHEMA_DIR/supervisor-verdict.schema.json" "$FIX_DIR/supervisor-halt.json"
assert_invalid "supervisor-invalid rejected"                "$SCHEMA_DIR/supervisor-verdict.schema.json" "$FIX_DIR/supervisor-invalid.json"
assert_valid   "supervisor-replan-with-rerun-params validates" "$SCHEMA_DIR/supervisor-verdict.schema.json" "$FIX_DIR/supervisor-replan-with-rerun-params.json"

# Research-index schema
assert_valid   "research-index-ok validates"   "$SCHEMA_DIR/research-index.schema.json"     "$FIX_DIR/research-index-ok.json"

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS test(s) failed."
  exit 1
fi
echo ""
echo "all subagent-schema tests passed"
