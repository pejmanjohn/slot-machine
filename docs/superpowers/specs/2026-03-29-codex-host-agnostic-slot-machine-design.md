# Codex-Friendly, Host-Agnostic Slot Machine Design

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this design task-by-task.

**Goal:** Make slot-machine run as a first-class skill in both Claude Code and Codex, while restructuring the orchestration model so the system is host-agnostic rather than Claude-first.

**Architecture:** Introduce an explicit split between the shared orchestration core and platform adapters. The shared core owns profile loading, slot parsing, run artifacts, review, judgment, and synthesis. Host adapters own how slot-machine runs its native orchestration phases, and harness adapters own how individual slots are executed in Claude or Codex.

**Tech Stack:** Markdown skill orchestration, Claude CLI, Codex CLI, shell-based validation harness, git worktrees, plugin packaging for Claude and Codex.

---

## Problem

The current repo already supports one cross-harness direction: Claude-hosted orchestration can launch Codex slots via `codex exec`. That is useful, but the architecture still assumes Claude is the default reality and Codex is an outbound special case.

This shows up in four places:

1. `SKILL.md` treats Claude-native orchestration as the default path and Codex as an adapter path.
2. The packaging and install story is Claude-first (`.claude-plugin/`, `~/.claude/skills`, README language).
3. Config and examples mostly point at `CLAUDE.md`, with `AGENTS.md` only lightly referenced.
4. The real smoke and E2E validation harness is hard-coded around `claude -p`.

The intended end state has always been host-agnostic: slot-machine should run from Claude or Codex as equal first-class hosts, and either host should be able to launch the other as an external harness.

## Scope

This design covers:

- Shared host-agnostic slot-machine architecture
- Equal Claude and Codex host support in docs, config, packaging, and tests
- First implementation slice for two hosts (`claude`, `codex`) and two external harness adapters (`claude`, `codex`)
- A bounded first release that keeps review, judge, and synthesis native to the active host

This design does not cover:

- Gemini or third-host support
- Moving reviewer, judge, or synthesizer phases across harnesses
- User-defined arbitrary harness registries in the first slice
- Broad marketplace polish beyond what is needed for equal Claude/Codex support

## Design Principles

1. **Host-agnostic core, host-specific edges.** Shared orchestration logic should not encode Claude-only assumptions.
2. **Equal first-class host support.** The repo should present Claude and Codex symmetrically in packaging, install, config, and examples.
3. **Harness-native implementation.** Each slot should execute through its selected harness in an isolated worktree or file path.
4. **Stable downstream contract.** Review, judge, synthesis, and run artifacts must not care how an implementation was produced.
5. **One source of truth.** `SKILL.md` remains the canonical orchestration document; packaging layers should point at it rather than fork it.

## Terminology

### Host

The environment running slot-machine itself.

Examples:
- Claude Code host
- Codex host

### Harness

The execution system used for a specific slot.

Examples:
- `claude`
- `codex`

### Slot

A single implementation attempt with normalized internal fields:

```text
slot = {
  skill_ref?: normalized skill identifier,
  harness_ref?: normalized harness identifier,
  mode: default | custom
}
```

### Host Adapter

The logic that maps the shared orchestration model onto the host's native capabilities.

Responsibilities:
- Native orchestration dispatch
- Native review/judge/synthesis execution
- Host-specific packaging and install docs
- Host-specific config discovery language where needed

### Harness Adapter

The logic that executes an implementer slot in a specific harness.

Responsibilities:
- Invoke the harness in an isolated workspace
- Translate skill syntax
- Detect model/version
- Parse the implementer report into the standard slot-machine report format

## Architecture

### Shared Orchestration Core

The shared core continues to own:

- Profile loading and inheritance
- Slot definition parsing and normalization
- Spec validation
- Project context gathering
- Run directory and artifact contracts under `.slot-machine/runs/`
- Review dispatch
- Judge dispatch
- Synthesis dispatch
- Status and verdict contracts

These behaviors stay shared because they are the product.

### Adapter Layer

The shared core delegates only the platform-specific edges:

- **Host adapters**
  - `claude-host`
  - `codex-host`

- **Harness adapters**
  - `claude-harness`
  - `codex-harness`

The first release should implement these four adapters only.

## Execution Model

The orchestrator should be host-native.
The implementers should be harness-native.

That yields these first-phase execution combinations:

| Active host | Slot harness | Execution path |
|-------------|--------------|----------------|
| Claude | Claude | Native Claude orchestration/subagent path |
| Claude | Codex | Worktree + `codex exec` |
| Codex | Codex | Worktree + `codex exec` |
| Codex | Claude | Worktree + `claude -p` |

### Host-Native Review Pipeline

The review, judge, and synthesizer phases remain native to the current host in the first slice.

That means:

- Claude-hosted slot-machine uses Claude-native review/judge/synthesis execution.
- Codex-hosted slot-machine uses Codex-native review/judge/synthesis execution.

This keeps the first implementation bounded while still delivering the critical bidirectional host/harness feature.

### Harness-Native Implementer Contract

Every implementer slot must satisfy the same output contract regardless of harness:

- Work only inside the assigned worktree or file output location
- Return one of:
  - `DONE`
  - `DONE_WITH_CONCERNS`
  - `BLOCKED`
  - `NEEDS_CONTEXT`
- End with the standard implementer report shape already consumed by reviewers

Reviewers, judges, and synthesizers must not need to know whether the code came from Claude or Codex.

## Skill Syntax Normalization

The current syntax is Claude-centric because slot definitions use slash-prefixed skills and only translate outward to Codex.

The normalized rule should be:

- Accept both `/skill-name` and `$skill-name` as input
- Normalize internally to a host-neutral skill reference
- Translate only when dispatching into a concrete harness

Examples:

- User input `/superpowers:test-driven-development`
- User input `$superpowers:test-driven-development`
- Internal normalized value `superpowers:test-driven-development`

Dispatch translation:

- Claude harness -> `/superpowers:test-driven-development`
- Codex harness -> `$superpowers:test-driven-development`

This removes host bias from the parser while keeping host-native ergonomics.

## Config and Instruction Discovery

The repo should stop implying that `CLAUDE.md` is the real config location and `AGENTS.md` is merely equivalent.

The first implementation should treat these as equal first-class project instruction sources:

- `AGENTS.md`
- `CLAUDE.md`

Documentation and `SKILL.md` should describe slot-machine configuration as supported in either file. Where examples differ by host, present both explicitly rather than implying one is canonical.

## Packaging and Distribution

### Claude

Retain Claude packaging:

- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`

### Codex

Add Codex packaging:

- `.codex-plugin/plugin.json`
- `skills/slot-machine/SKILL.md` as a symlink or thin wrapper to the root `SKILL.md`

The root `SKILL.md` remains the single source of truth. Packaging layers should reference it rather than duplicating the orchestration body.

### Install Story

The README and contributor docs should present Claude and Codex as equal install targets:

- Claude plugin or skills-directory installation
- Codex plugin or repo/user skills-directory installation

The repo should no longer describe itself as only a Claude Code skill.

## Test Strategy

### Keep

Preserve the fast contract suite:

- Prompt/status/verdict consistency
- Variable documentation consistency
- Artifact contract validation

### Refactor

Replace the host-specific test helper with a host-neutral runner abstraction.

Current state:

- `run_claude_to_file(...)`
- Claude-only stream parsing

Target state:

- `run_host_to_file(host, ...)`
- Host-specific parser for Claude JSON stream
- Host-specific parser for Codex JSONL stream

### Required First-Phase Runtime Coverage

When the relevant CLI is installed, the suite should be able to run real:

- Implementer smoke on Claude
- Implementer smoke on Codex
- Reviewer smoke on Claude
- Reviewer smoke on Codex
- Judge smoke on Claude
- Judge smoke on Codex
- Happy-path E2E from Claude host
- Happy-path E2E from Codex host

Tests should skip explicitly when a required host CLI is unavailable.

### Maintainability Benefit

Adding a new host later becomes:

1. Add one runner
2. Add one result parser
3. Reuse the same smoke/E2E structure

That is materially cleaner than multiplying host-specific test scripts.

## First Implementation Slice

The first implementation should include:

1. Shared host-agnostic orchestration wording in `SKILL.md`
2. Equal Claude/Codex packaging and install documentation
3. Equal `AGENTS.md` / `CLAUDE.md` config documentation
4. Input parsing for both slash and dollar skill syntax
5. `claude` as a first-class harness adapter
6. `codex` as a first-class harness adapter
7. Codex-hosted slot-machine launching `claude -p`
8. Claude-hosted slot-machine continuing to launch `codex exec`
9. Host-neutral runtime helpers and first-phase real validation coverage

The first implementation should explicitly not include:

- Third-host support
- Cross-harness reviewer/judge execution
- Arbitrary user-defined harness registries

## Operational Detail: Harness Execution

### Claude Harness Adapter

The Claude harness adapter should:

- Check `which claude`
- Run `claude -p` in the assigned worktree
- Use a machine-readable output mode
- Extract:
  - final implementer report
  - model identifier when available
  - failure details on timeout or non-zero exit

### Codex Harness Adapter

The Codex harness adapter should:

- Check `which codex`
- Run `codex exec` in the assigned worktree
- Use `workspace-write`
- Parse JSONL output
- Extract:
  - final implementer report
  - model identifier
  - failure details on timeout or non-zero exit

### Shared Failure Contract

Both harness adapters should normalize failures into the same slot-machine semantics:

- missing CLI -> explicit warning and fallback behavior defined by the host adapter
- timeout -> `BLOCKED`
- empty or unparsable report -> `BLOCKED`
- successful execution with concerns -> `DONE_WITH_CONCERNS`

## Acceptance Criteria

- Slot-machine can be installed and described as a first-class skill in both Claude and Codex.
- The shared orchestration contract no longer assumes Claude is the canonical host.
- Codex-hosted slot-machine can run slots through the Claude harness.
- Claude-hosted slot-machine can run slots through the Codex harness.
- `SKILL.md`, docs, packaging, and tests present Claude and Codex symmetrically.
- Real smoke and E2E harness support is no longer Claude-only.
- Existing run artifact contracts under `.slot-machine/runs/` remain intact.

## Risks

### Risk: Over-generalizing too early

If the first implementation tries to solve arbitrary harness registries or third-host support immediately, the change will grow too large and destabilize the repo.

Mitigation:
- Limit phase one to Claude and Codex only
- Define clean adapter boundaries now
- Leave broader registry work for a later phase

### Risk: Regressing current Claude-hosted behavior

The current skill already works in Claude-hosted mode and already documents a Codex outbound path.

Mitigation:
- Preserve current contracts and artifact layout
- Keep the Claude-host + Codex-harness path working throughout
- Add contract coverage before broad refactors

### Risk: Test matrix growth

Adding real Codex runtime coverage will increase test surface and runtime cost.

Mitigation:
- Keep the fast contract suite lightweight
- Gate runtime tests on CLI availability
- Preserve explicit skip behavior for unavailable environments

## Recommended Delivery Strategy

Design for the host-agnostic architecture immediately, but implement the first slice narrowly.

That means:

- Architect for symmetric Claude/Codex support
- Ship only the adapters and packaging needed for Claude and Codex
- Prove the shape with real runtime validation
- Leave third-host generalization for a later phase

This avoids another temporary Claude-first patch while still keeping the first implementation bounded and shippable.
