from threading import Lock
from typing import Annotated

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field


class TaskCreate(BaseModel):
    title: Annotated[str, Field(min_length=1)]


class Task(BaseModel):
    id: int
    title: str
    completed: bool = False


class TaskUpdate(BaseModel):
    completed: bool


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

    def complete(self, task_id: int) -> Task:
        with self._lock:
            for index, task in enumerate(self._tasks):
                if task.id == task_id:
                    completed = task.model_copy(update={"completed": True})
                    self._tasks[index] = completed
                    return completed
            raise KeyError(task_id)

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


@app.patch("/tasks/{task_id}", response_model=Task)
def complete_task(task_id: int, payload: TaskUpdate) -> Task:
    if not payload.completed:
        raise HTTPException(status_code=400, detail="Only completing tasks is supported")
    try:
        return store.complete(task_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="Task not found") from None


def reset_store_for_tests() -> None:
    store.reset()
