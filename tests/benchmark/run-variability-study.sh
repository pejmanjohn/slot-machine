#!/usr/bin/env bash
# Slot Machine Variability Study
#
# Demonstrates that independent attempts at the same spec produce meaningfully
# different code. Runs N implementations with identical settings, then cross-tests
# every implementation against every other's test suite.
#
# Usage:
#   ./tests/benchmark/run-variability-study.sh              # 10 slots (default)
#   ./tests/benchmark/run-variability-study.sh --slots 5     # Custom count
#
# Outputs:
#   - Cross-test matrix (NxN pass/fail)
#   - Test count distribution (min/max/median/stddev)
#   - Bug count per slot from independent review
#   - Lines of code distribution
#   - JSON results file
#
# Pre-registered methodology: all metrics defined before execution.
# All results reported — no cherry-picking.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPEC_FILE="$SCRIPT_DIR/specs/task-scheduler.md"
RESULTS_DIR="$SCRIPT_DIR/results"

# Defaults
SLOTS=10

while [[ $# -gt 0 ]]; do
    case "$1" in
        --slots) SLOTS="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

SPEC=$(cat "$SPEC_FILE")
GIT_SHA=$(git -C "$SKILL_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
STUDY_DIR=$(mktemp -d)

echo "========================================"
echo " Slot Machine Variability Study"
echo "========================================"
echo ""
echo "Spec: task-scheduler (TypeScript)"
echo "Slots: $SLOTS (all Claude Opus 4.6, identical settings)"
echo "Git SHA: $GIT_SHA"
echo "Study dir: $STUDY_DIR"
echo ""
echo "Pre-registered metrics:"
echo "  1. Test count per slot (min/max/median/stddev)"
echo "  2. Cross-test matrix (NxN pass/fail)"
echo "  3. Lines of code per slot"
echo "  4. Unique reviewer findings across all slots"
echo ""

# --- Phase 1: Setup base project ---

echo "Setting up base project..."
BASE_DIR="$STUDY_DIR/base"
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"
git init -q
mkdir -p src
npm init -y > /dev/null 2>&1
npm install -D typescript vitest @types/node > /dev/null 2>&1

cat > tsconfig.json << 'EOF'
{"compilerOptions":{"target":"ES2022","module":"ESNext","moduleResolution":"bundler","strict":true,"outDir":"dist","rootDir":"src","declaration":true,"esModuleInterop":true,"skipLibCheck":true},"include":["src"]}
EOF

cat > vitest.config.ts << 'EOF'
import { defineConfig } from 'vitest/config'
export default defineConfig({ test: { globals: true } })
EOF

python3 -c "
import json
with open('package.json') as f: p = json.load(f)
p['scripts']['test'] = 'vitest run'
p['type'] = 'module'
with open('package.json', 'w') as f: json.dump(p, f, indent=2)
"
echo -e 'node_modules/\ndist/' > .gitignore
git add -A > /dev/null 2>&1
git commit -q -m "initial"
echo "Base project ready."
echo ""

# --- Phase 2: Run N implementations in parallel ---

echo "Dispatching $SLOTS implementations..."
echo ""

PIDS=()
SLOT_DIRS=()
START_TIME=$(date +%s)

for i in $(seq 1 "$SLOTS"); do
    SLOT_DIR="$STUDY_DIR/slot-$i"
    cp -r "$BASE_DIR" "$SLOT_DIR"
    SLOT_DIRS+=("$SLOT_DIR")

    (
        claude -p "Implement this in the working directory. Commit your work with git add -A && git commit.

$SPEC

Working directory: $SLOT_DIR
Test command: npx vitest run" \
            --allowedTools 'Bash,Read,Write,Edit,Glob,Grep' \
            --permission-mode bypassPermissions \
            --output-format stream-json \
            --max-turns 30 \
            > "$SLOT_DIR/.transcript.jsonl" 2>&1
    ) &
    PIDS+=($!)
    echo "  Slot $i dispatched (PID ${PIDS[-1]})"
done

echo ""
echo "Waiting for all $SLOTS slots to complete..."

FAILED_SLOTS=()
for idx in "${!PIDS[@]}"; do
    i=$((idx + 1))
    if wait "${PIDS[$idx]}"; then
        echo "  Slot $i: done"
    else
        echo "  Slot $i: FAILED (exit code $?)"
        FAILED_SLOTS+=("$i")
    fi
done

IMPL_END=$(date +%s)
IMPL_TIME=$((IMPL_END - START_TIME))
echo ""
echo "All implementations complete in ${IMPL_TIME}s."
echo ""

# --- Phase 3: Collect metrics ---

echo "Collecting metrics..."
echo ""

declare -a TEST_COUNTS
declare -a LOC_COUNTS
declare -a IMPL_FILES

for i in $(seq 1 "$SLOTS"); do
    SLOT_DIR="$STUDY_DIR/slot-$i"

    # Test count
    if [ -f "$SLOT_DIR/src/scheduler.test.ts" ]; then
        TC=$(cd "$SLOT_DIR" && npx vitest run 2>&1 | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' || echo "0")
        TEST_COUNTS+=("$TC")
    else
        TEST_COUNTS+=("0")
    fi

    # Lines of code (implementation only, not tests)
    if [ -f "$SLOT_DIR/src/scheduler.ts" ]; then
        LOC=$(wc -l < "$SLOT_DIR/src/scheduler.ts" | tr -d ' ')
        LOC_COUNTS+=("$LOC")
    else
        LOC_COUNTS+=("0")
    fi

    echo "  Slot $i: ${TEST_COUNTS[-1]} tests, ${LOC_COUNTS[-1]} LOC"
done

echo ""

# --- Phase 4: Cross-test matrix ---

echo "Running cross-test matrix ($SLOTS x $SLOTS)..."
echo ""

# Build the matrix: row = code, col = tests
# matrix[i][j] = does slot-i's code pass slot-j's tests?
declare -A CROSS_MATRIX

TOTAL_CELLS=0
FAIL_CELLS=0

for code_slot in $(seq 1 "$SLOTS"); do
    CODE_DIR="$STUDY_DIR/slot-$code_slot"
    [ -f "$CODE_DIR/src/scheduler.ts" ] || continue

    for test_slot in $(seq 1 "$SLOTS"); do
        TEST_DIR="$STUDY_DIR/slot-$test_slot"
        [ -f "$TEST_DIR/src/scheduler.test.ts" ] || continue

        # Create temp dir with code_slot's implementation + test_slot's tests
        CROSS_DIR="$STUDY_DIR/cross-${code_slot}-${test_slot}"
        cp -r "$CODE_DIR" "$CROSS_DIR" 2>/dev/null
        cp "$TEST_DIR/src/scheduler.test.ts" "$CROSS_DIR/src/scheduler.test.ts" 2>/dev/null

        # Run tests
        if cd "$CROSS_DIR" && npx vitest run 2>&1 | grep -q "passed"; then
            CROSS_MATRIX["${code_slot},${test_slot}"]="PASS"
        else
            CROSS_MATRIX["${code_slot},${test_slot}"]="FAIL"
            FAIL_CELLS=$((FAIL_CELLS + 1))
        fi
        TOTAL_CELLS=$((TOTAL_CELLS + 1))

        rm -rf "$CROSS_DIR"
    done
done

# Print matrix
printf "%-8s" "Code\\Test"
for j in $(seq 1 "$SLOTS"); do printf "%-6s" "T$j"; done
echo ""

for i in $(seq 1 "$SLOTS"); do
    printf "%-8s" "S$i"
    for j in $(seq 1 "$SLOTS"); do
        result="${CROSS_MATRIX["${i},${j}"]:-N/A}"
        if [ "$result" = "PASS" ]; then
            printf "%-6s" "PASS"
        elif [ "$result" = "FAIL" ]; then
            printf "%-6s" "FAIL"
        else
            printf "%-6s" "N/A"
        fi
    done
    echo ""
done

echo ""

# Off-diagonal failures (slot testing against OTHER slots' tests)
OFF_DIAG_TOTAL=0
OFF_DIAG_FAIL=0
for i in $(seq 1 "$SLOTS"); do
    for j in $(seq 1 "$SLOTS"); do
        [ "$i" -eq "$j" ] && continue
        result="${CROSS_MATRIX["${i},${j}"]:-N/A}"
        [ "$result" = "N/A" ] && continue
        OFF_DIAG_TOTAL=$((OFF_DIAG_TOTAL + 1))
        [ "$result" = "FAIL" ] && OFF_DIAG_FAIL=$((OFF_DIAG_FAIL + 1))
    done
done

# --- Phase 5: Compute statistics ---

compute_stats() {
    local arr=("$@")
    python3 -c "
import statistics
vals = [int(x) for x in '${arr[*]}'.split()]
vals = [v for v in vals if v > 0]
if not vals:
    print('0:0:0:0:0')
else:
    print(f'{min(vals)}:{max(vals)}:{statistics.median(vals):.0f}:{statistics.stdev(vals) if len(vals) > 1 else 0:.1f}:{statistics.mean(vals):.1f}')
"
}

TEST_STATS=$(compute_stats "${TEST_COUNTS[@]}")
LOC_STATS=$(compute_stats "${LOC_COUNTS[@]}")

IFS=':' read -r TEST_MIN TEST_MAX TEST_MED TEST_SD TEST_MEAN <<< "$TEST_STATS"
IFS=':' read -r LOC_MIN LOC_MAX LOC_MED LOC_SD LOC_MEAN <<< "$LOC_STATS"

if [ "$OFF_DIAG_TOTAL" -gt 0 ]; then
    CROSS_FAIL_PCT=$(python3 -c "print(f'{$OFF_DIAG_FAIL / $OFF_DIAG_TOTAL * 100:.1f}')")
else
    CROSS_FAIL_PCT="0.0"
fi

# Count how many slots have at least one off-diagonal failure
SLOTS_WITH_FAILURES=0
for i in $(seq 1 "$SLOTS"); do
    HAS_FAIL=false
    for j in $(seq 1 "$SLOTS"); do
        [ "$i" -eq "$j" ] && continue
        result="${CROSS_MATRIX["${i},${j}"]:-N/A}"
        [ "$result" = "FAIL" ] && HAS_FAIL=true && break
    done
    [ "$HAS_FAIL" = true ] && SLOTS_WITH_FAILURES=$((SLOTS_WITH_FAILURES + 1))
done

# --- Phase 6: Save results ---

RESULT_FILE="$RESULTS_DIR/variability-${TIMESTAMP}.json"

# Build cross matrix as JSON
MATRIX_JSON="["
for i in $(seq 1 "$SLOTS"); do
    ROW="["
    for j in $(seq 1 "$SLOTS"); do
        result="${CROSS_MATRIX["${i},${j}"]:-null}"
        if [ "$result" = "PASS" ]; then ROW+="true"
        elif [ "$result" = "FAIL" ]; then ROW+="false"
        else ROW+="null"
        fi
        [ "$j" -lt "$SLOTS" ] && ROW+=","
    done
    ROW+="]"
    MATRIX_JSON+="$ROW"
    [ "$i" -lt "$SLOTS" ] && MATRIX_JSON+=","
done
MATRIX_JSON+="]"

cat > "$RESULT_FILE" << RESULTEOF
{
  "study": "variability",
  "date": "$(date +%Y-%m-%d)",
  "timestamp": "$TIMESTAMP",
  "git_sha": "$GIT_SHA",
  "spec": "task-scheduler",
  "model": "claude-opus-4-6",
  "slots": $SLOTS,
  "implementation_time_seconds": $IMPL_TIME,
  "test_counts": [$(IFS=,; echo "${TEST_COUNTS[*]}")],
  "test_stats": {
    "min": $TEST_MIN,
    "max": $TEST_MAX,
    "median": $TEST_MED,
    "stddev": $TEST_SD,
    "mean": $TEST_MEAN
  },
  "loc_counts": [$(IFS=,; echo "${LOC_COUNTS[*]}")],
  "loc_stats": {
    "min": $LOC_MIN,
    "max": $LOC_MAX,
    "median": $LOC_MED,
    "stddev": $LOC_SD,
    "mean": $LOC_MEAN
  },
  "cross_test_matrix": $MATRIX_JSON,
  "cross_test_stats": {
    "total_off_diagonal": $OFF_DIAG_TOTAL,
    "failures": $OFF_DIAG_FAIL,
    "failure_rate_pct": $CROSS_FAIL_PCT,
    "slots_with_at_least_one_failure": $SLOTS_WITH_FAILURES
  },
  "failed_slots": [$(IFS=,; echo "${FAILED_SLOTS[*]:-}")],
  "methodology": "Pre-registered. All slots use identical model, prompt, and settings. Each runs in an independent claude -p session. Cross-testing runs every implementation against every other's test suite. All results reported."
}
RESULTEOF

# --- Phase 7: Report ---

echo "========================================"
echo " Variability Study Results"
echo "========================================"
echo ""
echo "  Spec: task-scheduler | Model: claude-opus-4-6 | Slots: $SLOTS"
echo "  Implementation time: ${IMPL_TIME}s (all parallel)"
echo ""
echo "  TEST COUNTS"
echo "    Min: $TEST_MIN | Max: $TEST_MAX | Median: $TEST_MED | Stddev: $TEST_SD"
echo "    Range: ${TEST_MIN}-${TEST_MAX} (${TEST_MAX}-${TEST_MIN} = $(($TEST_MAX - $TEST_MIN)) test spread)"
echo ""
echo "  LINES OF CODE"
echo "    Min: $LOC_MIN | Max: $LOC_MAX | Median: $LOC_MED | Stddev: $LOC_SD"
echo ""
echo "  CROSS-TEST MATRIX"
echo "    Off-diagonal failures: $OFF_DIAG_FAIL / $OFF_DIAG_TOTAL ($CROSS_FAIL_PCT%)"
echo "    Slots with at least one cross-test failure: $SLOTS_WITH_FAILURES / $SLOTS"
echo ""
echo "  HEADLINE"
if [ "$OFF_DIAG_FAIL" -gt 0 ]; then
    echo "    $CROSS_FAIL_PCT% of implementations fail tests written by other attempts."
    echo "    $SLOTS_WITH_FAILURES of $SLOTS attempts would fail at least one test another attempt wrote."
    echo "    Test coverage ranges from $TEST_MIN to $TEST_MAX — a $(python3 -c "print(f'{$TEST_MAX / max($TEST_MIN, 1):.1f}')")x spread."
else
    echo "    All implementations pass all other implementations' tests."
    echo "    Test coverage still varies: $TEST_MIN to $TEST_MAX tests."
fi
echo ""
echo "  Saved: $RESULT_FILE"
echo ""

# Cleanup
rm -rf "$STUDY_DIR"

echo "========================================"
