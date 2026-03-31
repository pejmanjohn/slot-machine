#!/usr/bin/env bash
# Tier 2: Claude-host smoke check for mixed default + codex slots.
# Set SLOT_MACHINE_SKILL_DIR to point at an installed skill copy when validating sync.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

if ! command -v claude >/dev/null 2>&1; then
    echo "[SKIP] claude CLI not installed"
    exit 2
fi

if ! command -v codex >/dev/null 2>&1; then
    echo "[SKIP] codex CLI not installed"
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

echo "=== Claude Host + Codex Smoke Test ==="
echo "Skill dir: $SKILL_DIR"

SPEC_FILE="$SCRIPT_DIR/fixtures/tiny-spec.md"
TMPDIR=$(mktemp -d)
TRANSCRIPT_FILE=$(mktemp)
PYTEST_OUTPUT=$(mktemp)
KEEP_SMOKE_DIR="${SLOT_MACHINE_KEEP_SMOKE_DIR:-0}"

cleanup() {
    if [ "$KEEP_SMOKE_DIR" = "1" ]; then
        return
    fi
    rm -rf "$TMPDIR" "$TRANSCRIPT_FILE" "$PYTEST_OUTPUT"
}
trap cleanup EXIT

echo "Smoke repo: $TMPDIR"
echo "Transcript: $TRANSCRIPT_FILE"

cd "$TMPDIR"
git init -q
git config user.name "Slot Machine Codex Smoke"
git config user.email "slot-machine-codex-smoke@example.com"
mkdir -p src tests

cat > pyproject.toml <<'EOF'
[project]
name = "slot-machine-codex-smoke"
version = "0.1.0"

[tool.pytest.ini_options]
testpaths = ["tests"]
EOF

cat > src/__init__.py <<'EOF'
EOF

cat > tests/__init__.py <<'EOF'
EOF

git add -A
git commit -q -m "initial"

SPEC=$(cat "$SPEC_FILE")
PROMPT="/slot-machine with 2 slots: default, codex

Spec: $SPEC"

set +e
run_claude_to_file "$TRANSCRIPT_FILE" "$PROMPT" 1500 220 "$TMPDIR"
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

LATEST_RUN="$TMPDIR/.slot-machine/runs/latest"
RESULT_JSON="$LATEST_RUN/result.json"
VERDICT_FILE="$LATEST_RUN/verdict.md"
REVIEW_1="$LATEST_RUN/review-1.md"
REVIEW_2="$LATEST_RUN/review-2.md"

if [ -f "$RESULT_JSON" ]; then
    echo "  [PASS] result.json written"
else
    echo "  [FAIL] result.json missing at $RESULT_JSON"
    echo "$TRANSCRIPT_TEXT"
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
    echo "  [FAIL] Expected 2 successful slots, found $SLOTS_SUCCEEDED"
    echo "$TRANSCRIPT_TEXT"
    exit 1
fi

for artifact in "$REVIEW_1" "$REVIEW_2" "$VERDICT_FILE"; do
    if [ -s "$artifact" ]; then
        echo "  [PASS] Found artifact $(basename "$artifact")"
    else
        echo "  [FAIL] Missing artifact $artifact"
        echo "$TRANSCRIPT_TEXT"
        exit 1
    fi
done

assert_contains "$VERDICT_VALUE" "PICK\\|SYNTHESIZE" "Verdict is actionable"
assert_contains "$FINAL_REPORT" "Final Output\\|Verdict\\|Complete" "Final report present"

if (cd "$TMPDIR" && python3 -m pytest tests/ -v >"$PYTEST_OUTPUT" 2>&1); then
    echo "  [PASS] Final merged pytest suite passes"
else
    echo "  [FAIL] Final merged pytest suite does not pass"
    cat "$PYTEST_OUTPUT"
    exit 1
fi

echo "Artifacts:"
echo "  $REVIEW_1"
echo "  $REVIEW_2"
echo "  $VERDICT_FILE"
echo "  $RESULT_JSON"
