# Result Artifacts Reference

This file summarizes the canonical run-artifact layout and the terminal `result.json` shapes.

## Canonical Paths

- `run_dir`: the per-run directory under `.slot-machine/runs/`.
- `events_path`: `{run_dir}/events.jsonl`
- `state_path`: `{run_dir}/state.json`
- `result_path`: `{run_dir}/result.json`
- `handoff_path`: `.slot-machine/runs/latest/handoff.md` only in manual mode

The latest pointers always refer to the most recent terminal run without copying the full result payload.

## Finished Result

```json
{
  "resolution_mode": "finished",
  "verdict": "PICK",
  "winning_slot": 2,
  "confidence": "high",
  "slots": 3,
  "slots_succeeded": 3,
  "files_changed": ["src/example.py"],
  "tests_passing": 12,
  "run_dir": "/abs/path/.slot-machine/runs/2026-03-31-demo",
  "events_path": "/abs/path/.slot-machine/runs/2026-03-31-demo/events.jsonl",
  "state_path": "/abs/path/.slot-machine/runs/2026-03-31-demo/state.json"
}
```

## Manual Handoff Result

```json
{
  "resolution_mode": "manual",
  "verdict": null,
  "winning_slot": null,
  "confidence": null,
  "slots": 3,
  "slots_succeeded": 2,
  "handoff_path": "/abs/path/.slot-machine/runs/latest/handoff.md",
  "files_changed": null,
  "tests_passing": null,
  "slot_details": [
    {
      "slot": 1,
      "status": "DONE",
      "review_path": "/abs/path/.slot-machine/runs/2026-03-31-demo/review-1.md",
      "thread_id": "thread_abc123",
      "events_path": "/abs/path/.slot-machine/runs/2026-03-31-demo/slot-1/codex-events.jsonl",
      "stderr_path": "/abs/path/.slot-machine/runs/2026-03-31-demo/slot-1/codex-stderr.txt"
    }
  ],
  "run_dir": "/abs/path/.slot-machine/runs/2026-03-31-demo",
  "events_path": "/abs/path/.slot-machine/runs/2026-03-31-demo/events.jsonl",
  "state_path": "/abs/path/.slot-machine/runs/2026-03-31-demo/state.json"
}
```

## Blocked Setup Result

Use `resolution_mode: "blocked"` when setup cannot proceed, including profile-loading failures.

```json
{
  "resolution_mode": "blocked",
  "blocked_stage": "profile_loading",
  "blocked_reason": "Base profile 'coding' could not be resolved for profile 'blog-post-exp4'",
  "slots": 0,
  "slots_succeeded": 0,
  "files_changed": null,
  "tests_passing": null,
  "run_dir": "/abs/path/.slot-machine/runs/2026-03-31-demo",
  "events_path": "/abs/path/.slot-machine/runs/2026-03-31-demo/events.jsonl",
  "state_path": "/abs/path/.slot-machine/runs/2026-03-31-demo/state.json"
}
```

## History Updates

- `active.json` is written at run start, updated during execution, and reset to the idle sentinel when the run ends.
- `latest.json` and `index.jsonl` are refreshed on every terminal path, including judged completion, manual handoff completion, and blocked or failed exits.
- Manual handoff still writes `events.jsonl`, `state.json`, `latest.json`, and `index.jsonl`, and still emits `run_finished`.
