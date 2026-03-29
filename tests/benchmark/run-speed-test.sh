#!/usr/bin/env bash
# Slot Machine Speed Benchmark
#
# Runs a baseline (single agent, no slot-machine) and a slot-machine run
# on the same spec, records timing, and checks against speed budgets.
#
# Usage:
#   ./tests/benchmark/run-speed-test.sh              # Single run
#   ./tests/benchmark/run-speed-test.sh --runs 3      # Multiple runs (median)
#
# Results are saved to tests/benchmark/results/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPEC_FILE="$SCRIPT_DIR/specs/task-scheduler.md"
RESULTS_DIR="$SCRIPT_DIR/results"

# Speed budgets
RATIO_LIMIT=7.0
OVERHEAD_LIMIT=90  # seconds

# Parse args
RUNS=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --runs) RUNS="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

SPEC=$(cat "$SPEC_FILE")
GIT_SHA=$(git -C "$SKILL_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")

if ! command -v claude >/dev/null 2>&1; then
    echo "[SKIP] claude CLI is required for the speed benchmark"
    exit 2
fi
if ! command -v npm >/dev/null 2>&1; then
    echo "[SKIP] npm is required for the speed benchmark"
    exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "[SKIP] python3 is required for the speed benchmark"
    exit 2
fi

mkdir -p "$RESULTS_DIR"

echo "========================================"
echo " Slot Machine Speed Benchmark"
echo "========================================"
echo ""
echo "Spec: task-scheduler (TypeScript)"
echo "Runs: $RUNS"
echo "Git SHA: $GIT_SHA"
echo "Budgets: ratio < ${RATIO_LIMIT}x, overhead < ${OVERHEAD_LIMIT}s"
echo ""

# Create a fresh TypeScript project
setup_project() {
    local dir="$1"
    cd "$dir"
    git init -q
    git config user.name "Slot Machine Benchmark"
    git config user.email "benchmark@example.com"
    mkdir -p src
    npm init -y > /dev/null 2>&1
    npm install -D typescript vitest @types/node > /dev/null 2>&1

    cat > tsconfig.json << 'TSEOF'
{"compilerOptions":{"target":"ES2022","module":"ESNext","moduleResolution":"bundler","strict":true,"outDir":"dist","rootDir":"src","declaration":true,"esModuleInterop":true,"skipLibCheck":true},"include":["src"]}
TSEOF

    cat > vitest.config.ts << 'VTEOF'
import { defineConfig } from 'vitest/config'
export default defineConfig({ test: { globals: true } })
VTEOF

    python3 -c "
import json
with open('package.json') as f: p = json.load(f)
p['scripts']['test'] = 'vitest run'
p['type'] = 'module'
with open('package.json', 'w') as f: json.dump(p, f, indent=2)
"
    echo -e 'node_modules/\ndist/\n.slot-machine/' > .gitignore
    git add -A > /dev/null 2>&1
    git commit -q -m "initial"
    cd - > /dev/null
}

# Run baseline (single agent, no slot-machine)
run_baseline() {
    local project_dir
    project_dir=$(mktemp -d)
    setup_project "$project_dir"

    local start end elapsed status test_count
    local test_output=""
    status="OK"
    test_count=0
    start=$(date +%s)

    if ! (
        cd "$project_dir"
        claude -p "Implement this in the working directory. Commit your work.

$SPEC

Test command: npx vitest run" \
            --allowedTools 'Bash,Read,Write,Edit,Glob,Grep' \
            --permission-mode bypassPermissions \
            --output-format stream-json \
            --max-turns 30 \
            > /dev/null 2>&1
    ); then
        status="CLAUDE_FAILED"
    fi

    end=$(date +%s)
    elapsed=$((end - start))

    if [ ! -f "$project_dir/src/scheduler.ts" ] || [ ! -f "$project_dir/src/scheduler.test.ts" ]; then
        status="MISSING_FILES"
    fi

    if [ "$status" = "OK" ]; then
        if test_output=$(cd "$project_dir" && npx vitest run 2>&1); then
            test_count=$(echo "$test_output" | grep "^      Tests" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' || true)
            test_count="${test_count:-0}"
            if [ "$test_count" -eq 0 ]; then
                status="NO_TESTS"
            fi
        else
            status="TESTS_FAILED"
        fi
    fi

    rm -rf "$project_dir"
    echo "$elapsed:$test_count:$status"
}

# Run slot-machine (3 slots, coding profile)
run_slot_machine() {
    local project_dir
    project_dir=$(mktemp -d)
    setup_project "$project_dir"

    local start end elapsed status test_count verdict
    local test_output=""
    status="OK"
    test_count=0
    verdict="UNKNOWN"
    start=$(date +%s)

    if ! (
        cd "$project_dir"
        claude -p "/slot-machine with 3 slots

Spec: $SPEC" \
            --allowedTools 'all' \
            --permission-mode bypassPermissions \
            --output-format stream-json \
            --max-turns 100 \
            --add-dir "$SKILL_DIR" \
            > "$project_dir/.slot-machine-transcript.jsonl" 2>&1
    ); then
        status="CLAUDE_FAILED"
    fi

    end=$(date +%s)
    elapsed=$((end - start))

    if [ ! -s "$project_dir/.slot-machine-transcript.jsonl" ]; then
        status="MISSING_TRANSCRIPT"
    fi

    if [ ! -f "$project_dir/src/scheduler.ts" ] || [ ! -f "$project_dir/src/scheduler.test.ts" ]; then
        status="MISSING_FILES"
    fi

    if [ "$status" = "OK" ]; then
        if test_output=$(cd "$project_dir" && npx vitest run 2>&1); then
            test_count=$(echo "$test_output" | grep "^      Tests" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' || true)
            test_count="${test_count:-0}"
            if [ "$test_count" -eq 0 ]; then
                status="NO_TESTS"
            fi
        else
            status="TESTS_FAILED"
        fi
    fi

    if [ -f "$project_dir/.slot-machine/runs/latest/result.json" ]; then
        verdict=$(python3 -c "import json; print(json.load(open('$project_dir/.slot-machine/runs/latest/result.json')).get('verdict', 'UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
    fi
    if [ "$verdict" = "UNKNOWN" ] && [ "$status" = "OK" ]; then
        status="MISSING_VERDICT"
    fi

    rm -rf "$project_dir"
    echo "$elapsed:$test_count:$verdict:$status"
}

# Collect results across runs
baseline_times=()
sm_times=()
ratios=()

for run in $(seq 1 "$RUNS"); do
    if [ "$RUNS" -gt 1 ]; then
        echo "--- Run $run of $RUNS ---"
    fi

    echo -n "  Baseline (single agent)... "
    result=$(run_baseline)
    IFS=':' read -r b_time b_tests b_status <<< "$result"
    if [ "$b_status" != "OK" ]; then
        echo "FAILED (${b_status})"
        echo "Benchmark aborted: baseline run is incomplete."
        exit 1
    fi
    baseline_times+=("$b_time")
    echo "${b_time}s (${b_tests} tests)"

    echo -n "  Slot Machine (3 slots)... "
    result=$(run_slot_machine)
    IFS=':' read -r sm_time sm_tests sm_verdict sm_status <<< "$result"
    if [ "$sm_status" != "OK" ]; then
        echo "FAILED (${sm_status})"
        echo "Benchmark aborted: slot-machine run is incomplete."
        exit 1
    fi
    sm_times+=("$sm_time")
    echo "${sm_time}s (${sm_tests} tests, ${sm_verdict})"

    # Compute ratio for this run
    if [ "$b_time" -gt 0 ]; then
        ratio=$(python3 -c "print(round($sm_time / $b_time, 2))")
    else
        ratio="N/A"
    fi
    ratios+=("$ratio")
    echo "  Ratio: ${ratio}x"
    echo ""
done

# Compute medians
median() {
    local arr=("$@")
    printf '%s\n' "${arr[@]}" | sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}'
}

median_baseline=$(median "${baseline_times[@]}")
median_sm=$(median "${sm_times[@]}")
median_ratio=$(median "${ratios[@]}")

# Compute overhead (total - estimated implementation time)
# Implementation is roughly baseline time (one agent's work)
overhead=$(python3 -c "print(max(0, $median_sm - $median_baseline * 3))" 2>/dev/null || echo "0")

# Check budgets
ratio_pass=$(python3 -c "print('true' if $median_ratio <= $RATIO_LIMIT else 'false')")
overhead_pass=$(python3 -c "print('true' if $overhead <= $OVERHEAD_LIMIT else 'false')")

if [ "$ratio_pass" = "true" ] && [ "$overhead_pass" = "true" ]; then
    overall="PASS"
else
    overall="FAIL"
fi

# Save result
timestamp=$(date +%Y-%m-%d-%H%M%S)
result_file="$RESULTS_DIR/${timestamp}.json"
cat > "$result_file" << RESULTEOF
{
  "date": "$(date +%Y-%m-%d)",
  "timestamp": "$timestamp",
  "git_sha": "$GIT_SHA",
  "spec": "task-scheduler",
  "runs": $RUNS,
  "baseline_seconds": $median_baseline,
  "slot_machine_seconds": $median_sm,
  "ratio": $median_ratio,
  "overhead_seconds": $overhead,
  "slots": 3,
  "verdict": "${sm_verdict:-UNKNOWN}",
  "budget": {
    "ratio_limit": $RATIO_LIMIT,
    "overhead_limit_seconds": $OVERHEAD_LIMIT,
    "ratio_passed": $ratio_pass,
    "overhead_passed": $overhead_pass,
    "overall": "$overall"
  },
  "all_runs": {
    "baseline_times": [$(IFS=,; echo "${baseline_times[*]}")],
    "slot_machine_times": [$(IFS=,; echo "${sm_times[*]}")],
    "ratios": [$(IFS=,; echo "${ratios[*]}")]
  }
}
RESULTEOF

# Report
echo "========================================"
echo " Results"
echo "========================================"
echo ""
echo "  Baseline:     ${median_baseline}s ($((median_baseline / 60))m $((median_baseline % 60))s)"
echo "  Slot Machine: ${median_sm}s ($((median_sm / 60))m $((median_sm % 60))s)"
echo "  Ratio:        ${median_ratio}x (budget: < ${RATIO_LIMIT}x)"
echo "  Overhead:     ${overhead}s (budget: < ${OVERHEAD_LIMIT}s)"
echo ""

if [ "$overall" = "PASS" ]; then
    echo "  ✅ PASS — within speed budget"
else
    echo "  ❌ FAIL — speed budget exceeded"
    if [ "$ratio_pass" = "false" ]; then
        echo "    Ratio ${median_ratio}x exceeds limit ${RATIO_LIMIT}x"
    fi
    if [ "$overhead_pass" = "false" ]; then
        echo "    Overhead ${overhead}s exceeds limit ${OVERHEAD_LIMIT}s"
    fi
fi

echo ""
echo "  Saved: $result_file"

# Show trend if previous results exist
prev_results=$(ls -t "$RESULTS_DIR"/*.json 2>/dev/null | tail -n +2 | head -3)
if [ -n "$prev_results" ]; then
    echo ""
    echo "  Trend (last 3):"
    for f in $prev_results; do
        prev_ratio=$(python3 -c "import json; print(json.load(open('$f')).get('ratio', '?'))" 2>/dev/null || echo "?")
        prev_date=$(python3 -c "import json; print(json.load(open('$f')).get('date', '?'))" 2>/dev/null || echo "?")
        prev_sha=$(python3 -c "import json; print(json.load(open('$f')).get('git_sha', '?'))" 2>/dev/null || echo "?")
        echo "    $prev_date ($prev_sha): ${prev_ratio}x"
    done
fi

echo ""
echo "========================================"

# Exit with appropriate code
[ "$overall" = "PASS" ]
