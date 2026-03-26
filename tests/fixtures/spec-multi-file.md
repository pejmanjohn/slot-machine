# Task Queue API

Implement a simple in-memory task queue with a REST-like API layer:

**Core module (`src/task_queue.py`):**
- `TaskQueue` class with `submit(task_fn, priority=0) -> task_id`
- `get_status(task_id) -> dict` returning status, result, error
- Tasks execute in priority order (higher priority first)
- Thread-safe for concurrent submit/get_status calls
- Tasks run in a background worker thread

**API layer (`src/api.py`):**
- `create_app() -> Flask/FastAPI app` (choose one)
- POST /tasks — submit a task, return task_id
- GET /tasks/{id} — get task status/result
- GET /tasks — list all tasks with status

**Tests (`tests/`):**
- Unit tests for TaskQueue (submit, priority ordering, concurrent access)
- Integration tests for API endpoints (submit, poll status, list)
- Test that tasks actually execute and results are retrievable

Language: Python. Use pytest.
