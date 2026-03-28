# E2E Test 8: Cross-Harness (Claude + Codex)

**Date:** 2026-03-28
**Spec:** fizzbuzz(n)
**Slots:** 2 (Slot 1: Claude + /superpowers:tdd, Slot 2: Codex)

## Results

| Check | Result | Notes |
|-------|--------|-------|
| Codex exec dispatch | PASS | Exit code 0, 4225 bytes of report |
| JSONL parsing | PASS | Extracted agent_message text and command_execution events |
| workspace-write mode | PASS | Codex wrote files directly to worktree |
| Codex followed TDD unprompted | BONUS | Loaded superpowers skills from ~/.codex/ and ran RED/GREEN |
| Mixed-harness parallel dispatch | PASS | Both slots ran concurrently |
| Codex output normalized | PASS | Report saved to slot-2-report.txt, stderr to slot-2-codex-stderr.txt |
| Reviewer compared both fairly | PASS | Same review format for both slots |
| Judge compared cross-harness | PASS | Made evidence-based PICK with harness-aware reasoning |
| result.json includes harness info | PASS | harnesses field shows Claude Code (1) and Codex (1) |
| Via column in progress table | PASS | Slot 1: Claude, Slot 2: Codex |

## Verdict
PICK Slot 1 (Claude) — HIGH confidence. Both implementations identical, Claude had better test coverage (5 vs 4, multiple values per branch).

## Notable Findings

1. **Codex CLI dispatch works end-to-end.** `codex exec -s workspace-write --json` produces parseable JSONL output.
2. **Codex loaded superpowers skills from its own install.** It found `~/.codex/superpowers/skills/` and loaded TDD, brainstorming, and verification skills autonomously.
3. **Codex files are untracked** — same issue as Task 7. The orchestrator needs a post-dispatch commit step for Codex worktrees. (Documented in SKILL.md Path C step 3 is about failure handling, but doesn't explicitly say "commit files" — could be clearer.)
4. **JSONL parsing pipeline worked correctly** — the Python one-liner parsed item.completed events for both agent_message and command_execution types.

## Issues to Fix
- SKILL.md Path C should note that Codex files need to be committed to the worktree branch after dispatch completes (before review).
