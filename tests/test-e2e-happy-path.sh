#!/usr/bin/env bash
# Tier 3: Full E2E integration test — happy path
#
# Full E2E: invoke slot-machine with 3 slots on a real spec,
# verify the entire pipeline via NDJSON transcript analysis.
#
# Compare against baseline (without skill):
#   tests/fixtures/baseline-transcript-0de344b8.jsonl
#
# Baseline gaps this test should verify are NOW present:
#   - Independent reviewer agents dispatched (not orchestrator reading code)
#   - Structured scorecards with 6 weighted criteria
#   - Formal judge agent with PICK/SYNTHESIZE/NONE_ADEQUATE verdict
#   - Dedicated synthesizer agent (if SYNTHESIZE)
#   - Worktree cleanup after completion
#
# Runtime: ~20-30 minutes (headless claude -p)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

BASELINE_TRANSCRIPT="$SCRIPT_DIR/fixtures/baseline-transcript-0de344b8.jsonl"
TINY_SPEC="$SCRIPT_DIR/fixtures/tiny-spec.md"

echo "=== E2E Happy Path Test ==="
echo ""

# ---------------------------------------------------------------------------
# Phase 1: Setup — create temp test project
# ---------------------------------------------------------------------------
#
# TMPDIR=$(mktemp -d)
# trap 'rm -rf "$TMPDIR"' EXIT
#
# cd "$TMPDIR"
# git init
# mkdir -p src tests
#
# # Minimal Python project structure
# cat > pyproject.toml <<'PYPROJ'
# [project]
# name = "test-project"
# version = "0.1.0"
#
# [tool.pytest.ini_options]
# testpaths = ["tests"]
# PYPROJ
#
# cat > src/__init__.py <<'PY'
# PY
#
# cat > tests/__init__.py <<'PY'
# PY
#
# git add -A && git commit -m "initial commit"

echo "Phase 1: Setup"
echo "  - Create temp directory with git init"
echo "  - Minimal Python project (src/, tests/, pyproject.toml)"
echo "  - Initial commit so worktrees can be created"
echo ""

# ---------------------------------------------------------------------------
# Phase 2: Execute — run slot-machine skill via claude -p
# ---------------------------------------------------------------------------
#
# SPEC_CONTENT=$(cat "$TINY_SPEC")
# TRANSCRIPT="$TMPDIR/transcript.jsonl"
#
# timeout 1800 claude -p \
#     "Use the slot-machine skill to implement the following spec with 3 slots:
#
# $SPEC_CONTENT" \
#     --allowed-tools=all \
#     --permission-mode bypassPermissions \
#     --output-format stream-json \
#     --max-turns 200 \
#     --add-dir "$SKILL_DIR" \
#     --add-dir "$TMPDIR" \
#     > "$TRANSCRIPT" 2>&1 || true
#
# # Sanity: transcript must not be empty
# if [ ! -s "$TRANSCRIPT" ]; then
#     echo "  [FAIL] Transcript is empty — claude -p produced no output"
#     exit 1
# fi
# TRANSCRIPT_TEXT=$(cat "$TRANSCRIPT")

echo "Phase 2: Execute"
echo "  - Run claude -p with slot-machine skill (3 slots)"
echo "  - Capture NDJSON stream to transcript file"
echo "  - Timeout: 1800s (30 min)"
echo "  - --add-dir for skill root AND test project"
echo ""

# ---------------------------------------------------------------------------
# Phase 3: Phase ordering assertions
# ---------------------------------------------------------------------------
#
# echo "=== Phase Ordering ==="
#
# # Skill announcement
# assert_contains "$TRANSCRIPT_TEXT" "slot-machine" \
#     "Skill name mentioned in transcript"
#
# # Agent calls with worktree isolation
# assert_worktree_isolation "$TRANSCRIPT" \
#     "Agent calls use isolation:worktree"
#
# # Slot mentions (implementation phase)
# assert_contains "$TRANSCRIPT_TEXT" "Slot 1" \
#     "Slot 1 mentioned"
# assert_contains "$TRANSCRIPT_TEXT" "Slot 2" \
#     "Slot 2 mentioned"
# assert_contains "$TRANSCRIPT_TEXT" "Slot 3" \
#     "Slot 3 mentioned"
#
# # Phase ordering: implementation before review, review before judge
# assert_order "$TRANSCRIPT_TEXT" "Slot 1" "Scorecard" \
#     "Implementation before review"
# assert_order "$TRANSCRIPT_TEXT" "Scorecard" "verdict" \
#     "Review before judge"

echo "Phase 3: Phase ordering assertions"
echo "  - Skill 'slot-machine' announced in transcript"
echo "  - Agent calls use isolation:worktree"
echo "  - Slot 1, Slot 2, Slot 3 all mentioned"
echo "  - Implementation phase precedes review phase"
echo "  - Review phase precedes judge phase"
echo ""

# ---------------------------------------------------------------------------
# Phase 4: Review phase assertions
# ---------------------------------------------------------------------------
#
# echo "=== Review Phase ==="
#
# # Structured scorecards present
# assert_contains "$TRANSCRIPT_TEXT" "Scorecard" \
#     "Scorecard present in output"
# assert_contains "$TRANSCRIPT_TEXT" "Weighted Score" \
#     "Weighted Score present in output"
#
# # 6 weighted criteria from reviewer prompt
# for criterion in "Spec Compliance" "Correctness" "Test Quality" \
#                   "Code Quality" "Simplicity" "Architecture"; do
#     assert_contains "$TRANSCRIPT_TEXT" "$criterion" \
#         "Criterion '$criterion' in scorecard"
# done
#
# # Severity levels in issue lists
# SEVERITY_FOUND=false
# for severity in CRITICAL IMPORTANT MINOR; do
#     if echo "$TRANSCRIPT_TEXT" | grep -q "$severity"; then
#         SEVERITY_FOUND=true
#     fi
# done
# if [ "$SEVERITY_FOUND" = true ]; then
#     echo "  [PASS] At least one severity level (CRITICAL/IMPORTANT/MINOR) found"
# else
#     echo "  [FAIL] No severity levels found in review output"
# fi
#
# # Independent reviewers dispatched (not orchestrator reading code)
# REVIEWER_AGENT_COUNT=$(count_agent_calls "$TRANSCRIPT")
# if [ "$REVIEWER_AGENT_COUNT" -ge 3 ]; then
#     echo "  [PASS] At least 3 Agent calls found ($REVIEWER_AGENT_COUNT total)"
# else
#     echo "  [FAIL] Expected >= 3 Agent calls, found $REVIEWER_AGENT_COUNT"
# fi

echo "Phase 4: Review phase assertions"
echo "  - Scorecard present in output"
echo "  - Weighted Score present in output"
echo "  - All 6 criteria present: Spec Compliance, Correctness, Test Quality,"
echo "    Code Quality, Simplicity, Architecture"
echo "  - At least one severity level (CRITICAL/IMPORTANT/MINOR) found"
echo "  - Independent reviewer agents dispatched (>= 3 Agent calls)"
echo ""

# ---------------------------------------------------------------------------
# Phase 5: Judge phase assertions
# ---------------------------------------------------------------------------
#
# echo "=== Judge Phase ==="
#
# # Verdict present — one of PICK, SYNTHESIZE, NONE_ADEQUATE
# VERDICT_FOUND=false
# VERDICT_VALUE=""
# for verdict in PICK SYNTHESIZE NONE_ADEQUATE; do
#     if echo "$TRANSCRIPT_TEXT" | grep -q "$verdict"; then
#         VERDICT_FOUND=true
#         VERDICT_VALUE="$verdict"
#     fi
# done
# if [ "$VERDICT_FOUND" = true ]; then
#     echo "  [PASS] Verdict found: $VERDICT_VALUE"
# else
#     echo "  [FAIL] No verdict (PICK/SYNTHESIZE/NONE_ADEQUATE) found"
# fi
#
# # Ranking present
# assert_contains "$TRANSCRIPT_TEXT" "Ranking" \
#     "Ranking present in judge output"
#
# # Reasoning present
# assert_contains "$TRANSCRIPT_TEXT" "Reasoning" \
#     "Reasoning present in judge output"
#
# # Baseline comparison: judge phase is a NEW behavior not in baseline
# if [ -f "$BASELINE_TRANSCRIPT" ]; then
#     BASELINE_TEXT=$(cat "$BASELINE_TRANSCRIPT")
#     assert_not_contains "$BASELINE_TEXT" "PICK\|SYNTHESIZE\|NONE_ADEQUATE" \
#         "Baseline lacks formal verdict (confirming skill adds value)"
# fi

echo "Phase 5: Judge phase assertions"
echo "  - Verdict present: one of PICK, SYNTHESIZE, NONE_ADEQUATE"
echo "  - Ranking present in judge output"
echo "  - Reasoning present in judge output"
echo "  - Baseline transcript lacks formal verdict (confirming skill adds value)"
echo ""

# ---------------------------------------------------------------------------
# Phase 6: Resolution — files exist, worktrees cleaned up
# ---------------------------------------------------------------------------
#
# echo "=== Resolution ==="
#
# # Implementation files exist in the test project
# if ls "$TMPDIR"/src/*.py 1>/dev/null 2>&1; then
#     echo "  [PASS] Python files exist in src/"
# else
#     echo "  [FAIL] No .py files in src/"
# fi
#
# if ls "$TMPDIR"/tests/*.py 1>/dev/null 2>&1; then
#     echo "  [PASS] Test files exist in tests/"
# else
#     echo "  [FAIL] No .py files in tests/"
# fi
#
# # Worktrees cleaned up
# WORKTREE_COUNT=$(cd "$TMPDIR" && git worktree list 2>/dev/null | wc -l)
# if [ "$WORKTREE_COUNT" -le 1 ]; then
#     echo "  [PASS] Worktrees cleaned up ($WORKTREE_COUNT remaining)"
# else
#     echo "  [FAIL] Worktrees NOT cleaned up ($WORKTREE_COUNT remaining, expected <= 1)"
# fi
#
# # No leftover slot-* branches (optional — skill may or may not clean these)
# SLOT_BRANCHES=$(cd "$TMPDIR" && git branch --list 'slot-*' 2>/dev/null | wc -l)
# echo "  [INFO] Slot branches remaining: $SLOT_BRANCHES"

echo "Phase 6: Resolution assertions"
echo "  - Python implementation files exist in src/"
echo "  - Python test files exist in tests/"
echo "  - Worktrees cleaned up (<= 1 remaining)"
echo "  - Report leftover slot-* branches"
echo ""

# ---------------------------------------------------------------------------
# Phase 7: LLM quality eval (optional — requires anthropic SDK)
# ---------------------------------------------------------------------------
#
# echo "=== LLM Quality Eval (optional) ==="
#
# LLM_JUDGE="$SCRIPT_DIR/llm-judge.py"
# if command -v python3 &>/dev/null && python3 -c "import anthropic" 2>/dev/null; then
#     # Extract first scorecard from transcript
#     SCORECARD=$(echo "$TRANSCRIPT_TEXT" | \
#         grep -oP '(?<=Scorecard).*?(?=---|\Z)' | head -1 || echo "")
#     if [ -n "$SCORECARD" ]; then
#         SCORECARD_EVAL=$(python3 "$LLM_JUDGE" scorecard-quality "$SCORECARD")
#         echo "  Scorecard quality: $SCORECARD_EVAL"
#
#         # Check minimum quality bar (all dimensions >= 3)
#         for dim in thoroughness specificity fairness; do
#             SCORE=$(echo "$SCORECARD_EVAL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$dim',0))")
#             if [ "$SCORE" -ge 3 ]; then
#                 echo "  [PASS] $dim >= 3 ($SCORE)"
#             else
#                 echo "  [FAIL] $dim < 3 ($SCORE)"
#             fi
#         done
#     else
#         echo "  [SKIP] Could not extract scorecard from transcript"
#     fi
#
#     # Extract verdict from transcript
#     VERDICT_TEXT=$(echo "$TRANSCRIPT_TEXT" | \
#         grep -oP '(?<=Verdict|verdict).*?(?=---|## |\Z)' | head -1 || echo "")
#     if [ -n "$VERDICT_TEXT" ]; then
#         VERDICT_EVAL=$(python3 "$LLM_JUDGE" verdict-quality "$VERDICT_TEXT")
#         echo "  Verdict quality: $VERDICT_EVAL"
#
#         for dim in reasoning specificity decisiveness; do
#             SCORE=$(echo "$VERDICT_EVAL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$dim',0))")
#             if [ "$SCORE" -ge 3 ]; then
#                 echo "  [PASS] $dim >= 3 ($SCORE)"
#             else
#                 echo "  [FAIL] $dim < 3 ($SCORE)"
#             fi
#         done
#     else
#         echo "  [SKIP] Could not extract verdict from transcript"
#     fi
# else
#     echo "  [SKIP] anthropic SDK not available — skipping LLM quality eval"
# fi

echo "Phase 7: LLM quality eval (optional)"
echo "  - Extract scorecard from transcript, run llm-judge.py scorecard-quality"
echo "  - Assert thoroughness, specificity, fairness >= 3/5"
echo "  - Extract verdict from transcript, run llm-judge.py verdict-quality"
echo "  - Assert reasoning, specificity, decisiveness >= 3/5"
echo "  - Gracefully skip if anthropic SDK not installed"
echo ""

# ---------------------------------------------------------------------------
# Phase 8: Final report present
# ---------------------------------------------------------------------------
#
# echo "=== Final Report ==="
#
# # The skill should produce a final status report
# assert_contains "$TRANSCRIPT_TEXT" "Status:" \
#     "Final status report present"
#
# # Check that the transcript is substantially different from baseline
# if [ -f "$BASELINE_TRANSCRIPT" ]; then
#     BASELINE_AGENTS=$(count_agent_calls "$BASELINE_TRANSCRIPT")
#     SKILL_AGENTS=$(count_agent_calls "$TRANSCRIPT")
#     echo "  [INFO] Baseline Agent calls: $BASELINE_AGENTS"
#     echo "  [INFO] Skill Agent calls: $SKILL_AGENTS"
#
#     # Skill should dispatch MORE agents (reviewers, judge, possibly synthesizer)
#     if [ "$SKILL_AGENTS" -gt "$BASELINE_AGENTS" ]; then
#         echo "  [PASS] Skill dispatches more agents than baseline ($SKILL_AGENTS > $BASELINE_AGENTS)"
#     else
#         echo "  [WARN] Skill did not dispatch more agents than baseline"
#     fi
# fi

echo "Phase 8: Final report assertions"
echo "  - Final 'Status:' report present in transcript"
echo "  - Compare Agent call count: skill > baseline"
echo "  - Skill dispatches more agents (reviewers + judge + synthesizer)"
echo ""

# ---------------------------------------------------------------------------
# Phase 9: Cleanup
# ---------------------------------------------------------------------------
#
# # trap handles cleanup: rm -rf "$TMPDIR"
# echo "=== Cleanup ==="
# echo "  Temp directory cleaned up via trap"

echo "Phase 9: Cleanup"
echo "  - Temp directory removed via EXIT trap"
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== Test Structure Summary ==="
echo "  9 phases, ~25 assertions covering the full slot-machine pipeline"
echo "  Verifies baseline gaps are filled: independent reviewers, structured"
echo "  scorecards, formal judge verdicts, synthesizer dispatch, worktree cleanup"
echo ""
echo "[SKIP] Requires headless claude -p (~20-30 min)"
exit 0
