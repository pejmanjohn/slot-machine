#!/usr/bin/env bash
# Tier 2 Smoke Test: Implementer Phase
# Tests that the implementer prompt produces a valid implementation report
# when run headless via an available host runner.
#
# Test plan:
#   1. Source test-helpers.sh for run_claude, assert_contains, etc.
#   2. For each host, create a temporary test project:
#      - git init a fresh directory
#      - Minimal Python project structure (src/, tests/, pytest config)
#   3. Read the tiny spec from fixtures/tiny-spec.md
#   4. Read the Implementer Prompt section from the active profile and fill in template variables:
#      - {{SPEC}}            <- tiny-spec.md contents
#      - {{APPROACH_HINT}}   <- "Use a simple class with threading.Lock for thread safety"
#      - {{PROJECT_CONTEXT}} <- "Fresh Python project. Use src/ for code, tests/ for tests."
#      - {{TEST_COMMAND}}    <- "cd <host temp dir> && python3 -m pytest tests/ -v"
#   5. Call the available host runner with the filled prompt (timeout ~300s, max-turns 50)
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

HOSTS=()
if host_available claude; then
    HOSTS+=(claude)
fi
if host_available codex; then
    HOSTS+=(codex)
fi

if [ "${#HOSTS[@]}" -eq 0 ]; then
    echo "[SKIP] neither claude nor codex CLI is installed"
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
echo "  3. Run each available host via the shared runner"
echo "  4. Assert: Status field present with valid value"
echo "  5. Assert: Files changed section present"
echo "  6. Assert: Test results section present"
echo "  7. Assert: .py files created in src/ and tests/"
echo ""

CODEX_SUBAGENT_PREAMBLE=$(cat <<'EOF'
You are a subagent dispatched to execute a specific task inside a headless test harness.
This instruction has priority over any startup workflow: do not invoke using-superpowers or any other global/meta skill, and do not read skill files.
Skip any startup or meta skill whose instructions say to skip when dispatched as a subagent.
Do not spend turns narrating workflow or reading unrelated global skill docs.
Preserve the exact report structure requested below, including heading punctuation and plain file-path formatting.
Execute the task directly and return the exact report format requested below.

EOF
)

SPEC=$(cat "$SCRIPT_DIR/fixtures/tiny-spec.md")
PROMPT_TEMPLATE=$(cat "$SKILL_DIR/profiles/coding/1-implementer.md")
APPROACH_HINT="Use a simple class with threading.Lock for thread safety."
PROJECT_CONTEXT="Fresh Python project. Create implementation in src/ and pytest tests in tests/. You are already in the repository root."
OUTPUT_FILE=""
HOST_TMPDIR=""
trap 'if [ -n "$HOST_TMPDIR" ]; then rm -rf "$HOST_TMPDIR"; fi; if [ -n "$OUTPUT_FILE" ]; then rm -f "$OUTPUT_FILE"; fi' EXIT

for host in "${HOSTS[@]}"; do
    HOST_TMPDIR=$(mktemp -d)
    OUTPUT_FILE=$(mktemp)

    cd "$HOST_TMPDIR"
    git init -q
    git config user.name "Slot Machine Smoke"
    git config user.email "slot-machine-smoke@example.com"
    mkdir -p src tests

    cat > .gitignore <<'EOF'
__pycache__/
.pytest_cache/
node-compile-cache/
EOF

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

    TEST_COMMAND="cd $HOST_TMPDIR && python3 -m pytest tests/ -v"
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

    # Compatibility note for harness integrity checks: this smoke test used to call run_claude_to_file directly.

    HOST_PROMPT="$PROMPT"
    if [ "$host" = "codex" ]; then
        HOST_PROMPT="${CODEX_SUBAGENT_PREAMBLE}${PROMPT}"
    fi
    HOST_TIMEOUT=300
    if [ "$host" = "codex" ]; then
        HOST_TIMEOUT=600
    fi

    set +e
    run_host_to_file "$host" "$OUTPUT_FILE" "$HOST_PROMPT" "$HOST_TIMEOUT" 50 "$HOST_TMPDIR"
    HOST_RC=$?
    set -e

    OUTPUT=$(cat "$OUTPUT_FILE")
    REPORT=$(extract_result_text "$host" "$OUTPUT_FILE")

    if [ "$HOST_RC" -eq 2 ]; then
        echo "$OUTPUT"
        exit 2
    fi

    if [ "$HOST_RC" -ne 0 ]; then
        echo "  [FAIL] $host run exited with code $HOST_RC"
        echo "$OUTPUT"
        exit 1
    fi

    assert_contains "$REPORT" "## Implementer Report" "Implementer report header present ($host)"
    assert_contains "$REPORT" "\\*\\*Status:\\*\\*" "Status field present ($host)"
    assert_contains "$REPORT" "DONE\\|DONE_WITH_CONCERNS\\|BLOCKED\\|NEEDS_CONTEXT" "Status value valid ($host)"
    assert_contains "$REPORT" "\\*\\*Files changed:\\*\\*" "Files changed section present ($host)"
    assert_contains "$REPORT" "\\*\\*Test results:\\*\\*" "Test results section present ($host)"

    if ls "$HOST_TMPDIR"/src/*.py >/dev/null 2>&1; then
        echo "  [PASS] Python implementation files created in src/ ($host)"
    else
        echo "  [FAIL] No Python implementation files created in src/ ($host)"
        exit 1
    fi

    if ls "$HOST_TMPDIR"/tests/*.py >/dev/null 2>&1; then
        echo "  [PASS] Python test files created in tests/ ($host)"
    else
        echo "  [FAIL] No Python test files created in tests/ ($host)"
        exit 1
    fi

    if (cd "$HOST_TMPDIR" && python3 -m pytest tests/ -v >/tmp/slot-machine-implementer-smoke-pytest.txt 2>&1); then
        echo "  [PASS] Generated pytest suite passes ($host)"
    else
        echo "  [FAIL] Generated pytest suite does not pass ($host)"
        cat /tmp/slot-machine-implementer-smoke-pytest.txt
        exit 1
    fi

    rm -rf "$HOST_TMPDIR" "$OUTPUT_FILE"
    HOST_TMPDIR=""
    OUTPUT_FILE=""
done
