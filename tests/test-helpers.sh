#!/usr/bin/env bash
# Shared helpers for slot-machine skill tests

DEFAULT_SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="${SLOT_MACHINE_SKILL_DIR:-$DEFAULT_SKILL_DIR}"

host_available() {
    case "$1" in
        claude) command -v claude >/dev/null 2>&1 ;;
        codex) command -v codex >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

normalize_test_host_filter() {
    case "${1:-all}" in
        ""|all) echo "all" ;;
        claude|codex) echo "$1" ;;
        *) return 1 ;;
    esac
}

resolve_test_hosts() {
    local filter
    filter="$(normalize_test_host_filter "${1:-${SLOT_MACHINE_TEST_HOST_FILTER:-all}}")" || return 1

    case "$filter" in
        all)
            host_available claude && echo "claude"
            host_available codex && echo "codex"
            ;;
        claude|codex)
            host_available "$filter" && echo "$filter"
            ;;
    esac
}

host_filter_allows() {
    local requested_host="$1"
    local filter
    filter="$(normalize_test_host_filter "${SLOT_MACHINE_TEST_HOST_FILTER:-all}")" || return 1

    [ "$filter" = "all" ] || [ "$filter" = "$requested_host" ]
}

codex_can_host_claude_slots() {
    if ! host_available codex || ! host_available claude; then
        return 1
    fi

    local tmpdir
    local output_file
    local prompt
    local rc
    local result

    tmpdir=$(mktemp -d)
    output_file=$(mktemp)
    prompt=$(cat <<'EOF'
Use Bash only.

Run this exact command in the current directory:

claude -p "Reply with OK and nothing else." --output-format stream-json --verbose --max-turns 1

Return exactly one line:
SUCCESS

only if the command exits 0 and the final Claude result text is exactly:
OK

Otherwise return exactly one line beginning with:
FAILURE:
EOF
)

    if run_host_to_file codex "$output_file" "$prompt" 90 6 "$tmpdir" >/dev/null 2>&1; then
        rc=0
    else
        rc=$?
    fi
    result=$(extract_result_text codex "$output_file")

    rm -rf "$tmpdir"
    rm -f "$output_file"

    [ "$rc" -eq 0 ] && [ "$result" = "SUCCESS" ]
}

run_host_to_file() {
    local host="$1"
    local output_file="$2"
    local prompt="$3"
    local timeout_seconds="${4:-600}"
    local max_turns="${5:-100}"
    local cwd="${6:-$SKILL_DIR}"

    case "$host" in
        claude) _run_claude_to_file "$output_file" "$prompt" "$timeout_seconds" "$max_turns" "$cwd" ;;
        codex) _run_codex_to_file "$output_file" "$prompt" "$timeout_seconds" "$max_turns" "$cwd" ;;
        *) echo "[SKIP] unsupported host: $host" > "$output_file"; return 2 ;;
    esac
}

run_claude_to_file() {
    run_host_to_file claude "$@"
}

_run_claude_to_file() {
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

_run_codex_to_file() {
    local output_file="$1"
    local prompt="$2"
    local timeout_seconds="${3:-600}"
    local max_turns="${4:-100}"
    local cwd="${5:-$SKILL_DIR}"

    if ! command -v codex >/dev/null 2>&1; then
        echo "[SKIP] codex CLI not installed" > "$output_file"
        return 2
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "[SKIP] python3 not installed" > "$output_file"
        return 2
    fi

    python3 - "$cwd" "$output_file" "$timeout_seconds" "$max_turns" "$prompt" <<'PY'
import json
import pathlib
import queue
import subprocess
import sys
import threading
import time

cwd = sys.argv[1]
output_file = sys.argv[2]
timeout_seconds = int(sys.argv[3])
prompt = sys.argv[5]

pathlib.Path(output_file).parent.mkdir(parents=True, exist_ok=True)

cmd = [
    "codex",
    "exec",
    "--json",
    "-s",
    "workspace-write",
    "--skip-git-repo-check",
    "-C",
    cwd,
    prompt,
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
        lines = queue.Queue()

        def reader() -> None:
            assert proc.stdout is not None
            for line in proc.stdout:
                lines.put(line)
            lines.put(None)

        reader_thread = threading.Thread(target=reader, daemon=True)
        reader_thread.start()

        deadline = time.monotonic() + timeout_seconds
        saw_turn_completed = False

        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(cmd=cmd, timeout=timeout_seconds)

            try:
                line = lines.get(timeout=min(0.2, remaining))
            except queue.Empty:
                if proc.poll() is not None:
                    break
                continue

            if line is None:
                break

            out.write(line)
            out.flush()

            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue

            if payload.get("type") == "turn.completed":
                saw_turn_completed = True
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2)
                break

        if proc.poll() is None:
            proc.wait(timeout=2)

        if saw_turn_completed:
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

# Extract the final text result from a host transcript file.
# Usage: extract_result_text path/to/output.jsonl
# Usage: extract_result_text host path/to/output.jsonl
extract_result_text() {
    local host
    local output_file

    if [ "$#" -eq 1 ]; then
        host="claude"
        output_file="$1"
    else
        host="$1"
        output_file="$2"
    fi

    python3 - "$host" "$output_file" <<'PY'
import json
import sys

host = sys.argv[1]
path = sys.argv[2]
result = ""

with open(path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue

        if host == "claude" and payload.get("type") == "result":
            result = payload.get("result", "")
        elif host == "codex" and payload.get("type") == "item.completed":
            item = payload.get("item", {})
            if item.get("type") == "agent_message":
                result = item.get("text", "")

print(result)
PY
}

# Count host dispatches in a transcript file.
# Usage: count_dispatch_events path/to/output.jsonl
# Usage: count_dispatch_events host path/to/output.jsonl
count_dispatch_events() {
    local host
    local output_file

    if [ "$#" -eq 1 ]; then
        host="claude"
        output_file="$1"
    else
        host="$1"
        output_file="$2"
    fi

    case "$host" in
        claude) grep -c '"name":"Agent"' "$output_file" 2>/dev/null || echo "0" ;;
        codex) grep -c '"type":"item.started"' "$output_file" 2>/dev/null || echo "0" ;;
        *) echo "0" ;;
    esac
}

# Backward-compatible alias for earlier host-neutral naming.
count_host_dispatches() {
    count_dispatch_events "$@"
}

# Backward-compatible Claude-only dispatch counter.
count_agent_calls() {
    count_dispatch_events claude "$@"
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
