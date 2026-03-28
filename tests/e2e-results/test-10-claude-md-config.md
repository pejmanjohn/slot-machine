# E2E Test 10: CLAUDE.md Config-Driven Slots

**Date:** 2026-03-28
**Spec:** factorial(n)
**Slots:** 2 (from CLAUDE.md config: /superpowers:tdd, default)

## Results

| Check | Result | Notes |
|-------|--------|-------|
| CLAUDE.md config loaded | PASS | `slot-machine-slots` list detected and parsed |
| Slot count from config | PASS | 2 slots (equals number of definitions) |
| Slot 1 used TDD (skill) | PASS | Wrote 6 failing tests first, then implemented |
| Slot 2 used profile implementer + hint | PASS | "Robustness" hint → 34 tests, bool rejection, MAX_INPUT guard |
| Hint only on default slot | PASS | Slot 1 (skill) had no hint, Slot 2 (default) got robustness hint |
| User was NOT asked to specify slots | PASS | Config auto-loaded from CLAUDE.md |
| Pipeline completed | PASS | PICK Slot 1, HIGH confidence |

## Verdict
PICK Slot 1 (TDD) — spec-faithful 8-line implementation. Slot 2's robustness extras (bool rejection, MAX_INPUT) were correctly identified as YAGNI by the judge.

## Notable Findings

1. **CLAUDE.md config auto-loading works.** The orchestrator correctly reads `slot-machine-slots` from CLAUDE.md when no inline definitions are provided.
2. **Hints create genuine diversity.** The "robustness" hint produced a dramatically different implementation (34 tests, 70-line implementation with bool rejection, overflow guard, __index__ protocol) vs TDD's minimal 6-test, 8-line solution.
3. **Judge correctly applies YAGNI.** Despite Slot 2 being more "impressive," the judge picked Slot 1 for spec fidelity. The judge recommended cherry-picking one specific test (test_against_stdlib) — showing nuanced judgment.
4. **result.json includes slot_config_source field.** Added "CLAUDE.md" to identify config origin — useful for auditing.

## Issues
None found.
