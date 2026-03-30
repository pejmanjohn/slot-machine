# Contributing to Slot Machine

## Quick Start

1. Fork the repo
2. Make your changes
3. Run `./tests/run-tests.sh` (must pass)
4. Submit a PR

## Packaging Targets

- `.claude-plugin/` and `.codex-plugin/` are first-class packaging/discovery targets. Keep their metadata aligned with actual repo behavior.
- `skills/slot-machine/SKILL.md` must remain a symlink to the repo-root `SKILL.md` (`../../SKILL.md`), not a copied file.

## Testing Requirements

All PRs must pass the fast validation suite:

```bash
./tests/run-tests.sh
```

The fast suite currently verifies contracts, skill structure, and harness integrity.

If your change touches profiles (`profiles/*/`), SKILL.md workflow logic, or end-to-end orchestration behavior and you have the required environment available, also run:

```bash
./tests/run-tests.sh --smoke
./tests/run-tests.sh --integration
```

Today, the implementer, reviewer, and judge smoke tests plus the happy-path E2E test execute real headless `claude -p` assertions. `test-e2e-edge-cases.sh` and `test-reviewer-accuracy.sh` still skip explicitly, and these higher tiers do not constitute separate dual-host smoke/integration coverage for Codex.

## What the Tests Check

- **Contracts** — Variable references in prompts match SKILL.md definitions, status/verdict values are consistent across files, required sections exist
- **Structure** — Required packaging files exist, including the Codex skill symlink
- **Harness integrity** — The runner and placeholder/skip behavior match the documented contract
- **Smoke** — Real implementer/reviewer/judge headless Claude-harness checks
- **Benchmark** — Speed tests comparing slot-machine vs baseline single-agent runs
- **E2E** — Real happy-path headless Claude-harness coverage plus explicit skips for the still-unwired edge-case path

## Guidelines

- Keep SKILL.md's frontmatter `description` focused on trigger conditions only
- Every `{{VARIABLE}}` in a prompt template must appear in SKILL.md
- Don't change status/verdict string values without updating all files that reference them

## Creating Custom Profiles

To create a custom profile, either:
- Create a new folder in `profiles/` (e.g., `profiles/my-profile/`) with `0-profile.md` + 4 prompt files (`1-implementer.md`, `2-reviewer.md`, `3-judge.md`, `4-synthesizer.md`). Use `profiles/coding/` or `profiles/writing/` as a template.
- Create a profile that extends an existing one with `extends: coding` in the `0-profile.md` frontmatter. Only include files you want to override — missing files are inherited from the base.

Run `./tests/run-tests.sh` to validate your profile has all required files and consistent contracts.

For personal or community profiles that aren't part of this repo, place them in `~/.slot-machine/profiles/` instead. They'll be discovered automatically between project-local and built-in profiles.
