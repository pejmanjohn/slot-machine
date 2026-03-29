#!/usr/bin/env bash
# Tier 2 Smoke Test: Implementer Phase
# Tests that the implementer prompt produces a valid implementation report
# when run headless via `claude -p`.
#
# Test plan:
#   1. Source test-helpers.sh for run_claude, assert_contains, etc.
#   2. Create a temporary test project:
#      - git init a fresh directory
#      - Minimal Python project structure (src/, tests/, pytest config)
#   3. Read the tiny spec from fixtures/tiny-spec.md
#   4. Read the Implementer Prompt section from the active profile and fill in template variables:
#      - {{SPEC}}            <- tiny-spec.md contents
#      - {{APPROACH_HINT}}   <- "Use a simple class with threading.Lock for thread safety"
#      - {{PROJECT_CONTEXT}} <- "Fresh Python project. Use src/ for code, tests/ for tests."
#      - {{TEST_COMMAND}}    <- "cd $TMPDIR && python3 -m pytest tests/ -v"
#   5. Call run_claude with the filled prompt (timeout ~300s, max-turns 50)
#   6. Assert the output contains:
#      a. "Status:" field is present
#      b. Status value is one of: DONE, DONE_WITH_CONCERNS, BLOCKED, NEEDS_CONTEXT
#      c. "Files changed:" section is present
#      d. "Test results:" section is present
#      e. Implementation files were actually created in the temp dir
#         - At least one .py file in src/
#         - At least one .py file in tests/
#   7. Cleanup temp directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

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

echo "=== Implementer Smoke Test ==="
echo ""
echo "Test plan:"
echo "  1. Create temp project with git init + minimal Python setup"
echo "  2. Fill implementer prompt template with tiny-spec.md"
echo "  3. Run claude -p with filled prompt"
echo "  4. Assert: Status field present with valid value"
echo "  5. Assert: Files changed section present"
echo "  6. Assert: Test results section present"
echo "  7. Assert: .py files created in src/ and tests/"
echo ""

TMPDIR=$(mktemp -d)
OUTPUT_FILE=$(mktemp)
trap 'rm -rf "$TMPDIR" "$OUTPUT_FILE"' EXIT

cd "$TMPDIR"
git init -q
git config user.name "Slot Machine Smoke"
git config user.email "slot-machine-smoke@example.com"
mkdir -p src tests

cat > pyproject.toml <<'PYPROJECT'
[project]
name = "slot-machine-smoke"
version = "0.1.0"

[tool.pytest.ini_options]
testpaths = ["tests"]
PYPROJECT

cat > src/__init__.py <<'PY'
PY

cat > tests/__init__.py <<'PY'
PY

git add -A
git commit -q -m "initial"

SPEC=$(cat "$SCRIPT_DIR/fixtures/tiny-spec.md")
PROMPT_TEMPLATE=$(cat "$SKILL_DIR/profiles/coding/1-implementer.md")
APPROACH_HINT="Use a simple class with threading.Lock for thread safety."
PROJECT_CONTEXT="Fresh Python project. Create implementation in src/ and pytest tests in tests/. You are already in the repository root."
TEST_COMMAND="python3 -m pytest tests/ -v"

PROMPT=$(SPEC="$SPEC" \
APPROACH_HINT="$APPROACH_HINT" \
PROJECT_CONTEXT="$PROJECT_CONTEXT" \
TEST_COMMAND="$TEST_COMMAND" \
PROMPT_TEMPLATE="$PROMPT_TEMPLATE" \
python3 - <<'PY'
import os

prompt = os.environ["PROMPT_TEMPLATE"]
for key in ("SPEC", "APPROACH_HINT", "PROJECT_CONTEXT", "TEST_COMMAND"):
    prompt = prompt.replace("{{" + key + "}}", os.environ[key])
print(prompt)
PY
)

set +e
run_claude_to_file "$OUTPUT_FILE" "$PROMPT" 300 50 "$TMPDIR"
CLAUDE_RC=$?
set -e

OUTPUT=$(cat "$OUTPUT_FILE")
REPORT=$(extract_result_text "$OUTPUT_FILE")

if [ "$CLAUDE_RC" -eq 2 ]; then
    echo "$OUTPUT"
    exit 2
fi

if [ "$CLAUDE_RC" -ne 0 ]; then
    echo "  [FAIL] claude -p exited with code $CLAUDE_RC"
    echo "$OUTPUT"
    exit 1
fi

assert_contains "$REPORT" "## Implementer Report" "Implementer report header present"
assert_contains "$REPORT" "\\*\\*Status:\\*\\*" "Status field present"
assert_contains "$REPORT" "DONE\\|DONE_WITH_CONCERNS\\|BLOCKED\\|NEEDS_CONTEXT" "Status value valid"
assert_contains "$REPORT" "\\*\\*Files changed:\\*\\*" "Files changed section present"
assert_contains "$REPORT" "\\*\\*Test results:\\*\\*" "Test results section present"

if ls "$TMPDIR"/src/*.py >/dev/null 2>&1; then
    echo "  [PASS] Python implementation files created in src/"
else
    echo "  [FAIL] No Python implementation files created in src/"
    exit 1
fi

if ls "$TMPDIR"/tests/*.py >/dev/null 2>&1; then
    echo "  [PASS] Python test files created in tests/"
else
    echo "  [FAIL] No Python test files created in tests/"
    exit 1
fi

if (cd "$TMPDIR" && python3 -m pytest tests/ -v >/tmp/slot-machine-implementer-smoke-pytest.txt 2>&1); then
    echo "  [PASS] Generated pytest suite passes"
else
    echo "  [FAIL] Generated pytest suite does not pass"
    cat /tmp/slot-machine-implementer-smoke-pytest.txt
    exit 1
fi
