#!/usr/bin/env bash
# Shared helpers for slot-machine skill tests

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Run Claude headless and capture NDJSON stream to a file.
# Usage: run_claude_to_file output_file "prompt" [timeout_seconds] [max_turns] [cwd]
run_claude_to_file() {
    local output_file="$1"
    local prompt="$2"
    local timeout_seconds="${3:-600}"
    local max_turns="${4:-100}"
    local cwd="${5:-$SKILL_DIR}"

    if ! command -v claude >/dev/null 2>&1; then
        echo "[SKIP] claude CLI not installed" > "$output_file"
        return 2
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "[SKIP] python3 not installed" > "$output_file"
        return 2
    fi

    python3 - "$cwd" "$output_file" "$timeout_seconds" "$max_turns" "$SKILL_DIR" "$prompt" <<'PY'
import json
import pathlib
import selectors
import subprocess
import sys
import time

cwd = sys.argv[1]
output_file = sys.argv[2]
timeout_seconds = int(sys.argv[3])
max_turns = sys.argv[4]
skill_dir = sys.argv[5]
prompt = sys.argv[6]

pathlib.Path(output_file).parent.mkdir(parents=True, exist_ok=True)

cmd = [
    "claude",
    "-p",
    prompt,
    "--allowed-tools=all",
    "--permission-mode",
    "bypassPermissions",
    "--output-format",
    "stream-json",
    "--verbose",
    "--max-turns",
    max_turns,
    "--add-dir",
    skill_dir,
]

try:
    with open(output_file, "w", encoding="utf-8") as out:
        proc = subprocess.Popen(
            cmd,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        selector = selectors.DefaultSelector()
        if proc.stdout is not None:
            selector.register(proc.stdout, selectors.EVENT_READ)

        deadline = time.monotonic() + timeout_seconds
        saw_result = False

        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(cmd=cmd, timeout=timeout_seconds)

            events = selector.select(timeout=min(0.2, remaining))
            if not events:
                if proc.poll() is not None:
                    break
                continue

            for key, _ in events:
                line = key.fileobj.readline()
                if line == "":
                    selector.unregister(key.fileobj)
                    continue

                out.write(line)
                out.flush()

                try:
                    payload = json.loads(line)
                except json.JSONDecodeError:
                    continue

                if payload.get("type") == "result":
                    saw_result = True
                    proc.terminate()
                    try:
                        proc.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=2)
                    break

            if saw_result:
                break

        if proc.poll() is None:
            proc.wait(timeout=2)

        if saw_result:
            sys.exit(0)

        sys.exit(proc.returncode or 0)
except subprocess.TimeoutExpired:
    if 'proc' in locals() and proc.poll() is None:
        proc.kill()
        proc.wait(timeout=2)
    with open(output_file, "a", encoding="utf-8") as out:
        out.write('\n{"type":"local_test_event","status":"timeout"}\n')
    sys.exit(124)
PY
}

# Run Claude headless and print the NDJSON stream.
# Usage: run_claude "prompt" [timeout_seconds] [max_turns] [cwd]
run_claude() {
    local prompt="$1"
    local timeout_seconds="${2:-600}"
    local max_turns="${3:-100}"
    local cwd="${4:-$SKILL_DIR}"
    local output_file
    output_file=$(mktemp)

    run_claude_to_file "$output_file" "$prompt" "$timeout_seconds" "$max_turns" "$cwd"
    local rc=$?
    cat "$output_file"
    rm -f "$output_file"
    return "$rc"
}

# Extract the final text result from a Claude stream-json output file.
# Usage: extract_result_text path/to/output.jsonl
extract_result_text() {
    local output_file="$1"

    python3 - "$output_file" <<'PY'
import json
import sys

result = ""
with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if payload.get("type") == "result":
            result = payload.get("result", "")

print(result)
PY
}

# Assert output contains pattern
assert_contains() {
    local output="$1"
    local pattern="$2"
    local test_name="${3:-test}"

    if grep -q -- "$pattern" <<<"$output"; then
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

    if grep -q -- "$pattern" <<<"$output"; then
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

    local actual
    actual=$(grep -c -- "$pattern" <<<"$output" || echo "0")

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

    local line_a
    local line_b
    line_a=$(grep -n -- "$pattern_a" <<<"$output" | head -1 | cut -d: -f1)
    line_b=$(grep -n -- "$pattern_b" <<<"$output" | head -1 | cut -d: -f1)

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
