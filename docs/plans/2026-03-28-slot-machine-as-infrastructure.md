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

## What's Pluggable

| Component | Default | Pluggable now (Phase 1) | Pluggable later |
|-----------|---------|------------------------|-----------------|
| **Implementation** | Profile implementer prompt + hint | No — profile only | Phase 2: skill per slot. Phase 3: harness per slot. |
| **Review** | Profile reviewer prompt | Custom profile only | Phase 4+: different model/harness for review |
| **Judgment** | Profile judge prompt | Custom profile only | Phase 4+: different model/harness for judgment |
| **Synthesis** | Profile synthesizer prompt | Custom profile only | Phase 4+: different model/harness for synthesis |
| **Model (per step)** | Inherit from session | Per-role config in CLAUDE.md | Per-slot model override |
| **Isolation** | Profile setting (worktree/file) | Profile only | Per-slot override |

Advanced users configure via profiles today. Skill-per-slot and cross-harness expand what's pluggable in Phases 2-3. The evaluation pipeline (review/judge/synthesis) becomes fully pluggable in Phase 4+.

## Slot-Compatible Skills

Not every implementation skill works well as a slot candidate. Slots run independently and produce a single implementation. Skills that are themselves multi-agent orchestrators create awkward nesting.

**Good slot candidates (single-session, produce one implementation):**

| Skill | Why it works |
|-------|-------------|
| `/superpowers:tdd` | Single-session methodology. Produces code + tests in one pass. |
| `/ce:work` | Single-session execution. Does its own pattern research (a feature — different slots find different patterns). |
| `codex` | Single invocation via CLI. Produces files directly. |

**Poor slot candidates (multi-agent orchestrators — nesting issues):**

| Skill | Why it's awkward |
|-------|-----------------|
| `/superpowers:subagent-driven-development` | Dispatches its own subagents with its own review loops. Running SDD inside a slot = a full pipeline nested inside a pipeline. Redundant review, 10x longer per slot. |
| `/superpowers:executing-plans` | Designed for multi-task plans with checkpoints. A slot is one task, not a plan. |

The orchestrator should warn if a user assigns a poor-candidate skill to a slot, but not block it — the user might have a reason.

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

### Phase 3: Cross-Harness — Native Codex Dispatch

The wow feature. Run Claude Code vs Codex on the same spec, review both, pick the winner.

```
/slot-machine with 4 slots:
  slot 1: tdd                    ← Claude Code with TDD guidance
  slot 2: tdd + codex            ← Codex with TDD guidance
  slot 3: ce:work                ← Claude Code with CE patterns
  slot 4: codex                  ← Codex with default approach
```

**Key design decision: slot-machine dispatches to Codex natively — not through the `/codex` skill.**

The `/codex` skill (gstack) is designed for review/challenge/consult, not implementation. Delegating to it would confuse users ("is `/codex` creating a slot or running inside one?"). Instead, slot-machine handles Codex dispatch directly, the same way it handles Claude Code dispatch via the Agent tool.

**User mental model (clean separation):**
- **Skills** = methodology (TDD, CE patterns) — guidance injected into ANY harness
- **Harnesses** = which AI system (Claude Code, Codex, Gemini) — dispatch mechanism
- **Default** = profile implementer prompt + approach hints

Skills and harnesses compose: `tdd + codex` means "Codex implements using TDD methodology."

**Codex dispatch mechanics:**

Codex CLI supports workspace-write mode: `codex exec -s workspace-write`. This means Codex can write files directly to a worktree — no output parsing needed.

For each Codex slot, the orchestrator:
1. Creates a git worktree (same as Claude Code slots)
2. Runs `codex exec` pointed at that worktree:
   ```bash
   cd {worktree_path}
   codex exec "Implement this spec. Write all files to the current directory.

   {skill_guidance if specified}

   Spec: {spec}

   When done, report what you built, files changed, and any concerns." \
     -s workspace-write \
     -c 'model_reasoning_effort="high"' \
     --json 2>/dev/null
   ```
3. Parses JSONL output for the implementer report (what was built, concerns)
4. The worktree now contains Codex's implementation files
5. Reviewer reads the worktree — identical to reviewing a Claude Code slot

**JSONL parsing** (borrowed from gstack's codex skill pattern):
```python
# Parse codex JSONL events
for line in sys.stdin:
    obj = json.loads(line)
    if obj['type'] == 'item.completed':
        item = obj['item']
        if item['type'] == 'agent_message':
            # This is the implementer report
            print(item['text'])
        elif item['type'] == 'command_execution':
            # Log what codex did
            print(f"[codex ran] {item['command']}")
```

**Why native dispatch is better than using the `/codex` skill:**
1. No conceptual confusion — "use codex" means one thing
2. `workspace-write` mode lets Codex write files directly (gstack's codex uses read-only)
3. Slot-machine controls the worktree lifecycle (create, dispatch, review, cleanup)
4. Same pattern extends to Gemini CLI, AMP, or any future harness
5. Skills (TDD, CE) compose with harnesses independently — `tdd + codex` just works

**Same pattern for future harnesses:**

| Harness | Dispatch command | Sandbox |
|---------|-----------------|---------|
| Claude Code | Agent tool with `isolation: "worktree"` | Worktree (built-in) |
| Codex | `codex exec -s workspace-write --json` | Worktree (slot-machine manages) |
| Gemini CLI | `gemini run --workspace {path}` (TBD) | Worktree (slot-machine manages) |
| Custom | User-defined CLI command | User-defined |

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

### Cross-Harness (Codex) — Native Dispatch

| Harness | Dispatch | Sandbox mode | Isolation | Output |
|---------|---------|-------------|-----------|--------|
| Codex | `codex exec -s workspace-write --json` | workspace-write (can create/modify files) | Worktree (managed by slot-machine) | Files written directly to worktree + JSONL report |

**Integration notes:** Slot-machine dispatches to Codex **natively** via `codex exec`, not through the gstack `/codex` skill. The `/codex` skill is designed for review/challenge/consult — not implementation. Native dispatch gives us `workspace-write` mode (Codex writes files directly to a worktree), JSONL output for implementer reports, and clean composition with skills (`tdd + codex`).

JSONL parsing pattern borrowed from gstack's codex skill: parse `item.completed` events for agent messages and command executions.

### How Each Slot Type Maps to Orchestrator Behavior

| Slot config | Orchestrator action | Dispatch mechanism | Isolation |
|-------------|--------------------|--------------------|-----------|
| `default` | Profile implementer prompt + approach hint | Agent tool | Profile's isolation setting |
| `tdd` | TDD methodology guidance + spec | Agent tool | worktree |
| `ce:work` | CE work patterns guidance + spec | Agent tool | worktree |
| `codex` | Spec passed to codex exec CLI | `codex exec -s workspace-write --json` | worktree (slot-machine managed) |
| `tdd + codex` | TDD guidance embedded in codex exec prompt | `codex exec -s workspace-write --json` | worktree (slot-machine managed) |

**Two categories, composable:**
- **Skills** (tdd, ce:work, sdd) = methodology guidance. Injected into the prompt of whatever harness runs the slot.
- **Harnesses** (codex, gemini, default=claude-code) = which AI system executes. Determines the dispatch mechanism.

A slot with no harness specified uses Claude Code (the Agent tool). A slot with no skill specified uses the profile's implementer prompt + approach hint. Both can be combined: `tdd + codex` = Codex implements using TDD methodology.

**Key insight:** The profile's reviewer/judge/synthesizer prompts are always used regardless of how the slot was implemented. Only the implementation step is pluggable.

## Invocation Syntax

Three ways to configure slots, from casual to persistent:

### 1. Natural Language (primary — how most users interact)

```
/slot-machine this with tdd, ce:work, and codex

Spec: Implement a rate limiter with sliding window support
```

The orchestrator parses skill and harness names from the request. One slot per named item. If the user also specifies a slot count higher than the named items, remaining slots get default profile hints.

```
/slot-machine this with 5 slots — use tdd and codex, rest are default

Spec: [the spec]
```

Parsed as: Slot 1: tdd. Slot 2: codex. Slots 3-5: default profile hints.

### 2. Explicit Per-Slot (power users who want precise control)

```
/slot-machine with 4 slots:
  slot 1: tdd
  slot 2: ce:work
  slot 3: codex
  slot 4: tdd + codex

Spec: [the spec]
```

### 3. Project Config (CLAUDE.md — set once, use every time)

```markdown
## Slot Machine Settings
slot-machine-slots:
  - skill: tdd
  - skill: ce:work
  - harness: codex
  - default
```

Then `/slot-machine this` loads the config automatically.

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

## Cost Implications for Cross-Harness

Cross-harness slots use different billing accounts. A run with 2 Claude Code slots + 2 Codex slots means charges on both Anthropic and OpenAI. The orchestrator should report which harnesses were used in the final summary so the user understands where costs landed. No blocking or warning needed — just transparency.

## Open Questions

1. **Cross-harness timing** — Codex calls via CLI might take 2-5x longer than local Agent dispatch. Slots won't finish simultaneously. Should the orchestrator start reviewing completed slots while others are still running? Probably yes — dispatch reviewers as slots complete rather than waiting for all.

2. **Evaluation pipeline pluggability** — Custom profiles already allow custom reviewer/judge prompts. For full pluggability (different model for review, different harness for judge), the profile could specify `reviewer_harness: codex` or `judge_model: gpt-5`. Not for v1 but the profile structure supports it.

## Autonomous Loop Integration

Slot-machine works inside autonomous agent loops like Ralph and Trycycle. We tested this: a headless Claude Code instance reads CLAUDE.md, sees the slot-machine instruction, and runs the pipeline without human intervention.

**Key finding from testing:** Slot-machine is self-regulating. When given a mechanical task (fizzbuzz), it correctly decided the task didn't warrant competition and implemented it directly. In a Ralph loop with 20 stories, the agent decides which stories get slot-machine and which get single-shot. This is a feature, not a bug.

### What Already Works (no changes needed)

- **CLAUDE.md config is read by headless instances.** Set profile, slots, and instructions once.
- **Self-regulation.** The "When to Use" decision tree prevents wasting compute on mechanical tasks.
- **Clean exit state.** Winner merged, worktrees cleaned, tests passing.
- **No-stall on strong signals.** Profile auto-detection works without asking when coding signals are clear.
- **Non-interactive invocation.** Works as subagent prompt or `claude -p` CLI.

### What to Build (two things)

**1. JSON result artifact — always written, every run.**

```json
{
  "verdict": "PICK",
  "winning_slot": 2,
  "confidence": "HIGH",
  "slots": 3,
  "slots_succeeded": 3,
  "files_changed": ["src/task_queue.py", "tests/test_task_queue.py"],
  "tests_passing": 45,
  "run_dir": ".slot-machine/runs/2026-03-28-task-queue/"
}
```

Written to `.slot-machine/runs/{run}/result.json`. Plus a `latest` symlink: `.slot-machine/runs/latest → {current run}`.

Always written — zero cost for humans (they ignore it), high value for loops that parse it. No config flag needed.

**2. `quiet: true` config option.**

Suppresses progress tables and intermediate phase reports. Final verdict + output path still printed. Set in CLAUDE.md for loop projects, never set for interactive use. Default: false (verbose).

### What NOT to Build

- **`autonomous: true` flag** — unnecessary. The agent already self-regulates and auto-detects for strong signals. CLAUDE.md instructions like "do not ask questions" handle the rest. No special mode needed.
- **Ralph-specific adapters** — Ralph doesn't need to know slot-machine exists. It just spawns Claude Code and checks the result.
- **Special headless detection** — the pipeline works the same in both modes. Only output verbosity differs (`quiet: true`).

### Loop Integration Setup

**Ralph — add to CLAUDE.md:**

```markdown
## Slot Machine Settings
slot-machine-profile: coding
slots: 3
quiet: true

## Implementation Approach
When implementing stories, use the slot-machine skill.
Do not ask questions — make your best judgment and proceed.
```

That's the entire integration. No changes to Ralph.

**Trycycle — subagent prompt:**

```
Implement this spec using slot-machine with 3 slots.
Do not ask questions. Leave the workspace clean.
Spec: {plan_content}
```

Trycycle's orchestrator reads `.slot-machine/runs/latest/result.json` and passes the output to its review phase.

**Custom bash loop:**

```bash
for story in $(jq -r '.stories[] | select(.passes == false) | .id' prd.json); do
  SPEC=$(jq -r ".stories[] | select(.id == \"$story\") | .description" prd.json)
  claude -p "Use slot-machine with 3 slots. Spec: $SPEC" \
    --allowed-tools=all --permission-mode bypassPermissions
  VERDICT=$(jq -r '.verdict' .slot-machine/runs/latest/result.json 2>/dev/null)
  if [ "$VERDICT" != "NONE_ADEQUATE" ]; then
    jq "(.stories[] | select(.id == \"$story\")).passes = true" prd.json > tmp.json
    mv tmp.json prd.json
  fi
done
```

### What This Means for SKILL.md

Two additions only:

1. **JSON result artifact** — add to Phase 4 Final Report: always write `result.json` to the run directory + create `latest` symlink.
2. **`quiet: true` config** — add to Configuration table. When set, suppress progress tables. Final verdict + output path still printed.

No autonomous mode. No interactive/headless split. The pipeline is the same in both cases.

### README Section (to add)

Add a section to README.md titled **"## Works in Autonomous Loops"** with this content:

```markdown
## Works in Autonomous Loops

Slot-machine runs inside [Ralph](https://github.com/snarktank/ralph),
[Trycycle](https://github.com/danshapiro/trycycle), and custom agent loops.
No special setup — add config to your CLAUDE.md and the loop's AI instances
pick it up automatically.

Slot-machine self-regulates: it evaluates each task and only engages when the
task has meaningful design choices. Mechanical tasks (add a field, rename a
function) get single-shot implementation. You can blanket-enable slot-machine
and trust it to only spend compute when competition adds value.

**Setup (add to CLAUDE.md):**
\```markdown
## Slot Machine Settings
slot-machine-profile: coding
slots: 3
quiet: true
\```

Every run writes a machine-readable result to
`.slot-machine/runs/latest/result.json` that scripts can parse:

\```json
{
  "verdict": "PICK",
  "winning_slot": 2,
  "confidence": "HIGH",
  "files_changed": ["src/api.py", "tests/test_api.py"],
  "tests_passing": 45
}
\```

Set `quiet: true` to suppress progress tables in unattended runs.
The run directory (`.slot-machine/runs/`) keeps all artifacts
(slot drafts, reviewer scorecards, judge verdict) for post-hoc inspection.
```

## Next Steps

1. **Ship the current branch** (Phase 1 complete — profiles, pipeline, run storage, output formatting, model inheritance)
2. **Add JSON result artifact + quiet mode + README autonomous loop section** — small additions that enable loop integration without architectural changes
3. **Design and implement Phase 2: skill-per-slot** — start with tdd and ce:work as the two slot-compatible skills
4. **Spike Phase 3: native Codex dispatch** — prove Claude Code → Codex in a worktree, review the output, end-to-end
5. **Iterate on syntax** based on user testing of Phases 2-3
6. **Generalize harness support** based on ecosystem evolution (Gemini CLI, AMP, etc.)
