#!/usr/bin/env bash
# Tier 2: Claude-host smoke check for a local profile that extends coding with a mixed 4-slot matrix.
# Set SLOT_MACHINE_SKILL_DIR to point at an installed skill copy when validating sync.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

HOST_FILTER="${SLOT_MACHINE_TEST_HOST_FILTER:-all}"
case "$HOST_FILTER" in
    ""|all|claude) ;;
    codex)
        echo "[SKIP] test-claude-host-profile-inheritance-smoke.sh requires claude as the primary host"
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

echo "=== Claude Host Local-Profile Inheritance Smoke Test ==="
echo "Skill dir: $SKILL_DIR"
echo "Host filter: $HOST_FILTER"

SPEC_FILE="$SCRIPT_DIR/fixtures/tiny-spec.md"
TMPDIR=$(mktemp -d)
TRANSCRIPT_FILE=$(mktemp)
PYTEST_OUTPUT=$(mktemp)
KEEP_SMOKE_DIR="${SLOT_MACHINE_KEEP_SMOKE_DIR:-0}"
SETUP_TIMEOUT_SECONDS="${SLOT_MACHINE_SETUP_TIMEOUT_SECONDS:-180}"

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
git config user.name "Slot Machine Profile Inheritance Smoke"
git config user.email "slot-machine-profile-inheritance@example.com"
mkdir -p src tests profiles/blog-post-exp4

cat > pyproject.toml <<'EOF'
[project]
name = "slot-machine-profile-inheritance-smoke"
version = "0.1.0"

[tool.pytest.ini_options]
testpaths = ["tests"]
EOF

cat > src/__init__.py <<'EOF'
EOF

cat > tests/__init__.py <<'EOF'
EOF

cat > profiles/blog-post-exp4/0-profile.md <<'EOF'
---
name: blog-post-exp4
description: Local smoke profile that overrides only the profile config and inherits the built-in coding prompts.
extends: coding
---

## Approach Hints

1. "Use the simplest possible approach and inherit all prompt behavior from the built-in coding profile."
EOF

cat > CLAUDE.md <<'EOF'
slot-machine-profile: blog-post-exp4
quiet: true
cleanup: false
slot-machine-slots:
  - default
  - codex
  - /superpowers:test-driven-development
  - /superpowers:test-driven-development + codex
EOF

git add -A
git commit -q -m "initial"

SPEC=$(cat "$SPEC_FILE")
PROMPT="/slot-machine

Spec: $SPEC"

run_claude_to_file "$TRANSCRIPT_FILE" "$PROMPT" 1800 260 "$TMPDIR" &
CLAUDE_PID=$!

SETUP_DEADLINE=$((SECONDS + SETUP_TIMEOUT_SECONDS))
SAW_SLOT_STATE=0
SAW_CLAUDE_STATE=0

while kill -0 "$CLAUDE_PID" >/dev/null 2>&1; do
    if [ -d "$TMPDIR/.slot-machine" ]; then
        SAW_SLOT_STATE=1
    fi
    if [ -d "$TMPDIR/.claude" ]; then
        SAW_CLAUDE_STATE=1
    fi

    if [ "$SAW_SLOT_STATE" -eq 1 ] && [ "$SAW_CLAUDE_STATE" -eq 1 ]; then
        break
    fi

    if [ "$SECONDS" -ge "$SETUP_DEADLINE" ]; then
        break
    fi

    sleep 2
done

if ! wait "$CLAUDE_PID"; then
    CLAUDE_RC=$?
else
    CLAUDE_RC=0
fi

TRANSCRIPT_TEXT=$(cat "$TRANSCRIPT_FILE")
FINAL_REPORT=$(extract_result_text "$TRANSCRIPT_FILE")
TOOL_USE_COUNT=$(grep -c '"type":"tool_use"' "$TRANSCRIPT_FILE" 2>/dev/null || echo "0")
EARLY_HOST_FAILURE=0
if [ "$TOOL_USE_COUNT" -eq 0 ] && grep -Eq '"subtype":"api_retry"|authentication_failed|Failed to authenticate' "$TRANSCRIPT_FILE"; then
    EARLY_HOST_FAILURE=1
fi

if [ "$SAW_SLOT_STATE" -eq 1 ]; then
    echo "  [PASS] .slot-machine state created during setup"
elif [ "$EARLY_HOST_FAILURE" -eq 1 ]; then
    echo "[SKIP] Claude host became unavailable before setup could begin"
    echo "$TRANSCRIPT_TEXT"
    exit 2
else
    echo "  [FAIL] .slot-machine state was not created within the setup window"
    echo "$TRANSCRIPT_TEXT"
    exit 1
fi

if [ "$SAW_CLAUDE_STATE" -eq 1 ]; then
    echo "  [PASS] .claude state created during setup"
elif [ "$EARLY_HOST_FAILURE" -eq 1 ]; then
    echo "[SKIP] Claude host became unavailable before worktree setup could begin"
    echo "$TRANSCRIPT_TEXT"
    exit 2
else
    echo "  [FAIL] .claude state was not created within the setup window"
    echo "$TRANSCRIPT_TEXT"
    exit 1
fi

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

if [ -f "$RESULT_JSON" ]; then
    echo "  [PASS] result.json written"
else
    echo "  [FAIL] result.json missing at $RESULT_JSON"
    echo "$TRANSCRIPT_TEXT"
    exit 1
fi

if [ -s "$VERDICT_FILE" ]; then
    echo "  [PASS] verdict.md written"
else
    echo "  [FAIL] verdict.md missing at $VERDICT_FILE"
    echo "$TRANSCRIPT_TEXT"
    exit 1
fi

SLOTS_TOTAL=$(python3 - <<'PY' "$RESULT_JSON"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data.get("slots_total", 0))
PY
)

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

REVIEW_COUNT=$(find "$LATEST_RUN" -maxdepth 1 -name 'review-*.md' | wc -l | tr -d ' ')

if [ "$SLOTS_TOTAL" -eq 4 ]; then
    echo "  [PASS] Result recorded the 4-slot matrix"
else
    echo "  [FAIL] Expected 4 total slots, found $SLOTS_TOTAL"
    echo "$TRANSCRIPT_TEXT"
    exit 1
fi

if [ "$SLOTS_SUCCEEDED" -ge 2 ]; then
    echo "  [PASS] At least 2 slots succeeded ($SLOTS_SUCCEEDED)"
else
    echo "  [FAIL] Expected at least 2 successful slots, found $SLOTS_SUCCEEDED"
    echo "$TRANSCRIPT_TEXT"
    exit 1
fi

if [ "$REVIEW_COUNT" -ge 2 ]; then
    echo "  [PASS] Review artifacts written for successful slots ($REVIEW_COUNT)"
else
    echo "  [FAIL] Expected at least 2 review artifacts, found $REVIEW_COUNT"
    echo "$TRANSCRIPT_TEXT"
    exit 1
fi

assert_contains "$VERDICT_VALUE" "PICK\\|SYNTHESIZE\\|NONE_ADEQUATE" "Verdict recorded"
assert_contains "$FINAL_REPORT" "Final Output\\|Verdict\\|Complete" "Final report present"

if (cd "$TMPDIR" && python3 -m pytest tests/ -v >"$PYTEST_OUTPUT" 2>&1); then
    echo "  [PASS] Final merged pytest suite passes"
else
    echo "  [FAIL] Final merged pytest suite does not pass"
    cat "$PYTEST_OUTPUT"
    exit 1
fi

echo "Artifacts:"
echo "  $VERDICT_FILE"
echo "  $RESULT_JSON"
