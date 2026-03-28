# E2E Test 11: Skill + Harness Composition (/superpowers:tdd + codex)

**Date:** 2026-03-28
**Spec:** Stack class with push, pop, peek, is_empty
**Slots:** 2 (Slot 1: /superpowers:tdd on Claude, Slot 2: /superpowers:tdd + codex)

## Results

| Check | Result | Notes |
|-------|--------|-------|
| Both slots followed TDD sequence | PASS | Tests written first, RED step, then GREEN |
| Codex received TDD methodology in prompt | PASS | Prompt included "METHODOLOGY: Follow TDD principles" |
| Codex actually followed TDD | PARTIAL | Loaded TDD skill, ran tests-first, but RED was shallow (ModuleNotFoundError, not assertion failure) |
| Both produced valid implementations | PASS | Nearly identical list-backed Stack classes |
| Different test approaches | YES | Claude: 15 tests in 4 classes. Codex: 6 flat tests. |
| Judge compared cross-harness | PASS | Evidence-based PICK with composition-specific analysis |
| result.json includes composition info | PASS | composition_test field present |

## Verdict
PICK Slot 1 (Claude + TDD) — HIGH confidence. 15 vs 6 tests, deeper TDD discipline.

## Key Finding: Composition Gap

The judge identified a nuanced issue: **TDD skill guidance transferred the mechanics (tests-before-code) but not the depth (tests-as-spec).**

- **Claude + TDD:** 15 tests covering LIFO ordering, None values, drain-then-raises, peek non-mutation
- **Codex + TDD:** 6 tests covering happy path + 2 error cases only
- **RED step difference:** Claude's RED had assertion failures; Codex's RED was ModuleNotFoundError (never reached assertions)

### Recommendation
The Codex dispatch prompt (Path C in SKILL.md) should specify that TDD methodology means:
1. Write tests first
2. Create module stubs with `pass`/`raise NotImplementedError` bodies
3. Run tests — they should fail at the ASSERTION level, not the import level
4. Then implement

This is a prompt quality improvement, not an architecture change.

## Qualitative Comparison

Both implementations used `self._items = []` with identical method signatures. Error messages differed slightly ("pop from an empty stack" vs "pop from empty stack"). The implementations demonstrate that different models converge on the same canonical solution — the value of cross-harness is in the TEST diversity, not the implementation diversity for simple specs.

## Issues to Fix
- SKILL.md Path C TDD guidance should be more explicit about RED step quality (module stubs before first test run)
