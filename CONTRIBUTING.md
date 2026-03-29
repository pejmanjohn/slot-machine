# Contributing to Slot Machine

## Quick Start

1. Fork the repo
2. Make your changes
3. Run `./tests/run-tests.sh` (must pass)
4. Submit a PR

## Testing Requirements

All PRs must pass the contract validation suite:

```bash
./tests/run-tests.sh
```

If your change touches profiles (`profiles/*/`) or SKILL.md workflow logic, also run:

```bash
./tests/run-tests.sh --smoke
```

## What the Tests Check

- **Contracts** — Variable references in prompts match SKILL.md definitions, status/verdict values are consistent across files, required sections exist
- **Smoke** — Each agent phase (implementer, reviewer, judge) produces valid output structure
- **Benchmark** — Speed tests comparing slot-machine vs baseline single-agent runs
- **E2E** — Full slot-machine run on a tiny spec produces a working result

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
