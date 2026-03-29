#!/usr/bin/env bash
# Tier 2 Smoke Test: Reviewer Phase
# Tests that the reviewer prompt produces a valid evidence-backed review
# when run headless via `claude -p`.
#
# Test plan:
#   1. Source test-helpers.sh for run_claude, assert_contains, etc.
#   2. Create a temporary git repo from the planted-bugs fixture
#   3. Run the fixture's pytest suite and capture the real pre-check output
#   4. Build a fake implementer report claiming DONE status
#   5. Read the Reviewer Prompt section from the active profile and fill in template variables:
#      - {{SPEC}}                <- tiny-spec.md contents
#      - {{IMPLEMENTER_REPORT}}  <- fake DONE report
#      - {{PRE_CHECK_RESULTS}}   <- real pytest output
#      - {{WORKTREE_PATH}}       <- path to the temp repo
#      - {{SLOT_NUMBER}}         <- 1
#      - {{APPROACH_HINT_USED}}  <- "Prioritize simplicity."
#   6. Call run_claude_to_file with the filled prompt (timeout ~300s, max-turns 50)
#   7. Assert the review contains the required sections and an evidence-backed
#      critical finding against the seeded concurrency bug
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

echo "=== Reviewer Smoke Test ==="
echo ""
echo "Test plan:"
echo "  1. Copy the planted-bugs fixture into a temp git repo"
echo "  2. Run the real pytest pre-check and capture its output"
echo "  3. Fill reviewer prompt template with tiny-spec + fake implementer report"
echo "  4. Run claude -p with filled prompt"
echo "  5. Assert: Review header and all required sections are present"
echo "  6. Assert: Critical/Important/Minor issue categories are present"
echo "  7. Assert: At least one critical issue cites src/token_bucket.py with race/lock evidence"
echo "  8. Assert: Verdict section includes contender and rationale fields"
echo ""

FIXTURE_DIR="$SCRIPT_DIR/fixtures/planted-bugs"
SPEC_FILE="$SCRIPT_DIR/fixtures/tiny-spec.md"
REVIEWER_TEMPLATE="$SKILL_DIR/profiles/coding/2-reviewer.md"
TMPDIR=$(mktemp -d)
OUTPUT_FILE=$(mktemp)
PRECHECK_FILE=$(mktemp)
trap 'rm -rf "$TMPDIR" "$OUTPUT_FILE" "$PRECHECK_FILE"' EXIT

cp -R "$FIXTURE_DIR"/. "$TMPDIR"/
find "$TMPDIR" \( -name __pycache__ -o -name .pytest_cache \) -prune -exec rm -rf {} +

cd "$TMPDIR"
git init -q
git config user.name "Slot Machine Smoke"
git config user.email "slot-machine-smoke@example.com"
git add -A
git commit -q -m "initial fixture"

if (cd "$TMPDIR" && python3 -m pytest tests/ -v >"$PRECHECK_FILE" 2>&1); then
    PRE_CHECK_RESULTS=$(cat "$PRECHECK_FILE")
    echo "  [PASS] Fixture pytest suite passes before review"
else
    echo "  [FAIL] Fixture pytest suite does not pass before review"
    cat "$PRECHECK_FILE"
    exit 1
fi

SPEC=$(cat "$SPEC_FILE")
PROMPT_TEMPLATE=$(cat "$REVIEWER_TEMPLATE")
IMPLEMENTER_REPORT=$(cat <<'EOF'
## Implementer Report

**Status:** DONE

**Files changed:**
- src/token_bucket.py
- tests/test_token_bucket.py

**Test results:**
- python3 -m pytest tests/ -v: 8 passed

**Summary:** Implemented the token bucket and added tests. All requirements are complete.
EOF
)
APPROACH_HINT_USED="Prioritize simplicity."

PROMPT=$(SPEC="$SPEC" \
IMPLEMENTER_REPORT="$IMPLEMENTER_REPORT" \
PRE_CHECK_RESULTS="$PRE_CHECK_RESULTS" \
WORKTREE_PATH="$TMPDIR" \
SLOT_NUMBER="1" \
APPROACH_HINT_USED="$APPROACH_HINT_USED" \
PROMPT_TEMPLATE="$PROMPT_TEMPLATE" \
python3 - <<'PY'
import os

prompt = os.environ["PROMPT_TEMPLATE"]
for key in (
    "SPEC",
    "IMPLEMENTER_REPORT",
    "PRE_CHECK_RESULTS",
    "WORKTREE_PATH",
    "SLOT_NUMBER",
    "APPROACH_HINT_USED",
):
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

assert_contains "$REPORT" "## Slot 1 Review" "Reviewer report header present"
assert_contains "$REPORT" "### Spec Compliance:" "Spec compliance section present"
assert_contains "$REPORT" "\\*\\*Requirements checked:\\*\\*" "Requirements checked section present"
assert_contains "$REPORT" "### Issues" "Issues section present"
assert_contains "$REPORT" "\\*\\*Critical:\\*\\*" "Critical issue category present"
assert_contains "$REPORT" "\\*\\*Important:\\*\\*" "Important issue category present"
assert_contains "$REPORT" "\\*\\*Minor:\\*\\*" "Minor issue category present"
assert_contains "$REPORT" "### Test Assessment" "Test assessment section present"
assert_contains "$REPORT" "\\*\\*Tests found:\\*\\*" "Tests found line present"
assert_contains "$REPORT" "### Strengths" "Strengths section present"
assert_contains "$REPORT" "### Approach Hint Influence" "Approach hint influence section present"
assert_contains "$REPORT" "### Verdict" "Verdict section present"
assert_contains "$REPORT" "Contender" "Contender field present"
assert_contains "$REPORT" "Why:" "Verdict rationale present"
assert_contains "$REPORT" "src/token_bucket.py:[0-9]" "Issue cites file and line evidence"
assert_contains "$REPORT" "TOCTOU\\|race condition\\|atomic\\|lock released between check and deduct" \
    "Reviewer identifies the seeded concurrency bug"
assert_contains "$REPORT" "What:" "Issue includes What explanation"
assert_contains "$REPORT" "Impact:" "Issue includes Impact explanation"
assert_contains "$REPORT" "Fix:" "Issue includes Fix suggestion"
