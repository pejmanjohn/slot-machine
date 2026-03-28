# E2E Test 11 v2: Native Skill Invocation ($superpowers:tdd + codex)

**Date:** 2026-03-28
**Spec:** Stack class with push, pop, peek, is_empty
**Slots:** 2 (Slot 1: /superpowers:tdd on Claude, Slot 2: /superpowers:tdd + codex with native $prefix)
**Change tested:** `$superpowers:tdd` at start of codex exec prompt instead of text methodology hint

## Results vs Previous Run

| Metric | v1 (text hint) | v2 (native $skill) |
|--------|---------------|-------------------|
| RED/GREEN cycles | 1 (bulk) | 6 (incremental, one per behavior) |
| pytest invocations during TDD | 2 (red, green) | 12 (red+green per cycle) |
| Tests produced | 6 flat | 6 flat |
| Implementation quality | Minimal, correct | Minimal, correct, type-annotated |
| TDD discipline | Mechanical (tests-before-code) | Genuine (incremental RED/GREEN per behavior) |

## Key Improvement: Incremental TDD Cycles

With the text hint, Codex wrote all tests, ran once (RED), implemented everything, ran once (GREEN). Two pytest runs total.

With native `$superpowers:tdd`, Codex ran **6 distinct RED/GREEN cycles**:
1. `is_empty` → RED (missing module) → add minimal Stack → GREEN
2. `push` → RED (missing method) → add push → GREEN
3. `peek` → RED (missing method) → add peek → GREEN
4. `pop` → RED (missing method) → add pop → GREEN
5. `pop` on empty → already GREEN (IndexError from list.pop())
6. `peek` on empty → already GREEN (IndexError from list[-1])

Each cycle added ONE behavior, ran pytest, confirmed the failure, implemented the minimum, ran pytest again. This is textbook TDD.

## What Stayed the Same

- Test count: still 6 (same as v1) — Codex's TDD skill produces one test per behavior, not per edge case
- Claude's slot still won on test depth (16 vs 6)
- Implementation architecture identical (list-backed Stack)

## What Changed

- **TDD process fidelity dramatically improved.** The skill's full instructions (RED step requirements, incremental behavior addition, refactor phase) were followed because Codex loaded the complete SKILL.md rather than reading a one-sentence summary.
- **Type annotations appeared** (`-> None`, `-> object`, `-> bool`, `list[object]`) — likely from Codex's own style rather than the skill, but shows the model had more headroom to apply craft when not constrained by a text-hint prompt.
- **Codex also loaded brainstorming and verification-before-completion skills** — the full superpowers workflow, not just TDD in isolation.

## Conclusion

Native skill invocation (`$superpowers:tdd`) is significantly better than text hints for methodology transfer. The orchestrator should NOT try to summarize skills — it should pass the skill reference and let each harness load the full skill document natively.

The remaining gap (6 tests vs 16) is genuine model difference, not a skill transfer problem. Different models, given the same TDD skill, produce different numbers of test cases. This is exactly the kind of diversity cross-harness comparison is designed to surface.
