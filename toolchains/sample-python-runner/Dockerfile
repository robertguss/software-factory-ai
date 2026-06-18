# syntax=docker/dockerfile:1

FROM python@sha256:c33f0bc4364a6881bed1ec0cc2665e6c53c87a43e774aaeab88e6f17af105e4f

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /workspace

COPY requirements.lock /opt/conveyor/sample-python-runner/requirements.lock

RUN python -m pip install --upgrade pip \
    && python -m pip install --requirement /opt/conveyor/sample-python-runner/requirements.lock \
    && python - <<'PY'
import fastapi
import pytest
import uvicorn

print(f"fastapi={fastapi.__version__}")
print(f"pytest={pytest.__version__}")
print(f"uvicorn={uvicorn.__version__}")
PY

CMD ["pytest", "-q"]
