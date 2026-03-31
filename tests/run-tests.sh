#!/usr/bin/env bash
# Slot Machine Skill Test Runner
# Usage:
#   ./tests/run-tests.sh                  # Tier 1 only (contracts, instant)
#   ./tests/run-tests.sh --smoke          # + Tier 2 (headless checks, may skip)
#   ./tests/run-tests.sh --integration    # + Tier 3 (headless E2E, may skip)
#   ./tests/run-tests.sh --changed        # Tier 1 + change-matched heavier checks
#   ./tests/run-tests.sh --host claude    # Restrict headless tests to one host
#   ./tests/run-tests.sh --jobs 2         # Run independent tests in parallel
#   ./tests/run-tests.sh --benchmark      # Speed benchmark (~15 min)
#   ./tests/run-tests.sh --all            # Everything, skipping unavailable headless tiers
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT_DIR="${TEST_ROOT_DIR:-$SCRIPT_DIR}"
BENCHMARK_SCRIPT_PATH="${BENCHMARK_SCRIPT_PATH:-$SCRIPT_DIR/benchmark/run-speed-test.sh}"
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
RUN_CHANGED=false
HOST_FILTER="all"
MAX_JOBS="1"
CHANGED_BASE="HEAD"
SPECIFIC_TESTS=()

print_help() {
    echo "Usage: $0 [options]"
    echo "  --smoke             Run Tier 1 + Tier 2 (headless checks may skip)"
    echo "  --integration       Run Tier 1 + Tier 2 + Tier 3 (headless E2E may skip)"
    echo "  --changed           Run Tier 1 + the smallest heavier checks matched to local changes"
    echo "  --host HOST         Restrict headless tests to claude, codex, or all"
    echo "  --jobs N|auto       Run up to N tests in parallel"
    echo "  --benchmark         Run speed benchmark (~15 min)"
    echo "  --all               Run everything"
    echo "  --test NAME         Run specific test (repeatable)"
    echo "  --help              Show this help"
}

normalize_host_filter() {
    case "${1:-all}" in
        ""|all) echo "all" ;;
        claude|codex) echo "$1" ;;
        *) return 1 ;;
    esac
}

cpu_count() {
    if command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN 2>/dev/null && return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - <<'PY'
import os
print(os.cpu_count() or 1)
PY
        return 0
    fi

    echo "1"
}

normalize_job_count() {
    local raw="${1:-1}"

    if [ "$raw" = "auto" ]; then
        raw="$(cpu_count)"
    fi

    case "$raw" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    if [ "$raw" -lt 1 ]; then
        return 1
    fi

    echo "$raw"
}

contains_test() {
    local needle="$1"
    local existing
    for existing in "${selected_tests[@]:-}"; do
        if [ "$existing" = "$needle" ]; then
            return 0
        fi
    done
    return 1
}

add_selected_test() {
    local test_name="$1"
    if ! contains_test "$test_name"; then
        selected_tests+=("$test_name")
    fi
}

collect_changed_files() {
    local base_ref="$1"
    local repo_root

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 1
    fi

    repo_root="$(git rev-parse --show-toplevel)"

    {
        if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
            git -C "$repo_root" diff --name-only "$base_ref" --
        else
            git -C "$repo_root" diff --name-only --
        fi
        git -C "$repo_root" ls-files --others --exclude-standard
    } | awk 'NF { print }' | sort -u
}

changed_diff_matches() {
    local base_ref="$1"
    local pattern="$2"
    local repo_root

    if [ "${#changed_files[@]}" -eq 0 ]; then
        return 1
    fi

    if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
        return 1
    fi

    repo_root="$(git rev-parse --show-toplevel)"

    git -C "$repo_root" diff --no-ext-diff --unified=0 "$base_ref" -- "${changed_files[@]}" 2>/dev/null | grep -Eq "$pattern"
}

select_changed_tests() {
    local changed_path
    local changed_note_base

    selected_tests=()
    changed_files=()

    for test_name in "${tier1_tests[@]}"; do
        add_selected_test "$test_name"
    done

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        CHANGED_NOTE="Note: --changed requires a git worktree; running Tier 1 only."
        tests=("${selected_tests[@]}")
        return 0
    fi

    while IFS= read -r changed_path; do
        [ -n "$changed_path" ] && changed_files+=("$changed_path")
    done < <(collect_changed_files "$CHANGED_BASE")

    if [ "${#changed_files[@]}" -eq 0 ]; then
        CHANGED_NOTE="Note: No local changes detected; running Tier 1 only."
        tests=("${selected_tests[@]}")
        return 0
    fi

    for changed_path in "${changed_files[@]}"; do
        case "$changed_path" in
            profiles/*/1-implementer.md|tests/test-implementer-smoke.sh)
                add_selected_test test-implementer-smoke.sh
                ;;
            profiles/*/2-reviewer.md|tests/test-reviewer-smoke.sh|tests/fixtures/planted-bugs/*)
                add_selected_test test-reviewer-smoke.sh
                ;;
            profiles/*/3-judge.md|tests/test-judge-smoke.sh)
                add_selected_test test-judge-smoke.sh
                ;;
            profiles/*/0-profile.md|profiles/*/4-synthesizer.md|SKILL.md|skills/slot-machine/SKILL.md|tests/test-e2e-happy-path.sh)
                add_selected_test test-e2e-happy-path.sh
                case "$changed_path" in
                    profiles/*/0-profile.md|SKILL.md|skills/slot-machine/SKILL.md)
                        add_selected_test test-claude-profile-inheritance-smoke.sh
                        add_selected_test test-claude-host-profile-inheritance-smoke.sh
                        ;;
                esac
                ;;
            tests/test-e2e-manual-handoff.sh)
                add_selected_test test-e2e-manual-handoff.sh
                ;;
            tests/test-claude-host-codex-smoke.sh)
                add_selected_test test-claude-host-codex-smoke.sh
                ;;
            tests/test-claude-host-profile-inheritance-smoke.sh)
                add_selected_test test-claude-host-profile-inheritance-smoke.sh
                ;;
            tests/test-claude-profile-inheritance-smoke.sh)
                add_selected_test test-claude-profile-inheritance-smoke.sh
                ;;
        esac
    done

    if changed_diff_matches "$CHANGED_BASE" '(^|[^[:alnum:]_])(manual_handoff|handoff\.md|slot-manifest\.json|resolution_mode|winning_slot)([^[:alnum:]_]|$)'; then
        add_selected_test test-e2e-happy-path.sh
        add_selected_test test-e2e-manual-handoff.sh
    fi

    if changed_diff_matches "$CHANGED_BASE" '(^|[^[:alnum:]_])(profile_loading|blocked_stage|blocked_reason|extends:|pwd -P|find -L)([^[:alnum:]_]|$)'; then
        add_selected_test test-claude-profile-inheritance-smoke.sh
    fi

    tests=("${selected_tests[@]}")
    CHANGED_NOTE="Note: --changed selected ${#tests[@]} tests from ${#changed_files[@]} changed files."
}

run_test_capture() {
    local test="$1"
    local output_file="$2"
    local test_path="$TEST_ROOT_DIR/$test"
    local start_time
    local end_time
    local status
    local normalized_status=0

    {
        echo "----------------------------------------"
        echo "Running: $test"
        echo "----------------------------------------"

        if [ ! -f "$test_path" ]; then
            echo "  [FAIL] Test file not found"
            normalized_status=1
        else
            chmod +x "$test_path"
            start_time=$(date +%s)

            if bash "$test_path"; then
                end_time=$(date +%s)
                echo "  [PASS] ($(( end_time - start_time ))s)"
                normalized_status=0
            else
                status=$?
                end_time=$(date +%s)
                if [ "$status" -eq 2 ]; then
                    echo "  [SKIP] ($(( end_time - start_time ))s)"
                    normalized_status=2
                else
                    echo "  [FAIL] ($(( end_time - start_time ))s)"
                    normalized_status=1
                fi
            fi
        fi

        echo ""
    } >"$output_file" 2>&1

    return "$normalized_status"
}

record_result() {
    local status="$1"
    case "$status" in
        0) passed=$((passed + 1)) ;;
        2) skipped=$((skipped + 1)) ;;
        *) failed=$((failed + 1)) ;;
    esac
}

run_tests_serial() {
    local test
    local output_file
    local status

    for test in "${tests[@]}"; do
        output_file=$(mktemp)
        set +e
        run_test_capture "$test" "$output_file"
        status=$?
        set -e
        cat "$output_file"
        rm -f "$output_file"
        record_result "$status"
    done
}

run_tests_parallel() {
    local tmpdir
    local fifo_path
    local index
    local status
    local pids=()

    tmpdir=$(mktemp -d)
    fifo_path="$tmpdir/jobs.fifo"
    mkfifo "$fifo_path"
    exec 9<>"$fifo_path"
    rm -f "$fifo_path"

    for index in $(seq 1 "$MAX_JOBS"); do
        printf 'slot\n' >&9
    done

    for index in "${!tests[@]}"; do
        read -r -u 9 _
        {
            set +e
            run_test_capture "${tests[$index]}" "$tmpdir/$index.out"
            status=$?
            set -e
            printf '%s\n' "$status" >"$tmpdir/$index.status"
            printf 'slot\n' >&9
        } &
        pids[$index]=$!
    done

    for index in "${!pids[@]}"; do
        wait "${pids[$index]}" || true
    done

    exec 9>&-
    exec 9<&-

    for index in "${!tests[@]}"; do
        cat "$tmpdir/$index.out"
        status=$(cat "$tmpdir/$index.status")
        record_result "$status"
    done

    rm -rf "$tmpdir"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --smoke) RUN_SMOKE=true; shift ;;
        --integration) RUN_INTEGRATION=true; RUN_SMOKE=true; shift ;;
        --changed) RUN_CHANGED=true; shift ;;
        --host)
            HOST_FILTER="$2"
            shift 2
            ;;
        --jobs)
            MAX_JOBS="$2"
            shift 2
            ;;
        --changed-base)
            CHANGED_BASE="$2"
            shift 2
            ;;
        --benchmark) RUN_BENCHMARK=true; shift ;;
        --all) RUN_SMOKE=true; RUN_INTEGRATION=true; RUN_QUALITY=true; RUN_BENCHMARK=true; shift ;;
        --test|-t) SPECIFIC_TESTS+=("$2"); shift 2 ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if ! HOST_FILTER="$(normalize_host_filter "$HOST_FILTER")"; then
    echo "Unsupported host filter: $HOST_FILTER"
    exit 1
fi

if ! MAX_JOBS="$(normalize_job_count "$MAX_JOBS")"; then
    echo "Invalid job count: $MAX_JOBS"
    exit 1
fi

if [ "$RUN_CHANGED" = true ] && { [ "$RUN_SMOKE" = true ] || [ "$RUN_INTEGRATION" = true ] || [ "$RUN_QUALITY" = true ] || [ "$RUN_BENCHMARK" = true ] || [ "${#SPECIFIC_TESTS[@]}" -gt 0 ]; }; then
    echo "--changed cannot be combined with --smoke, --integration, --all, --benchmark, or --test"
    exit 1
fi

export SLOT_MACHINE_TEST_HOST_FILTER="$HOST_FILTER"

# Test lists
tier1_tests=(test-contracts.sh test-skill-structure.sh test-codex-standalone-install.sh test-harness-integrity.sh test-codex-wrapper-parser.sh)
tier2_tests=(test-implementer-smoke.sh test-reviewer-smoke.sh test-judge-smoke.sh test-claude-host-codex-smoke.sh test-claude-profile-inheritance-smoke.sh test-claude-host-profile-inheritance-smoke.sh)
tier3_tests=(test-e2e-happy-path.sh test-e2e-manual-handoff.sh test-e2e-edge-cases.sh)
quality_tests=(test-reviewer-accuracy.sh)

# Build test list
tests=()
selected_tests=()
changed_files=()
CHANGED_NOTE=""

if [ "${#SPECIFIC_TESTS[@]}" -gt 0 ]; then
    tests=("${SPECIFIC_TESTS[@]}")
elif [ "$RUN_CHANGED" = true ]; then
    select_changed_tests
else
    tests=("${tier1_tests[@]}")
    if [ "$RUN_SMOKE" = true ]; then tests+=("${tier2_tests[@]}"); fi
    if [ "$RUN_INTEGRATION" = true ]; then tests+=("${tier3_tests[@]}"); fi
    if [ "$RUN_QUALITY" = true ]; then tests+=("${quality_tests[@]}"); fi
fi

# Run tests
passed=0
failed=0
skipped=0

if [ "$MAX_JOBS" -gt 1 ] && [ "${#tests[@]}" -gt 1 ]; then
    run_tests_parallel
else
    run_tests_serial
fi

# Run benchmark if requested (separate from the test loop — it's a different format)
if [ "$RUN_BENCHMARK" = true ]; then
    echo "----------------------------------------"
    echo "Running: Speed Benchmark"
    echo "----------------------------------------"
    if bash "$BENCHMARK_SCRIPT_PATH"; then
        passed=$((passed + 1))
    else
        status=$?
        if [ "$status" -eq 2 ]; then
            skipped=$((skipped + 1))
            echo "  [SKIP]"
        else
            failed=$((failed + 1))
        fi
    fi
    echo ""
fi

# Summary
echo "========================================"
echo " Results: $passed passed, $failed failed, $skipped skipped"
echo "========================================"

if [ "$RUN_CHANGED" = false ] && [ "$RUN_SMOKE" = false ] && [ "$RUN_INTEGRATION" = false ] && [ "$RUN_BENCHMARK" = false ] && [ "$RUN_QUALITY" = false ] && [ "${#SPECIFIC_TESTS[@]}" -eq 0 ]; then
    echo "Note: Only Tier 1 (contract) tests ran. Use --smoke, --benchmark, or --all for more."
fi

if [ -n "$CHANGED_NOTE" ]; then
    echo "$CHANGED_NOTE"
fi

if [ "$skipped" -gt 0 ]; then
    echo "Note: Some requested checks were skipped. Read the per-test output before treating this as full coverage."
fi

[ $failed -eq 0 ] && exit 0 || exit 1
