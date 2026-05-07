#!/usr/bin/env bash
# Validate frontmatter of all subagent definitions in pentest-core.

set -u
FAILS=0
AGENT_DIR="plugins/pentest-core/agents"

declare -A EXPECTED_TOOLS=(
  ["pentest-worker"]="Bash Read Skill Write"
  ["pentest-supervisor"]="Read Write"
  ["pentest-research"]="WebFetch WebSearch Read Write"
)

# Helper: extract a YAML field from frontmatter
extract_field_value() {
  local file="$1" field="$2"
  # Get all lines between --- delimiters, then extract the field
  awk '/^---$/{if(++n==1)next;if(n==2)exit} n==1 && /^'"$field"':/{print; exit}' "$file" | sed "s/^$field:[[:space:]]*//;s/^['\"]//;s/['\"]$//"
}

# Helper: extract tools array and sort them
extract_and_sort_tools() {
  local file="$1"
  # Extract the tools line, remove brackets and quotes, split on comma, and sort
  extract_field_value "$file" "tools" | tr -d '[]"' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort
}

for name in "${!EXPECTED_TOOLS[@]}"; do
  file="$AGENT_DIR/$name.md"
  if [ ! -f "$file" ]; then
    echo "FAIL: $name → $file does not exist"
    FAILS=$((FAILS + 1))
    continue
  fi

  # Check frontmatter delimiters
  if ! head -1 "$file" | grep -q '^---$'; then
    echo "FAIL: $name → missing frontmatter opening delimiter"
    FAILS=$((FAILS + 1))
    continue
  fi

  # Validate name
  actual_name=$(extract_field_value "$file" "name")
  if [ "$actual_name" != "$name" ]; then
    echo "FAIL: $name → name mismatch: got '$actual_name', expected '$name'"
    FAILS=$((FAILS + 1))
    continue
  fi

  # Validate description
  desc=$(extract_field_value "$file" "description")
  if [ -z "$desc" ] || [ ${#desc} -lt 30 ]; then
    echo "FAIL: $name → description missing or too short (length: ${#desc})"
    FAILS=$((FAILS + 1))
    continue
  fi

  # Validate tools
  actual_tools=$(extract_and_sort_tools "$file")
  expected_tools=$(echo "${EXPECTED_TOOLS[$name]}" | tr ' ' '\n' | sort)

  if [ "$actual_tools" != "$expected_tools" ]; then
    echo "FAIL: $name → tool mismatch"
    echo "  Got:      $(echo "$actual_tools" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    echo "  Expected: $(echo "$expected_tools" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    FAILS=$((FAILS + 1))
    continue
  fi

  echo "PASS: $name frontmatter valid"
done

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS test(s) failed."
  exit 1
fi
echo ""
echo "all agent-frontmatter tests passed"
