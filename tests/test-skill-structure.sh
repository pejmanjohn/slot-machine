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
    profiles/coding/profile.md
    profiles/writing/profile.md
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
    # Check profile.md exists
    if [ -f "$profile_dir/profile.md" ]; then
        echo "  [PASS] Profile '$PROFILE_NAME' has profile.md"
    else
        echo "  [FAIL] Profile '$PROFILE_NAME' missing profile.md"
        FAILED=$((FAILED + 1))
    fi
    # Check all 4 prompt files exist
    for prompt in implementer.md reviewer.md judge.md synthesizer.md; do
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
    if [ -f "$profile_dir/profile.md" ]; then
        PROFILE_CONTENT=$(cat "$profile_dir/profile.md")
        assert_contains "$PROFILE_CONTENT" "name:" "Profile '$PROFILE_NAME' has name in frontmatter" || FAILED=$((FAILED + 1))
        assert_contains "$PROFILE_CONTENT" "description:" "Profile '$PROFILE_NAME' has description in frontmatter" || FAILED=$((FAILED + 1))
        assert_contains "$PROFILE_CONTENT" "isolation:" "Profile '$PROFILE_NAME' has isolation in frontmatter" || FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=== Skill Structure Tests Complete ==="
echo "Failures: $FAILED"
exit $FAILED
