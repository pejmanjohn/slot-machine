# Slot Machine Development

You are working on the slot-machine skill/plugin repo for best-of-N parallel implementation across Claude Code and Codex.

## Structure
- `SKILL.md` — Host-agnostic orchestration engine (shared across task types)
- `.claude-plugin/` — Claude packaging and marketplace metadata
- `.codex-plugin/` — Codex plugin metadata
- `skills/slot-machine/SKILL.md` — Must stay a symlink to `../../SKILL.md` for Codex discovery
- `profiles/` — Task-specific profiles (one folder per profile)
  - `coding/` — Built-in: code implementation tasks
    - `0-profile.md` — Config: frontmatter + approach hints
    - `1-implementer.md`, `2-reviewer.md`, `3-judge.md`, `4-synthesizer.md` — Agent prompts
  - `writing/` — Built-in: writing/drafting tasks
    - Same structure as coding, adapted for prose
- `tests/` — Tiered test suite
  - `tests/benchmark/` — Speed and variability benchmarks
- `docs/` — Plans, notes, brainstorms, E2E test results

## Key Rules
- SKILL.md description must ONLY describe when to trigger, never the workflow
- All {{VARIABLES}} in profile prompts must be from the universal variable set in SKILL.md
- Status/verdict values must match across SKILL.md and all profiles
- Treat Claude and Codex packaging as first-class; if discovery changes, update both packaging docs/metadata paths together
- Project config may live in `AGENTS.md` or `CLAUDE.md`
- Describe harness routing host-relatively: native path on the active host, shell-out only for the other harness
- Run `./tests/run-tests.sh` before committing

## Testing
- `./tests/run-tests.sh` — Fast suite: contracts, skill structure, harness integrity
- `./tests/run-tests.sh --smoke` — Current real implementer/reviewer/judge smoke tests via headless `claude -p`
- `./tests/run-tests.sh --integration` — Adds the current real happy-path E2E via headless `claude -p`
- `./tests/run-tests.sh --benchmark` — Speed benchmarks
- `./tests/run-tests.sh --all` — Full suite, with edge-case E2E and reviewer-accuracy still skipping explicitly
