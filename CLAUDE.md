# Slot Machine Development

You are working on the slot-machine skill — a Claude Code skill for best-of-N parallel implementation.

## Structure
- `SKILL.md` — Orchestration engine (shared across all task types)
- `profiles/` — Task-specific profiles (one folder per profile)
  - `coding/` — Built-in: code implementation tasks
    - `0-profile.md` — Config: frontmatter + approach hints
    - `1-implementer.md`, `2-reviewer.md`, `3-judge.md`, `4-synthesizer.md` — Agent prompts
  - `writing/` — Built-in: writing/drafting tasks
    - Same structure as coding, adapted for prose
- `tests/` — Tiered test suite
  - `tests/benchmark/` — Speed and variability benchmarks
- `docs/` — Plans, notes, brainstorms, E2E test results
- `marketplace.json`, `plugin.json` — Plugin distribution metadata (root level)

## Key Rules
- SKILL.md description must ONLY describe when to trigger, never the workflow
- All {{VARIABLES}} in profile prompts must be from the universal variable set in SKILL.md
- Status/verdict values must match across SKILL.md and all profiles
- Run `./tests/run-tests.sh` before committing

## Testing
- `./tests/run-tests.sh` — Fast contract validation (always run this)
- `./tests/run-tests.sh --smoke` — Phase-level tests
- `./tests/run-tests.sh --benchmark` — Speed benchmarks
- `./tests/run-tests.sh --all` — Full suite including E2E
