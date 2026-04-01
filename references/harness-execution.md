# Harness Execution Reference

This file summarizes how slot implementations are dispatched across native and external harnesses.

## Routing Matrix

| Active host | Slot harness | Execution path |
|-------------|--------------|----------------|
| Claude | Claude | Native Claude orchestration/subagent path |
| Claude | Codex | Profile-isolated slot workspace + `codex exec` |
| Codex | Codex | Native Codex slot workspace + `codex exec` |
| Codex | Claude | Profile-isolated slot workspace + `claude -p` |

Native-host slots are Group 1. External-harness slots are Group 2.

## Codex Harness Contract

For Codex harness slots on the Codex host, the supported execution path is the shared slot runtime helper:

```bash
"$REAL_SKILL_DIR/scripts/codex-slot-runner.py"
```

The helper runs `codex exec` in the current slot workspace, captures `codex-events.jsonl` and `codex-stderr.txt`, writes `codex-slot-report.md` and `codex-slot-result.json`, and records the Codex `thread_id` for later inspection or resume.

For `skill + codex` slots, translate the normalized skill to Codex syntax such as `$superpowers:test-driven-development` and write the prompt to `codex-prompt.txt` before invoking the helper.

## Claude Harness Contract

For explicit Claude harness slots on Codex, launch `claude -p` directly.

```bash
claude -p "/superpowers:test-driven-development

Implement this specification.

Specification:
..."
```

Use the active profile isolation:

- `worktree`: create one worktree per slot.
- `file`: create a per-slot run directory and write the final output there.

## Guardrails

- Do not launch Codex slots as background shell jobs.
- Wait for the external CLI to finish before the review or judge pipeline continues.
- Use the same routing rule for `skill + harness` combinations as for plain harness slots.
