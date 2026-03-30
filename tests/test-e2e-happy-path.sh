#!/usr/bin/env bash
# Tier 3: Full E2E integration test — happy path
# Runs a real slot-machine pipeline end-to-end on a temporary Python project
# and validates the transcript, run artifacts, merged output, and cleanup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

TEST_HOST="${TEST_HOST:-auto}"
CODEX_CLAUDE_BRIDGE_READY=0
if [ "$TEST_HOST" = "auto" ]; then
    if host_available codex && codex_can_host_claude_slots; then
        TEST_HOST="codex"
        CODEX_CLAUDE_BRIDGE_READY=1
    elif host_available claude; then
        TEST_HOST="claude"
    else
        echo "[SKIP] neither claude nor codex CLI is installed"
        exit 2
    fi
elif [ "$TEST_HOST" = "codex" ]; then
    if ! host_available claude; then
        echo "[SKIP] codex-hosted E2E requires claude CLI for explicit external slots"
        exit 2
    fi
    if codex_can_host_claude_slots; then
        CODEX_CLAUDE_BRIDGE_READY=1
    else
        echo "[SKIP] codex-hosted E2E requires a working Codex-to-Claude headless bridge"
        exit 2
    fi
elif ! host_available "$TEST_HOST"; then
    echo "[SKIP] $TEST_HOST CLI not installed"
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

echo "=== E2E Happy Path Test ==="
echo ""
echo "Test plan:"
echo "  1. Create a temp Python repo with an initial git commit"
echo "  2. Run slot-machine against the tiny spec using the selected host path"
echo "  3. Assert transcript sanity: non-empty, host dispatches"
echo "  4. Assert run artifacts: result.json, review-*.md, and verdict output"
echo "  5. Assert final merged project contains implementation and tests"
echo "  6. Assert generated pytest suite passes"
echo "  7. Assert worktrees are cleaned up"
echo ""

SPEC_FILE="$SCRIPT_DIR/fixtures/tiny-spec.md"
SLOT_COUNT=2
TMPDIR=$(mktemp -d)
TEST_BIN="$TMPDIR/.test-bin"
TRANSCRIPT_FILE=$(mktemp)
PYTEST_OUTPUT=$(mktemp)
trap 'rm -rf "$TMPDIR" "$TRANSCRIPT_FILE" "$PYTEST_OUTPUT"' EXIT

cd "$TMPDIR"
git init -q
git config user.name "Slot Machine E2E"
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

SPEC=$(cat "$SPEC_FILE")
SKILL_TRIGGER="/slot-machine"
if [ "$TEST_HOST" = "codex" ]; then
    SKILL_TRIGGER='$slot-machine'
fi

if [ "$TEST_HOST" = "codex" ]; then
    SKILL_REQUEST=$(cat <<EOF
$SKILL_TRIGGER with $SLOT_COUNT slots:
  slot 1: claude
  slot 2: claude
EOF
)
    SKILL_BODY=$(cat "$SKILL_DIR/SKILL.md")
    PROMPT=$(printf 'Base directory for this skill: %s\n\n%s\n\n%s\n\nSpec: %s' \
        "$SKILL_DIR" "$SKILL_BODY" "$SKILL_REQUEST" "$SPEC")
else
    SKILL_REQUEST="$SKILL_TRIGGER with $SLOT_COUNT slots"
    PROMPT=$(printf '%s\n\nSpec: %s' "$SKILL_REQUEST" "$SPEC")
fi

set +e
run_host_to_file "$TEST_HOST" "$TRANSCRIPT_FILE" "$PROMPT" 1200 200 "$TMPDIR"
HOST_RC=$?
set -e

TRANSCRIPT_TEXT=$(cat "$TRANSCRIPT_FILE")
FINAL_REPORT=$(extract_result_text "$TEST_HOST" "$TRANSCRIPT_FILE")
DISPATCH_EVENTS=$(count_dispatch_events "$TEST_HOST" "$TRANSCRIPT_FILE")

if [ "$HOST_RC" -eq 2 ]; then
    echo "$TRANSCRIPT_TEXT"
    exit 2
fi

if [ "$HOST_RC" -ne 0 ]; then
    echo "  [FAIL] $TEST_HOST exited with code $HOST_RC"
    echo "$TRANSCRIPT_TEXT"
    exit 1
fi

if [ ! -s "$TRANSCRIPT_FILE" ]; then
    echo "  [FAIL] Transcript is empty"
    exit 1
fi

echo "  [PASS] Transcript captured"
if [ "$DISPATCH_EVENTS" -ge 3 ]; then
    echo "  [PASS] Transcript includes multiple dispatch events ($DISPATCH_EVENTS)"
else
    echo "  [FAIL] Expected multiple dispatch events, found $DISPATCH_EVENTS"
    exit 1
fi

if printf '%s' "$FINAL_REPORT" | grep -Eq "Verdict|Final Output|Complete"; then
    echo "  [PASS] Final report includes a completion summary"
elif [ -n "$FINAL_REPORT" ]; then
    echo "  [PASS] Final report text captured"
else
    echo "  [PASS] Selected host omitted final report text; relying on run artifacts"
fi

LATEST_RUN="$TMPDIR/.slot-machine/runs/latest"
RESULT_JSON="$LATEST_RUN/result.json"
VERDICT_FILE="$LATEST_RUN/verdict.md"

if [ -f "$RESULT_JSON" ]; then
    echo "  [PASS] result.json written to latest run dir"
else
    echo "  [FAIL] result.json missing at $RESULT_JSON"
    exit 1
fi

SLOTS_SUCCEEDED=$(python3 - <<'PY' "$RESULT_JSON"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data.get("slots_succeeded", 0))
PY
)
VERDICT_VALUE=$(python3 - <<'PY' "$RESULT_JSON"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data.get("verdict", "UNKNOWN"))
PY
)

if [ "$SLOTS_SUCCEEDED" -ge 2 ]; then
    echo "  [PASS] At least 2 slots succeeded ($SLOTS_SUCCEEDED)"
else
    echo "  [FAIL] Need at least 2 successful slots, found $SLOTS_SUCCEEDED"
    exit 1
fi

if echo "$VERDICT_VALUE" | grep -Eq "PICK|SYNTHESIZE"; then
    echo "  [PASS] Verdict is actionable ($VERDICT_VALUE)"
else
    echo "  [FAIL] Unexpected verdict value: $VERDICT_VALUE"
    exit 1
fi

if [ -f "$VERDICT_FILE" ]; then
    echo "  [PASS] verdict.md written to latest run dir"
    VERDICT_LENGTH=$(wc -c <"$VERDICT_FILE" | tr -d ' ')
    if [ "$VERDICT_LENGTH" -ge 40 ]; then
        echo "  [PASS] Judge verdict file is non-empty and substantive"
    else
        echo "  [FAIL] Judge verdict is unexpectedly short ($VERDICT_LENGTH chars)"
        exit 1
    fi
else
    assert_contains "$FINAL_REPORT" "Verdict\\|PICK\\|SYNTHESIZE" \
        "Final report carries the judge verdict when verdict.md is absent"
fi

shopt -s nullglob
review_files=("$LATEST_RUN"/review-*.md)
shopt -u nullglob

if [ "${#review_files[@]}" -eq "$SLOTS_SUCCEEDED" ]; then
    echo "  [PASS] Review artifact count matches successful slots (${#review_files[@]})"
else
    echo "  [FAIL] Expected $SLOTS_SUCCEEDED review artifacts, found ${#review_files[@]}"
    exit 1
fi

for review_file in "${review_files[@]}"; do
    REVIEW_TEXT=$(cat "$review_file")
    assert_contains "$REVIEW_TEXT" "## Slot" "$(basename "$review_file") has slot review header"
    assert_contains "$REVIEW_TEXT" "Spec Compliance:\\|### Spec Compliance:" \
        "$(basename "$review_file") has spec compliance summary"
    assert_contains "$REVIEW_TEXT" "Critical:\\|\\*\\*Critical\\*\\*" \
        "$(basename "$review_file") records critical issue count"
    assert_contains "$REVIEW_TEXT" "Important:\\|\\*\\*Important\\*\\*" \
        "$(basename "$review_file") records important issue count"
    assert_contains "$REVIEW_TEXT" "Minor:\\|\\*\\*Minor\\*\\*" \
        "$(basename "$review_file") records minor issue count"
done

if find "$TMPDIR/src" -maxdepth 1 -type f -name '*.py' ! -name '__init__.py' | grep -q .; then
    echo "  [PASS] Implementation files exist in src/"
else
    echo "  [FAIL] No implementation files created in src/"
    exit 1
fi

if find "$TMPDIR/tests" -maxdepth 1 -type f -name '*.py' ! -name '__init__.py' | grep -q .; then
    echo "  [PASS] Test files exist in tests/"
else
    echo "  [FAIL] No test files created in tests/"
    exit 1
fi

if (cd "$TMPDIR" && python3 -m pytest tests/ -v >"$PYTEST_OUTPUT" 2>&1); then
    echo "  [PASS] Final merged pytest suite passes"
else
    echo "  [FAIL] Final merged pytest suite does not pass"
    cat "$PYTEST_OUTPUT"
    exit 1
fi

WORKTREE_COUNT=$(cd "$TMPDIR" && git worktree list 2>/dev/null | wc -l | tr -d ' ')
if [ "$WORKTREE_COUNT" -le 1 ]; then
    echo "  [PASS] Worktrees cleaned up ($WORKTREE_COUNT remaining)"
else
    echo "  [FAIL] Worktrees not cleaned up ($WORKTREE_COUNT remaining)"
    exit 1
fi
