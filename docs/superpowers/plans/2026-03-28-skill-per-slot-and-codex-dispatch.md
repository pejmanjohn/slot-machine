# Skill-Per-Slot and Native Codex Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make slot-machine dispatch pluggable — users can assign different skills (`/superpowers:tdd`, `/ce:work`) and harnesses (`codex`) to individual slots, composable with `+` syntax.

**Architecture:** Two new concepts added to SKILL.md's orchestration: (1) slot definitions that override the profile's implementer prompt with skill guidance or harness dispatch, and (2) a native Codex dispatch path via `codex exec` CLI. The evaluation pipeline (review, judge, synthesis) is unchanged — only the implementation step becomes pluggable.

**Tech Stack:** Markdown (SKILL.md orchestration instructions), bash test scripts. Codex dispatch via `codex exec` CLI with JSONL output parsing.

**Design doc:** `docs/plans/2026-03-28-slot-machine-as-infrastructure.md`

---

### Task 1: Add slot definition parsing to SKILL.md Phase 1

Add the ability for the orchestrator to parse slot definitions from the user's invocation or CLAUDE.md config. This is the foundation — later tasks build on the parsed slot list.

**Files:**
- Modify: `SKILL.md` (Phase 1 Setup section)

- [ ] **Step 1: Add "Slot Definitions" section after Profile Loading in SKILL.md**

After the `## Profile Loading` section and before `## The Process`, add a new section `## Slot Definitions` that explains:

1. Three input sources (precedence: inline > CLAUDE.md > profile defaults):

   **Inline:** Parse skill/harness names from the user's command. Slash-prefixed names (`/superpowers:tdd`, `/ce:work`) are skills. Bare names (`codex`) are harnesses. The `+` operator composes them (`/superpowers:tdd + codex`). The word `default` means use the profile's implementer prompt + approach hint.

   **CLAUDE.md config:** Read `slot-machine-slots` list if present:
   ```markdown
   slot-machine-slots:
     - /superpowers:tdd
     - /ce:work
     - codex
     - default
   ```

   **Profile defaults:** If no slot definitions found, use the current behavior — all slots get the profile's implementer prompt with randomly assigned approach hints.

2. Slot definition parsing rules:
   - If the user specifies slot definitions AND a slot count higher than the definitions, remaining slots get profile defaults with approach hints
   - If the user specifies only slot definitions (no count), the slot count equals the number of definitions
   - Each slot definition produces a tuple: `(skill: string | null, harness: string | null)`
   - `default` → `(null, null)` — use profile implementer + hint
   - `/superpowers:tdd` → `(skill="/superpowers:tdd", harness=null)` — Claude Code with skill guidance
   - `codex` → `(skill=null, harness="codex")` — Codex with profile implementer
   - `/superpowers:tdd + codex` → `(skill="/superpowers:tdd", harness="codex")` — Codex with skill guidance

3. Poor slot candidate warning: If a parsed skill name matches a known multi-agent orchestrator (`/superpowers:subagent-driven-development`, `/superpowers:executing-plans`), warn the user but don't block.

- [ ] **Step 2: Update Phase 1 Step 0 to parse slot definitions**

In the Phase 1 Setup, after loading the profile, add a step to parse slot definitions:

"**Parse slot definitions.** Check for slot definitions in this order: (1) inline in the user's command, (2) `slot-machine-slots` in CLAUDE.md, (3) fall back to profile defaults. Record the slot list — each slot is `(skill, harness)` or `default`."

- [ ] **Step 3: Update Phase 1 setup report to show slot definitions**

Change the setup report template from:

```
Slots: `{N}` | Hints: {hint_1}, {hint_2}, ...
```

To:

```
Slots: `{N}` | {slot_summary}
```

Where `{slot_summary}` is:
- If all defaults: `Hints: {hint_1}, {hint_2}, ...` (current behavior)
- If mixed: `Slots: /superpowers:tdd, /ce:work, codex, 2x default hints`

- [ ] **Step 4: Commit**

```bash
git add SKILL.md
git commit -m "feat: add slot definition parsing to Phase 1 — skill/harness/default per slot"
```

---

### Task 2: Update Phase 2 dispatch for skill-based slots

Make the implementer dispatch conditional — skill-based slots get skill guidance injected instead of the profile's implementer prompt.

**Files:**
- Modify: `SKILL.md` (Phase 2 section)

- [ ] **Step 1: Add skill dispatch path to Phase 2**

In the Phase 2 dispatch section, before the current Agent tool call table, add conditional logic:

"For each slot, check its definition:

**If `default` (no skill, no harness):** Use the current dispatch — read `1-implementer.md` from the active profile, fill variables, include approach hint. This is unchanged from Phase 1 behavior.

**If skill-based (e.g., `/superpowers:tdd`, no harness):** Do NOT read the profile's `1-implementer.md`. Instead, dispatch the Agent with a prompt that says:

```
You are implementing a feature. Use the {skill_name} methodology.

Spec: {{SPEC}}

Project Context: {{PROJECT_CONTEXT}}

Implement this spec following {skill_name}. When done, report:
- Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
- What you implemented
- Files changed
- Test results (if applicable)
- Any concerns
```

The skill name tells the subagent which installed skill to follow. The subagent has access to all skills in its session — it loads the skill and follows its methodology."

- [ ] **Step 2: Add harness dispatch path (Codex) to Phase 2**

Add the Codex dispatch path:

"**If harness-based (`codex`, with or without skill):** Do NOT use the Agent tool. Instead, dispatch via the Codex CLI:

1. Create a git worktree for this slot (same as Claude Code slots)
2. Run `codex exec` pointed at the worktree:

```bash
cd {worktree_path}
codex exec "Implement this spec. Write all files to the current directory.

{skill_guidance if skill is specified — e.g., 'Follow TDD: write failing tests first, then implement.'}

Spec: {spec}

Project context: {project_context}

When done, summarize what you built, files changed, and any concerns." \
  -s workspace-write \
  -c 'model_reasoning_effort="high"' \
  --json 2>{RUN_DIR}/slot-{i}-codex-stderr.txt
```

3. Parse the JSONL output to extract the implementer report. Use this Python parser:

```python
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        t = obj.get('type', '')
        if t == 'item.completed' and 'item' in obj:
            item = obj['item']
            if item.get('type') == 'agent_message' and item.get('text'):
                print(item['text'])
            elif item.get('type') == 'command_execution' and item.get('command'):
                print(f'[codex ran] {item[\"command\"]}')
    except:
        pass
```

4. Save the parsed report to `{RUN_DIR}/slot-{i}-report.txt`
5. The worktree now contains Codex's implementation files
6. Check for Codex failures:
   - Non-zero exit code → mark FAILED, save stderr to run dir
   - Empty output → mark FAILED
   - Timeout (5 minutes default) → mark FAILED
   - On failure, save whatever output exists for debugging

**If harness + skill (`/superpowers:tdd + codex`):** Same as harness dispatch, but include the skill guidance in the Codex prompt. The skill guidance line tells Codex what methodology to follow."

- [ ] **Step 3: Update the dispatch table**

Replace the current single-row Agent tool call table with a conditional summary:

| Slot type | Dispatch | Prompt source | Isolation |
|-----------|----------|---------------|-----------|
| `default` | Agent tool | Profile `1-implementer.md` + approach hint | Profile setting |
| Skill only (`/superpowers:tdd`) | Agent tool | Skill guidance + spec (no profile implementer) | worktree |
| Harness only (`codex`) | `codex exec` CLI | Spec + profile context (no profile implementer) | worktree (slot-machine managed) |
| Skill + harness (`/superpowers:tdd + codex`) | `codex exec` CLI | Skill guidance + spec | worktree (slot-machine managed) |

- [ ] **Step 4: Update the progress report table**

Add a "Via" column to the Phase 2 progress table to show which harness ran each slot:

| Slot | Via | Status | Words/Tests | Approach |
|------|-----|--------|-------------|----------|
| 1 | Claude | `DONE` | 13 tests | /superpowers:tdd |
| 2 | Codex | `DONE` | 15 tests | /superpowers:tdd + codex |
| 3 | Claude | `DONE` | 21 tests | /ce:work |
| 4 | Codex | `DONE_WITH_CONCERNS` | 8 tests | codex (default) |

- [ ] **Step 5: Commit**

```bash
git add SKILL.md
git commit -m "feat: skill and harness dispatch in Phase 2 — skill guidance, native codex exec"
```

---

### Task 3: Update tests for slot definitions and harness dispatch

Add contract tests that validate the new SKILL.md content.

**Files:**
- Modify: `tests/test-contracts.sh`

- [ ] **Step 1: Add Contract 11 — Slot Definition Syntax**

```bash
echo "=== Contract 11: Slot Definition Syntax ==="
# SKILL.md must describe slot definitions
assert_contains "$SKILL_CONTENT" "Slot Definitions\|slot definition\|slot-machine-slots" \
    "SKILL.md documents slot definition parsing" || FAILED=$((FAILED + 1))

# Must describe the three slot types
for slot_type in "default" "skill" "harness"; do
    assert_contains "$SKILL_CONTENT" "$slot_type" \
        "SKILL.md describes '$slot_type' slot type" || FAILED=$((FAILED + 1))
done

# Must describe the + composition operator
assert_contains "$SKILL_CONTENT" '+ codex\|+ gemini\|compose\|composition' \
    "SKILL.md describes skill + harness composition" || FAILED=$((FAILED + 1))

# Must describe CLAUDE.md config
assert_contains "$SKILL_CONTENT" "slot-machine-slots" \
    "SKILL.md documents slot-machine-slots config key" || FAILED=$((FAILED + 1))
```

- [ ] **Step 2: Add Contract 12 — Codex Dispatch**

```bash
echo "=== Contract 12: Codex Dispatch ==="
# SKILL.md must describe native codex dispatch
assert_contains "$SKILL_CONTENT" "codex exec" \
    "SKILL.md describes codex exec dispatch" || FAILED=$((FAILED + 1))

assert_contains "$SKILL_CONTENT" "workspace-write" \
    "SKILL.md specifies workspace-write sandbox mode" || FAILED=$((FAILED + 1))

assert_contains "$SKILL_CONTENT" "JSONL\|jsonl\|json.*parse\|parse.*json" \
    "SKILL.md describes JSONL output parsing" || FAILED=$((FAILED + 1))

# Codex failure handling must be documented
assert_contains "$SKILL_CONTENT" "timeout\|non-zero exit\|empty output" \
    "SKILL.md describes codex failure handling" || FAILED=$((FAILED + 1))
```

- [ ] **Step 3: Run tests to verify they fail (RED)**

```bash
./tests/run-tests.sh
```

Expected: Contracts 1-10 pass, Contracts 11-12 fail (SKILL.md doesn't have the new content yet — but actually it does from Tasks 1-2 if those ran first. If running TDD with tests first, these will be RED until Tasks 1-2 are implemented.)

Note: If following the plan sequentially (Tasks 1-2 first), run tests after Task 2 to verify GREEN instead.

- [ ] **Step 4: Commit**

```bash
git add tests/test-contracts.sh
git commit -m "test: add contracts for slot definitions and codex dispatch"
```

---

### Task 4: Add Codex availability check to Phase 1

Before dispatching to Codex, verify the CLI is installed. Fail gracefully if not.

**Files:**
- Modify: `SKILL.md` (Phase 1 section)

- [ ] **Step 1: Add harness availability check to Phase 1**

In Phase 1 Setup, after parsing slot definitions, add:

"**Check harness availability.** For each slot that specifies a harness:
- `codex`: Run `which codex`. If not found, warn: 'Codex CLI not found — slot {i} will fall back to Claude Code. Install: `npm install -g @openai/codex`'. Change the slot's harness to `null` (falls back to Claude Code with the same skill guidance if any).
- Future harnesses: same pattern — check binary, warn and fall back if missing."

- [ ] **Step 2: Commit**

```bash
git add SKILL.md
git commit -m "feat: harness availability check in Phase 1 — graceful fallback if codex missing"
```

---

### Task 5: Update README for new capabilities

Document the new slot definition syntax and cross-harness features in the README.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Usage section**

After the existing usage examples, add a subsection showing skill and harness slots:

```markdown
### Multi-Skill and Cross-Model Runs

Compare different implementation approaches and AI systems on the same spec:

\```
/slot-machine with /superpowers:tdd, /ce:work, and codex

Spec: Implement the payment webhook handler from PLAN.md
\```

Three slots: Claude Code with TDD, Claude Code with CE patterns, and OpenAI Codex. Each implements independently, all reviewed by the same evaluation pipeline.

Compose skills with harnesses using `+`:

\```
/slot-machine with 4 slots:
  slot 1: /superpowers:tdd
  slot 2: /superpowers:tdd + codex
  slot 3: /ce:work
  slot 4: codex
\```

Or set project defaults in `CLAUDE.md`:

\```markdown
## Slot Machine Settings
slot-machine-slots:
  - /superpowers:tdd
  - /ce:work
  - codex
  - default
\```
```

- [ ] **Step 2: Add a "Cross-Model" row to the Without vs With table**

Add to the comparison table:

```
| **Cross-model** | N/A | Claude vs Codex on same spec — different models find different bugs |
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add multi-skill and cross-model usage to README"
```

---

### Task 6: End-to-end live test — skill-per-slot

Run slot-machine with explicit skill slots to verify skill guidance injection works.

**Files:** None created — live execution test.

- [ ] **Step 1: Run slot-machine with 2 skill slots + 1 default**

Use the tiny-spec fixture (token bucket rate limiter) with:
```
/slot-machine with 3 slots:
  slot 1: /superpowers:tdd
  slot 2: /ce:work
  slot 3: default
```

- [ ] **Step 2: Verify Phase 1 — slot definitions parsed**

Check the setup report:
- Does it show slot definitions (not just hints)?
- Does it list `/superpowers:tdd`, `/ce:work`, and `default`?

- [ ] **Step 3: Verify Phase 2 — skill-based slots used different approaches**

Check that:
- Slot 1 (TDD) wrote tests before implementation
- Slot 2 (CE work) did pattern research
- Slot 3 (default) used a profile approach hint
- Progress table shows the "Via" column

- [ ] **Step 4: Verify Phase 3-4 — review and judgment worked normally**

The evaluation pipeline should work identically regardless of how each slot was implemented. Verify reviewers produced structured scorecards, judge made a verdict, and the pipeline completed.

---

### Task 7: End-to-end live test — Codex dispatch

Run slot-machine with a Codex slot to verify native dispatch works.

**Files:** None created — live execution test. **Requires:** Codex CLI installed (`codex` binary available).

- [ ] **Step 1: Verify Codex is available**

```bash
which codex && codex --version
```

If not available, skip this test.

- [ ] **Step 2: Run slot-machine with 1 Claude + 1 Codex slot**

```
/slot-machine with 2 slots:
  slot 1: /superpowers:tdd
  slot 2: codex

Spec: [paste tiny-spec.md content]
```

- [ ] **Step 3: Verify Codex slot executed via CLI**

Check that:
- The orchestrator ran `codex exec` (not the Agent tool) for Slot 2
- Codex wrote files to the worktree
- The JSONL output was parsed into an implementer report
- The progress table shows `Via: Codex` for Slot 2

- [ ] **Step 4: Verify the reviewer compared both slots**

The reviewer should review both the Claude Code output (Slot 1) and the Codex output (Slot 2) using the same reviewer prompt and evaluation criteria. The judge should compare them and make a verdict.

- [ ] **Step 5: Verify cross-harness cost reporting**

The final report should note which harnesses were used:
```
Harnesses: Claude Code (1 slot), Codex (1 slot)
```

- [ ] **Step 6: Commit any fixes found during testing**

```bash
git add -A
git commit -m "fix: address issues found during live skill/codex testing"
```

---

### Task 8: Add skill discovery

Implement the `--discover` / "all my skills" detection and first-time proposal flow.

**Files:**
- Modify: `SKILL.md` (add Skill Discovery section)

- [ ] **Step 1: Add Skill Discovery section to SKILL.md**

After the Slot Definitions section, add `## Skill Discovery` with:

1. **Trigger rules** — only fires on "all my skills", "all implementation skills", or `--discover`. Never as a default, never as a suggestion.

2. **Detection heuristic** — read skill descriptions from the system prompt. Include signals: "implement", "build", "execute plan", "write code". Exclude signals: "review", "deploy", "ship", "audit". Check for external harnesses: `which codex`, `which gemini`. Filter out known poor candidates (SDD, executing-plans).

3. **First-time flow** — propose the detected list, user confirms or edits. Save to `~/.slot-machine/config.md`.

4. **Subsequent runs** — load saved list. Re-scan with `--discover`.

- [ ] **Step 2: Commit**

```bash
git add SKILL.md
git commit -m "feat: skill discovery — detect installed implementation skills on demand"
```

---

### Task 9: Final verification

Run all tests, verify no stale references, confirm structure is complete.

**Files:** None — read-only verification.

- [ ] **Step 1: Run full test suite**

```bash
./tests/run-tests.sh
```

Expected: all contracts pass (including new Contracts 11-12).

- [ ] **Step 2: Verify no stale references**

```bash
grep -rn "slot-implementer-prompt\|slot-reviewer-prompt\|SLOT_TEMP_DIR\|mktemp" SKILL.md
```

Expected: no matches.

- [ ] **Step 3: Verify SKILL.md covers all slot types**

```bash
for term in "default" "skill" "harness" "codex exec" "workspace-write" "slot-machine-slots" "Skill Discovery"; do
    grep -q "$term" SKILL.md && echo "PASS: $term" || echo "FAIL: $term"
done
```

- [ ] **Step 4: Verify README covers new features**

```bash
for term in "Multi-Skill" "Cross-Model" "codex" "/superpowers:tdd" "slot-machine-slots"; do
    grep -q "$term" README.md && echo "PASS: $term" || echo "FAIL: $term"
done
```
