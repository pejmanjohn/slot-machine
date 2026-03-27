---
date: 2026-03-27
topic: task-profiles
status: draft
---

# Task Profiles: Making Slot Machine Domain-Agnostic

## Goal

Make slot-machine extensible to any task type — coding, writing, research, or anything a user defines — while shipping coding and writing as built-in profiles.

## Design Principles

1. **Optimize for agents, not humans.** Profiles are created and edited by agents (via a profile-writer skill). Human readability is a bonus, not a constraint.
2. **One file per profile.** Everything a slot-machine run needs beyond the orchestration engine lives in a single self-contained profile file. Easy to understand, iterate, and share.
3. **Inheritance for variations.** Custom profiles can extend a base profile and override only the parts that differ. Override unit is the markdown section — no partial patching.
4. **SKILL.md is the engine, profiles are the fuel.** The orchestration flow (phases, dispatch, verdicts, cleanup) stays in SKILL.md and is shared across all task types. Profiles contain the task-specific content.

## Architecture

```
SKILL.md                          ← Orchestration engine (shared, task-agnostic)
profiles/
  coding.md                       ← Built-in: code implementation tasks
  writing.md                      ← Built-in: writing/drafting tasks
  my-custom-profile.md            ← User-defined (from scratch or extends a base)
```

### What lives in SKILL.md (shared)

- Phase 1: Validate spec, load profile, gather context, set up isolation, assign hints
- Phase 2: Dispatch N implementers in parallel
- Phase 3: Run pre-checks, dispatch reviewers, dispatch judge
- Phase 4: Handle PICK/SYNTHESIZE/NONE_ADEQUATE, merge/cleanup
- Configuration table (slots, models, etc.)
- Red flags / common mistakes
- Model selection guidance

### What lives in a profile (task-specific)

Everything else:

```markdown
---
name: coding
description: For implementing well-specified features in a codebase
extends: null
isolation: worktree
pre_checks: |
  {test_command} 2>&1
  git diff --name-only HEAD~1
  find src/ tests/ -name "*.py" -exec wc -l {} + 2>/dev/null || true
  python3 -c "import importlib, pathlib; ..." 2>&1 || true
  python3 -m ruff check src/ tests/ 2>/dev/null || true
---

## Approach Hints

1. "Use the simplest possible approach..."
2. "Design for robustness..."
3. "Explore a functional or data-oriented approach..."
4. "Design around a fluent or context-manager API..."
5. "Build for extensibility..."

## Extended Hints

6. "Async-first design..."
7. "Decorator pattern..."
[for N > 5]

## Implementer Prompt

[Complete prompt template for implementer agents, with {{VARIABLES}}]

## Reviewer Prompt

[Complete prompt template for reviewer agents, with {{VARIABLES}}]

## Judge Prompt

[Complete prompt template for judge agent, with {{VARIABLES}}]

## Synthesizer Prompt

[Complete prompt template for synthesizer agent, with {{VARIABLES}}]
```

### Profile inheritance

A custom profile can extend a base and override specific sections:

```markdown
---
name: security-focused-coding
description: Coding with security-hardened approach hints and review criteria
extends: coding
---

## Approach Hints

1. "Defensive coding — assume all input is hostile..."
2. "Minimize attack surface — least privilege, no unnecessary dependencies..."
3. "Cryptographic correctness — use established libraries, no custom crypto..."
4. "Audit trail — structured logging for all security-relevant operations..."
5. "Fail closed — deny by default, explicit allow..."

## Reviewer Prompt

[Complete reviewer prompt with security-focused evaluation criteria]
```

**Rules:**
- `extends: coding` means start with everything from `coding.md`
- Any section present in the custom file fully replaces the base version
- Any section NOT present is inherited from the base
- Frontmatter fields (isolation, pre_checks) are also inherited unless overridden
- Maximum one level of inheritance (no chains). If you need more, you're building a new profile.

### What the writing profile looks like

```markdown
---
name: writing
description: For drafting documents, READMEs, blog posts, announcements, or any prose
extends: null
isolation: file
pre_checks: null
---

## Approach Hints

1. "Write the shortest version that fully communicates the value. Every sentence must earn its place..."
2. "Open with the problem. Build tension, then reveal the solution. Structure as a story..."
3. "Lead with a concrete example. Let the demo do the talking. Minimize explanation..."
4. "Write for the reader who wants to understand HOW it works before deciding to use it..."
5. "Open with a bold, specific claim — then immediately prove it..."

## Implementer Prompt

[Writing-specific: "You are drafting a document..." instead of "You are implementing a feature..."]
[No test commands, no git worktree references]
[Self-review focused on clarity, accuracy, voice instead of code quality]

## Reviewer Prompt

[Writing-specific 4-pass structure:]
[Pass 1: Brief Compliance — did it cover what was asked?]
[Pass 2: Accuracy — is the information factually correct?]
[Pass 3: Evidence Assessment — does it prove its claims?]
[Pass 4: Strengths — what's worth keeping for synthesis?]

## Judge Prompt

[Mostly the same as coding — verdicts, ranking, convergence all work as-is]
[Evaluation criteria adjusted for prose quality]

## Synthesizer Prompt

[Editorial merge strategy instead of git merge]
["Take the intro from slot 2, the argument structure from slot 4"]
[Coherence check: does it read like one person wrote it?]
```

## Profile Selection

One command, smart default, easy override. Selection logic in order:

1. **Explicit override** — user says `slot-machine this --profile security` or `slot-machine this with profile: writing` → use that profile, no detection
2. **Project default** — `CLAUDE.md` or `AGENTS.md` sets `slot-machine-profile: writing` → use it
3. **Auto-detect from spec** — analyze the spec for signals:
   - **Coding signals:** implement, build, create a module, add a feature, fix, refactor; references to tests, APIs, functions, classes, endpoints
   - **Writing signals:** write, draft, compose, describe, announce; references to audience, tone, structure, sections, word count
   - If confident (strong signals for one profile) → use it silently
4. **Ask when not confident** — if signals are mixed or absent, ask one question: "Should I run this as **coding** (worktrees, tests, code review) or **writing** (parallel drafts, prose review)? Or specify a profile name."

For custom profiles, detection is always explicit (step 1) or project-configured (step 2). Auto-detection only chooses between the built-in profiles.

The ask is cheap (one question, one time). Guessing wrong is expensive (5 slots of compute in the wrong mode).

## Profile Discovery

Profiles are found in this order (first match wins):

1. Inline override: user specifies `profile: my-custom` in the command
2. Project config: `CLAUDE.md` or `AGENTS.md` sets a default profile
3. Local profiles: `./profiles/` directory in the project
4. Skill profiles: `profiles/` directory in the slot-machine skill installation
5. Fallback: `coding` profile

## Profile Writer Skill

A companion skill (`/slot-machine-profile` or similar) that helps create custom profiles:

1. Asks what kind of task (or starts from a base profile)
2. Asks about evaluation criteria — what makes a good result?
3. Asks about diversity — what dimensions should vary across slots?
4. Generates the profile file
5. Optionally validates it (checks required sections exist, variables are defined)

This is how most users will create profiles — not by hand-editing markdown.

## Migration Path

### What changes in SKILL.md

- Phase 1 adds: load profile, resolve inheritance
- Phase 2 changes: read implementer prompt from profile instead of `slot-implementer-prompt.md`
- Phase 3 changes: read reviewer/judge prompts from profile, run profile-defined pre-checks
- Phase 4 changes: read synthesizer prompt from profile
- Isolation strategy comes from profile (worktree vs. file)
- Approach hints come from profile
- Remove hardcoded Python-specific pre-checks
- Remove hardcoded approach hints (they move to `coding.md`)

### What happens to existing prompt template files

The four `slot-*-prompt.md` files in the repo root become the content of the `coding.md` profile. They're migrated, not deleted — the content is preserved, just reorganized.

### Backwards compatibility

- If no profile is specified and the project looks like a coding project, use `coding.md` — identical behavior to today
- The configuration table in SKILL.md stays the same (slots, models, etc.)
- Trigger phrases stay the same

## Open Questions

1. **Profile selection** — auto-detect vs. explicit vs. smart default (see above)
2. **Variable contract** — RESOLVED. SKILL.md passes a fixed set of universal variables to every profile: SPEC, APPROACH_HINT, PROJECT_CONTEXT, SLOT_NUMBER, PRE_CHECK_RESULTS, IMPLEMENTER_REPORT, WORKTREE_PATH, ALL_SCORECARDS, SYNTHESIS_PLAN, BASE_SLOT_PATH. Profile-specific variables (TEST_COMMAND, REFERENCE_EXAMPLES, etc.) are the profile's own responsibility — gathered and used within the profile's prompts, invisible to the orchestrator.
3. **Testing** — RESOLVED. Test runner discovers all profiles in `profiles/` and validates each one: required sections exist, required frontmatter exists, universal variables are from the known set, status/verdict values are consistent with SKILL.md, at least 5 approach hints. For inherited profiles, resolve the inheritance first, then validate the merged result. Check that `extends` targets exist and no circular/multi-level chains. Same assertions as today, just iterated over discovered profiles instead of hardcoded filenames.
4. **Profile versioning** — if a base profile changes, do extending profiles need updating? With section-level inheritance, adding a new section to the base is safe (it's inherited). Changing an existing section that's been overridden has no effect. Changing a section that's inherited propagates automatically. This seems fine.
