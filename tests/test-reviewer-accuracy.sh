#!/usr/bin/env bash
# Tier 4 Quality Test: Reviewer Accuracy (Precision & Recall)
# Tests the reviewer's ability to find planted bugs in a known-buggy implementation.
#
# Background:
#   We need an objective way to measure reviewer quality. This test uses the
#   "Code Review Bench" approach: plant KNOWN bugs in an implementation, run
#   the reviewer, and check if it finds them.
#
# Test plan:
#   1. Source test-helpers.sh for run_claude, assert_contains, etc.
#   2. Point at the planted-bug implementation in tests/fixtures/planted-bugs/
#   3. Read golden issues from tests/fixtures/planted-bugs/golden-issues.json
#   4. Build the reviewer prompt by filling the Reviewer Prompt section from the active profile:
#      - {{SPEC}}                = tiny-spec.md contents
#      - {{IMPLEMENTER_REPORT}}  = fake DONE report
#      - {{WORKTREE_PATH}}       = planted-bugs directory
#      - {{SLOT_NUMBER}}         = 1
#      - {{PRE_CHECK_RESULTS}}   = passing test output
#      - {{APPROACH_HINT_USED}}  = "Prioritize simplicity"
#   5. Dispatch the reviewer via run_claude with the filled prompt
#   6. Parse the reviewer output and check against golden issues:
#
#      Recall checks (did it find each golden bug?):
#        BUG-1 (Critical): TOCTOU race condition
#          Look for: "race", "TOCTOU", "lock", "atomic" in critical issues
#        BUG-2 (Important): time.time() vs time.monotonic()
#          Look for: "time.time", "monotonic", "clock" in issues
#        BUG-3 (Minor): Missing __repr__
#          Look for: "repr", "__repr__", "debug" in minor issues
#
#      Precision check:
#        Count total issues reported. If significantly more than 3,
#        some may be false positives.
#
#      Severity accuracy:
#        Check that BUG-1 is classified as Critical (not Important/Minor).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

FIXTURE_DIR="$SCRIPT_DIR/fixtures/planted-bugs"
GOLDEN_ISSUES="$FIXTURE_DIR/golden-issues.json"
SPEC_FILE="$SCRIPT_DIR/fixtures/tiny-spec.md"
REVIEWER_TEMPLATE="$SKILL_DIR/profiles/coding/2-reviewer.md"  # Reviewer prompt file

echo "=== Reviewer Accuracy Test (Planted Bugs) ==="
echo ""
echo "Test plan:"
echo "  1. Load planted-bug fixture from $FIXTURE_DIR"
echo "  2. Read 3 golden issues from golden-issues.json"
echo "  3. Fill reviewer prompt template with:"
echo "     - SPEC = tiny-spec.md"
echo "     - IMPLEMENTER_REPORT = fake DONE status"
echo "     - WORKTREE_PATH = $FIXTURE_DIR"
echo "     - SLOT_NUMBER = 1"
echo "     - PRE_CHECK_RESULTS = 8 tests passing"
echo "     - APPROACH_HINT_USED = Prioritize simplicity"
echo "  4. Run reviewer via claude -p"
echo "  5. Recall: Check for BUG-1 (TOCTOU race, Critical)"
echo "  6. Recall: Check for BUG-2 (time.time vs monotonic, Important)"
echo "  7. Recall: Check for BUG-3 (missing __repr__, Minor)"
echo "  8. Precision: Count total issues (expect ~3, flag if >>3)"
echo "  9. Severity accuracy: BUG-1 should be Critical"
echo ""

# --- Validate fixture exists ---
if [ ! -f "$GOLDEN_ISSUES" ]; then
    echo "[FAIL] Golden issues file not found: $GOLDEN_ISSUES"
    exit 1
fi
if [ ! -f "$FIXTURE_DIR/src/token_bucket.py" ]; then
    echo "[FAIL] Planted-bug implementation not found: $FIXTURE_DIR/src/token_bucket.py"
    exit 1
fi
if [ ! -f "$FIXTURE_DIR/tests/test_token_bucket.py" ]; then
    echo "[FAIL] Planted-bug tests not found: $FIXTURE_DIR/tests/test_token_bucket.py"
    exit 1
fi

echo "[OK] Fixture files found"
echo ""

# --- Build the reviewer prompt ---
# (This section is ready but skipped until headless claude -p is available)

# SPEC=$(cat "$SPEC_FILE")
# IMPLEMENTER_REPORT="Status: DONE. Implemented token bucket with tests. All tests pass."
# WORKTREE_PATH="$FIXTURE_DIR"
# SLOT_NUMBER="1"
# PRE_CHECK_RESULTS="Tests: 8 passed. Files: src/token_bucket.py, tests/test_token_bucket.py"
# APPROACH_HINT_USED="Prioritize simplicity"
#
# PROMPT=$(cat "$REVIEWER_TEMPLATE")
# PROMPT="${PROMPT//\{\{SPEC\}\}/$SPEC}"
# PROMPT="${PROMPT//\{\{IMPLEMENTER_REPORT\}\}/$IMPLEMENTER_REPORT}"
# PROMPT="${PROMPT//\{\{WORKTREE_PATH\}\}/$WORKTREE_PATH}"
# PROMPT="${PROMPT//\{\{SLOT_NUMBER\}\}/$SLOT_NUMBER}"
# PROMPT="${PROMPT//\{\{PRE_CHECK_RESULTS\}\}/$PRE_CHECK_RESULTS}"
# PROMPT="${PROMPT//\{\{APPROACH_HINT_USED\}\}/$APPROACH_HINT_USED}"
#
# --- Run the reviewer ---
# OUTPUT=$(run_claude "$PROMPT" 600 50)
#
# --- Recall checks ---
# echo "Recall checks:"
# assert_contains "$OUTPUT" "race\|TOCTOU\|lock.*outside\|atomic" "BUG-1 detected (TOCTOU race)"
# assert_contains "$OUTPUT" "time\.time\|monotonic\|clock" "BUG-2 detected (time.time vs monotonic)"
# assert_contains "$OUTPUT" "repr\|__repr__\|debug.*string" "BUG-3 detected (missing __repr__)"
#
# --- Severity accuracy ---
# echo ""
# echo "Severity accuracy:"
# # Extract the Critical section and check BUG-1 keywords appear there
# CRITICAL_SECTION=$(echo "$OUTPUT" | sed -n '/\*\*Critical\*\*/,/\*\*Important\*\*/p')
# assert_contains "$CRITICAL_SECTION" "race\|TOCTOU\|lock.*outside\|atomic" "BUG-1 classified as Critical"
#
# --- Precision check ---
# echo ""
# echo "Precision check:"
# ISSUE_COUNT=$(echo "$OUTPUT" | grep -c '^\s*[0-9]\+\.\s*\*\*' || echo "0")
# echo "  Total issues reported: $ISSUE_COUNT"
# if [ "$ISSUE_COUNT" -le 5 ]; then
#     echo "  [PASS] Reasonable issue count (<=5)"
# else
#     echo "  [WARN] High issue count ($ISSUE_COUNT) — possible false positives"
# fi

echo "[SKIP] Requires headless claude -p and planted-bugs fixture"
exit 0
