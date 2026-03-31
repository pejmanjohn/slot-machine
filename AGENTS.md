# AGENTS.md

## Purpose

This repository is a skill/plugin repo for Claude Code and Codex, not an application service. The primary artifacts are prompt specifications, packaging metadata, and their validation harness:

- `SKILL.md` is the host-agnostic orchestration engine.
- `.claude-plugin/` and `.codex-plugin/` are first-class packaging/discovery targets.
- `skills/slot-machine/SKILL.md` is the Codex-packaged mirror of the repo-root `SKILL.md`.
- `scripts/build-codex-runtime-skill.sh`, `scripts/install-codex-skill.sh`, and `scripts/update-codex-skill.sh` define the supported Codex runtime install/update flow.
- `scripts/install-codex-standalone-skill.sh` is a compatibility wrapper for materializing a plain bundle at an arbitrary destination.
- `profiles/` contains task-specific profile configs and agent prompts.
- `tests/` contains shell-based contract checks, real implementer/reviewer smoke tests, scaffolded higher-tier checks, fixtures, and benchmarks.

Treat prompt wording, documented variables, status strings, and output contracts as code. Small text edits can break downstream parsing.

## Repo Map

- `SKILL.md`
  - Frontmatter `description` must describe trigger conditions only, not workflow details.
  - Defines the universal variable set, slot configuration rules, artifact paths, and orchestration behavior.
- `.claude-plugin/`, `.codex-plugin/`, and `skills/slot-machine/SKILL.md`
  - Keep Claude and Codex packaging aligned when discovery changes.
  - `skills/slot-machine/SKILL.md` must remain byte-for-byte synchronized with the repo-root `SKILL.md`.
  - `scripts/build-codex-runtime-skill.sh` must keep producing a standalone Codex skill directory with a real `SKILL.md`, linked built-in assets, and no `.codex-plugin` metadata.
  - `scripts/install-codex-skill.sh` must rebuild that runtime bundle into the Codex runtime root and point the stable `~/.agents/skills/slot-machine` link at it.
  - `scripts/update-codex-skill.sh` must rebuild from install metadata so Codex updates do not depend on manual path reconstruction.
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
- Use conventional branch type prefixes for repo work: `feat/`, `fix/`, `docs/`, `style/` with a short kebab-case suffix.
- Open PRs as ready for review by default. Use draft only when there is an explicit reason or the user asks for it.
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

Default development policy:

- Run `./tests/run-tests.sh` for every change. This is the required fast gate for normal feature work.
- Use `./tests/run-tests.sh --changed` when you want the runner to keep Tier 1 and add only the heavier checks matched to the files you changed.
- Use `./tests/run-tests.sh --host claude` or `./tests/run-tests.sh --host codex` when local work only needs one host path.
- Use `./tests/run-tests.sh --jobs auto` or a fixed `--jobs N` value to parallelize independent shell tests.
- Do not treat `--smoke` or `--integration` as default local-development commands. They are much more expensive and should be used selectively.
- Prefer the smallest targeted headless check that matches the area you changed:
  - Implementer prompt or implementer result-shape changes: `./tests/run-tests.sh --test test-implementer-smoke.sh`
  - Reviewer prompt, seeded-bug expectations, or review formatting changes: `./tests/run-tests.sh --test test-reviewer-smoke.sh`
  - Judge prompt, ranking/verdict parsing, or scorecard aggregation changes: `./tests/run-tests.sh --test test-judge-smoke.sh`
  - Claude-host plus Codex-slot bridge changes: `./tests/run-tests.sh --test test-claude-host-codex-smoke.sh`
  - Profile loading, inherited-profile resolution, or symlinked installed-skill layouts: `./tests/run-tests.sh --test test-claude-profile-inheritance-smoke.sh`
  - Happy-path orchestration, merge/finalization, or run-artifact changes: `./tests/run-tests.sh --test test-e2e-happy-path.sh`
  - `manual_handoff`, preserved-worktree behavior, or handoff artifact changes: `./tests/run-tests.sh --test test-e2e-manual-handoff.sh`
- Reserve full smoke and integration sweeps for release prep, cross-host harness work, or broad orchestration refactors.
- Reserve benchmarks for performance work and regression investigation; they are not part of the default feature-development loop.

If you change prompt flow, profile behavior, or orchestration logic and need broader confirmation, run the smallest additional tier that matches the change:

```bash
./tests/run-tests.sh --smoke
./tests/run-tests.sh --integration
```

Recommended release bar:

- Always run `./tests/run-tests.sh`.
- Add at least the relevant targeted smoke or E2E tests for the surfaces changed in the release.
- Run `./tests/run-tests.sh --smoke` for host/harness changes or broad prompt-flow changes.
- Run `./tests/run-tests.sh --integration` when the release touches end-to-end orchestration, artifact generation, merge/finalization, or manual handoff behavior.

Important: today, higher-tier coverage is mixed and expensive. `test-implementer-smoke.sh`, `test-reviewer-smoke.sh`, and `test-judge-smoke.sh` run once per available host, while `test-claude-host-codex-smoke.sh`, `test-claude-profile-inheritance-smoke.sh`, `test-e2e-happy-path.sh`, and `test-e2e-manual-handoff.sh` each perform real headless orchestration runs. `test-e2e-edge-cases.sh` and `test-reviewer-accuracy.sh` still report explicit skips until their headless assertions are wired in. Read the output instead of assuming `--smoke`, `--integration`, or `--all` gives uniform coverage.

## Practical Review Checklist

Before finishing a change, verify:

- Prompt variables still match `SKILL.md`.
- Section headers and scorecard/verdict wording still match what downstream phases expect.
- Claude and Codex packaging docs still match the repo layout.
- README and contributor docs still describe the real behavior.
- The fast contract suite passes.
