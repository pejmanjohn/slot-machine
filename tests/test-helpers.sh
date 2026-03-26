#!/usr/bin/env bash
# Shared helpers for slot-machine skill tests

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Run Claude headless and capture output
# Usage: run_claude "prompt" [timeout_seconds] [max_turns]
run_claude() {
    local prompt="$1"
    local timeout="${2:-600}"
    local max_turns="${3:-100}"
    local output_file=$(mktemp)

    timeout "$timeout" claude -p "$prompt" \
        --allowed-tools=all \
        --permission-mode bypassPermissions \
        --output-format stream-json \
        --max-turns "$max_turns" \
        --add-dir "$SKILL_DIR" \
        > "$output_file" 2>&1 || true

    cat "$output_file"
    rm -f "$output_file"
}

# Assert output contains pattern
assert_contains() {
    local output="$1"
    local pattern="$2"
    local test_name="${3:-test}"

    if echo "$output" | grep -q "$pattern"; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name"
        echo "  Expected to find: $pattern"
        return 1
    fi
}

# Assert output does NOT contain pattern
assert_not_contains() {
    local output="$1"
    local pattern="$2"
    local test_name="${3:-test}"

    if echo "$output" | grep -q "$pattern"; then
        echo "  [FAIL] $test_name"
        echo "  Did not expect to find: $pattern"
        return 1
    else
        echo "  [PASS] $test_name"
        return 0
    fi
}

# Count pattern occurrences
assert_count() {
    local output="$1"
    local pattern="$2"
    local expected="$3"
    local test_name="${4:-test}"

    local actual=$(echo "$output" | grep -c "$pattern" || echo "0")

    if [ "$actual" -eq "$expected" ]; then
        echo "  [PASS] $test_name (found $actual instances)"
        return 0
    else
        echo "  [FAIL] $test_name"
        echo "  Expected $expected instances of: $pattern"
        echo "  Found $actual instances"
        return 1
    fi
}

# Assert pattern A appears before pattern B
assert_order() {
    local output="$1"
    local pattern_a="$2"
    local pattern_b="$3"
    local test_name="${4:-test}"

    local line_a=$(echo "$output" | grep -n "$pattern_a" | head -1 | cut -d: -f1)
    local line_b=$(echo "$output" | grep -n "$pattern_b" | head -1 | cut -d: -f1)

    if [ -z "$line_a" ]; then
        echo "  [FAIL] $test_name: pattern A not found: $pattern_a"
        return 1
    fi
    if [ -z "$line_b" ]; then
        echo "  [FAIL] $test_name: pattern B not found: $pattern_b"
        return 1
    fi
    if [ "$line_a" -lt "$line_b" ]; then
        echo "  [PASS] $test_name (A at line $line_a, B at line $line_b)"
        return 0
    else
        echo "  [FAIL] $test_name"
        echo "  Expected '$pattern_a' before '$pattern_b'"
        echo "  But found A at line $line_a, B at line $line_b"
        return 1
    fi
}

# Count Agent tool dispatches in NDJSON
count_agent_calls() {
    local file="$1"
    grep -c '"name":"Agent"' "$file" 2>/dev/null || echo "0"
}

# Check if Agent calls used worktree isolation
assert_worktree_isolation() {
    local file="$1"
    local test_name="${2:-worktree isolation}"
    if grep -q '"isolation".*"worktree"' "$file"; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name — no isolation:worktree found in Agent calls"
        return 1
    fi
}
