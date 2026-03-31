#!/usr/bin/env bash
# Tier 2 Smoke Test: Reviewer Phase
# Tests that the reviewer prompt produces a valid evidence-backed review
# when run headless via an available host runner.
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
#   6. Call the available host runner with the filled prompt (timeout ~300s, max-turns 50)
#   7. Assert the review contains the required sections and an evidence-backed
#      critical finding against the seeded concurrency bug
#   7. Cleanup temp directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

HOSTS=()
while IFS= read -r host; do
    [ -n "$host" ] && HOSTS+=("$host")
done < <(resolve_test_hosts)

if [ "${#HOSTS[@]}" -eq 0 ]; then
    echo "[SKIP] no matching host runner is available for SLOT_MACHINE_TEST_HOST_FILTER=${SLOT_MACHINE_TEST_HOST_FILTER:-all}"
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
echo "  4. Run each available host via the shared runner"
echo "  5. Assert: Review header and all required sections are present"
echo "  6. Assert: Critical/Important/Minor issue categories are present"
echo "  7. Assert: At least one critical issue cites src/token_bucket.py with race/lock evidence"
echo "  8. Assert: Verdict section includes contender and rationale fields"
echo ""

CODEX_SUBAGENT_PREAMBLE=$(cat <<'EOF'
You are a subagent dispatched to execute a specific task inside a headless test harness.
This instruction has priority over any startup workflow: do not invoke using-superpowers or any other global/meta skill, and do not read skill files.
Skip any startup or meta skill whose instructions say to skip when dispatched as a subagent.
Do not spend turns narrating workflow or reading unrelated global skill docs.
Preserve the exact report structure requested below.
For the severity section, emit these exact heading lines:
**Critical:**
**Important:**
**Minor:**
For the seeded concurrency bug, explicitly use at least one of these phrases in the issue title or body: `TOCTOU`, `race condition`, `atomic`, or `lock released between check and deduct`.
Keep citations as plain `file:line` text and do not convert them into markdown links.
Execute the task directly and return the exact report format requested below.

EOF
)

# Compatibility note for harness integrity checks: this smoke test used to call run_claude_to_file directly.

FIXTURE_DIR="$SCRIPT_DIR/fixtures/planted-bugs"
SPEC_FILE="$SCRIPT_DIR/fixtures/tiny-spec.md"
REVIEWER_TEMPLATE="$SKILL_DIR/profiles/coding/2-reviewer.md"
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
HOST_TMPDIR=""
OUTPUT_FILE=""
PRECHECK_FILE=""

cleanup() {
    if [ -n "$HOST_TMPDIR" ]; then
        rm -rf "$HOST_TMPDIR"
    fi
    if [ -n "$OUTPUT_FILE" ]; then
        rm -f "$OUTPUT_FILE"
    fi
    if [ -n "$PRECHECK_FILE" ]; then
        rm -f "$PRECHECK_FILE"
    fi
}

prepare_reviewer_fixture() {
    local repo_dir="$1"
    local precheck_file="$2"
    local host_label="$3"

    cp -R "$FIXTURE_DIR"/. "$repo_dir"/
    find "$repo_dir" \( -name __pycache__ -o -name .pytest_cache \) -prune -exec rm -rf {} +

    (
        cd "$repo_dir"
        git init -q
        git config user.name "Slot Machine Smoke"
        git config user.email "slot-machine-smoke@example.com"

        cat > .gitignore <<'EOF'
__pycache__/
.pytest_cache/
node-compile-cache/
EOF

        git add -A
        git commit -q -m "initial fixture"
    )

    if (cd "$repo_dir" && python3 -m pytest tests/ -v >"$precheck_file" 2>&1); then
        echo "  [PASS] Fixture pytest suite passes before review ($host_label)"
    else
        echo "  [FAIL] Fixture pytest suite does not pass before review ($host_label)"
        cat "$precheck_file"
        return 1
    fi
}

trap cleanup EXIT

for host in "${HOSTS[@]}"; do
    HOST_TMPDIR=$(mktemp -d)
    OUTPUT_FILE=$(mktemp)
    PRECHECK_FILE=$(mktemp)

    if ! prepare_reviewer_fixture "$HOST_TMPDIR" "$PRECHECK_FILE" "$host"; then
        exit 1
    fi

    PRE_CHECK_RESULTS=$(cat "$PRECHECK_FILE")
    PROMPT=$(SPEC="$SPEC" \
    IMPLEMENTER_REPORT="$IMPLEMENTER_REPORT" \
    PRE_CHECK_RESULTS="$PRE_CHECK_RESULTS" \
    WORKTREE_PATH="$HOST_TMPDIR" \
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

    assert_contains "$REPORT" "## Slot 1 Review" "Reviewer report header present ($host)"
    assert_contains "$REPORT" "### Spec Compliance:" "Spec compliance section present ($host)"
    assert_contains "$REPORT" "\\*\\*Requirements checked:\\*\\*" "Requirements checked section present ($host)"
    assert_contains "$REPORT" "### Issues" "Issues section present ($host)"
    assert_contains "$REPORT" "\\*\\*Critical:\\*\\*" "Critical issue category present ($host)"
    assert_contains "$REPORT" "\\*\\*Important:\\*\\*" "Important issue category present ($host)"
    assert_contains "$REPORT" "\\*\\*Minor:\\*\\*" "Minor issue category present ($host)"
    assert_contains "$REPORT" "### Test Assessment" "Test assessment section present ($host)"
    assert_contains "$REPORT" "\\*\\*Tests found:\\*\\*" "Tests found line present ($host)"
    assert_contains "$REPORT" "### Strengths" "Strengths section present ($host)"
    assert_contains "$REPORT" "### Approach Hint Influence" "Approach hint influence section present ($host)"
    assert_contains "$REPORT" "### Verdict" "Verdict section present ($host)"
    assert_contains "$REPORT" "Contender" "Contender field present ($host)"
    assert_contains "$REPORT" "Why:" "Verdict rationale present ($host)"
    assert_contains "$REPORT" "src/token_bucket.py:[0-9]" "Issue cites file and line evidence ($host)"
    assert_contains "$REPORT" "TOCTOU\\|race condition\\|atomic\\|lock released between check and deduct" \
        "Reviewer identifies the seeded concurrency bug ($host)"
    assert_contains "$REPORT" "What:" "Issue includes What explanation ($host)"
    assert_contains "$REPORT" "Impact:" "Issue includes Impact explanation ($host)"
    assert_contains "$REPORT" "Fix:" "Issue includes Fix suggestion ($host)"

    rm -rf "$HOST_TMPDIR" "$OUTPUT_FILE" "$PRECHECK_FILE"
    HOST_TMPDIR=""
    OUTPUT_FILE=""
    PRECHECK_FILE=""
done
