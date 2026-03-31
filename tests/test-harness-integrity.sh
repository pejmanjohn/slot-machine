#!/usr/bin/env bash
# Tier 1: Validate the test harness itself is honest about coverage and failures.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

FAILED=0
RUNNER="$SKILL_DIR/tests/run-tests.sh"
SPEED_BENCH="$SKILL_DIR/tests/benchmark/run-speed-test.sh"
VARIABILITY_BENCH="$SKILL_DIR/tests/benchmark/run-variability-study.sh"

all_runner_tests=(
    test-contracts.sh
    test-skill-structure.sh
    test-codex-standalone-install.sh
    test-harness-integrity.sh
    test-codex-wrapper-parser.sh
    test-implementer-smoke.sh
    test-reviewer-smoke.sh
    test-judge-smoke.sh
    test-claude-host-codex-smoke.sh
    test-e2e-happy-path.sh
    test-e2e-manual-handoff.sh
    test-e2e-edge-cases.sh
    test-reviewer-accuracy.sh
)

make_runner_fixture_repo() {
    local repo_dir="$1"
    local sleep_seconds="${2:-0}"

    mkdir -p "$repo_dir/tests/benchmark" "$repo_dir/profiles/coding" "$repo_dir/profiles/writing"
    cp "$RUNNER" "$repo_dir/tests/run-tests.sh"
    chmod +x "$repo_dir/tests/run-tests.sh"

    cat > "$repo_dir/SKILL.md" <<'EOF'
# Synthetic skill
EOF

    for prompt_file in \
        "$repo_dir/profiles/coding/0-profile.md" \
        "$repo_dir/profiles/coding/1-implementer.md" \
        "$repo_dir/profiles/coding/2-reviewer.md" \
        "$repo_dir/profiles/coding/3-judge.md" \
        "$repo_dir/profiles/coding/4-synthesizer.md" \
        "$repo_dir/profiles/writing/0-profile.md" \
        "$repo_dir/profiles/writing/1-implementer.md" \
        "$repo_dir/profiles/writing/2-reviewer.md" \
        "$repo_dir/profiles/writing/3-judge.md" \
        "$repo_dir/profiles/writing/4-synthesizer.md"; do
        cat > "$prompt_file" <<'EOF'
synthetic fixture
EOF
    done

    for test_name in "${all_runner_tests[@]}"; do
        cat > "$repo_dir/tests/$test_name" <<EOF
#!/usr/bin/env bash
echo "synthetic: $test_name"
sleep "$sleep_seconds"
exit 0
EOF
        chmod +x "$repo_dir/tests/$test_name"
    done

    cat > "$repo_dir/tests/benchmark/run-speed-test.sh" <<EOF
#!/usr/bin/env bash
echo "synthetic benchmark"
sleep "$sleep_seconds"
exit 0
EOF
    chmod +x "$repo_dir/tests/benchmark/run-speed-test.sh"

    (
        cd "$repo_dir"
        git init -q
        git config user.name "Slot Machine Harness"
        git config user.email "slot-machine-harness@example.com"
        git add -A
        git commit -q -m "initial fixture"
    )
}

echo "=== Harness Integrity: Runner Behavior ==="
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/skip.sh" <<'EOF'
#!/usr/bin/env bash
echo "[SKIP] synthetic skip"
exit 2
EOF
chmod +x "$TMPDIR/skip.sh"

set +e
SKIP_OUTPUT=$(TEST_ROOT_DIR="$TMPDIR" "$RUNNER" --test skip.sh 2>&1)
SKIP_STATUS=$?
set -e

if [ "$SKIP_STATUS" -eq 0 ] &&
   echo "$SKIP_OUTPUT" | grep -q "\[SKIP\] synthetic skip" &&
   echo "$SKIP_OUTPUT" | grep -q "Results: 0 passed, 0 failed, 1 skipped"; then
    echo "  [PASS] Runner treats exit code 2 as skipped"
else
    echo "  [FAIL] Runner does not treat exit code 2 as skipped"
    FAILED=$((FAILED + 1))
fi

set +e
MISSING_OUTPUT=$(TEST_ROOT_DIR="$TMPDIR" "$RUNNER" --test missing.sh 2>&1)
MISSING_STATUS=$?
set -e

if [ "$MISSING_STATUS" -ne 0 ] &&
   echo "$MISSING_OUTPUT" | grep -q "Test file not found" &&
   echo "$MISSING_OUTPUT" | grep -q "Results: 0 passed, 1 failed, 0 skipped"; then
    echo "  [PASS] Runner fails when a declared test file is missing"
else
    echo "  [FAIL] Runner does not fail when a declared test file is missing"
    FAILED=$((FAILED + 1))
fi

HOST_REPO=$(mktemp -d)
make_runner_fixture_repo "$HOST_REPO"
cat > "$HOST_REPO/tests/test-contracts.sh" <<'EOF'
#!/usr/bin/env bash
echo "host-filter=${SLOT_MACHINE_TEST_HOST_FILTER:-unset}"
exit 0
EOF
chmod +x "$HOST_REPO/tests/test-contracts.sh"

set +e
HOST_FILTER_OUTPUT=$(TEST_ROOT_DIR="$HOST_REPO/tests" "$HOST_REPO/tests/run-tests.sh" --host codex --test test-contracts.sh 2>&1)
HOST_FILTER_STATUS=$?
set -e

if [ "$HOST_FILTER_STATUS" -eq 0 ] &&
   echo "$HOST_FILTER_OUTPUT" | grep -q "host-filter=codex"; then
    echo "  [PASS] Runner forwards --host filter to test scripts"
else
    echo "  [FAIL] Runner does not forward --host filter to test scripts"
    FAILED=$((FAILED + 1))
fi
rm -rf "$HOST_REPO"

JOBS_REPO=$(mktemp -d)
make_runner_fixture_repo "$JOBS_REPO" 2
JOBS_START=$(python3 - <<'PY'
import time
print(time.time())
PY
)
set +e
JOBS_OUTPUT=$(TEST_ROOT_DIR="$JOBS_REPO/tests" "$JOBS_REPO/tests/run-tests.sh" --jobs 2 2>&1)
JOBS_STATUS=$?
set -e
JOBS_END=$(python3 - <<'PY'
import time
print(time.time())
PY
)
JOBS_ELAPSED=$(python3 - <<'PY' "$JOBS_START" "$JOBS_END"
import sys
print(float(sys.argv[2]) - float(sys.argv[1]))
PY
)

if [ "$JOBS_STATUS" -eq 0 ] &&
   echo "$JOBS_OUTPUT" | grep -q "Results: 5 passed, 0 failed, 0 skipped" &&
   python3 - <<'PY' "$JOBS_ELAPSED"
import sys
sys.exit(0 if float(sys.argv[1]) < 9.0 else 1)
PY
then
    echo "  [PASS] Runner executes independent tests in parallel with --jobs"
else
    echo "  [FAIL] Runner does not execute independent tests in parallel with --jobs"
    echo "  Elapsed: $JOBS_ELAPSED"
    FAILED=$((FAILED + 1))
fi
rm -rf "$JOBS_REPO"

CHANGED_REPO=$(mktemp -d)
make_runner_fixture_repo "$CHANGED_REPO"
cat >> "$CHANGED_REPO/profiles/coding/1-implementer.md" <<'EOF'
implementer change
EOF

set +e
CHANGED_OUTPUT=$(TEST_ROOT_DIR="$CHANGED_REPO/tests" "$CHANGED_REPO/tests/run-tests.sh" --changed 2>&1)
CHANGED_STATUS=$?
set -e

if [ "$CHANGED_STATUS" -eq 0 ] &&
   echo "$CHANGED_OUTPUT" | grep -q "Running: test-implementer-smoke.sh" &&
   ! echo "$CHANGED_OUTPUT" | grep -q "Running: test-reviewer-smoke.sh" &&
   ! echo "$CHANGED_OUTPUT" | grep -q "Running: test-judge-smoke.sh" &&
   ! echo "$CHANGED_OUTPUT" | grep -q "Running: test-e2e-happy-path.sh" &&
   echo "$CHANGED_OUTPUT" | grep -q "Results: 6 passed, 0 failed, 0 skipped"; then
    echo "  [PASS] Runner selects the matching phase smoke test for --changed"
else
    echo "  [FAIL] Runner does not select the matching phase smoke test for --changed"
    FAILED=$((FAILED + 1))
fi
rm -rf "$CHANGED_REPO"

MANUAL_REPO=$(mktemp -d)
make_runner_fixture_repo "$MANUAL_REPO"
cat >> "$MANUAL_REPO/SKILL.md" <<'EOF'
manual_handoff path updated
handoff.md
slot-manifest.json
EOF

set +e
MANUAL_OUTPUT=$(TEST_ROOT_DIR="$MANUAL_REPO/tests" "$MANUAL_REPO/tests/run-tests.sh" --changed 2>&1)
MANUAL_STATUS=$?
set -e

if [ "$MANUAL_STATUS" -eq 0 ] &&
   echo "$MANUAL_OUTPUT" | grep -q "Running: test-e2e-happy-path.sh" &&
   echo "$MANUAL_OUTPUT" | grep -q "Running: test-e2e-manual-handoff.sh"; then
    echo "  [PASS] Runner selects both happy-path and manual handoff coverage when manual artifacts change"
else
    echo "  [FAIL] Runner does not select the expected E2E coverage for manual-handoff changes"
    FAILED=$((FAILED + 1))
fi
rm -rf "$MANUAL_REPO"

echo ""
echo "=== Harness Integrity: Test Manifest ==="
RUNNER_CONTENT=$(cat "$RUNNER")
assert_contains "$RUNNER_CONTENT" "quality_tests=(test-reviewer-accuracy.sh)" \
    "Quality tier points at the reviewer accuracy test" || FAILED=$((FAILED + 1))
assert_contains "$RUNNER_CONTENT" "test-harness-integrity.sh" \
    "Tier 1 includes harness integrity checks" || FAILED=$((FAILED + 1))
assert_contains "$RUNNER_CONTENT" "test-e2e-manual-handoff.sh" \
    "Tier 3 includes manual handoff integration coverage" || FAILED=$((FAILED + 1))
assert_contains "$RUNNER_CONTENT" "test-claude-host-codex-smoke.sh" \
    "Smoke tier includes the Claude-host + Codex regression test" || FAILED=$((FAILED + 1))
assert_contains "$RUNNER_CONTENT" "--host" \
    "Runner exposes a host-selection option" || FAILED=$((FAILED + 1))
assert_contains "$RUNNER_CONTENT" "--jobs" \
    "Runner exposes a parallel-jobs option" || FAILED=$((FAILED + 1))
assert_contains "$RUNNER_CONTENT" "--changed" \
    "Runner exposes a change-aware selection option" || FAILED=$((FAILED + 1))

echo ""
echo "=== Harness Integrity: Repo Guidance ==="
CLAUDE_CONTENT=$(cat "$SKILL_DIR/CLAUDE.md")
AGENTS_CONTENT=$(cat "$SKILL_DIR/AGENTS.md")
CONTRIBUTING_CONTENT=$(cat "$SKILL_DIR/CONTRIBUTING.md")
assert_contains "$CLAUDE_CONTENT" "ready for review by default" \
    "CLAUDE.md documents ready-for-review PRs by default" || FAILED=$((FAILED + 1))
assert_contains "$AGENTS_CONTENT" "ready for review by default" \
    "AGENTS.md documents ready-for-review PRs by default" || FAILED=$((FAILED + 1))
assert_contains "$CONTRIBUTING_CONTENT" "ready for review by default" \
    "CONTRIBUTING.md documents ready-for-review PRs by default" || FAILED=$((FAILED + 1))

echo ""
echo "=== Harness Integrity: Placeholder Tests ==="
IMPLEMENTER_SMOKE_CONTENT=$(cat "$SKILL_DIR/tests/test-implementer-smoke.sh")
REVIEWER_SMOKE_CONTENT=$(cat "$SKILL_DIR/tests/test-reviewer-smoke.sh")
JUDGE_SMOKE_CONTENT=$(cat "$SKILL_DIR/tests/test-judge-smoke.sh")
E2E_HAPPY_CONTENT=$(cat "$SKILL_DIR/tests/test-e2e-happy-path.sh")
MANUAL_E2E_CONTENT=$(cat "$SKILL_DIR/tests/test-e2e-manual-handoff.sh" 2>/dev/null || echo "")
CLAUDE_CODEX_SMOKE_CONTENT=$(cat "$SKILL_DIR/tests/test-claude-host-codex-smoke.sh")
assert_not_contains "$IMPLEMENTER_SMOKE_CONTENT" "Placeholder until headless claude -p execution is wired to real assertions" \
    "test-implementer-smoke.sh is no longer a placeholder" || FAILED=$((FAILED + 1))
assert_contains "$IMPLEMENTER_SMOKE_CONTENT" 'run_host_to_file "\$host" "\$OUTPUT_FILE" "\$HOST_PROMPT" "\$HOST_TIMEOUT" 50 "\$HOST_TMPDIR"' \
    "test-implementer-smoke.sh invokes hosts via the shared runner" || FAILED=$((FAILED + 1))
assert_contains "$IMPLEMENTER_SMOKE_CONTENT" "extract_result_text" \
    "test-implementer-smoke.sh parses host result payloads" || FAILED=$((FAILED + 1))
assert_contains "$IMPLEMENTER_SMOKE_CONTENT" "resolve_test_hosts" \
    "test-implementer-smoke.sh resolves hosts through the shared helper" || FAILED=$((FAILED + 1))

assert_not_contains "$REVIEWER_SMOKE_CONTENT" "Placeholder until headless claude -p execution is wired to real assertions" \
    "test-reviewer-smoke.sh is no longer a placeholder" || FAILED=$((FAILED + 1))
assert_contains "$REVIEWER_SMOKE_CONTENT" 'run_host_to_file "\$host" "\$OUTPUT_FILE" "\$HOST_PROMPT" "\$HOST_TIMEOUT" 50 "\$HOST_TMPDIR"' \
    "test-reviewer-smoke.sh invokes hosts via the shared runner" || FAILED=$((FAILED + 1))
assert_contains "$REVIEWER_SMOKE_CONTENT" "extract_result_text" \
    "test-reviewer-smoke.sh parses host result payloads" || FAILED=$((FAILED + 1))
assert_contains "$REVIEWER_SMOKE_CONTENT" "resolve_test_hosts" \
    "test-reviewer-smoke.sh resolves hosts through the shared helper" || FAILED=$((FAILED + 1))
assert_contains "$REVIEWER_SMOKE_CONTENT" 'HOST_TMPDIR=$(mktemp -d)' \
    "test-reviewer-smoke.sh creates a fresh temp repo per host" || FAILED=$((FAILED + 1))
assert_count "$REVIEWER_SMOKE_CONTENT" 'run_host_to_file "\$host" "\$OUTPUT_FILE" "\$HOST_PROMPT" "\$HOST_TIMEOUT" 50 "\$HOST_TMPDIR"' 1 \
    "test-reviewer-smoke.sh runs each host against its own temp repo" || FAILED=$((FAILED + 1))

assert_not_contains "$JUDGE_SMOKE_CONTENT" "Placeholder until headless claude -p execution is wired to real assertions" \
    "test-judge-smoke.sh is no longer a placeholder" || FAILED=$((FAILED + 1))
assert_contains "$JUDGE_SMOKE_CONTENT" 'run_host_to_file "\$host" "\$OUTPUT_FILE" "\$HOST_PROMPT" "\$HOST_TIMEOUT" 50 "\$HOST_TMP_ROOT"' \
    "test-judge-smoke.sh invokes hosts via the shared runner" || FAILED=$((FAILED + 1))
assert_contains "$JUDGE_SMOKE_CONTENT" "extract_result_text" \
    "test-judge-smoke.sh parses host result payloads" || FAILED=$((FAILED + 1))
assert_contains "$JUDGE_SMOKE_CONTENT" "resolve_test_hosts" \
    "test-judge-smoke.sh resolves hosts through the shared helper" || FAILED=$((FAILED + 1))
assert_contains "$JUDGE_SMOKE_CONTENT" 'HOST_TMP_ROOT=$(mktemp -d)' \
    "test-judge-smoke.sh creates fresh slot worktrees per host" || FAILED=$((FAILED + 1))
assert_count "$JUDGE_SMOKE_CONTENT" 'run_host_to_file "\$host" "\$OUTPUT_FILE" "\$HOST_PROMPT" "\$HOST_TIMEOUT" 50 "\$HOST_TMP_ROOT"' 1 \
    "test-judge-smoke.sh runs each host against its own slot worktrees" || FAILED=$((FAILED + 1))

assert_not_contains "$E2E_HAPPY_CONTENT" "Placeholder until the full headless claude -p E2E assertions are implemented" \
    "test-e2e-happy-path.sh is no longer a placeholder" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" 'TEST_HOST="${TEST_HOST:-auto}"' \
    "test-e2e-happy-path.sh defaults to host auto-selection" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" 'if host_available codex && codex_can_host_claude_slots; then' \
    "test-e2e-happy-path.sh prefers Codex only when the Claude bridge is operational" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" "working Codex-to-Claude headless bridge" \
    "test-e2e-happy-path.sh skips explicit Codex hosting when the Claude bridge is unavailable" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" '\$slot-machine' \
    "test-e2e-happy-path.sh uses Codex-native skill syntax when needed" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" '/slot-machine' \
    "test-e2e-happy-path.sh keeps Claude-native skill syntax available" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" 'SKILL_BODY=$(cat "$SKILL_DIR/SKILL.md")' \
    "test-e2e-happy-path.sh inlines the skill body for Codex exec" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" "Base directory for this skill:" \
    "test-e2e-happy-path.sh seeds Codex with the local skill base directory" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" 'slot 1: claude' \
    "test-e2e-happy-path.sh requests explicit Claude slots when hosted in Codex" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" 'slot 2: claude' \
    "test-e2e-happy-path.sh requests two explicit Claude slots when hosted in Codex" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" 'run_host_to_file "$TEST_HOST"' \
    "test-e2e-happy-path.sh invokes the selected host via the shared runner" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" 'extract_result_text "$TEST_HOST" "$TRANSCRIPT_FILE"' \
    "test-e2e-happy-path.sh parses the selected host transcript" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" 'count_dispatch_events "$TEST_HOST" "$TRANSCRIPT_FILE"' \
    "test-e2e-happy-path.sh checks host-neutral dispatch counts" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" "SLOT_MACHINE_TEST_HOST_FILTER" \
    "test-e2e-happy-path.sh honors the runner host filter" || FAILED=$((FAILED + 1))
assert_not_contains "$E2E_HAPPY_CONTENT" "assert_worktree_isolation" \
    "test-e2e-happy-path.sh no longer requires Claude-specific transcript isolation markers" || FAILED=$((FAILED + 1))
assert_contains "$E2E_HAPPY_CONTENT" "result.json" \
    "test-e2e-happy-path.sh checks run artifacts" || FAILED=$((FAILED + 1))

assert_contains "$CLAUDE_CODEX_SMOKE_CONTENT" "run_claude_to_file" \
    "test-claude-host-codex-smoke.sh invokes Claude headlessly" || FAILED=$((FAILED + 1))
assert_contains "$CLAUDE_CODEX_SMOKE_CONTENT" "review-1.md" \
    "test-claude-host-codex-smoke.sh checks review artifacts explicitly" || FAILED=$((FAILED + 1))
assert_contains "$CLAUDE_CODEX_SMOKE_CONTENT" "SLOT_MACHINE_SKILL_DIR" \
    "test-claude-host-codex-smoke.sh can target installed skills" || FAILED=$((FAILED + 1))
assert_contains "$CLAUDE_CODEX_SMOKE_CONTENT" "SLOT_MACHINE_TEST_HOST_FILTER" \
    "test-claude-host-codex-smoke.sh honors the runner host filter" || FAILED=$((FAILED + 1))

assert_contains "$MANUAL_E2E_CONTENT" "handoff.md" \
    "test-e2e-manual-handoff.sh checks handoff artifact output" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_E2E_CONTENT" "resolution_mode" \
    "test-e2e-manual-handoff.sh checks manual result.json discriminator" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_E2E_CONTENT" "Judge Slot Machine results" \
    "test-e2e-manual-handoff.sh asserts judge dispatch is absent" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_E2E_CONTENT" "SLOT_MACHINE_TEST_HOST_FILTER" \
    "test-e2e-manual-handoff.sh honors the runner host filter" || FAILED=$((FAILED + 1))

for file in \
    "$SKILL_DIR/tests/test-e2e-edge-cases.sh" \
    "$SKILL_DIR/tests/test-reviewer-accuracy.sh"; do
    CONTENT=$(cat "$file")
    assert_contains "$CONTENT" "exit 2" \
        "$(basename "$file") exits with explicit skip status" || FAILED=$((FAILED + 1))
done

echo ""
echo "=== Harness Integrity: Test Helpers ==="
HELPERS_CONTENT=$(cat "$SKILL_DIR/tests/test-helpers.sh")
assert_contains "$HELPERS_CONTENT" "run_host_to_file" \
    "test helpers expose a host-neutral runner" || FAILED=$((FAILED + 1))
assert_contains "$HELPERS_CONTENT" "host_available" \
    "test helpers expose host availability detection" || FAILED=$((FAILED + 1))
assert_contains "$HELPERS_CONTENT" "resolve_test_hosts" \
    "test helpers expose shared smoke-host resolution" || FAILED=$((FAILED + 1))
assert_contains "$HELPERS_CONTENT" "codex_can_host_claude_slots" \
    "test helpers expose the Codex-to-Claude bridge probe" || FAILED=$((FAILED + 1))
assert_contains "$HELPERS_CONTENT" 'case "\$host" in' \
    "test helpers dispatch by host" || FAILED=$((FAILED + 1))
assert_contains "$HELPERS_CONTENT" "count_dispatch_events" \
    "test helpers expose host-aware dispatch counting" || FAILED=$((FAILED + 1))
assert_contains "$HELPERS_CONTENT" '"type":"item.started"' \
    "host-aware dispatch counting handles Codex transcript events" || FAILED=$((FAILED + 1))
assert_contains "$HELPERS_CONTENT" 'run_host_to_file claude "\$@"' \
    "run_claude_to_file remains a compatibility wrapper" || FAILED=$((FAILED + 1))
assert_contains "$HELPERS_CONTENT" 'local host="\$1"' \
    "extract_result_text accepts a host argument" || FAILED=$((FAILED + 1))
assert_contains "$HELPERS_CONTENT" 'local output_file="$1"' \
    "extract_result_text keeps the one-argument compatibility path" || FAILED=$((FAILED + 1))

LARGE_OUTPUT=$(python3 - <<'PY'
print("TARGET_START")
print("x" * 200000)
print("TARGET_END")
PY
)
assert_contains "$LARGE_OUTPUT" "TARGET_START" \
    "assert_contains handles large early matches under pipefail" || FAILED=$((FAILED + 1))
assert_not_contains "$LARGE_OUTPUT" "DOES_NOT_EXIST" \
    "assert_not_contains handles large payloads" || FAILED=$((FAILED + 1))
assert_count "$LARGE_OUTPUT" "TARGET_" 2 \
    "assert_count works on large payloads" || FAILED=$((FAILED + 1))
assert_order "$LARGE_OUTPUT" "TARGET_START" "TARGET_END" \
    "assert_order works on large payloads" || FAILED=$((FAILED + 1))

FAKE_BIN_DIR=$(mktemp -d)
RESULT_STREAM=$(mktemp)
trap 'rm -rf "$TMPDIR" "$FAKE_BIN_DIR" "$RESULT_STREAM"' EXIT

cat > "$FAKE_BIN_DIR/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"type":"result","result":"synthetic success"}'
sleep 5
EOF
chmod +x "$FAKE_BIN_DIR/claude"

cat > "$FAKE_BIN_DIR/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"synthetic codex success"}}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
sleep 5
EOF
chmod +x "$FAKE_BIN_DIR/codex"

HELPER_START=$(python3 - <<'PY'
import time
print(time.time())
PY
)
set +e
PATH="$FAKE_BIN_DIR:$PATH" run_host_to_file claude "$RESULT_STREAM" "synthetic prompt" 1 5 "$TMPDIR"
HELPER_STATUS=$?
set -e
HELPER_END=$(python3 - <<'PY'
import time
print(time.time())
PY
)
HELPER_ELAPSED=$(python3 - <<'PY' "$HELPER_START" "$HELPER_END"
import sys
print(float(sys.argv[2]) - float(sys.argv[1]))
PY
)

if [ "$HELPER_STATUS" -eq 0 ] &&
   grep -q '"type":"result"' "$RESULT_STREAM" &&
   [ "$(extract_result_text claude "$RESULT_STREAM")" = "synthetic success" ] &&
   [ "$(extract_result_text "$RESULT_STREAM")" = "synthetic success" ] &&
   python3 - <<'PY' "$HELPER_ELAPSED"
import sys
sys.exit(0 if float(sys.argv[1]) < 3 else 1)
PY
then
    echo "  [PASS] run_host_to_file stops after the Claude result event"
else
    echo "  [FAIL] run_host_to_file does not stop after the Claude result event"
    echo "  Status: $HELPER_STATUS"
    echo "  Elapsed: $HELPER_ELAPSED"
    FAILED=$((FAILED + 1))
fi

HELPER_START=$(python3 - <<'PY'
import time
print(time.time())
PY
)
set +e
PATH="$FAKE_BIN_DIR:$PATH" run_host_to_file codex "$RESULT_STREAM" "synthetic prompt" 1 5 "$TMPDIR"
HELPER_STATUS=$?
set -e
HELPER_END=$(python3 - <<'PY'
import time
print(time.time())
PY
)
HELPER_ELAPSED=$(python3 - <<'PY' "$HELPER_START" "$HELPER_END"
import sys
print(float(sys.argv[2]) - float(sys.argv[1]))
PY
)

if [ "$HELPER_STATUS" -eq 0 ] &&
   grep -q 'synthetic codex success' "$RESULT_STREAM" &&
   [ "$(extract_result_text codex "$RESULT_STREAM")" = "synthetic codex success" ] &&
   python3 - <<'PY' "$HELPER_ELAPSED"
import sys
sys.exit(0 if float(sys.argv[1]) < 3 else 1)
PY
then
    echo "  [PASS] run_host_to_file stops after the Codex turn.completed event"
else
    echo "  [FAIL] run_host_to_file does not stop after the Codex turn.completed event"
    echo "  Status: $HELPER_STATUS"
    echo "  Elapsed: $HELPER_ELAPSED"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=== Harness Integrity: Benchmarks ==="
SPEED_CONTENT=$(cat "$SPEED_BENCH")
VARIABILITY_CONTENT=$(cat "$VARIABILITY_BENCH")

assert_contains "$SPEED_CONTENT" "set -euo pipefail" \
    "Speed benchmark uses strict shell flags" || FAILED=$((FAILED + 1))
assert_contains "$SPEED_CONTENT" 'BENCHMARK_HOST="\${BENCHMARK_HOST:-claude}"' \
    "Speed benchmark accepts BENCHMARK_HOST" || FAILED=$((FAILED + 1))
assert_contains "$SPEED_CONTENT" 'host_available "\$BENCHMARK_HOST"' \
    "Speed benchmark checks benchmark host availability" || FAILED=$((FAILED + 1))
assert_contains "$SPEED_CONTENT" 'run_host_to_file "\$BENCHMARK_HOST"' \
    "Speed benchmark uses the shared host runner" || FAILED=$((FAILED + 1))
assert_contains "$SPEED_CONTENT" 'if \[ "\$b_status" != "OK" \]' \
    "Speed benchmark fails if the baseline run is incomplete" || FAILED=$((FAILED + 1))
assert_contains "$SPEED_CONTENT" 'if \[ "\$sm_status" != "OK" \]' \
    "Speed benchmark fails if the slot-machine run is incomplete" || FAILED=$((FAILED + 1))

assert_contains "$VARIABILITY_CONTENT" "set -euo pipefail" \
    "Variability study uses strict shell flags" || FAILED=$((FAILED + 1))
assert_contains "$VARIABILITY_CONTENT" 'BENCHMARK_HOST="\${BENCHMARK_HOST:-claude}"' \
    "Variability study accepts BENCHMARK_HOST" || FAILED=$((FAILED + 1))
assert_contains "$VARIABILITY_CONTENT" 'host_available "\$BENCHMARK_HOST"' \
    "Variability study checks benchmark host availability" || FAILED=$((FAILED + 1))
assert_contains "$VARIABILITY_CONTENT" 'run_host_to_file "\$BENCHMARK_HOST"' \
    "Variability study uses the shared host runner" || FAILED=$((FAILED + 1))
assert_contains "$VARIABILITY_CONTENT" 'if \[ "\$FAILED_COUNT" -gt 0 \]' \
    "Variability study fails when slot runs fail" || FAILED=$((FAILED + 1))
assert_contains "$VARIABILITY_CONTENT" "missing scheduler.ts or scheduler.test.ts" \
    "Variability study fails on incomplete slot output" || FAILED=$((FAILED + 1))

echo ""
echo "=== Harness Integrity Tests Complete ==="
echo "Failures: $FAILED"
if [ "$FAILED" -eq 0 ]; then
    exit 0
fi
exit 1
