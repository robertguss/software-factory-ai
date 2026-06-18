# Project Goal

Extend the sample tasks API so tasks can be marked complete.

# Non-goals

- Authentication.
- Pagination.
- Un-completing a task.
- Bulk updates.
- Deployment or production hardening.

# Requirement REQ-001

Newly created tasks expose `completed: false` by default.

# Requirement REQ-002

A client can mark an existing task complete through `PATCH /tasks/{id}`.

# Requirement REQ-003

Completed state is returned by `GET /tasks` after a task is marked complete.

# Requirement REQ-004

Patching an unknown task id returns 404.

# Test Strategy

Human-authored pytest cases cover REQ-001 through REQ-004 before implementation
starts. The existing create/list tests remain regression coverage and must keep
passing.

# Verification Commands

```bash
pytest -q
```

# Implementation Slice

One low-risk L1 slice updates the in-memory task model, create/list responses,
and the new complete endpoint in `tasks_service/main.py`, with matching pytest
coverage in `tests/test_tasks_api.py`.
