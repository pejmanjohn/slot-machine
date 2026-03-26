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
    slot-implementer-prompt.md
    slot-reviewer-prompt.md
    slot-judge-prompt.md
    slot-synthesizer-prompt.md
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
echo "=== Skill Structure Tests Complete ==="
echo "Failures: $FAILED"
exit $FAILED
