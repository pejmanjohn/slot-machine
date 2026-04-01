# Slot Machine Orchestrator Trace Design

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this design task-by-task.

**Goal:** Add first-class orchestration observability to slot-machine so each run exposes an append-only trace of what happened, a current-state snapshot of what is happening now, and a stable cross-run discovery home for inspection and future analysis.

**Architecture:** Keep run-local trace artifacts co-located with the existing run directory under `.slot-machine/runs/<run-id>/`, and add a lightweight `.slot-machine/history/` discovery layer that points at active, latest, and completed runs. The trace remains orchestrator-level only: it records lifecycle transitions, retries, persisted artifacts, and outcome metadata, but does not expose subagent internal reasoning or require slots to share state.

**Tech Stack:** Markdown skill orchestration in `SKILL.md`, run artifacts under `.slot-machine/runs/`, shell-based contract and E2E tests, git worktrees for coding isolation, JSON/JSONL artifact contracts, Claude and Codex harness metadata.

---

## Problem

Slot-machine already preserves final run artifacts such as `result.json`, reviewer scorecards, verdicts, raw Codex logs, and manual handoff artifacts under `.slot-machine/runs/`. That is enough for post-hoc inspection of the end result, but it does not preserve a normalized, orchestrator-level story of how the run got there.

Today, that gap creates three problems:

1. **Troubleshooting is slower than it should be.** When a run stalls, retries unexpectedly, writes incomplete artifacts, or dies between phases, the operator has to reconstruct state from terminal output and scattered artifacts rather than inspecting a single source of truth.
2. **Current-state inspection is weak.** There is no stable machine-readable answer to "what phase is this run in right now?" or "which slots are done, retried, waiting on review, or blocked?".
3. **Cross-run insight has no clean substrate.** The repo can preserve completed run directories, but there is no normalized discovery home for later aggregation across many runs or for comparing harness, profile, and retry behavior over time.

The design goal is to solve those problems without weakening slot independence, changing the existing `result.json` contract, or coupling runtime behavior to historical analysis.

## Scope

This design covers:

- Per-run orchestrator trace artifacts for every run
- A stable current-state snapshot for active inspection
- A cross-run discovery home that can locate active, latest, and completed traces
- Contract rules that keep trace emission in sync as the skill evolves
- Documentation and validation updates needed to make the trace a first-class artifact contract

This design does not cover:

- Slot-to-slot shared state during implementation
- Historical analytics queries, dashboards, or ranking logic
- Tracing internal model reasoning or raw prompt/response contents beyond what artifacts already preserve
- Replacing existing `result.json`, review, verdict, or handoff artifacts
- Changing slot isolation, judge logic, or synthesis behavior

## Design Principles

1. **Observability first, analytics second.** The first implementation should make runs easier to inspect and debug. Future cross-run analysis must consume the trace; the live orchestrator must not depend on historical aggregation.
2. **Slots remain independent.** No slot may read another slot's trace state as implementation context. The trace belongs to the orchestrator, not to the implementers.
3. **Run-local truth, cross-run discovery.** Canonical trace artifacts should live with the run that produced them. Cross-run storage should provide stable discovery pointers and summaries, not replace run-local state.
4. **Additive compatibility.** Existing artifact contracts such as `.slot-machine/runs/latest/result.json` remain valid. The trace extends the contract; it does not replace it.
5. **Normalized orchestrator vocabulary.** Trace events must describe orchestration lifecycle concepts that apply across Claude-hosted, Codex-hosted, native, and external harness runs.
6. **Self-maintained contract.** Adding a new orchestration phase, retry path, or required artifact should require updating trace docs and tests in the same change.

## Storage Model

### Canonical Per-Run Artifacts

Every run gains two new canonical artifacts alongside the existing run outputs:

- `.slot-machine/runs/<run-id>/events.jsonl`
- `.slot-machine/runs/<run-id>/state.json`

`events.jsonl` is the append-only raw trace for the run.

`state.json` is the materialized current snapshot for the run. It is rewritten as the orchestrator advances so humans and scripts can inspect current status without replaying the full event stream.

The existing run directory remains the canonical home for:

- `result.json`
- review scorecards
- `verdict.md`
- synthesis artifacts
- manual handoff artifacts
- raw Codex harness logs

### Cross-Run Discovery Home

Add a stable discovery layer under:

- `.slot-machine/history/active.json`
- `.slot-machine/history/latest.json`
- `.slot-machine/history/index.jsonl`

These files are intentionally lightweight:

- `active.json` points at the run currently in progress, if any, and includes the canonical `run_dir`, `events_path`, `state_path`, `started_at`, and current status.
- `latest.json` points at the most recently finished run and includes the canonical `run_dir`, `events_path`, `state_path`, `result_path`, `finished_at`, and outcome summary.
- `index.jsonl` appends one summary row per completed run. This is the seed for future cross-run analysis, but the runtime must not read it to make orchestration decisions.

### Run Discoverability

Each run must be able to find its own trace without scanning history:

- `result.json` should include canonical absolute `events_path` and `state_path` fields for that run.
- `state.json` should include canonical `run_dir`, `events_path`, and `result_path` fields.
- `active.json` and `latest.json` should point directly at the same canonical run-local trace files.

This gives operators three easy lookup paths:

1. Start from the run directory and open `events.jsonl` or `state.json`
2. Start from `.slot-machine/history/active.json` to inspect the current run
3. Start from `.slot-machine/history/latest.json` to inspect the most recent finished run

## Event Model

### Canonical Event Stream

`events.jsonl` is the source of truth for orchestrator history. It must be append-only and ordered by a monotonically increasing per-run sequence number.

Each event uses a stable envelope:

```json
{
  "schema_version": 1,
  "seq": 14,
  "ts": "2026-03-31T22:10:04Z",
  "run_id": "2026-03-31-task-queue-abc123",
  "phase": "review",
  "event": "review_finished",
  "slot": 2,
  "attempt": 1,
  "data": {
    "compliance": "PASS",
    "critical": 0,
    "important": 1,
    "minor": 2,
    "review_path": "/abs/path/.slot-machine/runs/2026-03-31-task-queue/review-2.md"
  }
}
```

### Required Envelope Fields

- `schema_version`: integer schema version for forward compatibility
- `seq`: monotonically increasing integer sequence number within the run
- `ts`: ISO 8601 UTC timestamp
- `run_id`: stable run identifier
- `phase`: normalized orchestration phase name
- `event`: normalized event name
- `slot`: slot number when the event is slot-scoped, otherwise omitted or `null`
- `attempt`: attempt number when the event is retry-aware, otherwise omitted or `null`
- `data`: event-specific metadata object

### Normalized Event Vocabulary

The first implementation should support this bounded event vocabulary:

- `run_started`
- `phase_entered`
- `artifact_written`
- `slot_dispatched`
- `slot_finished`
- `slot_retry_scheduled`
- `precheck_started`
- `precheck_finished`
- `review_dispatched`
- `review_finished`
- `judge_dispatched`
- `judge_finished`
- `synthesis_dispatched`
- `synthesis_finished`
- `cleanup_started`
- `cleanup_finished`
- `run_finished`
- `run_failed`

These event names are intentionally generic. Future orchestration features should reuse the vocabulary where possible and extend only when a genuinely new lifecycle concept appears.

### Phase Names

The initial normalized phase set should match the orchestration model already described in `SKILL.md`:

- `setup`
- `implementation`
- `review`
- `judgment`
- `synthesis`
- `manual_handoff`
- `cleanup`
- `finalization`

If a run skips a phase, it should simply never emit `phase_entered` for that phase.

### Event Payload Conventions

Event payloads should prefer references over duplication:

- Artifact events should record absolute paths to files that were written.
- Slot events should record normalized harness/model metadata, slot status, thread IDs when available, and workspace paths.
- Review, judge, and synthesis completion events should record structured summaries plus canonical artifact paths.
- Failure events should record normalized reason categories, not only free-form prose.

The trace should not attempt to duplicate raw subagent transcripts, prompt bodies, or harness-native session logs that are already stored elsewhere or too unstable to normalize cleanly.

## State Model

### Purpose

`state.json` exists for fast inspection. It should answer "what is happening right now?" and "what is the latest known state of every orchestration actor?" without replaying `events.jsonl`.

### Source of Truth

`events.jsonl` remains the canonical history.

`state.json` is a materialized snapshot derived from the orchestrator's current in-memory state and the same normalized schema rules used to emit events. It should be rewritten immediately after each event append or equivalent state transition so that `active.json` always points at a useful current snapshot.

### Required Top-Level Fields

The first implementation should include at minimum:

```json
{
  "schema_version": 1,
  "run_id": "2026-03-31-task-queue-abc123",
  "status": "running",
  "current_phase": "review",
  "started_at": "2026-03-31T22:00:00Z",
  "updated_at": "2026-03-31T22:10:04Z",
  "run_dir": "/abs/path/.slot-machine/runs/2026-03-31-task-queue",
  "events_path": "/abs/path/.slot-machine/runs/2026-03-31-task-queue/events.jsonl",
  "result_path": "/abs/path/.slot-machine/runs/2026-03-31-task-queue/result.json",
  "manual_handoff": false,
  "slots": [
    {
      "slot": 1,
      "attempt": 1,
      "implementer_status": "DONE",
      "review_status": "DONE",
      "workspace_path": "/abs/path/to/slot-1",
      "harness": "claude",
      "model": "claude-opus-4-6"
    }
  ],
  "judge_status": "PENDING",
  "synthesis_status": "PENDING",
  "cleanup_status": "PENDING",
  "last_event_seq": 14
}
```

### State Semantics

- `status` should distinguish at least `running`, `finished`, and `failed`
- `current_phase` should reflect the latest emitted `phase_entered`
- `slots` should contain one normalized object per slot, including latest attempt and lifecycle statuses
- `judge_status`, `synthesis_status`, and `cleanup_status` should make phase-specific progress visible without requiring event replay
- `last_event_seq` should match the latest appended event sequence number

## Integration Rules

### Required Emission Points

Trace emission is mandatory at these orchestration points:

1. When the run starts
2. Whenever the orchestrator enters a new phase
3. Whenever a required artifact is successfully written
4. Whenever a slot is dispatched
5. Whenever a slot finishes, blocks, errors, or schedules a retry
6. Whenever pre-checks start and finish
7. Whenever a reviewer, judge, or synthesizer is dispatched and finishes
8. Whenever cleanup starts and finishes
9. Whenever the run finishes successfully
10. Whenever the run fails terminally

### Artifact Coverage

Every artifact that is already a required contract artifact should emit a corresponding `artifact_written` event, including:

- `result.json`
- `review-{i}.md`
- `verdict.md`
- `handoff.md`
- `slot-manifest.json`
- any new trace artifacts themselves, where sensible

The purpose is not to trace every file in the workspace. The purpose is to make required orchestration outputs auditable.

### Retry Semantics

Retries should be explicit in the trace:

- `slot_retry_scheduled` records the reason and next attempt number
- the retried slot emits a fresh `slot_dispatched` event with incremented `attempt`
- state must reflect the latest attempt while preserving retry history in `events.jsonl`

### Cross-Host and Cross-Harness Normalization

Trace artifacts must use normalized orchestrator terms regardless of host:

- Claude-hosted and Codex-hosted runs emit the same event vocabulary
- native and external harness slots emit the same slot lifecycle events
- harness-specific metadata belongs in `data` fields, not in the event names themselves

This keeps traces comparable across many runs and many agent combinations.

## Self-Maintenance Contract

The trace only stays useful if it evolves with the skill instead of drifting behind it. This design therefore treats trace emission as a first-class artifact contract, not a best-effort debug extra.

### Required Maintenance Rules

1. Any change that adds a new orchestration phase, terminal path, retry path, or required artifact must update:
   - `SKILL.md`
   - README artifact/inspection docs where relevant
   - trace contract tests
2. Any new required persisted artifact must emit `artifact_written`
3. Any new lifecycle actor with dispatch and completion semantics must emit dispatched + finished/failed events
4. `state.json` fields must remain derivable from emitted lifecycle transitions and current normalized run state
5. The root `SKILL.md` and `skills/slot-machine/SKILL.md` must stay byte-for-byte synchronized after trace instructions are added

### Schema Discipline

To keep maintenance elegant:

- Prefer extending `data` payloads over adding many new top-level envelope fields
- Reuse existing event names when a new behavior is semantically the same lifecycle action
- Add new event names only when the lifecycle concept is genuinely distinct
- Version the schema with `schema_version` if breaking changes ever become necessary

### What Not To Trace

The orchestrator trace should not become a second copy of raw agent transcripts. Do not record:

- full prompts or full model outputs that already live in harness-native artifacts
- internal chain-of-thought style reasoning
- per-token or per-message low-level transport events
- slot-to-slot shared context

The trace is meant to explain orchestration, not mirror everything the harness saw.

## Result and History Contracts

### `result.json`

Keep the current top-level result contract intact and extend it additively with:

- `events_path`
- `state_path`

These should be canonical absolute paths to the run-local trace artifacts.

### `active.json`

`active.json` should exist only while a run is active. It should contain:

- `run_id`
- `run_dir`
- `events_path`
- `state_path`
- `started_at`
- `updated_at`
- `status`

When no run is active, the file may be removed or replaced with a sentinel object. The implementation must pick one behavior and document it clearly.

### `latest.json`

`latest.json` should always point at the most recently finished run and include:

- `run_id`
- `run_dir`
- `events_path`
- `state_path`
- `result_path`
- `finished_at`
- `status`

### `index.jsonl`

Each completed run appends one summary row to `index.jsonl`. The first implementation should include:

- `schema_version`
- `run_id`
- `started_at`
- `finished_at`
- `profile`
- `slots`
- `successful_slots`
- `manual_handoff`
- `status`
- `verdict` when available
- `run_dir`
- `events_path`
- `state_path`
- `result_path`

This keeps the initial index useful for discovery and future analysis without overcommitting to a premature analytics model.

## Validation Strategy

The trace is part of the skill contract and should be validated accordingly.

### Contract Tests

Add or extend contract checks so `SKILL.md` explicitly documents:

- the new per-run trace artifacts
- the `.slot-machine/history/` discovery home
- the bounded event vocabulary
- the `state.json` snapshot contract
- the maintenance rule that new orchestration behavior must update trace docs/tests

### Happy-Path E2E Coverage

Extend the happy-path E2E test to verify that a completed judged run writes:

- `events.jsonl`
- `state.json`
- `result.json` with `events_path` and `state_path`
- `latest.json`
- `index.jsonl`

It should also verify that required lifecycle events appear in the event stream in a plausible order.

### Manual-Handoff Coverage

Extend the manual handoff E2E test to verify:

- `manual_handoff` runs emit the correct terminal path events
- `judge_finished` and `synthesis_finished` are absent when those phases are skipped
- `handoff.md`, `slot-manifest.json`, and manual-mode `result.json` each produce `artifact_written` coverage

### Mirror Integrity

Keep the existing requirement that `skills/slot-machine/SKILL.md` stays synchronized with the root `SKILL.md`.

## Rollout

The first release should stay intentionally small:

1. Add run-local `events.jsonl` and `state.json`
2. Add `.slot-machine/history/active.json`, `.slot-machine/history/latest.json`, and `.slot-machine/history/index.jsonl`
3. Extend `result.json` additively with `events_path` and `state_path`
4. Document the trace contract in `SKILL.md` and README
5. Add contract and targeted E2E coverage

This is enough to make the skill more inspectable today while leaving room for richer cross-run analysis later.

## Success Criteria

The design is successful when:

- an operator can inspect one stable file to see current orchestration state
- a completed run exposes an append-only event trace without reading terminal logs
- runs can be discovered from a stable cross-run home without scanning dated directories manually
- slot independence remains unchanged
- future changes to orchestration behavior are forced to keep trace docs/tests in sync

## Open Decision

The only remaining implementation-level choice is how `active.json` behaves when there is no active run:

- remove the file entirely, or
- keep a sentinel object such as `{ "status": "idle" }`

Either behavior is acceptable, but the implementation should pick one and make it consistent across docs, tests, and runtime instructions.
