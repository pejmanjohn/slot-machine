# Task Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make slot-machine domain-agnostic by extracting all task-specific content (prompts, hints, pre-checks, isolation strategy) into self-contained profile files, shipping coding and writing as built-in profiles.

**Architecture:** SKILL.md becomes a pure orchestration engine. Each profile is a single markdown file containing frontmatter config + approach hints + all 4 agent prompt templates. Profiles support single-level inheritance via `extends:` frontmatter. Profile selection: explicit override > project default > auto-detect (coding/writing signals) > ask user.

**Tech Stack:** Markdown files, bash test scripts. No runtime dependencies.

**Design doc:** `docs/plans/2026-03-27-task-profiles.md`
**Spike results:** `docs/brainstorms/2026-03-27-writing-mode-spike.md`

---

### Task 1: Create `profiles/coding.md` — migrate existing prompts

Migrate the 4 standalone prompt templates and approach hints into a single coding profile file. This is a reorganization — the content is preserved, just moved.

**Files:**
- Create: `profiles/coding.md`
- Source (read-only): `slot-implementer-prompt.md`, `slot-reviewer-prompt.md`, `slot-judge-prompt.md`, `slot-synthesizer-prompt.md`, `SKILL.md` (approach hints section)

- [ ] **Step 1: Create the profiles directory**

```bash
mkdir -p profiles
```

- [ ] **Step 2: Create `profiles/coding.md` with frontmatter**

Write the frontmatter and section structure. The `pre_checks` field contains bash command templates. The orchestrator substitutes `{test_command}` with the detected test command (pytest, npm test, etc.) during Phase 1 before running these.

```markdown
---
name: coding
description: For implementing well-specified features in a codebase. Use when the spec describes code to write — functions, modules, APIs, services.
extends: null
isolation: worktree
pre_checks: |
  {test_command} 2>&1
  git diff --name-only HEAD~1
  find . -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.rb" -o -name "*.go" -o -name "*.rs" | head -50 | xargs wc -l 2>/dev/null || true
---
```

Note: `{test_command}` is substituted by the orchestrator from what it detected during project context gathering. This is not a universal `{{VARIABLE}}` — it's a pre_checks-specific template substitution.

- [ ] **Step 3: Add the Approach Hints section**

Copy the full "Approach Hints" section from SKILL.md (lines 397-419 — all 10 hints, both default and extended) into `profiles/coding.md` as `## Approach Hints` and `## Extended Hints`.

Keep the exact text of all 10 hints. Do not modify hint content.

- [ ] **Step 4: Add the Implementer Prompt section**

Add `## Implementer Prompt` section. Copy the full content of `slot-implementer-prompt.md` starting from line 7 (after the `---` separator — skip the header comment and separator). This is everything from "You are implementing a feature..." to the end of the report format.

- [ ] **Step 5: Add the Reviewer Prompt section**

Add `## Reviewer Prompt` section. Copy the full content of `slot-reviewer-prompt.md` starting from line 7 (after the `---` separator). This includes the evidence rules, the 4-pass review process, the output format, and the example review.

- [ ] **Step 6: Add the Judge Prompt section**

Add `## Judge Prompt` section. Copy the full content of `slot-judge-prompt.md` starting from line 7 (after the `---` separator). This includes the 4-step process and the output format.

- [ ] **Step 7: Add the Synthesizer Prompt section**

Add `## Synthesizer Prompt` section. Copy the full content of `slot-synthesizer-prompt.md` starting from line 7 (after the `---` separator). This includes the 6-step process and the report format.

- [ ] **Step 8: Verify the coding profile is complete**

Check that `profiles/coding.md` has all required sections:

```bash
for section in "Approach Hints" "Implementer Prompt" "Reviewer Prompt" "Judge Prompt" "Synthesizer Prompt"; do
    grep -q "## $section" profiles/coding.md && echo "PASS: $section" || echo "FAIL: $section"
done
```

Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add profiles/coding.md
git commit -m "feat: create coding profile — migrate prompts and hints into single file"
```

---

### Task 2: Create `profiles/writing.md` — writing profile

**⚠️ Highest-risk task.** This is entirely new content — no existing prompts to migrate. The prompt descriptions below are specific (exact pass names, evaluation criteria, variable mappings) but the actual prose must be authored during implementation. Task 8 (live test) is the real validation. Expect iteration.

Create the writing profile based on learnings from the writing-mode spike (`docs/brainstorms/2026-03-27-writing-mode-spike.md`). This is new content, not a migration.

**Files:**
- Create: `profiles/writing.md`
- Reference (read-only): `spike/approach-hints.md`, `spike/writing-brief.md`, `profiles/coding.md` (for structural reference)

- [ ] **Step 1: Create `profiles/writing.md` with frontmatter**

```markdown
---
name: writing
description: For drafting documents, READMEs, blog posts, announcements, or any prose. Use when the spec describes text to write — not code.
extends: null
isolation: file
pre_checks: null
---
```

Key differences from coding: `isolation: file` (no worktrees — each slot writes to a separate file), `pre_checks: null` (no tests or linters for prose).

- [ ] **Step 2: Add the Approach Hints section**

Use the 5 writing-specific hints validated in the spike (from `spike/approach-hints.md`). These produced genuinely diverse outputs — minimalist, narrative, show-don't-tell, technical, bold-claim. Copy the full hint text for each.

- [ ] **Step 3: Write the Implementer Prompt section**

Add `## Implementer Prompt` with a writing-specific prompt. Key differences from coding implementer:

- "You are drafting a document..." instead of "You are implementing a feature..."
- No test commands or git worktree references
- Self-review focuses on: brief compliance, clarity, accuracy, voice — not code quality or tests
- "Your Job" steps: read the spec, read any reference materials, draft the document, self-review, report back
- Report format is the same structure (Status, What I produced, Files changed, Self-review findings, Concerns) — statuses DONE/DONE_WITH_CONCERNS/BLOCKED/NEEDS_CONTEXT remain unchanged
- Include guidance on what makes good writing: clear voice, no generic AI filler, every sentence earns its place
- The `{{SPEC}}` variable is the writing brief. `{{APPROACH_HINT}}` is the writing style hint. `{{PROJECT_CONTEXT}}` is any reference materials or examples.

- [ ] **Step 4: Write the Reviewer Prompt section**

Add `## Reviewer Prompt` with a writing-specific 4-pass review process:

- **Pass 1: Brief Compliance (GATE)** — go through the spec/brief line by line. Did the draft cover everything asked? Missing a required section = CRITICAL.
- **Pass 2: Accuracy** — is the information factually correct? Are claims supported? Any misleading statements?
- **Pass 3: Evidence Assessment** — does the writing prove its claims? Are examples concrete? Is the argument supported or just asserted?
- **Pass 4: Strengths** — what's this draft's standout quality? Best section, strongest voice, most compelling argument.

Evidence rules adapt: instead of "cite file:line," it's "cite the specific passage." Instead of "grep the worktree," it's "read the draft to verify." The "Don't trust the implementer's report" philosophy carries over — the reviewer reads the actual draft, not the implementer's self-assessment.

Output format mirrors coding: Spec Compliance (PASS/FAIL), Issues (Critical/Important/Minor), Strengths, Approach Hint Influence, Verdict (Contender? Yes/No/With concerns).

The `{{WORKTREE_PATH}}` variable becomes the path to the draft file.

- [ ] **Step 5: Write the Judge Prompt section**

Add `## Judge Prompt`. This is mostly the same as the coding judge — the verdict framework (PICK/SYNTHESIZE/NONE_ADEQUATE), ranking table, and convergence logic are all domain-agnostic.

Key adaptations:
- "Targeted code inspection" becomes "targeted draft reading" — the judge reads specific sections where reviewers diverge, not full files
- Synthesis plan references sections/passages instead of file:line ranges
- Quality criteria are prose-specific: voice, clarity, persuasiveness, structure

- [ ] **Step 6: Write the Synthesizer Prompt section**

Add `## Synthesizer Prompt`. This has the biggest changes from coding:

- Instead of "copy files from worktrees," the strategy is editorial: "take the opening from slot 2, the argument structure from slot 4, the closing from slot 1"
- Instead of git operations, the synthesizer reads all drafts and writes a new document that combines the best elements
- Coherence check: "does it read like one person wrote it?" — same concept as coding, different execution
- No test suite to run. The quality check is a self-review pass.
- The `{{SYNTHESIS_PLAN}}` from the judge describes which sections/elements to take from which drafts
- `{{WORKTREE_PATHS}}` becomes paths to draft files
- `{{BASE_SLOT_PATH}}` becomes the path to the base draft

- [ ] **Step 7: Verify the writing profile is complete**

```bash
for section in "Approach Hints" "Implementer Prompt" "Reviewer Prompt" "Judge Prompt" "Synthesizer Prompt"; do
    grep -q "## $section" profiles/writing.md && echo "PASS: $section" || echo "FAIL: $section"
done
```

Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add profiles/writing.md
git commit -m "feat: create writing profile — prose drafting with editorial review and synthesis"
```

---

### Task 3: Refactor SKILL.md — profile-aware orchestration

Make SKILL.md load profiles instead of hardcoded prompt files. The orchestration phases stay the same. What changes is where prompts, hints, and config come from.

**Files:**
- Modify: `SKILL.md`
- Reference (read-only): `profiles/coding.md`, `profiles/writing.md`

- [ ] **Step 1: Update the header and description**

Change the subtitle from "Best-of-N parallel implementation for coding agents" to "Best-of-N parallel implementation for any task" (or similar wording that reflects domain-agnosticism).

Update the frontmatter `description` to mention that slot-machine works for coding, writing, and custom task types.

Update the "Core principle" line and the "Announce at start" template to not assume coding.

- [ ] **Step 2: Add a Profile Loading section after Configuration**

Add a new section `## Profile Loading` after the Configuration table. This section explains:

1. How profiles are discovered (discovery order from the design doc):
   - Explicit: user says `--profile X` or `profile: X`
   - Project default: `CLAUDE.md` sets `slot-machine-profile: X`
   - Local: `./profiles/` in the project
   - Skill: `profiles/` in the slot-machine skill installation
   - Fallback: `coding`

2. Profile selection logic:
   - If explicit or project-configured → use it
   - If not → auto-detect between coding/writing from spec signals
   - Coding signals: implement, build, create, fix, refactor; references to tests, APIs, functions
   - Writing signals: write, draft, compose, describe; references to audience, tone, structure
   - If not confident → ask one question

3. Profile inheritance resolution:
   - If profile has `extends: X`, read base profile X first
   - Overlay the extending profile's sections on top
   - Sections present in extending profile replace base entirely
   - Frontmatter fields override individually
   - Max one level of inheritance

4. Universal variables that SKILL.md injects into all profile prompts:
   - `{{SPEC}}`, `{{APPROACH_HINT}}`, `{{PROJECT_CONTEXT}}`, `{{SLOT_NUMBER}}`
   - `{{PRE_CHECK_RESULTS}}`, `{{IMPLEMENTER_REPORT}}`, `{{WORKTREE_PATH}}`
   - `{{ALL_SCORECARDS}}`, `{{WORKTREE_PATHS}}`, `{{SLOT_COUNT}}`
   - `{{SYNTHESIS_PLAN}}`, `{{BASE_SLOT_PATH}}`

- [ ] **Step 3: Update Phase 1 to load and use the profile**

In the Phase 1: Setup section:

- Add step 0 (before "Validate the spec"): **Load profile.** Follow the profile loading section to find and resolve the active profile. Report to user: "Using profile: {name}"
- Change step 3: instead of "Ensure git repo is ready" unconditionally, make it conditional: "If profile isolation is `worktree`, ensure git repo is ready." For `file` isolation, create a temp directory for slot outputs instead.
- Change step 4: instead of "Verify test baseline" unconditionally, read the profile's `pre_checks` field. If null, skip. If set, run those commands.
- Change step 5: "Assign approach hints" — read hints from the profile's `## Approach Hints` section instead of the hardcoded list in SKILL.md.
- Update the setup report to include the profile name.

- [ ] **Step 4: Update Phase 2 to read prompts from profile**

In the Phase 2: Parallel Implementation section:

- Change the prompt source: instead of `Read ./slot-implementer-prompt.md and fill in all {{VARIABLES}}`, it's `Read the ## Implementer Prompt section from the active profile and fill in all universal {{VARIABLES}}`
- Change the isolation parameter: instead of hardcoded `"worktree"`, use the profile's `isolation` field. If `file`, don't set `isolation: "worktree"` on the Agent call — instead, tell the agent to write its output to a specific file path.
- For `file` isolation: each slot writes to `{temp_dir}/slot-{i}-output.md` (or appropriate extension). No worktrees, no git branches.

- [ ] **Step 5: Update Phase 3 to read prompts from profile**

In the Phase 3: Review and Judgment section:

- Step 0 (pre-checks): instead of the hardcoded Python bash commands, run the commands from the profile's `pre_checks` frontmatter. Before running, substitute `{test_command}` with the test command detected during Phase 1 context gathering (pytest, npm test, make test, etc.). If `pre_checks` is `null`, skip pre-checks entirely and pass an empty string for `{{PRE_CHECK_RESULTS}}`.
- Step 1 (reviewers): read from `## Reviewer Prompt` section in the active profile.
- Step 2 (judge): read from `## Judge Prompt` section in the active profile.

- [ ] **Step 6: Update Phase 4 to read prompts from profile**

In the Phase 4: Resolution section:

- Synthesizer prompt: read from `## Synthesizer Prompt` section in the active profile.
- PICK resolution: if isolation is `worktree`, merge the branch (as today). If isolation is `file`, copy the winning file to the target location.
- SYNTHESIZE resolution: if isolation is `worktree`, synthesizer gets its own worktree (as today). If isolation is `file`, synthesizer reads the slot output files and writes a new combined output.
- Cleanup: if isolation is `worktree`, remove worktrees (as today). If isolation is `file`, remove temp directory.

- [ ] **Step 7: Remove hardcoded approach hints from SKILL.md**

Delete the entire `## Approach Hints` section from SKILL.md (including both default and extended hints). These now live in `profiles/coding.md`. Add a note: "Approach hints are defined in the active profile. See `profiles/coding.md` for the coding defaults."

- [ ] **Step 8: Remove hardcoded pre-check commands from SKILL.md**

In Phase 3, Step 0, replace the hardcoded Python bash commands with: "Run the pre-check commands defined in the active profile's `pre_checks` frontmatter field. If `null`, skip pre-checks."

- [ ] **Step 9: Update the "What This Is NOT" section**

Add a note that slot-machine works for non-coding tasks too. The "competition and selection" principle is universal — it's not just about code.

- [ ] **Step 10: Verify SKILL.md no longer references standalone prompt files**

```bash
grep -n "slot-implementer-prompt\|slot-reviewer-prompt\|slot-judge-prompt\|slot-synthesizer-prompt" SKILL.md
```

Expected: no matches (all references now point to profile sections).

- [ ] **Step 11: Commit**

```bash
git add SKILL.md
git commit -m "refactor: make SKILL.md profile-aware — load prompts, hints, and config from profiles"
```

---

### Task 4: Update tests for profile-based structure

Update the test suite to validate profiles instead of standalone prompt template files.

**Files:**
- Modify: `tests/test-contracts.sh`
- Modify: `tests/test-skill-structure.sh`
- Modify: `tests/test-helpers.sh` (if it defines paths to prompt files)

- [ ] **Step 1: Update `test-skill-structure.sh` to check for profiles directory**

Replace the `SKILL_FILES` array that checks for standalone prompt files:

```bash
# Old:
SKILL_FILES=(
    SKILL.md
    slot-implementer-prompt.md
    slot-reviewer-prompt.md
    slot-judge-prompt.md
    slot-synthesizer-prompt.md
)

# New:
SKILL_FILES=(
    SKILL.md
    profiles/coding.md
    profiles/writing.md
)
```

Add a check that each profile has required sections:

```bash
for profile in "$SKILL_DIR"/profiles/*.md; do
    PROFILE_NAME=$(basename "$profile")
    PROFILE_CONTENT=$(cat "$profile")
    for section in "Approach Hints" "Implementer Prompt" "Reviewer Prompt" "Judge Prompt" "Synthesizer Prompt"; do
        assert_contains "$PROFILE_CONTENT" "## $section" \
            "Profile '$PROFILE_NAME' has section '$section'" || FAILED=$((FAILED + 1))
    done
done
```

Add frontmatter validation:

```bash
for profile in "$SKILL_DIR"/profiles/*.md; do
    PROFILE_NAME=$(basename "$profile")
    PROFILE_CONTENT=$(cat "$profile")
    assert_contains "$PROFILE_CONTENT" "name:" "Profile '$PROFILE_NAME' has name in frontmatter" || FAILED=$((FAILED + 1))
    assert_contains "$PROFILE_CONTENT" "description:" "Profile '$PROFILE_NAME' has description in frontmatter" || FAILED=$((FAILED + 1))
    assert_contains "$PROFILE_CONTENT" "isolation:" "Profile '$PROFILE_NAME' has isolation in frontmatter" || FAILED=$((FAILED + 1))
done
```

- [ ] **Step 2: Update `test-contracts.sh` to validate profiles**

Change Contract 1 (Implementer Status) to read from profile instead of standalone file:

```bash
# Old:
IMPL_CONTENT=$(cat "$SKILL_DIR/slot-implementer-prompt.md")

# New — iterate over all profiles:
for profile in "$SKILL_DIR"/profiles/*.md; do
    PROFILE_NAME=$(basename "$profile")
    PROFILE_CONTENT=$(cat "$profile")
    # Extract implementer prompt section
    IMPL_CONTENT=$(sed -n '/^## Implementer Prompt$/,/^## /p' "$profile" | head -n -1)

    for status in DONE DONE_WITH_CONCERNS BLOCKED NEEDS_CONTEXT; do
        assert_contains "$IMPL_CONTENT" "$status" \
            "Status '$status' in $PROFILE_NAME implementer prompt" || FAILED=$((FAILED + 1))
    done
done
```

Apply the same pattern for Contract 2 (Reviewer → Judge), Contract 3 (Judge → SKILL.md), Contract 4 (Judge → Synthesizer), and Contract 5 (Template Variables).

For Contract 5 (variables), check that all `{{VARIABLE}}` patterns in each profile section are from the universal set defined in SKILL.md.

For Contract 7 (Approach Hints), iterate over profiles and check each one has at least 5 hints. The architectural keyword check only applies to the coding profile — writing hints won't have Python-specific keywords.

- [ ] **Step 3: Check all other test files for old prompt references**

Grep all test files for references to the old standalone prompt filenames:

```bash
grep -rn "slot-implementer-prompt\|slot-reviewer-prompt\|slot-judge-prompt\|slot-synthesizer-prompt" tests/
```

Update any matches found — this may include `test-e2e-happy-path.sh`, `test-implementer-smoke.sh`, `test-reviewer-smoke.sh`, `test-judge-smoke.sh`, or others. Each reference should be updated to read from the corresponding profile section instead.

- [ ] **Step 4: Add inheritance validation**

Add a new contract that validates profile inheritance:

```bash
echo "=== Contract 8: Profile Inheritance ==="
for profile in "$SKILL_DIR"/profiles/*.md; do
    PROFILE_NAME=$(basename "$profile")
    EXTENDS=$(grep "^extends:" "$profile" | head -1 | awk '{print $2}')
    if [ -n "$EXTENDS" ] && [ "$EXTENDS" != "null" ]; then
        BASE_FILE="$SKILL_DIR/profiles/${EXTENDS}.md"
        if [ -f "$BASE_FILE" ]; then
            echo "  [PASS] $PROFILE_NAME extends '$EXTENDS' — base file exists"
        else
            echo "  [FAIL] $PROFILE_NAME extends '$EXTENDS' — base file NOT FOUND"
            FAILED=$((FAILED + 1))
        fi
        # Check no multi-level inheritance
        BASE_EXTENDS=$(grep "^extends:" "$BASE_FILE" | head -1 | awk '{print $2}')
        if [ -n "$BASE_EXTENDS" ] && [ "$BASE_EXTENDS" != "null" ]; then
            echo "  [FAIL] $PROFILE_NAME -> $EXTENDS -> $BASE_EXTENDS — multi-level inheritance not allowed"
            FAILED=$((FAILED + 1))
        fi
    fi
done
```

- [ ] **Step 5: Run the updated tests**

```bash
./tests/run-tests.sh
```

Expected: all pass. The tests now validate the profile-based structure instead of standalone files.

- [ ] **Step 6: Commit**

```bash
git add tests/
git commit -m "test: update contract tests for profile-based structure"
```

---

### Task 5: Delete old files, update docs

Remove the standalone prompt template files (content is now in profiles) and update documentation.

**Files:**
- Delete: `slot-implementer-prompt.md`, `slot-reviewer-prompt.md`, `slot-judge-prompt.md`, `slot-synthesizer-prompt.md`
- Modify: `CLAUDE.md`
- Modify: `CONTRIBUTING.md`

- [ ] **Step 1: Delete standalone prompt template files and reference copies**

```bash
git rm slot-implementer-prompt.md slot-reviewer-prompt.md slot-judge-prompt.md slot-synthesizer-prompt.md
git rm docs/reference/slot-implementer-prompt.md docs/reference/slot-reviewer-prompt.md docs/reference/slot-judge-prompt.md docs/reference/slot-synthesizer-prompt.md
```

The `docs/reference/` copies are stale references to the old structure. Remove them to avoid confusion. `docs/reference/SPEC.md` is unrelated and stays.

- [ ] **Step 2: Update CLAUDE.md**

Change the Structure section to reflect the new layout:

```markdown
## Structure
- `SKILL.md` — Orchestration engine (shared across all task types)
- `profiles/` — Task-specific profiles (prompts, hints, config)
  - `coding.md` — Built-in: code implementation tasks
  - `writing.md` — Built-in: writing/drafting tasks
- `tests/` — Tiered test suite
- `.claude-plugin/` — Plugin distribution metadata
```

Update the Key Rules:
- Change "All {{VARIABLES}} in prompt templates must be documented in SKILL.md" to "All {{VARIABLES}} in profile prompts must be from the universal variable set in SKILL.md"
- Change "Status/verdict values must match across all files" to "Status/verdict values must match across SKILL.md and all profiles"

- [ ] **Step 3: Update CONTRIBUTING.md**

Change "If your change touches prompt templates (`slot-*-prompt.md`)" to "If your change touches profiles (`profiles/*.md`)".

Add a note about creating custom profiles:
```markdown
## Creating Custom Profiles

To create a custom profile, either:
- Create a new `.md` file in `profiles/` following the structure of `coding.md` or `writing.md`
- Create a profile that extends an existing one with `extends: coding` in the frontmatter

Run `./tests/run-tests.sh` to validate your profile has all required sections and consistent contracts.
```

- [ ] **Step 4: Run the full test suite**

```bash
./tests/run-tests.sh
```

Expected: all pass with the new file structure.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove standalone prompt files, update docs for profile structure"
```

---

### Task 6: Verify structure end-to-end

Run a quick sanity check that the new file structure is complete and consistent before live testing.

**Files:** None — read-only verification.

- [ ] **Step 1: Verify no references to deleted files**

```bash
grep -r "slot-implementer-prompt\|slot-reviewer-prompt\|slot-judge-prompt\|slot-synthesizer-prompt" --include="*.md" --include="*.sh" .
```

Expected: no matches (all references updated to profile-based).

- [ ] **Step 2: Verify both profiles have all required sections**

```bash
for profile in profiles/*.md; do
    echo "=== $(basename $profile) ==="
    for section in "Approach Hints" "Implementer Prompt" "Reviewer Prompt" "Judge Prompt" "Synthesizer Prompt"; do
        grep -q "## $section" "$profile" && echo "  PASS: $section" || echo "  FAIL: $section"
    done
done
```

- [ ] **Step 3: Run the full test suite**

```bash
./tests/run-tests.sh
```

Expected: all pass.

- [ ] **Step 4: Verify SKILL.md references profiles correctly**

```bash
grep -c "profile" SKILL.md
```

Expected: multiple references to profiles in the orchestration instructions.

---

### Task 7: Live test — coding profile

Run slot-machine with the coding profile on a small spec to verify the profile loads correctly, prompts are read from the profile, and the full pipeline works end-to-end. This is the regression test — coding must work exactly as it did before the refactor.

**Files:** None created — this is a live execution test.
**Time:** ~5-10 minutes. 2 slots × (implementer + reviewer) + judge = ~6 agent calls at sonnet/opus speed. Don't assume it's stuck.

- [ ] **Step 1: Use the tiny-spec fixture for a quick run**

Read `tests/fixtures/tiny-spec.md` — this is the smallest spec in the test suite. Run slot-machine with 2 slots (minimum for comparison) using the coding profile explicitly:

```
slot-machine this with 2 slots, profile: coding

Spec: [paste contents of tests/fixtures/tiny-spec.md]
```

- [ ] **Step 2: Verify Phase 1 — profile loading**

Check the setup report:
- Does it say "Using profile: coding"?
- Does it show approach hints from `profiles/coding.md` (not from SKILL.md)?
- Does it verify test baseline (pre_checks ran)?
- Does it use worktree isolation?

- [ ] **Step 3: Verify Phase 2 — implementers use profile prompts**

Check that implementers:
- Were dispatched with `isolation: "worktree"`
- Received the implementer prompt from the coding profile (references tests, code quality, YAGNI)
- Produced implementer reports with the expected status format (DONE/DONE_WITH_CONCERNS/BLOCKED/NEEDS_CONTEXT)

- [ ] **Step 4: Verify Phase 3 — reviewers and judge use profile prompts**

Check that reviewers:
- Ran pre-checks (test results, file diffs, line counts)
- Used the coding reviewer's 4-pass process (Spec Compliance, Correctness, Test Assessment, Strengths)
- Produced structured scorecards with the expected format

Check that the judge:
- Read scorecards and produced a verdict (PICK/SYNTHESIZE/NONE_ADEQUATE)
- Used the expected ranking format

- [ ] **Step 5: Verify Phase 4 — resolution**

Check that the verdict was executed:
- If PICK: winning branch was merged
- If SYNTHESIZE: synthesizer used the coding synthesizer prompt (git operations, base + ports)
- Worktrees were cleaned up (if cleanup: true)
- Final report was produced

- [ ] **Step 6: Compare to pre-refactor behavior**

The output should be functionally identical to running slot-machine before the profile refactor. The only visible difference should be the "Using profile: coding" line in the setup report.

If any phase behaves differently from before, investigate and fix before proceeding.

---

### Task 8: Live test — writing profile

Run slot-machine with the writing profile to verify the new profile works end-to-end. This validates the entire writing pipeline — file isolation, writing-specific prompts, prose review, editorial synthesis.

**Files:** None created — this is a live execution test.
**Time:** ~5-10 minutes. Same agent call count as Task 7. Writing slots may be faster since there are no test suites to run.

- [ ] **Step 1: Create a small writing spec**

Write a brief for a short writing task — something quick enough to complete with 2 slots but complex enough to have real design choices. Example:

```
Write a 200-word project tagline and elevator pitch for slot-machine.
The audience is developers who use Claude Code.
It should explain what slot-machine does and why they should care.
Cover: what it is, the key insight (competition > single attempt), and one concrete benefit.
```

- [ ] **Step 2: Run slot-machine with writing profile**

```
slot-machine this with 2 slots, profile: writing

Spec: [the brief from Step 1]
```

- [ ] **Step 3: Verify Phase 1 — writing profile loading**

Check the setup report:
- Does it say "Using profile: writing"?
- Does it show writing-specific approach hints (tone/structure variations, not architecture styles)?
- Does it skip test baseline (pre_checks: null)?
- Does it use file isolation (no worktrees)?

- [ ] **Step 4: Verify Phase 2 — implementers produce drafts**

Check that implementers:
- Were NOT dispatched with `isolation: "worktree"` (file isolation instead)
- Wrote their drafts to separate files
- Received the writing implementer prompt (references clarity, voice, audience — not tests or code quality)
- Produced reports with standard status format

- [ ] **Step 5: Verify Phase 3 — writing-specific review**

Check that reviewers:
- Skipped pre-checks (no test output, no linter)
- Used the writing reviewer's 4-pass process (Brief Compliance, Accuracy, Evidence Assessment, Strengths)
- Evaluated prose quality, not code quality
- Produced scorecards with the standard format (Spec Compliance PASS/FAIL, Issues, Strengths, Verdict)

Check that the judge:
- Compared drafts on writing quality, not code metrics
- Produced a verdict using the standard format

- [ ] **Step 6: Verify Phase 4 — writing-specific resolution**

If PICK:
- The winning draft was identified (no branch merge — just the file)

If SYNTHESIZE:
- The synthesizer used editorial merge strategy (combine sections/passages, not git operations)
- The result reads like one person wrote it
- No "Frankenstein" seams between ported elements

- [ ] **Step 7: Evaluate output quality**

Read the winning draft (or synthesis). Does it:
- Address the brief?
- Have a clear voice?
- Show the influence of the approach hint?
- Feel like a reasonable quality output?

This is a subjective check — the goal is "does the writing pipeline produce something usable," not "is this the best possible output." If the output is incoherent, garbled, or ignores the brief, something is wrong with the writing profile prompts.

- [ ] **Step 8: Commit any fixes**

If any issues were found and fixed during testing:

```bash
git add -A
git commit -m "fix: address issues found during live profile testing"
```

---

### Task 9: Live test — auto-detection

Verify that profile auto-detection correctly identifies coding vs. writing tasks without explicit profile selection.

**Files:** None — live execution test.
**Time:** ~15-20 minutes total for 3 test runs (coding, writing, ambiguous). Each run is 2 slots.

- [ ] **Step 1: Test auto-detection with a coding spec**

Give slot-machine a clearly coding-oriented spec without specifying a profile:

```
slot-machine this with 2 slots

Implement a function called `fibonacci(n)` that returns the nth Fibonacci number.
Handle edge cases (n=0, n=1, negative n). Include tests.
```

Verify: it auto-detects and uses the coding profile (worktrees, test baseline, code-oriented hints).

- [ ] **Step 2: Test auto-detection with a writing spec**

Give slot-machine a clearly writing-oriented spec without specifying a profile:

```
slot-machine this with 2 slots

Write a 3-paragraph changelog entry announcing the new task profiles feature for slot-machine.
Target audience: existing users of the tool. Tone: excited but not hyperbolic.
```

Verify: it auto-detects and uses the writing profile (file isolation, no test baseline, writing-oriented hints).

- [ ] **Step 3: Test ambiguous spec triggers the ask**

Give slot-machine a spec that's ambiguous between coding and writing:

```
slot-machine this with 2 slots

Create documentation for the slot-machine API that includes code examples.
```

Verify: it asks the user which profile to use rather than guessing.

- [ ] **Step 4: Document any detection issues**

If auto-detection made a wrong call, note what signals were misleading and adjust the detection logic in SKILL.md. Commit any fixes.
