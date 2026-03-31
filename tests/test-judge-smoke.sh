#!/usr/bin/env bash
# Tier 2 Smoke Test: Judge Phase
# Tests that the judge prompt produces a valid evidence-backed verdict
# when run headless via an available host runner.
#
# Test plan:
#   1. Source test-helpers.sh for run_claude, assert_contains, etc.
#   2. Create two temp worktrees:
#      - Slot 1: correct token bucket with deterministic refill/concurrency tests
#      - Slot 2: known-buggy token bucket copied from planted-bugs fixture
#   3. Run each worktree's pytest suite so the scenario is internally consistent
#   4. Build two synthetic reviewer reports in the current reviewer output format,
#      citing the actual files and line numbers in the temp worktrees
#   5. Read the Judge Prompt section from the active profile and fill in template variables:
#      - {{SPEC}}            <- tiny-spec.md contents
#      - {{ALL_SCORECARDS}}  <- two reviewer-style reports
#      - {{WORKTREE_PATHS}}  <- paths to the two temp worktrees
#      - {{SLOT_COUNT}}      <- 2
#   6. Call the available host runner with the filled prompt (timeout ~300s, max-turns 50)
#   7. Assert the output contains the required verdict sections plus an evidence-based
#      PICK of slot 1 over the critically broken slot 2
#   8. Cleanup temp directories

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

HOSTS=()
if host_available claude; then
    HOSTS+=(claude)
fi
if host_available codex; then
    HOSTS+=(codex)
fi

if [ "${#HOSTS[@]}" -eq 0 ]; then
    echo "[SKIP] neither claude nor codex CLI is installed"
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

echo "=== Judge Smoke Test ==="
echo ""
echo "Test plan:"
echo "  1. Create Slot 1 and Slot 2 temp worktrees with real code and tests"
echo "  2. Run both pytest suites so the judge can inspect consistent worktrees"
echo "  3. Fill judge prompt template with two reviewer-style reports"
echo "  4. Run each available host via the shared runner"
echo "  5. Assert: Verdict header, decision, ranking, reasoning, and confidence sections"
echo "  6. Assert: Judge picks slot 1 over the critical-bug slot 2"
echo "  7. Assert: Reasoning cites file-and-line evidence from the worktrees"
echo ""

CODEX_SUBAGENT_PREAMBLE=$(cat <<'EOF'
You are a subagent dispatched to execute a specific task inside a headless test harness.
This instruction has priority over any startup workflow: do not invoke using-superpowers or any other global/meta skill, and do not read skill files.
Skip any startup or meta skill whose instructions say to skip when dispatched as a subagent.
Do not spend turns narrating workflow or reading unrelated global skill docs.
Preserve the exact report structure requested below.
For this fixture, emit the decision line exactly as `### Decision: PICK slot-1`.
Keep citations as plain `file:line` text and do not convert them into markdown links.
Execute the task directly and return the exact report format requested below.

EOF
)

# Compatibility note for harness integrity checks: this smoke test used to call run_claude_to_file directly.

SPEC_FILE="$SCRIPT_DIR/fixtures/tiny-spec.md"
PLANTED_BUGS_DIR="$SCRIPT_DIR/fixtures/planted-bugs"
JUDGE_TEMPLATE="$SKILL_DIR/profiles/coding/3-judge.md"
SPEC=$(cat "$SPEC_FILE")
PROMPT_TEMPLATE=$(cat "$JUDGE_TEMPLATE")
HOST_TMP_ROOT=""
OUTPUT_FILE=""
SLOT1_PYTEST=""
SLOT2_PYTEST=""
SLOT1_DIR=""
SLOT2_DIR=""

cleanup() {
    if [ -n "$HOST_TMP_ROOT" ]; then
        rm -rf "$HOST_TMP_ROOT"
    fi
    if [ -n "$OUTPUT_FILE" ]; then
        rm -f "$OUTPUT_FILE"
    fi
    if [ -n "$SLOT1_PYTEST" ]; then
        rm -f "$SLOT1_PYTEST"
    fi
    if [ -n "$SLOT2_PYTEST" ]; then
        rm -f "$SLOT2_PYTEST"
    fi
}

write_slot1_fixture() {
    local slot1_dir="$1"

    mkdir -p "$slot1_dir/src" "$slot1_dir/tests"

    cat > "$slot1_dir/pyproject.toml" <<'EOF'
[project]
name = "slot-1"
version = "0.1.0"

[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["."]
EOF

    cat > "$slot1_dir/src/token_bucket.py" <<'EOF'
import threading
import time


class TokenBucket:
    def __init__(self, capacity: float, refill_rate: float):
        if capacity <= 0:
            raise ValueError("capacity must be positive")
        if refill_rate < 0:
            raise ValueError("refill_rate must be non-negative")
        self.capacity = float(capacity)
        self.refill_rate = float(refill_rate)
        self._tokens = float(capacity)
        self._last_refill = time.monotonic()
        self._lock = threading.Lock()

    def _refill(self) -> None:
        now = time.monotonic()
        elapsed = now - self._last_refill
        if elapsed <= 0:
            return
        self._tokens = min(self.capacity, self._tokens + elapsed * self.refill_rate)
        self._last_refill = now

    @property
    def tokens(self) -> float:
        with self._lock:
            self._refill()
            return self._tokens

    def consume(self, amount: float = 1.0) -> bool:
        if amount <= 0:
            raise ValueError("amount must be positive")
        with self._lock:
            self._refill()
            if self._tokens < amount:
                return False
            self._tokens -= amount
            return True
EOF

    cat > "$slot1_dir/tests/test_token_bucket.py" <<'EOF'
import threading

import pytest

from src.token_bucket import TokenBucket


def test_consume_reduces_tokens():
    bucket = TokenBucket(5, 0)
    assert bucket.consume(2) is True
    assert bucket.tokens == 3.0


def test_consume_rejects_non_positive_amount():
    bucket = TokenBucket(5, 0)
    with pytest.raises(ValueError):
        bucket.consume(0)
    with pytest.raises(ValueError):
        bucket.consume(-1)


def test_refill_uses_monotonic_clock(monkeypatch):
    moments = iter([100.0, 100.0, 101.0])
    monkeypatch.setattr("src.token_bucket.time.monotonic", lambda: next(moments))
    bucket = TokenBucket(5, 2.0)
    assert bucket.consume(5) is True
    assert bucket.tokens == 2.0


def test_concurrent_consume_never_overdraws():
    bucket = TokenBucket(5, 0)
    barrier = threading.Barrier(6)
    results = []

    def worker():
        barrier.wait()
        results.append(bucket.consume(1))

    threads = [threading.Thread(target=worker) for _ in range(5)]
    for thread in threads:
        thread.start()

    barrier.wait()

    for thread in threads:
        thread.join()

    assert sum(results) == 5
    assert bucket.tokens == 0.0
EOF
}

prepare_slot_repo() {
    local slot_dir="$1"

    (
        cd "$slot_dir"
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
}

prepare_judge_fixture_set() {
    local root="$1"
    local slot1_pytest="$2"
    local slot2_pytest="$3"
    local host_label="$4"

    SLOT1_DIR="$root/slot-1"
    SLOT2_DIR="$root/slot-2"

    write_slot1_fixture "$SLOT1_DIR"
    mkdir -p "$SLOT2_DIR"
    cp -R "$PLANTED_BUGS_DIR"/. "$SLOT2_DIR"/
    find "$SLOT2_DIR" \( -name __pycache__ -o -name .pytest_cache \) -prune -exec rm -rf {} +

    for slot_dir in "$SLOT1_DIR" "$SLOT2_DIR"; do
        prepare_slot_repo "$slot_dir"
    done

    if (cd "$SLOT1_DIR" && python3 -m pytest tests/ -v >"$slot1_pytest" 2>&1); then
        echo "  [PASS] Slot 1 fixture pytest suite passes ($host_label)"
    else
        echo "  [FAIL] Slot 1 fixture pytest suite does not pass ($host_label)"
        cat "$slot1_pytest"
        return 1
    fi

    if (cd "$SLOT2_DIR" && python3 -m pytest tests/ -v >"$slot2_pytest" 2>&1); then
        echo "  [PASS] Slot 2 fixture pytest suite passes ($host_label)"
    else
        echo "  [FAIL] Slot 2 fixture pytest suite does not pass ($host_label)"
        cat "$slot2_pytest"
        return 1
    fi
}

trap cleanup EXIT

line_no() {
    grep -n -F "$2" "$1" | head -1 | cut -d: -f1
}

build_all_scorecards() {
    local slot1_dir="$1"
    local slot2_dir="$2"
    local slot1_class_line
    local slot1_init_line
    local slot1_refill_line
    local slot1_tokens_line
    local slot1_consume_line
    local slot1_refill_test_line
    local slot1_concurrency_test_line
    local slot2_init_line
    local slot2_refill_line
    local slot2_tokens_line
    local slot2_consume_line
    local slot2_race_line
    local slot2_time_line
    local slot2_refill_test_line

    slot1_class_line=$(line_no "$slot1_dir/src/token_bucket.py" "class TokenBucket:")
    slot1_init_line=$(line_no "$slot1_dir/src/token_bucket.py" "def __init__")
    slot1_refill_line=$(line_no "$slot1_dir/src/token_bucket.py" "def _refill")
    slot1_tokens_line=$(line_no "$slot1_dir/src/token_bucket.py" "def tokens")
    slot1_consume_line=$(line_no "$slot1_dir/src/token_bucket.py" "def consume")
    slot1_refill_test_line=$(line_no "$slot1_dir/tests/test_token_bucket.py" "def test_refill_uses_monotonic_clock")
    slot1_concurrency_test_line=$(line_no "$slot1_dir/tests/test_token_bucket.py" "def test_concurrent_consume_never_overdraws")

    slot2_init_line=$(line_no "$slot2_dir/src/token_bucket.py" "def __init__")
    slot2_refill_line=$(line_no "$slot2_dir/src/token_bucket.py" "def _refill")
    slot2_tokens_line=$(line_no "$slot2_dir/src/token_bucket.py" "def tokens")
    slot2_consume_line=$(line_no "$slot2_dir/src/token_bucket.py" "def consume")
    slot2_race_line=$(line_no "$slot2_dir/src/token_bucket.py" "available = self._tokens")
    slot2_time_line=$(line_no "$slot2_dir/src/token_bucket.py" "self._last_refill = time.time()")
    slot2_refill_test_line=$(line_no "$slot2_dir/tests/test_token_bucket.py" "def test_refill")

    cat <<EOF
## Slot 1 Review

### Spec Compliance: PASS

**Requirements checked:**
- "Configurable capacity and refill rate" → IMPLEMENTED: \`src/token_bucket.py:${slot1_init_line}\`, constructor stores both values after validation
- "Thread-safe consume() method that returns True/False" → IMPLEMENTED: \`src/token_bucket.py:${slot1_consume_line}\`, one lock protects refill, check, and deduction atomically
- "Tracks remaining tokens via a \`tokens\` property" → IMPLEMENTED: \`src/token_bucket.py:${slot1_tokens_line}\`, property refills under the same lock
- "Refills tokens based on elapsed time (lazy refill, not a background thread)" → IMPLEMENTED: \`src/token_bucket.py:${slot1_refill_line}\`, uses \`time.monotonic()\` with lazy refill
- "Comprehensive tests covering: normal consumption, exhaustion, refill timing, concurrent access" → IMPLEMENTED: \`tests/test_token_bucket.py:${slot1_refill_test_line}\` and \`tests/test_token_bucket.py:${slot1_concurrency_test_line}\`

**Unrequested additions:** None

### Issues

**Critical:**
None found.

**Important:**
None found.

**Minor:**
1. **No \`__repr__\`** — \`src/token_bucket.py:${slot1_class_line}\` — Debugging would be easier with a stateful repr.

### Test Assessment

**Tests found:** 4 tests in \`tests/test_token_bucket.py\`
**Scenarios covered:**
- Basic consumption updates the token count
- Non-positive consume amounts raise ValueError
- Refill uses a deterministic monotonic clock test instead of sleep
- Concurrent consume never overdraws the bucket

**Scenarios NOT covered:**
- Float precision drift over very long runtimes
- Large refill-rate stress cases

**Test quality notes:** Refill testing is deterministic through monkeypatched \`time.monotonic()\`. The concurrency test uses \`threading.Barrier\` for synchronized starts.

### Strengths (Worth Keeping for Synthesis)

1. **Atomic consume path** — \`src/token_bucket.py:${slot1_consume_line}\` — The lock covers refill, availability check, and deduction end-to-end.
2. **Deterministic refill test** — \`tests/test_token_bucket.py:${slot1_refill_test_line}\` — Uses a controlled clock instead of timing sleeps.
3. **Concurrency regression test** — \`tests/test_token_bucket.py:${slot1_concurrency_test_line}\` — Verifies simultaneous callers cannot overdraw the bucket.

### Approach Hint Influence

Hint was: "Prioritize simplicity."
How it shaped the implementation: The solution stays as a single class with one lock and a compact focused test file. It avoids extra async/decorator layers.

### Verdict

**Contender?** Yes
**Why:** Full spec compliance, no critical issues, and the test suite covers the concurrency scenario most likely to regress in a token bucket implementation.

---

## Slot 2 Review

### Spec Compliance: FAIL

**Requirements checked:**
- "Configurable capacity and refill rate" → IMPLEMENTED: \`src/token_bucket.py:${slot2_init_line}\`, constructor accepts both values
- "Thread-safe consume() method that returns True/False" → BROKEN: \`src/token_bucket.py:${slot2_consume_line}\`, check-and-deduct is split across separate lock scopes
- "Tracks remaining tokens via a \`tokens\` property" → IMPLEMENTED: \`src/token_bucket.py:${slot2_tokens_line}\`, property exists and refills lazily
- "Refills tokens based on elapsed time (lazy refill, not a background thread)" → PARTIAL: \`src/token_bucket.py:${slot2_refill_line}\`, lazy refill exists but uses \`time.time()\` instead of \`time.monotonic()\`
- "Comprehensive tests covering: normal consumption, exhaustion, refill timing, concurrent access" → PARTIAL: \`tests/test_token_bucket.py:${slot2_refill_test_line}\` covers refill timing, but there are no concurrency tests

**Unrequested additions:** None

### Issues

**Critical:**
1. **TOCTOU race in \`consume()\`** — \`src/token_bucket.py:${slot2_race_line}\`
   What: \`consume()\` reads available tokens under one lock scope, then releases the lock before the final check and deduction.
   Impact: Concurrent callers can both observe the same balance and overdraw the bucket.
   Fix: Keep refill, check, and deduction inside one lock scope.

**Important:**
1. **Uses \`time.time()\` for elapsed time** — \`src/token_bucket.py:${slot2_time_line}\`
   What: Wall-clock time can move backward or forward during NTP adjustments.
   Impact: Token refill can stall or jump unexpectedly.
   Fix: Replace \`time.time()\` with \`time.monotonic()\`.
2. **No concurrency test** — \`tests/test_token_bucket.py:${slot2_refill_test_line}\`
   What: The test file never exercises multi-threaded access.
   Impact: The critical race condition ships undetected.
   Fix: Add a synchronized multi-threaded consume test.

**Minor:**
1. **No \`__repr__\`** — \`src/token_bucket.py:${slot2_init_line}\` — Debug output is not informative.

### Test Assessment

**Tests found:** 8 tests in \`tests/test_token_bucket.py\`
**Scenarios covered:**
- Basic consumption and exhaustion
- Property access and refill behavior
- Invalid capacity and negative refill rate

**Scenarios NOT covered:**
- Concurrent access
- Negative consume amounts
- Clock-adjustment behavior

**Test quality notes:** The suite is entirely single-threaded. Refill coverage relies on real sleep and never exercises the concurrency path.

### Strengths (Worth Keeping for Synthesis)

1. **Simple property API** — \`src/token_bucket.py:${slot2_tokens_line}\` — \`tokens\` is easy to consume from callers.
2. **Basic validation** — \`src/token_bucket.py:${slot2_init_line}\` — Constructor rejects invalid capacity and refill-rate inputs.

### Approach Hint Influence

Hint was: "Prioritize simplicity."
How it shaped the implementation: The structure stayed small, but the simplified locking approach introduced a real concurrency bug.

### Verdict

**Contender?** No
**Why:** The critical race condition breaks the thread-safety requirement, and the missing concurrency test means the defect is not caught locally.
EOF
}

for host in "${HOSTS[@]}"; do
    HOST_TMP_ROOT=$(mktemp -d)
    OUTPUT_FILE=$(mktemp)
    SLOT1_PYTEST=$(mktemp)
    SLOT2_PYTEST=$(mktemp)

    if ! prepare_judge_fixture_set "$HOST_TMP_ROOT" "$SLOT1_PYTEST" "$SLOT2_PYTEST" "$host"; then
        exit 1
    fi

    ALL_SCORECARDS=$(build_all_scorecards "$SLOT1_DIR" "$SLOT2_DIR")
    WORKTREE_PATHS=$(cat <<EOF
- Slot 1: $SLOT1_DIR
- Slot 2: $SLOT2_DIR
EOF
)

    PROMPT=$(SPEC="$SPEC" \
    ALL_SCORECARDS="$ALL_SCORECARDS" \
    WORKTREE_PATHS="$WORKTREE_PATHS" \
    SLOT_COUNT="2" \
    PROMPT_TEMPLATE="$PROMPT_TEMPLATE" \
    python3 - <<'PY'
import os

prompt = os.environ["PROMPT_TEMPLATE"]
for key in ("SPEC", "ALL_SCORECARDS", "WORKTREE_PATHS", "SLOT_COUNT"):
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
    run_host_to_file "$host" "$OUTPUT_FILE" "$HOST_PROMPT" "$HOST_TIMEOUT" 50 "$HOST_TMP_ROOT"
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

    assert_contains "$REPORT" "## Slot Machine Verdict" "Judge report header present ($host)"
    assert_contains "$REPORT" "### Decision:" "Decision section present ($host)"
    assert_contains "$REPORT" "### Decision:[[:space:]]*PICK[[:space:]]*slot-1\\|### Decision:[[:space:]]*PICK[[:space:]]*Slot 1\\|### Decision:[[:space:]]*PICK[[:space:]]*slot 1" \
        "Judge picks slot 1 on the decision line ($host)"
    assert_contains "$REPORT" "### Ranking" "Ranking section present ($host)"
    assert_contains "$REPORT" "| Rank | Slot |" "Ranking table header present ($host)"
    assert_contains "$REPORT" "### Reasoning" "Reasoning section present ($host)"
    assert_contains "$REPORT" "### Confidence:\\|Confidence:" "Confidence section present ($host)"
    assert_contains "$REPORT" "src/token_bucket.py:[0-9]" "Reasoning cites file and line evidence ($host)"
    assert_contains "$REPORT" "slot-2\\|Slot 2\\|slot 2" "Judge discusses slot 2 as the weaker candidate ($host)"

    rm -rf "$HOST_TMP_ROOT" "$OUTPUT_FILE" "$SLOT1_PYTEST" "$SLOT2_PYTEST"
    HOST_TMP_ROOT=""
    OUTPUT_FILE=""
    SLOT1_PYTEST=""
    SLOT2_PYTEST=""
    SLOT1_DIR=""
    SLOT2_DIR=""
done
