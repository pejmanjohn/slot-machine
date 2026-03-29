#!/usr/bin/env bash
# Slot Machine Skill Test Runner
# Usage:
#   ./tests/run-tests.sh                  # Tier 1 only (contracts, instant)
#   ./tests/run-tests.sh --smoke          # + Tier 2 (phase-level, ~10 min)
#   ./tests/run-tests.sh --integration    # + Tier 3 (full E2E, ~20 min)
#   ./tests/run-tests.sh --benchmark       # Speed benchmark (~15 min)
#   ./tests/run-tests.sh --all            # Everything including LLM quality evals
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo " Slot Machine Skill Test Suite"
echo "========================================"
echo ""

# Parse arguments
RUN_SMOKE=false
RUN_INTEGRATION=false
RUN_QUALITY=false
RUN_BENCHMARK=false
SPECIFIC_TEST=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --smoke) RUN_SMOKE=true; shift ;;
        --integration) RUN_INTEGRATION=true; RUN_SMOKE=true; shift ;;
        --benchmark) RUN_BENCHMARK=true; shift ;;
        --all) RUN_SMOKE=true; RUN_INTEGRATION=true; RUN_QUALITY=true; RUN_BENCHMARK=true; shift ;;
        --test|-t) SPECIFIC_TEST="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "  --smoke          Run Tier 1 + Tier 2 (phase-level)"
            echo "  --integration    Run Tier 1 + Tier 2 + Tier 3 (E2E)"
            echo "  --benchmark      Run speed benchmark (~15 min)"
            echo "  --all            Run everything"
            echo "  --test NAME      Run specific test"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Test lists
tier1_tests=(test-contracts.sh test-skill-structure.sh)
tier2_tests=(test-implementer-smoke.sh test-reviewer-smoke.sh test-judge-smoke.sh)
tier3_tests=(test-e2e-happy-path.sh test-e2e-edge-cases.sh)
quality_tests=(test-prompt-quality.sh)

# Build test list
tests=("${tier1_tests[@]}")
if [ "$RUN_SMOKE" = true ]; then tests+=("${tier2_tests[@]}"); fi
if [ "$RUN_INTEGRATION" = true ]; then tests+=("${tier3_tests[@]}"); fi
if [ "$RUN_QUALITY" = true ]; then tests+=("${quality_tests[@]}"); fi

# Filter to specific test
if [ -n "$SPECIFIC_TEST" ]; then tests=("$SPECIFIC_TEST"); fi

# Run tests
passed=0
failed=0
skipped=0

for test in "${tests[@]}"; do
    echo "----------------------------------------"
    echo "Running: $test"
    echo "----------------------------------------"

    if [ ! -f "$SCRIPT_DIR/$test" ]; then
        echo "  [SKIP] Test file not found"
        skipped=$((skipped + 1))
        continue
    fi

    chmod +x "$SCRIPT_DIR/$test"
    start_time=$(date +%s)

    if bash "$SCRIPT_DIR/$test"; then
        end_time=$(date +%s)
        echo "  [PASS] ($(( end_time - start_time ))s)"
        passed=$((passed + 1))
    else
        end_time=$(date +%s)
        echo "  [FAIL] ($(( end_time - start_time ))s)"
        failed=$((failed + 1))
    fi
    echo ""
done

# Run benchmark if requested (separate from the test loop — it's a different format)
if [ "$RUN_BENCHMARK" = true ]; then
    echo "----------------------------------------"
    echo "Running: Speed Benchmark"
    echo "----------------------------------------"
    if bash "$SCRIPT_DIR/benchmark/run-speed-test.sh"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
    echo ""
fi

# Summary
echo "========================================"
echo " Results: $passed passed, $failed failed, $skipped skipped"
echo "========================================"

if [ "$RUN_SMOKE" = false ] && [ "$RUN_INTEGRATION" = false ] && [ "$RUN_BENCHMARK" = false ]; then
    echo "Note: Only Tier 1 (contract) tests ran. Use --smoke, --benchmark, or --all for more."
fi

[ $failed -eq 0 ] && exit 0 || exit 1
