#!/usr/bin/env bash
# Tier 2 Smoke Test: Judge Phase
# Tests that the judge prompt produces a valid evidence-backed verdict
# when run headless via `claude -p`.
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
#   6. Call run_claude_to_file with the filled prompt (timeout ~300s, max-turns 50)
#   7. Assert the output contains the required verdict sections plus an evidence-based
#      PICK of slot 1 over the critically broken slot 2
#   8. Cleanup temp directories

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

echo "=== Judge Smoke Test ==="
echo ""
echo "Test plan:"
echo "  1. Create Slot 1 and Slot 2 temp worktrees with real code and tests"
echo "  2. Run both pytest suites so the judge can inspect consistent worktrees"
echo "  3. Fill judge prompt template with two reviewer-style reports"
echo "  4. Run claude -p with filled prompt"
echo "  5. Assert: Verdict header, decision, ranking, reasoning, and confidence sections"
echo "  6. Assert: Judge picks slot 1 over the critical-bug slot 2"
echo "  7. Assert: Reasoning cites file-and-line evidence from the worktrees"
echo ""

SPEC_FILE="$SCRIPT_DIR/fixtures/tiny-spec.md"
PLANTED_BUGS_DIR="$SCRIPT_DIR/fixtures/planted-bugs"
JUDGE_TEMPLATE="$SKILL_DIR/profiles/coding/3-judge.md"
TMP_ROOT=$(mktemp -d)
OUTPUT_FILE=$(mktemp)
SLOT1_PYTEST=$(mktemp)
SLOT2_PYTEST=$(mktemp)
trap 'rm -rf "$TMP_ROOT" "$OUTPUT_FILE" "$SLOT1_PYTEST" "$SLOT2_PYTEST"' EXIT

SLOT1_DIR="$TMP_ROOT/slot-1"
SLOT2_DIR="$TMP_ROOT/slot-2"
mkdir -p "$SLOT1_DIR/src" "$SLOT1_DIR/tests"

cat > "$SLOT1_DIR/pyproject.toml" <<'EOF'
[project]
name = "slot-1"
version = "0.1.0"

[tool.pytest.ini_options]
testpaths = ["tests"]
EOF

cat > "$SLOT1_DIR/src/token_bucket.py" <<'EOF'
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

cat > "$SLOT1_DIR/tests/test_token_bucket.py" <<'EOF'
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

cp -R "$PLANTED_BUGS_DIR"/. "$SLOT2_DIR"/
find "$SLOT2_DIR" \( -name __pycache__ -o -name .pytest_cache \) -prune -exec rm -rf {} +

for slot_dir in "$SLOT1_DIR" "$SLOT2_DIR"; do
    cd "$slot_dir"
    git init -q
    git config user.name "Slot Machine Smoke"
    git config user.email "slot-machine-smoke@example.com"
    git add -A
    git commit -q -m "initial fixture"
done

if (cd "$SLOT1_DIR" && python3 -m pytest tests/ -v >"$SLOT1_PYTEST" 2>&1); then
    echo "  [PASS] Slot 1 fixture pytest suite passes"
else
    echo "  [FAIL] Slot 1 fixture pytest suite does not pass"
    cat "$SLOT1_PYTEST"
    exit 1
fi

if (cd "$SLOT2_DIR" && python3 -m pytest tests/ -v >"$SLOT2_PYTEST" 2>&1); then
    echo "  [PASS] Slot 2 fixture pytest suite passes"
else
    echo "  [FAIL] Slot 2 fixture pytest suite does not pass"
    cat "$SLOT2_PYTEST"
    exit 1
fi

line_no() {
    grep -n -F "$2" "$1" | head -1 | cut -d: -f1
}

SLOT1_CLASS_LINE=$(line_no "$SLOT1_DIR/src/token_bucket.py" "class TokenBucket:")
SLOT1_INIT_LINE=$(line_no "$SLOT1_DIR/src/token_bucket.py" "def __init__")
SLOT1_REFILL_LINE=$(line_no "$SLOT1_DIR/src/token_bucket.py" "def _refill")
SLOT1_TOKENS_LINE=$(line_no "$SLOT1_DIR/src/token_bucket.py" "def tokens")
SLOT1_CONSUME_LINE=$(line_no "$SLOT1_DIR/src/token_bucket.py" "def consume")
SLOT1_REFILL_TEST_LINE=$(line_no "$SLOT1_DIR/tests/test_token_bucket.py" "def test_refill_uses_monotonic_clock")
SLOT1_CONCURRENCY_TEST_LINE=$(line_no "$SLOT1_DIR/tests/test_token_bucket.py" "def test_concurrent_consume_never_overdraws")

SLOT2_INIT_LINE=$(line_no "$SLOT2_DIR/src/token_bucket.py" "def __init__")
SLOT2_REFILL_LINE=$(line_no "$SLOT2_DIR/src/token_bucket.py" "def _refill")
SLOT2_TOKENS_LINE=$(line_no "$SLOT2_DIR/src/token_bucket.py" "def tokens")
SLOT2_CONSUME_LINE=$(line_no "$SLOT2_DIR/src/token_bucket.py" "def consume")
SLOT2_RACE_LINE=$(line_no "$SLOT2_DIR/src/token_bucket.py" "available = self._tokens")
SLOT2_TIME_LINE=$(line_no "$SLOT2_DIR/src/token_bucket.py" "self._last_refill = time.time()")
SLOT2_REFILL_TEST_LINE=$(line_no "$SLOT2_DIR/tests/test_token_bucket.py" "def test_refill")

ALL_SCORECARDS=$(cat <<EOF
## Slot 1 Review

### Spec Compliance: PASS

**Requirements checked:**
- "Configurable capacity and refill rate" → IMPLEMENTED: \`src/token_bucket.py:${SLOT1_INIT_LINE}\`, constructor stores both values after validation
- "Thread-safe consume() method that returns True/False" → IMPLEMENTED: \`src/token_bucket.py:${SLOT1_CONSUME_LINE}\`, one lock protects refill, check, and deduction atomically
- "Tracks remaining tokens via a \`tokens\` property" → IMPLEMENTED: \`src/token_bucket.py:${SLOT1_TOKENS_LINE}\`, property refills under the same lock
- "Refills tokens based on elapsed time (lazy refill, not a background thread)" → IMPLEMENTED: \`src/token_bucket.py:${SLOT1_REFILL_LINE}\`, uses \`time.monotonic()\` with lazy refill
- "Comprehensive tests covering: normal consumption, exhaustion, refill timing, concurrent access" → IMPLEMENTED: \`tests/test_token_bucket.py:${SLOT1_REFILL_TEST_LINE}\` and \`tests/test_token_bucket.py:${SLOT1_CONCURRENCY_TEST_LINE}\`

**Unrequested additions:** None

### Issues

**Critical:**
None found.

**Important:**
None found.

**Minor:**
1. **No \`__repr__\`** — \`src/token_bucket.py:${SLOT1_CLASS_LINE}\` — Debugging would be easier with a stateful repr.

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

1. **Atomic consume path** — \`src/token_bucket.py:${SLOT1_CONSUME_LINE}\` — The lock covers refill, availability check, and deduction end-to-end.
2. **Deterministic refill test** — \`tests/test_token_bucket.py:${SLOT1_REFILL_TEST_LINE}\` — Uses a controlled clock instead of timing sleeps.
3. **Concurrency regression test** — \`tests/test_token_bucket.py:${SLOT1_CONCURRENCY_TEST_LINE}\` — Verifies simultaneous callers cannot overdraw the bucket.

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
- "Configurable capacity and refill rate" → IMPLEMENTED: \`src/token_bucket.py:${SLOT2_INIT_LINE}\`, constructor accepts both values
- "Thread-safe consume() method that returns True/False" → BROKEN: \`src/token_bucket.py:${SLOT2_CONSUME_LINE}\`, check-and-deduct is split across separate lock scopes
- "Tracks remaining tokens via a \`tokens\` property" → IMPLEMENTED: \`src/token_bucket.py:${SLOT2_TOKENS_LINE}\`, property exists and refills lazily
- "Refills tokens based on elapsed time (lazy refill, not a background thread)" → PARTIAL: \`src/token_bucket.py:${SLOT2_REFILL_LINE}\`, lazy refill exists but uses \`time.time()\` instead of \`time.monotonic()\`
- "Comprehensive tests covering: normal consumption, exhaustion, refill timing, concurrent access" → PARTIAL: \`tests/test_token_bucket.py:${SLOT2_REFILL_TEST_LINE}\` covers refill timing, but there are no concurrency tests

**Unrequested additions:** None

### Issues

**Critical:**
1. **TOCTOU race in \`consume()\`** — \`src/token_bucket.py:${SLOT2_RACE_LINE}\`
   What: \`consume()\` reads available tokens under one lock scope, then releases the lock before the final check and deduction.
   Impact: Concurrent callers can both observe the same balance and overdraw the bucket.
   Fix: Keep refill, check, and deduction inside one lock scope.

**Important:**
1. **Uses \`time.time()\` for elapsed time** — \`src/token_bucket.py:${SLOT2_TIME_LINE}\`
   What: Wall-clock time can move backward or forward during NTP adjustments.
   Impact: Token refill can stall or jump unexpectedly.
   Fix: Replace \`time.time()\` with \`time.monotonic()\`.
2. **No concurrency test** — \`tests/test_token_bucket.py:${SLOT2_REFILL_TEST_LINE}\`
   What: The test file never exercises multi-threaded access.
   Impact: The critical race condition ships undetected.
   Fix: Add a synchronized multi-threaded consume test.

**Minor:**
1. **No \`__repr__\`** — \`src/token_bucket.py:${SLOT2_INIT_LINE}\` — Debug output is not informative.

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

1. **Simple property API** — \`src/token_bucket.py:${SLOT2_TOKENS_LINE}\` — \`tokens\` is easy to consume from callers.
2. **Basic validation** — \`src/token_bucket.py:${SLOT2_INIT_LINE}\` — Constructor rejects invalid capacity and refill-rate inputs.

### Approach Hint Influence

Hint was: "Prioritize simplicity."
How it shaped the implementation: The structure stayed small, but the simplified locking approach introduced a real concurrency bug.

### Verdict

**Contender?** No
**Why:** The critical race condition breaks the thread-safety requirement, and the missing concurrency test means the defect is not caught locally.
EOF
)

WORKTREE_PATHS=$(cat <<EOF
- Slot 1: $SLOT1_DIR
- Slot 2: $SLOT2_DIR
EOF
)

SPEC=$(cat "$SPEC_FILE")
PROMPT_TEMPLATE=$(cat "$JUDGE_TEMPLATE")

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

set +e
run_claude_to_file "$OUTPUT_FILE" "$PROMPT" 300 50 "$TMP_ROOT"
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

assert_contains "$REPORT" "## Slot Machine Verdict" "Judge report header present"
assert_contains "$REPORT" "### Decision:" "Decision section present"
assert_contains "$REPORT" "PICK" "Judge makes a PICK decision"
assert_contains "$REPORT" "slot-1\\|Slot 1\\|slot 1" "Judge selects slot 1"
assert_contains "$REPORT" "### Ranking" "Ranking section present"
assert_contains "$REPORT" "| Rank | Slot |" "Ranking table header present"
assert_contains "$REPORT" "### Reasoning" "Reasoning section present"
assert_contains "$REPORT" "### Confidence:\\|Confidence:" "Confidence section present"
assert_contains "$REPORT" "src/token_bucket.py:[0-9]" "Reasoning cites file and line evidence"
assert_contains "$REPORT" "slot-2\\|Slot 2\\|slot 2" "Judge discusses slot 2 as the weaker candidate"
