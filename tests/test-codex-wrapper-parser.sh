#!/usr/bin/env bash
# Tier 1: Validate the Codex wrapper contract handles current JSON event variants.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

FAILED=0
SKILL_CONTENT=$(cat "$SKILL_DIR/SKILL.md")
ITEM_FIXTURE="$SKILL_DIR/tests/fixtures/codex-item-and-turn.jsonl"
TURN_ONLY_FIXTURE="$SKILL_DIR/tests/fixtures/codex-turn-only.jsonl"

render_reference_report() {
    local stream_file="$1"
    local changed_files="$2"

    python3 - "$stream_file" "$changed_files" <<'PY'
import json
import sys

stream_file = sys.argv[1]
changed_files = [line for line in sys.argv[2].splitlines() if line]

messages = []
commands = []
saw_turn_completed = False

with open(stream_file, encoding="utf-8") as fh:
    for raw in fh:
        raw = raw.strip()
        if not raw:
            continue
        payload = json.loads(raw)
        event_type = payload.get("type")

        if event_type == "item.completed":
            item = payload.get("item", {})
            if item.get("type") == "agent_message" and item.get("text"):
                messages.append(item["text"])
            elif item.get("type") == "command_execution" and item.get("command"):
                commands.append(item["command"])
        elif event_type == "turn.completed":
            saw_turn_completed = True

if messages:
    print(messages[-1].strip())
elif saw_turn_completed and changed_files:
    status = "DONE" if commands else "DONE_WITH_CONCERNS"
    print("## Implementer Report")
    print("")
    print(f"**Status:** {status}")
    print("")
    print("**What I implemented:**")
    print("- Wrapper detected a successful Codex run and synthesized this report from post-run inspection.")
    print("")
    print("**Files changed:**")
    for path in changed_files:
        print(f"- {path}")
    print("")
    print("**Test results:**")
    if commands:
        for command in commands:
            print(f"- Observed command: {command}")
    else:
        print("- No structured test summary was extractable from the Codex JSON stream.")
    print("")
    print("**Concerns (if any):**")
    print("- Codex emitted turn.completed without a structured agent_message report.")
elif saw_turn_completed:
    print("BLOCKED: successful terminal event but no meaningful workspace output detected")
else:
    print("BLOCKED: no successful Codex completion event detected")
PY
}

echo "=== Codex Wrapper Parser: Reference Behavior ==="
ITEM_REPORT=$(render_reference_report "$ITEM_FIXTURE" $'SKILL.md\ntests/test-codex-wrapper-parser.sh')
TURN_ONLY_REPORT=$(render_reference_report "$TURN_ONLY_FIXTURE" $'SKILL.md\ntests/test-codex-wrapper-parser.sh')

assert_contains "$ITEM_REPORT" "## Implementer Report" \
    "Reference parser keeps structured implementer reports" || FAILED=$((FAILED + 1))
assert_contains "$ITEM_REPORT" "\\*\\*Status:\\*\\* DONE" \
    "Reference parser preserves DONE status from agent_message" || FAILED=$((FAILED + 1))
assert_contains "$TURN_ONLY_REPORT" "## Implementer Report" \
    "Reference parser synthesizes a standard report for turn.completed-only streams" || FAILED=$((FAILED + 1))
assert_contains "$TURN_ONLY_REPORT" "\\*\\*Status:\\*\\* DONE_WITH_CONCERNS" \
    "Reference parser downgrades to DONE_WITH_CONCERNS when only post-run inspection is available" || FAILED=$((FAILED + 1))
assert_contains "$TURN_ONLY_REPORT" "turn.completed without a structured agent_message report" \
    "Reference parser records the missing structured message as a concern" || FAILED=$((FAILED + 1))

echo ""
echo "=== Codex Wrapper Parser: SKILL Contract ==="
assert_contains "$SKILL_CONTENT" "turn.completed" \
    "SKILL.md documents turn.completed handling" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "codex-events.jsonl" \
    "SKILL.md saves the raw Codex JSONL stream for post-run inspection" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "git status --short" \
    "SKILL.md describes deterministic changed-file inspection" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "DONE_WITH_CONCERNS" \
    "SKILL.md documents DONE_WITH_CONCERNS fallback status" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "structured agent message" \
    "SKILL.md explains the missing structured-message fallback" || FAILED=$((FAILED + 1))

echo ""
echo "=== Codex Wrapper Parser Tests Complete ==="
echo "Failures: $FAILED"
exit $FAILED
