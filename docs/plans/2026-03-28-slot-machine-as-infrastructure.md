---
date: 2026-03-28
topic: slot-machine-as-infrastructure
status: draft
---

# Slot Machine as Infrastructure: Pluggable Slots, Opinionated Evaluation

## Vision

Slot machine is a **competition and selection framework**, not an opinionated implementation tool. The value is the pipeline — parallel execution, independent review, structured judgment, synthesis. What happens inside each slot is the user's choice.

Advanced users bring their own skills, workflows, and even AI harnesses. Slot machine makes it easy to run N of whatever-they-already-use and pick the best result. Novice users get good defaults that work out of the box.

**The wow feature:** Run Claude Code vs Codex on the same spec, review both independently, and pick the winner or synthesize the best of each. Different models, different reasoning, same evaluation framework.

## The Core Architectural Principle

Slot machine owns the **sequence of steps** — the pipeline:

```
1. Dispatch N implementations (pluggable)
2. Review each independently (opinionated by default, configurable)
3. Judge and compare (opinionated by default, configurable)
4. Synthesize or pick (opinionated by default, configurable)
5. Persist and report (always slot-machine's job)
```

Everything beyond this sequence is configurable. What model runs each step, what skills guide each slot, what harness dispatches each agent, what criteria the reviewer uses — all pluggable. The pipeline is the product. The defaults are just good starting points.

**Build for advanced users first.** If the infrastructure is right, good defaults for novices are just a thin layer on top.

## What a Slot Is

Today: slot = approach hint + profile implementer prompt. This remains the default.

A slot can be any of:

| Slot type | What it means | Example |
|-----------|---------------|---------|
| **Hint** (default) | Profile implementer prompt + architectural nudge | "Use the simplest possible approach" |
| **Skill** | Dispatch with a specific skill loaded | `/superpowers:tdd`, `/ce:work` |
| **Harness** | Run in a different AI system entirely | `codex`, `gemini-cli`, `amp` |
| **Harness + Skill** | Different system with specific skill guidance | `codex + /superpowers:tdd` |
| **Command** | Run an arbitrary CLI command, capture output | Custom user-defined |

All slot types produce the same thing: implementation artifacts + a self-report. The evaluation pipeline doesn't care how it was made.

## What's Pluggable (Eventually Everything)

| Component | Default | Override via |
|-----------|---------|-------------|
| **Implementation** | Profile implementer prompt + hint | Skill, harness, or command per slot |
| **Review** | Profile reviewer prompt | Custom reviewer in profile, or different model/agent |
| **Judgment** | Profile judge prompt | Custom judge in profile, or different model/agent |
| **Synthesis** | Profile synthesizer prompt | Custom synthesizer in profile |
| **Model (per step)** | Inherit from session | Per-slot or per-role config |
| **Isolation** | Profile setting (worktree/file) | Per-slot override |
| **Pre-checks** | Profile setting | Per-slot override |

Advanced users configure via profiles. Slot machine is pure infrastructure — profiles are the opinion layer.

## Phased Rollout

### Phase 1: Profiles and Pipeline (shipped)

- Coding and writing profiles with full prompt sets
- Folder-per-profile structure (0-profile.md through 4-synthesizer.md)
- Approach hints for diversity within a single skill/harness
- Complete review/judge/synthesis pipeline
- Run storage (.slot-machine/runs/), structured output formatting
- Model inheritance from session
- Community profile support (~/.slot-machine/profiles/)

### Phase 2: Skill-Per-Slot

The smallest useful expansion. Users specify which skill each slot uses:

```
/slot-machine with 3 slots:
  slot 1: use /superpowers:tdd
  slot 2: use /ce:work
  slot 3: default (profile hint)
```

Implementation:
- Slot definition syntax in the invocation command
- Each slot's context includes the specified skill's guidance
- Profile implementer prompt is a fallback — skipped when a skill is specified
- Review/judge/synthesis unchanged (profile prompts)
- Approach hints still work for default slots

This is context management, not new infrastructure.

### Phase 3: Cross-Harness — Claude Code + Codex

The wow feature. Start with the most common case: a Claude Code user who also has Codex installed.

```
/slot-machine with 4 slots:
  slot 1: claude-code + /superpowers:tdd
  slot 2: claude-code + /ce:work
  slot 3: codex
  slot 4: codex + /superpowers:tdd
```

Implementation approach:
- **Don't build custom adapters.** The ecosystem already has cross-agent dispatch (gstack's /codex skill, other emerging tools). Hook into what exists.
- For Codex: use `codex exec` CLI (already available via gstack /codex skill). Pass the spec as a prompt, capture output files + report.
- Output normalization: each harness adapter produces files in `{RUN_DIR}/slot-{i}/` + a text report. The reviewer reads files regardless of origin.
- Review/judge stay in the orchestrator's harness (Claude Code) by default.

Key decisions:
- Start Claude Code-first. Support Codex as the first cross-harness target.
- Harness adapters are thin — they invoke a CLI command and normalize output. Not a framework.
- If someone has already solved a cross-agent dispatch pattern (e.g., a skill that invokes Codex), we use theirs.

### Phase 4: Any Harness, Any Direction

Generalize beyond Claude Code → Codex:

- Codex user dispatching to Claude Code
- Gemini CLI user dispatching to either
- AMP or other model-agnostic harnesses dispatching to multiple models
- The orchestrator itself could run in any harness — it just needs to dispatch, collect, and evaluate

This is the "pure infrastructure" endgame. Slot machine is harness-agnostic. It can run inside any agent system that can invoke other agent systems.

Implementation:
- Harness registry: a simple config mapping names to dispatch commands
- User defines harnesses in their profile or CLAUDE.md
- Slot machine invokes, collects, evaluates
- The evaluation pipeline can ALSO be dispatched to a different harness/model (e.g., use GPT to review Claude's code, or vice versa)

### Phase 5: Bring-Your-Own-Everything

The user defines slots as arbitrary commands:

```yaml
slots:
  - name: "my-tdd-flow"
    command: "claude -p '{spec}' --skill superpowers:tdd"
  - name: "codex-approach"
    command: "codex exec '{spec}'"
  - name: "gemini-attempt"
    command: "gemini run '{spec}'"
  - name: "my-custom-pipeline"
    command: "./scripts/implement.sh '{spec}'"
```

Slot machine just needs output artifacts and runs the evaluation pipeline. At this point, slot machine is a tournament runner for any AI-produced output.

## Reviewer Across Harnesses

When comparing outputs from different models, the reviewer is (by default) an agent in the orchestrator's harness. This means a Claude agent reviews both Claude and GPT output.

Potential bias mitigation (not required for v1):
- The reviewer reads files, not conversations — the producing model shouldn't be identifiable from the artifacts alone
- For extra rigor: run the review step in multiple harnesses too (Claude reviews + Codex reviews), then the judge sees both perspectives
- Eventually: the reviewer itself becomes a pluggable step, allowing users to specify which model/agent reviews

For v1: accept that the orchestrator's model does the review. Flag it as a known limitation. The artifacts-based review largely mitigates bias — code is code regardless of who wrote it.

## The Novice vs Advanced Spectrum

```
Novice                                              Advanced
|                                                        |
"slot-machine this"              "slot-machine with custom slots,
 → auto-detect profile            cross-harness, custom reviewer"
 → default hints
 → built-in prompts
 → everything works
```

The default path (left side) is profiles with built-in prompts. Zero config.

The advanced path (right side) overrides everything via:
1. Custom profiles (reviewer, judge, synthesizer prompts)
2. Slot definitions (skills, harnesses, commands)
3. Model overrides (per-step)
4. Eventually: pluggable evaluation pipeline

Both paths use the same underlying machinery. The difference is how much the user configures vs inherits from defaults.

## Grounded Analysis: The Implementation Skills

These are the skills that would be assigned to slots. Each produces files + a report — exactly what slot-machine's reviewer needs.

### Superpowers

| Skill | Invocation | What it does | Isolation | Output |
|-------|-----------|-------------|-----------|--------|
| TDD | `/superpowers:tdd` | Test-first, RED/GREEN/REFACTOR cycle | Current workspace | Code + tests, incremental commits |
| Subagent-Driven | `/superpowers:subagent-driven-development` | Multi-agent with per-task review loops | Worktree (required) | Code + tests, reviewed commits |
| Executing Plans | `/superpowers:executing-plans` | Single-session plan execution | Worktree (required) | Code + tests, commits per task |

**Integration notes:** All superpowers implementation skills need a plan file as input. For slot-machine, the orchestrator passes the spec directly — these skills should treat it as a single-task plan. The worktree-requiring skills get their worktree from slot-machine's isolation, not their own.

### Compound Engineering

| Skill | Invocation | What it does | Isolation | Output |
|-------|-----------|-------------|-----------|--------|
| Work | `/ce:work` | Pattern-matching execution with optional reviewers | Branch or worktree | Code + tests, incremental commits |

**Integration notes:** CE work does its own codebase pattern research. In a slot-machine context, this is a feature — different slots might discover and follow different patterns. CE work also has optional reviewer agents (simplicity, security, performance) which add a second review layer on top of slot-machine's review.

### Cross-Harness (Codex)

| Harness | Invocation | What it does | Isolation | Output |
|---------|-----------|-------------|-----------|--------|
| Codex | `codex exec "{spec}"` | GPT-based implementation in read-only sandbox | Codex sandbox | Code files (no commits) |

**Integration notes:** Codex runs in a read-only sandbox — it produces files but can't commit. The orchestrator needs to capture Codex's output and place it in the run directory. Codex doesn't produce a structured implementer report, so the orchestrator extracts what was built from the CLI output. Existing integration: gstack's `/codex` skill already handles `codex exec` invocation and output parsing.

### How Each Slot Type Maps to Orchestrator Behavior

| Slot config | Orchestrator action | Prompt source | Isolation |
|-------------|-------------------|---------------|-----------|
| `default` | Read profile implementer prompt, add approach hint | Profile `1-implementer.md` | Profile's isolation setting |
| `/superpowers:tdd` | Dispatch Agent with TDD skill instruction + spec | Skill guidance injected into context | worktree |
| `/superpowers:sdd` | Dispatch Agent with SDD instruction + spec as plan | Skill guidance injected into context | worktree |
| `/ce:work` | Dispatch Agent with CE work instruction + spec | Skill guidance injected into context | worktree |
| `codex` | Run `codex exec` via Bash, capture output files | Spec passed as prompt to codex CLI | codex sandbox → files copied to RUN_DIR |

**Key insight:** For skill-based slots, the orchestrator doesn't read the profile's implementer prompt. Instead, it tells the subagent "use this skill to implement {spec}" and the skill's own prompting takes over. The profile's reviewer/judge/synthesizer prompts are still used — only the implementer is overridden.

## Invocation Syntax

### Natural Language (the common case)

Users describe what they want conversationally. The orchestrator parses intent:

```
/slot-machine this with /superpowers:tdd, /ce:work, and codex

Spec: Implement a rate limiter with sliding window support
```

Parsed as: 3 slots, one per named skill/harness. No default hint slots.

```
/slot-machine this with 5 slots — use /superpowers:tdd and codex,
rest are default

Spec: [the spec]
```

Parsed as: 5 slots. Slot 1: superpowers:tdd. Slot 2: codex. Slots 3-5: default profile hints.

```
/slot-machine this using all my implementation skills

Spec: [the spec]
```

Parsed as: auto-detect installed implementation skills, one slot per skill. The orchestrator checks what's available (superpowers, CE, codex CLI) and creates one slot for each.

### Explicit Per-Slot (power users)

```
/slot-machine with 4 slots:
  slot 1: /superpowers:tdd
  slot 2: /ce:work
  slot 3: codex
  slot 4: default

Spec: [the spec]
```

### Config-Based (project defaults in CLAUDE.md)

```markdown
## Slot Machine Settings
slot-machine-slots:
  - skill: /superpowers:tdd
  - skill: /ce:work
  - harness: codex
  - default
```

Then the user just says `/slot-machine this` and the config is loaded.

### Shorthand Flags

```
/slot-machine --skills tdd,ce:work --harness codex

Spec: [the spec]
```

### Precedence

1. Inline slot definitions (in the command)
2. CLAUDE.md `slot-machine-slots` config
3. Profile defaults (implementer prompt + approach hints)

## Skill Discovery

When the user says "all my skills" or "all implementation skills" or uses `--discover`, the orchestrator scans for available implementation skills and proposes a slot configuration.

### Trigger Rules (strict — never auto-fires)

| User says | Detection fires? |
|-----------|-----------------|
| `/slot-machine this` | No — default profile + hints |
| `/slot-machine this with 3 slots` | No — default hints |
| `/slot-machine this with /superpowers:tdd and codex` | No — explicit list |
| `/slot-machine this with all my skills` | **Yes** |
| `/slot-machine this using all implementation skills` | **Yes** |
| `/slot-machine --discover` | **Yes** |

Detection ONLY fires on explicit "all my/implementation skills" language or `--discover` flag. Never as a helpful suggestion. Never as a default.

### First-Time Flow

```
I scanned your installed skills and detected these implementation workflows:

  1. /superpowers:tdd — test-first development
  2. /superpowers:subagent-driven-development — multi-agent with review loops
  3. /ce:work — pattern-matching execution
  4. codex — OpenAI Codex (external, GPT model)

Use all 4 as slots? Or adjust?
```

User confirms or edits. Selection saved to `~/.slot-machine/config.md`:

```markdown
## Discovered Implementation Skills
- /superpowers:tdd
- /superpowers:subagent-driven-development
- /ce:work
- codex
```

### Subsequent Runs

"All my skills" loads the saved list without re-scanning. User can re-trigger fresh scan with `--discover`.

### Detection Heuristic

The orchestrator reads skill descriptions from the system prompt and filters by signals:

**Include signals:** "implement", "build", "execute plan", "write code", "development workflow"
**Exclude signals:** "review", "deploy", "ship", "test-only", "audit", "monitor", "debug"
**External harnesses:** Check for CLI binaries (`which codex`, `which gemini`)

The heuristic proposes — the user decides. The saved config is the source of truth, not the heuristic.

## Open Questions

1. **Skills that do their own review (SDD)** — SDD has built-in spec compliance and code quality review loops. When running SDD inside a slot, slot-machine also runs its own independent review. This is intentional (two independent review perspectives are better than one), but it means SDD slots take longer and do redundant work. Should we offer a "skip slot-machine review for skill-based slots" option? Probably not in v1 — the independent review is the whole point.

2. **Codex sandbox vs slot-machine worktrees** — Codex runs read-only. It can produce files but can't run tests. The orchestrator needs to take Codex's output, place it in a worktree or run dir, and run tests itself before the reviewer sees it. This is doable but adds a step.

3. **Cross-harness timing** — Codex calls via CLI might take 2-5x longer than local Agent dispatch. Slots won't finish simultaneously. Should the orchestrator start reviewing completed slots while others are still running? Probably yes — dispatch reviewers as slots complete rather than waiting for all.

4. **Evaluation pipeline pluggability** — Custom profiles already allow custom reviewer/judge prompts. For full pluggability (different model for review, different harness for judge), the profile could specify `reviewer_harness: codex` or `judge_model: gpt-5`. Not for v1 but the profile structure supports it.

## Autonomous Loop Integration

Slot-machine should work inside autonomous agent loops — frameworks like Ralph (outer bash loop, one story per iteration) and Trycycle (inner multi-phase orchestration with subagent dispatch). In these scenarios, slot-machine runs fully unattended for hours.

### Two Integration Patterns

**Pattern A: Slot-machine as a step in an outer loop (Ralph-style)**

```
Ralph's loop:
  while stories_remain:
    pick next story
    → invoke slot-machine to implement it (replaces single AI instance)
    run quality checks
    if pass: mark done, commit
    continue
```

Ralph doesn't care how the implementation happened. It spawns a fresh AI instance per story. Slot-machine replaces that single instance with N competing instances + review + judgment. Ralph's quality checks (typecheck, tests) validate the winner.

**Pattern B: Slot-machine as a phase in an inner orchestrator (Trycycle-style)**

```
Trycycle's phases:
  plan → strengthen → test plan → BUILD → review → fix → finish
                                    ↑
                        slot-machine replaces this
```

Trycycle dispatches subagents per phase and collects structured output. Slot-machine could be the build phase — dispatch N implementations, review, pick winner. Trycycle's own review phase provides an independent second check.

### Requirements for Loop Integration

1. **Fully autonomous mode.** When invoked programmatically, slot-machine must run to completion without interactive prompts. No "which profile?" — auto-detect or use configured defaults. No "does this look right?" — just execute. Add an `autonomous: true` config or detect non-interactive context.

2. **Clean exit state.** After the run, the workspace must be in a known state:
   - Winning code merged to the working branch (or output file written)
   - All tests passing
   - No dangling worktrees
   - No uncommitted changes
   The outer loop picks up exactly where slot-machine left off.

3. **Machine-readable output artifact.** In addition to human-readable tables, write a structured JSON file to the run directory:

   ```json
   {
     "verdict": "PICK",
     "winning_slot": 2,
     "confidence": "HIGH",
     "slots_succeeded": 3,
     "slots_failed": 0,
     "tests_passing": 45,
     "files_changed": ["src/task_queue.py", "tests/test_task_queue.py"],
     "output_path": ".slot-machine/runs/2026-03-28-task-queue/output.md",
     "run_dir": ".slot-machine/runs/2026-03-28-task-queue/"
   }
   ```

   Outer loops can read this JSON to decide what to do next. Ralph reads it to update `prd.json`. Trycycle reads it to feed into its review phase.

4. **Non-interactive invocation.** Loops invoke slot-machine either as:
   - A subagent prompt: `"Use slot-machine autonomously. Profile: coding. Slots: 3. Spec: {story}"`
   - A CLI invocation: `claude -p "slot-machine this..." --allowed-tools=all`
   - A skill reference within another skill's orchestration

5. **Configurable verbosity.** In a 12-hour loop, no one watches the terminal. Add a `quiet` mode that suppresses progress tables and only outputs the final verdict + path to run artifacts. The run directory still has everything for post-hoc inspection.

6. **Deterministic behavior.** When `autonomous: true`, never ask the user anything. If the spec is ambiguous, use best judgment and note concerns in the verdict. If auto-detection can't determine the profile, fall back to `coding`. The loop must not stall.

### What This Means for SKILL.md

The orchestration logic needs two modes:

**Interactive (default):** Current behavior — progress tables, user can be asked questions, rich output.

**Autonomous:** Triggered by config (`autonomous: true` in CLAUDE.md or inline). Differences:
- Skip all AskUserQuestion calls
- Auto-detect profile without asking (use signals, fall back to coding)
- Suppress progress tables (or minimize to one-line status updates)
- Always write JSON result artifact to run dir
- Ensure clean exit state (merge winner, cleanup worktrees, verify tests)
- Report final verdict in a parseable format

### Integration Examples

**Ralph integration (CLAUDE.md):**
```markdown
## Slot Machine Settings
autonomous: true
slots: 3
profile: coding
quiet: true
```

Ralph's prompt template includes: "Use slot-machine to implement this story. Run fully autonomously."

**Trycycle integration (subagent prompt):**
```
Implement this spec using slot-machine with 3 slots.
Run autonomously — no questions, no interactive prompts.
Write results to .slot-machine/runs/ and leave the workspace clean.
Spec: {plan_content}
```

Trycycle's orchestrator reads the JSON result artifact and passes it to its review phase.

**Custom loop (bash script):**
```bash
for story in $(jq -r '.stories[] | select(.passes == false) | .id' prd.json); do
  SPEC=$(jq -r ".stories[] | select(.id == \"$story\") | .description" prd.json)
  claude -p "Use slot-machine autonomously with 3 slots. Spec: $SPEC" \
    --allowed-tools=all --permission-mode bypassPermissions
  # Check result
  RESULT=$(cat .slot-machine/runs/latest/result.json)
  VERDICT=$(echo "$RESULT" | jq -r '.verdict')
  if [ "$VERDICT" != "NONE_ADEQUATE" ]; then
    jq ".stories[] |= if .id == \"$story\" then .passes = true else . end" prd.json > tmp.json
    mv tmp.json prd.json
  fi
done
```

## Next Steps

1. Ship the current branch (Phase 1 complete)
2. Design and implement Phase 2: skill-per-slot (start with superpowers:tdd and ce:work)
3. Spike Phase 3: prove Claude Code → Codex dispatch and review works end-to-end
4. Add autonomous mode for loop integration
5. Iterate on syntax based on user testing
6. Generalize harness support based on ecosystem evolution
