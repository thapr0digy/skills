---
name: verify-spec
description: Reality-checks a freshly written spec or plan against actual code, docs, and API specs using parallel read-only research agents, then applies approved corrections. Invoke via /verify-spec [path].
user_invocable: true
---

# verify-spec — Coordinator

You reality-check a spec or plan against the actual code, in-repo docs, and API
specs, surface discrepancies, and apply approved corrections. Follow every step
exactly. Make no decisions interactively except the single approval gate in Step 6.

**Announce at start:** "Using verify-spec to reality-check `<artifact path>`."

---

## Step 1 — Resolve artifact, project, and codebase root

1. **Artifact path:**
   - If an argument was provided to `/verify-spec`, use it (resolve to absolute).
   - Otherwise, use the spec/plan that was just written in this session.
2. **Resolve `<project>` (cwd-independent):**
   - *Primary:* if the artifact path contains `/superpowers/<project>/{specs,plans}/`,
     take `<project>` as the path segment immediately after `superpowers/`.
   - *Fallback:* basename of the target repo root (`git rev-parse --show-toplevel`),
     then cwd basename last.
3. **Codebase root to verify against:** run `git rev-parse --show-toplevel` in the
   relevant repo. Sanity-check its basename equals `<project>`. If they differ
   (e.g. session cwd is a parent dir), trust the vault `<project>` for the artifact
   and locate the repo whose basename matches `<project>`.

State the resolved artifact path, `<project>`, and codebase root before continuing.

## Step 2 — Extract checkable assumptions

Read the artifact in full. Enumerate its **checkable** load-bearing claims. A claim
is checkable iff it can be falsified by reading a file, running a read-only command,
or fetching a pinned spec. Pure rationale/prose is NOT extracted.

Closed list of claim types to extract:
1. file/dir paths asserted to exist;
2. symbol names (function/class/method/module) referenced as existing;
3. API surface items (proto field numbers & RPC names, OpenAPI path+method, SDK
   method signatures, OAuth/OIDC endpoints);
4. config keys / env vars;
5. dependency name + version constraints;
6. explicit doc/spec claims quoted or paraphrased from in-repo files;
7. assumed existing behaviors **that map to a named symbol or documented contract**.

Tag each extracted claim with its location in the artifact (line or section).

*Worked example:* claim "`plugins/verify-spec/.claude-plugin/plugin.json` exists"
→ check via `ls`/Read → result Confirmed or Addition.

## Step 3 — Decompose into independent streams

Group the extracted claims into N coherent, independent slices sized to the content
(NOT a fixed count). Each slice should be verifiable without depending on another
slice's result. One agent per slice. State the slices and their claim counts.

## Step 4 — Dispatch parallel read-only agents

Use the `superpowers:dispatching-parallel-agents` approach: dispatch all N agents
concurrently via the Agent/Task tool **in a single message**.

- Dispatch the built-in **`Explore`** read-only agent. (If `general-purpose` is used
  instead, the prompt MUST restrict it to read-only tools: Read, Grep/rg, Glob/fd,
  read-only Bash; forbid Edit/Write.) Never dispatch the user's custom agents
  (`go-principal-engineer`, `security-pen-tester`) — they inherit write tools.
- Give each agent: its claim slice (with artifact locations), the codebase root, and
  this REQUIRED return contract verbatim:

  ```
  ## CONFIRMED
  - <claim> — evidence (file:line + quote)
  ## DISCREPANCIES
  - [GAP|ADDITION|SUBTRACTION|INCONSISTENCY] <description> — evidence
  ## CORRECTIONS
  - <concrete edit to the artifact, with artifact location + proposed new text>
  ```

Discrepancy types:
- **GAP** — artifact requires something code/API can't support or doesn't mention.
- **ADDITION** — artifact assumes something exists that doesn't.
- **SUBTRACTION** — artifact omits something code/API actually requires.
- **INCONSISTENCY** — artifact contradicts code/docs/API, or itself.

## Step 5 — Aggregate and write the report

Merge all agent results into one categorized report grouped by the four discrepancy
types, each finding citing evidence + proposed edit. Write it (Write tool, absolute
path) to:

`/Users/pr0digy/Documents/obsidian/superpowers/<project>/specs/<YYYY-MM-DD>-<topic>-reality-check.md`

where `<topic>` matches the artifact's slug and `<YYYY-MM-DD>` is today.

## Step 6 — Present, then apply on approval

Present the categorized report to the user with the proposed edits. Ask for approval.

On approval, apply the edits to the artifact **using the Edit/Write tools against the
absolute vault file path**. Do NOT shell out to obsidian-cli: the Obsidian binary at
`/Applications/Obsidian.app/Contents/MacOS/obsidian` crashes under the command sandbox
(`Failed to create socket directory` / `mach_port_rendezvous … Permission denied`).
The vault is a normal filesystem directory, so Edit/Write is sufficient and sandbox-safe.

## Step 7 — Hand back

- If invoked from **brainstorming**: hand back to brainstorming's User Review Gate
  (step 8) so the user reviews the now-corrected spec.
- If invoked from **writing-plans**: hand back to the Execution Handoff.
- If invoked **manually**: report that corrections are applied and stop.
