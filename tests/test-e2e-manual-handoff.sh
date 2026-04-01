#!/usr/bin/env bash
# Tier 3: Full E2E integration test — manual handoff path
# Runs a real slot-machine pipeline end-to-end on a temporary Python project
# and validates the transcript, run artifacts, preserved worktrees, and manual
# handoff output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

HOST_FILTER="${SLOT_MACHINE_TEST_HOST_FILTER:-all}"
case "$HOST_FILTER" in
    ""|all|claude) ;;
    codex)
        echo "[SKIP] test-e2e-manual-handoff.sh requires the claude host path"
        exit 2
        ;;
    *)
        echo "[SKIP] unsupported SLOT_MACHINE_TEST_HOST_FILTER: $HOST_FILTER"
        exit 2
        ;;
esac

if ! command -v claude >/dev/null 2>&1; then
    echo "[SKIP] claude CLI not installed"
    exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "[SKIP] python3 not installed"
    exit 2
fi

if ! python3 - <<'PY' >/dev/null 2>&1
import pytest
PY
then
    echo "[SKIP] pytest not available"
    exit 2
fi

echo "=== E2E Manual Handoff Test ==="
echo ""
echo "Test plan:"
echo "  1. Create a temp Python repo with an initial git commit"
echo "  2. Run /slot-machine with 2 slots in manual handoff mode"
echo "  3. Assert transcript sanity: non-empty, no judge dispatch, worktree isolation"
echo "  4. Assert run artifacts: handoff.md, result.json, events.jsonl, state.json, review-*.md, slot diffs, slot manifest, and history pointers"
echo "  5. Assert manual result metadata: resolution_mode=manual and verdict=null"
echo "  6. Assert successful coding worktrees remain and the main worktree is not merged"
echo ""
echo "Host filter: $HOST_FILTER"

SPEC_FILE="$SCRIPT_DIR/fixtures/tiny-spec.md"
SLOT_COUNT=2
TMPDIR=$(mktemp -d)
TEST_BIN="$TMPDIR/.test-bin"
TRANSCRIPT_FILE=$(mktemp)
PYTEST_OUTPUT=$(mktemp)
trap 'rm -rf "$TMPDIR" "$TRANSCRIPT_FILE" "$PYTEST_OUTPUT"' EXIT

canonical_path() {
    python3 - <<'PY' "$1"
import os
import sys

print(os.path.realpath(sys.argv[1]))
PY
}

cd "$TMPDIR"
git init -q
git config user.name "Slot Machine Manual Handoff E2E"
git config user.email "slot-machine-e2e@example.com"
mkdir -p src tests

cat > pyproject.toml <<'EOF'
[project]
name = "slot-machine-e2e"
version = "0.1.0"

[tool.pytest.ini_options]
testpaths = ["tests"]
EOF

cat > src/__init__.py <<'EOF'
EOF

cat > tests/__init__.py <<'EOF'
EOF

# The slot-machine prompts sometimes invoke `python -m pytest`.
# Provide a local shim so the E2E environment matches the guaranteed `python3`.
mkdir -p "$TEST_BIN"
cat > "$TEST_BIN/python" <<'EOF'
#!/usr/bin/env bash
exec python3 "$@"
EOF
chmod +x "$TEST_BIN/python"
export PATH="$TEST_BIN:$PATH"

git add -A
git commit -q -m "initial"
INITIAL_HEAD=$(git rev-parse HEAD)

SPEC=$(cat "$SPEC_FILE")
PROMPT="/slot-machine with $SLOT_COUNT slots, manual_handoff: true, cleanup: true

Spec: $SPEC"

set +e
run_claude_to_file "$TRANSCRIPT_FILE" "$PROMPT" 1200 200 "$TMPDIR"
CLAUDE_RC=$?
set -e

TRANSCRIPT_TEXT=$(cat "$TRANSCRIPT_FILE")
FINAL_REPORT=$(extract_result_text "$TRANSCRIPT_FILE")

if [ "$CLAUDE_RC" -eq 2 ]; then
    echo "$TRANSCRIPT_TEXT"
    exit 2
fi

if [ "$CLAUDE_RC" -ne 0 ]; then
    echo "  [FAIL] claude -p exited with code $CLAUDE_RC"
    echo "$TRANSCRIPT_TEXT"
    exit 1
fi

if [ ! -s "$TRANSCRIPT_FILE" ]; then
    echo "  [FAIL] Transcript is empty"
    exit 1
fi

echo "  [PASS] Transcript captured"
assert_not_contains "$TRANSCRIPT_TEXT" "Judge Slot Machine results" \
    "Manual handoff run does not dispatch the judge"

if [ ! -f "$TMPDIR/.slot-machine/runs/latest/result.json" ] && \
    printf '%s\n' "$TRANSCRIPT_TEXT" | rg -q 'rate_limit_event|error":"rate_limit|out of extra usage'; then
    echo "  [SKIP] claude-host rate limit returned before writing expected run artifacts"
    exit 2
fi

assert_worktree_isolation "$TRANSCRIPT_FILE" "Agent calls use isolation:worktree"

AGENT_CALLS=$(count_agent_calls "$TRANSCRIPT_FILE")
if [ "$AGENT_CALLS" -ge 4 ]; then
    echo "  [PASS] Transcript includes at least 4 Agent calls ($AGENT_CALLS)"
else
    echo "  [FAIL] Expected at least 4 Agent calls, found $AGENT_CALLS"
    exit 1
fi

assert_contains "$FINAL_REPORT" "Manual Handoff" "Final manual handoff report present"
assert_contains "$FINAL_REPORT" "handoff.md" "Final report references the handoff artifact"
assert_contains "$FINAL_REPORT" "slot-manifest.json" "Final report references the slot manifest"

LATEST_RUN="$TMPDIR/.slot-machine/runs/latest"
RESULT_JSON="$LATEST_RUN/result.json"
HANDOFF_FILE="$LATEST_RUN/handoff.md"
MANIFEST_FILE="$LATEST_RUN/slot-manifest.json"
EVENTS_FILE="$LATEST_RUN/events.jsonl"
STATE_FILE="$LATEST_RUN/state.json"
ACTIVE_TRACE="$TMPDIR/.slot-machine/history/active.json"
LATEST_TRACE="$TMPDIR/.slot-machine/history/latest.json"
INDEX_FILE="$TMPDIR/.slot-machine/history/index.jsonl"
CANONICAL_LATEST_RUN=$(canonical_path "$LATEST_RUN")
CANONICAL_HANDOFF_FILE=$(canonical_path "$HANDOFF_FILE")

if [ ! -f "$RESULT_JSON" ] || [ ! -f "$HANDOFF_FILE" ] || [ ! -f "$MANIFEST_FILE" ] || \
    [ ! -f "$EVENTS_FILE" ] || [ ! -f "$STATE_FILE" ]; then
    if printf '%s\n' "$TRANSCRIPT_TEXT" | rg -q 'rate_limit_event|error":"rate_limit|out of extra usage'; then
        echo "  [SKIP] claude-host rate limit returned before writing expected run artifacts"
        exit 2
    fi
fi

if [ -f "$RESULT_JSON" ]; then
    echo "  [PASS] result.json written to latest run dir"
else
    echo "  [FAIL] result.json missing at $RESULT_JSON"
    exit 1
fi

if [ -f "$HANDOFF_FILE" ]; then
    echo "  [PASS] handoff.md written to latest run dir"
else
    echo "  [FAIL] handoff.md missing at $HANDOFF_FILE"
    exit 1
fi

if [ -f "$MANIFEST_FILE" ]; then
    echo "  [PASS] slot-manifest.json written to latest run dir"
else
    echo "  [FAIL] slot-manifest.json missing at $MANIFEST_FILE"
    exit 1
fi

RESULT_FIELDS=$(python3 - <<'PY' "$RESULT_JSON"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data.get("resolution_mode", "UNKNOWN"))
print(data.get("verdict", "UNKNOWN"))
print(data.get("winning_slot", "UNKNOWN"))
print(data.get("slots_succeeded", 0))
print(data.get("run_dir", ""))
print(data.get("handoff_path", ""))
for slot in data.get("slot_details", []):
    worktree_path = slot.get("worktree_path")
    diff_path = slot.get("diff_path")
    review_path = slot.get("review_path")
    branch = slot.get("branch")
    head_sha = slot.get("head_sha")
    if worktree_path:
        print(f"WORKTREE:{worktree_path}")
    if diff_path:
        print(f"DIFF:{diff_path}")
    if review_path:
        print(f"REVIEW:{review_path}")
    if branch:
        print(f"BRANCH:{branch}")
    if head_sha:
        print(f"HEADSHA:{head_sha}")
PY
)

RESULT_MODE=$(printf '%s\n' "$RESULT_FIELDS" | sed -n '1p')
RESULT_VERDICT=$(printf '%s\n' "$RESULT_FIELDS" | sed -n '2p')
RESULT_WINNER=$(printf '%s\n' "$RESULT_FIELDS" | sed -n '3p')
SLOTS_SUCCEEDED=$(printf '%s\n' "$RESULT_FIELDS" | sed -n '4p')
RESULT_RUN_DIR=$(printf '%s\n' "$RESULT_FIELDS" | sed -n '5p')
RESULT_HANDOFF_PATH=$(printf '%s\n' "$RESULT_FIELDS" | sed -n '6p')

if [ "$RESULT_MODE" = "manual" ]; then
    echo "  [PASS] result.json reports manual resolution mode"
else
    echo "  [FAIL] Unexpected resolution mode: $RESULT_MODE"
    exit 1
fi

if [ "$RESULT_VERDICT" = "None" ] || [ "$RESULT_VERDICT" = "null" ]; then
    echo "  [PASS] result.json verdict is null"
else
    echo "  [FAIL] Unexpected verdict value: $RESULT_VERDICT"
    exit 1
fi

if [ "$RESULT_WINNER" = "None" ] || [ "$RESULT_WINNER" = "null" ]; then
    echo "  [PASS] result.json winning_slot is null"
else
    echo "  [FAIL] Unexpected winning_slot value: $RESULT_WINNER"
    exit 1
fi

if [ "$(canonical_path "$RESULT_HANDOFF_PATH")" = "$CANONICAL_HANDOFF_FILE" ]; then
    echo "  [PASS] result.json handoff_path points at the latest handoff"
else
    echo "  [FAIL] Unexpected handoff_path: $RESULT_HANDOFF_PATH"
    exit 1
fi

if [ "$(canonical_path "$RESULT_RUN_DIR")" = "$CANONICAL_LATEST_RUN" ]; then
    echo "  [PASS] result.json run_dir points at the latest run"
else
    echo "  [FAIL] Unexpected run_dir: $RESULT_RUN_DIR"
    exit 1
fi

if [ "$SLOTS_SUCCEEDED" -ge 1 ]; then
    echo "  [PASS] At least one slot succeeded ($SLOTS_SUCCEEDED)"
else
    echo "  [FAIL] Expected at least one successful slot, found $SLOTS_SUCCEEDED"
    exit 1
fi

for trace_file in "$EVENTS_FILE" "$STATE_FILE" "$ACTIVE_TRACE" "$LATEST_TRACE" "$INDEX_FILE"; do
    if [ -f "$trace_file" ]; then
        echo "  [PASS] Trace artifact exists: $trace_file"
    else
        echo "  [FAIL] Missing trace artifact: $trace_file"
        exit 1
    fi
done

python3 - <<'PY' "$RESULT_JSON" "$EVENTS_FILE" "$STATE_FILE" "$ACTIVE_TRACE" "$LATEST_TRACE" "$INDEX_FILE"
import json
import os
import sys

result_path, events_path, state_path, active_path, latest_path, index_path = sys.argv[1:]

with open(result_path, encoding="utf-8") as fh:
    result = json.load(fh)
with open(events_path, encoding="utf-8") as fh:
    events = [json.loads(line) for line in fh if line.strip()]
with open(state_path, encoding="utf-8") as fh:
    state = json.load(fh)
with open(active_path, encoding="utf-8") as fh:
    active = json.load(fh)
with open(latest_path, encoding="utf-8") as fh:
    latest = json.load(fh)
with open(index_path, encoding="utf-8") as fh:
    index_rows = [json.loads(line) for line in fh if line.strip()]

observed = {event["event"] for event in events}
required = {
    "run_started",
    "phase_entered",
    "slot_dispatched",
    "slot_finished",
    "review_dispatched",
    "review_finished",
    "artifact_written",
    "run_finished",
}
missing = sorted(required - observed)
assert not missing, f"missing manual-run events: {missing}"

for forbidden in {"judge_dispatched", "judge_finished", "synthesis_dispatched", "synthesis_finished"}:
    assert forbidden not in observed, f"unexpected manual-run event: {forbidden}"

assert os.path.realpath(result["events_path"]) == os.path.realpath(events_path)
assert os.path.realpath(result["state_path"]) == os.path.realpath(state_path)
assert state["status"] == "finished", state
assert active["status"] == "idle", active
assert os.path.realpath(latest["events_path"]) == os.path.realpath(events_path), latest
assert os.path.realpath(latest["state_path"]) == os.path.realpath(state_path), latest
assert index_rows[-1]["manual_handoff"] is True, index_rows[-1]
assert index_rows[-1]["status"] == "finished", index_rows[-1]
PY

shopt -s nullglob
review_files=("$LATEST_RUN"/review-*.md)
diff_files=("$LATEST_RUN"/slot-*.diff)
shopt -u nullglob

if [ "${#review_files[@]}" -ge 1 ]; then
    echo "  [PASS] Review artifacts exist (${#review_files[@]})"
else
    echo "  [FAIL] No review artifacts were written"
    exit 1
fi

if [ "${#diff_files[@]}" -ge 1 ]; then
    echo "  [PASS] Slot diffs exist (${#diff_files[@]})"
else
    echo "  [FAIL] No slot diffs were written"
    exit 1
fi

for review_file in "${review_files[@]}"; do
    REVIEW_TEXT=$(cat "$review_file")
    assert_contains "$REVIEW_TEXT" "## Slot" "$(basename "$review_file") has slot review header"
    assert_contains "$REVIEW_TEXT" "### Spec Compliance:" \
        "$(basename "$review_file") has spec compliance summary"
done

for diff_file in "${diff_files[@]}"; do
    if [ -s "$diff_file" ]; then
        echo "  [PASS] $(basename "$diff_file") is non-empty"
    else
        echo "  [FAIL] $(basename "$diff_file") is empty"
        exit 1
    fi
done

WORKTREE_PATHS=$(printf '%s\n' "$RESULT_FIELDS" | sed -n 's/^WORKTREE://p')
WORKTREE_COUNT=0
while IFS= read -r worktree_path; do
    [ -n "$worktree_path" ] || continue
    WORKTREE_COUNT=$((WORKTREE_COUNT + 1))
    if [ -d "$worktree_path" ]; then
        echo "  [PASS] Preserved worktree exists: $worktree_path"
    else
        echo "  [FAIL] Missing preserved worktree: $worktree_path"
        exit 1
    fi
done <<EOF
$WORKTREE_PATHS
EOF

if [ "$WORKTREE_COUNT" -ge 1 ]; then
    echo "  [PASS] Successful coding worktrees were preserved ($WORKTREE_COUNT)"
else
    echo "  [FAIL] No preserved worktrees were reported"
    exit 1
fi

CURRENT_HEAD=$(git rev-parse HEAD)
if [ "$CURRENT_HEAD" = "$INITIAL_HEAD" ]; then
    echo "  [PASS] Main worktree HEAD was not merged"
else
    echo "  [FAIL] Main worktree HEAD changed from $INITIAL_HEAD to $CURRENT_HEAD"
    exit 1
fi

if python3 - <<'PY' "$RESULT_JSON" "$TMPDIR" >/dev/null
import json
import os
import subprocess
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
tmpdir = sys.argv[2]

for slot in data.get("slot_details", []):
    worktree_path = slot.get("worktree_path")
    branch = slot.get("branch")
    head_sha = slot.get("head_sha")
    if not worktree_path or not branch or not head_sha:
        raise SystemExit(1)
    if not os.path.isabs(worktree_path):
        worktree_path = os.path.join(tmpdir, worktree_path)
    actual_head = subprocess.check_output(
        ["git", "-C", worktree_path, "rev-parse", "HEAD"],
        text=True,
    ).strip()
    if actual_head != head_sha:
        raise SystemExit(1)
PY
then
    echo "  [PASS] Preserved worktrees remain valid git checkouts with matching head_sha metadata"
else
    echo "  [FAIL] Preserved worktree metadata does not resolve to live git checkouts"
    exit 1
fi
