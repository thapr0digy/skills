#!/usr/bin/env bash
# End-to-end integration test for Plan D1 — drives a synthetic phase batch
# through inline-checks, supervisor-verdict application, queue draining,
# completion check, and plan-mutation logging in sequence.

set -u
FAILS=0
REPO=$(pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-d1-int.XXXXXX")
mkdir -p "$WORK/output/research/_dispatched" "$WORK/workers"

cat > "$WORK/eng.json" <<EOF
{
  "engagement_id": "d1-int",
  "output_dir": "$WORK/output",
  "current_phase": "enum-web",
  "scope": {"in_scope": [{"type":"domain","value":"acme.com","added_at":"2026-05-07T00:00:00Z"}], "out_of_scope": []},
  "roe": {"restricted_techniques": [], "rate_limits": {"parallel_research_workers": 2}}
}
EOF

cat > "$WORK/output/plan.yaml" <<EOF
engagement_id: d1-int
created_at: 2026-05-07T14:00:00Z
phases:
  - {name: recon-passive, status: complete, rerun_count: 0}
  - {name: enum-web, status: in_progress, rerun_count: 0}
  - {name: prioritize, status: pending, rerun_count: 0}
conditional_phases:
  - {name: enum-cloud, status: locked, unlock_when: "cloud assets fingerprinted", insert_before: prioritize}
final_phases:
  - {name: finding-write, status: pending}
  - {name: pentest-export, status: pending}
EOF

cat > "$WORK/workers/worker-1.json" <<EOF
{
  "phase":"enum-web","batch_id":"int-batch-1","worker_id":"worker-1","status":"ok",
  "targets_processed":["acme.com"],"artifacts":["$WORK/output/enum/web/acme.com/dirs.json"],
  "services_discovered":[{"host":"acme.com","port":443,"product":"AWS-S3"}],
  "errors":[],"duration_seconds":120.0
}
EOF
mkdir -p "$WORK/output/enum/web/acme.com"
echo "{}" > "$WORK/output/enum/web/acme.com/dirs.json"

cat > "$WORK/output/activity.log" <<EOF
{"ts":"2026-05-07T15:00:00Z","tester":"x","event_type":"dispatch","batch_id":"int-batch-1","worker_id":"worker-1","phase":"enum-web","attempt_number":1}
{"ts":"2026-05-07T15:01:00Z","tester":"x","event_type":"tool_call","batch_id":"int-batch-1","worker_id":"worker-1","phase":"enum-web","attempt_number":1,"command":"ffuf -u https://acme.com/FUZZ"}
EOF

assert() {
  local label="$1" cond="$2"
  if eval "$cond"; then echo "PASS: $label"; else echo "FAIL: $label"; FAILS=$((FAILS + 1)); fi
}

# Step A: inline-checks should pass
ENGAGEMENT_JSON="$WORK/eng.json" OUTPUT_DIR="$WORK/output" BATCH_ID="int-batch-1" \
WORKER_RESULTS_DIR="$WORK/workers" \
PHASE_TOOL_ALLOWLIST="$REPO/plugins/pentest-core/skills/shared/phase-tool-allowlist.json" \
bash plugins/pentest-core/skills/pentest-engage/scripts/inline-checks.sh
ic_rc=$?
assert "inline-checks passes for clean batch" '[ "$ic_rc" = "0" ]'

# Step B: apply-verdict unlocks enum-cloud
cat > "$WORK/verdict.json" <<EOF
{
  "verdict": "replan",
  "reasons": ["AWS S3 endpoint discovered at acme.com:443 → unlock enum-cloud"],
  "quality_assessment": {"coverage_pct": 80, "depth_score": 7, "gaps": ["enum-cloud not yet run"]},
  "required_actions": [{"action":"unlock_conditional","phase":"enum-cloud","reason":"S3 endpoint discovered"}],
  "halt_reason": null
}
EOF
bash plugins/pentest-core/skills/pentest-engage/scripts/apply-verdict.sh \
  --plan "$WORK/output/plan.yaml" --verdict "$WORK/verdict.json" --in-place
av_rc=$?
assert "apply-verdict succeeds" '[ "$av_rc" = "0" ]'
assert "enum-cloud unlocked into phases[]" 'yq -r ".phases[].name" "$WORK/output/plan.yaml" | grep -Fxq "enum-cloud"'

# Step C: log_plan_mutation
python3 -c "
import re
content = open('plugins/pentest-core/skills/shared/engagement-resolver.md').read()
m = re.search(r'# --- Orchestration Helpers ---.*?# --- End Orchestration Helpers ---', content, re.DOTALL)
open('$WORK/h.sh', 'w').write('#!/bin/bash\nset -u\n' + m.group(0))
"
ENGAGEMENT_JSON="$WORK/eng.json" OUTPUT_DIR="$WORK/output" TESTER=fixture \
PENTEST_CORE_SHARED="$REPO/plugins/pentest-core/skills/shared" \
bash -c "source $WORK/h.sh; log_plan_mutation supervisor pentest-supervisor phase_unlocked 'S3 discovered' '{\"name\":\"enum-cloud\",\"status\":\"locked\"}' '{\"name\":\"enum-cloud\",\"status\":\"unlocked\"}'"
mut_count=$(grep -c '' "$WORK/output/plan-mutations.jsonl" 2>/dev/null || echo 0)
assert "plan-mutations.jsonl has 1 entry" '[ "$mut_count" = "1" ]'

# Step D: drain research queue
mkdir -p "$WORK/output/research"
cat > "$WORK/output/research/_pending.jsonl" <<EOF
{"host":"acme.com","port":443,"product":"AWS-S3","version":""}
{"host":"acme.com","port":80,"product":"nginx","version":"1.24"}
{"host":"acme.com","port":22,"product":"OpenSSH","version":"9.3"}
EOF
drain_out=$(ENGAGEMENT_JSON="$WORK/eng.json" OUTPUT_DIR="$WORK/output" \
  bash plugins/pentest-core/skills/pentest-engage/scripts/drain-research-queue.sh)
drain_count=$(printf '%s' "$drain_out" | grep -c '' 2>/dev/null || echo 0)
remain_count=$(grep -c '' "$WORK/output/research/_pending.jsonl" 2>/dev/null || echo 0)
assert "drain returns 2 entries (capped by parallel_research_workers)" '[ "$drain_count" = "2" ]'
assert "1 entry remaining in _pending.jsonl" '[ "$remain_count" = "1" ]'

# Step E: state running (enum-web still in_progress)
state=$(bash plugins/pentest-core/skills/pentest-engage/scripts/check-engagement-complete.sh \
  --plan "$WORK/output/plan.yaml" --engagement "$WORK/eng.json")
assert "engagement state is 'running'" '[ "$state" = "running" ]'

# Step F: mark all phases complete, recheck
yq -y '.phases |= map(.status = "complete") | .final_phases |= map(.status = "complete")' "$WORK/output/plan.yaml" > "$WORK/output/plan.yaml.tmp"
mv "$WORK/output/plan.yaml.tmp" "$WORK/output/plan.yaml"
state=$(bash plugins/pentest-core/skills/pentest-engage/scripts/check-engagement-complete.sh \
  --plan "$WORK/output/plan.yaml" --engagement "$WORK/eng.json")
assert "engagement state is 'complete' after all phases done" '[ "$state" = "complete" ]'

rm -rf "$WORK"
if [ "$FAILS" -gt 0 ]; then echo "$FAILS test(s) failed."; exit 1; fi
echo "all D1 integration tests passed"
