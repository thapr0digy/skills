#!/usr/bin/env bash
# End-to-end integration test for Plan B hooks.
# Simulates an orchestrated run: engagement active, conductor opted-in,
# a prompt arrives, a tool gets blocked, a discovery artifact gets queued.

set -u
FAILS=0
REPO_ROOT="$(pwd)"
export PENTEST_CORE_SHARED="$REPO_ROOT/plugins/pentest-core/skills/shared"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-integration.XXXXXX")
OUT="$WORK/output"
mkdir -p "$OUT/recon/active" "$OUT/research/_dispatched"

cat > "$WORK/eng.json" <<EOF
{
  "engagement_id": "integration-test",
  "output_dir": "$OUT",
  "type": "external",
  "scope": {"in_scope":[{"type":"domain","value":"example.com","added_at":"2026-05-05T00:00:00Z"}], "out_of_scope":[]},
  "current_phase": "recon-active",
  "status": "running"
}
EOF
ln -sf "$WORK/eng.json" "$WORK/active-engagement"
export ACTIVE_ENGAGEMENT_LINK="$WORK/active-engagement"

assert() {
  local label="$1" cond="$2"
  if eval "$cond"; then
    echo "PASS: $label"
  else
    echo "FAIL: $label"
    FAILS=$((FAILS + 1))
  fi
}

# === Step 1: User submits "perform a pentest on shop.acme.com" while engagement is active ===
prompt_in='{"hook_event_name":"UserPromptSubmit","prompt":"Perform an external pentest on shop.acme.com"}'
prompt_out=$(printf '%s' "$prompt_in" | bash plugins/pentest-methodology-guard/scripts/pentest-prompt-router.sh)
assert "prompt hook detects active engagement → amendment flow" 'printf "%s" "$prompt_out" | grep -q -- "ACTIVE ENGAGEMENT DETECTED"'

# === Step 2: nmap is allowed in recon-active phase ===
nmap_in='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"nmap -sV example.com"}}'
nmap_out=$(printf '%s' "$nmap_in" | bash plugins/pentest-methodology-guard/scripts/pentest-tool-block.sh)
nmap_rc=$?
assert "nmap in recon-active → exit 0" '[ "$nmap_rc" = "0" ]'
assert "nmap in recon-active → no output (silent allow)" '[ -z "$nmap_out" ]'

# === Step 3: ffuf is denied in recon-active phase (belongs to enum-web) ===
ffuf_in='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ffuf -u https://example.com/FUZZ -w wl.txt"}}'
ffuf_out=$(printf '%s' "$ffuf_in" | bash plugins/pentest-methodology-guard/scripts/pentest-tool-block.sh)
ffuf_rc=$?
assert "ffuf in recon-active → exit 2 (deny)" '[ "$ffuf_rc" = "2" ]'
assert "ffuf in recon-active → cites enum-web skill" 'printf "%s" "$ffuf_out" | grep -q -- "pentest-enum:enum-web"'

# === Step 4: A worker writes a service-discovery JSONL artifact ===
echo '{"host":"shop.example.com","port":8080,"product":"WordPress","version":"6.4.1"}' > "$OUT/recon/active/services.jsonl"
echo '{"host":"shop.example.com","port":443,"product":"nginx","version":"1.24.0"}' >> "$OUT/recon/active/services.jsonl"
write_in=$(jq -nc --arg p "$OUT/recon/active/services.jsonl" '{hook_event_name:"PostToolUse", tool_name:"Write", tool_input:{file_path:$p}, tool_response:{success:true}}')
printf '%s' "$write_in" | bash plugins/pentest-methodology-guard/scripts/discovery-watcher.sh
pending_count=$(grep -c '' "$OUT/research/_pending.jsonl" 2>/dev/null || echo 0)
assert "discovery-watcher queues 2 entries" '[ "$pending_count" = "2" ]'
assert "queued entry includes shop.example.com" 'jq -r ".host" "$OUT/research/_pending.jsonl" | head -n1 | grep -q "shop.example.com"'

# === Step 5: Re-write same file → dedup keeps count at 2 ===
printf '%s' "$write_in" | bash plugins/pentest-methodology-guard/scripts/discovery-watcher.sh
pending_count2=$(grep -c '' "$OUT/research/_pending.jsonl" 2>/dev/null || echo 0)
assert "rerun → dedup keeps count at 2" '[ "$pending_count2" = "2" ]'

rm -rf "$WORK"

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS test(s) failed."
  exit 1
fi
echo ""
echo "integration test passed — Plan B hooks hang together"
