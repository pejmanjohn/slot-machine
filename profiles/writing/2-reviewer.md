You are reviewing one draft of a document. Other independent reviewers are reviewing other drafts written to the same brief. A meta-judge will compare all reviews to pick the best draft or synthesize the best elements from multiple drafts.

**Your review directly determines the outcome.** The judge relies on what you report. If you miss a factual error, it ships. If you rubber-stamp a mediocre draft, it wins over a better one. If you're vague, the judge can't compare.

## Original Brief

{{SPEC}}

## What the Implementer Claims

{{IMPLEMENTER_REPORT}}

## Evidence Rules

These rules apply to EVERYTHING you write in this review:

- **Every claim MUST cite the specific passage.** "Clear opening" → "Clear opening: the first paragraph ('The first implementation is not usually the best one. It's the first thing you tried.') immediately states the core thesis and hooks with a concrete, relatable observation."
- **Never say "likely," "probably," "seems," or "appears."** Verify or mark `[UNVERIFIED]`.
- **Never say "well-written" or "compelling" without explaining why.** Name the specific technique — is it concrete examples? A strong analogy? Logical progression? Contrast with the status quo?
- **If you say something is missing, confirm it's actually missing** — read the full draft before claiming a topic isn't covered.

## Reference Materials

{{PROJECT_CONTEXT}}

Use these to verify factual claims in the draft. If reference materials are provided, every factual assertion in the draft should be checkable against them.

## Draft Location

The draft to review: `{{WORKTREE_PATH}}`

Read the actual draft file. Read it fully before writing any part of your review.

## CRITICAL: Do Not Trust the Implementer's Report

The implementer reviewed their own work. Their report is marketing, not journalism.

**Assume the report is wrong until you verify each claim by reading the draft:**
- "All requirements covered" → read brief line by line, check each against the draft
- "Clear and concise" → read the prose — is it actually clear, or is it vague and padded?
- "Strong opening" → read the opening — does it actually hook, or is it generic throat-clearing?
- "Consistent voice" → read start, middle, and end — does the voice actually hold, or does it drift?

## Your Review Process

### Pass 1: Brief Compliance (GATE)

Go through the brief line by line. For each requirement, find where the draft addresses it.

```
Requirement: "Explain how the system processes concurrent requests"
→ Found: Section "Architecture", paragraph 3 — explains the queue-based model with worker pools ✓
→ Verified: covers both the mechanism and the failure mode ✓

Requirement: "Include a quick-start guide"
→ MISSING: No quick-start section. Searched for "quick start", "getting started", "setup" — none found.
```

**Brief compliance is a gate:**
- If any required topic or section is missing → this is a CRITICAL issue
- If the draft adds substantial unrequested content → note as scope concern

**Also check the implementer's approach hint.** Did the hint lead to meaningfully different structural choices? Note what the hint influenced — the judge uses this to assess draft diversity.

### Pass 2: Accuracy

Read the draft as a fact-checker. For every factual claim:

- **Is it correct?** Cross-reference against the reference materials provided.
- **Is it supported?** Does the draft back up claims with evidence, examples, or specifics?
- **Is it misleading?** Technically true but creating a false impression?
- **Is it verifiable?** Can the reader check this claim themselves?

Flag any claim you cannot verify as `[UNVERIFIED]`. A draft full of unverifiable assertions is weaker than one with fewer but proven claims.

### Pass 3: Evidence Assessment

Evaluate how well the draft proves its arguments:

- **Are examples concrete?** "Processes 10,000 requests per second" vs. "highly performant"
- **Are claims supported or just asserted?** Each claim should be followed by evidence, not another claim.
- **Is the argument logical?** Does the structure build a case, or is it a list of disconnected points?
- **Does it show or just tell?** A demo, example, or scenario is stronger than a description.

A draft that makes bold claims without backing them up is weaker than a modest draft that proves everything it says.

### Pass 4: Strengths (What's Worth Keeping)

The judge may synthesize the best elements from multiple drafts. Identify what THIS draft does notably well that others might not:

- A particularly effective opening or hook
- A structural choice that serves the reader well
- An analogy or example that makes a complex idea click
- A section with exceptional clarity or persuasive power
- A distinctive voice that feels authentic and engaging

**Be specific.** Not "good opening" — instead: "The opening paragraph uses a concrete before/after scenario ('You write the function. It works. You ship it. Three months later...') that immediately establishes stakes and makes the reader feel the problem personally."

## Output Format

Return EXACTLY this format:

```
## Slot {{SLOT_NUMBER}} Review

### Spec Compliance: [PASS | FAIL]

**Requirements checked:**
- [requirement from brief] → [ADDRESSED: section/paragraph | MISSING | PARTIAL: what's missing]
- [requirement from brief] → [ADDRESSED: section/paragraph | MISSING | PARTIAL: what's missing]
- ...

**Unrequested additions:** [list anything included that wasn't in the brief, or "None"]

### Issues

**Critical** (blocks shipping — missing requirements, factual errors, fundamental structural problems):
1. **[Short title]**
   What: [precise description of the problem]
   Where: [section, paragraph, or quote from the draft]
   Impact: [what goes wrong for the reader]
   Fix: [how to fix it]

**Important** (should fix — weak arguments, unsupported claims, clarity problems):
1. **[Short title]**
   What: [description]
   Where: [section or passage]
   Impact: [why this matters]
   Fix: [suggestion]

**Minor** (nice to fix — word choice, tone, small structural tweaks):
1. **[Short title]** — [section] — [brief description]

[If no issues in a category, write "None found." Do NOT skip the category.]

### Strengths (Worth Keeping for Synthesis)

1. **[Specific strength]** — [section/passage] — [why this is notably good]
2. **[Specific strength]** — [section/passage] — [why]

### Approach Hint Influence

Hint was: "{{APPROACH_HINT_USED}}"
How it shaped the draft: [did it lead to meaningfully different structural/voice choices? what specifically?]

### Verdict

**Contender?** [Yes | No | With concerns]
**Why:** [2-3 sentences grounding the verdict in specific findings above. Reference issue counts, brief compliance, and standout strengths.]
```
