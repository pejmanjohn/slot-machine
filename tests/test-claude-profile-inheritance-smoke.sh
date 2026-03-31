#!/usr/bin/env bash
# Tier 2: Claude-host smoke check for inherited profiles when the skill path is a symlink.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

HOST_FILTER="${SLOT_MACHINE_TEST_HOST_FILTER:-all}"
case "$HOST_FILTER" in
    ""|all|claude) ;;
    codex)
        echo "[SKIP] test-claude-profile-inheritance-smoke.sh requires claude as the primary host"
        exit 2
        ;;
    *)
        echo "[SKIP] unsupported SLOT_MACHINE_TEST_HOST_FILTER: $HOST_FILTER"
        exit 2
        ;;
esac

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

echo "=== Claude Profile Inheritance Smoke Test ==="
echo "Host filter: $HOST_FILTER"

SOURCE_SKILL_DIR="$SKILL_DIR"
TMP_ROOT=$(mktemp -d)
SUCCESS_REPO="$TMP_ROOT/success-repo"
BLOCKED_REPO="$TMP_ROOT/blocked-repo"
INSTALLED_SKILL_LINK="$TMP_ROOT/slot-machine-installed"
SUCCESS_TRANSCRIPT="$TMP_ROOT/success-transcript.jsonl"
BLOCKED_TRANSCRIPT="$TMP_ROOT/blocked-transcript.jsonl"
SPEC_FILE="$SOURCE_SKILL_DIR/tests/fixtures/tiny-spec.md"
KEEP_SMOKE_DIR="${SLOT_MACHINE_KEEP_SMOKE_DIR:-0}"

cleanup() {
    SKILL_DIR="$SOURCE_SKILL_DIR"
    if [ "$KEEP_SMOKE_DIR" = "1" ]; then
        return
    fi
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

ln -s "$SOURCE_SKILL_DIR" "$INSTALLED_SKILL_LINK"
SKILL_DIR="$INSTALLED_SKILL_LINK"

init_python_repo() {
    local repo_dir="$1"

    mkdir -p "$repo_dir/src" "$repo_dir/tests"
    cd "$repo_dir"
    git init -q
    git config user.name "Slot Machine Profile Smoke"
    git config user.email "slot-machine-profile-smoke@example.com"

    cat > pyproject.toml <<'EOF'
[project]
name = "slot-machine-profile-smoke"
version = "0.1.0"

[tool.pytest.ini_options]
testpaths = ["tests"]
EOF

    cat > src/__init__.py <<'EOF'
EOF

    cat > tests/__init__.py <<'EOF'
EOF

    git add -A
    git commit -q -m "initial"
}

assert_success_case() {
    local latest_run result_json verdict_file final_report dispatch_events slots_succeeded verdict_value transcript_text

    init_python_repo "$SUCCESS_REPO"
    mkdir -p "$SUCCESS_REPO/profiles/symlink-inherit"

    cat > "$SUCCESS_REPO/CLAUDE.md" <<'EOF'
slot-machine-profile: symlink-inherit
quiet: true
cleanup: true
EOF

    cat > "$SUCCESS_REPO/profiles/symlink-inherit/0-profile.md" <<'EOF'
---
name: symlink-inherit
description: Regression profile for inherited built-in prompts through a symlinked skill dir.
extends: coding
---
EOF

    set +e
    run_claude_to_file \
        "$SUCCESS_TRANSCRIPT" \
        "/slot-machine with 2 slots

Spec: $(cat "$SPEC_FILE")" \
        1500 \
        220 \
        "$SUCCESS_REPO"
    local claude_rc=$?
    set -e

    transcript_text=$(cat "$SUCCESS_TRANSCRIPT")
    if [ "$claude_rc" -ne 0 ]; then
        echo "  [FAIL] symlinked inheritance happy path exited with code $claude_rc"
        echo "$transcript_text"
        exit 1
    fi

    latest_run="$SUCCESS_REPO/.slot-machine/runs/latest"
    result_json="$latest_run/result.json"
    verdict_file="$latest_run/verdict.md"
    final_report=$(extract_result_text claude "$SUCCESS_TRANSCRIPT")
    dispatch_events=$(count_dispatch_events claude "$SUCCESS_TRANSCRIPT")

    if [ ! -f "$result_json" ]; then
        echo "  [FAIL] missing happy-path result.json at $result_json"
        echo "$transcript_text"
        exit 1
    fi

    slots_succeeded=$(python3 - <<'PY' "$result_json"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data.get("slots_succeeded", 0))
PY
)
    verdict_value=$(python3 - <<'PY' "$result_json"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data.get("verdict", "UNKNOWN"))
PY
)

    if [ "$slots_succeeded" -ge 2 ]; then
        echo "  [PASS] Symlinked installed skill still resolved inherited prompts ($slots_succeeded slots succeeded)"
    else
        echo "  [FAIL] Expected inherited-profile happy path to reach 2 successful slots, found $slots_succeeded"
        echo "$transcript_text"
        exit 1
    fi

    if [ "$dispatch_events" -ge 3 ]; then
        echo "  [PASS] Happy path reached slot dispatch ($dispatch_events dispatch events)"
    else
        echo "  [FAIL] Expected symlinked happy path to reach dispatch, found $dispatch_events events"
        echo "$transcript_text"
        exit 1
    fi

    assert_contains "$verdict_value" "PICK\\|SYNTHESIZE" \
        "Symlinked inheritance happy path produced an actionable verdict"
    if [ -s "$verdict_file" ]; then
        echo "  [PASS] Happy-path verdict artifact written"
    else
        echo "  [FAIL] Missing happy-path verdict artifact at $verdict_file"
        exit 1
    fi
    assert_contains "$final_report" "Final Output\\|Verdict\\|Complete" \
        "Symlinked inheritance happy path returned a final report"
}

assert_blocked_case() {
    local latest_run result_json blocked_mode blocked_stage blocked_reason slots_succeeded dispatch_events transcript_text

    init_python_repo "$BLOCKED_REPO"
    mkdir -p "$BLOCKED_REPO/profiles/missing-base"

    cat > "$BLOCKED_REPO/CLAUDE.md" <<'EOF'
slot-machine-profile: missing-base
quiet: true
cleanup: true
EOF

    cat > "$BLOCKED_REPO/profiles/missing-base/0-profile.md" <<'EOF'
---
name: missing-base
description: Negative test for missing inherited base profile resolution.
extends: definitely-missing-base
---
EOF

    set +e
    run_claude_to_file \
        "$BLOCKED_TRANSCRIPT" \
        "/slot-machine with 2 slots

Spec: $(cat "$SPEC_FILE")" \
        300 \
        120 \
        "$BLOCKED_REPO"
    local claude_rc=$?
    set -e

    transcript_text=$(cat "$BLOCKED_TRANSCRIPT")
    if [ "$claude_rc" -ne 0 ]; then
        echo "  [FAIL] blocked inheritance case exited with code $claude_rc"
        echo "$transcript_text"
        exit 1
    fi

    latest_run="$BLOCKED_REPO/.slot-machine/runs/latest"
    result_json="$latest_run/result.json"

    if [ ! -f "$result_json" ]; then
        echo "  [FAIL] missing blocked result.json at $result_json"
        echo "$transcript_text"
        exit 1
    fi

    blocked_mode=$(python3 - <<'PY' "$result_json"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data.get("resolution_mode", "missing"))
PY
)
    blocked_stage=$(python3 - <<'PY' "$result_json"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data.get("blocked_stage", "missing"))
PY
)
    blocked_reason=$(python3 - <<'PY' "$result_json"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data.get("blocked_reason", ""))
PY
)
    slots_succeeded=$(python3 - <<'PY' "$result_json"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data.get("slots_succeeded", -1))
PY
)
    dispatch_events=$(count_dispatch_events claude "$BLOCKED_TRANSCRIPT")

    if [ "$blocked_mode" = "blocked" ]; then
        echo "  [PASS] Missing inherited base wrote blocked result mode"
    else
        echo "  [FAIL] Expected blocked resolution_mode, found $blocked_mode"
        echo "$transcript_text"
        exit 1
    fi

    if [ "$blocked_stage" = "profile_loading" ]; then
        echo "  [PASS] Missing inherited base reported the blocked stage"
    else
        echo "  [FAIL] Expected blocked_stage=profile_loading, found $blocked_stage"
        echo "$transcript_text"
        exit 1
    fi

    assert_contains "$blocked_reason" "definitely-missing-base\\|profile" \
        "Missing inherited base recorded a human-readable blocked reason"

    if [ "$slots_succeeded" -eq 0 ]; then
        echo "  [PASS] Blocked profile resolution did not mark any slot as succeeded"
    else
        echo "  [FAIL] Expected zero successful slots for blocked profile resolution, found $slots_succeeded"
        echo "$transcript_text"
        exit 1
    fi

    if [ "$dispatch_events" -eq 0 ]; then
        echo "  [PASS] Blocked profile resolution stopped before slot dispatch"
    else
        echo "  [FAIL] Expected blocked profile resolution to stop before dispatch, found $dispatch_events events"
        echo "$transcript_text"
        exit 1
    fi
}

assert_success_case
assert_blocked_case
