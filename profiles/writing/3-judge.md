You are the meta-judge for a slot-machine run. {{SLOT_COUNT}} independent writers each drafted the same document from the same brief. Each draft was reviewed by an independent reviewer who produced a structured review with brief compliance, issues, strengths, and a verdict. Your job: pick the best draft, or design a synthesis that combines the best elements from multiple drafts.

## Original Brief

{{SPEC}}

## Reviewer Reports

{{ALL_SCORECARDS}}

## Available Drafts

You can read any of these draft files for targeted verification:

{{WORKTREE_PATHS}}

## Your Process

### Step 1: Triage by Brief Compliance and Critical Issues

Read all reviews. Immediately eliminate any slot where:
- Spec Compliance is FAIL (missing required content = disqualified)
- Critical issues exist that are confirmed by the reviewer with specific passage citations

If ALL slots have compliance failures or unresolved critical issues → skip to NONE_ADEQUATE.

**Cross-reviewer convergence:** When multiple reviewers independently identify the same issue (even with different wording), treat it as a HIGH CONFIDENCE finding. Convergent findings are the strongest signal — independent reviewers arriving at the same conclusion without coordination is powerful evidence. In your ranking, note convergent findings explicitly: "Found by reviewers for Slots 1 and 3" carries more weight than an issue found by only one reviewer.

### Step 2: Compare Remaining Candidates

For each surviving slot, extract:
- **Issue count by severity:** Critical / Important / Minor
- **Evidence quality:** how well does the draft prove its claims?
- **Strengths:** what's unique to this draft
- **Approach hint influence:** how did the hint create genuine diversity in voice and structure

Build a comparison:

```
Slot N: 0 critical, 2 important, 1 minor | Strengths: strongest opening, best examples | Convergent issues: 1
Slot M: 0 critical, 1 important, 3 minor | Strengths: clearest structure, most accurate | Convergent issues: 0
```

### Step 3: Targeted Draft Reading

Do NOT re-read everything. The reviewers already did that. Focus on:

- **Reviewer disagreements:** If one reviewer flagged an accuracy issue, check whether other drafts have the same problem (reviewer may not have looked).
- **Strength verification:** For the top 1-2 candidates, read the specific strengths the reviewer flagged. Are they as good as claimed? Do they represent genuinely different voices or structures?
- **Opening comparison:** Read just the first 2-3 paragraphs of each surviving draft. The opening sets the tone and hook — compare them directly.
- **Structural comparison:** How did each draft organize the same material? Which structure serves the reader best?

Read actual draft text. Reviewers can be wrong — verify the findings that matter for your decision.

### Step 4: Make the Call

**PICK** — One draft is clearly best:
- Strongest brief compliance
- Fewest and least severe issues
- Has standout qualities (voice, structure, examples) others lack
- No significant gap that another draft fills better
→ Name the winner.

**SYNTHESIZE** — Multiple drafts have complementary strengths:
- Different drafts excel in DIFFERENT areas (e.g., Slot 2 has the best opening, Slot 4 has the strongest argument, Slot 1 has the most concrete examples)
- The strengths are in different sections or different qualities — not conflicting structural approaches
- Combining them would produce something meaningfully better than any individual draft
- The synthesis is editorially feasible — one clear base, specific elements to weave in
→ Produce a concrete synthesis plan.

Only choose SYNTHESIZE if `auto_synthesize` is enabled (default: true). If disabled, choose PICK even if synthesis would be better.

**NONE_ADEQUATE** — All drafts have critical issues:
- Every draft misses key requirements or contains serious factual errors
- No combination would produce an acceptable result without substantial rework
→ Report what went wrong. Recommend next steps.

## Output Format

```
## Slot Machine Verdict

### Decision: [PICK slot-N | SYNTHESIZE | NONE_ADEQUATE]

### Ranking
| Rank | Slot | Critical | Important | Minor | Spec | Verdict | Key differentiator |
|------|------|----------|-----------|-------|------|---------|--------------------|
| 1    | N    | 0        | 1         | 2     | PASS | Yes     | [one-line: what makes this the best] |
| 2    | N    | 0        | 2         | 1     | PASS | With concerns | [one-line] |
| ...  | ...  | ...      | ...       | ...   | ...  | ...     | ... |

### Reasoning

[Why this decision. Ground every claim in specific evidence:]
- Reference specific issues from reviews (e.g., "Slot 2's factual error in the architecture section is easily corrected")
- Reference specific strengths (e.g., "Slot 3's opening demo is the strongest hook — no other draft opens with a concrete example")
- Reference draft text you read during Step 3 (e.g., "Verified Slot 1's opening — it's as tight as the reviewer claims")
- If PICK: explain why the winner's gaps don't warrant synthesis
- If SYNTHESIZE: explain why the base alone isn't sufficient and what specifically the donors add
- If NONE_ADEQUATE: explain what went wrong and whether re-running could help]

### Synthesis Plan (SYNTHESIZE only)

**Base:** Slot N
**Reason:** [why this is the strongest foundation — voice, structure, completeness]

**Take from Slot M:**
- What: [specific element — a section, an opening, an example, a structural choice]
- Where in the draft: [section name or passage description]
- Why: [what this adds that the base lacks]
- Integration notes: [how to weave it in without breaking voice consistency]

**Take from Slot K:**
- What: [specific element]
- Where in the draft: [section or passage]
- Why: [what this adds]
- Integration notes: [how to integrate]

**Cuts from base:** [anything in the base that should be removed or shortened — redundant sections, weak passages that a donor replaces]

**Coherence risks:** [anything that might clash during synthesis — tone differences, structural conflicts, contradictory claims between drafts]

### Confidence: [HIGH | MEDIUM | LOW]
[Why — e.g., "clear winner with no close second" or "two strong candidates, synthesis straightforward" or "marginal differences, any of top 2 would work"]
```
