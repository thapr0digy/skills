#!/usr/bin/env bash
# Test discovery-watcher.sh: clean run, dedup, noise filter, malformed safety.

set -u
HOOK="plugins/pentest-methodology-guard/scripts/discovery-watcher.sh"
FAILS=0

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-dw.XXXXXX")
OUT="$WORK/output"
mkdir -p "$OUT/recon/active" "$OUT/research/_dispatched"

# Active-engagement fixture pointing at our temp output dir
cat > "$WORK/eng.json" <<EOF
{
  "engagement_id": "fixture-discovery",
  "output_dir": "$OUT",
  "current_phase": "recon-active",
  "status": "running"
}
EOF
ln -sf "$WORK/eng.json" "$WORK/active-engagement"

# Write a JSONL artifact — 2 real services, 1 noise (http), 1 malformed
cat > "$OUT/recon/active/services.jsonl" <<EOF
{"host":"example.com","port":80,"product":"nginx","version":"1.24.0"}
{"host":"example.com","port":443,"product":"http"}
{"host":"example.com","port":8080,"product":"WordPress","version":"6.4.1"}
not valid json at all
{"host":"example.com","port":22,"product":"OpenSSH","version":"9.3p1"}
EOF

# Build the PostToolUse input payload
input=$(jq -nc --arg p "$OUT/recon/active/services.jsonl" \
  '{hook_event_name:"PostToolUse", tool_name:"Write", tool_input:{file_path:$p}, tool_response:{success:true}}')

run_hook() {
  printf '%s' "$input" | ACTIVE_ENGAGEMENT_LINK="$WORK/active-engagement" bash "$HOOK"
}

assert_pending_count() {
  local label="$1" expected="$2"
  local actual=0
  if [ -f "$OUT/research/_pending.jsonl" ]; then
    # Use grep -c '' so missing trailing newline still counts the last line
    actual=$(grep -c '' "$OUT/research/_pending.jsonl" 2>/dev/null || echo 0)
  fi
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $label (count=$actual)"
  else
    echo "FAIL: $label — expected $expected, got $actual"
    FAILS=$((FAILS + 1))
  fi
}

# --- First run: should queue 3 entries (nginx, WordPress, OpenSSH); skip http (noise) and malformed line ---
run_hook
assert_pending_count "first run queues 3 valid services" 3

# --- Second run with same artifact: dedup should keep count at 3 ---
run_hook
assert_pending_count "rerun dedups via flag files" 3

# --- New service appears in artifact → only the new one queues ---
echo '{"host":"example.com","port":3306,"product":"MySQL","version":"8.0.35"}' >> "$OUT/recon/active/services.jsonl"
run_hook
assert_pending_count "new line adds 1" 4

# --- Hook should be silent no-op when research/_dispatched/ missing ---
rm -rf "$OUT/research"
run_hook
if [ ! -d "$OUT/research" ]; then
  echo "PASS: hook does not create research/ when absent"
else
  echo "FAIL: hook created research/ — should be silent no-op"
  FAILS=$((FAILS + 1))
fi

# --- Hook should ignore writes outside ${OUTPUT_DIR}/(recon|enum|scan) ---
mkdir -p "$OUT/research/_dispatched"
unrelated_input=$(jq -nc --arg p "/tmp/some-other-file.jsonl" \
  '{hook_event_name:"PostToolUse", tool_name:"Write", tool_input:{file_path:$p}, tool_response:{success:true}}')
printf '%s' "$unrelated_input" | ACTIVE_ENGAGEMENT_LINK="$WORK/active-engagement" bash "$HOOK"
if [ ! -f "$OUT/research/_pending.jsonl" ]; then
  echo "PASS: ignores unrelated writes"
else
  echo "FAIL: queued an unrelated write"
  FAILS=$((FAILS + 1))
fi

rm -rf "$WORK"

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS test(s) failed."
  exit 1
fi
echo ""
echo "all discovery-watcher tests passed"
