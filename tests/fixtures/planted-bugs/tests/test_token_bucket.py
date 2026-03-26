"""Tests for token bucket — these pass despite the bugs in the implementation."""

import time
import pytest
from src.token_bucket import TokenBucket


def test_basic_consume():
    bucket = TokenBucket(10, 1.0)
    assert bucket.consume(1) is True

def test_consume_all():
    bucket = TokenBucket(5, 0)
    for _ in range(5):
        assert bucket.consume(1) is True
    assert bucket.consume(1) is False

def test_tokens_property():
    bucket = TokenBucket(10, 0)
    bucket.consume(3)
    assert bucket.tokens == 7.0

def test_refill():
    bucket = TokenBucket(10, 100)  # Fast refill
    bucket.consume(5)
    time.sleep(0.1)
    assert bucket.tokens > 5.0

def test_capacity_cap():
    bucket = TokenBucket(10, 100)
    time.sleep(0.1)
    assert bucket.tokens <= 10.0

def test_invalid_capacity():
    with pytest.raises(ValueError):
        TokenBucket(0, 1.0)

def test_negative_refill():
    with pytest.raises(ValueError):
        TokenBucket(10, -1)

def test_large_consume():
    bucket = TokenBucket(5, 0)
    assert bucket.consume(10) is False
