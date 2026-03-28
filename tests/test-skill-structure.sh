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
    profiles/coding.md
    profiles/writing.md
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
echo "=== Skill Structure: Profile Required Sections ==="
for profile in "$SKILL_DIR"/profiles/*.md; do
    PROFILE_NAME=$(basename "$profile")
    # Resolve inheritance: if profile extends a base, merge base + child
    EXTENDS=$(grep "^extends:" "$profile" | head -1 | awk '{print $2}')
    if [ -n "$EXTENDS" ] && [ "$EXTENDS" != "null" ]; then
        BASE_FILE="$SKILL_DIR/profiles/${EXTENDS}.md"
        if [ -f "$BASE_FILE" ]; then
            # Resolved content = base + child overlay (child sections override base)
            PROFILE_CONTENT="$(cat "$BASE_FILE")
$(cat "$profile")"
        else
            PROFILE_CONTENT=$(cat "$profile")
        fi
    else
        PROFILE_CONTENT=$(cat "$profile")
    fi
    for section in "Approach Hints" "Implementer Prompt" "Reviewer Prompt" "Judge Prompt" "Synthesizer Prompt"; do
        assert_contains "$PROFILE_CONTENT" "## $section" \
            "Profile '$PROFILE_NAME' has section '$section'" || FAILED=$((FAILED + 1))
    done
done

echo ""
echo "=== Skill Structure: Profile Frontmatter ==="
for profile in "$SKILL_DIR"/profiles/*.md; do
    PROFILE_NAME=$(basename "$profile")
    PROFILE_CONTENT=$(cat "$profile")
    assert_contains "$PROFILE_CONTENT" "name:" "Profile '$PROFILE_NAME' has name in frontmatter" || FAILED=$((FAILED + 1))
    assert_contains "$PROFILE_CONTENT" "description:" "Profile '$PROFILE_NAME' has description in frontmatter" || FAILED=$((FAILED + 1))
    assert_contains "$PROFILE_CONTENT" "isolation:" "Profile '$PROFILE_NAME' has isolation in frontmatter" || FAILED=$((FAILED + 1))
done

echo ""
echo "=== Skill Structure Tests Complete ==="
echo "Failures: $FAILED"
exit $FAILED
