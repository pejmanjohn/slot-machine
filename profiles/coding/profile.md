---
name: coding
description: For implementing well-specified features in a codebase. Use when the spec describes code to write — functions, modules, APIs, services.
extends: null
isolation: worktree
pre_checks: |
  {test_command} 2>&1
  git diff --name-only HEAD~1 2>/dev/null || true
  find . -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.rb" -o -name "*.go" -o -name "*.rs" | head -50 | xargs wc -l 2>/dev/null || true
---

## Approach Hints

When `approach_hints` is enabled (default: true), each slot gets a different architectural direction to encourage genuinely divergent implementations. Assign randomly without replacement.

The goal is structural diversity — different designs, not different priorities on the same design. Each hint steers toward a distinct architecture so the judge sees real alternatives.

**Default hints (for N ≤ 5):**

1. "Use the simplest possible approach — single class, minimal API surface, fewest lines of code that fully satisfy the spec. When in doubt, do less."
2. "Design for robustness — thorough input validation, defensive error handling, edge case coverage. Think about what happens with invalid inputs, concurrent access, and resource exhaustion."
3. "Explore a functional or data-oriented approach — use dataclasses, named tuples, or plain functions instead of classes where possible. Prefer immutability and composition over inheritance."
4. "Design around a fluent or context-manager API — make the interface Pythonic with `with` statements, chaining, or protocol support (`__enter__`, `__iter__`, etc). The API ergonomics matter as much as the internals."
5. "Build for extensibility — use protocols/ABCs, dependency injection, or the strategy pattern. Make it easy to swap implementations or add new behavior without modifying existing code."

**Extended hints (for N > 5):**

6. "Async-first design — use asyncio primitives (Event, Lock, Semaphore) as the core, with a sync wrapper for backwards compatibility."
7. "Decorator pattern — expose the core functionality as a decorator or function wrapper so users can apply it with `@rate_limit` syntax."
8. "Observable and debuggable — add structured logging, metrics hooks, and clear error messages. Optimize for production debugging, not just correctness."
9. "Follow existing codebase patterns exactly — match the project's style, naming conventions, and architectural patterns precisely. Integrate, don't innovate."
10. "Security-hardened — defense in depth, input sanitization, least privilege. Design as if the caller is untrusted."

Each hint is a nudge, not a mandate. Every implementation must still fully satisfy the spec regardless of its hint.
