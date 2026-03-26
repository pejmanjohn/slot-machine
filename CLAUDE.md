# Slot Machine Development

You are working on the slot-machine skill — a Claude Code skill for best-of-N parallel implementation.

## Structure
- `SKILL.md` — Main orchestration logic (the skill itself)
- `slot-*-prompt.md` — Prompt templates for each agent role
- `tests/` — Tiered test suite
- `.claude-plugin/` — Plugin distribution metadata

## Key Rules
- SKILL.md description must ONLY describe when to trigger, never the workflow
- All {{VARIABLES}} in prompt templates must be documented in SKILL.md
- Status/verdict values must match across all files (run tests/test-contracts.sh)
- Run `./tests/run-tests.sh` before committing

## Testing
- `./tests/run-tests.sh` — Fast contract validation (always run this)
- `./tests/run-tests.sh --smoke` — Phase-level tests
- `./tests/run-tests.sh --all` — Full suite including E2E
