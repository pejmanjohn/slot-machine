# AGENTS.md

## Purpose

This repository is a skill/plugin repo for Claude Code and Codex, not an application service. The primary artifacts are prompt specifications, packaging metadata, and their validation harness:

- `SKILL.md` is the host-agnostic orchestration engine.
- `.claude-plugin/` and `.codex-plugin/` are first-class packaging/discovery targets.
- `skills/slot-machine/SKILL.md` is the Codex discovery symlink to the repo-root `SKILL.md`.
- `profiles/` contains task-specific profile configs and agent prompts.
- `tests/` contains shell-based contract checks, real implementer/reviewer smoke tests, scaffolded higher-tier checks, fixtures, and benchmarks.

Treat prompt wording, documented variables, status strings, and output contracts as code. Small text edits can break downstream parsing.

## Repo Map

- `SKILL.md`
  - Frontmatter `description` must describe trigger conditions only, not workflow details.
  - Defines the universal variable set, slot configuration rules, artifact paths, and orchestration behavior.
- `.claude-plugin/`, `.codex-plugin/`, and `skills/slot-machine/SKILL.md`
  - Keep Claude and Codex packaging aligned when discovery changes.
  - `skills/slot-machine/SKILL.md` must remain a symlink to `../../SKILL.md`.
- `profiles/coding/` and `profiles/writing/`
  - `0-profile.md` holds frontmatter and approach hints.
  - `1-implementer.md`, `2-reviewer.md`, `3-judge.md`, `4-synthesizer.md` are the phase prompts.
- `tests/`
  - `test-contracts.sh`, `test-skill-structure.sh`, and `test-harness-integrity.sh` are the fast checks that currently run in normal local validation.
  - `test-implementer-smoke.sh`, `test-reviewer-smoke.sh`, and `test-judge-smoke.sh` are real headless smoke tests for the implementer, reviewer, and judge phases.
  - `test-e2e-happy-path.sh` is a real headless happy-path E2E test.
  - `test-e2e-edge-cases.sh` and `test-reviewer-accuracy.sh` still skip until their headless `claude -p` assertions are wired in.
  - `benchmark/` contains long-running benchmark scripts.
- `README.md`, `CONTRIBUTING.md`, `CLAUDE.md`, `AGENTS.md`
  - Keep these aligned with actual workflow and test coverage when behavior changes.

## Change Rules

When editing this repo, preserve these invariants:

1. Keep status values synchronized across `SKILL.md`, profile prompts, and tests:
   - `DONE`
   - `DONE_WITH_CONCERNS`
   - `BLOCKED`
   - `NEEDS_CONTEXT`
2. Keep judge verdict values synchronized everywhere:
   - `PICK`
   - `SYNTHESIZE`
   - `NONE_ADEQUATE`
3. Every `{{VARIABLE}}` used in any profile prompt must be documented in `SKILL.md`.
4. If you change slot configuration, artifact layout, profile loading, or Codex dispatch behavior, update both docs and contract tests in the same change.
5. Preserve the run artifact contract under `.slot-machine/runs/`, including `.slot-machine/runs/latest/result.json` if you change result generation.
6. Do not add workflow details to the `SKILL.md` frontmatter description.
7. Project config can live in `AGENTS.md` or `CLAUDE.md`; docs should treat both as first-class sources.
8. Describe harness routing host-relatively: native path on the active host, with Codex slots using `codex exec` in their slot workspace and Claude-as-other-harness using `claude -p`.

## Editing Guidance

- Follow the existing repo style: Markdown and shell first, minimal ceremony.
- Prefer focused edits. Avoid wholesale prompt rewrites unless the task requires a behavior change.
- If you add a new built-in profile, include all five files:
  - `0-profile.md`
  - `1-implementer.md`
  - `2-reviewer.md`
  - `3-judge.md`
  - `4-synthesizer.md`
- If a change affects parsing assumptions, search broadly with `rg` for the relevant string before and after editing.

## Validation

Run these commands from the repo root:

```bash
./tests/run-tests.sh
```

If you change prompt flow, profile behavior, or orchestration logic and have the required environment available, also run:

```bash
./tests/run-tests.sh --smoke
./tests/run-tests.sh --integration
```

Important: today, higher-tier coverage is mixed. `test-implementer-smoke.sh`, `test-reviewer-smoke.sh`, `test-judge-smoke.sh`, and `test-e2e-happy-path.sh` run for real via headless `claude -p`, while `test-e2e-edge-cases.sh` and `test-reviewer-accuracy.sh` still report explicit skips until their headless assertions are wired in. Read the output instead of assuming `--smoke`, `--integration`, or `--all` gives full dual-host behavioral coverage.

## Practical Review Checklist

Before finishing a change, verify:

- Prompt variables still match `SKILL.md`.
- Section headers and scorecard/verdict wording still match what downstream phases expect.
- Claude and Codex packaging docs still match the repo layout.
- README and contributor docs still describe the real behavior.
- The fast contract suite passes.
