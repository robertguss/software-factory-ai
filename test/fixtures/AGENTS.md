# PROJECT KNOWLEDGE BASE

## OVERVIEW

`test/fixtures/` contains reusable corpora, snapshots, policy samples, and
expected artifacts for Conveyor tests.

## WHERE TO LOOK

| Task | Location | Notes |
| --- | --- | --- |
| AGENTS linter cases | `agents_md_linter/` | Positive/negative instruction fixtures. |
| Evaluation suites | `eval_suites/` | Inputs for quality and gate evaluations. |
| Plan audit data | `plan_audit/` | Snapshots and audit scenarios. |
| Policy examples | `policy_eval/` | Policy decision and enforcement samples. |
| Prompt builder data | `prompt_builder/` | Prompt/context assembly fixtures. |

## CONVENTIONS

- Treat fixtures as test contracts. Update expected output only when the
  contract intentionally changes.
- Keep fixture names descriptive enough to identify the scenario without opening
  every file.
- Prefer adding a new fixture for a new edge case over mutating a broad shared
  fixture.
- When updating snapshots, verify the corresponding test explains why the new
  output is correct.

## ANTI-PATTERNS

- Do not regenerate snapshots blindly.
- Do not store secrets or host-specific absolute paths in fixtures.
- Do not collapse multiple behavioral scenarios into one fixture that tests
  cannot diagnose.
