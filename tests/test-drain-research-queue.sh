#!/usr/bin/env bash
set -u
HOOK="plugins/pentest-core/skills/pentest-engage/scripts/drain-research-queue.sh"
FAILS=0

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-drq.XXXXXX")
mkdir -p "$WORK/output/research"

cat > "$WORK/eng.json" <<EOF
{"engagement_id":"drq","output_dir":"$WORK/output","roe":{"rate_limits":{"parallel_research_workers":3}}}
EOF

for i in 1 2 3 4 5; do
  echo "{\"host\":\"h$i\",\"port\":80,\"product\":\"p$i\",\"version\":\"v$i\"}"
done > "$WORK/output/research/_pending.jsonl"

run_drain() {
  out=$(ENGAGEMENT_JSON="$WORK/eng.json" OUTPUT_DIR="$WORK/output" bash "$HOOK")
  rc=$?
}

assert() {
  local label="$1" cond="$2"
  if eval "$cond"; then echo "PASS: $label"; else echo "FAIL: $label rc=$rc out=$out"; FAILS=$((FAILS + 1)); fi
}

# Count non-empty lines; returns 0 for missing or empty files/strings.
# grep -c '' exits 1 on empty input (BSD grep), so capture output before
# using the exit-code-based fallback.
count_lines() {
  local n
  n=$(grep -c '' "$1" 2>/dev/null)
  [ -n "$n" ] && echo "$n" || echo 0
}
count_stdout_lines() {
  local n
  n=$(printf '%s' "$1" | grep -c '' 2>/dev/null)
  [ -n "$n" ] && echo "$n" || echo 0
}

run_drain
assert "first drain → exit 0" '[ "$rc" = "0" ]'
assert "first drain → 3 entries on stdout" '[ "$(count_stdout_lines "$out")" = "3" ]'
assert "first drain → 2 entries remaining" '[ "$(count_lines "$WORK/output/research/_pending.jsonl")" = "2" ]'

run_drain
assert "second drain → 2 entries on stdout" '[ "$(count_stdout_lines "$out")" = "2" ]'
assert "second drain → 0 entries remaining" '[ "$(count_lines "$WORK/output/research/_pending.jsonl")" = "0" ]'

run_drain
assert "third drain → exit 0" '[ "$rc" = "0" ]'
assert "third drain → no output" '[ -z "$out" ]'

rm "$WORK/output/research/_pending.jsonl"
run_drain
assert "missing pending file → exit 0" '[ "$rc" = "0" ]'
assert "missing pending file → no output" '[ -z "$out" ]'

rm -rf "$WORK"
if [ "$FAILS" -gt 0 ]; then echo "$FAILS test(s) failed."; exit 1; fi
echo "all drain-research-queue tests passed"
