#!/usr/bin/env bash
# Validate that every script, agent, schema, and helper referenced in
# pentest-engage/SKILL.md actually exists on disk. Cheap canary for path typos.

set -u
SKILL="plugins/pentest-core/skills/pentest-engage/SKILL.md"
FAILS=0

[ -f "$SKILL" ] || { echo "FATAL: $SKILL does not exist"; exit 1; }

# Extract referenced paths from SKILL.md.
script_refs=$(grep -oE 'plugins/pentest-core/skills/pentest-engage/scripts/[a-z-]+\.sh' "$SKILL" | sort -u)
schema_refs=$(grep -oE 'plugins/pentest-core/skills/shared/schemas/[a-z-]+\.schema\.json' "$SKILL" | sort -u)
helper_md_refs=$(grep -oE 'plugins/pentest-core/skills/shared/[a-z-]+\.md' "$SKILL" | sort -u)
allowlist_refs=$(grep -oE 'plugins/pentest-core/skills/shared/[a-z-]+\.json' "$SKILL" | sort -u)

agent_refs=$(grep -oE 'subagent_type: [a-z-]+' "$SKILL" | awk '{print $2}' | sort -u)
skill_refs=$(grep -oE "skill='pentest-[a-z-]+:[a-z-]+'" "$SKILL" | sort -u)

assert_file() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    echo "PASS: $label ($path)"
  else
    echo "FAIL: $label — file does not exist: $path"
    FAILS=$((FAILS + 1))
  fi
}

assert_agent() {
  local name="$1"
  local md="plugins/pentest-core/agents/${name}.md"
  if [ -f "$md" ]; then
    echo "PASS: agent $name ($md)"
  else
    echo "FAIL: agent $name — file does not exist: $md"
    FAILS=$((FAILS + 1))
  fi
}

echo "=== script references ==="
while IFS= read -r p; do [ -z "$p" ] && continue; assert_file "script $(basename "$p")" "$p"; done <<< "$script_refs"

echo "=== schema references ==="
while IFS= read -r p; do [ -z "$p" ] && continue; assert_file "schema $(basename "$p")" "$p"; done <<< "$schema_refs"

echo "=== helper md references ==="
while IFS= read -r p; do [ -z "$p" ] && continue; assert_file "md $(basename "$p")" "$p"; done <<< "$helper_md_refs"

echo "=== allowlist json references ==="
while IFS= read -r p; do [ -z "$p" ] && continue; assert_file "data $(basename "$p")" "$p"; done <<< "$allowlist_refs"

echo "=== agent references ==="
while IFS= read -r a; do
  [ -z "$a" ] && continue
  case "$a" in
    pentest-worker|pentest-supervisor|pentest-research) assert_agent "$a" ;;
    *)
      echo "FAIL: unknown subagent_type '$a' in SKILL.md (not a known pentest agent)"
      FAILS=$((FAILS + 1))
      ;;
  esac
done <<< "$agent_refs"

echo "=== skill references ==="
while IFS= read -r s; do
  [ -z "$s" ] && continue
  plugin=$(printf '%s' "$s" | sed -E "s/skill='([^:]+):.+'/\1/")
  skill_name=$(printf '%s' "$s" | sed -E "s/skill='[^:]+:([^']+)'/\1/")
  candidate="plugins/${plugin}/skills/${skill_name}/SKILL.md"
  if [ -f "$candidate" ]; then
    echo "PASS: skill ${plugin}:${skill_name}"
  else
    echo "FAIL: skill ${plugin}:${skill_name} — SKILL.md not found at $candidate"
    FAILS=$((FAILS + 1))
  fi
done <<< "$skill_refs"

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS reference(s) failed validation."
  exit 1
fi
echo ""
echo "all conductor references validated"
