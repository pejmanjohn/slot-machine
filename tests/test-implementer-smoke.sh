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
#      - {{TEST_COMMAND}}    <- "cd $TMPDIR && python -m pytest tests/ -v"
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

echo "[SKIP] Requires headless claude -p execution"
exit 0
