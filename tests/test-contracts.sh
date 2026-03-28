#!/usr/bin/env bash
# Tier 1: Contract validation between agent roles
# Verifies that format contracts between profile prompts and SKILL.md are consistent.
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

FAILED=0

echo "=== Contract 1: Implementer Status -> SKILL.md ==="
SKILL_CONTENT=$(cat "$SKILL_DIR/SKILL.md")

for profile_dir in "$SKILL_DIR"/profiles/*/; do
    PROFILE_NAME=$(basename "$profile_dir")
    IMPL_CONTENT=$(cat "$profile_dir/implementer.md" 2>/dev/null || echo "")

    for status in DONE DONE_WITH_CONCERNS BLOCKED NEEDS_CONTEXT; do
        assert_contains "$IMPL_CONTENT" "$status" \
            "Status '$status' in $PROFILE_NAME implementer prompt" || FAILED=$((FAILED + 1))
    done
done

# Also check SKILL.md itself
for status in DONE DONE_WITH_CONCERNS BLOCKED NEEDS_CONTEXT; do
    assert_contains "$SKILL_CONTENT" "$status" "Status '$status' in SKILL.md" || FAILED=$((FAILED + 1))
done

echo ""
echo "=== Contract 2: Reviewer Output -> Judge Input ==="
for profile_dir in "$SKILL_DIR"/profiles/*/; do
    PROFILE_NAME=$(basename "$profile_dir")
    REVIEWER_CONTENT=$(cat "$profile_dir/reviewer.md" 2>/dev/null || echo "")

    # Reviewer output sections the judge expects to parse
    for header in "Spec Compliance" "Issues" "Strengths" "Verdict"; do
        assert_contains "$REVIEWER_CONTENT" "$header" \
            "Section '$header' in $PROFILE_NAME reviewer prompt" || FAILED=$((FAILED + 1))
    done

    # Issue severity levels
    for severity in Critical Important Minor; do
        assert_contains "$REVIEWER_CONTENT" "$severity" \
            "Severity '$severity' in $PROFILE_NAME reviewer prompt" || FAILED=$((FAILED + 1))
    done

    # Reviewer verdict format matches what judge looks for
    assert_contains "$REVIEWER_CONTENT" "Contender" \
        "$PROFILE_NAME reviewer uses 'Contender' verdict format" || FAILED=$((FAILED + 1))

    # Judge expects PASS/FAIL on spec compliance
    assert_contains "$REVIEWER_CONTENT" "PASS" \
        "$PROFILE_NAME reviewer uses PASS for spec compliance" || FAILED=$((FAILED + 1))
    assert_contains "$REVIEWER_CONTENT" "FAIL" \
        "$PROFILE_NAME reviewer uses FAIL for spec compliance" || FAILED=$((FAILED + 1))
done

echo ""
echo "=== Contract 3: Judge Verdict -> SKILL.md Phase 4 ==="
for profile_dir in "$SKILL_DIR"/profiles/*/; do
    PROFILE_NAME=$(basename "$profile_dir")
    JUDGE_CONTENT=$(cat "$profile_dir/judge.md" 2>/dev/null || echo "")

    for verdict in PICK SYNTHESIZE NONE_ADEQUATE; do
        assert_contains "$JUDGE_CONTENT" "$verdict" \
            "Verdict '$verdict' in $PROFILE_NAME judge prompt" || FAILED=$((FAILED + 1))
    done
done

for verdict in PICK SYNTHESIZE NONE_ADEQUATE; do
    assert_contains "$SKILL_CONTENT" "$verdict" "Verdict '$verdict' in SKILL.md" || FAILED=$((FAILED + 1))
done

echo ""
echo "=== Contract 4: Judge Synthesis Plan -> Synthesizer Input ==="
for profile_dir in "$SKILL_DIR"/profiles/*/; do
    PROFILE_NAME=$(basename "$profile_dir")
    JUDGE_CONTENT=$(cat "$profile_dir/judge.md" 2>/dev/null || echo "")

    # Universal synthesis plan keywords present in all profiles
    for keyword in base Coherence; do
        assert_contains "$JUDGE_CONTENT" "$keyword" \
            "Keyword '$keyword' in $PROFILE_NAME judge prompt" || FAILED=$((FAILED + 1))
    done

    # Cross-reviewer convergence guidance
    assert_contains "$JUDGE_CONTENT" "convergent\|convergence\|multiple reviewers" \
        "$PROFILE_NAME judge prompt includes cross-reviewer convergence guidance" || FAILED=$((FAILED + 1))
done

# Coding-specific: synthesis plan has Port/Source/Target terminology
CODING_JUDGE_CONTENT=$(cat "$SKILL_DIR/profiles/coding/judge.md" 2>/dev/null || echo "")
for keyword in Port Source Target; do
    assert_contains "$CODING_JUDGE_CONTENT" "$keyword" \
        "Keyword '$keyword' in coding/judge.md judge synthesis plan" || FAILED=$((FAILED + 1))
done

echo ""
echo "=== Contract 5: Template Variables -> SKILL.md Documentation ==="
for profile_dir in "$SKILL_DIR"/profiles/*/; do
    PROFILE_NAME=$(basename "$profile_dir")
    for prompt_file in "$profile_dir"/implementer.md "$profile_dir"/reviewer.md "$profile_dir"/judge.md "$profile_dir"/synthesizer.md; do
        [ -f "$prompt_file" ] || continue
        PROMPT_NAME=$(basename "$prompt_file")
        TEMPLATE_CONTENT=$(cat "$prompt_file")
        VARS=$(echo "$TEMPLATE_CONTENT" | grep -oE '\{\{[A-Z_]+\}\}' | sort -u)
        for var in $VARS; do
            assert_contains "$SKILL_CONTENT" "$var" \
                "Variable $var from $PROFILE_NAME/$PROMPT_NAME documented in SKILL.md" || FAILED=$((FAILED + 1))
        done
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
echo "=== Contract 7: Approach Hints ==="
for profile_dir in "$SKILL_DIR"/profiles/*/; do
    PROFILE_NAME=$(basename "$profile_dir")
    HINTS_CONTENT=$(cat "$profile_dir/profile.md" 2>/dev/null || echo "")

    # Test: at least 5 hints
    HINT_COUNT=$(echo "$HINTS_CONTENT" | grep -cE '^\s*[0-9]+\.' || echo "0")
    if [ "$HINT_COUNT" -ge 5 ]; then
        echo "  [PASS] $PROFILE_NAME has $HINT_COUNT hints (need >= 5)"
    else
        echo "  [FAIL] $PROFILE_NAME has only $HINT_COUNT hints (need >= 5)"
        FAILED=$((FAILED + 1))
    fi
done

# Coding-specific: architectural keywords check
CODING_HINTS=$(cat "$SKILL_DIR/profiles/coding/profile.md" 2>/dev/null || echo "")
ARCH_MATCH_COUNT=$(echo "$CODING_HINTS" | grep -ioE 'dataclass|decorator|async|context.manager|protocol|ABCs?|inheritance|fluent|functional|data-oriented|immutab[a-z]*|composition|strategy.pattern|dependency.injection|named.tuple|with.statement|__enter__|__iter__|@rate_limit|asyncio|logging|metrics|observable' | tr '[:upper:]' '[:lower:]' | sort -u | wc -l | tr -d ' ')

if [ "$ARCH_MATCH_COUNT" -ge 4 ]; then
    echo "  [PASS] coding/profile.md hints contain $ARCH_MATCH_COUNT distinct architectural keywords (need >= 4)"
else
    echo "  [FAIL] coding/profile.md hints contain only $ARCH_MATCH_COUNT distinct architectural keywords (need >= 4)"
    FAILED=$((FAILED + 1))
fi

# Coding-specific: The first 5 hints should NOT all use "Prioritize" framing
FIRST_5_HINTS=$(echo "$CODING_HINTS" | grep -E '^\s*[1-5]\.' | head -5)
if [ -z "$FIRST_5_HINTS" ]; then
    FIRST_5_HINTS=$(echo "$CODING_HINTS" | grep -E '^\|\s*[1-5]\s*\|' | head -5)
fi
PRIORITIZE_COUNT=$(echo "$FIRST_5_HINTS" | grep -ic 'Prioritize' || true)
PRIORITIZE_COUNT=${PRIORITIZE_COUNT:-0}

if [ "$PRIORITIZE_COUNT" -le 2 ]; then
    echo "  [PASS] At most 2 of first 5 coding hints use 'Prioritize' framing ($PRIORITIZE_COUNT found)"
else
    echo "  [FAIL] $PRIORITIZE_COUNT of first 5 coding hints use 'Prioritize' framing (max 2 allowed)"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=== Contract 8: Profile Inheritance ==="
for profile_dir in "$SKILL_DIR"/profiles/*/; do
    PROFILE_NAME=$(basename "$profile_dir")
    PROFILE_FILE="$profile_dir/profile.md"
    if [ ! -f "$PROFILE_FILE" ]; then
        echo "  [SKIP] $PROFILE_NAME — profile.md not found"
        continue
    fi
    EXTENDS=$(grep "^extends:" "$PROFILE_FILE" | head -1 | awk '{print $2}')
    if [ -n "$EXTENDS" ] && [ "$EXTENDS" != "null" ]; then
        BASE_DIR="$SKILL_DIR/profiles/$EXTENDS"
        if [ -d "$BASE_DIR" ]; then
            echo "  [PASS] $PROFILE_NAME extends '$EXTENDS' — base folder exists"
        else
            echo "  [FAIL] $PROFILE_NAME extends '$EXTENDS' — base folder NOT FOUND"
            FAILED=$((FAILED + 1))
        fi
        # Check no multi-level inheritance
        BASE_PROFILE_FILE="$BASE_DIR/profile.md"
        if [ -f "$BASE_PROFILE_FILE" ]; then
            BASE_EXTENDS=$(grep "^extends:" "$BASE_PROFILE_FILE" | head -1 | awk '{print $2}')
            if [ -n "$BASE_EXTENDS" ] && [ "$BASE_EXTENDS" != "null" ]; then
                echo "  [FAIL] $PROFILE_NAME -> $EXTENDS -> $BASE_EXTENDS — multi-level inheritance not allowed"
                FAILED=$((FAILED + 1))
            fi
        fi
    else
        echo "  [PASS] $PROFILE_NAME has no extends (base profile)"
    fi
done

echo ""
echo "=== Contract Tests Complete ==="
echo "Failures: $FAILED"
exit $FAILED
