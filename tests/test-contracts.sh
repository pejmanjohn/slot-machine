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
echo "=== Contract 2b: Reviewer Prompt Hardening ==="
CODING_REVIEWER_CONTENT=$(cat "$SKILL_DIR/profiles/coding/2-reviewer.md" 2>/dev/null || echo "")

assert_contains "$CODING_REVIEWER_CONTENT" "git diff\\|changed files\\|diff shape" \
    "coding reviewer starts from changed files or diff scope" || FAILED=$((FAILED + 1))

assert_contains "$CODING_REVIEWER_CONTENT" "concrete failure mode\\|do not report speculative\\|drop speculative\\|downgrade speculative" \
    "coding reviewer filters speculative findings" || FAILED=$((FAILED + 1))

assert_contains "$CODING_REVIEWER_CONTENT" "existing utilit\\|existing helper\\|repo pattern\\|project convention\\|compare against existing" \
    "coding reviewer compares against existing repo patterns" || FAILED=$((FAILED + 1))

assert_contains "$CODING_REVIEWER_CONTENT" "well tested\\|weakly tested\\|untested\\|changed behavior" \
    "coding reviewer evaluates test coverage for changed behavior" || FAILED=$((FAILED + 1))

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
echo "=== Contract 8b: Profile Resolution Guardrails ==="
assert_contains "$SKILL_CONTENT" "pwd -P" \
    "SKILL.md canonicalizes built-in skill paths before inherited-profile lookup" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "find -L" \
    "SKILL.md documents a symlink-safe fallback for built-in profile discovery" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" '"resolution_mode": "blocked"' \
    "SKILL.md documents blocked result.json mode for setup-time failures" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" '"blocked_stage": "profile_loading"' \
    "SKILL.md records profile-loading failures in result.json" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" '"blocked_reason": "' \
    "SKILL.md records a human-readable blocked reason in result.json" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 9: Run Storage ==="
# SKILL.md must reference .slot-machine/runs/ for artifact storage (not mktemp or temp dirs)
assert_contains "$SKILL_CONTENT" ".slot-machine/runs/" \
    "SKILL.md references .slot-machine/runs/ for artifact storage" || FAILED=$((FAILED + 1))

# Manual handoff adds a branch before judge dispatch and a handoff artifact/result discriminator
assert_contains "$SKILL_CONTENT" "manual_handoff" \
    "SKILL.md documents manual_handoff config" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" '`0-profile.md`' \
    "SKILL.md references the numbered profile config file" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" '`1-implementer.md`' \
    "SKILL.md references the numbered implementer prompt file" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" '`2-reviewer.md`' \
    "SKILL.md references the numbered reviewer prompt file" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" '`3-judge.md`' \
    "SKILL.md references the numbered judge prompt file" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" '`4-synthesizer.md`' \
    "SKILL.md references the numbered synthesizer prompt file" || FAILED=$((FAILED + 1))
assert_not_contains "$SKILL_CONTENT" '`profile.md`' \
    "SKILL.md no longer references the legacy profile.md name" || FAILED=$((FAILED + 1))
assert_not_contains "$SKILL_CONTENT" '`implementer.md`' \
    "SKILL.md no longer references the legacy implementer.md name" || FAILED=$((FAILED + 1))
assert_not_contains "$SKILL_CONTENT" '`reviewer.md`' \
    "SKILL.md no longer references the legacy reviewer.md name" || FAILED=$((FAILED + 1))
assert_not_contains "$SKILL_CONTENT" '`judge.md`' \
    "SKILL.md no longer references the legacy judge.md name" || FAILED=$((FAILED + 1))
assert_not_contains "$SKILL_CONTENT" '`synthesizer.md`' \
    "SKILL.md no longer references the legacy synthesizer.md name" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "handoff\\.md" \
    "SKILL.md documents handoff.md artifact" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "slot-manifest\\.json" \
    "SKILL.md documents slot-manifest.json artifact" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "resolution_mode" \
    "SKILL.md documents manual-mode result.json discriminator" || FAILED=$((FAILED + 1))
MANUAL_HANDOFF_BLOCK=$(echo "$SKILL_CONTENT" | sed -n '/#### Manual Handoff/,/#### Dispatch the judge immediately/p')
assert_contains "$MANUAL_HANDOFF_BLOCK" "terminal path\|skip the judge/verdict/merge finalization path" \
    "SKILL.md makes manual handoff the terminal path" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "Do NOT dispatch the judge" \
    "SKILL.md manual handoff skips judge dispatch" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "Do NOT dispatch the synthesizer" \
    "SKILL.md manual handoff skips synthesizer dispatch" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "Do NOT auto-merge or copy a winning result" \
    "SKILL.md manual handoff skips auto-merge/copy" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "preserve all successful slot worktrees" \
    "SKILL.md manual handoff preserves worktrees" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "preserve slot output files and reviews" \
    "SKILL.md manual handoff preserves file-isolation outputs and reviews" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "restore the user's original checkout" \
    "SKILL.md manual handoff restores the original checkout" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "# Manual Handoff" \
    "SKILL.md manual handoff defines the final user-facing heading" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "STOP\\. Do not read or follow any judged-run verdict/final-report instructions below this block" \
    "SKILL.md manual handoff explicitly terminates before judged-path instructions" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "slot summary table" \
    "SKILL.md documents the handoff slot summary table" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "Artifact paths" \
    "SKILL.md documents the handoff artifact paths" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "Next-step guidance" \
    "SKILL.md documents the handoff next-step guidance" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "git switch \"\\\$ORIGINAL_BRANCH\"" \
    "SKILL.md documents restoring the original branch in manual handoff" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "git checkout --detach \"\\\$ORIGINAL_HEAD\"" \
    "SKILL.md documents restoring the original detached HEAD in manual handoff" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" 'report `BLOCKED`' \
    "SKILL.md documents failing manual handoff if checkout restore fails" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "result\\.json" \
    "SKILL.md ties manual metadata to result.json" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "slot_details\|slot details" \
    "SKILL.md ties manual metadata to slot details" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_HANDOFF_BLOCK" "runs/latest" \
    "SKILL.md documents latest-path manual metadata" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" 'If `manual_handoff` is false' \
    "SKILL.md makes the judge path conditional on manual_handoff being false" || FAILED=$((FAILED + 1))
MANUAL_RESULT_EXAMPLE=$(echo "$SKILL_CONTENT" | sed -n '/Manual handoff writes the same run artifact path with unresolved result state:/,/^\*\*Part 4: Footer\*\*/p')
assert_contains "$MANUAL_RESULT_EXAMPLE" "\"resolution_mode\": \"manual\"" \
    "SKILL.md documents manual-mode result example resolution_mode" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_RESULT_EXAMPLE" "\"verdict\": null" \
    "SKILL.md documents unresolved manual verdict" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_RESULT_EXAMPLE" "\"winning_slot\": null" \
    "SKILL.md documents unresolved manual winning_slot" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_RESULT_EXAMPLE" "\"files_changed\": null" \
    "SKILL.md documents top-level null files_changed in manual result" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_RESULT_EXAMPLE" "\"tests_passing\": null" \
    "SKILL.md documents top-level null tests_passing in manual result" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_RESULT_EXAMPLE" "\"handoff_path\"" \
    "SKILL.md documents manual-mode handoff_path" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_RESULT_EXAMPLE" "runs/latest/handoff\\.md" \
    "SKILL.md documents latest-based manual handoff_path" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_RESULT_EXAMPLE" "\"slot_details\"" \
    "SKILL.md documents manual-mode slot details metadata" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_RESULT_EXAMPLE" "\"run_dir\": \"/abs/path/\\.slot-machine/runs/latest\"" \
    "SKILL.md documents latest-based manual run_dir" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_RESULT_EXAMPLE" "\"diff_path\"" \
    "SKILL.md documents per-slot diff_path metadata in manual result" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_RESULT_EXAMPLE" "\"worktree_path\"" \
    "SKILL.md documents per-slot worktree_path metadata in manual result" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_RESULT_EXAMPLE" "\"branch\"" \
    "SKILL.md documents per-slot branch metadata in manual result" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_RESULT_EXAMPLE" "\"head_sha\"" \
    "SKILL.md documents per-slot head_sha metadata in manual result" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_RESULT_EXAMPLE" "\"review_path\"" \
    "SKILL.md documents per-slot review_path metadata in manual result" || FAILED=$((FAILED + 1))
MANUAL_SLOT_DETAILS_OBJECT=$(echo "$MANUAL_RESULT_EXAMPLE" | sed -n '/^  "slot_details": \[/,/^  ],/p' | sed -n '/^    {/,/^    },/p')
assert_contains "$MANUAL_SLOT_DETAILS_OBJECT" "\"files_changed\"" \
    "SKILL.md documents nested per-slot files_changed metadata in slot_details" || FAILED=$((FAILED + 1))
assert_contains "$MANUAL_SLOT_DETAILS_OBJECT" "\"tests_passing\"" \
    "SKILL.md documents nested per-slot tests_passing metadata in slot_details" || FAILED=$((FAILED + 1))
FILE_MODE_NOTE=$(echo "$SKILL_CONTENT" | sed -n '/For `file` isolation, each `slot_details` item uses `output_path` instead of `worktree_path`/,/Each file-isolation `slot_details` item still carries the slot output path, review path, files_changed, and tests_passing\./p')
assert_contains "$FILE_MODE_NOTE" "output_path" \
    "SKILL.md documents file-isolation output_path in slot_details" || FAILED=$((FAILED + 1))
assert_contains "$FILE_MODE_NOTE" "worktree-path.*omitted\|worktree-only.*omitted\|diff_path.*branch.*head_sha" \
    "SKILL.md documents omitted or null worktree-only fields for file isolation" || FAILED=$((FAILED + 1))
assert_contains "$FILE_MODE_NOTE" "review path\|files_changed\|tests_passing" \
    "SKILL.md documents file-isolation slot_details contents" || FAILED=$((FAILED + 1))

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
assert_contains "$SKILL_CONTENT" "RUN_DIR_REL\|absolute path\|cwd-relative redirect" \
    "SKILL.md makes run artifact paths absolute instead of relying on cwd" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" 'mkdir -p "\$RUN_DIR"' \
    "SKILL.md recreates the run directory before artifact writes" || FAILED=$((FAILED + 1))

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

# Must describe host-neutral skill references for TDD
assert_contains "$SKILL_CONTENT" "/superpowers:test-driven-development" \
    "SKILL.md documents /superpowers:test-driven-development" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "\$superpowers:test-driven-development" \
    "SKILL.md documents \$superpowers:test-driven-development" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "normalize.*superpowers:test-driven-development\|host-neutral skill reference" \
    "SKILL.md explains host-neutral skill normalization" || FAILED=$((FAILED + 1))

# Must describe CLAUDE.md config key
assert_contains "$SKILL_CONTENT" "slot-machine-slots" \
    "SKILL.md documents slot-machine-slots config key" || FAILED=$((FAILED + 1))

# Must treat AGENTS.md and CLAUDE.md as equal/either config sources
assert_contains "$SKILL_CONTENT" '\(AGENTS\.md.*CLAUDE\.md.*equal.*sources\|CLAUDE\.md.*AGENTS\.md.*equal.*sources\|either.*AGENTS\.md.*CLAUDE\.md\|either.*CLAUDE\.md.*AGENTS\.md\)' \
    "SKILL.md treats AGENTS.md and CLAUDE.md as equal/either config sources" || FAILED=$((FAILED + 1))

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
echo "=== Contract 12: Host and Harness Execution ==="
# SKILL.md must describe an execution matrix with host, harness, and path columns
assert_contains "$SKILL_CONTENT" "Active host.*Slot harness.*Execution path" \
    "SKILL.md has an execution matrix with host, harness, and path columns" || FAILED=$((FAILED + 1))

# Must describe all host/harness path combinations
assert_contains "$SKILL_CONTENT" "Claude.*Claude.*Native" \
    "SKILL.md includes Claude -> Claude native execution row" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "Claude.*Codex.*codex exec" \
    "SKILL.md includes Claude -> Codex execution row" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "Codex.*Codex.*codex exec" \
    "SKILL.md includes Codex -> Codex execution row" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "Codex.*Claude.*claude -p" \
    "SKILL.md includes Codex -> Claude execution row" || FAILED=$((FAILED + 1))

# Must describe native-host and external-harness group language
assert_contains "$SKILL_CONTENT" "Group 1.*Native-host slots\|Native-host slots.*Group 1" \
    "SKILL.md uses Group 1 Native-host slots language" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "Group 2.*External-harness slots\|External-harness slots.*Group 2" \
    "SKILL.md uses Group 2 External-harness slots language" || FAILED=$((FAILED + 1))

# Must describe JSONL output parsing
assert_contains "$SKILL_CONTENT" "JSONL\|jsonl" \
    "SKILL.md describes JSONL output parsing" || FAILED=$((FAILED + 1))

# Must describe multiple Codex event variants
assert_contains "$SKILL_CONTENT" "turn.completed\|item.completed" \
    "SKILL.md documents multiple Codex JSON event variants" || FAILED=$((FAILED + 1))

# Must describe Codex failure handling
assert_contains "$SKILL_CONTENT" "non-zero exit\|timeout.*codex\|codex.*fail" \
    "SKILL.md describes codex failure handling" || FAILED=$((FAILED + 1))

# Must describe deterministic post-run inspection fallback
assert_contains "$SKILL_CONTENT" "git status --short\|post-run inspection\|structured agent message" \
    "SKILL.md documents deterministic fallback when structured extraction fails" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "codex-slot-runner.py" \
    "SKILL.md documents the Codex slot runtime helper" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "thread_id\|codex_thread_id" \
    "SKILL.md documents Codex thread/session metadata in slot artifacts" || FAILED=$((FAILED + 1))

# Must forbid background Codex launches that bypass harvesting
assert_contains "$SKILL_CONTENT" "Never launch Codex slots as background Bash jobs\|wait for `codex exec` to finish\|wrapper must return a normal implementer report before reviewers or the judge can run" \
    "SKILL.md forbids background Codex launches that bypass harvesting" || FAILED=$((FAILED + 1))

# Must describe harness availability check with fallback
assert_contains "$SKILL_CONTENT" "which codex\|codex.*not found\|fall.*back.*Claude" \
    "SKILL.md describes codex availability check with fallback" || FAILED=$((FAILED + 1))

# Must describe mixed-harness parallel dispatch
assert_contains "$SKILL_CONTENT" "Claude Code slots.*parallel\|Codex slots.*background\|mixed.*harness\|dispatch.*group" \
    "SKILL.md describes mixed-harness parallel dispatch strategy" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 13: External Harness Commands ==="
# SKILL.md must describe Claude and Codex external harness commands
assert_contains "$SKILL_CONTENT" "claude -p" \
    "SKILL.md documents claude -p" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "stream-json" \
    "SKILL.md documents stream-json output mode" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "codex exec" \
    "SKILL.md documents codex exec" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "--json\|JSONL\|jsonl" \
    "SKILL.md documents JSON output formatting" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "workspace-write" \
    "SKILL.md documents workspace-write harness mode" || FAILED=$((FAILED + 1))

# Failure normalization terms should be present for external harness execution
assert_contains "$SKILL_CONTENT" "missing CLI\|timeout\|unparsable\|non-zero exit" \
    "SKILL.md normalizes external harness failure terms" || FAILED=$((FAILED + 1))

# Progress tables should identify harness and model
assert_contains "$SKILL_CONTENT" "| Harness | Model |" \
    "SKILL.md progress tables include Harness and Model columns" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 13A: No Claude Runtime Preflight Gate ==="
assert_not_contains "$SKILL_CONTENT" "Claude runtime readiness\|runtime-readiness\|runtime readiness" \
    "SKILL.md does not require a Claude runtime readiness preflight" || FAILED=$((FAILED + 1))
assert_not_contains "$SKILL_CONTENT" "checked once per run\|once per run" \
    "SKILL.md does not impose a once-per-run Claude preflight" || FAILED=$((FAILED + 1))
assert_not_contains "$SKILL_CONTENT" "Reply with exactly OK\|exactly OK" \
    "SKILL.md does not document a synthetic Claude OK probe" || FAILED=$((FAILED + 1))

CLAUDE_DOC_CONTENT=$(cat "$SKILL_DIR/CLAUDE.md" 2>/dev/null || echo "")
CONTRIBUTING_DOC_CONTENT=$(cat "$SKILL_DIR/CONTRIBUTING.md" 2>/dev/null || echo "")
assert_not_contains "$CLAUDE_DOC_CONTENT" "runtime readiness\|headless runtime contract\|exactly OK" \
    "CLAUDE.md does not describe a Claude runtime readiness gate" || FAILED=$((FAILED + 1))
assert_not_contains "$CONTRIBUTING_DOC_CONTENT" "runtime readiness\|headless runtime contract\|exactly OK" \
    "CONTRIBUTING.md does not describe a Claude runtime readiness gate" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 13B: Explicit Claude Slot Failure Behavior ==="
assert_contains "$SKILL_CONTENT" "explicit Claude slot\|explicit \`claude\` slot\|explicit claude slots" \
    "SKILL.md distinguishes explicit Claude slots" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "do not silently fall back\|must not silently fall back\|no silent fallback" \
    "SKILL.md forbids silent fallback for explicit Claude slots" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "Missing CLI\|non-zero exit\|empty report\|unparsable" \
    "SKILL.md documents per-slot external Claude failure normalization" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 14: Skill Discovery ==="
assert_contains "$SKILL_CONTENT" "Skill Discovery\|skill discovery" \
    "SKILL.md has Skill Discovery section" || FAILED=$((FAILED + 1))

assert_contains "$SKILL_CONTENT" "\-\-discover" \
    "SKILL.md documents --discover flag" || FAILED=$((FAILED + 1))

assert_contains "$SKILL_CONTENT" "all my skills\|all implementation skills" \
    "SKILL.md documents natural language discovery triggers" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 15: Orchestrator Trace ==="
TRACE_SECTION=$(echo "$SKILL_CONTENT" | sed -n '/^## Orchestrator Trace$/,/^## /p')
TRACE_SECTION_COMPACT=$(printf '%s' "$TRACE_SECTION" | tr '\n' ' ')

assert_contains "$TRACE_SECTION" "## Orchestrator Trace" \
    "SKILL.md has Orchestrator Trace section" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION" "events.jsonl" \
    "SKILL.md documents orchestrator trace events.jsonl path" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION" "state.json" \
    "SKILL.md documents orchestrator trace state.json path" || FAILED=$((FAILED + 1))
for reference_file in \
    references/orchestrator-trace.md \
    references/harness-execution.md \
    references/result-artifacts.md; do
    assert_contains "$TRACE_SECTION" "$reference_file" \
        "SKILL.md references $reference_file from the orchestrator trace contract" || FAILED=$((FAILED + 1))
done
for load_phrase in \
    "before creating or updating trace/history artifacts" \
    "before using Claude or Codex external harness execution paths" \
    "before writing final run artifacts"; do
    assert_contains "$TRACE_SECTION_COMPACT" "$load_phrase" \
        "SKILL.md includes load instruction: $load_phrase" || FAILED=$((FAILED + 1))
done
assert_contains "$TRACE_SECTION" "\\.slot-machine/history/active\\.json" \
    "SKILL.md documents .slot-machine/history/active.json" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION" "\\.slot-machine/history/latest\\.json" \
    "SKILL.md documents .slot-machine/history/latest.json" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION" "\\.slot-machine/history/index\\.jsonl" \
    "SKILL.md documents .slot-machine/history/index.jsonl" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION" '"status": "idle"' \
    "SKILL.md documents idle sentinel status" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 15A: Orchestrator Trace Events ==="
assert_contains "$TRACE_SECTION" "phase_entered" \
    "SKILL.md documents phase_entered events" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION" "artifact_written" \
    "SKILL.md documents artifact_written events" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION" "slot_retry_scheduled" \
    "SKILL.md documents slot_retry_scheduled events" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION" "run_finished" \
    "SKILL.md documents run_finished events" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION" "run_failed" \
    "SKILL.md documents run_failed events" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION" '"events_path"' \
    "SKILL.md documents events_path" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION" '"state_path"' \
    "SKILL.md documents state_path" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION" '"current_phase"' \
    "SKILL.md documents current_phase state" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION" '"last_event_seq"' \
    "SKILL.md documents last_event_seq state" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION_COMPACT" "Any change that adds a new orchestration phase.*update" \
    "SKILL.md includes maintenance rule for new orchestration phases" || FAILED=$((FAILED + 1))
assert_contains "$TRACE_SECTION_COMPACT" "SKILL\\.md and \`skills/slot-machine/SKILL\\.md\` must stay byte-for-byte synchronized" \
    "SKILL.md includes mirror sync rule for the packaged skill" || FAILED=$((FAILED + 1))

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

# Implementers dispatch in a single message for true parallelism
assert_contains "$SKILL_CONTENT" "SINGLE message\|single message.*parallel\|parallel Agent tool calls" \
    "SKILL.md dispatches implementers in a single parallel message" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract 18: Python Test Command Guidance ==="
assert_contains "$SKILL_CONTENT" "python3 -m pytest" \
    "SKILL.md prefers python3 pytest commands for Python repos" || FAILED=$((FAILED + 1))
assert_contains "$SKILL_CONTENT" "Do not assume.*python.*exists\|only guarantee.*python3\|Do not invent.*python -m pytest" \
    "SKILL.md warns against assuming a bare python executable" || FAILED=$((FAILED + 1))

echo ""
echo "=== Contract Tests Complete ==="
echo "Failures: $FAILED"
exit $FAILED
