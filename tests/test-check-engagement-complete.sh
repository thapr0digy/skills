#!/usr/bin/env bash
set -u
HOOK="plugins/pentest-core/skills/pentest-engage/scripts/check-engagement-complete.sh"
FAILS=0

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-cec.XXXXXX")
cat > "$WORK/eng.json" <<EOF
{"engagement_id":"cec","output_dir":"$WORK"}
EOF

write_plan() { cat > "$WORK/p.yaml"; }

run_check() {
  out=$(bash "$HOOK" --plan "$WORK/p.yaml" --engagement "$WORK/eng.json" 2>&1)
  rc=$?
}

assert() {
  local label="$1" cond="$2"
  if eval "$cond"; then echo "PASS: $label"; else echo "FAIL: $label rc=$rc out=$out"; FAILS=$((FAILS + 1)); fi
}

# Case 1: pending phase → running
write_plan <<'EOF'
engagement_id: cec
created_at: 2026-05-07T00:00:00Z
phases:
  - {name: recon-passive, status: complete, rerun_count: 0}
  - {name: enum-web, status: pending, rerun_count: 0}
conditional_phases: []
final_phases:
  - {name: finding-write, status: pending}
  - {name: pentest-export, status: pending}
EOF
run_check
assert "pending phase → running, exit 0" '[ "$out" = "running" ] && [ "$rc" = "0" ]'

# Case 2: all complete → complete
write_plan <<'EOF'
engagement_id: cec
created_at: 2026-05-07T00:00:00Z
phases:
  - {name: recon-passive, status: complete, rerun_count: 0}
  - {name: enum-web, status: complete, rerun_count: 0}
conditional_phases: []
final_phases:
  - {name: finding-write, status: complete}
  - {name: pentest-export, status: complete}
EOF
run_check
assert "all complete → complete, exit 0" '[ "$out" = "complete" ] && [ "$rc" = "0" ]'

# Case 3: pentest-export missing entirely → halt-needed:supervisor_failure
write_plan <<'EOF'
engagement_id: cec
created_at: 2026-05-07T00:00:00Z
phases:
  - {name: recon-passive, status: complete, rerun_count: 0}
conditional_phases: []
final_phases:
  - {name: finding-write, status: complete}
EOF
run_check
assert "no pentest-export → supervisor_failure halt" '[ "$out" = "halt-needed:supervisor_failure" ] && [ "$rc" = "1" ]'

# Case 4: missing plan file → halt-needed:plan_missing
rm "$WORK/p.yaml"
run_check
assert "missing plan → plan_missing halt" '[ "$out" = "halt-needed:plan_missing" ] && [ "$rc" = "1" ]'

# Case 5: missing engagement file
write_plan <<'EOF'
engagement_id: cec
created_at: 2026-05-07T00:00:00Z
phases: []
conditional_phases: []
final_phases:
  - {name: finding-write, status: complete}
  - {name: pentest-export, status: complete}
EOF
out=$(bash "$HOOK" --plan "$WORK/p.yaml" --engagement "$WORK/no-such-eng.json" 2>&1); rc=$?
assert "missing engagement → engagement_missing halt" '[ "$out" = "halt-needed:engagement_missing" ] && [ "$rc" = "1" ]'

rm -rf "$WORK"
if [ "$FAILS" -gt 0 ]; then echo "$FAILS test(s) failed."; exit 1; fi
echo "all check-engagement-complete tests passed"
