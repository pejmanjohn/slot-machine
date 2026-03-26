#!/usr/bin/env bash
# Tier 2 Smoke Test: Reviewer Phase
# Tests that the reviewer prompt produces a valid scorecard
# when run headless via `claude -p`.
#
# Test plan:
#   1. Source test-helpers.sh for run_claude, assert_contains, etc.
#   2. Create a temporary directory with a known implementation:
#      - git init, commit a pre-built token bucket implementation
#      - Include src/rate_limiter.py with a simple TokenBucket class
#      - Include tests/test_rate_limiter.py with basic passing tests
#   3. Build a fake implementer report claiming DONE status
#   4. Read slot-reviewer-prompt.md and fill in template variables:
#      - {{SPEC}}               <- tiny-spec.md contents
#      - {{IMPLEMENTER_REPORT}} <- the fake implementer report
#      - {{WORKTREE_PATH}}      <- path to the temp dir with code
#      - {{SLOT_NUMBER}}        <- 1
#   5. Call run_claude with the filled prompt (timeout ~300s, max-turns 50)
#   6. Assert the output contains:
#      a. Scorecard header: "Slot 1 Scorecard"
#      b. All 6 scoring criteria with X/5 format:
#         - "Spec Compliance" with score pattern [1-5]/5
#         - "Correctness" with score pattern [1-5]/5
#         - "Test Quality" with score pattern [1-5]/5
#         - "Code Quality" with score pattern [1-5]/5
#         - "Simplicity" with score pattern [1-5]/5
#         - "Architecture" with score pattern [1-5]/5
#      c. "Weighted Score:" with X.X/5 format
#      d. "Issues" section present
#      e. Issue severity labels: at least one of CRITICAL, IMPORTANT, or MINOR
#      f. "Verdict" section present
#   7. Cleanup temp directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Reviewer Smoke Test ==="
echo ""
echo "Test plan:"
echo "  1. Create temp dir with pre-built token bucket implementation"
echo "  2. Build fake implementer report (DONE status)"
echo "  3. Fill reviewer prompt template with tiny-spec + fake report"
echo "  4. Run claude -p with filled prompt"
echo "  5. Assert: Scorecard header present (Slot 1 Scorecard)"
echo "  6. Assert: All 6 criteria scored with X/5 format"
echo "  7. Assert: Weighted Score present with X.X/5 format"
echo "  8. Assert: Issues section with CRITICAL/IMPORTANT/MINOR labels"
echo "  9. Assert: Verdict section present"
echo ""

echo "[SKIP] Requires headless claude -p execution"
exit 0
