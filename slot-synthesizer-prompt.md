# Slot Synthesizer Prompt Template

The orchestrator reads this template, fills in all `{{VARIABLES}}`, and passes the result as the `prompt` parameter to the Agent tool. The synthesizer should use the most capable available model and gets its own worktree via `isolation: "worktree"`.

---

The meta-judge reviewed multiple implementations of the same feature and decided the best result is a synthesis — combining the best elements from multiple attempts. Your job: execute the synthesis plan.

## Original Specification

{{SPEC}}

## Judge's Synthesis Plan

{{SYNTHESIS_PLAN}}

## Slot Worktrees

These are the worktrees you can read from:

{{WORKTREE_PATHS}}

The base slot worktree: `{{BASE_SLOT_PATH}}`

## Your Process

1. **Start from the base slot.** Copy the base implementation's changes into your working directory. This is your foundation — the judge chose it because it has the strongest overall implementation.

   ```bash
   # Get the list of changed files from the base slot
   cd {{BASE_SLOT_PATH}}
   git diff --name-only HEAD~1
   # Copy those files to your worktree
   ```

2. **Port elements per the plan.** For each item in the synthesis plan:
   - Read the source code in the donor slot's worktree
   - Read the corresponding area in your working copy
   - Integrate the donor's approach cleanly
   - **Don't just copy-paste** — adapt to the base's conventions, naming, and patterns

3. **Check for coherence.** After all ports:
   - Do imports and dependencies line up?
   - Are naming conventions consistent throughout?
   - Do the ported pieces integrate naturally or feel bolted on?
   - Any conflicting patterns or duplicate logic?
   - Read the whole thing as if one person wrote it

4. **Run the full test suite.** All existing + new tests must pass.
   If tests fail:
   - Diagnose: integration issue or fundamental conflict?
   - Fix integration issues (import paths, naming mismatches)
   - If there's a fundamental conflict between ported elements, report DONE_WITH_CONCERNS and describe the conflict

5. **Self-review.** Read through the entire implementation as a whole. It should read like one person wrote it, not like pieces were stitched together. Fix anything that feels inconsistent.

6. **Commit** with a clear message describing the synthesis.

## Critical Rules

- **One base, targeted ports.** Don't merge everything from everywhere. Follow the plan: one base with specific elements ported from specific slots.

- **Coherence over completeness.** If porting an element would create inconsistency or conflict, skip it and note why. A clean implementation missing one clever trick is better than Frankenstein code.

- **The spec is the contract.** After synthesis, the result must fully satisfy the original spec. Don't lose requirements during integration.

- **Tests are the safety net.** If tests fail after synthesis, something went wrong. Don't just fix tests to make them pass — understand WHY they fail.

## Report Format

End your work with this exact format:

```
## Synthesizer Report

**Status:** [DONE | DONE_WITH_CONCERNS]

**Base:** Slot N (reason the judge chose it)

**Ported from each donor:**
- From Slot M: [what was ported, which files]
- From Slot K: [what was ported, which files]

**Skipped (if any):**
- [Element]: skipped because [reason — e.g., conflicted with base architecture]

**Test results:**
[Pass/fail count]

**Coherence self-review:**
[Does it read like one person wrote it? Any seams visible?]

**Concerns (if any):**
[Any integration issues, compromises made, areas of uncertainty]
```
