# PROJECT KNOWLEDGE BASE

## OVERVIEW

`priv/repo/migrations/` is the chronological schema evolution log for
Conveyor's Ash/Postgres-backed authority model.

## WHERE TO LOOK

| Task | Location | Notes |
| --- | --- | --- |
| Factory resources | `../../../lib/conveyor/factory/` | Resource definitions migrations must support. |
| Repo config | `../../../lib/conveyor/repo.ex`, `../../../config/*.exs` | Database runtime/test settings. |
| Migration formatter | `.formatter.exs` | Local formatter import/config. |
| Migration tests | `../../../test/conveyor/*schema*_test.exs` | Resource and schema behavior. |

## CONVENTIONS

- Add new migrations with timestamped filenames; do not rewrite applied history
  casually.
- Keep database constraints aligned with explicit state machines and allowed
  enum/status values.
- Preserve append-only and authority-event semantics when changing ledger,
  evidence, effect, or approval tables.
- Use reversible Ecto migration operations where practical; when raw SQL is
  required, keep `up`/`down` behavior explicit.
- Update Ash resources, schema tests, and docs/ADRs together when persistence
  semantics change.

## ANTI-PATTERNS

- Do not drop constraints to make failing writes pass without replacing the
  invariant.
- Do not mutate authority, approval, evidence, or ledger history in-place unless
  a specific migration contract requires it.
- Do not depend on UI/static projection fields as database authority.
