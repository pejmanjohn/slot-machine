#!/usr/bin/env bash
# Tier 1: Contract validation between agent roles
# Verifies that format contracts between prompt templates and SKILL.md are consistent.
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

FAILED=0

echo "=== Contract 1: Implementer Status -> SKILL.md ==="
IMPL_CONTENT=$(cat "$SKILL_DIR/slot-implementer-prompt.md")
SKILL_CONTENT=$(cat "$SKILL_DIR/SKILL.md")

for status in DONE DONE_WITH_CONCERNS BLOCKED NEEDS_CONTEXT; do
    assert_contains "$IMPL_CONTENT" "$status" "Status '$status' in implementer prompt" || FAILED=$((FAILED + 1))
    assert_contains "$SKILL_CONTENT" "$status" "Status '$status' in SKILL.md" || FAILED=$((FAILED + 1))
done

echo ""
echo "=== Contract 2: Reviewer Output -> Judge Input ==="
REVIEWER_CONTENT=$(cat "$SKILL_DIR/slot-reviewer-prompt.md")

# Reviewer output sections the judge expects to parse
for header in "Spec Compliance" "Issues" "Test Assessment" "Strengths" "Verdict"; do
    assert_contains "$REVIEWER_CONTENT" "$header" "Section '$header' in reviewer prompt" || FAILED=$((FAILED + 1))
done

# Issue severity levels
for severity in Critical Important Minor; do
    assert_contains "$REVIEWER_CONTENT" "$severity" "Severity '$severity' in reviewer prompt" || FAILED=$((FAILED + 1))
done

# Reviewer verdict format matches what judge looks for
assert_contains "$REVIEWER_CONTENT" "Contender" "Reviewer uses 'Contender' verdict format" || FAILED=$((FAILED + 1))

# Judge expects PASS/FAIL on spec compliance
assert_contains "$REVIEWER_CONTENT" "PASS" "Reviewer uses PASS for spec compliance" || FAILED=$((FAILED + 1))
assert_contains "$REVIEWER_CONTENT" "FAIL" "Reviewer uses FAIL for spec compliance" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 3: Judge Verdict -> SKILL.md Phase 4 ==="
JUDGE_CONTENT=$(cat "$SKILL_DIR/slot-judge-prompt.md")

for verdict in PICK SYNTHESIZE NONE_ADEQUATE; do
    assert_contains "$JUDGE_CONTENT" "$verdict" "Verdict '$verdict' in judge prompt" || FAILED=$((FAILED + 1))
    assert_contains "$SKILL_CONTENT" "$verdict" "Verdict '$verdict' in SKILL.md" || FAILED=$((FAILED + 1))
done

echo ""
echo "=== Contract 4: Judge Synthesis Plan -> Synthesizer Input ==="
for keyword in base Port Source Target Coherence; do
    assert_contains "$JUDGE_CONTENT" "$keyword" "Keyword '$keyword' in judge prompt" || FAILED=$((FAILED + 1))
done

# Cross-reviewer convergence guidance
assert_contains "$JUDGE_CONTENT" "convergent\|convergence\|multiple reviewers" \
    "Judge prompt includes cross-reviewer convergence guidance" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 5: Template Variables -> SKILL.md Documentation ==="
for template in slot-implementer-prompt.md slot-reviewer-prompt.md slot-judge-prompt.md slot-synthesizer-prompt.md; do
    TEMPLATE_CONTENT=$(cat "$SKILL_DIR/$template")
    # Extract all {{VARIABLE}} patterns, deduplicate
    VARS=$(echo "$TEMPLATE_CONTENT" | grep -oE '\{\{[A-Z_]+\}\}' | sort -u)
    for var in $VARS; do
        assert_contains "$SKILL_CONTENT" "$var" "Variable $var from $template documented in SKILL.md" || FAILED=$((FAILED + 1))
    done
done

echo ""
echo "=== Contract 6: Model Values ==="
# Extract model values referenced in SKILL.md configuration/model section
# Valid values are: sonnet, opus, haiku
# Check that model references in the configuration table and model selection section
# only use these valid values
VALID_MODELS="sonnet opus haiku"
# Extract lines from SKILL.md that reference model settings (implementer_model, reviewer_model, etc.)
MODEL_LINES=$(echo "$SKILL_CONTENT" | grep -E '(implementer_model|reviewer_model|judge_model|synthesizer_model|Default Model)' || true)

# Check that no invalid model names appear in model config lines
# Extract all quoted model names from model-related lines
FOUND_MODELS=$(echo "$MODEL_LINES" | grep -oE '"[a-z]+"' | tr -d '"' | sort -u)
if [ -z "$FOUND_MODELS" ]; then
    echo "  [FAIL] No model values found in SKILL.md model config"
    FAILED=$((FAILED + 1))
else
    for found in $FOUND_MODELS; do
        if ! echo "$VALID_MODELS" | grep -qw "$found"; then
            echo "  [FAIL] Invalid model value '$found' in SKILL.md"
            FAILED=$((FAILED + 1))
        else
            echo "  [PASS] Model value '$found' is valid"
        fi
    done
fi

echo ""
echo "=== Contract 7: Approach Hints Suggest Different Architectures ==="
# Extract the Approach Hints section from SKILL.md (between ## Approach Hints and next ## heading)
HINTS_SECTION=$(echo "$SKILL_CONTENT" | sed -n '/^## Approach Hints$/,/^## /{/^## Approach Hints$/p; /^## [^A]/!p;}')

# Test 7a: Hints must contain architectural/design-pattern keywords, not just priority words.
# We require at least 4 distinct architectural keywords across all hints.
ARCH_MATCH_COUNT=$(echo "$HINTS_SECTION" | grep -ioE 'dataclass|decorator|async|context.manager|protocol|ABCs?|inheritance|fluent|functional|data-oriented|immutab[a-z]*|composition|strategy.pattern|dependency.injection|named.tuple|with.statement|__enter__|__iter__|@rate_limit|asyncio|logging|metrics|observable|goroutine|channel|trait|enum|Promise|AbortController|middleware|builder|Iterator|Symbol|tokio|io\.Reader|io\.Writer|context\.Context|impl.Into|Drop|newtype|macro|type.guard|discriminated.union' | tr '[:upper:]' '[:lower:]' | sort -u | wc -l | tr -d ' ')

if [ "$ARCH_MATCH_COUNT" -ge 4 ]; then
    echo "  [PASS] Hints contain $ARCH_MATCH_COUNT distinct architectural keywords (need >= 4)"
else
    echo "  [FAIL] Hints contain only $ARCH_MATCH_COUNT distinct architectural keywords (need >= 4)"
    FAILED=$((FAILED + 1))
fi

# Test 7b: The first 5 hints should NOT all use "Prioritize" framing — that indicates
# priority-based hints rather than architectural diversity.
# Match numbered hint lines (e.g., '1. "Prioritize...' or '| 1 | "Prioritize...')
FIRST_5_HINTS=$(echo "$HINTS_SECTION" | grep -E '^\s*[1-5]\.' | head -5)
if [ -z "$FIRST_5_HINTS" ]; then
    # Try table format: | 1 | "..." |
    FIRST_5_HINTS=$(echo "$HINTS_SECTION" | grep -E '^\|\s*[1-5]\s*\|' | head -5)
fi
PRIORITIZE_COUNT=$(echo "$FIRST_5_HINTS" | grep -ic 'Prioritize' || true)
PRIORITIZE_COUNT=${PRIORITIZE_COUNT:-0}

if [ "$PRIORITIZE_COUNT" -le 2 ]; then
    echo "  [PASS] At most 2 of first 5 hints use 'Prioritize' framing ($PRIORITIZE_COUNT found)"
else
    echo "  [FAIL] $PRIORITIZE_COUNT of first 5 hints use 'Prioritize' framing (max 2 allowed)"
    FAILED=$((FAILED + 1))
fi

# Test 7c: All 5 default hints must exist.
# Count numbered hint lines in the default section.
DEFAULT_HINT_COUNT=0
for i in 1 2 3 4 5; do
    HINT_LINE=$(echo "$HINTS_SECTION" | grep -E "^[[:space:]]*$i\." | head -1)
    if [ -z "$HINT_LINE" ]; then
        # Try table format
        HINT_LINE=$(echo "$HINTS_SECTION" | grep -E "^\|[[:space:]]*$i[[:space:]]*\|" | head -1)
    fi
    if [ -n "$HINT_LINE" ]; then
        DEFAULT_HINT_COUNT=$((DEFAULT_HINT_COUNT + 1))
    fi
done

if [ "$DEFAULT_HINT_COUNT" -ge 5 ]; then
    echo "  [PASS] Found $DEFAULT_HINT_COUNT default hints (need >= 5)"
else
    echo "  [FAIL] Found only $DEFAULT_HINT_COUNT default hints (need >= 5)"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=== Contract Tests Complete ==="
echo "Failures: $FAILED"
exit $FAILED
