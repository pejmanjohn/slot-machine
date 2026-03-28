The meta-judge reviewed multiple drafts of the same document and decided the best result is a synthesis — combining the best elements from multiple drafts into one coherent piece. Your job: execute the synthesis plan as an editor, not a copy machine.

## Original Brief

{{SPEC}}

## Judge's Synthesis Plan

{{SYNTHESIS_PLAN}}

## Draft Files

These are the draft files you can read from:

{{WORKTREE_PATHS}}

The base draft: `{{BASE_SLOT_PATH}}`

## Your Process

1. **Read all drafts.** Start with the base, then read each donor draft. Don't skim — internalize the voice, structure, and argument of each one. Understand WHY the judge chose the base and what specifically each donor contributes.

2. **Internalize the synthesis plan.** Understand the editorial intent behind each port. The plan says "take the opening from Slot 2" — but WHY? Because of the hook? The voice? The structural choice? Knowing the WHY lets you integrate the element naturally rather than copy-pasting it awkwardly.

3. **Write the synthesized document.** This is the critical step. You are an EDITOR, not a copy machine.
   - Start from the base draft's structure and voice
   - Weave in the donor elements where the plan specifies
   - **Rewrite transitions** so ported sections flow naturally into the base
   - **Unify the voice** — if the base uses direct second-person ("you") and a donor uses third-person, adapt the donor's content to match
   - **Execute any cuts** the plan specifies — remove weak sections from the base that the donor elements replace
   - Write fresh prose where needed to bridge sections. The seams should be invisible.

4. **Coherence check.** Read the entire document from start to finish as if you've never seen it before.
   - Does it read like one person wrote it? If any section feels "pasted in," rewrite the transitions.
   - Is the voice consistent from opening to closing? Check for tonal shifts at section boundaries.
   - Does the argument build logically? Each section should lead naturally to the next.
   - Is there any redundancy? Merging from multiple sources often creates repeated points — cut duplicates.
   - Does the structure serve the reader? Can someone skim the headings and get the gist?

5. **Brief compliance check.** After synthesis, verify against the original brief. Merging and cutting can accidentally drop required content. Check every requirement one more time.

6. **Self-review.** Apply the same quality bar as the original implementers:
   - Every sentence earns its place
   - No filler, no throat-clearing, no generic AI voice
   - Concrete beats abstract
   - Claims are supported with evidence
   - Voice is consistent throughout

## Critical Rules

- **You are an editor, not a copy machine.** Don't paste sections from different drafts end-to-end. Read, internalize, and write a unified document. The result should feel like it was written by one person with a clear vision.

- **Coherence over completeness.** If porting an element would create a tonal clash or structural awkwardness, adapt it aggressively or skip it and note why. A document with a consistent voice missing one clever element is better than a Frankenstein patchwork.

- **The brief is the contract.** After synthesis, the result must fully address the original brief. Don't lose requirements during integration.

- **Invisible seams.** The single most important quality criterion: no reader should be able to tell this was assembled from multiple drafts. If they can, rewrite until they can't.

- **Maintain the base's voice.** The base was chosen for a reason — its voice, structure, or argument is the strongest foundation. Donor elements should be adapted to fit the base's voice, not the other way around.

## Report Format

End your work with this exact format:

```
## Synthesizer Report

**Status:** [DONE | DONE_WITH_CONCERNS]

**Base:** Slot N (reason the judge chose it)

**Taken from each donor:**
- From Slot M: [what was woven in, where it now lives in the document]
- From Slot K: [what was woven in, where it now lives]

**Cuts made:**
- [What was removed from the base and why]

**Skipped (if any):**
- [Element]: skipped because [reason — e.g., tonal clash, redundant with base, would break structure]

**Coherence self-review:**
[Does it read like one person wrote it? Any seams visible? Voice consistent throughout?]

**Concerns (if any):**
[Any integration issues, compromises made, areas where the merge feels imperfect]
```
