#!/usr/bin/env bash
# Test apply-verdict.sh — verdict → plan.yaml mutation.

set -u
HOOK="plugins/pentest-core/skills/pentest-engage/scripts/apply-verdict.sh"
FIX="tests/fixtures/apply-verdict"
FAILS=0

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-av.XXXXXX")

run_apply() {
  local plan="$1" verdict="$2"
  out=$(bash "$HOOK" --plan "$plan" --verdict "$verdict" 2>&1)
  rc=$?
}

assert() {
  local label="$1" cond="$2"
  if eval "$cond"; then
    echo "PASS: $label"
  else
    echo "FAIL: $label"
    echo "  rc=$rc"
    echo "  out: $(printf '%s' "$out" | head -30)"
    FAILS=$((FAILS + 1))
  fi
}

# Case 1: proceed → exit 0, plan unchanged
cp "$FIX/plan-baseline.yaml" "$WORK/p.yaml"
run_apply "$WORK/p.yaml" "$FIX/verdict-proceed.json"
assert "proceed → exit 0" '[ "$rc" = "0" ]'
assert "proceed → plan unchanged on stdout" '[ "$(yq -r ".phases[1].name" <<< "$out")" = "enum-web" ]'

# Case 2: skip_phase scan-vuln → status becomes "skipped"
cp "$FIX/plan-baseline.yaml" "$WORK/p.yaml"
run_apply "$WORK/p.yaml" "$FIX/verdict-skip.json"
assert "skip → exit 0" '[ "$rc" = "0" ]'
assert "skip → scan-vuln status=skipped" '[ "$(yq -r ".phases[] | select(.name == \"scan-vuln\") | .status" <<< "$out")" = "skipped" ]'

# Case 3: unlock_conditional enum-cloud
cp "$FIX/plan-baseline.yaml" "$WORK/p.yaml"
run_apply "$WORK/p.yaml" "$FIX/verdict-unlock.json"
assert "unlock → exit 0" '[ "$rc" = "0" ]'
assert "unlock → enum-cloud appears in phases[]" 'yq -r ".phases[].name" <<< "$out" | grep -Fxq "enum-cloud"'
assert "unlock → enum-cloud appears before prioritize" 'test "$(yq -r "[.phases[].name] | index(\"enum-cloud\")" <<< "$out")" -lt "$(yq -r "[.phases[].name] | index(\"prioritize\")" <<< "$out")"'
assert "unlock → conditional_phases.enum-cloud.status=unlocked" '[ "$(yq -r ".conditional_phases[] | select(.name == \"enum-cloud\") | .status" <<< "$out")" = "unlocked" ]'

# Case 4: rerun_phase enum-web (rerun_count 0 → 1)
cp "$FIX/plan-baseline.yaml" "$WORK/p.yaml"
run_apply "$WORK/p.yaml" "$FIX/verdict-rerun.json"
assert "rerun → exit 0" '[ "$rc" = "0" ]'
assert "rerun → enum-web.rerun_count=1" '[ "$(yq -r ".phases[] | select(.name == \"enum-web\") | .rerun_count" <<< "$out")" = "1" ]'
assert "rerun → enum-web.status=pending" '[ "$(yq -r ".phases[] | select(.name == \"enum-web\") | .status" <<< "$out")" = "pending" ]'
assert "rerun → enum-web.rerun_params.wordlist_size=medium" '[ "$(yq -r ".phases[] | select(.name == \"enum-web\") | .rerun_params.wordlist_size" <<< "$out")" = "medium" ]'

# Case 4b: rerun a phase mid-plan → downstream phases AND final_phases get invalidated
cp "$FIX/plan-with-completed-downstream.yaml" "$WORK/p.yaml"
# Verdict: rerun enum-web (phases[1]) — all downstream phases and final_phases should reset to pending
run_apply "$WORK/p.yaml" "$FIX/verdict-rerun.json"
assert "downstream rerun → exit 0" '[ "$rc" = "0" ]'
assert "downstream rerun → enum-web reset to pending" '[ "$(yq -r ".phases[] | select(.name == \"enum-web\") | .status" <<< "$out")" = "pending" ]'
assert "downstream rerun → prioritize timestamps cleared" '[ "$(yq -r ".phases[] | select(.name == \"prioritize\") | .completed_at" <<< "$out")" = "null" ]'
assert "downstream rerun → scan-vuln status reset to pending" '[ "$(yq -r ".phases[] | select(.name == \"scan-vuln\") | .status" <<< "$out")" = "pending" ]'
assert "downstream rerun → finding-write status reset to pending" '[ "$(yq -r ".final_phases[] | select(.name == \"finding-write\") | .status" <<< "$out")" = "pending" ]'
assert "downstream rerun → finding-write timestamps cleared" '[ "$(yq -r ".final_phases[] | select(.name == \"finding-write\") | .completed_at" <<< "$out")" = "null" ]'
assert "downstream rerun → pentest-export status reset to pending" '[ "$(yq -r ".final_phases[] | select(.name == \"pentest-export\") | .status" <<< "$out")" = "pending" ]'

# Case 5: rerun exhausted (current=2, +1=3 → halt)
cp "$FIX/plan-baseline.yaml" "$WORK/p.yaml"
yq -yi '(.phases[] | select(.name == "enum-web")).rerun_count = 2' "$WORK/p.yaml"
run_apply "$WORK/p.yaml" "$FIX/verdict-rerun-exhausted.json"
assert "rerun-exhausted → exit 2" '[ "$rc" = "2" ]'
assert "rerun-exhausted → halt_reason=replan_exhausted in stderr" 'printf "%s" "$out" | grep -q "halt_reason=replan_exhausted"'

# Case 6: halt verdict → exit 2
cp "$FIX/plan-baseline.yaml" "$WORK/p.yaml"
run_apply "$WORK/p.yaml" "$FIX/verdict-halt.json"
assert "halt → exit 2" '[ "$rc" = "2" ]'
assert "halt → halt_reason=scope_violation in stderr" 'printf "%s" "$out" | grep -q "halt_reason=scope_violation"'

rm -rf "$WORK"

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS test(s) failed."
  exit 1
fi
echo ""
echo "all apply-verdict tests passed"
