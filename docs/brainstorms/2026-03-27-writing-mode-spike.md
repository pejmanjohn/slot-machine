---
date: 2026-03-27
topic: writing-mode-spike
---

# Writing Mode Spike: Can Slot Machine Work for Non-Coding Tasks?

## What We Were Testing

Whether the slot-machine approach (N parallel attempts → independent review → judge → synthesize) produces meaningfully better results for **writing tasks** compared to a single attempt.

## Experiment Design

**Task:** Write a README.md for the slot-machine project itself.

**Setup:**
- Deleted the existing README on a feature branch so agents couldn't cheat
- Agents could read the full codebase (SKILL.md, prompt templates, CLAUDE.md, CONTRIBUTING.md)
- Provided 3 reference READMEs as style examples (gstack, superpowers, compound-engineering)
- 5 slots, each with a different writing-specific approach hint

**Approach Hints (writing-adapted):**
1. **Minimalist** — shortest possible, every word earns its place
2. **Narrative / Problem-First** — open with the problem, build tension, reveal the solution
3. **Show Don't Tell** — lead with a concrete demo, minimize explanation
4. **Technical Architecture** — lead with system design, explain the mechanism
5. **Bold Claim / Proof** — open with a specific claim, immediately back it up

**Evaluation:** Blind A/B testing with 10 agents, position-controlled (5 saw draft A first, 5 saw draft B first).

## Key Findings

### 1. Approach hints produce real diversity for writing

The 5 drafts were structurally very different — not word-level variation but genuinely different organizational strategies, voice, and emphasis. The hints worked as well for prose as they do for code architecture.

| Slot | Length | Opens With | Distinctive Element |
|------|--------|-----------|-------------------|
| 1 (Minimalist) | 107 lines | One-liner + differentiator | Tightest prose, "One attempt is a sample" tagline |
| 2 (Narrative) | 195 lines | "The Problem With Your First Draft" | Story arc, "running a tournament" metaphor |
| 3 (Show Don't Tell) | 200 lines | Full terminal session | Best opening demo, ASCII phase diagram |
| 4 (Technical) | 265 lines | Phase diagram + mechanism | Deepest architecture explanation |
| 5 (Bold Claim) | 214 lines | "The first implementation is not usually the best one" | Scorecard examples, judge ranking table |

### 2. Judge and synthesizer work for prose

The judge (Opus) produced a coherent synthesis plan:
- **Base:** Slot 5 (strongest hook, best proof artifacts, strongest voice)
- **From Slot 3:** Opening terminal demo, agent pipeline table
- **From Slot 2:** "Does this problem have a design space worth exploring?" closing line
- **From Slot 1:** "One attempt is a sample. Five attempts is a distribution." tagline
- **Cuts:** Redundant sections from Slot 5

The synthesizer executed the plan and produced a 190-line draft that reads as one voice throughout. The ported elements integrated naturally — no visible seams.

### 3. Blind evaluation results

**Synthesis vs. First Draft (single-shot, no human editing):**
- **Synthesis wins 10-0** (no position bias)
- Average scores: Synthesis 8.9 vs First Draft 6.2
- Consistent reasoning: synthesis won on hook, proof, voice, and persuasion
- First draft called "competent boilerplate," "a spec sheet with no conviction"

**Synthesis vs. Final README (multiple rounds of human editing):**
- **Original wins 10-0** (no position bias)
- Average scores: Original 8.3 vs Synthesis 7.0
- Consistent reasoning: original had richer proof (comparison table, detailed reviewer findings, "Works With Your Other Skills" section)
- Synthesis had better hook but less evidence density

### 4. The gap is identifiable

The synthesis lost to the human-edited version for specific, fixable reasons:
- Judge was too aggressive cutting proof sections (dropped the "Without vs With" comparison table)
- Dropped the "Works With Your Other Skills" section (addresses "how does this fit my workflow?")
- Dropped the "This is NOT Standard Parallel Agents" explicit distinction
- Less evidence density overall

These aren't fundamental limitations — they're judgment calls in the synthesis plan that could be improved with better evaluation criteria for writing.

### 5. Grafting human edits onto synthesis produces the best result

We identified exactly what the human editing passes added (comparison table, "Works With Your Other Skills," detailed reviewer finding, "This is NOT Standard Parallel Agents," etc.) and grafted those same additions onto the synthesis. This tests the real question: **does slot-machine produce a better foundation for human editing?**

**Grafted (slot-machine + human edits) vs. Final README (single-shot + human edits):**
- **Grafted wins 10-0** (no position bias)
- Average scores: Grafted 8.5 vs Original 7.4
- Consistent reasoning: grafted version had sharper hook, more credible proof (showing a failed slot felt more authentic), and tighter structure

The three slot-machine advantages that survived human editing:
1. **Slot 1's tagline** ("One attempt is a sample. Five attempts is a distribution.") beat the original's "coin flip" metaphor every time
2. **Slot 3's demo** (showing a failed slot) felt more honest/authentic than the original's clean run
3. **The synthesis's structural flow** (hook → demo → problem → proof → when to use) was consistently preferred

These are exactly the improvements that come from having 5 diverse starting points. No single attempt would have produced Slot 1's tagline AND Slot 3's demo AND Slot 5's voice.

## Full Results Summary

| Comparison | What it tests | Winner | Score |
|-----------|---------------|--------|-------|
| Synthesis vs First Draft | Slot-machine vs single-shot (no editing) | **Synthesis 10-0** | 8.9 vs 6.2 |
| Synthesis vs Final README | Slot-machine vs single-shot + human edits | Original 10-0 | 7.0 vs 8.3 |
| Grafted vs Final README | Slot-machine + human edits vs single-shot + human edits | **Grafted 10-0** | 8.5 vs 7.4 |

**Bottom line:** Slot-machine produces a better foundation. Human editing makes both versions better, but the slot-machine foundation retains its structural and voice advantages through the editing process.

## What This Validates

1. **Writing works with slot-machine.** The core mechanism (diverse attempts → independent evaluation → judge → synthesize) transfers from code to prose.
2. **Single automated pass beats single-shot by ~2.5 points.** Significant quality improvement without human iteration.
3. **Slot-machine + human edits beats single-shot + human edits.** The foundation matters. When the same edits are applied, the slot-machine version wins unanimously (+1.1 points).
4. **Human iteration still adds value on top of slot-machine.** But the starting point determines the ceiling.
5. **The approach hints are the key mechanism.** They produced genuinely different structures and voices, not just word-level variation.
6. **Synthesis is coherent for prose.** The synthesizer combined elements from 4 different drafts into something that reads like one person wrote it.

## What Needs Work for Writing Mode

### Evaluation criteria
Code has tests as an objective quality signal. Writing evaluation is inherently more subjective. The reviewer's 4-pass structure needs adaptation:
- Pass 1 (Spec Compliance) → **Brief Compliance** (did it cover what was asked?)
- Pass 2 (Correctness) → **Accuracy** (is information factually correct?)
- Pass 3 (Test Assessment) → **Evidence Assessment** (does it prove its claims?)
- Pass 4 (Strengths) → same, works as-is

### Synthesis strategy
Code synthesis = git operations (copy files from worktrees). Prose synthesis = editorial operations (take the intro from slot 2, the argument structure from slot 4). The synthesizer prompt needs a writing-specific mode.

### Pre-checks
Code pre-checks: tests, linter, imports. Writing pre-checks could be: word count, structure analysis (has intro/conclusion), readability metrics. Or skip entirely — the reviewer can handle it.

### Isolation
Git worktrees are overkill for writing. Each slot just writes to a separate file. No git machinery needed.

## Recommended Next Steps

1. **Throw away this branch.** The spike validated the concept but was implemented ad-hoc.
2. **Build the generalized extensible approach.** Task profiles that make the coding-specific parts pluggable:
   - Isolation strategy (worktree vs. file)
   - Pre-checks (tests vs. word count vs. none)
   - Approach hints (architecture vs. writing style vs. custom)
   - Evaluation criteria (code quality vs. prose quality vs. custom)
   - Synthesis strategy (code merge vs. prose merge)
3. **Ship coding as the default profile.** Everything works as-is.
4. **Ship writing as a built-in profile.** Based on what we learned here.
5. **Allow custom profiles** via CLAUDE.md config for other use cases (research, analysis, etc.).

## Artifacts

All spike files are on the `feat/writing-mode` branch:
- `spike/writing-brief.md` — the writing spec/brief
- `spike/approach-hints.md` — the 5 writing-specific approach hints
- `spike/references/` — the 3 reference READMEs used as examples
- `spike/slot-{1-5}-draft.md` — the 5 independent drafts
- `spike/synthesis-draft.md` — the synthesized README (5 drafts → judge → synthesize)
- `spike/synthesis-plus-human-edits.md` — synthesis with human edits grafted on (the best version)
