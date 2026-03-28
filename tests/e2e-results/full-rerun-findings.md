# Full E2E Re-Run Findings

**Date:** 2026-03-28
**Tests run:** 7, 8, 10, 11 (all with fresh specs)

## Test 7: Skill-per-slot (clamp function)

**Result:** PASS — all 3 slots worked correctly.

**Observation:** For simple functions, skill-based slots (TDD, CE work) produce similar architectures. The approach *hint* (functional/data-oriented) produced the most architecturally distinct implementation (`max(minimum, min(value, maximum))` vs if/elif chains). Skills guide *process*, hints guide *architecture*. Both are valuable but for different reasons.

## Test 8: Cross-harness — bare Codex (flatten function)

**Result:** PASS — both slots produced working implementations.

**Finding: Bare Codex loads superpowers autonomously.** Even without `$superpowers:tdd` in the prompt, Codex loaded `using-superpowers`, `brainstorming`, and `test-driven-development` on its own (because they're installed at `~/.codex/superpowers/`). This means:
- `codex` slot ≠ "vanilla codex" — it's "codex with whatever skills the user has installed"
- A bare `codex` slot and a `/superpowers:tdd + codex` slot may behave similarly if the user has TDD installed on Codex

**Is this a problem?** No — it's the user's Codex installation. The explicit `$superpowers:tdd` makes the intent clear and ensures the skill is invoked even if `using-superpowers` wouldn't auto-select it. But the orchestrator should not expect bare Codex to be "skill-free."

**Bonus finding:** Codex created a proper `NotImplementedError` stub for the RED step (vs ModuleNotFoundError in earlier runs). This happened because it loaded the TDD skill on its own. The native skill invocation change is working even indirectly.

## Test 10: CLAUDE.md config (range_iter function)

**Result:** PASS — config auto-loaded, slots worked correctly.

**Observation:** The "extensibility" hint produced a Strategy pattern with a Protocol — genuinely different from the TDD slot's while-loop. 26 tests vs 11. Hints continue to produce meaningful architectural diversity.

## Test 11: Skill + harness composition (LRUCache)

**Result:** FAIL on first attempt, PASS after fix.

### Critical Finding: Interactive skill gates block codex exec

**What happened:** Codex loaded the brainstorming skill (via `using-superpowers`). The brainstorming skill has a design-approval gate that asks the user to confirm a design choice. In `codex exec` non-interactive mode, Codex emitted "Reply with `1` or `2`" and the session ended. Zero files produced.

**Fix:** Added "Do not ask questions or wait for confirmation — make your best judgment and proceed" to the Codex dispatch prompt. On retry, Codex said "The user explicitly asked me to proceed without questions, so I'm treating the design step as a brief internal spec and moving straight into red-green." Problem solved.

**After fix:** Codex produced a correct LRU implementation (OrderedDict-based, same approach as Claude) with 5 tests. The TDD RED/GREEN cycle ran properly.

## Summary of Issues Found and Fixed

| Issue | Severity | Fix | Commit |
|-------|----------|-----|--------|
| Interactive skill gates block codex exec | **Breaking** (zero output) | "Do not ask questions" in prompt | `8874f2a` |
| Native skill invocation (previous session) | Quality gap | `$prefix` instead of text hints | `58f7fe6` |
| Codex files uncommitted (previous session) | Quality gap | Explicit commit step in Path C | `edb8710` |

## Observations (Not Issues)

1. **Bare Codex auto-loads installed skills.** Expected behavior, not a bug.
2. **Skills guide process, hints guide architecture.** Both create diversity but in different dimensions.
3. **Test depth gap persists across harnesses.** Claude consistently produces more tests (16-20) than Codex (4-6) for the same spec. This is model difference, not skill transfer.
4. **Implementations converge on canonical solutions.** For well-specified functions, both models reach the same architecture (OrderedDict for LRU, list for Stack, recursive extend for flatten). Cross-harness value is in test diversity and edge case coverage, not implementation diversity.
