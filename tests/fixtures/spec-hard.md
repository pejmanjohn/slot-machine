# Lock-Free Concurrent Counter with Snapshots

Implement a high-performance concurrent counter system WITHOUT using locks:

- `Counter(name: str)` — named counter
- `increment(amount: int = 1)` — atomic increment without locks (use CAS/compare-and-swap)
- `decrement(amount: int = 1)` — atomic decrement without locks
- `value` property — returns current count (eventually consistent is acceptable)
- `CounterGroup()` — manages multiple named counters
- `CounterGroup.snapshot() -> dict[str, int]` — returns consistent point-in-time snapshot of ALL counters (this is the hard part — snapshot must be linearizable)
- Comprehensive tests proving:
  - Single-counter correctness under 100+ concurrent threads
  - Snapshot linearizability: no snapshot should show a state that never existed
  - Performance: lock-free counter must be faster than a locked counter under contention

Language: Python. Use pytest. No external dependencies beyond stdlib.
