# Harness Execution Reference

This file carries the detailed external-harness command templates that were moved out of `SKILL.md`.

## Routing Matrix

| Active host | Slot harness | Execution path |
|-------------|--------------|----------------|
| Claude | Claude | Native Claude orchestration/subagent path |
| Claude | Codex | Profile-isolated slot workspace + `codex exec` |
| Codex | Codex | Native Codex slot workspace + `codex exec` |
| Codex | Claude | Profile-isolated slot workspace + `claude -p` |

Native-host slots are Group 1. External-harness slots are Group 2.

## External Claude Harness Contract

For explicit Claude harness slots on Codex, launch `claude -p` directly from the assigned isolated slot workspace.

```bash
claude -p "{If skill specified: '/claude_skill_name\n\n'}Implement this specification. {If isolation is worktree: 'Write all files to the current directory.'}{If isolation is file: 'Write the final output to {RUN_DIR}/slot-{i}.md and do not write elsewhere.'}
Do not ask questions or wait for confirmation.

Specification:
{spec}

Project context:
{project_context}

When done, provide this implementer report:
- What you implemented
- Files created or modified
- Test results if you wrote tests
- Concerns or issues encountered" \
  --output-format stream-json \
  2>claude-stderr.txt > claude-stream.jsonl
```

Use the active profile isolation:

- `worktree`: create one worktree per slot, `cd` into it, and run the command there.
- `file`: create a per-slot run directory and tell Claude exactly which `{RUN_DIR}/slot-{i}.md` file to write.

## External Codex Harness Contract

For Codex harness slots, the supported execution path is the shared slot runtime helper in every host/harness combination:

- active host `Codex`, slot harness `Codex`
- active host `Claude`, slot harness `Codex`

Use the helper from the assigned isolated slot workspace:

```bash
"$REAL_SKILL_DIR/scripts/codex-slot-runner.py"
```

The helper runs `codex exec` in the current slot workspace, captures `codex-events.jsonl` and `codex-stderr.txt`, writes `codex-slot-report.md` and `codex-slot-result.json`, and records the Codex `thread_id` for later inspection or resume. On Claude-hosted runs, the external Codex slot path still uses this helper; it is not replaced by a native Claude subagent.

For `skill + codex` slots, translate the normalized skill to Codex syntax such as `$superpowers:test-driven-development` and write the prompt to `codex-prompt.txt` before invoking the helper:

```bash
cat > codex-prompt.txt <<'PROMPT'
{If skill specified: '$codex_skill_name\n\n'}Implement this specification. {If isolation is worktree: 'Write all files to the current directory.'}{If isolation is file: 'Write the final output to {RUN_DIR}/slot-{i}.md and do not write elsewhere.'}
Do not ask questions or wait for confirmation.

Specification:
{spec}

Project context:
{project_context}

When done, provide this implementer report:
- What you implemented
- Files created or modified
- Test results if you wrote tests
- Concerns or issues encountered
PROMPT

python3 "$REAL_SKILL_DIR/scripts/codex-slot-runner.py" \
  --cwd "$PWD" \
  --prompt-file codex-prompt.txt \
  --events-file codex-events.jsonl \
  --stderr-file codex-stderr.txt \
  --result-file codex-slot-result.json \
  --report-file codex-slot-report.md \
  --sandbox workspace-write \
  --config 'model_reasoning_effort="high"' \
  {If isolation is file: --expected-output-path "{RUN_DIR}/slot-{i}.md"}
```

## Guardrails

- Do not launch Codex slots as background shell jobs.
- Wait for the external CLI to finish before the review or judge pipeline continues.
- Use the same routing rule for `skill + harness` combinations as for plain harness slots.
