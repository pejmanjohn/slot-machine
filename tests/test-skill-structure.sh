#!/usr/bin/env bash
# Tier 1: Validate SKILL.md follows skill conventions
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

FAILED=0
SKILL_CONTENT=$(cat "$SKILL_DIR/SKILL.md")

echo "=== Skill Structure: Frontmatter ==="
assert_contains "$SKILL_CONTENT" "name: slot-machine" "Frontmatter has name: slot-machine" || FAILED=$((FAILED + 1))

echo ""
echo "=== Skill Structure: Description ==="
# Description field in frontmatter should start with "Use when"
DESCRIPTION_LINE=$(echo "$SKILL_CONTENT" | grep "^description:" | head -1)
assert_contains "$DESCRIPTION_LINE" "Use when" "Description starts with 'Use when'" || FAILED=$((FAILED + 1))

echo ""
echo "=== Skill Structure: No @-syntax cross-references ==="
assert_not_contains "$SKILL_CONTENT" "@skills/" "No @skills/ cross-references" || FAILED=$((FAILED + 1))

echo ""
echo "=== Skill Structure: Required Sections ==="
for section in "When to Use" "Configuration" "The Process" "Common Mistakes" "Integration"; do
    assert_contains "$SKILL_CONTENT" "$section" "Required section '$section' exists" || FAILED=$((FAILED + 1))
done

echo ""
echo "=== Skill Structure: All Skill Files Exist ==="
SKILL_FILES=(
    SKILL.md
    references/orchestrator-trace.md
    references/harness-execution.md
    references/result-artifacts.md
    profiles/coding/0-profile.md
    profiles/writing/0-profile.md
    skills/slot-machine/references/orchestrator-trace.md
    skills/slot-machine/references/harness-execution.md
    skills/slot-machine/references/result-artifacts.md
)
for file in "${SKILL_FILES[@]}"; do
    if [ -f "$SKILL_DIR/$file" ]; then
        echo "  [PASS] File '$file' exists"
    else
        echo "  [FAIL] File '$file' missing"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=== Skill Structure: Profile Required Files ==="
for profile_dir in "$SKILL_DIR"/profiles/*/; do
    PROFILE_NAME=$(basename "$profile_dir")
    # Check 0-profile.md exists
    if [ -f "$profile_dir/0-profile.md" ]; then
        echo "  [PASS] Profile '$PROFILE_NAME' has 0-profile.md"
    else
        echo "  [FAIL] Profile '$PROFILE_NAME' missing 0-profile.md"
        FAILED=$((FAILED + 1))
    fi
    # Check all 4 prompt files exist
    for prompt in 1-implementer.md 2-reviewer.md 3-judge.md 4-synthesizer.md; do
        if [ -f "$profile_dir/$prompt" ]; then
            echo "  [PASS] Profile '$PROFILE_NAME' has $prompt"
        else
            echo "  [FAIL] Profile '$PROFILE_NAME' missing $prompt"
            FAILED=$((FAILED + 1))
        fi
    done
done

echo ""
echo "=== Skill Structure: Profile Frontmatter ==="
for profile_dir in "$SKILL_DIR"/profiles/*/; do
    PROFILE_NAME=$(basename "$profile_dir")
    if [ -f "$profile_dir/0-profile.md" ]; then
        PROFILE_CONTENT=$(cat "$profile_dir/0-profile.md")
        assert_contains "$PROFILE_CONTENT" "name:" "Profile '$PROFILE_NAME' has name in frontmatter" || FAILED=$((FAILED + 1))
        assert_contains "$PROFILE_CONTENT" "description:" "Profile '$PROFILE_NAME' has description in frontmatter" || FAILED=$((FAILED + 1))
        assert_contains "$PROFILE_CONTENT" "isolation:" "Profile '$PROFILE_NAME' has isolation in frontmatter" || FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=== Skill Structure: Plugin Packaging ==="
for file in \
    .claude-plugin/plugin.json \
    .claude-plugin/marketplace.json \
    .codex-plugin/plugin.json \
    skills/slot-machine/SKILL.md; do
    if [ -e "$SKILL_DIR/$file" ]; then
        echo "  [PASS] Packaging file '$file' exists"
    else
        echo "  [FAIL] Packaging file '$file' missing"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=== Skill Structure: Codex Skill Packaging ==="
CODEX_SKILL_DIR="$SKILL_DIR/skills/slot-machine"
CODEX_SKILL_PATH="$CODEX_SKILL_DIR/SKILL.md"
if [ -L "$CODEX_SKILL_PATH" ]; then
    echo "  [FAIL] Codex skill SKILL.md must be a real file, not a symlink"
    FAILED=$((FAILED + 1))
elif cmp -s "$SKILL_DIR/SKILL.md" "$CODEX_SKILL_PATH"; then
    echo "  [PASS] Codex skill SKILL.md matches the repo-root SKILL.md"
else
    echo "  [FAIL] Codex skill SKILL.md must stay in sync with the repo-root SKILL.md"
    FAILED=$((FAILED + 1))
fi

for relative_file in \
    "skills/slot-machine/profiles/coding/0-profile.md" \
    "skills/slot-machine/profiles/writing/0-profile.md" \
    "skills/slot-machine/tests/fixtures/sample-metrics.json"; do
    if [ -e "$SKILL_DIR/$relative_file" ]; then
        echo "  [PASS] Codex skill asset '$relative_file' is reachable"
    else
        echo "  [FAIL] Codex skill asset '$relative_file' missing"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=== Skill Structure Tests Complete ==="
echo "Failures: $FAILED"
exit $FAILED
