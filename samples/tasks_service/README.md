# Conveyor sample tasks service

This is the disposable Phase 1 sample app used by Conveyor tracer-bullet work.
It is intentionally independent of Conveyor internals: verification is just
`pytest -q` from this directory.

## Install

```bash
python -m venv .venv
. .venv/bin/activate
pip install -r requirements.lock
```

## Run tests

```bash
pytest -q
```

## Run the API

```bash
uvicorn tasks_service.main:app --reload
```

The baseline API supports:

- `GET /tasks`
- `POST /tasks` with JSON body `{"title": "write tests"}`
