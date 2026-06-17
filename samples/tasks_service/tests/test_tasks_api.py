import pytest
from fastapi.testclient import TestClient

from tasks_service.main import app, reset_store_for_tests


@pytest.fixture(autouse=True)
def reset_store() -> None:
    reset_store_for_tests()


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def test_list_tasks_starts_empty(client: TestClient) -> None:
    response = client.get("/tasks")

    assert response.status_code == 200
    assert response.json() == []


def test_create_task_returns_new_task(client: TestClient) -> None:
    response = client.post("/tasks", json={"title": "write baseline tests"})

    assert response.status_code == 201
    assert response.json() == {"id": 1, "title": "write baseline tests"}


def test_created_tasks_are_listed_in_creation_order(client: TestClient) -> None:
    first = client.post("/tasks", json={"title": "write baseline tests"})
    second = client.post("/tasks", json={"title": "run pytest"})

    response = client.get("/tasks")

    assert first.status_code == 201
    assert second.status_code == 201
    assert response.status_code == 200
    assert response.json() == [
        {"id": 1, "title": "write baseline tests"},
        {"id": 2, "title": "run pytest"},
    ]
