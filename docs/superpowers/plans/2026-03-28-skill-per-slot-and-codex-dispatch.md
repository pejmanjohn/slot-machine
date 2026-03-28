# Skill-Per-Slot and Native Codex Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make slot-machine dispatch pluggable — users can assign different skills (`/superpowers:tdd`, `/ce:work`) and harnesses (`codex`) to individual slots, composable with `+` syntax.

**Architecture:** Two new concepts added to SKILL.md's orchestration: (1) slot definitions that override the profile's implementer prompt with skill guidance or harness dispatch, and (2) a native Codex dispatch path via `codex exec` CLI. The evaluation pipeline (review, judge, synthesis) is unchanged — only the implementation step becomes pluggable.

**Tech Stack:** Markdown (SKILL.md orchestration instructions), bash test scripts. Codex dispatch via `codex exec` CLI with JSONL output parsing.

**Design doc:** `docs/plans/2026-03-28-slot-machine-as-infrastructure.md`

**Key design decisions (resolved during planning):**

- **Skill-based slots do NOT get approach hints.** The skill IS the diversity mechanism. Only `default` slots get hints.
- **Bare `codex` slots (no skill) get a generic implementation prompt** — not the profile's implementer prompt (which is Claude-Code-specific in tone). The prompt includes the spec + project context + a "implement this and report what you built" instruction.
- **Mixed-harness parallel dispatch:** Claude Code slots dispatch in parallel via Agent tool (one message). Codex slots dispatch in parallel via background Bash commands. Both groups can run concurrently. Collect all results after both groups complete.
- **Skill-based slots must explicitly invoke the skill**, not just "follow the methodology." The prompt tells the subagent to use the Skill tool.

---

### Task 1: Write tests for slot definitions and harness dispatch (TDD RED)

Write the contract tests first. They describe the desired SKILL.md content and should FAIL against the current SKILL.md.

**Files:**
- Modify: `tests/test-contracts.sh`

- [ ] **Step 1: Add Contract 11 — Slot Definition Syntax**

Add before the "Contract Tests Complete" line:

```bash
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
```

- [ ] **Step 2: Add Contract 12 — Codex Dispatch**

```bash
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
```

- [ ] **Step 3: Add Contract 13 — Skill Discovery**

```bash
echo ""
echo "=== Contract 13: Skill Discovery ==="
assert_contains "$SKILL_CONTENT" "Skill Discovery\|skill discovery" \
    "SKILL.md has Skill Discovery section" || FAILED=$((FAILED + 1))

assert_contains "$SKILL_CONTENT" "\-\-discover" \
    "SKILL.md documents --discover flag" || FAILED=$((FAILED + 1))

assert_contains "$SKILL_CONTENT" "all my skills\|all implementation skills" \
    "SKILL.md documents natural language discovery triggers" || FAILED=$((FAILED + 1))
```

- [ ] **Step 4: Run tests — verify RED**

```bash
./tests/run-tests.sh
```

Expected: Contracts 1-10 pass, Contracts 11-13 fail. Count the failures.

- [ ] **Step 5: Commit**

```bash
git add tests/test-contracts.sh
git commit -m "test: add contracts for slot definitions, codex dispatch, and skill discovery (RED)"
```

---

### Task 2: Add slot definition parsing to SKILL.md Phase 1

Add the ability for the orchestrator to parse slot definitions from the user's invocation or CLAUDE.md config.

**Files:**
- Modify: `SKILL.md`

- [ ] **Step 1: Add "Slot Definitions" section after Profile Loading**

After the `## Profile Loading` section and before `## The Process`, add:

```markdown
## Slot Definitions

Slots can be configured per-slot instead of using the same profile implementer for all. Two axes compose with `+`:

- **Skills** (`/superpowers:tdd`, `/ce:work`) — methodology guidance, slash-prefixed. Injected into the prompt of whatever harness runs the slot.
- **Harnesses** (`codex`, `gemini`) — which AI system executes. No slash prefix. Determines the dispatch mechanism.

### Slot Definition Sources (precedence)

1. **Inline:** Parsed from the user's command. Slash-prefixed names are skills, bare names are harnesses. `+` composes them. `default` means profile implementer + approach hint.
2. **CLAUDE.md config:** Read `slot-machine-slots` list if present:
   ```markdown
   slot-machine-slots:
     - /superpowers:tdd
     - /ce:work
     - codex
     - /superpowers:tdd + codex
     - default
   ```
3. **Profile defaults:** If no slot definitions found, all slots use the profile's implementer prompt with randomly assigned approach hints. This is the Phase 1 behavior — unchanged.

### Parsing Rules

- If the user specifies slot definitions AND a slot count higher than the number of definitions, remaining slots get profile defaults with approach hints
- If the user specifies only slot definitions (no count), the slot count equals the number of definitions
- Each slot definition is a tuple: `(skill, harness)`:
  - `default` → `(null, null)` — profile implementer + hint
  - `/superpowers:tdd` → `("/superpowers:tdd", null)` — Claude Code with skill
  - `codex` → `(null, "codex")` — Codex with generic prompt
  - `/superpowers:tdd + codex` → `("/superpowers:tdd", "codex")` — Codex with skill

### Approach Hints and Skill Slots

Approach hints only apply to `default` slots. Skill-based slots do NOT get approach hints — the skill IS the diversity mechanism. When mixing skill and default slots, assign hints only to the default slots.

### Poor Slot Candidate Warning

If a parsed skill name matches a known multi-agent orchestrator (`/superpowers:subagent-driven-development`, `/superpowers:executing-plans`), warn the user: "⚠ {skill} is a multi-agent orchestrator — running it inside a slot creates nested pipelines (slower, redundant review). Consider using a single-session skill like /superpowers:tdd instead." Do not block — the user may have a reason.
```

- [ ] **Step 2: Update Phase 1 to parse slot definitions**

In Phase 1 Setup, after step 0 (Load profile), add a new step:

"**1. Parse slot definitions.** Check for slot definitions in precedence order: (1) inline in the user's command, (2) `slot-machine-slots` in CLAUDE.md, (3) fall back to profile defaults. Record the slot list — each slot is `(skill, harness)` or `default`. Check harness availability (see below)."

Renumber subsequent steps (current 1 becomes 2, etc.).

- [ ] **Step 3: Add harness availability check**

Add to the same new step:

"**Check harness availability.** For each slot that specifies a harness:
- `codex`: Run `which codex` via Bash. If not found, warn: 'Codex CLI not found — slot {i} will fall back to Claude Code. Install: `npm install -g @openai/codex`'. Change the slot's harness to `null` (falls back to Claude Code with the same skill guidance if any).
- Future harnesses: same pattern — check binary, warn and fall back if missing."

- [ ] **Step 4: Update setup report**

Change the setup report template. When slots have definitions:

```
Slots: `{N}` | /superpowers:tdd, /ce:work, codex, 2x default hints
```

When all defaults (current behavior):

```
Slots: `{N}` | Hints: {hint_1}, {hint_2}, ...
```

- [ ] **Step 5: Run tests — check Contract 11 progress**

```bash
./tests/run-tests.sh 2>&1 | grep "Contract 11"
```

Some Contract 11 assertions should now pass.

- [ ] **Step 6: Commit**

```bash
git add SKILL.md
git commit -m "feat: add slot definition parsing — skills, harnesses, composition, discovery"
```

---

### Task 3: Update Phase 2 dispatch for skill and harness slots

Make the implementer dispatch conditional — skill-based slots get explicit skill invocation, harness-based slots use `codex exec`.

**Files:**
- Modify: `SKILL.md` (Phase 2 section)

- [ ] **Step 1: Add conditional dispatch logic to Phase 2**

Replace the current single dispatch path with conditional logic. Before the Agent tool call table, add:

"**Dispatch depends on the slot definition.** For each slot, determine the dispatch path:

**Group 1 — Claude Code slots (Agent tool):** All slots where `harness` is `null` (default slots and skill-only slots). Dispatch all Group 1 slots in a SINGLE message using parallel Agent tool calls.

**Group 2 — Codex slots (CLI):** All slots where `harness` is `codex`. Dispatch all Group 2 slots in parallel using background Bash commands (one per slot, using Bash tool with `run_in_background: true` and `timeout: 300000`).

Both groups can run concurrently — dispatch Group 1 and Group 2 in the same message if possible, or Group 1 first then Group 2 immediately after. Collect all results after both groups complete."

- [ ] **Step 2: Add the three dispatch paths**

After the grouping logic, add the three paths:

"**Path A — Default slots (no skill, no harness):**

Unchanged from Phase 1. Read `1-implementer.md` from the active profile, fill universal `{{VARIABLES}}`, include the assigned approach hint. Dispatch via Agent tool with `isolation: "worktree"` (or omit if `file` profile).

**Path B — Skill-only slots (e.g., `/superpowers:tdd`, no harness):**

Do NOT read the profile's `1-implementer.md`. Dispatch via Agent tool with this prompt:

```
You are implementing a feature in an isolated workspace.

IMPORTANT: You MUST invoke the {skill_name} skill using the Skill tool before beginning implementation. Follow its workflow exactly.

Specification:
{spec}

Project Context:
{project_context}

After implementation is complete, end with this report format:
**Status:** [DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT]
**What I implemented:** [bullet list]
**Files changed:** [list]
**Test results:** [if applicable]
**Concerns (if any):** [issues]
```

Use `isolation: "worktree"` on the Agent call. Do NOT include an approach hint — the skill is the diversity mechanism.

**Path C — Codex slots (harness = `codex`, with or without skill):**

Do NOT use the Agent tool. Dispatch via Bash:

1. Create a git worktree for this slot (same as Claude Code slots):
   ```bash
   git worktree add "../slot-machine-{feature}-slot-{i}" -b "slot-machine/{feature}/slot-{i}"
   ```

2. Run `codex exec` pointed at the worktree. Use the Bash tool with `timeout: 300000` (5 minutes) and `run_in_background: true`:

   ```bash
   cd {worktree_path} && codex exec "Implement this specification. Write all files to the current directory.

   {If skill specified: 'METHODOLOGY: Follow {skill_name} principles — e.g., for TDD: write failing tests first, verify they fail, then implement minimal code to pass, verify all tests pass.'}

   Specification:
   {spec}

   Project context:
   {project_context}

   When done, provide a summary of:
   - What you implemented (bullet list)
   - Files created or modified
   - Test results if you wrote tests
   - Any concerns or issues encountered" \
     -s workspace-write \
     -c 'model_reasoning_effort="high"' \
     --json 2>{RUN_DIR}/slot-{i}-codex-stderr.txt | python3 -c "
   import sys, json
   for line in sys.stdin:
       line = line.strip()
       if not line: continue
       try:
           obj = json.loads(line)
           t = obj.get('type', '')
           if t == 'item.completed' and 'item' in obj:
               item = obj['item']
               if item.get('type') == 'agent_message' and item.get('text'):
                   print(item['text'])
               elif item.get('type') == 'command_execution':
                   cmd = item.get('command', '')
                   if cmd: print(f'[codex ran] {cmd}')
       except: pass
   " > {RUN_DIR}/slot-{i}-report.txt
   ```

3. After `codex exec` completes, check for failures:
   - Non-zero exit code → mark FAILED, save stderr for debugging
   - Empty report file (`{RUN_DIR}/slot-{i}-report.txt` is 0 bytes) → mark FAILED
   - Timeout (Bash tool returns timeout) → mark FAILED
   - On any failure, save whatever output exists to the run dir. The slot is marked FAILED but the run continues."

- [ ] **Step 3: Update the dispatch summary table**

Replace the current single-row Agent tool call table:

| Slot definition | Dispatch | Prompt | Isolation | Hint? |
|----------------|----------|--------|-----------|-------|
| `default` | Agent tool (parallel Group 1) | Profile `1-implementer.md` + hint | Profile setting | Yes |
| `/superpowers:tdd` | Agent tool (parallel Group 1) | "Invoke {skill} via Skill tool" + spec | worktree | No |
| `codex` | `codex exec` CLI (parallel Group 2) | Generic "implement this" + spec | worktree (manual) | No |
| `/superpowers:tdd + codex` | `codex exec` CLI (parallel Group 2) | Skill methodology + spec | worktree (manual) | No |

- [ ] **Step 4: Update the progress report table**

Add a "Via" column:

| Slot | Via | Status | Words/Tests | Approach |
|------|-----|--------|-------------|----------|
| 1 | `Claude` | `DONE` | 13 tests | /superpowers:tdd |
| 2 | `Codex` | `DONE` | 15 tests | /superpowers:tdd + codex |
| 3 | `Claude` | `DONE` | 21 tests | /ce:work |
| 4 | `Codex` | `DONE_WITH_CONCERNS` | 8 tests | codex |

- [ ] **Step 5: Run tests — check Contracts 11-12**

```bash
./tests/run-tests.sh 2>&1 | grep -E "Contract (11|12)"
```

- [ ] **Step 6: Commit**

```bash
git add SKILL.md
git commit -m "feat: conditional dispatch in Phase 2 — skill invocation, native codex exec, parallel groups"
```

---

### Task 4: Add Skill Discovery to SKILL.md

Implement the `--discover` / "all my skills" detection and first-time proposal flow.

**Files:**
- Modify: `SKILL.md`

- [ ] **Step 1: Add Skill Discovery section**

After the Slot Definitions section, add `## Skill Discovery`:

```markdown
## Skill Discovery

When the user says "all my skills", "all implementation skills", or uses `--discover`, the orchestrator scans for available slot-compatible skills and proposes a slot configuration.

### Trigger Rules (strict — never auto-fires)

| User says | Discovery fires? |
|-----------|-----------------|
| `/slot-machine this` | No — default profile + hints |
| `/slot-machine this with 3 slots` | No — default hints |
| `/slot-machine this with /superpowers:tdd and codex` | No — explicit list |
| `/slot-machine this with all my skills` | **Yes** |
| `/slot-machine this using all implementation skills` | **Yes** |
| `/slot-machine --discover` | **Yes** |

Discovery ONLY fires on explicit "all my/implementation skills" language or `--discover`. Never as a suggestion. Never as a default.

### Detection Heuristic

1. Read skill descriptions from the system prompt
2. Filter by signals:
   - **Include:** "implement", "build", "execute plan", "write code", "development workflow"
   - **Exclude:** "review", "deploy", "ship", "test-only", "audit", "monitor", "debug"
3. Filter out known poor candidates: `/superpowers:subagent-driven-development`, `/superpowers:executing-plans`
4. Check for external harnesses: run `which codex`, `which gemini` via Bash
5. Propose the filtered list to the user

### First-Time Flow

```
I scanned your installed skills and detected these slot-compatible workflows:

  1. /superpowers:tdd — test-first development
  2. /ce:work — pattern-matching execution
  3. codex — OpenAI Codex (external harness)

Use all 3 as slots? Or adjust?
```

User confirms or edits. Save selection to `~/.slot-machine/config.md`:

```markdown
## Discovered Implementation Skills
- /superpowers:tdd
- /ce:work
- codex
```

### Subsequent Runs

"All my skills" loads the saved list without re-scanning. User can re-trigger a fresh scan with `--discover`.
```

- [ ] **Step 2: Run tests — verify Contract 13 passes**

```bash
./tests/run-tests.sh 2>&1 | grep "Contract 13"
```

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat: skill discovery — detect installed implementation skills on demand"
```

---

### Task 5: Run all tests — verify GREEN

All contracts should now pass.

**Files:** None — verification only.

- [ ] **Step 1: Run full test suite**

```bash
./tests/run-tests.sh
```

Expected: ALL contracts (1-13) pass, 0 failures.

- [ ] **Step 2: If any failures, fix and re-run**

Iterate until all green. Commit fixes individually.

---

### Task 6: Update README for new capabilities

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add "Multi-Skill and Cross-Model Runs" subsection after Usage**

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

- [ ] **Step 2: Add "Cross-model" row to the Without vs With table**

```
| **Cross-model** | N/A | Claude vs Codex on same spec — different models find different bugs |
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add multi-skill and cross-model usage to README"
```

---

### Task 7: End-to-end live test — skill-per-slot (Claude Code only)

Run slot-machine with explicit skill slots to verify skill guidance injection works. This test uses only Claude Code slots — no Codex.

**Files:** None created — live execution test.
**Time:** ~10-15 minutes for a 3-slot run with review and judgment.

- [ ] **Step 1: Create a test project with a small spec**

```bash
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
git init && mkdir -p src tests
echo '# Test Project' > README.md
git add -A && git commit -m "initial"
echo "Test dir: $TEST_DIR"
```

- [ ] **Step 2: Run slot-machine with 3 skill/default slots**

From the test directory, invoke slot-machine:

```
/slot-machine with 3 slots:
  slot 1: /superpowers:tdd
  slot 2: /ce:work
  slot 3: default

Spec: Implement a function called `is_palindrome(s)` in src/palindrome.py
that checks if a string is a palindrome (case-insensitive, ignoring spaces
and punctuation). Include tests in tests/test_palindrome.py using pytest.
```

- [ ] **Step 3: Verify Phase 1 — slot definitions parsed correctly**

Check the setup report output:
- Does it show `/superpowers:tdd`, `/ce:work`, and `default`?
- Does it show a hint only for the default slot (slot 3)?
- Does it NOT show hints for slots 1 and 2?

- [ ] **Step 4: Verify Phase 2 — each slot used different approaches**

Check the progress table:
- Does slot 1 (TDD) show `Via: Claude`?
- Does slot 2 (CE work) show `Via: Claude`?
- Does slot 3 (default) show `Via: Claude` with a hint name?
- Did slot 1 actually write tests first (check the implementer report or slot diff)?
- Did slot 2 do pattern research (check the implementer report)?
- Did slot 3 follow the profile's implementer prompt?

- [ ] **Step 5: Verify Phase 3-4 — evaluation pipeline unchanged**

- Did reviewers produce structured scorecards for all 3 slots?
- Did the judge compare all 3 and make a verdict?
- If SYNTHESIZE: did the synthesizer execute the plan?
- Did the run produce `result.json` in the run dir?

- [ ] **Step 6: Verify run artifacts**

```bash
ls -la .slot-machine/runs/latest/
cat .slot-machine/runs/latest/result.json
```

Expected: `slot-{1,2,3}` artifacts, `review-{1,2,3}.md`, `verdict.md`, `output.md` (or output files), `result.json`.

- [ ] **Step 7: Clean up test directory**

```bash
rm -rf "$TEST_DIR"
```

- [ ] **Step 8: Commit any fixes found**

```bash
git add -A && git commit -m "fix: address issues from skill-per-slot live test"
```

---

### Task 8: End-to-end live test — Codex dispatch (cross-harness)

Run slot-machine with a Codex slot alongside a Claude Code slot. This is the wow feature test.

**Files:** None created — live execution test.
**Requires:** Codex CLI installed (`which codex` succeeds).
**Time:** ~10-15 minutes. Codex slots may take longer than Claude Code slots.

- [ ] **Step 1: Verify Codex is available**

```bash
which codex && codex --version
```

If not available, document why and skip to Task 9.

- [ ] **Step 2: Create a test project**

```bash
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
git init && mkdir -p src tests
echo '# Test Project' > README.md
git add -A && git commit -m "initial"
```

- [ ] **Step 3: Run slot-machine with 1 Claude + 1 Codex slot**

```
/slot-machine with 2 slots:
  slot 1: /superpowers:tdd
  slot 2: codex

Spec: Implement a function called `fizzbuzz(n)` in src/fizzbuzz.py that
returns "Fizz" for multiples of 3, "Buzz" for multiples of 5, "FizzBuzz"
for multiples of both, and the number as a string otherwise. Include tests
in tests/test_fizzbuzz.py using pytest.
```

- [ ] **Step 4: Verify Phase 2 dispatch was mixed-harness**

Check that:
- Slot 1 was dispatched via Agent tool (Claude Code)
- Slot 2 was dispatched via `codex exec` CLI (check for Bash tool calls with `codex exec`)
- Both slots produced implementation files in their worktrees
- The progress table shows `Via: Claude` for slot 1 and `Via: Codex` for slot 2

- [ ] **Step 5: Verify Codex output was normalized**

Check that:
- The Codex slot produced files in its worktree (not just text output)
- An implementer report was extracted from the JSONL output
- The report is saved to `{RUN_DIR}/slot-2-report.txt`
- Codex stderr is saved to `{RUN_DIR}/slot-2-codex-stderr.txt`

- [ ] **Step 6: Verify the reviewer compared both fairly**

- Did the reviewer review slot 1 (Claude) and slot 2 (Codex) using the same reviewer prompt?
- Are both scorecards in the same format?
- Did the reviewer cite file:line evidence from both worktrees?

- [ ] **Step 7: Verify the judge compared cross-harness outputs**

- Did the judge receive both scorecards?
- Did the judge make a verdict (PICK or SYNTHESIZE)?
- Does the verdict reference specific strengths/weaknesses from each harness?

- [ ] **Step 8: Verify result.json includes harness info**

```bash
cat .slot-machine/runs/latest/result.json
```

Check that the result includes which harness ran each slot.

- [ ] **Step 9: Verify final report shows harness breakdown**

The final report footer should indicate:
```
Harnesses: Claude Code (1 slot), Codex (1 slot)
```

- [ ] **Step 10: Clean up and commit**

```bash
rm -rf "$TEST_DIR"
git add -A && git commit -m "fix: address issues from cross-harness live test"
```

---

### Task 9: End-to-end live test — Codex fallback when not installed

Verify graceful degradation when a user requests Codex but it's not available.

**Files:** None — behavioral verification.

- [ ] **Step 1: Simulate missing Codex**

Temporarily rename the codex binary (or test on a machine without it):

```bash
CODEX_PATH=$(which codex 2>/dev/null)
if [ -n "$CODEX_PATH" ]; then
    sudo mv "$CODEX_PATH" "${CODEX_PATH}.bak"
    echo "Codex temporarily hidden"
fi
```

(Or skip this task if you can't modify the binary path — document the expected behavior instead.)

- [ ] **Step 2: Run slot-machine requesting Codex**

```
/slot-machine with 2 slots:
  slot 1: /superpowers:tdd
  slot 2: codex

Spec: [any small spec]
```

- [ ] **Step 3: Verify graceful fallback**

Check that:
- The orchestrator warned: "Codex CLI not found — slot 2 will fall back to Claude Code"
- Slot 2 ran via Claude Code (Agent tool) instead of codex exec
- The skill guidance (if any) was preserved in the fallback
- The run completed successfully with 2 Claude Code slots

- [ ] **Step 4: Restore Codex**

```bash
if [ -n "$CODEX_PATH" ]; then
    sudo mv "${CODEX_PATH}.bak" "$CODEX_PATH"
    echo "Codex restored"
fi
```

---

### Task 10: End-to-end live test — CLAUDE.md config-driven slots

Verify that `slot-machine-slots` in CLAUDE.md works without inline slot definitions.

**Files:** None — behavioral verification.

- [ ] **Step 1: Create a test project with slot config in CLAUDE.md**

```bash
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
git init && mkdir -p src tests

cat > CLAUDE.md << 'EOF'
# Test Project

## Slot Machine Settings
slot-machine-profile: coding
slot-machine-slots:
  - /superpowers:tdd
  - default
EOF

git add -A && git commit -m "initial"
```

- [ ] **Step 2: Run slot-machine WITHOUT inline slot definitions**

```
/slot-machine this

Spec: Implement a function called `factorial(n)` in src/math_utils.py
that returns n! for non-negative integers. Raise ValueError for negative input.
Include tests in tests/test_math_utils.py using pytest.
```

- [ ] **Step 3: Verify CLAUDE.md config was loaded**

Check that:
- The setup report shows 2 slots: `/superpowers:tdd` and `default`
- Slot 1 used TDD (invoked the skill)
- Slot 2 used the profile's implementer prompt with an approach hint
- The user was NOT asked to specify slots — config was auto-loaded

- [ ] **Step 4: Clean up**

```bash
rm -rf "$TEST_DIR"
```

---

### Task 11: End-to-end live test — skill + harness composition

Verify that `/superpowers:tdd + codex` actually causes Codex to follow TDD methodology.

**Files:** None — behavioral verification.
**Requires:** Codex CLI installed.

- [ ] **Step 1: Run slot-machine with composed slot**

```
/slot-machine with 2 slots:
  slot 1: /superpowers:tdd
  slot 2: /superpowers:tdd + codex

Spec: Implement a `Stack` class in src/stack.py with push, pop, peek,
and is_empty methods. Pop and peek on empty stack should raise IndexError.
Include tests in tests/test_stack.py using pytest.
```

- [ ] **Step 2: Verify both slots followed TDD**

Check that:
- Slot 1 (Claude + TDD): invoked the TDD skill, wrote tests first
- Slot 2 (Codex + TDD): the codex exec prompt included TDD methodology guidance, and Codex's output shows test-first behavior (tests written before or alongside implementation)

- [ ] **Step 3: Verify the judge compared across harnesses**

- Did the judge see different implementations from different models?
- Were both valid implementations of the Stack spec?
- Did the verdict reflect genuine differences (not just "both are the same")?

- [ ] **Step 4: Compare the two implementations qualitatively**

Read both slot outputs from the run dir. Are they genuinely different? Different variable names, different error handling approaches, different test strategies? This is the value proposition of cross-harness — different models produce genuinely different code.

---

### Task 12: Final verification

**Files:** None — read-only checks.

- [ ] **Step 1: Run full test suite**

```bash
./tests/run-tests.sh
```

Expected: all contracts (1-13) pass.

- [ ] **Step 2: Verify no stale references**

```bash
grep -rn "SLOT_TEMP_DIR\|mktemp" SKILL.md && echo "STALE FOUND" || echo "Clean"
```

- [ ] **Step 3: Verify SKILL.md covers all slot types**

```bash
for term in "## Slot Definitions" "slot-machine-slots" "codex exec" "workspace-write" "## Skill Discovery" "which codex" "+ codex" "Group 1" "Group 2"; do
    grep -q "$term" SKILL.md && echo "PASS: $term" || echo "FAIL: $term"
done
```

- [ ] **Step 4: Verify README covers new features**

```bash
for term in "Multi-Skill" "Cross-Model" "codex" "/superpowers:tdd" "slot-machine-slots"; do
    grep -q "$term" README.md && echo "PASS: $term" || echo "FAIL: $term"
done
```

- [ ] **Step 5: Run git log to verify commit history is clean**

```bash
git log --oneline | head -15
```
