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
# Pre-registered methodology: all metrics defined before execution.
# All results reported — no cherry-picking.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPEC_FILE="$SCRIPT_DIR/specs/task-scheduler.md"
RESULTS_DIR="$SCRIPT_DIR/results"

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
MATRIX_DIR="$STUDY_DIR/matrix"
mkdir -p "$MATRIX_DIR"

echo "========================================"
echo " Slot Machine Variability Study"
echo "========================================"
echo ""
echo "Spec: task-scheduler (TypeScript)"
echo "Slots: $SLOTS (all Claude Opus 4.6, identical settings)"
echo "Git SHA: $GIT_SHA"
echo ""
echo "Pre-registered metrics:"
echo "  1. Test count per slot (min/max/median/stddev)"
echo "  2. Cross-test matrix (NxN pass/fail)"
echo "  3. Lines of code per slot"
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

echo "Dispatching $SLOTS implementations in parallel..."
echo ""

PIDS=""
START_TIME=$(date +%s)

for i in $(seq 1 "$SLOTS"); do
    SLOT_DIR="$STUDY_DIR/slot-$i"
    cp -r "$BASE_DIR" "$SLOT_DIR"

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
    PIDS="$PIDS $!"
    echo "  Slot $i dispatched"
done

echo ""
echo "Waiting for all $SLOTS slots to complete..."

FAILED_COUNT=0
for pid in $PIDS; do
    if ! wait "$pid" 2>/dev/null; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

IMPL_END=$(date +%s)
IMPL_TIME=$((IMPL_END - START_TIME))
echo "All implementations complete in ${IMPL_TIME}s ($((IMPL_TIME / 60))m $((IMPL_TIME % 60))s)."
echo ""

# --- Phase 3: Collect per-slot metrics ---

echo "Collecting metrics..."

TEST_COUNTS=""
LOC_COUNTS=""

for i in $(seq 1 "$SLOTS"); do
    SLOT_DIR="$STUDY_DIR/slot-$i"

    # Test count
    TC=0
    if [ -f "$SLOT_DIR/src/scheduler.test.ts" ]; then
        TC=$(cd "$SLOT_DIR" && npx vitest run 2>&1 | grep -oE '[0-9]+ passed' | head -1 | grep -oE '[0-9]+' || echo "0")
        [ -z "$TC" ] && TC=0
    fi

    # LOC (implementation only)
    LOC=0
    if [ -f "$SLOT_DIR/src/scheduler.ts" ]; then
        LOC=$(wc -l < "$SLOT_DIR/src/scheduler.ts" | tr -d ' ')
    fi

    TEST_COUNTS="$TEST_COUNTS $TC"
    LOC_COUNTS="$LOC_COUNTS $LOC"
    echo "  Slot $i: $TC tests, $LOC LOC"
done
echo ""

# --- Phase 4: Cross-test matrix ---

echo "Running cross-test matrix ($SLOTS x $SLOTS)..."
echo ""

for code_slot in $(seq 1 "$SLOTS"); do
    CODE_DIR="$STUDY_DIR/slot-$code_slot"
    [ -f "$CODE_DIR/src/scheduler.ts" ] || continue

    for test_slot in $(seq 1 "$SLOTS"); do
        TEST_DIR="$STUDY_DIR/slot-$test_slot"
        [ -f "$TEST_DIR/src/scheduler.test.ts" ] || continue

        # Create temp dir: code_slot's impl + test_slot's tests
        CROSS_DIR="$STUDY_DIR/cross-tmp"
        rm -rf "$CROSS_DIR"
        cp -r "$CODE_DIR" "$CROSS_DIR"
        cp "$TEST_DIR/src/scheduler.test.ts" "$CROSS_DIR/src/scheduler.test.ts"

        # Run tests
        if cd "$CROSS_DIR" && npx vitest run 2>&1 | grep -q "passed"; then
            echo "PASS" > "$MATRIX_DIR/${code_slot}_${test_slot}"
        else
            echo "FAIL" > "$MATRIX_DIR/${code_slot}_${test_slot}"
        fi

        rm -rf "$CROSS_DIR"
    done
done

# Print matrix
printf "%-10s" "Code\\Test"
for j in $(seq 1 "$SLOTS"); do printf "%-6s" "T$j"; done
echo ""

for i in $(seq 1 "$SLOTS"); do
    printf "%-10s" "Slot $i"
    for j in $(seq 1 "$SLOTS"); do
        result=$(cat "$MATRIX_DIR/${i}_${j}" 2>/dev/null || echo "N/A")
        printf "%-6s" "$result"
    done
    echo ""
done
echo ""

# Compute off-diagonal stats
OFF_DIAG_TOTAL=0
OFF_DIAG_FAIL=0
SLOTS_WITH_FAILURES=0

for i in $(seq 1 "$SLOTS"); do
    SLOT_HAS_FAIL=false
    for j in $(seq 1 "$SLOTS"); do
        [ "$i" -eq "$j" ] && continue
        result=$(cat "$MATRIX_DIR/${i}_${j}" 2>/dev/null || echo "N/A")
        [ "$result" = "N/A" ] && continue
        OFF_DIAG_TOTAL=$((OFF_DIAG_TOTAL + 1))
        if [ "$result" = "FAIL" ]; then
            OFF_DIAG_FAIL=$((OFF_DIAG_FAIL + 1))
            SLOT_HAS_FAIL=true
        fi
    done
    [ "$SLOT_HAS_FAIL" = true ] && SLOTS_WITH_FAILURES=$((SLOTS_WITH_FAILURES + 1))
done

# --- Phase 5: Compute statistics ---

STATS=$(python3 -c "
import statistics, json

test_vals = [int(x) for x in '$TEST_COUNTS'.split() if int(x) > 0]
loc_vals = [int(x) for x in '$LOC_COUNTS'.split() if int(x) > 0]

off_total = $OFF_DIAG_TOTAL
off_fail = $OFF_DIAG_FAIL
fail_pct = (off_fail / off_total * 100) if off_total > 0 else 0

result = {
    'test': {
        'min': min(test_vals) if test_vals else 0,
        'max': max(test_vals) if test_vals else 0,
        'median': statistics.median(test_vals) if test_vals else 0,
        'mean': round(statistics.mean(test_vals), 1) if test_vals else 0,
        'stddev': round(statistics.stdev(test_vals), 1) if len(test_vals) > 1 else 0,
    },
    'loc': {
        'min': min(loc_vals) if loc_vals else 0,
        'max': max(loc_vals) if loc_vals else 0,
        'median': statistics.median(loc_vals) if loc_vals else 0,
        'mean': round(statistics.mean(loc_vals), 1) if loc_vals else 0,
        'stddev': round(statistics.stdev(loc_vals), 1) if len(loc_vals) > 1 else 0,
    },
    'cross_fail_pct': round(fail_pct, 1),
}
print(json.dumps(result))
")

TEST_MIN=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['test']['min'])")
TEST_MAX=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['test']['max'])")
TEST_MED=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['test']['median'])")
TEST_SD=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['test']['stddev'])")
TEST_MEAN=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['test']['mean'])")
LOC_MIN=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['loc']['min'])")
LOC_MAX=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['loc']['max'])")
LOC_MED=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['loc']['median'])")
LOC_SD=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['loc']['stddev'])")
CROSS_FAIL_PCT=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['cross_fail_pct'])")
TEST_SPREAD=$(python3 -c "print(f'{$TEST_MAX / max($TEST_MIN, 1):.1f}')")

# --- Phase 6: Save results ---

RESULT_FILE="$RESULTS_DIR/variability-${TIMESTAMP}.json"

# Build matrix JSON
MATRIX_JSON=$(python3 -c "
import json
slots = $SLOTS
matrix = []
for i in range(1, slots + 1):
    row = []
    for j in range(1, slots + 1):
        try:
            with open('$MATRIX_DIR/{0}_{1}'.format(i, j)) as f:
                val = f.read().strip()
                row.append(True if val == 'PASS' else False)
        except:
            row.append(None)
    matrix.append(row)
print(json.dumps(matrix))
")

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
  "test_counts": [$(echo $TEST_COUNTS | tr ' ' ',')],
  "test_stats": {
    "min": $TEST_MIN, "max": $TEST_MAX, "median": $TEST_MED,
    "stddev": $TEST_SD, "mean": $TEST_MEAN
  },
  "loc_counts": [$(echo $LOC_COUNTS | tr ' ' ',')],
  "loc_stats": {
    "min": $LOC_MIN, "max": $LOC_MAX, "median": $LOC_MED, "stddev": $LOC_SD
  },
  "cross_test_matrix": $MATRIX_JSON,
  "cross_test_stats": {
    "total_off_diagonal": $OFF_DIAG_TOTAL,
    "failures": $OFF_DIAG_FAIL,
    "failure_rate_pct": $CROSS_FAIL_PCT,
    "slots_with_at_least_one_failure": $SLOTS_WITH_FAILURES
  },
  "methodology": "Pre-registered. All slots use identical model, prompt, and settings. Each runs in an independent claude -p session. Cross-testing runs every implementation against every other test suite. All results reported."
}
RESULTEOF

# --- Phase 7: Report ---

echo "========================================"
echo " Variability Study Results"
echo "========================================"
echo ""
echo "  Spec: task-scheduler | Model: claude-opus-4-6 | Slots: $SLOTS"
echo "  Implementation time: ${IMPL_TIME}s ($((IMPL_TIME / 60))m $((IMPL_TIME % 60))s, all parallel)"
echo ""
echo "  TEST COUNTS"
echo "    Min: $TEST_MIN | Max: $TEST_MAX | Median: $TEST_MED | Stddev: $TEST_SD"
echo "    Range: ${TEST_MIN}-${TEST_MAX} (${TEST_SPREAD}x spread)"
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
    echo "    ${CROSS_FAIL_PCT}% of implementations fail tests written by other attempts."
    echo "    ${SLOTS_WITH_FAILURES} of $SLOTS attempts would fail at least one test another attempt wrote."
    echo "    Test coverage ranges from $TEST_MIN to $TEST_MAX — a ${TEST_SPREAD}x spread."
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
