# verify-spec

Reality-checks a freshly written spec or plan against the actual code, in-repo
docs, and API specs — using parallel read-only research agents — then applies
approved corrections. Catches gaps, additions, subtractions, and inconsistencies
before they reach the human review gate.

## Invocation

```
/verify-spec [path-to-spec-or-plan]
```

With no argument, it targets the spec/plan written most recently in the session.

## How it works

1. Resolves the artifact, its `<project>` (from the Obsidian vault path), and the
   target repo root.
2. Extracts the artifact's checkable load-bearing assumptions.
3. Decomposes them into independent slices and dispatches one read-only `Explore`
   agent per slice, concurrently.
4. Aggregates findings into a categorized report (gap / addition / subtraction /
   inconsistency) saved next to the artifact.
5. Presents the report and applies approved corrections to the artifact.

## Pipeline integration

A directive in `~/.claude/CLAUDE.md` runs verify-spec as a pre-gate in the
superpowers brainstorming (before the User Review Gate) and writing-plans (before
the Execution Handoff) flows. A bundled `PostToolUse` hook reminds the model to run
it whenever a spec/plan is written into the vault, as a deterministic backstop.

## Components

- `skills/verify-spec/SKILL.md` — the coordinator workflow.
- `hooks/hooks.json` + `scripts/verify-spec-reminder.sh` — the reminder hook.
