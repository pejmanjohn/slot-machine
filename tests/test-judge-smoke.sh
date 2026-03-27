#!/usr/bin/env bash
# Tier 2 Smoke Test: Judge Phase
# Tests that the judge prompt produces a valid verdict
# when run headless via `claude -p`.
#
# Test plan:
#   1. Source test-helpers.sh for run_claude, assert_contains, etc.
#   2. Read fixtures/sample-scorecards.md (two pre-written scorecards):
#      - Slot 1: 4.25/5 — solid, clean, well-tested, minor edge case gap
#      - Slot 2: 2.70/5 — over-engineered, CRITICAL dual-lock race condition
#   3. Create two temp worktree directories with minimal placeholder code
#      (judge needs paths but primarily relies on scorecards for this test)
#   4. Read the Judge Prompt section from the active profile and fill in template variables:
#      - {{SPEC}}            <- tiny-spec.md contents
#      - {{ALL_SCORECARDS}}  <- sample-scorecards.md contents
#      - {{WORKTREE_PATHS}}  <- paths to the two temp worktree dirs
#      - {{SLOT_COUNT}}      <- 2
#   5. Call run_claude with the filled prompt (timeout ~300s, max-turns 30)
#   6. Assert the output contains:
#      a. "Decision:" field present
#      b. Decision value is one of: PICK, SYNTHESIZE, NONE_ADEQUATE
#      c. Ranking table present (look for "Rank" and "Slot" headers)
#      d. "Reasoning" section present
#      e. "Confidence:" field present with HIGH, MEDIUM, or LOW value
#   7. Sanity check the decision quality:
#      - Slot 1 (4.25/5, no critical issues) vs Slot 2 (2.70/5, CRITICAL bug)
#      - Judge should PICK slot 1 (assert "PICK" and "slot.1" or "Slot 1")
#      - If judge picks slot 2 or NONE_ADEQUATE, the prompt has a problem
#   8. Cleanup temp directories

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Judge Smoke Test ==="
echo ""
echo "Test plan:"
echo "  1. Load sample-scorecards.md (Slot 1: 4.25/5 vs Slot 2: 2.70/5)"
echo "  2. Create temp worktree dirs with placeholder code"
echo "  3. Fill judge prompt template with tiny-spec + scorecards"
echo "  4. Run claude -p with filled prompt"
echo "  5. Assert: Decision field present (PICK/SYNTHESIZE/NONE_ADEQUATE)"
echo "  6. Assert: Ranking table present with Rank and Slot columns"
echo "  7. Assert: Reasoning section present"
echo "  8. Assert: Confidence field present (HIGH/MEDIUM/LOW)"
echo "  9. Sanity: Judge should PICK slot 1 (clear winner over slot 2)"
echo ""

echo "[SKIP] Requires headless claude -p execution"
exit 0
