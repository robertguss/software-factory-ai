# PROJECT KNOWLEDGE BASE

## OVERVIEW

`samples/` contains external example projects used to exercise Conveyor against
non-core codebases.

## WHERE TO LOOK

| Task                | Location                                                   | Notes                                             |
| ------------------- | ---------------------------------------------------------- | ------------------------------------------------- |
| Python task service | `tasks_service/`                                           | FastAPI-style sample with its own plan and tests. |
| Sample contract     | `tasks_service/conveyor.plan.yml`, `tasks_service/plan.md` | Conveyor-facing work definition.                  |
| Python tests        | `tasks_service/tests/`                                     | `pytest` surface for the sample.                  |
| Python config       | `tasks_service/pyproject.toml`, `requirements*.txt`        | Sample-local tooling.                             |

## CONVENTIONS

- Treat samples as external repos under test, not as Conveyor app code.
- Keep sample dependencies and commands local to the sample directory.
- Preserve sample plans because Conveyor tests may rely on their exact shape.
- Run sample verification from the sample root unless a Conveyor test says
  otherwise.
- Ignore `.venv/` and `.pytest_cache/`; they are runtime artifacts, not source.

## ANTI-PATTERNS

- Do not apply Elixir/Phoenix conventions to sample Python code.
- Do not update sample expected behavior without checking Conveyor tests that
  reference it.
- Do not commit environment-specific cache or virtualenv contents.
