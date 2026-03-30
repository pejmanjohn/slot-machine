---
name: slot-machine
description: Use when a well-specified task has meaningful design choices and you want to maximize quality by comparing multiple independent attempts. Works for coding, writing, and custom task types. Triggers on "slot-machine", "best-of-N", "pull the lever", "parallel implementations", or when quality matters more than speed and the spec is clear enough for independent work.
---

# Slot Machine

**Best-of-N parallel implementation for any task type.**

Run N independent attempts at the same spec in parallel. Review each. Pick the best — or synthesize the best elements into a single winner.

**Core principle:** LLMs are probabilistic. More attempts = better outcomes. Trade compute for quality.

**Announce at start:** "I'm using the slot-machine skill ({profile_name} profile) to run N parallel implementations."

## What This Is NOT

Standard multi-agent patterns split DIFFERENT tasks across agents (frontend, backend, tests in parallel). Every major tool does this — it's table stakes.

**Slot-machine gives the SAME spec to N agents and compares their FULL attempts.** The value isn't parallelism — it's competition and selection. Each slot is an independent attempt at the same task, not a piece of a divided workload. This applies to any task type — coding, writing, or custom profiles.

If you want to split a plan into parallel tasks, use **superpowers:dispatching-parallel-agents** instead.

## When to Use

```dot
digraph when_to_use {
    "Have a clear spec?" [shape=diamond];
    "Design choices exist?" [shape=diamond];
    "Quality worth the compute?" [shape=diamond];
    "Use slot-machine" [shape=box, style=bold];
    "Write spec first (brainstorm)" [shape=box];
    "Single implementation" [shape=box];
    "Single implementation (mechanical)" [shape=box];

    "Have a clear spec?" -> "Design choices exist?" [label="yes"];
    "Have a clear spec?" -> "Write spec first (brainstorm)" [label="no"];
    "Design choices exist?" -> "Quality worth the compute?" [label="yes"];
    "Design choices exist?" -> "Single implementation (mechanical)" [label="no"];
    "Quality worth the compute?" -> "Use slot-machine" [label="yes"];
    "Quality worth the compute?" -> "Single implementation" [label="no"];
}
```

**Use when:**
- Feature is well-specified (clear enough for independent implementation)
- Quality matters more than speed or cost
- Medium complexity (1-4 hours of agent work per attempt)
- Implementation has meaningful design choices (architecture, patterns, tradeoffs)

**Don't use when:**
- Simple mechanical changes (rename, add a field, update a config)
- Feature needs heavy human-in-the-loop iteration during implementation
- You already know exactly how it should be built
- Spec is too vague for independent attempts (brainstorm first)
- Task is purely mechanical with no design choices — 5 attempts at "add a column" is burning money

## Configuration

Check for config in the project's `CLAUDE.md` or `AGENTS.md` — treat them as equal sources. User can override inline (e.g., "slot-machine this with 3 slots").

| Setting | Default | Description |
|---------|---------|-------------|
| `slots` | 3 | Number of parallel attempts |
| `approach_hints` | true | Give each slot a different architectural direction |
| `auto_synthesize` | true | Allow judge to combine elements from multiple slots |
| `max_retries` | 1 | Re-run failed slots (0 = no retry) |
| `manual_handoff` | false | Stop after per-slot review and hand reviewed candidates back to the user for manual selection and merge |
| `cleanup` | true | Delete worktrees after completion |
| `quiet` | false | Suppress progress tables — only show final verdict + output path. For autonomous loops. |
| `implementer_model` | inherit | Model for implementer subagents (inherits from session if not set) |
| `reviewer_model` | inherit | Model for reviewer subagents (inherits from session if not set) |
| `judge_model` | inherit | Model for judge subagent (inherits from session if not set) |
| `synthesizer_model` | inherit | Model for synthesizer subagent (inherits from session if not set) |

## Profile Loading

Profiles define the task-specific content for a slot-machine run: approach hints, agent prompts, isolation strategy, and pre-check commands. SKILL.md is a domain-agnostic orchestration engine — all task-specific content comes from the active profile.

### Profile Discovery (order of precedence)

1. **Explicit:** user says `--profile X` or `profile: X`
2. **Project default:** `CLAUDE.md` sets `slot-machine-profile: X`
3. **Local:** `./profiles/` folders in the project
4. **User:** `~/.slot-machine/profiles/` (community or personal profiles)
5. **Skill:** `profiles/` in the slot-machine skill directory (the built-in profiles)
6. **Fallback:** `coding`

### Profile Selection Logic

- If explicit or project-configured → use it
- If not → auto-detect between coding/writing from spec signals:
  - **Coding signals:** implement, build, create, fix, refactor; references to tests, APIs, functions
  - **Writing signals:** write, draft, compose, describe; references to audience, tone, structure
- If not confident → ask one question: "This spec could be a coding task or a writing task. Which profile should I use?"

### Profile Inheritance Resolution

- If profile has `extends: X`, read base profile X first
- Overlay the extending profile's files on top
- Files present in extending profile's folder replace base files entirely
- Missing files are inherited from the base folder
- Frontmatter fields override individually
- Max one level of inheritance

### Universal Variables

SKILL.md injects these variables into ALL profile prompts. If a variable isn't relevant for the active profile (e.g., `{{PRE_CHECK_RESULTS}}` for writing), pass an empty string.

| Variable | Description |
|----------|-------------|
| `{{SPEC}}` | Full text of the spec/brief |
| `{{APPROACH_HINT}}` | The hint assigned to this slot |
| `{{PROJECT_CONTEXT}}` | README, architecture notes, CLAUDE.md conventions, reference materials |
| `{{SLOT_NUMBER}}` | This slot's number |
| `{{PRE_CHECK_RESULTS}}` | Output from pre-check commands (empty string if `pre_checks` is null) |
| `{{IMPLEMENTER_REPORT}}` | The implementer's status report |
| `{{WORKTREE_PATH}}` | Path to this slot's worktree or output file |
| `{{ALL_SCORECARDS}}` | All reviewer scorecards concatenated |
| `{{WORKTREE_PATHS}}` | List of all slot worktree/output paths |
| `{{SLOT_COUNT}}` | Number of successful slots |
| `{{SYNTHESIS_PLAN}}` | The judge's synthesis plan |
| `{{BASE_SLOT_PATH}}` | The worktree/output path of the base slot |
| `{{APPROACH_HINT_USED}}` | The approach hint given to the implementer (used in reviewer context) |
| `{{TEST_COMMAND}}` | How to run the test suite (empty string if not applicable) |

When filling `{{TEST_COMMAND}}` for Python repos, prefer `python3 -m pytest ...` unless the project already standardizes on another command. Do not assume a bare `python` executable exists.

## Slot Definitions

Slots can be configured per-slot instead of using the same profile implementer for all. Two axes compose with `+`:

- **Skills** (`/superpowers:test-driven-development`, `/ce:work`) — methodology guidance, slash-prefixed. Injected into the prompt of whatever harness runs the slot.
- **Harnesses** (`codex`, `gemini`) — which AI system executes. No slash prefix. Determines the dispatch mechanism.

### Slot Definition Sources (precedence)

1. **Inline:** Parsed from the user's command. Slash-prefixed names are skills, bare names are harnesses. `+` composes them. `default` means profile implementer + approach hint.
2. **`CLAUDE.md` or `AGENTS.md` config:** Read `slot-machine-slots` from either file if present — they are equal sources:
   ```markdown
   slot-machine-slots:
     - /superpowers:test-driven-development
     - /ce:work
     - codex
     - /superpowers:test-driven-development + codex
     - default
   ```
3. **Profile defaults:** If no slot definitions found, all slots use the profile's implementer prompt with randomly assigned approach hints. This is the Phase 1 behavior — unchanged.

### Parsing Rules

- If the user specifies slot definitions AND a slot count higher than the number of definitions, remaining slots get profile defaults with approach hints
- If the user specifies only slot definitions (no count), the slot count equals the number of definitions
- Each slot definition is a tuple: `(skill, harness)`:
  - `default` → `(null, null)` — profile implementer + hint
  - `/superpowers:test-driven-development` → `("/superpowers:test-driven-development", null)` — Claude Code with skill
  - `codex` → `(null, "codex")` — Codex with generic prompt
  - `/superpowers:test-driven-development + codex` → `("/superpowers:test-driven-development", "codex")` — Codex with skill

### Skill Name Translation for External Harnesses

Slot definitions use Claude Code's `/` prefix for skills. External harnesses use different syntax. When dispatching a skill to a non-Claude harness, translate the prefix:

- **Codex:** `/superpowers:test-driven-development` → `$superpowers:test-driven-development` (replace `/` with `$`)
- **Future harnesses:** follow their native skill invocation syntax

The skill is invoked natively by the target harness — Codex loads its own copy of the skill, not a text summary. The user is responsible for ensuring the skill is installed on the target harness.

### Approach Hints and Skill Slots

Approach hints only apply to `default` slots. Skill-based slots do NOT get approach hints — the skill IS the diversity mechanism. When mixing skill and default slots, assign hints only to the default slots.

### Poor Slot Candidate Warning

If a parsed skill name matches a known multi-agent orchestrator (`/superpowers:subagent-driven-development`, `/superpowers:executing-plans`), warn the user: "⚠ {skill} is a multi-agent orchestrator — running it inside a slot creates nested pipelines (slower, redundant review). Consider using a single-session skill like /superpowers:test-driven-development instead." Do not block — the user may have a reason.

## Skill Discovery

When the user says "all my skills", "all implementation skills", or uses `--discover`, the orchestrator scans for available slot-compatible skills and proposes a slot configuration.

### Trigger Rules (strict — never auto-fires)

| User says | Discovery fires? |
|-----------|-----------------|
| `/slot-machine this` | No — default profile + hints |
| `/slot-machine this with 3 slots` | No — default hints |
| `/slot-machine this with /superpowers:test-driven-development and codex` | No — explicit list |
| `/slot-machine this with all my skills` | **Yes** |
| `/slot-machine this using all implementation skills` | **Yes** |
| `/slot-machine --discover` | **Yes** |

Discovery ONLY fires on explicit "all my/implementation skills" language or `--discover`. Never as a suggestion. Never as a default.

### Detection Heuristic

1. Read skill descriptions from the system prompt
2. Filter by signals:
   - **Include:** "implement", "build", "execute plan", "write code", "development workflow"
   - **Exclude:** "review", "deploy", "ship", "test-only", "audit", "monitor", "debug"
3. Filter out known poor candidates: `/superpowers:subagent-driven-development`, `/superpowers:executing-plans`
4. Check for external harnesses: run `which codex`, `which gemini` via Bash
5. Propose the filtered list to the user

### First-Time Flow

```
I scanned your installed skills and detected these slot-compatible workflows:

  1. /superpowers:test-driven-development — test-first development
  2. /ce:work — pattern-matching execution
  3. codex — OpenAI Codex (external harness)

Use all 3 as slots? Or adjust?
```

User confirms or edits. Save selection to `~/.slot-machine/config.md`:

```markdown
## Discovered Implementation Skills
- /superpowers:test-driven-development
- /ce:work
- codex
```

### Subsequent Runs

"All my skills" loads the saved list without re-scanning. User can re-trigger a fresh scan with `--discover`.

## The Process

### Phase 1: Setup

0. **Load profile.** Follow the [Profile Loading](#profile-loading) section to find the active profile folder and read `0-profile.md` from it for config. Report to user: "Using profile: {profile_name}"

1. **Parse slot definitions.** Check for slot definitions in precedence order: (1) inline in the user's command, (2) `slot-machine-slots` in `CLAUDE.md` or `AGENTS.md` (equal sources), (3) fall back to profile defaults. Record the slot list — each slot is `(skill, harness)` or `default`. Check harness availability (see below).

   **Check harness availability and detect model.** For each slot that specifies a harness:
   - `codex`: Run `which codex` via Bash. If not found, warn: 'Codex CLI not found — slot {i} will fall back to Claude Code. Install: `npm install -g @openai/codex`'. Change the slot's harness to `null` (falls back to Claude Code with the same skill guidance if any). If found, read the Codex model version from `~/.codex/config.toml` (look for `model = "..."` line). Record this as the slot's model identifier (e.g., `gpt-5.4`).
   - **Claude Code slots:** The model is the session model (e.g., `claude-opus-4-6`) or the configured `implementer_model` override.
   - Future harnesses: same pattern — check binary, read model from config, warn and fall back if missing.

2. **Validate the spec.** The spec (plan, requirements doc, or inline description) must be concrete enough for independent attempts. If ambiguous — stop and ask for clarification before spending compute.

   Red flags that mean "not ready":
   - "Something like..." or "maybe we could..."
   - Missing acceptance criteria
   - References to external context not provided
   - Contradictory requirements

3. **Gather project context.** Collect what implementers need:
   - README or architecture docs (if they exist)
   - Key file descriptions relevant to the task
   - Test patterns and how to run tests (if applicable)
   - Any CLAUDE.md conventions
   - Reference materials, style guides, or source material (for writing tasks)

   Keep context focused — don't dump everything. Implementers should get just enough to orient themselves.

4. **Create run directory.** Create the run storage directory and add `.slot-machine/` to `.gitignore` if not already present:
   ```bash
   RUN_DIR_REL=".slot-machine/runs/$(date +%Y-%m-%d)-{feature_slug}"
   RUN_DIR="$PWD/$RUN_DIR_REL"
   mkdir -p "$RUN_DIR"
   grep -q '.slot-machine/' .gitignore 2>/dev/null || echo '.slot-machine/' >> .gitignore
   ```
   Persist `RUN_DIR` as the absolute path for this run. All review, verdict, and result artifacts must be written via that absolute path, not a cwd-relative redirect. Before every artifact write later in the run, re-run `mkdir -p "$RUN_DIR"` so artifact persistence never depends on shell state.
   All artifacts from this run will be saved to `{RUN_DIR}/`.

5. **Prepare isolation.** Check the profile's `isolation` field:
   - If `worktree`: The project MUST be a git repository with at least one commit before Phase 2 can create worktrees. If the directory is not a git repo or has no commits:
     ```bash
     git init && git add -A && git commit -m "initial commit"
     ```
     Without this, `isolation: "worktree"` on Agent calls will fail and agents will not get isolated workspaces.
     Record the original checkout before dispatching any slots so Phase 4 can restore it if needed:
     ```bash
     ORIGINAL_HEAD=$(git rev-parse HEAD)
     ORIGINAL_BRANCH=$(git symbolic-ref --short -q HEAD || true)
     ```
   - If `file`: No git repo required. Each slot will write its output to `{RUN_DIR}/slot-{i}.md`.

6. **Run pre-checks (if configured).** Read the active profile's `0-profile.md` frontmatter for the `pre_checks` field.
   - If `null` → skip this step.
   - If set → run the pre-check commands, substituting `{test_command}` with the detected test command. These establish the baseline. If baseline checks fail, stop and fix first.

7. **Assign approach hints.** If `approach_hints` is enabled, read hints from the active profile's `0-profile.md`. Randomly assign one hint per slot (without replacement). Each hint steers toward a different approach — the profile defines what diversity means for this task type.

8. **Report setup to user** using this format (top-level markdown, not inside a code block):

   **Slot Machine** — `{profile_name}` profile

   Feature: {feature_name}
   Slots: `{N}` | /ce:work (`claude-opus-4-6`), /ce:work + codex (`gpt-5.4`), codex (`gpt-5.4`), 2x default hints (`claude-opus-4-6`)

   When all slots use profile defaults (no slot definitions):

   Slots: `{N}` | Hints: {hint_1}, {hint_2}, ...

   Formatting rules for ALL orchestrator output (apply throughout Phases 1-4):
   - Tables MUST be top-level markdown — never indented or inside code blocks
   - Status values in backticks: `DONE`, `PASS`, `FAIL`, `HIGH`, `MEDIUM`, `LOW`
   - Profile name and key numbers in backticks
   - Bold for phase labels and verdicts
   - No italics anywhere — they de-emphasize in monospace terminals
   - Verdict section bounded by horizontal rules (`---`) — no blockquotes (they render as dim italics in terminals)
   - H1 (`#`) for Final Output header only

### Phase 2: Parallel Implementation

**Dispatch all N slots in a SINGLE message** using N parallel Agent tool calls. This is critical — all calls must be in one message for true parallel execution.

Dispatch is uniform: all slots dispatch via the Agent tool regardless of harness. For Codex slots, the subagent wraps `codex exec` internally and returns a standard implementer report. For mixed-harness runs, dispatch is transparent.

Never launch Codex slots as background Bash jobs from the orchestrator. The Codex wrapper agent must wait for `codex exec` to finish, harvest the final report or synthesize one from post-run inspection, and only then return control to the review/judge pipeline.

---

**Path A — Default slots (no skill, no harness):**

Unchanged from Phase 1. Read `1-implementer.md` from the active profile, fill universal `{{VARIABLES}}`, include the assigned approach hint. Dispatch via Agent tool with `isolation: "worktree"` (or omit if `file` profile).

For each slot i (1 to N), make an Agent tool call with:

| Parameter | Value |
|-----------|-------|
| `description` | `"Slot {i}: Implement {feature_name}"` |
| `isolation` | `"worktree"` if profile isolation is `worktree`; omit if `file` |
| `model` | Omit unless user configured `implementer_model` — inherits from session by default |
| `prompt` | Read `1-implementer.md` from the active profile's folder and fill in all universal `{{VARIABLES}}` |

The universal variables to fill in the implementer prompt:

| Variable | Source |
|----------|--------|
| `{{SPEC}}` | Full text of the spec — paste it, don't make the subagent read a file |
| `{{APPROACH_HINT}}` | The hint assigned to this slot (or omit section if hints disabled) |
| `{{PROJECT_CONTEXT}}` | README, architecture notes, CLAUDE.md conventions, reference materials gathered in Phase 1. Include any user-specified skill guidance. |
| `{{TEST_COMMAND}}` | How to run the test suite (empty string if not applicable) |

For Python projects, prefer `python3 -m pytest ...` unless the repo already provides an explicit test command. Do not invent `python -m pytest` on systems that only guarantee `python3`.

**For `file` isolation:** Each slot writes its output to `{RUN_DIR}/slot-{i}.md`. Include this path in the prompt so the implementer knows where to write. No worktrees, no git branches.

**For `worktree` isolation — worktree fallback:** If `isolation: "worktree"` fails (e.g., git repo not detected, permission issues), fall back to manual worktree creation:

```bash
mkdir -p .slot-machine/worktrees
for i in $(seq 1 $N); do
    git worktree add ".slot-machine/worktrees/slot-$i" -b "slot-machine/{feature_name}/slot-$i"
done
```

Then dispatch implementers WITHOUT `isolation: "worktree"`, pointing each to its worktree directory. Track worktree paths manually for cleanup in Phase 4. For `worktree` isolation, save each slot's diff to `{RUN_DIR}/slot-{i}.diff` before cleanup.

---

**Path B — Skill-only slots (e.g., `/superpowers:test-driven-development`, no harness):**

Do NOT read the profile's `1-implementer.md`. Dispatch via Agent tool with this prompt:

```
You are implementing a feature in an isolated workspace.

IMPORTANT: You MUST invoke the {skill_name} skill using the Skill tool before beginning implementation. Follow its workflow exactly.

Specification:
{spec}

Project Context:
{project_context}

After implementation is complete, end with this report format:
**Status:** [DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT]
**What I implemented:** [bullet list]
**Files changed:** [list]
**Test results:** [if applicable]
**Concerns (if any):** [issues]
```

Use `isolation: "worktree"` on the Agent call. Do NOT include an approach hint — the skill is the diversity mechanism.

---

**Path C — Codex slots (harness = `codex`, with or without skill):**

Dispatch via Agent tool — same as Paths A and B. The subagent acts as a thin wrapper that runs `codex exec` and translates the output into a standard implementer report.

This wrapper path is the supported Claude-host Codex execution path. Do not replace it with a raw background shell launch: the wrapper must return a normal implementer report before reviewers or the judge can run.

Agent tool call:

| Parameter | Value |
|-----------|-------|
| `description` | `"Slot {i}: Implement {feature_name} (via Codex)"` |
| `isolation` | `"worktree"` if profile isolation is `worktree`; omit if `file` |
| `model` | Omit (the subagent is a wrapper — the actual model is Codex's) |
| `prompt` | See Codex wrapper prompt below |

**Codex wrapper prompt:**

```
You are a wrapper agent that dispatches implementation to Codex CLI and reports back.

1. Run `codex exec` in the current directory using the Bash tool. Save the raw `--json` JSONL stream to `codex-events.jsonl`, then parse it. Do not assume a single event mix — current Codex runs may expose `item.completed`, `turn.completed`, or both.

   ```bash
   codex exec "{If skill specified: '$codex_skill_name\n\n'}Implement this specification. Write all files to the current directory.
   Do not ask questions or wait for confirmation — make your best judgment and proceed.

   Specification:
   {spec}

   Project context:
   {project_context}

   When done, provide a summary of:
   - What you implemented (bullet list)
   - Files created or modified
   - Test results if you wrote tests
   - Any concerns or issues encountered" \
     -s workspace-write \
     -c 'model_reasoning_effort="high"' \
     --json > codex-events.jsonl 2>codex-stderr.txt
   codex_rc=$?

   python3 - <<'PY' > codex-report.txt
   import json
   import pathlib

   messages = []
   commands = []
   saw_turn_completed = False

   for line in pathlib.Path("codex-events.jsonl").read_text(encoding="utf-8").splitlines():
       line = line.strip()
       if not line:
           continue
       try:
           obj = json.loads(line)
       except json.JSONDecodeError:
           continue

       event_type = obj.get("type", "")
       if event_type == "item.completed":
           item = obj.get("item", {})
           if item.get("type") == "agent_message" and item.get("text"):
               messages.append(item["text"].strip())
           elif item.get("type") == "command_execution" and item.get("command"):
               commands.append(item["command"].strip())
       elif event_type == "turn.completed":
           saw_turn_completed = True

   if messages:
       print(messages[-1])
   elif commands:
       for command in commands:
           print(f"[codex ran] {command}")
   elif saw_turn_completed:
       print("[codex completed successfully but did not expose a structured agent message]")
   PY
   ```

2. After `codex exec` completes:
   - If non-zero exit code or timeout → report Status: BLOCKED with error details.
   - Otherwise inspect meaningful workspace output deterministically:
     - Prefer `git status --short --untracked-files=all` to build the changed-file list.
     - If git is unavailable, fall back to listing files created or modified during the run by other deterministic shell means.
   - If `codex-report.txt` contains a structured implementer message, translate it directly.
   - If the JSON stream only shows `turn.completed` or otherwise lacks a structured agent message, but the run exited zero and files changed, synthesize the standard implementer report from post-run inspection:
     - `Status: DONE` if the captured command executions include an obvious test command or result.
     - `Status: DONE_WITH_CONCERNS` if files changed but no structured test summary was extractable.
     - `What I implemented:` include a bullet noting that the wrapper synthesized the report from post-run inspection.
     - `Files changed:` list the deterministic changed files.
     - `Test results:` include observed test commands if available; otherwise say no structured test summary was extractable from the Codex JSON stream.
     - `Concerns (if any):` note that Codex emitted `turn.completed` without a structured agent message report.
   - If `codex exec` exits zero but there is no structured report and no meaningful workspace output, report Status: BLOCKED.
   - Once the report is ready, commit files: `git add -A && git commit -m "feat: {feature_name}"`

3. Read `codex-report.txt` and translate to standard report format:

   **Status:** DONE, DONE_WITH_CONCERNS, or BLOCKED
   **What I implemented:** [from Codex report, or synthesized from post-run inspection]
   **Files changed:** [deterministic changed-file list]
   **Test results:** [from Codex report or observed test commands]
   **Concerns (if any):** [from Codex report, or note the missing structured agent message]
```

Do NOT include an approach hint — for bare `codex` slots, the prompt has no skill prefix. For `skill + codex` slots, the `$codex_skill_name` prefix triggers native skill loading in Codex.

---

| Slot definition | Dispatch | Prompt | Isolation | Hint? |
|----------------|----------|--------|-----------|-------|
| `default` | Agent tool | Profile `1-implementer.md` + hint | Profile setting | Yes |
| `/superpowers:test-driven-development` | Agent tool | "Invoke {skill} via Skill tool" + spec | worktree | No |
| `codex` | Agent tool (Codex wrapper) | Wrapper runs `codex exec` with spec | worktree | No |
| `/superpowers:test-driven-development + codex` | Agent tool (Codex wrapper) | Wrapper runs `codex exec` with `$superpowers:test-driven-development` | worktree | No |

---

**After all agents return**, process each result:

| Result | Action |
|--------|--------|
| Agent succeeded, implementer status DONE | Record worktree path + branch. Save implementer report. Run pre-checks and dispatch reviewer (see Phase 3 streaming). |
| Agent succeeded, status DONE_WITH_CONCERNS | Record path. Save report including concerns. Run pre-checks and dispatch reviewer. |
| Agent succeeded, status BLOCKED or NEEDS_CONTEXT | If `max_retries` > 0: re-dispatch with additional context. Else: mark FAILED. |
| Agent errored/crashed | If `max_retries` > 0: re-dispatch fresh. Else: mark FAILED. |

**Retry handling:** When retrying, dispatch a SINGLE Agent call (not parallel) with the same template but additional context addressing the block. Use a fresh subagent — don't try to continue the failed one.

**Report progress** using a top-level markdown table. For writing profiles, show word count. For coding profiles, show test count. Include a one-line summary of each slot's approach (from the hint influence):

**Phase 2:** Implementation — `done`

| Slot | Status | Model | Words/Tests | Approach |
|------|--------|-------|-------------|----------|
| 1 | `DONE` | `claude-opus-4-6` | 13 tests | /superpowers:test-driven-development |
| 2 | `DONE` | `gpt-5.4` | 15 tests | /superpowers:test-driven-development + codex |
| 3 | `DONE` | `claude-opus-4-6` | 21 tests | /ce:work |
| 4 | `DONE_WITH_CONCERNS` | `gpt-5.4` | 8 tests | codex |

Do NOT show full implementer reports, self-review findings, or file lists. The table summarizes the essential information. Agent internals are pipeline noise.

**Minimum viable:** At least 2 successful slots needed for meaningful comparison. If fewer than 2 succeed, report to user and recommend: re-run with different slot count, fix spec issues, or manual implementation.

### Phase 3: Review and Judgment

**The review/judgment pipeline is the skill's core value.** Baseline testing showed that Claude naturally does parallel dispatch and even synthesis — but it centralizes all evaluation in the orchestrator. This phase delegates evaluation to specialized agents for higher-quality, unbiased assessment.

#### Streaming Review: Review as Slots Complete

**Do NOT wait for all implementations to finish before starting reviews.** As each slot completes, immediately run its pre-checks and dispatch its reviewer. This overlaps review work with implementation — a slot that finishes early gets reviewed while slower slots are still implementing.

**For each slot, as it returns successfully:**

1. **Run pre-checks** for that slot. If `pre_checks` is `null`, skip and pass an empty string for `{{PRE_CHECK_RESULTS}}`. If set, `cd` into the slot's worktree first, then run the commands. Every pre-check Bash command must start with `cd {worktree_path} &&` — do not assume the shell is already in the right directory.

2. **Dispatch its reviewer immediately** — do not wait for other slots. Make an Agent tool call with:

| Parameter | Value |
|-----------|-------|
| `description` | `"Review Slot {i} implementation"` |
| `model` | Omit unless user configured `reviewer_model` — inherits from session by default |
| `prompt` | Read `2-reviewer.md` from the active profile's folder and fill in all universal `{{VARIABLES}}` |

The universal variables to fill in the reviewer prompt:

| Variable | Source |
|----------|--------|
| `{{SPEC}}` | Full text of the original spec |
| `{{IMPLEMENTER_REPORT}}` | The implementer's status report (what they claim they built) |
| `{{WORKTREE_PATH}}` | Path to this slot's worktree or output file (from Phase 2 results) |
| `{{SLOT_NUMBER}}` | This slot's number |
| `{{PRE_CHECK_RESULTS}}` | Pre-check output from the step above (empty string if pre_checks is null) |
| `{{APPROACH_HINT_USED}}` | The approach hint that was given to this slot's implementer |

The reviewer reads actual content in the worktree/output file — it does NOT have `isolation: "worktree"` (it inspects existing work, not its own workspace).

**When multiple slots complete close together**, batch their reviewers into a single message for parallel dispatch — this is faster than dispatching one at a time. The key rule is: don't wait for stragglers. If 2 of 3 slots are done, dispatch their 2 reviewers now rather than waiting for the 3rd.

**Collect reviews as they return.** Save each reviewer's full scorecard to `{RUN_DIR}/review-{i}.md` immediately when that reviewer finishes. Use the absolute path from `RUN_DIR` when persisting the file. If you use Bash, run `mkdir -p "$RUN_DIR"` immediately before the write; if you use a file-write tool, pass the same absolute path. Do NOT postpone these writes until after the summary table, and do NOT replace the saved scorecard with only your orchestrator summary. Never rely on the current shell directory for artifact redirects.

**Before dispatching the judge, verify the review artifacts exist.** For every successful slot, confirm `{RUN_DIR}/review-{i}.md` exists and is non-empty. If any scorecard file is missing, write it before continuing. The judge phase is not allowed to start with missing review artifacts.

**Report review results** after all reviews are collected, using a top-level markdown table and standout bullets. Do NOT show full reviewer scorecards, evidence chains, or pass-by-pass analysis — those are pipeline internals the judge uses, not the user.

**Phase 3:** Review — `done`

| Slot | Compliance | Critical | Important | Minor | Verdict |
|------|------------|----------|-----------|-------|---------|
| 1 | `PASS` | 0 | 0 | 3 | **Contender** |
| 2 | `PASS` | 0 | 1 | 2 | **Contender** |
| 3 | `FAIL` | 1 | 0 | 1 | Eliminated |

**Standout elements:**
- Slot 1: {the reviewer's top strength for this slot — one line}
- Slot 2: {the reviewer's top strength}

Extract standout elements from each reviewer's "Strengths" section. Pick the single most notable strength per slot — the one the judge is most likely to care about.

#### Manual Handoff

If `manual_handoff` is true:

This is the terminal path for the run. Skip the judge/verdict/merge finalization path below and use the manual handoff report instead.

- Do NOT dispatch the judge
- Do NOT dispatch the synthesizer
- Do NOT auto-merge or copy a winning result
- For `worktree` isolation, preserve all successful slot worktrees
- For `file` isolation, preserve slot output files and reviews
- For `worktree` isolation, restore the user's original checkout before the final report. Manual mode must not leave the main worktree on a slot branch, detached at a slot commit, or merged to a winner.
- Write `{RUN_DIR}/handoff.md`
- Write `{RUN_DIR}/slot-manifest.json`
- Write manual-mode `{RUN_DIR}/result.json`
- Refresh `.slot-machine/runs/latest` before finalizing manual-mode `result.json`
- Compose the user-facing final section headed `# Manual Handoff`
- Report the reviewed candidates and next steps to the user
- STOP. Do not read or follow any judged-run verdict/final-report instructions below this block when `manual_handoff` is true.

Manual handoff output for coding/worktree runs must include at minimum:

- The exact H1 heading `# Manual Handoff`
- A slot summary table with each successful slot's status and reviewer counts or verdict summary
- Artifact paths for the slot diff, worktree path, branch name, head SHA, review markdown, `handoff.md`, `slot-manifest.json`, and manual-mode `result.json`
- Next-step guidance for manual selection, merge, and any follow-up verification

Before emitting the final manual handoff report for `worktree` isolation, restore the main checkout recorded in Phase 1:

```bash
if [ -n "${ORIGINAL_BRANCH:-}" ]; then
    git switch "$ORIGINAL_BRANCH"
else
    git checkout --detach "$ORIGINAL_HEAD"
fi
```

If the restore fails, report `BLOCKED` instead of silently leaving the user on the wrong checkout. Manual handoff is only complete when the main worktree is back on the original branch/HEAD and the reviewed slot worktrees remain available for inspection.

Persist the per-slot diff, branch, path, SHA, review, file-change, and test metadata in `{RUN_DIR}/result.json` under `slot_details`. For manual handoff, `slot_details` is the source of truth for per-slot file/test data and artifact metadata in both `worktree` and `file` isolation.
In manual mode, write the top-level `handoff_path` and `run_dir` fields as the canonical absolute `.slot-machine/runs/latest/...` paths so scripts can follow a stable location without resolving the dated run directory themselves.
`{RUN_DIR}/slot-manifest.json` mirrors the same per-slot metadata as the human-readable handoff summary so manual selection can happen without reading `result.json`.

#### Dispatch the judge immediately

If `manual_handoff` is false:

As soon as all reviews are collected, dispatch the judge — do not pause for orchestrator reporting. The review report table above can be shown *after* the judge is already running, or combined with the verdict output. The goal is to eliminate idle time between the last review returning and the judge starting.

Make a SINGLE Agent tool call. **The judge MUST use the most capable model** — this is where architectural judgment matters most:

| Parameter | Value |
|-----------|-------|
| `description` | `"Judge Slot Machine results for {feature_name}"` |
| `model` | Omit unless user configured `judge_model` — inherits from session by default. The judge benefits from the most capable model available. |
| `prompt` | Read `3-judge.md` from the active profile's folder and fill in all universal `{{VARIABLES}}` |

The universal variables to fill in the judge prompt:

| Variable | Source |
|----------|--------|
| `{{SPEC}}` | Full text of the original spec |
| `{{ALL_SCORECARDS}}` | All reviewer scorecards concatenated |
| `{{WORKTREE_PATHS}}` | List of all slot worktree/output paths (for targeted inspection) |
| `{{SLOT_COUNT}}` | Number of successful slots |

The judge returns one of three verdicts:
- **PICK** — one slot is the clear winner
- **SYNTHESIZE** — multiple slots have complementary strengths worth combining
- **NONE_ADEQUATE** — all slots have critical issues

Save the judge's full verdict and reasoning to `{RUN_DIR}/verdict.md` before composing the user-facing verdict block. Use the absolute `RUN_DIR` path, and if you use Bash run `mkdir -p "$RUN_DIR"` immediately before the write.

**Before continuing to the final report, verify `{RUN_DIR}/verdict.md` exists and is non-empty.** If the file is missing, write it before proceeding. The inline verdict shown to the user is not a substitute for the persisted run artifact.

**Report the verdict** bounded by horizontal rules. This is the most important output — include a one-sentence why summary explaining the decision in plain language. Every slot reference must include full identity: `(Harness `Model` w/ skill)`.

**Phase 4:** Verdict

---

**Verdict: `SYNTHESIZE`** | Confidence: `HIGH`

Slot 3 has the cleanest code. Slot 1 has the best tests. Combining both produces something better than either.

- **Base:** Slot 3 (Codex `gpt-5.4`) — cleanest implementation, no NaN bug, proper drain waiter pattern
- **+ Slot 1** (Claude Code `opus-4.6` w/ /ce:work) — 19-test suite: nested scheduling, timing verification, counter tracking
- **Keep Slot 3:** event-ordering drain test, error propagation test

---

For PICK verdicts:

---

**Verdict: `PICK Slot 2`** (Claude Code `opus-4.6` w/ /ce:work) | Confidence: `HIGH`

Zero critical issues, strongest test coverage (45 tests), correct lock granularity. No synthesis needed — clear winner.

---

### Phase 4: Resolution

#### If PICK:

**For `worktree` isolation:**

1. The judge named a winning slot. Merge its branch:
   ```bash
   # From the main working directory
   git merge {winning_branch} --no-ff -m "feat: {feature_name} (slot-machine winner: slot {N})"
   ```

2. Run the full test suite to verify the merge is clean.

3. If tests fail: investigate. The worktree passed tests in isolation — merge conflicts or environment differences are the likely cause. Fix before proceeding.

**For `file` isolation:**

1. Copy the winning slot's output file to the target location specified in the spec (or ask the user where to place it).
2. Report the winning output to the user.

#### If SYNTHESIZE:

1. The judge produced a concrete synthesis plan (which base slot, what to port from where).

2. Dispatch the synthesizer as a SINGLE Agent tool call:

   | Parameter | Value |
   |-----------|-------|
   | `description` | `"Synthesize best elements for {feature_name}"` |
   | `isolation` | `"worktree"` if profile isolation is `worktree`; omit if `file` |
   | `model` | Omit unless user configured `synthesizer_model` — inherits from session by default |
   | `prompt` | Read `4-synthesizer.md` from the active profile's folder and fill in all universal `{{VARIABLES}}` |

   The universal variables to fill in the synthesizer prompt:

   | Variable | Source |
   |----------|--------|
   | `{{SPEC}}` | Full text of the spec |
   | `{{SYNTHESIS_PLAN}}` | The judge's synthesis plan (which base, what to port) |
   | `{{WORKTREE_PATHS}}` | All slot worktree/output paths the synthesizer needs to read from |
   | `{{BASE_SLOT_PATH}}` | The worktree/output path of the base slot specifically |

3. Run full test suite to verify (for `worktree` isolation). For `file` isolation, the synthesizer writes its output to `{RUN_DIR}/output.md` (or appropriate extension). Tell the synthesizer this destination path in its prompt.

4. **Post-synthesis review.** Dispatch ONE reviewer to check the synthesized result for integration issues:

   | Parameter | Value |
   |-----------|-------|
   | `description` | `"Review synthesis for {feature_name}"` |
   | `model` | Omit unless user configured `reviewer_model` — inherits from session by default |
   | `prompt` | Read `2-reviewer.md` from the active profile's folder and fill in `{{VARIABLES}}` using the synthesis worktree/output |

   The reviewer checks:
   - Coherence: does it read like one person wrote it?
   - Integration: did porting introduce bugs, naming conflicts, or tonal inconsistencies?
   - Coverage: did any requirements get dropped during synthesis?

   If the reviewer finds critical issues, fix them before finalizing. Important/minor issues can be noted in the final report.

5. **Finalize the synthesis:**
   - For `worktree` isolation: merge the synthesis branch:
     ```bash
     git merge {synthesis_branch} --no-ff -m "feat: {feature_name} (slot-machine synthesis: slot {base} base + elements from slots {donors})"
     ```
   - For `file` isolation: copy the synthesized output file to the target location.

#### If NONE_ADEQUATE:

1. Report the judge's analysis to the user.
2. Recommend next steps based on judge's reasoning:
   - Re-run with an adjusted or clarified spec
   - Re-run with more slots
   - Manual intervention on the best attempt
   - Abandon and rethink the approach
3. **Do NOT auto-retry** — the user decides.

#### Cleanup

If `cleanup` is true (default):

**For `worktree` isolation:** remove all worktrees:

```bash
# For each worktree path tracked during the run:
git worktree remove {worktree_path} --force
# The --force handles uncommitted changes in non-winning slots

# Branches are cleaned up automatically if they were only in the worktree
# For any lingering branches:
git branch -D {branch_name}
```

Slot diffs are preserved in `{RUN_DIR}/`.

**For `file` isolation:** Run artifacts are kept permanently — no cleanup needed. All slot outputs, reviews, and the verdict remain in `{RUN_DIR}/`.

If `manual_handoff` is true for `worktree` isolation, ignore `cleanup: true` and keep successful worktrees so the user can inspect and merge manually. In manual mode, do NOT write `verdict.md`; write `handoff.md` instead, and do not use the judged-run finalization path below. For each successful coding slot, persist `{RUN_DIR}/slot-{i}.diff`, branch name, head SHA, worktree path, and review artifact path in the manual handoff result metadata.

If `cleanup` is false, report worktree/output locations so the user can inspect them.

#### Final Report

Judged runs only. Manual handoff already terminates with `# Manual Handoff`, `handoff.md`, `slot-manifest.json`, and manual-mode `result.json`; do not use this section when `manual_handoff` is true.

The final report has three parts: the H1 header, the output content, and the footer line.

**Part 1: H1 header** (use markdown `#` — this is the most visually distinct element):

# Final Output

**Part 2: Output content** — depends on profile isolation and output length:

**For `file` isolation (writing):** Count lines in the final output file. The winner (or synthesis) is saved to `{RUN_DIR}/output.md`.
- If ≤ 60 lines: show the full content inline after the header.
- If > 60 lines: show the first ~20 lines, then: `Full output at \`.slot-machine/runs/{date}-{feature}/output.md\``

**For `worktree` isolation (coding):** Show a file change summary table:

# Final Output — merged to `{branch}`

| File | Lines | What |
|------|-------|------|
| src/task_queue.py | +142 | TaskQueue class with priority support |
| tests/test_task_queue.py | +245 | 45 tests including concurrency |

`3` files changed, `474` insertions
`45` tests passing

**Part 3: Result artifact** — always write a machine-readable JSON file to the run directory:

```bash
mkdir -p "{RUN_DIR}"
cat > "{RUN_DIR}/result.json" << RESULT
{
  "verdict": "{PICK|SYNTHESIZE|NONE_ADEQUATE}",
  "winning_slot": {N or null},
  "confidence": "{HIGH|MEDIUM|LOW}",
  "slots": {total},
  "slots_succeeded": {succeeded},
  "files_changed": [{list}],
  "tests_passing": {count or null},
  "run_dir": "{RUN_DIR}"
}
RESULT

# Create latest symlink for easy script access
ln -sfn "$(basename "{RUN_DIR}")" "$(dirname "{RUN_DIR}")/latest"
```

This is always written, every run. Humans ignore it. Autonomous loops and scripts parse it via `.slot-machine/runs/latest/result.json`.

Manual handoff writes the same run artifact path with unresolved result state:

In manual mode, the top-level `files_changed` and `tests_passing` fields are `null`; per-slot file/test data lives under `slot_details`.
After refreshing `.slot-machine/runs/latest`, set the top-level `handoff_path` and `run_dir` fields to the absolute `latest` paths rather than the dated `{RUN_DIR}` path.
For `file` isolation, each `slot_details` item uses `output_path` instead of `worktree_path`, and the worktree-only fields (`diff_path`, `branch`, `head_sha`) are omitted or `null`.
Each file-isolation `slot_details` item still carries the slot output path, review path, files_changed, and tests_passing.

```bash
cat > {RUN_DIR}/result.json << RESULT
{
  "resolution_mode": "manual",
  "verdict": null,
  "winning_slot": null,
  "confidence": null,
  "slots": {total},
  "slots_succeeded": {succeeded},
  "handoff_path": "/abs/path/.slot-machine/runs/latest/handoff.md",
  "files_changed": null,
  "tests_passing": null,
  "slot_details": [
    {
      "slot": 1,
      "status": "DONE",
      "diff_path": "{RUN_DIR}/slot-1.diff",
      "worktree_path": ".slot-machine/worktrees/slot-1",
      "branch": "slot-machine/{feature_name}/slot-1",
      "head_sha": "abc123",
      "review_path": "{RUN_DIR}/review-1.md",
      "review_summary": { "critical": 0, "important": 1, "minor": 2 },
      "files_changed": ["src/example.py"],
      "tests_passing": 12
    }
  ],
  "run_dir": "/abs/path/.slot-machine/runs/latest"
}
RESULT
```

**Part 4: Footer** — a horizontal rule followed by a one-line summary:

---

**Complete** — `{word_count} words` | `{N} slots` | `{verdict}`

**Quiet mode:** If `quiet: true` is set, suppress all Phase 2-3 progress tables and standout elements. Only output the Phase 4 verdict blockquote, the Final Output section, and the footer. The run directory still has everything for post-hoc inspection.

#### Metrics (optional)

If the project has a `.slot-machine/` directory (or `metrics_dir` is configured), write run metrics:

```bash
mkdir -p .slot-machine
cat > .slot-machine/run-$(date +%Y%m%d-%H%M%S).json << 'METRICS'
{
  "schema_version": 1,
  "timestamp": "...",
  "feature": "...",
  "config": { "slots": N, ... },
  "results": { "verdict": "...", ... },
  "reviewers": { ... },
  "agents": { "total_dispatched": N, ... },
  "final_output": { "test_count": N, ... }
}
METRICS
```

See `tests/fixtures/sample-metrics.json` for the full schema. Metrics enable tracking improvement across runs — which approach hints win, how often synthesis triggers, whether reviewer differentiation improves over time.

The `reviewers` section tracks effectiveness per slot: `findings_total`, `findings_acted_on` (used by judge), `findings_ignored` (correct but unused), `false_positives`. The `convergent_findings` array lists issues found independently by multiple reviewers — these are the highest-confidence signals. When golden issues are available (from planted-bug test fixtures), `precision` and `recall` are computed.

## Implementer Status Handling

Implementer subagents report one of four statuses in their output:

| Status | Meaning | Orchestrator Action |
|--------|---------|-------------------|
| **DONE** | Implementation complete, tests pass | Proceed to review |
| **DONE_WITH_CONCERNS** | Complete but implementer has reservations | Proceed to review — include concerns in reviewer context |
| **BLOCKED** | Can't proceed — architectural uncertainty, missing info | Retry with more context if retries remain. If still blocked, mark failed. |
| **NEEDS_CONTEXT** | Spec is ambiguous or missing information | Provide the missing context and re-dispatch. If context isn't available, mark failed. |

**Never ignore BLOCKED or NEEDS_CONTEXT.** These indicate real problems. Forcing a retry without changes produces the same failure.

## Model Selection

By default, all agents inherit the model from your current session. If you're running Opus, every slot gets Opus. If you're running Sonnet, every slot gets Sonnet. This means you always get the quality level you're paying for.

To override, set model configs in your project's `CLAUDE.md` or inline. Only pass the `model` parameter to the Agent tool when the user has explicitly configured an override — otherwise omit it so the session model is inherited.

| Role | Default | Configurable As | When to override |
|------|---------|-----------------|------------------|
| Implementer | inherit | `implementer_model` | Downgrade to save cost on mechanical tasks |
| Reviewer | inherit | `reviewer_model` | Downgrade to save cost on structured evaluation |
| Judge | inherit | `judge_model` | Upgrade if running a cheaper session model |
| Synthesizer | inherit | `synthesizer_model` | Upgrade if running a cheaper session model |

## Approach Hints

Approach hints are defined in the active profile's `0-profile.md`. See `profiles/coding/0-profile.md` for the coding defaults and `profiles/writing/0-profile.md` for writing defaults.

When `approach_hints` is enabled (default: true), each slot gets a different hint to encourage genuinely divergent attempts. Assign randomly without replacement. The profile defines what "diversity" means for its task type — architectural diversity for coding, voice/structure diversity for writing.

## Common Mistakes

### Skipping spec validation
- **Problem:** Vague spec → N implementations that all miss the mark in different ways → expensive waste
- **Fix:** Validate spec is concrete enough BEFORE spinning up slots. If ambiguous, ask.

### Dumping too much context
- **Problem:** Giving implementers the entire codebase burns their context window on irrelevant information
- **Fix:** Curate context — README, relevant architecture notes, key files only. Implementers can read more if needed.

### Judge reading all code from scratch
- **Problem:** Judge burns context reading N full implementations
- **Fix:** Judge reads scorecards FIRST, only does targeted code inspection where scorecards diverge or flag issues

### Synthesis that creates Frankenstein code
- **Problem:** Cherry-picking from multiple implementations creates inconsistent code
- **Fix:** Synthesizer uses ONE slot as base, ports SPECIFIC elements. Full test suite must pass. Self-review for coherence.

### Running on mechanical tasks
- **Problem:** 5 parallel attempts at "add a field to this model" is burning money
- **Fix:** Only use slot-machine when implementation has meaningful design choices

### Retrying without changes
- **Problem:** Re-dispatching a BLOCKED slot with the same context produces the same failure
- **Fix:** Add context, clarify the spec, or provide the missing information before retrying

## Red Flags — STOP If You Catch Yourself Doing These

**The #1 baseline failure mode** (observed in Task 0 testing without the skill): the orchestrator reads all implementations itself, makes an ad hoc comparison, and writes the synthesis — centralizing everything instead of delegating to specialized reviewer/judge/synthesizer agents. The review and judgment pipeline IS the skill's value. Don't collapse it.

| Thought / Action | What's Wrong |
|-----------------|-------------|
| "I'll just read all the code and compare them myself" | **This is the most common shortcut.** Dispatch independent reviewer agents per slot. Your job is orchestration, not evaluation. Blind review by fresh agents prevents bias from seeing all implementations simultaneously. |
| "I'll make a quick comparison table instead of formal scorecards" | A comparison table is not a scorecard. Each slot needs independent review with 6 weighted criteria, issue categorization, and a verdict. The judge needs structured input, not your summary. |
| "I can write the synthesis myself, I've already read the code" | Dispatch the synthesizer agent. It works from the judge's plan with a single base + targeted ports. Ad hoc synthesis by the orchestrator produces Frankenstein code. |
| "I'll split the spec into different tasks for each slot" | That's standard parallel agents, not slot-machine. Each slot gets the FULL spec. |
| "3 slots is probably enough" | Use the configured count. User chose N for a reason. Don't second-guess. |
| "I'll skip the judge and just merge the highest scorer" | Judge does targeted code inspection. Scorecard alone isn't enough for the decision. |
| "Synthesis sounds risky, I'll just PICK" | If multiple slots have complementary strengths, synthesis produces a better result. Trust the process. |
| "This spec is probably clear enough" | Validate. Ambiguous specs × N slots = N different wrong implementations = expensive waste. |
| "Reviewing each separately is overkill" | Structured review is what makes judgment possible. Ad hoc comparison = ad hoc results. |

**All of these mean you're about to shortcut the review/judgment pipeline. That pipeline is the entire point of this skill.**

## Integration

- **superpowers:brainstorming** → Produces the spec that slot-machine consumes. Run brainstorming BEFORE slot-machine if requirements are unclear.
- **superpowers:writing-plans** → Can produce the plan/spec. Slot-machine gives the ENTIRE spec to each slot (not individual tasks).
- **superpowers:using-git-worktrees** → Slot-machine uses `isolation: "worktree"` which follows the same underlying git worktree mechanics.
- **superpowers:test-driven-development** → Each implementer should follow TDD if the project uses it. Include TDD guidance in the spec if applicable.
- **superpowers:finishing-a-development-branch** → After slot-machine produces a winner, use this for final merge/PR/cleanup.

**Key difference from subagent-driven-development:** SDD splits a plan into sequential tasks (one agent per task). Slot-machine gives the ENTIRE spec to N agents and compares their full implementations. They are complementary — you could use SDD within each slot for large features.
