# Orchestrator Trace Reference

This file summarizes the run-trace contract that was previously embedded in `SKILL.md`.
It covers the orchestrator-level JSONL event stream plus the snapshot files that point at the current run.

## Core Files

- `events.jsonl`: append-only event log for the active run.
- `state.json`: current snapshot of orchestrator state.
- `.slot-machine/history/active.json`: pointer to the active run, or the idle sentinel.
- `.slot-machine/history/latest.json`: pointer to the most recent terminal run.
- `.slot-machine/history/index.jsonl`: append-only summary history.

## Event Shapes

Keep events orchestrator-level only. Do not store raw prompt bodies, slot-local transcripts, or subagent reasoning here.

```json
{"event":"phase_entered","stage":"setup"}
{"event":"slot_dispatched","slot":1,"harness":"codex","skill":"default"}
{"event":"precheck_started","slot":1,"command":"python3 -m pytest tests/ -v"}
{"event":"artifact_written","path":"/abs/path/.slot-machine/runs/2026-03-31-demo/result.json"}
{"event":"slot_finished","slot":1,"status":"DONE"}
{"event":"run_finished","status":"finished"}
```

## Required Event Types

- `phase_entered` for `setup`, `implementation`, `review`, `judgment`, `synthesis`, `manual_handoff`, `cleanup`, and `finalization`.
- `slot_dispatched`, `slot_finished`, and `slot_retry_scheduled` for slot lifecycle changes.
- `precheck_started` and `precheck_finished` around required precheck commands.
- `review_dispatched` and `review_finished` for reviewer lifecycle changes.
- `judge_dispatched` and `judge_finished` for judge lifecycle changes.
- `synthesis_dispatched` and `synthesis_finished` for synthesis lifecycle changes.
- `cleanup_started` and `cleanup_finished` for cleanup lifecycle changes.
- `artifact_written` immediately after each required artifact write completes.
- `run_finished` on success and `run_failed` on terminal failure.

## Notes

- `slot_finished.status` must be one of `DONE`, `DONE_WITH_CONCERNS`, `BLOCKED`, or `NEEDS_CONTEXT`.
- Trace files are for discovery and replay, not for storing full execution payloads.
- Any new orchestration phase or required artifact should keep this reference and the trace-aware tests in sync.
