# Token Bucket Rate Limiter

Implement a token bucket rate limiter in Python:
- Configurable capacity and refill rate
- Thread-safe `consume()` method that returns `True`/`False`
- Tracks remaining tokens via a `tokens` property
- Refills tokens based on elapsed time (lazy refill, not a background thread)
- Comprehensive tests covering: normal consumption, exhaustion, refill timing, concurrent access

Create files in `src/` for implementation and `tests/` for tests. Use pytest.
