from threading import Lock
from typing import Annotated

from fastapi import FastAPI
from pydantic import BaseModel, Field


class TaskCreate(BaseModel):
    title: Annotated[str, Field(min_length=1)]


class Task(BaseModel):
    id: int
    title: str


class TaskStore:
    def __init__(self) -> None:
        self._lock = Lock()
        self._next_id = 1
        self._tasks: list[Task] = []

    def create(self, title: str) -> Task:
        with self._lock:
            task = Task(id=self._next_id, title=title)
            self._next_id += 1
            self._tasks.append(task)
            return task

    def list(self) -> list[Task]:
        with self._lock:
            return list(self._tasks)

    def reset(self) -> None:
        with self._lock:
            self._next_id = 1
            self._tasks = []


store = TaskStore()
app = FastAPI(title="Conveyor sample tasks API")


@app.get("/tasks", response_model=list[Task])
def list_tasks() -> list[Task]:
    return store.list()


@app.post("/tasks", response_model=Task, status_code=201)
def create_task(payload: TaskCreate) -> Task:
    return store.create(payload.title)


def reset_store_for_tests() -> None:
    store.reset()
