# Task 0: Baseline Observations (RED Phase)

**Date:** 2026-03-25
**Session:** `0de344b8-f133-4935-bef0-9d9ed352c0ee`
**Transcript:** `tests/fixtures/baseline-transcript-0de344b8.jsonl`
**Prompt:** Token bucket rate limiter, 5 parallel implementations
**Skill loaded:** None (baseline — no slot-machine skill)

---

## What the agent did well WITHOUT the skill

| Behavior | Result | Details |
|----------|--------|---------|
| Created parallel worktrees | YES | First tried `isolation: "worktree"` (failed — git wasn't init'd in time), then manually `git worktree add ../throwaway-test-impl{1-5}` |
| Dispatched truly parallel agents | YES | 5 Agent calls in one message, all ran concurrently |
| Each got FULL spec | YES | Full spec + design philosophy hint to each agent |
| Encouraged divergent approaches | YES | 5 distinct approaches: Classic Lock, Dataclass+Slots, Context Manager, Async-compatible, Decorator |
| Considered synthesis | YES | Cherry-picked Impl 3 (Condition-based blocking) + Impl 5 (decorator ergonomics) into combined implementation |
| Found a real bug | YES | Identified Impl 4's dual-lock correctness issue |

## What the agent SKIPPED

| Behavior | Result | Gap |
|----------|--------|-----|
| Structured per-slot review with scorecards | NO | Did a comparison TABLE (lines, tests, blocking, thread-safety, validation, ergonomics) but NOT individual scorecards with weighted scores |
| Independent reviewer agents | NO | Orchestrator read all 5 codebases itself — no dedicated reviewer subagents dispatched |
| Formal judge phase with dedicated agent | NO | Orchestrator compared and decided itself — no judge subagent |
| Formal verdict (PICK/SYNTHESIZE/NONE_ADEQUATE) | NO | Used informal labels: "Best core", "Best ergonomics", "Eliminated" |
| Issue categorization (CRITICAL/IMPORTANT/MINOR) | NO | Found dual-lock bug but didn't categorize severity |
| Dedicated synthesizer agent | NO | Orchestrator wrote the combined code itself rather than dispatching a synthesis specialist |
| Worktree cleanup on first attempt | PARTIAL | Failed without `--force`, had to retry |

## Rationalizations / Shortcuts Observed

No explicit rationalizations (the agent didn't say "I'll skip review" or "this is good enough"). Instead, the agent **defaulted to doing everything itself** — it naturally centralized all evaluation and synthesis in the orchestrator rather than delegating to specialized agents. This is the key baseline failure mode: not resistance to the process, but ignorance that a structured pipeline exists.

Specific shortcuts:
1. **Orchestrator as reviewer:** Read all 5 implementations directly instead of dispatching independent reviewers. This means the "review" was colored by the orchestrator seeing all implementations simultaneously — no blind evaluation.
2. **Orchestrator as judge:** Made the comparison decision inline with no formal reasoning structure. The comparison table was created AFTER reading code, not from independent scorecard data.
3. **Orchestrator as synthesizer:** Wrote the combined implementation itself. While this worked, it means the synthesis wasn't guided by a formal plan from a judge — the orchestrator decided what to combine on the fly.
4. **No self-review by implementers:** Implementers reported what they built but there's no evidence of structured self-review against the spec.

## Skill Gap Analysis

| Baseline Failure | Skill Section That Fixes It | Priority |
|-----------------|---------------------------|----------|
| No structured per-slot review | Reviewer prompt with 6-criteria weighted scorecard | HIGH — this is the #1 quality lever |
| No independent reviewers | Phase 3: dispatch reviewer per slot as Agent calls | HIGH — blind review prevents orchestrator bias |
| No formal judge phase | Judge prompt with PICK/SYNTHESIZE/NONE verdict | HIGH — structured decision beats gut feel |
| No issue categorization | Reviewer prompt: CRITICAL/IMPORTANT/MINOR levels | MEDIUM — helps judge prioritize |
| No dedicated synthesizer | Synthesizer prompt: "one base, targeted ports" | MEDIUM — prevents ad hoc combination |
| No formal verdict | Judge output format with ranking table + reasoning | MEDIUM — makes decision auditable |
| No implementer self-review | Implementer prompt: self-review checklist | LOW — agents did basic reporting already |

## Key Insight

**The parallel dispatch is NOT the skill's main value.** Claude naturally creates worktrees, dispatches parallel agents with different approaches, and even synthesizes. The skill's value is in the REVIEW AND JUDGMENT PIPELINE — structured scorecards, independent reviewers, formal judge, and auditable decisions. Without the skill, the orchestrator centralizes all evaluation in itself, which is fast but lacks the rigor of independent review.
