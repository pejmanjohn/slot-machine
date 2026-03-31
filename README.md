# 🎰 Slot Machine

**An open-source best-of-N agent skill for Claude Code and Codex.**

AI agents are probabilistic. The same spec produces different code every time — different designs, different bugs, different quality. A single attempt is a coin flip. Slot Machine gives you N coins and keeps the best one — or combines the best parts of each.

Run N independent implementations of the same feature in parallel. Each gets reviewed by an independent agent that hunts for real bugs. A meta-judge compares all of them and makes one of three calls: **pick** the clear winner, **synthesize** the best elements from multiple implementations into something better than any individual, or **reject all** if none meet the bar.

## What You Can Do

**Run 3 competing implementations and pick the best one:**
```
/slot-machine with 3 slots — Implement the payment webhook handler from PLAN.md
```
Three agents implement the same spec independently, each steered toward a different emphasis such as simplicity, robustness, or functional style. Independent reviewers hunt for bugs in each. A judge picks the winner — or synthesizes the best parts of several.

**Run the same workflow from Codex with the native skill invocation:**
```
$slot-machine with 3 slots — Implement the payment webhook handler from PLAN.md
```
Same orchestration, same artifacts, same review pipeline. The active host just changes how the skill is invoked and how native slots are dispatched.

**Assign a different skill to each slot:**
```
/slot-machine with /superpowers:test-driven-development and /ce:work — Build the rate limiter
```
Slot 1 follows TDD (tests first). Slot 2 follows CE patterns (codebase-aware). Same spec, different methodologies, best result wins.

**Use Claude-style `/skill` or Codex-style `$skill`, and target external harnesses when you want:**
```
/slot-machine with /superpowers:test-driven-development, $ce:work + codex, and codex — Implement the API
```
Three slots: Claude with TDD, Codex with CE patterns, and bare Codex. Slot definitions accept both `/skill` and `$skill`; slot-machine normalizes them and dispatches the right host-native form to each harness.

**It works for writing too:**
```
/slot-machine with profile: writing — Write the launch announcement
```
Each slot drafts with a different voice and structure. The judge picks the strongest draft or synthesizes the best elements from several.

**Set it once in your project and forget:**
```markdown
## Slot Machine Settings (add to `AGENTS.md` or `CLAUDE.md`)
slot-machine-slots:
  - /superpowers:test-driven-development
  - /ce:work
  - codex
  - default
```
Every slot-machine invocation in this project uses these slots automatically.

## How It Works

Slot-machine dispatches a pipeline of specialized agents. Each role is isolated — implementers never see each other's work, reviewers never see each other's reviews.

| Step | Agent | What it does |
|------|-------|-------------|
| **Implement** | N implementers (parallel) | Each builds the full spec independently in the active profile's isolated slot workspace: a git worktree for worktree profiles, or a per-slot file/directory target for file-isolated profiles. Different slots can use different skills or even different agent harnesses (Codex). |
| **Review** | N reviewers (parallel) | Each reviews one implementation blind — spec compliance, adversarial bug hunting with file:line evidence, test gap analysis. |
| **Judge** | 1 judge | Reads all reviewer scorecards, does targeted code inspection where reviewers disagree, and issues a verdict: **PICK** the winner, **SYNTHESIZE** the best elements, or **NONE_ADEQUATE**. |
| **Synthesize** | 1 synthesizer (if needed) | Takes one slot as base, ports specific elements from donors per the judge's plan, verifies coherence, runs the full test suite. |
| **Resolve** | Orchestrator | Finalizes the winner or synthesis result, cleans up worktrees when the profile uses them, and writes result artifacts with full model attribution. |

The key insight: the agent that implements never evaluates. The agent that reviews never sees alternatives. The judge only sees structured scorecards, not raw code (unless it needs to inspect a specific disagreement). This separation reduces the self-evaluation bias that shows up when one agent does everything.[^anthropic-harness]

## Claude Code: Install

Install slot-machine into Claude's user skill directory:

```bash
git clone https://github.com/pejmanjohn/slot-machine.git ~/.claude/skills/slot-machine
```

And update slot-machine with:

```bash
git -C ~/.claude/skills/slot-machine pull
```

### Codex: Local Skill Install

For Codex, the recommended local install path is a generated standalone skill bundle, not a plugin-root symlink. This keeps the skill identifier clean as `slot-machine` while preserving the repo's plugin metadata for publishing and development:

```bash
git clone https://github.com/pejmanjohn/slot-machine.git ~/src/slot-machine
~/src/slot-machine/scripts/install-codex-skill.sh
```

Whenever you want to update to the latest slot-machine, run:

```bash
~/src/slot-machine/scripts/update-codex-skill.sh --pull
```

## See It Work

You give it a spec:

> */slot-machine with 3 slots — Implement the TaskScheduler from the spec*

The skill takes over:

```
Slot Machine — coding profile

Feature: TaskScheduler
Slots: 3 | Simplest approach (claude-opus-4-6), Robustness (claude-opus-4-6), Functional (claude-opus-4-6)
```

Three agents implement the full spec independently, each in an isolated worktree with a different implementation emphasis. Then independent reviewers inspect each one — not a rubber stamp, an adversarial review with evidence:

```
Slot 1 Review:
  Spec Compliance: PASS
  Critical: src/scheduler.ts:47 — unhandled TypeError when concurrency
           is non-integer. Constructor accepts 1.5 silently.
  Important: src/scheduler.ts:38 — drain() doesn't account for tasks
             scheduled after drain is called.
  Verdict: Not a contender — critical validation bug.

Slot 2 Review:
  Spec Compliance: PASS
  Important: tests/scheduler.test.ts:92 — flaky timing assertion.
  Minor: No error message in constructor throw.
  Verdict: Yes — strongest validation, 17 tests.

Slot 3 Review:
  Spec Compliance: PASS
  Important: drain() uses snapshot semantics — may miss late-scheduled tasks.
  Verdict: Yes with concerns — clean API but drain limitation.
```

The judge compares all three, does targeted code inspection, and decides:

```
---

Verdict: PICK Slot 2 (Claude Code claude-opus-4-6) | Confidence: HIGH

Zero critical issues, strongest test coverage (17 tests including concurrency
stress tests), correct drain semantics. No synthesis needed — clear winner.

---
```

Bugs caught that would have shipped with a single implementation. The winner has 3x the test coverage of either alternative.

### When the Judge Synthesizes

Sometimes no single slot is the best at everything. In a cross-model run, the judge saw complementary strengths and called **SYNTHESIZE**:

```
---

Verdict: SYNTHESIZE | Confidence: HIGH

Slot 3 has the cleanest code. Slot 1 has the best tests. Combining both
produces something better than either.

- Base: Slot 3 (Codex gpt-5.4) — cleanest implementation, proper drain pattern
- + Slot 1 (Claude Code opus-4.6 w/ /ce:work) — 19-test suite: nested scheduling,
  timing verification, counter tracking
- Keep Slot 3: event-ordering drain test, error propagation test

---
```

The synthesizer agent starts with one slot as the base, ports specific elements from the donors, checks for coherence, and runs the full test suite. The result reads like one person wrote it, not like pieces were stitched together.

## Without vs With Slot Machine

| | Without Skill | With Slot Machine |
|---|---|---|
| **Implementations** | 1 | 3 (parallel) |
| **Review** | Implementer self-review (0 bugs in our benchmark) | 3 independent adversarial reviewers |
| **Bugs found** | 0 | 3 (including a crash-severity TypeError) |
| **Tests in winner** | ~20 | 45 |
| **Decision process** | Ships whatever it built | Evidence-based PICK or SYNTHESIZE with file:line reasoning |
| **Synthesis** | N/A | Can combine best code from one slot with best tests from another |
| **Confidence** | "Looks good to me" | HIGH — judge verified via targeted code inspection |
| **Design alternatives** | 0 (never explored) | 2 rejected alternatives with documented reasons |
| **Cross-model** | N/A | Claude vs Codex on same spec — different models find different bugs |

## Usage

```
/slot-machine

Spec: Implement the payment webhook handler from PLAN.md
```

Or from Codex:

```
$slot-machine

Spec: Implement the payment webhook handler from PLAN.md
```

Or inline with options:

```
/slot-machine with 3 slots, profile: writing

Spec: Write a changelog entry announcing the new task profiles feature
```

The skill also triggers on natural language: "slot-machine this", "best-of-N", "pull the lever", or "parallel implementations."

## Cross-Model Runs

Run the same spec across different agent harnesses and pick the best result:

```
/slot-machine with /ce:work, /ce:work + codex, and codex

Spec: Implement the TaskScheduler class from PLAN.md
```

Three slots: Claude Code with CE patterns, Codex with CE patterns, and bare Codex. Each implements independently, all reviewed by the same evaluation pipeline. The progress table tracks both harness and model:

| Slot | Status | Harness | Model | Tests | Approach |
|------|--------|---------|-------|-------|----------|
| 1 | `DONE` | `Claude Code` | `claude-opus-4-6` | 17 tests | /ce:work |
| 2 | `DONE_WITH_CONCERNS` | `Codex` | `gpt-5.4` | 5 tests | /ce:work + codex |
| 3 | `DONE_WITH_CONCERNS` | `Codex` | `gpt-5.4` | 5 tests | codex |

**Skills** guide methodology (TDD, CE patterns). **Harnesses** choose the AI system (`claude`, `codex`). Compose them with `+`:

```
/slot-machine with 4 slots:
  slot 1: /superpowers:test-driven-development
  slot 2: /superpowers:test-driven-development + codex
  slot 3: /ce:work
  slot 4: codex
```

Slot definitions accept both `/skill` and `$skill`. Slot-machine normalizes that to a host-neutral skill reference, then dispatches the harness-native form when it runs the slot.

Execution stays host-relative. If you start on Claude, Claude-targeted slots stay native and Codex-targeted slots run in isolated slot workspaces with `codex exec`. If you start on Codex, Codex-targeted slots use the native Codex slot path with `codex exec`, and only Claude-targeted slots use `claude -p`.

Or set project defaults in `AGENTS.md` or `CLAUDE.md`:

```markdown
## Slot Machine Settings
slot-machine-slots:
  - /superpowers:test-driven-development
  - /ce:work
  - codex
  - default
```

## Profiles: Coding and Writing

Slot-machine auto-detects whether your spec is a coding task or a writing task and loads the right profile. Each profile has its own approach hints, reviewer criteria, and synthesis strategy. Those criteria are not cosmetic; they determine what the evaluation pipeline rewards.

**Coding profile** (`isolation: worktree`):
- Hints steer toward different implementation emphases: simplicity, robustness, functional style, idiomatic APIs, extensibility
- Reviewer checks spec compliance, hunts bugs with file:line evidence, assesses test coverage
- Pre-checks run your test suite before review
- Each slot gets an isolated git worktree

**Writing profile** (`isolation: file`):
- Hints steer toward different voices: concise, narrative, technical, conversational, structured
- Reviewer checks brief compliance, prose quality, audience fit, coherence
- No git worktrees — each slot writes to a file
- Synthesis merges the best phrasing and structure from multiple drafts

Force a profile with `profile: writing` or `profile: coding`, or let auto-detection handle it.

## Works With Your Other Skills

Each implementer slot runs in the selected harness with access to that host's installed skills. You can assign a specific skill per slot — or let implementers pick up skills automatically from your environment.

Works with [superpowers](https://github.com/obra/superpowers), [compound-engineering](https://github.com/EveryInc/compound-engineering-plugin), [gstack](https://github.com/garrytan/gstack), or any other implementation skill. The orchestrator passes your `AGENTS.md` and/or `CLAUDE.md` conventions as project context to each implementer, so project-specific rules apply to every slot automatically.

## What the Reviewer Actually Finds

This is a real finding from one of our test runs. The reviewer is an independent agent that reads the actual code — not the implementer's self-report:

```
Critical: src/api.py:47 — Unhandled TypeError crash

  What: POST /tasks with priority="high" (string instead of int) causes
        an unhandled TypeError in PriorityQueue.put(). Flask catches it
        and returns a generic 500 Internal Server Error.

  Impact: Any API caller sending a non-integer priority crashes the endpoint.
          No error message, no 400 Bad Request — just a 500.

  Fix: Add type validation before queue insertion:
       if not isinstance(priority, int):
           return jsonify({"error": "priority must be an integer"}), 400
```

The reviewer cites the exact file and line, explains the impact, and suggests a fix. The implementer's self-review said "all requirements implemented, tests pass" — it missed this entirely.

The judge then ranks all slots based on reviewer findings:

```
| Rank | Slot | Critical | Important | Minor | Spec | Verdict       |
|------|------|----------|-----------|-------|------|---------------|
| 1    | 2    | 0        | 1         | 1     | PASS | Winner        |
| 2    | 3    | 0        | 2         | 1     | PASS | With concerns |
| 3    | 1    | 1        | 1         | 0     | PASS | Disqualified  |
```

That's what goes into your codebase. Not the first thing, not the prettiest — the one that held up under independent scrutiny.

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `slots` | 3 | Number of parallel attempts |
| `approach_hints` | true | Different architectural direction per slot |
| `auto_synthesize` | true | Allow combining best elements from multiple slots |
| `max_retries` | 1 | Re-run failed slots (0 = no retry) |
| `manual_handoff` | false | Stop after per-slot review, keep successful slot worktrees, restore your original checkout, and let you choose/merge manually |
| `cleanup` | true | Delete worktrees after completion |
| `quiet` | false | Suppress progress tables (for autonomous loops) |
| `implementer_model` | inherit | Model for implementers (inherits from session) |
| `reviewer_model` | inherit | Model for reviewers (inherits from session) |
| `judge_model` | inherit | Model for judge (inherits from session) |
| `synthesizer_model` | inherit | Model for synthesizer (inherits from session) |

Set project defaults in `AGENTS.md`, `CLAUDE.md`, or both. When both exist, non-conflicting `slot-machine-*` settings merge; conflicting keys prefer the active host file. You can still override inline with `/slot-machine with 3 slots`.

## When to Use

Slot-machine trades tokens and time for quality. In return, you get independent review that catches bugs self-review misses, multiple design alternatives compared under structured criteria, and the option to synthesize the best parts of each.

That tradeoff is worth it when the cost of shipping a bug exceeds the cost of the extra compute, and when the task sits near the edge of what the current model does reliably on its own. It's not worth it when the task is mechanical or comfortably within cheap single-shot execution.

**Use when:**
- Feature has meaningful design choices (architecture, patterns, tradeoffs)
- The code will ship to production or be built on top of
- Spec is clear enough for independent implementation
- Running in autonomous loops where you're not waiting at the terminal — the extra time costs nothing when the agent is working overnight

**Skip when:**
- Simple mechanical changes (rename, add a field)
- You already know exactly how it should be built
- Spec is too vague — brainstorm first, then slot-machine
- Interactive back-and-forth where you're waiting for each response

Does this problem have a design space worth exploring? If yes, pull the lever.

## Works in Autonomous Loops

Slot-machine runs inside [Ralph Loop](https://ghuntley.com/loop/) and custom agent loops. No special setup — add config to `AGENTS.md`, `CLAUDE.md`, or both, and the loop's AI instances pick it up automatically.

Slot-machine is a good fit for loops when the task is worth the extra compute. Use it for tasks with real design space, and skip it for mechanical work where best-of-N comparison does not add value.

**Setup (add to `AGENTS.md` or `CLAUDE.md`):**

```markdown
## Slot Machine Settings
slot-machine-profile: coding
slot-machine-slots:
  - /ce:work
  - $superpowers:test-driven-development + codex
  - default
```

Every run writes a machine-readable result to `.slot-machine/runs/latest/result.json` that scripts can parse:

```json
{
  "verdict": "PICK",
  "winning_slot": 2,
  "confidence": "HIGH",
  "slots": 3,
  "slots_succeeded": 3,
  "files_changed": ["src/api.py", "tests/test_api.py"],
  "tests_passing": 45,
  "run_dir": ".slot-machine/runs/2026-03-29-payment-webhook"
}
```

Set `quiet: true` to suppress progress tables in unattended runs. The run directory (`.slot-machine/runs/`) keeps all artifacts (slot drafts, reviewer scorecards, judge verdict) for post-hoc inspection.

## Custom Profiles

Create your own profiles to customize how slot-machine implements, reviews, judges, and synthesizes. Use this to enforce your team's coding standards, define domain-specific review criteria, or change how the judge weighs tradeoffs. A profile is a folder with 5 files:

```
my-profile/
  0-profile.md       # Config: name, isolation, pre-checks, approach hints
  1-implementer.md   # Prompt for each implementation agent
  2-reviewer.md      # Prompt for each review agent
  3-judge.md         # Prompt for the meta-judge
  4-synthesizer.md   # Prompt for the synthesizer
```

**Profile config (`0-profile.md`)** uses YAML frontmatter:

```yaml
---
name: api-review
description: For reviewing and reimplementing API endpoints with security focus.
extends: coding
isolation: worktree
pre_checks: |
  {test_command} 2>&1
  npm audit 2>&1
---

## Approach Hints

1. "Focus on input validation and authentication — treat every caller as untrusted."
2. "Optimize for observability — structured logging, error codes, request tracing."
3. "Design for backward compatibility — existing clients must not break."
```

**Inheritance:** Set `extends: coding` to inherit all prompts from the coding profile and override only what you change. Files present in your profile replace the base; missing files are inherited. One level of inheritance max. Built-in base profiles are resolved from the physical slot-machine skill directory, so inherited-profile lookup still works when the installed skill path is a symlink instead of a copied directory. If the selected profile or its base still cannot be resolved, slot-machine stops before dispatch and writes a blocked `.slot-machine/runs/latest/result.json` artifact instead of stalling.

**Install locations:**
- **Project-local:** `./profiles/my-profile/` (checked into your repo)
- **Personal:** `~/.slot-machine/profiles/my-profile/` (available in all projects)

Use it: `/slot-machine with profile: my-profile`

Or set as project default in `AGENTS.md` or `CLAUDE.md`:

```markdown
slot-machine-profile: my-profile
```

All prompts receive [universal variables](SKILL.md#universal-variables) (`{{SPEC}}`, `{{PROJECT_CONTEXT}}`, `{{APPROACH_HINT}}`, etc.) — your prompts just need to reference them.

## Why Not Just Ask Claude to Do It 5 Times?

We tried that. Five parallel implementations, no skill, Claude doing what it naturally does. The parallelism worked fine. Six things broke:

**Self-review misses things.** The same agent that wrote the code also graded it. In our benchmark, self-review found 0 bugs. Independent reviewers found 3 — including a crash-severity TypeError. Anthropic reports the same failure mode in long-running harnesses: agents tend to overrate their own work, and tuning a separate evaluator is much more tractable than making the generator grade itself honestly.[^anthropic-harness]

**No structured comparison.** Without a rubric, Claude made an ad hoc "this one looks best" decision. No spec compliance check, no severity categorization, no file:line evidence. The judge in slot-machine reads structured scorecards with ranked findings — not vibes. Anthropic's harness write-up reaches the same conclusion: turning vague judgments into explicit criteria and thresholds makes evaluator output far more useful.[^anthropic-harness]

**No synthesis.** When no single implementation is best at everything — one has the cleanest code, another has the best tests — Claude just picks one and loses the other's strengths. Slot-machine's judge can call SYNTHESIZE: combine the best code from one slot with the best tests from another.

**No diversity.** Without guidance, Claude produces similar implementations each time. Same patterns, same blind spots. Slot-machine creates diversity at three levels: hints steer each slot toward a different implementation emphasis (simplicity vs robustness vs functional style), skills assign different methodologies per slot (TDD for one, CE patterns for another), and cross-model dispatch runs some slots on entirely different agent harnesses (Codex finds bugs Claude doesn't, and vice versa).

**No isolation.** Without per-slot isolation, parallel attempts write into the same place and clobber each other. Slot-machine isolates each slot using the active profile's storage model: git worktrees for coding-style worktree profiles, or separate per-slot files/directories for file-isolated profiles. The attempts stay independent, and the final winner or synthesis can be resolved cleanly.

**No trail.** Without the skill, the comparison is ephemeral — gone when the conversation ends. Slot-machine saves reviewer scorecards, judge verdict, and result artifacts to `.slot-machine/runs/` for post-hoc inspection.

The hard part isn't running N agents. It's evaluating their output honestly.

## This is NOT Standard Parallel Agents

Every major tool splits different tasks across agents (frontend, backend, tests in parallel). That's task decomposition.

Slot Machine gives the **same task** to N agents and compares their **full implementations**. The value isn't parallelism — it's competition, independent review, and structured judgment. Different problem, different solution.

## Running Tests

```bash
./tests/run-tests.sh                  # Tier 1: contracts, skill structure, harness integrity
./tests/run-tests.sh --changed        # Tier 1 + the smallest heavier checks matched to local changes
./tests/run-tests.sh --host claude    # Restrict headless tests to one host
./tests/run-tests.sh --jobs auto      # Parallelize independent tests
./tests/run-tests.sh --smoke          # + Real implementer/reviewer/judge smoke tests on each available host
./tests/run-tests.sh --integration    # + Heavier E2E coverage on the selected host path
./tests/run-tests.sh --all            # Everything the runner knows about, including explicit skips
```

The fast suite is the host-agnostic validation layer: it checks prompt contracts, skill structure, and harness integrity. `--changed` keeps Tier 1 and adds only the heavier checks that match the files you actually changed. `--host` trims smoke/E2E tests to one host when you do not need the full matrix, and `--jobs` parallelizes independent shell tests. The smoke tier still runs phase checks on each allowed host, and the happy-path integration test uses the selected viable host path. When Codex is present but the Codex-to-Claude bridge is not operational, integration falls back to the viable host path instead of hanging. `test-e2e-edge-cases.sh` and `test-reviewer-accuracy.sh` still report explicit skips instead of passing silently.

[^anthropic-harness]: Anthropic, [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps) (Mar. 24, 2026). Useful external support for three claims reflected here: LLM self-evaluation is lenient, explicit grading criteria matter, and external evaluation is most worth the cost when the task is beyond what the current model handles reliably solo.

## License

MIT
