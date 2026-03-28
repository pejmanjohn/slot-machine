# 🎰 Slot Machine

**An open-source agent skill for Claude Code, Codex, and Gemini CLI.**

AI agents are probabilistic. The same spec produces different code every time — different designs, different bugs, different quality. A single attempt is a coin flip. Slot Machine gives you N coins and keeps the best one — or combines the best parts of each.

Run N independent implementations of the same feature in parallel. Each gets reviewed by an independent agent that hunts for real bugs. A meta-judge compares all of them and makes one of three calls: **pick** the clear winner, **synthesize** the best elements from multiple implementations into something better than any individual, or **reject all** if none meet the bar.

## See It Work

You give it a spec:

> *Use slot-machine with 3 slots to implement the Task Queue API from the spec*

The skill takes over:

```
🎰 Slot Machine: Pulling the lever with 3 slots
Feature: Task Queue API
Baseline: 1 test passing
Hints:
  Slot 1 → Simplest possible approach
  Slot 2 → Design for robustness
  Slot 3 → Functional / data-oriented approach
```

Three agents implement the full spec independently, each in an isolated worktree. Then independent reviewers inspect each one — not a rubber stamp, an adversarial review with evidence:

```
Slot 1 Review:
  Spec Compliance: PASS
  Critical: src/api.py:47 — unhandled TypeError crash when priority
           is non-integer. Flask returns 500 instead of 400.
  Important: src/task_queue.py:38 — to_dict() called outside lock.
             Another thread can see inconsistent state.
  Verdict: Not a contender — critical API crash.

Slot 2 Review:
  Spec Compliance: PASS
  Important: tests/test_api.py:92 — flaky timing assertion, may
             fail under CI load.
  Minor: No __repr__ on TaskQueue for debugging.
  Verdict: Yes — strongest validation, 45 tests.

Slot 3 Review:
  Spec Compliance: PASS
  Important: Sentinel object in worker lifecycle can mask shutdown errors.
  Verdict: Yes with concerns — elegant API but sentinel bug.
```

The opus-level judge compares all three, does targeted code inspection, and decides:

```
🎰 Slot Machine Complete
Feature: Task Queue API
Slots: 3 (3 succeeded, 0 failed)
Verdict: PICK slot-2 (HIGH confidence)
Tests: 45 passing

Why Slot 2 won:
• Zero critical issues (Slot 1 had a crash)
• Input validation at both layers (TaskQueue + Flask API)
• Correct lock granularity (Slot 1 had a race condition)
• 45 tests including concurrent access stress tests
```

Three bugs caught that would have shipped with a single implementation. The winner has 2x the test coverage.

### When the Judge Synthesizes

Sometimes no single slot is the best at everything. In an earlier test run on a rate limiter spec, the judge saw complementary strengths across slots and called **SYNTHESIZE** instead of PICK:

```
🎰 Slot Machine Complete
Feature: Token Bucket Rate Limiter
Verdict: SYNTHESIZE (HIGH confidence)

Synthesis plan:
  Base: Slot 3 (readability) — cleanest structure, spec-faithful consume()
  + From Slot 1: refill_rate=0 support for fixed-capacity buckets
  + From Slot 2: edge-case tests (tiny capacity, over-capacity, high-refill cap)

Result: 74 lines, 28 tests — combines the best code from Slot 3
        with the best tests from Slots 1 and 2
```

The synthesizer agent works from the judge's plan: it starts with one slot as the base, ports specific elements from the donors, checks for coherence, and runs the full test suite. The result reads like one person wrote it, not like pieces were stitched together.

This is one of the skill's strongest features — you don't have to choose between "clean code" and "thorough tests" when different slots excel at each.

## Without vs With Slot Machine

We benchmarked on the same spec (multi-file Task Queue API), same model, same machine:

| | Without Skill | With Slot Machine |
|---|---|---|
| **Implementations** | 1 | 3 (parallel) |
| **Review** | Self-review (finds 0 bugs) | 3 independent adversarial reviewers |
| **Bugs found** | 0 | 3 (including a crash-severity TypeError) |
| **Tests in winner** | ~20 | 45 |
| **Decision process** | Ships whatever it built | Evidence-based PICK or SYNTHESIZE with file:line reasoning |
| **Synthesis** | N/A | Can combine best code from one slot with best tests from another |
| **Confidence** | "Looks good to me" | HIGH — judge verified via targeted code inspection |
| **Design alternatives** | 0 (never explored) | 2 rejected alternatives with documented reasons |

## Install

**Claude Code (plugin):**
```
/plugin marketplace add pejman/slot-machine
/plugin install slot-machine@slot-machine
```

**Claude Code (manual):**
```bash
git clone https://github.com/pejman/slot-machine.git ~/.claude/skills/slot-machine
```

**Codex:**
```bash
git clone https://github.com/pejman/slot-machine.git ~/.codex/skills/slot-machine
```

**Gemini CLI:**
```bash
gemini extensions install https://github.com/pejman/slot-machine
```

## Usage

```
/slot-machine

Spec: Implement the payment webhook handler from PLAN.md
```

Or inline with options:

```
/slot-machine with 3 slots, profile: writing

Spec: Write a changelog entry announcing the new task profiles feature
```

The skill also triggers on natural language: "slot-machine this", "best-of-N", "pull the lever", or "parallel implementations."

## Works With Your Other Skills

Each implementer subagent is a full Claude Code session with access to all your installed skills. If you use [superpowers](https://github.com/obra/superpowers), [gstack](https://github.com/garrytan/gstack), [compound-engineering](https://github.com/EveryInc/compound-engineering-plugin), or any other skills, the implementers can use them automatically.

**Common combos:**

| Your Skill | What Happens in Slot Machine |
|-----------|------------------------------|
| superpowers TDD | Each implementer writes tests first, watches them fail, then implements |
| superpowers systematic-debugging | If an implementer gets stuck, it debugs methodically instead of guessing |
| gstack /review | The judge can reference your project's review conventions |
| compound-engineering workflows | Implementers follow your team's coding patterns |

To make this explicit, mention it in your spec:

```
Use slot-machine with 3 slots. Each implementer should follow TDD.

Spec: [your feature spec]
```

Or add it to your project's `CLAUDE.md`:

```markdown
## Slot Machine Settings
When using slot-machine, implementers should:
- Follow TDD (write failing test first)
- Use our project's existing patterns in src/services/
- Run `make lint` before committing
```

The orchestrator passes your `CLAUDE.md` conventions as project context to each implementer, so project-specific rules apply to every slot automatically.

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

## How It Works

1. **Setup** — Validate the spec, gather project context, verify tests pass
2. **Implement** — N agents work in parallel, each in an isolated worktree with a different architectural hint:
   - *"Simplest possible approach — single class, minimal API surface"*
   - *"Design for robustness — input validation, error handling, edge cases"*
   - *"Functional / data-oriented — dataclasses, composition over inheritance"*
   - *"Context-manager API — Pythonic with `with` statements, protocols"*
   - *"Build for extensibility — protocols/ABCs, dependency injection"*
3. **Review** — Independent reviewers inspect each implementation: spec compliance (pass/fail), adversarial bug hunting (file:line evidence), test gap analysis
4. **Judge** — An opus-level meta-judge compares all reviews, does targeted code inspection, and returns one of three verdicts:
   - **PICK** — one slot is the clear winner → merge it
   - **SYNTHESIZE** — multiple slots have complementary strengths → a synthesizer agent combines the best elements into one coherent implementation
   - **NONE_ADEQUATE** — all slots have critical issues → report to user, don't ship broken code
5. **Resolve** — Merge the winner (or synthesis), clean up worktrees, report the outcome

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `slots` | 5 | Number of parallel attempts |
| `approach_hints` | true | Different architectural direction per slot |
| `auto_synthesize` | true | Allow combining best elements from multiple slots |
| `implementer_model` | sonnet | Model for implementers and reviewers |
| `judge_model` | opus | Model for judge and synthesizer |

Set in your project's `CLAUDE.md` or override inline: `"slot-machine this with 3 slots"`

## When to Use

**Use when:**
- Feature has meaningful design choices (architecture, patterns, tradeoffs)
- Quality matters more than speed
- Spec is clear enough for independent implementation
- Medium complexity (1-4 hours of agent time per attempt)

**Skip when:**
- Simple mechanical changes (rename, add a field)
- You already know exactly how it should be built
- Spec is too vague — brainstorm first, then slot-machine

## Running Tests

```bash
./tests/run-tests.sh                  # Contract validation (instant)
./tests/run-tests.sh --smoke          # + Phase-level tests (~10 min)
./tests/run-tests.sh --integration    # + Full E2E (~20-30 min)
./tests/run-tests.sh --all            # Everything
```

57 contract assertions verify format consistency across all agent prompts. E2E tests run the full pipeline headlessly via `claude -p` and verify the NDJSON transcript.

## Works in Autonomous Loops

Slot-machine runs inside [Ralph](https://github.com/snarktank/ralph), [Trycycle](https://github.com/danshapiro/trycycle), and custom agent loops. No special setup — add config to your `CLAUDE.md` and the loop's AI instances pick it up automatically.

Slot-machine self-regulates: it evaluates each task and only engages when the task has meaningful design choices. Mechanical tasks (add a field, rename a function) get single-shot implementation. You can blanket-enable slot-machine and trust it to only spend compute when competition adds value.

**Setup (add to CLAUDE.md):**

```markdown
## Slot Machine Settings
slot-machine-profile: coding
slots: 3
quiet: true
```

Every run writes a machine-readable result to `.slot-machine/runs/latest/result.json` that scripts can parse:

```json
{
  "verdict": "PICK",
  "winning_slot": 2,
  "confidence": "HIGH",
  "files_changed": ["src/api.py", "tests/test_api.py"],
  "tests_passing": 45
}
```

Set `quiet: true` to suppress progress tables in unattended runs. The run directory (`.slot-machine/runs/`) keeps all artifacts (slot drafts, reviewer scorecards, judge verdict) for post-hoc inspection.

## This is NOT Standard Parallel Agents

Every major tool splits different tasks across agents (frontend, backend, tests in parallel). That's task decomposition.

Slot Machine gives the **same task** to N agents and compares their **full implementations**. The value isn't parallelism — it's competition, independent review, and structured judgment. Different problem, different solution.

## License

MIT
