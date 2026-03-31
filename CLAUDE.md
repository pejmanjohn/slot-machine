# Slot Machine Development

You are working on the slot-machine skill/plugin repo for best-of-N parallel implementation across Claude Code and Codex.

## Structure
- `SKILL.md` — Host-agnostic orchestration engine (shared across task types)
- `.claude-plugin/` — Claude packaging and marketplace metadata
- `.codex-plugin/` — Codex plugin metadata
- `skills/slot-machine/SKILL.md` — Must stay byte-for-byte in sync with the repo-root `SKILL.md`
- `scripts/codex-slot-runner.py` — Supported Codex slot runtime helper; invokes `codex exec`, captures raw logs, and normalizes Codex slot reports
- `scripts/install-claude-skill.sh`, `scripts/update-claude-skill.sh` — Supported Claude install/update scripts for keeping `~/.claude/skills/slot-machine` aligned with a chosen source checkout
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
- Describe harness routing host-relatively: native path on the active host, with Codex slots using the slot runtime helper in their slot workspace, which runs `codex exec`, and Claude-as-other-harness using `claude -p`
- Explicit `claude` harness slots should run through `claude -p` directly; do not silently fall back if the external Claude execution fails
- Use conventional branch type prefixes for repo work: `feat/`, `fix/`, `docs/`, `style/` with a short kebab-case suffix
- Open PRs as ready for review by default. Use draft only when there is an explicit reason or the user asks for it.
- Run `./tests/run-tests.sh` before committing

## Testing
- `./tests/run-tests.sh` — Fast suite: contracts, skill structure, harness integrity
- `./tests/run-tests.sh --changed` — Fast suite plus the heavier checks matched to local changes
- `./tests/run-tests.sh --host claude|codex|all` — Restrict headless tests to one host or run the full matrix
- `./tests/run-tests.sh --jobs N|auto` — Run independent tests in parallel
- `./tests/run-tests.sh --smoke` — Real implementer/reviewer/judge smoke tests on each available host
- `./tests/run-tests.sh --integration` — Smoke tier plus the heavier E2E tests
- `./tests/run-tests.sh --benchmark` — Speed benchmarks
- `./tests/run-tests.sh --all` — Full suite, with edge-case E2E and reviewer-accuracy still skipping explicitly

Use this policy for normal repo work:

- Always run `./tests/run-tests.sh` before committing. This is the default development gate.
- Prefer targeted headless tests over full sweeps during feature work:
  - `./tests/run-tests.sh --test test-implementer-smoke.sh`
  - `./tests/run-tests.sh --test test-reviewer-smoke.sh`
  - `./tests/run-tests.sh --test test-judge-smoke.sh`
  - `./tests/run-tests.sh --test test-claude-host-codex-smoke.sh`
  - `./tests/run-tests.sh --test test-e2e-happy-path.sh`
  - `./tests/run-tests.sh --test test-e2e-manual-handoff.sh`
- Do not run `--smoke`, `--integration`, or `--all` by default for routine feature development. Use them when the change is broad enough to justify the cost.
- Use `--smoke` for host/harness changes, prompt-flow changes that span phases, or release prep.
- Use `--integration` for end-to-end orchestration changes, run-artifact changes, merge/finalization changes, or `manual_handoff` changes.
- Use `--benchmark` only for performance work or regression investigation.
