---
date: 2026-03-28
topic: output-formatting
---

# Output Formatting: Structured Reports and Smart Truncation

## What We're Building

Redesign how slot-machine reports progress and final output to the user. Replace the current wall-of-text approach with structured tables for intermediate phases and smart truncation for final output.

## Key Decisions

- **Tables as top-level markdown**: Never indent tables inside code blocks or bullet lists. Tables must be top-level markdown so they render with borders and spacing.
- **`inline code` for visual emphasis**: Use backtick-wrapped inline code for status values (`DONE`, `PASS`, `HIGH`), profile names, slot counts, and key numbers. This is our primary "color" tool — it renders with a highlighted background.
- **Bold for labels and emphasis**: Phase names, section headers, verdicts.
- **Blockquote for the verdict**: The `>` blockquote renders with a left bar, making the verdict visually distinct from the rest of the report.
- **H1 for Final Output header only**: H1 renders as underlined bold italic — the most distinct element. Reserve it for the final output section.
- **No italics**: They de-emphasize rather than emphasize in Claude Code's monospace renderer. Avoid.
- **Agent internals hidden by default**: Implementer self-reviews, reviewer evidence chains, synthesizer process notes are pipeline internals. Suppress from user output. Add `verbose: true` config option for debugging.
- **Standout elements surfaced as bullets**: Key findings from reviews shown as a short bullet list, not buried in scorecard walls.

## Report Template

The orchestrator outputs this structure, filling in actual values:

```
**Slot Machine** — `{profile_name}` profile

Feature: {feature_name}
Slots: `{N}` | Hints: {hint_1}, {hint_2}, {hint_3}

**Phase 1:** Setup — `done`
**Phase 2:** Implementation — `done`

| Slot | Status | Words | Approach |
|------|--------|-------|----------|
| 1 | `DONE` | ~330 | {hint_name} — {one-line summary} |
| 2 | `DONE` | ~327 | {hint_name} — {one-line summary} |
| 3 | `DONE` | ~350 | {hint_name} — {one-line summary} |

**Phase 3:** Review — `done`

| Slot | Compliance | Critical | Important | Minor | Verdict |
|------|------------|----------|-----------|-------|---------|
| 1 | `PASS` | 0 | 0 | 3 | **Contender** |
| 2 | `PASS` | 0 | 0 | 3 | **Contender** |
| 3 | `PASS` | 0 | 0 | 4 | **Contender** |

**Standout elements:**
- Slot 1: {best element from this slot}
- Slot 2: {best element from this slot}
- Slot 3: {best element from this slot}

**Phase 4:** Verdict

> **{PICK/SYNTHESIZE/NONE_ADEQUATE}** — `{confidence}` confidence
>
> **Base:** Slot {N} — {reason}
> **+ Slot {M}:** {what was taken}
> **+ Slot {K}:** {what was taken}
> **Cut:** {what was removed} — {reason}

# Final Output

{see Final Output Display rules below}

---

**Complete** — `{word_count} words` | `{N} slots` | `{verdict}`
```

### Coding Profile Variant

For coding runs, the Phase 2 table replaces Words with Tests:

| Slot | Status | Tests | Approach |
|------|--------|-------|----------|
| 1 | `DONE` | 13 passing | {hint_name} — {summary} |

And the Final Output section shows a file change summary:

```
# Final Output — merged to `{branch}`

| File | Lines | What |
|------|-------|------|
| src/task_queue.py | +142 | TaskQueue class |
| tests/test_task_queue.py | +245 | 45 tests |

`3` files changed, `474` insertions
`45` tests passing
```

### Final Output Display

- **Threshold: 60 lines.** Count lines in the final output.
- **Short output (≤ 60 lines)**: Show full content inline after the `# Final Output` header.
- **Long output (> 60 lines)**: Show first ~20 lines, then: `Full output at {path}`
- **Coding output**: Show file change table (no inline content — code is already in the project).

### Formatting Rules (for SKILL.md)

1. Tables MUST be top-level markdown — never indented or inside code blocks
2. Status values in backticks: `DONE`, `PASS`, `FAIL`, `HIGH`, `MEDIUM`, `LOW`
3. Profile name in backticks: `writing`, `coding`
4. Key numbers in backticks when standalone: `3` slots, `387` words
5. Bold for phase labels and verdicts: **Phase 1:**, **Contender**, **SYNTHESIZE**
6. Blockquote for verdict section only
7. H1 for Final Output header only
8. No italics anywhere
9. Standout elements as plain bullets (not a table)
10. One-line footer with backtick-wrapped stats

### Where This Lives

This is orchestrator behavior — all changes go in SKILL.md:
- Phase 2: Replace the "Report progress" block with the implementation table template
- Phase 3: Add review table template after reviewer dispatch, add standout elements template
- Phase 4: Replace the "Final Report" block with the new structured format including verdict blockquote and final output display logic

No profile changes needed — this is about how the orchestrator presents results, not what the agents produce.

## Next Steps

-> Implement in SKILL.md: rewrite the progress reporting sections and Final Report with the new templates and formatting rules.
