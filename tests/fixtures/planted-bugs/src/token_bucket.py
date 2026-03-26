"""Token bucket rate limiter — contains intentional bugs for reviewer testing."""

import threading
import time


class TokenBucket:
    """A token bucket rate limiter.

    Note: this implementation has intentional bugs for testing
    the slot-machine reviewer's ability to find real issues.
    """

    def __init__(self, capacity: float, refill_rate: float):
        if capacity <= 0:
            raise ValueError("capacity must be positive")
        if refill_rate < 0:
            raise ValueError("refill_rate must be non-negative")
        self.capacity = capacity
        self.refill_rate = refill_rate
        self._tokens = capacity
        # BUG-2: Uses time.time() instead of time.monotonic()
        # If system clock adjusts, refill breaks
        self._last_refill = time.time()
        self._lock = threading.Lock()

    def _refill(self):
        """Add tokens based on elapsed time."""
        now = time.time()  # BUG-2: should be time.monotonic()
        elapsed = now - self._last_refill
        if elapsed > 0:
            self._tokens = min(
                self.capacity,
                self._tokens + elapsed * self.refill_rate
            )
            self._last_refill = now

    @property
    def tokens(self) -> float:
        with self._lock:
            self._refill()
            return self._tokens

    def consume(self, amount: float = 1.0) -> bool:
        """Try to consume tokens. Returns True if successful."""
        # BUG-1: TOCTOU race — checks under lock, but the lock
        # scope doesn't cover the full check-and-deduct atomically
        # in a way that's buggy: _refill releases implicitly by
        # being called before the lock in some paths
        with self._lock:
            self._refill()
            available = self._tokens

        # BUG-1: This section is OUTSIDE the lock!
        # Another thread can modify self._tokens between the check and deduct
        if available >= amount:
            with self._lock:
                self._tokens -= amount
            return True
        return False
