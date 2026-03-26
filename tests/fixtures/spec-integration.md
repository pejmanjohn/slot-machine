# Add Caching to UserService

The following UserService exists (DO NOT modify it, only add to it):

```python
# src/user_service.py (EXISTING — do not modify)
class UserService:
    def __init__(self, db):
        self.db = db

    def get_user(self, user_id: str) -> dict:
        return self.db.query("SELECT * FROM users WHERE id = ?", user_id)

    def list_users(self, limit: int = 100) -> list[dict]:
        return self.db.query("SELECT * FROM users LIMIT ?", limit)
```

**Your task:** Create a `CachedUserService` that wraps `UserService` with caching:

- `CachedUserService(user_service, ttl_seconds=60)` — wraps an existing UserService
- `get_user(user_id)` — returns cached result if available and not expired, otherwise calls underlying service
- `list_users(limit)` — always calls underlying service (not cached)
- `invalidate(user_id=None)` — clear cache for one user or all users
- Thread-safe cache access
- Comprehensive tests using a mock db (the real db isn't available)

Create `src/cached_user_service.py` and `tests/test_cached_user_service.py`.
Language: Python. Use pytest.
