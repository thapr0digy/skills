#!/usr/bin/env bash
# Test pentest-prompt-router.sh against fixture inputs.
# Usage: bash tests/test-prompt-reminder.sh

set -u
HOOK="plugins/pentest-methodology-guard/scripts/pentest-prompt-router.sh"
FIXDIR="tests/fixtures/hooks"
FAILS=0

# Set up a temporary active-engagement link for the "with engagement" cases
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-prompt-reminder-XXXXXX")
cp tests/fixtures/active-engagement/engagement.json "$WORK/eng.json"
ln -sf "$WORK/eng.json" "$WORK/active-engagement"

run_with_engagement() {
  ACTIVE_ENGAGEMENT_LINK="$WORK/active-engagement" bash "$HOOK" < "$1"
}
run_without_engagement() {
  ACTIVE_ENGAGEMENT_LINK="$WORK/no-such-link" bash "$HOOK" < "$1"
}

assert_contains() {
  local label="$1" actual="$2" needle="$3"
  if printf '%s' "$actual" | grep -qF -- "$needle"; then
    echo "PASS: $label"
  else
    echo "FAIL: $label — expected substring not found"
    echo "  needle: $needle"
    echo "  actual: $actual"
    FAILS=$((FAILS + 1))
  fi
}

assert_empty() {
  local label="$1" actual="$2"
  if [ -z "$actual" ]; then
    echo "PASS: $label"
  else
    echo "FAIL: $label — expected empty output, got:"
    echo "  $actual"
    FAILS=$((FAILS + 1))
  fi
}

# Case 1: start regex, no active engagement → conductor invocation
out=$(run_without_engagement "$FIXDIR/prompt-start-no-engagement.json")
assert_contains "start/no-engagement → invoke conductor" "$out" "PENTEST ENGAGEMENT REQUEST DETECTED"

# Case 2: start regex, active engagement → amendment flow
out=$(run_with_engagement "$FIXDIR/prompt-start-with-engagement.json")
assert_contains "start/with-engagement → amendment flow" "$out" "ACTIVE ENGAGEMENT DETECTED"
assert_contains "start/with-engagement → references --amend" "$out" "--amend"

# Case 3: resume regex → conductor with resume
out=$(run_without_engagement "$FIXDIR/prompt-resume.json")
assert_contains "resume → conductor with resume" "$out" "PENTEST RESUME REQUEST DETECTED"

# Case 4: no match → silent
out=$(run_without_engagement "$FIXDIR/prompt-no-match.json")
assert_empty "unrelated prompt → no output" "$out"

rm -rf "$WORK"

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS test(s) failed."
  exit 1
fi
echo ""
echo "all prompt-reminder tests passed"
