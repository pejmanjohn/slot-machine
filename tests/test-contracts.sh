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
    IMPL_CONTENT=$(cat "$profile_dir/1-implementer.md" 2>/dev/null || echo "")

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
    REVIEWER_CONTENT=$(cat "$profile_dir/2-reviewer.md" 2>/dev/null || echo "")

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
    JUDGE_CONTENT=$(cat "$profile_dir/3-judge.md" 2>/dev/null || echo "")

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
    JUDGE_CONTENT=$(cat "$profile_dir/3-judge.md" 2>/dev/null || echo "")

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
CODING_JUDGE_CONTENT=$(cat "$SKILL_DIR/profiles/coding/3-judge.md" 2>/dev/null || echo "")
for keyword in Port Source Target; do
    assert_contains "$CODING_JUDGE_CONTENT" "$keyword" \
        "Keyword '$keyword' in coding/3-judge.md judge synthesis plan" || FAILED=$((FAILED + 1))
done

echo ""
echo "=== Contract 5: Template Variables -> SKILL.md Documentation ==="
for profile_dir in "$SKILL_DIR"/profiles/*/; do
    PROFILE_NAME=$(basename "$profile_dir")
    for prompt_file in "$profile_dir"/1-implementer.md "$profile_dir"/2-reviewer.md "$profile_dir"/3-judge.md "$profile_dir"/4-synthesizer.md; do
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
echo "=== Contract 6: Model Configuration ==="
# Model config must reference the 4 model settings and use "inherit" as default
MODEL_LINES=$(echo "$SKILL_CONTENT" | grep -E '(implementer_model|reviewer_model|judge_model|synthesizer_model)' || true)

if [ -z "$MODEL_LINES" ]; then
    echo "  [FAIL] No model settings found in SKILL.md"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] Model settings referenced in SKILL.md"
fi

# Check that "inherit" appears as a model concept
assert_contains "$SKILL_CONTENT" "inherit" \
    "SKILL.md mentions model inheritance from session" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 7: Approach Hints ==="
for profile_dir in "$SKILL_DIR"/profiles/*/; do
    PROFILE_NAME=$(basename "$profile_dir")
    HINTS_CONTENT=$(cat "$profile_dir/0-profile.md" 2>/dev/null || echo "")

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
CODING_HINTS=$(cat "$SKILL_DIR/profiles/coding/0-profile.md" 2>/dev/null || echo "")
ARCH_MATCH_COUNT=$(echo "$CODING_HINTS" | grep -ioE 'dataclass|decorator|async|context.manager|protocol|ABCs?|inheritance|fluent|functional|data-oriented|immutab[a-z]*|composition|strategy.pattern|dependency.injection|named.tuple|with.statement|__enter__|__iter__|@rate_limit|asyncio|logging|metrics|observable|goroutine|channel|trait|enum|Promise|AbortController|middleware|builder|Iterator|Symbol|tokio|io\.Reader|io\.Writer|context\.Context|impl.Into|Drop|newtype|macro|type.guard|discriminated.union' | tr '[:upper:]' '[:lower:]' | sort -u | wc -l | tr -d ' ')

if [ "$ARCH_MATCH_COUNT" -ge 4 ]; then
    echo "  [PASS] coding/0-profile.md hints contain $ARCH_MATCH_COUNT distinct architectural keywords (need >= 4)"
else
    echo "  [FAIL] coding/0-profile.md hints contain only $ARCH_MATCH_COUNT distinct architectural keywords (need >= 4)"
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
    PROFILE_FILE="$profile_dir/0-profile.md"
    if [ ! -f "$PROFILE_FILE" ]; then
        echo "  [SKIP] $PROFILE_NAME — 0-profile.md not found"
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
        BASE_PROFILE_FILE="$BASE_DIR/0-profile.md"
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
echo "=== Contract 9: Run Storage ==="
# SKILL.md must reference .slot-machine/runs/ for artifact storage (not mktemp or temp dirs)
assert_contains "$SKILL_CONTENT" ".slot-machine/runs/" \
    "SKILL.md references .slot-machine/runs/ for artifact storage" || FAILED=$((FAILED + 1))

# SKILL.md must NOT reference mktemp for slot output (temp dirs replaced by run storage)
MKTEMP_LINES=$(echo "$SKILL_CONTENT" | grep -n "mktemp" || true)
if [ -n "$MKTEMP_LINES" ]; then
    echo "  [FAIL] SKILL.md still references mktemp (should use .slot-machine/runs/)"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] SKILL.md does not reference mktemp"
fi

# SKILL.md must reference saving review scorecards and verdict
assert_contains "$SKILL_CONTENT" "review-.*\.md\|scorecard.*save\|save.*review\|review.*run_dir\|review.*run dir" \
    "SKILL.md describes saving reviewer output to run dir" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "verdict.*\.md\|verdict.*save\|save.*verdict\|verdict.*run_dir\|verdict.*run dir" \
    "SKILL.md describes saving judge verdict to run dir" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 10: Model Inheritance ==="
# Model config defaults should say "inherit" not hardcode specific models
# The Configuration table should NOT have "sonnet" or "opus" as default values for model settings
CONFIG_TABLE=$(echo "$SKILL_CONTENT" | sed -n '/^## Configuration$/,/^## /p')
MODEL_DEFAULTS=$(echo "$CONFIG_TABLE" | grep -E 'implementer_model|reviewer_model|judge_model|synthesizer_model')

# Check that no model config line has "sonnet" or "opus" as the default
HARDCODED_DEFAULTS=$(echo "$MODEL_DEFAULTS" | grep -E '\| sonnet \|| \| opus \|' || true)
if [ -n "$HARDCODED_DEFAULTS" ]; then
    echo "  [FAIL] Configuration table has hardcoded model defaults (should inherit from session)"
    echo "  Found: $HARDCODED_DEFAULTS"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] No hardcoded model defaults in Configuration table"
fi

# The Agent dispatch tables in Phases should NOT specify model parameter unconditionally
# They should say "omit" or "inherit" or "only if configured"
PHASE2_DISPATCH=$(echo "$SKILL_CONTENT" | sed -n '/^### Phase 2/,/^### Phase 3/p')
if echo "$PHASE2_DISPATCH" | grep -q '`"sonnet"`'; then
    echo "  [FAIL] Phase 2 dispatch still hardcodes sonnet model"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] Phase 2 dispatch does not hardcode sonnet"
fi

# Judge can still mention opus as a recommendation but should not force it
JUDGE_DISPATCH=$(echo "$SKILL_CONTENT" | sed -n '/Step 2: Dispatch the judge/,/^###\|^#### /p')
if echo "$JUDGE_DISPATCH" | grep -q '"opus".*do NOT omit'; then
    echo "  [FAIL] Judge dispatch still forces opus with 'do NOT omit'"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] Judge dispatch does not force opus"
fi

echo ""
echo "=== Contract 11: Slot Definition Syntax ==="
# SKILL.md must have a Slot Definitions section
assert_contains "$SKILL_CONTENT" "## Slot Definitions" \
    "SKILL.md has Slot Definitions section" || FAILED=$((FAILED + 1))

# Must describe the + composition operator
assert_contains "$SKILL_CONTENT" '+ codex' \
    "SKILL.md describes skill + harness composition with codex" || FAILED=$((FAILED + 1))

# Must describe CLAUDE.md config key
assert_contains "$SKILL_CONTENT" "slot-machine-slots" \
    "SKILL.md documents slot-machine-slots config key" || FAILED=$((FAILED + 1))

# Must describe precedence
assert_contains "$SKILL_CONTENT" "inline.*CLAUDE.md.*profile\|precedence" \
    "SKILL.md documents slot definition precedence" || FAILED=$((FAILED + 1))

# Must describe poor slot candidate warning
assert_contains "$SKILL_CONTENT" "poor.*candidate\|multi-agent.*orchestrator\|warn.*block" \
    "SKILL.md warns about poor slot candidates" || FAILED=$((FAILED + 1))

# Skill-based slots must NOT get approach hints
assert_contains "$SKILL_CONTENT" "skill.*no.*hint\|hint.*only.*default\|default.*slots.*hint" \
    "SKILL.md clarifies hints only apply to default slots" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 12: Codex Dispatch ==="
# SKILL.md must describe native codex exec dispatch
assert_contains "$SKILL_CONTENT" "codex exec" \
    "SKILL.md describes codex exec dispatch" || FAILED=$((FAILED + 1))

# Must specify workspace-write mode
assert_contains "$SKILL_CONTENT" "workspace-write" \
    "SKILL.md specifies workspace-write sandbox mode" || FAILED=$((FAILED + 1))

# Must describe JSONL output parsing
assert_contains "$SKILL_CONTENT" "JSONL\|jsonl" \
    "SKILL.md describes JSONL output parsing" || FAILED=$((FAILED + 1))

# Must describe Codex failure handling
assert_contains "$SKILL_CONTENT" "non-zero exit\|timeout.*codex\|codex.*fail" \
    "SKILL.md describes codex failure handling" || FAILED=$((FAILED + 1))

# Must describe harness availability check with fallback
assert_contains "$SKILL_CONTENT" "which codex\|codex.*not found\|fall.*back.*Claude" \
    "SKILL.md describes codex availability check with fallback" || FAILED=$((FAILED + 1))

# Must describe mixed-harness parallel dispatch
assert_contains "$SKILL_CONTENT" "Claude Code slots.*parallel\|Codex slots.*background\|mixed.*harness\|dispatch.*group" \
    "SKILL.md describes mixed-harness parallel dispatch strategy" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 13: Skill Discovery ==="
assert_contains "$SKILL_CONTENT" "Skill Discovery\|skill discovery" \
    "SKILL.md has Skill Discovery section" || FAILED=$((FAILED + 1))

assert_contains "$SKILL_CONTENT" "\-\-discover" \
    "SKILL.md documents --discover flag" || FAILED=$((FAILED + 1))

assert_contains "$SKILL_CONTENT" "all my skills\|all implementation skills" \
    "SKILL.md documents natural language discovery triggers" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 14: Agent-Wrapped Codex Dispatch ==="
# Codex slots must dispatch via Agent tool, not raw Bash
assert_contains "$SKILL_CONTENT" "Agent tool.*codex\|wrapper.*agent.*codex\|subagent.*codex exec" \
    "SKILL.md describes Codex dispatch via Agent wrapper" || FAILED=$((FAILED + 1))

# Must NOT have Group 1 / Group 2 distinction
GROUPS_FOUND=$(echo "$SKILL_CONTENT" | grep -c "Group 1\|Group 2" || true)
if [ "$GROUPS_FOUND" -eq 0 ]; then
    echo "  [PASS] No Group 1/Group 2 dispatch distinction"
else
    echo "  [FAIL] Still has Group 1/Group 2 distinction ($GROUPS_FOUND references)"
    FAILED=$((FAILED + 1))
fi

# All slots should use Agent tool in dispatch table
assert_contains "$SKILL_CONTENT" "Agent tool.*Agent tool.*Agent tool\|all.*slots.*Agent tool\|every.*slot.*Agent" \
    "SKILL.md says all slots dispatch via Agent tool" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 15: Model Version Display ==="
# Must describe reading codex model from config
assert_contains "$SKILL_CONTENT" "config.toml\|codex.*model.*version\|model.*codex.*config" \
    "SKILL.md describes reading Codex model version from config" || FAILED=$((FAILED + 1))

# Progress table must have Model column
assert_contains "$SKILL_CONTENT" "| Model |\|| Model|" \
    "SKILL.md progress table has Model column" || FAILED=$((FAILED + 1))

# Must NOT have Via column (replaced by Model)
PHASE2_TABLE=$(echo "$SKILL_CONTENT" | sed -n '/Phase 2.*Implementation/,/Phase 3/p')
VIA_COUNT=$(echo "$PHASE2_TABLE" | grep -c "| Via |" || true)
if [ "$VIA_COUNT" -eq 0 ]; then
    echo "  [PASS] Phase 2 progress table has no Via column (replaced by Model)"
else
    echo "  [FAIL] Phase 2 progress table still has Via column ($VIA_COUNT found)"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=== Contract 16: Verdict Formatting ==="
# Must NOT use blockquote for verdict
VERDICT_SECTION=$(echo "$SKILL_CONTENT" | sed -n '/Report the verdict/,/Phase 4.*Resolution\|### Phase 4/p')
BLOCKQUOTE_COUNT=$(echo "$VERDICT_SECTION" | grep -c "^>" || true)
if [ "$BLOCKQUOTE_COUNT" -eq 0 ]; then
    echo "  [PASS] Verdict does not use blockquote formatting"
else
    echo "  [FAIL] Verdict still uses blockquote formatting ($BLOCKQUOTE_COUNT lines)"
    FAILED=$((FAILED + 1))
fi

# Must include slot identity with harness and model
assert_contains "$SKILL_CONTENT" "Harness.*Model\|harness.*model.*skill\|Claude Code.*opus\|Codex.*gpt" \
    "SKILL.md verdict includes slot identity with harness and model" || FAILED=$((FAILED + 1))

# Must have one-sentence why summary
assert_contains "$SKILL_CONTENT" "one-sentence.*why\|why.*summary\|human-readable.*explanation" \
    "SKILL.md verdict requires a why summary" || FAILED=$((FAILED + 1))

# Formatting rules must NOT mention blockquote for verdict
assert_contains "$SKILL_CONTENT" "horizontal.*rule\|---.*verdict\|bounded.*section" \
    "SKILL.md uses horizontal rules for verdict section" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 17: Streaming Review Pipeline ==="
# Reviews should start as slots complete, not wait for all
REVIEW_SECTION=$(echo "$SKILL_CONTENT" | sed -n '/Step 1: Dispatch reviewers/,/Step 2: Dispatch the judge/p')
assert_contains "$SKILL_CONTENT" "as.*slot.*completes\|as.*each.*returns\|stream.*review\|review.*as.*finish\|overlap.*review.*implement" \
    "SKILL.md describes starting reviews as slots complete" || FAILED=$((FAILED + 1))

# Must NOT say "dispatch all reviewers in a SINGLE message" (old batch approach)
BATCH_REVIEW=$(echo "$REVIEW_SECTION" | grep -c "Dispatch all reviewers in a SINGLE message" || true)
if [ "$BATCH_REVIEW" -eq 0 ]; then
    echo "  [PASS] Reviews are not batched into a single message"
else
    echo "  [FAIL] Still says dispatch all reviewers in a single message"
    FAILED=$((FAILED + 1))
fi

# Judge should dispatch immediately after last review, no reporting gap
assert_contains "$SKILL_CONTENT" "immediately.*judge\|judge.*without.*waiting\|dispatch.*judge.*as soon as\|review.*report.*after.*judge" \
    "SKILL.md dispatches judge immediately after reviews complete" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract Tests Complete ==="
echo "Failures: $FAILED"
exit $FAILED
