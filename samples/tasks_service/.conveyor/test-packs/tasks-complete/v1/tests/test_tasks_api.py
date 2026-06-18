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
    assert response.json() == {
        "id": 1,
        "title": "write baseline tests",
        "completed": False,
    }


def test_create_defaults_completed_false(client: TestClient) -> None:
    response = client.post("/tasks", json={"title": "write acceptance tests"})

    assert response.status_code == 201
    assert response.json() == {
        "id": 1,
        "title": "write acceptance tests",
        "completed": False,
    }


def test_created_tasks_are_listed_in_creation_order(client: TestClient) -> None:
    first = client.post("/tasks", json={"title": "write baseline tests"})
    second = client.post("/tasks", json={"title": "run pytest"})

    response = client.get("/tasks")

    assert first.status_code == 201
    assert second.status_code == 201
    assert response.status_code == 200
    assert response.json() == [
        {"id": 1, "title": "write baseline tests", "completed": False},
        {"id": 2, "title": "run pytest", "completed": False},
    ]


def test_complete_task(client: TestClient) -> None:
    created = client.post("/tasks", json={"title": "ship tracer bullet"})

    response = client.patch("/tasks/1", json={"completed": True})

    assert created.status_code == 201
    assert response.status_code == 200
    assert response.json() == {
        "id": 1,
        "title": "ship tracer bullet",
        "completed": True,
    }


def test_completed_state_visible_in_list(client: TestClient) -> None:
    client.post("/tasks", json={"title": "persist completed state"})
    completed = client.patch("/tasks/1", json={"completed": True})

    response = client.get("/tasks")

    assert completed.status_code == 200
    assert response.status_code == 200
    assert response.json() == [
        {
            "id": 1,
            "title": "persist completed state",
            "completed": True,
        }
    ]


def test_complete_unknown_task_returns_404(client: TestClient) -> None:
    response = client.patch("/tasks/999", json={"completed": True})

    assert response.status_code == 404
    assert response.json() == {"detail": "Task not found"}
