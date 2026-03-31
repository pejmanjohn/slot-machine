# Contributing to Slot Machine

## Quick Start

1. Fork the repo
2. Make your changes
3. Run `./tests/run-tests.sh` (must pass)
4. Submit a PR

## Packaging Targets

- `.claude-plugin/` and `.codex-plugin/` are first-class packaging/discovery targets. Keep their metadata aligned with actual repo behavior.
- `skills/slot-machine/SKILL.md` must stay byte-for-byte in sync with the repo-root `SKILL.md`. It is a real file because Codex discovery rejected the symlinked form in local testing.
- `scripts/build-codex-runtime-skill.sh` is the source-repo -> runtime-bundle step for Codex. It should keep producing a plain standalone skill directory with a real `SKILL.md`, linked `profiles/`, linked `tests/`, and no `.codex-plugin` metadata.
- `scripts/install-codex-skill.sh` and `scripts/update-codex-skill.sh` are the supported Codex local install/update flow. They should keep the stable `~/.agents/skills/slot-machine` link pointed at the generated runtime bundle.
- `scripts/install-codex-standalone-skill.sh` remains a compatibility wrapper for arbitrary-destination bundle generation.

PRs should be opened as ready for review by default. Use draft only when there is an explicit reason or the user asks for it.

## Branch Naming

Use branch type prefixes so the purpose of a branch is obvious at a glance:

- `feat/<short-kebab-name>` for new functionality
- `fix/<short-kebab-name>` for bug fixes
- `docs/<short-kebab-name>` for documentation-only changes
- `style/<short-kebab-name>` for formatting or non-behavioral cleanup

Examples:

- `docs/readme-anthropic-footnote`
- `fix/reviewer-scorecard-parser`
- `feat/writing-profile-inheritance`

## Testing Requirements

All PRs must pass the fast validation suite:

```bash
./tests/run-tests.sh
```

The fast suite currently verifies contracts, skill structure, and harness integrity.

For normal development, prefer the smaller runner options before reaching for the full smoke or integration tiers:

```bash
./tests/run-tests.sh --changed        # Tier 1 + change-matched heavier checks
./tests/run-tests.sh --host claude    # Restrict headless tests to one host
./tests/run-tests.sh --jobs auto      # Parallelize independent tests
./tests/run-tests.sh --test test-implementer-smoke.sh
```

If your change touches profiles (`profiles/*/`), SKILL.md workflow logic, or end-to-end orchestration behavior and you have the required environment available, also run:

```bash
./tests/run-tests.sh --smoke
./tests/run-tests.sh --integration
```

Today, the implementer, reviewer, and judge smoke tests execute on each allowed host via the shared runner, and the happy-path E2E runs on the selected viable host path. Use `--host` when you want only one host locally, and use `--changed` when you want the runner to keep Tier 1 and add only the matching heavier checks. Explicit `claude` harness slots should execute through `claude -p` directly and fail per slot if the external Claude runtime is unavailable. `test-e2e-edge-cases.sh` and `test-reviewer-accuracy.sh` still skip explicitly.
For profile-loading regressions, especially inherited profiles that rely on built-in prompts through a symlinked install layout, use `./tests/run-tests.sh --test test-claude-profile-inheritance-smoke.sh`.

## What the Tests Check

- **Contracts** — Variable references in prompts match SKILL.md definitions, status/verdict values are consistent across files, required sections exist
- **Structure** — Required packaging files exist, including the Codex skill mirror plus the Codex build/install/update scripts
- **Harness integrity** — The runner and placeholder/skip behavior match the documented contract
- **Smoke** — Real implementer/reviewer/judge checks on each available host
- **Claude profile inheritance smoke** — Real Claude-host coverage for local `extends:` profiles through a symlinked installed skill path, plus blocked setup artifacts when inheritance cannot resolve
- **Benchmark** — Speed tests comparing slot-machine vs baseline single-agent runs
- **E2E** — Real happy-path host-neutral coverage plus explicit skips for the still-unwired edge-case path

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
